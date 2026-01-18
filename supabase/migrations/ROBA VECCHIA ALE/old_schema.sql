SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';

CREATE OR REPLACE FUNCTION "public"."delete_my_account"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
declare
  v_user_id    uuid := auth.uid();
  v_has_active boolean;
begin
  if v_user_id is null then
    raise exception 'Nessun utente autenticato.';
  end if;

  -- 1) CONTROLLO PRENOTAZIONI ATTIVE
  select exists (
    select 1
    from public.partner_bookings
    where user_id = v_user_id
      and status in ('pending','confirmed')
      and booking_date::date >= current_date
  )
  into v_has_active;

  if v_has_active then
    raise exception
      'Hai ancora prenotazioni attive. Cancella o attendi la conclusione delle prenotazioni prima di eliminare l''account.'
      using errcode = 'P0001';
  end if;

  -- 2) ELIMINA / PULISCI I DATI COLLEGATI ALL'UTENTE
  delete from public.partner_bookings
  where user_id = v_user_id;

  delete from public.user_profiles
  where id = v_user_id;

  -- (se hai altre tabelle legate all’utente, falle qui)

  -- ⚠️ NON cancellare qui da auth.users.
  -- Questo lo farà la Edge Function con service role.
end;
$$;

ALTER FUNCTION "public"."delete_my_account"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."delete_stale_unverified_users"("max_age_minutes" integer) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_count int;
begin
  delete from auth.users
  where coalesce((raw_user_meta_data->>'otp_verified')::boolean, false) = false
    and created_at < now() - (max_age_minutes || ' minutes')::interval;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

ALTER FUNCTION "public"."delete_stale_unverified_users"("max_age_minutes" integer) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."handle_otp_verified_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  old_verified boolean;
  new_verified boolean;
begin
  old_verified := coalesce((old.raw_user_meta_data->>'otp_verified')::boolean, false);
  new_verified := coalesce((new.raw_user_meta_data->>'otp_verified')::boolean, false);

  -- Da non verificato a verificato
  if old_verified = false and new_verified = true then
    insert into public.user_profiles (id)
    values (new.id)
    on conflict (id) do nothing;
  end if;

  return new;
end;
$$;

ALTER FUNCTION "public"."handle_otp_verified_user"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."set_partners_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;

ALTER FUNCTION "public"."set_partners_updated_at"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."set_timestamp_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;

ALTER FUNCTION "public"."set_timestamp_updated_at"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end $$;

ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";

CREATE TABLE IF NOT EXISTS "public"."account_deletion_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."account_deletion_logs" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."partner_bookings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "partner_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'confirmed'::"text" NOT NULL,
    "contact_first_name" "text" NOT NULL,
    "contact_last_name" "text" NOT NULL,
    "contact_phone" "text" NOT NULL,
    "contact_email" "text" NOT NULL,
    "bags_s" integer DEFAULT 0 NOT NULL,
    "bags_m" integer DEFAULT 0 NOT NULL,
    "bags_l" integer DEFAULT 0 NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "booking_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "start_time" time without time zone DEFAULT '00:00:00'::time without time zone NOT NULL,
    "end_time" time without time zone DEFAULT '23:59:00'::time without time zone NOT NULL,
    CONSTRAINT "partner_bookings_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'confirmed'::"text", 'cancelled'::"text", 'completed'::"text"])))
);

ALTER TABLE "public"."partner_bookings" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."partner_photos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "partner_id" "uuid" NOT NULL,
    "url" "text" NOT NULL,
    "is_cover" boolean DEFAULT false NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."partner_photos" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."partner_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "partner_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "message" "text",
    "admin_note" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reviewed_at" timestamp with time zone,
    "reviewed_by" "uuid",
    CONSTRAINT "partner_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);

ALTER TABLE "public"."partner_requests" OWNER TO "postgres";

COMMENT ON TABLE "public"."partner_requests" IS 'Richieste di partnership BagDrop.';

CREATE TABLE IF NOT EXISTS "public"."partners" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "address" "text",
    "lat" double precision,
    "lng" double precision,
    "opening_hours" "jsonb",
    "capacity" integer DEFAULT 0 NOT NULL,
    "price_2h" numeric(10,2),
    "price_per_day" numeric(10,2),
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "reject_reason" "text",
    "description" "text",
    "phone" "text",
    "rules" "text",
    "capacity_s" integer DEFAULT 0 NOT NULL,
    "capacity_m" integer DEFAULT 0 NOT NULL,
    "capacity_l" integer DEFAULT 0 NOT NULL,
    CONSTRAINT "partners_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);

ALTER TABLE "public"."partners" OWNER TO "postgres";

COMMENT ON TABLE "public"."partners" IS 'Attività partner collegate a auth.users (owner_id).';

CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "full_name" "text",
    "avatar_url" "text",
    "kyc_status" "text" DEFAULT 'none'::"text" NOT NULL,
    "role" "text" DEFAULT 'user'::"text" NOT NULL,
    CONSTRAINT "user_profiles_kyc_status_check" CHECK (("kyc_status" = ANY (ARRAY['none'::"text", 'basic'::"text", 'verified'::"text"]))),
    CONSTRAINT "user_profiles_role_check" CHECK (("role" = ANY (ARRAY['user'::"text", 'partner'::"text", 'admin'::"text"])))
);

ALTER TABLE "public"."user_profiles" OWNER TO "postgres";

COMMENT ON TABLE "public"."user_profiles" IS 'Profili utente applicativi; PK = auth.users.id. Ruoli: user/partner/admin.';

ALTER TABLE ONLY "public"."account_deletion_logs"
    ADD CONSTRAINT "account_deletion_logs_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."partner_bookings"
    ADD CONSTRAINT "partner_bookings_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."partner_photos"
    ADD CONSTRAINT "partner_photos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."partner_requests"
    ADD CONSTRAINT "partner_requests_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."partners"
    ADD CONSTRAINT "partners_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_partner_photos_partner_id" ON "public"."partner_photos" USING "btree" ("partner_id");

CREATE INDEX "idx_partner_requests_status" ON "public"."partner_requests" USING "btree" ("status");

CREATE INDEX "idx_partner_requests_user" ON "public"."partner_requests" USING "btree" ("user_id");

CREATE INDEX "idx_partners_is_active" ON "public"."partners" USING "btree" ("is_active");

CREATE INDEX "idx_partners_owner_id" ON "public"."partners" USING "btree" ("owner_id");

CREATE INDEX "idx_partners_status" ON "public"."partners" USING "btree" ("status");

CREATE UNIQUE INDEX "partners_owner_id_key" ON "public"."partners" USING "btree" ("owner_id");

CREATE OR REPLACE TRIGGER "on_auth_user_otp_verified"
AFTER UPDATE ON "auth"."users"
FOR EACH ROW
WHEN (old.raw_user_meta_data IS DISTINCT FROM new.raw_user_meta_data)
EXECUTE FUNCTION "public"."handle_otp_verified_user"();


CREATE OR REPLACE TRIGGER "set_partners_updated_at" BEFORE UPDATE ON "public"."partners" FOR EACH ROW EXECUTE FUNCTION "public"."set_partners_updated_at"();

CREATE OR REPLACE TRIGGER "trg_partner_bookings_updated_at" BEFORE UPDATE ON "public"."partner_bookings" FOR EACH ROW EXECUTE FUNCTION "public"."set_timestamp_updated_at"();

CREATE OR REPLACE TRIGGER "trg_partners_set_updated_at" BEFORE UPDATE ON "public"."partners" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

ALTER TABLE ONLY "public"."partner_bookings"
    ADD CONSTRAINT "partner_bookings_partner_id_fkey" FOREIGN KEY ("partner_id") REFERENCES "public"."partners"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."partner_bookings"
    ADD CONSTRAINT "partner_bookings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."partner_photos"
    ADD CONSTRAINT "partner_photos_partner_id_fkey" FOREIGN KEY ("partner_id") REFERENCES "public"."partners"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."partner_requests"
    ADD CONSTRAINT "partner_requests_partner_id_fkey" FOREIGN KEY ("partner_id") REFERENCES "public"."partners"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."partner_requests"
    ADD CONSTRAINT "partner_requests_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "public"."partner_requests"
    ADD CONSTRAINT "partner_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."partners"
    ADD CONSTRAINT "partners_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;

CREATE POLICY "admin_manage_all_partners" ON "public"."partners" USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles" "up"
  WHERE (("up"."id" = "auth"."uid"()) AND ("up"."role" = 'admin'::"text"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."user_profiles" "up"
  WHERE (("up"."id" = "auth"."uid"()) AND ("up"."role" = 'admin'::"text")))));

CREATE POLICY "admin_manage_requests" ON "public"."partner_requests" USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles" "up"
  WHERE (("up"."id" = "auth"."uid"()) AND ("up"."role" = 'admin'::"text"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."user_profiles" "up"
  WHERE (("up"."id" = "auth"."uid"()) AND ("up"."role" = 'admin'::"text")))));

CREATE POLICY "insert self" ON "public"."user_profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));

CREATE POLICY "own_requests" ON "public"."partner_requests" FOR SELECT USING (("auth"."uid"() = "user_id"));

CREATE POLICY "own_requests_insert" ON "public"."partner_requests" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));

CREATE POLICY "owner_manage_partners" ON "public"."partners" USING (("auth"."uid"() = "owner_id")) WITH CHECK (("auth"."uid"() = "owner_id"));

ALTER TABLE "public"."partner_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."partners" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "partners_insert_self" ON "public"."partners" FOR INSERT WITH CHECK (("auth"."uid"() = "owner_id"));

CREATE POLICY "partners_select_own" ON "public"."partners" FOR SELECT USING (("auth"."uid"() = "owner_id"));

CREATE POLICY "partners_update_own" ON "public"."partners" FOR UPDATE USING (("auth"."uid"() = "owner_id")) WITH CHECK (("auth"."uid"() = "owner_id"));

CREATE POLICY "public_read_active_partners" ON "public"."partners" FOR SELECT USING ((("is_active" = true) AND ("status" = 'approved'::"text")));

CREATE POLICY "read own profile" ON "public"."user_profiles" FOR SELECT USING (("auth"."uid"() = "id"));

CREATE POLICY "update own profile" ON "public"."user_profiles" FOR UPDATE USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));

ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

GRANT ALL ON FUNCTION "public"."delete_my_account"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_my_account"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_my_account"() TO "service_role";

GRANT ALL ON FUNCTION "public"."delete_stale_unverified_users"("max_age_minutes" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."delete_stale_unverified_users"("max_age_minutes" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_stale_unverified_users"("max_age_minutes" integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."handle_otp_verified_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_otp_verified_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_otp_verified_user"() TO "service_role";

GRANT ALL ON FUNCTION "public"."set_partners_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_partners_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_partners_updated_at"() TO "service_role";

GRANT ALL ON FUNCTION "public"."set_timestamp_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_timestamp_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_timestamp_updated_at"() TO "service_role";

GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";

GRANT ALL ON TABLE "public"."account_deletion_logs" TO "anon";
GRANT ALL ON TABLE "public"."account_deletion_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."account_deletion_logs" TO "service_role";

GRANT ALL ON TABLE "public"."partner_bookings" TO "anon";
GRANT ALL ON TABLE "public"."partner_bookings" TO "authenticated";
GRANT ALL ON TABLE "public"."partner_bookings" TO "service_role";

GRANT ALL ON TABLE "public"."partner_photos" TO "anon";
GRANT ALL ON TABLE "public"."partner_photos" TO "authenticated";
GRANT ALL ON TABLE "public"."partner_photos" TO "service_role";

GRANT ALL ON TABLE "public"."partner_requests" TO "anon";
GRANT ALL ON TABLE "public"."partner_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."partner_requests" TO "service_role";

GRANT ALL ON TABLE "public"."partners" TO "anon";
GRANT ALL ON TABLE "public"."partners" TO "authenticated";
GRANT ALL ON TABLE "public"."partners" TO "service_role";

GRANT ALL ON TABLE "public"."user_profiles" TO "anon";
GRANT ALL ON TABLE "public"."user_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";
