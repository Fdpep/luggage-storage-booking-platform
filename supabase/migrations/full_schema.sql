


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


CREATE SCHEMA IF NOT EXISTS "auth";


ALTER SCHEMA "auth" OWNER TO "supabase_admin";


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE SCHEMA IF NOT EXISTS "storage";


ALTER SCHEMA "storage" OWNER TO "supabase_admin";


CREATE TYPE "auth"."aal_level" AS ENUM (
    'aal1',
    'aal2',
    'aal3'
);


ALTER TYPE "auth"."aal_level" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."code_challenge_method" AS ENUM (
    's256',
    'plain'
);


ALTER TYPE "auth"."code_challenge_method" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."factor_status" AS ENUM (
    'unverified',
    'verified'
);


ALTER TYPE "auth"."factor_status" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."factor_type" AS ENUM (
    'totp',
    'webauthn',
    'phone'
);


ALTER TYPE "auth"."factor_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_authorization_status" AS ENUM (
    'pending',
    'approved',
    'denied',
    'expired'
);


ALTER TYPE "auth"."oauth_authorization_status" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_client_type" AS ENUM (
    'public',
    'confidential'
);


ALTER TYPE "auth"."oauth_client_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_registration_type" AS ENUM (
    'dynamic',
    'manual'
);


ALTER TYPE "auth"."oauth_registration_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_response_type" AS ENUM (
    'code'
);


ALTER TYPE "auth"."oauth_response_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."one_time_token_type" AS ENUM (
    'confirmation_token',
    'reauthentication_token',
    'recovery_token',
    'email_change_token_new',
    'email_change_token_current',
    'phone_change_token'
);


ALTER TYPE "auth"."one_time_token_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "public"."partner_request_status" AS ENUM (
    'draft',
    'submitted',
    'awaiting_payment',
    'paid',
    'rejected'
);


ALTER TYPE "public"."partner_request_status" OWNER TO "postgres";


CREATE TYPE "storage"."buckettype" AS ENUM (
    'STANDARD',
    'ANALYTICS',
    'VECTOR'
);


ALTER TYPE "storage"."buckettype" OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "auth"."email"() RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;


ALTER FUNCTION "auth"."email"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."email"() IS 'Deprecated. Use auth.jwt() -> ''email'' instead.';



CREATE OR REPLACE FUNCTION "auth"."jwt"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    AS $$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$$;


ALTER FUNCTION "auth"."jwt"() OWNER TO "supabase_auth_admin";


CREATE OR REPLACE FUNCTION "auth"."role"() RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;


ALTER FUNCTION "auth"."role"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."role"() IS 'Deprecated. Use auth.jwt() -> ''role'' instead.';



CREATE OR REPLACE FUNCTION "auth"."uid"() RETURNS "uuid"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;


ALTER FUNCTION "auth"."uid"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."uid"() IS 'Deprecated. Use auth.jwt() -> ''sub'' instead.';



CREATE OR REPLACE FUNCTION "public"."admin_approve_partner_docs"("p_request_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_admin_id uuid := auth.uid();
  v_role text;
  v_partner_id uuid;
  v_user_id uuid;
  v_status public.partner_request_status;
  v_contract text;
begin
  if v_admin_id is null then
    raise exception 'Not authenticated';
  end if;

  select up.role into v_role
  from public.user_profiles up
  where up.id = v_admin_id;

  if v_role is distinct from 'admin' then
    raise exception 'Not authorized';
  end if;

  select pr.partner_id, pr.user_id, pr.status, pr.contract_signed_url
    into v_partner_id, v_user_id, v_status, v_contract
  from public.partner_requests pr
  where pr.id = p_request_id;

  if v_partner_id is null then
    raise exception 'Request not found';
  end if;

  if v_status is distinct from 'submitted'::public.partner_request_status then
    raise exception 'Invalid status. Expected submitted, got %', v_status;
  end if;

  if v_contract is null or length(trim(v_contract)) = 0 then
    raise exception 'Missing contract_signed_url';
  end if;

  update public.partners
  set status = 'approved',
      is_active = false,
      reject_reason = null,
      updated_at = now()
  where id = v_partner_id;

  update public.partner_requests
  set status = 'awaiting_payment',
      reviewed_at = now(),
      reviewed_by = v_admin_id,
      docs_approved_at = now(),
      payment_required = true,
      updated_at = now()
  where id = p_request_id;

  update public.user_profiles
  set role = 'partner_candidate'
  where id = v_user_id;
end;
$$;


ALTER FUNCTION "public"."admin_approve_partner_docs"("p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_reject_partner_request"("p_request_id" "uuid", "p_reason" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_admin_id uuid := auth.uid();
  v_role text;
  v_partner_id uuid;
  v_user_id uuid;
  v_status public.partner_request_status;
begin
  if v_admin_id is null then
    raise exception 'Not authenticated';
  end if;

  select up.role into v_role
  from public.user_profiles up
  where up.id = v_admin_id;

  if v_role is distinct from 'admin' then
    raise exception 'Not authorized';
  end if;

  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'Missing reject reason';
  end if;

  select pr.partner_id, pr.user_id, pr.status
    into v_partner_id, v_user_id, v_status
  from public.partner_requests pr
  where pr.id = p_request_id;

  if v_partner_id is null then
    raise exception 'Request not found';
  end if;

  -- ✅ BLOCCO: si può rifiutare SOLO se è "submitted"
  if v_status is distinct from 'submitted'::public.partner_request_status then
    raise exception 'Invalid status. Can reject only submitted, got %', v_status;
  end if;

  update public.partners
  set
    status = 'rejected',
    is_active = false,
    reject_reason = p_reason,
    updated_at = now()
  where id = v_partner_id;

  update public.partner_requests
  set
    status = 'rejected',
    reject_reason = p_reason,
    admin_note = p_reason,
    reviewed_at = now(),
    reviewed_by = v_admin_id,
    updated_at = now(),
    payment_required = false
  where id = p_request_id;

  -- (opzionale ma consigliato) garantisci che l’utente resti candidate
  update public.user_profiles
  set role = 'partner_candidate'
  where id = v_user_id
    and role <> 'admin';
end;
$$;


ALTER FUNCTION "public"."admin_reject_partner_request"("p_request_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."attach_contract_to_partner_request"("p_request_id" "uuid", "p_contract_path" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.partner_requests
  set
    contract_signed_url = p_contract_path,
    contract_signed_at = now()
  where id = p_request_id
    and user_id = auth.uid()
    and status = 'draft'::public.partner_request_status;
end;
$$;


ALTER FUNCTION "public"."attach_contract_to_partner_request"("p_request_id" "uuid", "p_contract_path" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bd_calc_covered_until"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_duration_key" "text", "p_extra_days" integer DEFAULT 0) RETURNS timestamp with time zone
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
declare
  d0 date;
  target_date date;
  extra int := greatest(0, coalesce(p_extra_days,0));
  drop_local timestamp;
begin
  drop_local := (p_dropoff at time zone 'Europe/Rome');
  d0 := drop_local::date;

  if p_duration_key = 'threeHours' then
    return (p_dropoff + interval '3 hours');
  end if;

  if p_duration_key = 'oneDay' then
    -- chiusura del giorno di consegna (se chiuso: prossimo aperto)
    return public.bd_next_open_close_at(p_partner_id, d0);
  end if;

  if p_duration_key = 'oneAndHalfDay' then
    target_date := d0 + 1;
    return ((target_date::timestamp + time '13:00:00') at time zone 'Europe/Rome');
  end if;

  if p_duration_key = 'twoDays' then
    target_date := d0 + 1;
    return public.bd_next_open_close_at(p_partner_id, target_date);
  end if;

  -- threeDays (+ extra): target base = d0+2+extra
  target_date := d0 + 2 + extra;
  return public.bd_next_open_close_at(p_partner_id, target_date);
end;
$$;


ALTER FUNCTION "public"."bd_calc_covered_until"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_duration_key" "text", "p_extra_days" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bd_day_close_time"("p_partner_id" "uuid", "p_local_date" "date") RETURNS time without time zone
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
declare
  oh jsonb;
  v_key text;
  intervals jsonb;
  it jsonb;
  close_txt text;
  best_close time := null;

  closed_dates jsonb;
  forced_open_dates jsonb;
  is_closed boolean := false;
begin
  select opening_hours::jsonb into oh
  from public.partners
  where id = p_partner_id;

  -- fallback robusto se non configurato
  if oh is null or (oh->>'type') is distinct from 'weekly_v1' then
    return time '23:59:00';
  end if;

  -- exceptions
  if (oh ? 'exceptions') then
    closed_dates := (oh->'exceptions'->'closed_dates');
    forced_open_dates := (oh->'exceptions'->'forced_open_dates');

    if closed_dates is not null then
      is_closed := exists (
        select 1
        from jsonb_array_elements_text(closed_dates) d
        where d = p_local_date::text
      );
    end if;

    if is_closed and forced_open_dates is not null then
      -- forced_open prevale sul closed
      is_closed := not exists (
        select 1
        from jsonb_array_elements_text(forced_open_dates) d
        where d = p_local_date::text
      );
    end if;
  end if;

  -- Se “chiuso” per eccezione: per ora fallback (non blocchiamo il calcolo)
  if is_closed then
    return time '23:59:00';
  end if;

  v_key := public.bd_weekday_key(p_local_date);

  intervals := oh->v_key;
  if intervals is null or jsonb_typeof(intervals) <> 'array' then
    return time '23:59:00';
  end if;

  -- prendi la close più tardiva tra le fasce del giorno
  for it in select * from jsonb_array_elements(intervals)
  loop
    close_txt := it->>'close';
    if close_txt is null or close_txt = '' then
      continue;
    end if;

    -- cast robusto: accetta "20:00" o "20:00:00"
    if best_close is null then
      best_close := close_txt::time;
    else
      if close_txt::time > best_close then
        best_close := close_txt::time;
      end if;
    end if;
  end loop;

  return coalesce(best_close, time '23:59:00');
end;
$$;


ALTER FUNCTION "public"."bd_day_close_time"("p_partner_id" "uuid", "p_local_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bd_day_close_time_nullable"("p_partner_id" "uuid", "p_local_date" "date") RETURNS time without time zone
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
declare
  oh jsonb;
  v_key text;
  intervals jsonb;
  it jsonb;
  close_txt text;
  best_close time := null;
begin
  if not public.bd_is_day_open(p_partner_id, p_local_date) then
    return null;
  end if;

  select opening_hours::jsonb into oh
  from public.partners
  where id = p_partner_id;

  if oh is null or (oh->>'type') is distinct from 'weekly_v1' then
    return time '23:59:00';
  end if;

  v_key := public.bd_weekday_key(p_local_date);
  intervals := oh->v_key;

  if intervals is null or jsonb_typeof(intervals) <> 'array' then
    return null;
  end if;

  for it in select * from jsonb_array_elements(intervals)
  loop
    close_txt := it->>'close';
    if close_txt is null or close_txt = '' then
      continue;
    end if;

    if best_close is null or close_txt::time > best_close then
      best_close := close_txt::time;
    end if;
  end loop;

  return best_close;
end;
$$;


ALTER FUNCTION "public"."bd_day_close_time_nullable"("p_partner_id" "uuid", "p_local_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bd_infer_duration"("p_start" timestamp with time zone, "p_end" timestamp with time zone) RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
declare
  s_local timestamp;
  e_local timestamp;
  hours numeric;
  next_day date;
  cutoff timestamp;
begin
  if p_end is null or p_start is null or p_end <= p_start then
    return 'threeHours';
  end if;

  s_local := (p_start at time zone 'Europe/Rome');
  e_local := (p_end   at time zone 'Europe/Rome');

  hours := extract(epoch from (e_local - s_local)) / 3600.0;

  if hours <= 3.0 then
    return 'threeHours';
  end if;

  if (date(s_local) = date(e_local)) then
    return 'oneDay';
  end if;

  next_day := date(s_local) + 1;

  if date(e_local) = next_day then
    cutoff := (date_trunc('day', e_local) + time '13:00');
    if e_local <= cutoff then
      return 'oneAndHalfDay';
    end if;
  end if;

  if hours <= 48.0 then
    return 'twoDays';
  end if;

  return 'threeDays';
end;
$$;


ALTER FUNCTION "public"."bd_infer_duration"("p_start" timestamp with time zone, "p_end" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bd_infer_window_v2"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_covered_until" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
declare
  d0 date;
  drop_local timestamp;
  cov_local timestamp;

  close_d0 time;
  t_one_day timestamptz;
  t_one_half timestamptz;
  t_two_days timestamptz;
  t_three_days timestamptz;

  days_total int;
  extra int := 0;
begin
  if p_dropoff is null or p_covered_until is null or p_covered_until <= p_dropoff then
    return jsonb_build_object('duration_key','threeHours','extra_days',0);
  end if;

  drop_local := (p_dropoff at time zone 'Europe/Rome');
  cov_local  := (p_covered_until at time zone 'Europe/Rome');
  d0 := drop_local::date;

  -- threeHours: <= dropoff+3h
  if p_covered_until <= (p_dropoff + interval '3 hours') then
    return jsonb_build_object('duration_key','threeHours','extra_days',0);
  end if;

  -- confini principali
  t_one_day   := public.bd_calc_covered_until(p_partner_id, p_dropoff, 'oneDay', 0);
  t_one_half  := public.bd_calc_covered_until(p_partner_id, p_dropoff, 'oneAndHalfDay', 0);
  t_two_days  := public.bd_calc_covered_until(p_partner_id, p_dropoff, 'twoDays', 0);
  t_three_days:= public.bd_calc_covered_until(p_partner_id, p_dropoff, 'threeDays', 0);

  if p_covered_until = t_one_day then
    return jsonb_build_object('duration_key','oneDay','extra_days',0);
  end if;

  if p_covered_until = t_one_half then
    return jsonb_build_object('duration_key','oneAndHalfDay','extra_days',0);
  end if;

  if p_covered_until = t_two_days then
    return jsonb_build_object('duration_key','twoDays','extra_days',0);
  end if;

  -- threeDays o oltre: se coincide con chiusura di (d0+2+extra)
  -- calcolo extra_days confrontando date locali:
  -- days_total = (covered_date - d0) + 1
  -- threeDays corrisponde a days_total=3 -> extra=0
  days_total := (cov_local::date - d0) + 1;
  if days_total >= 3 then
    extra := greatest(0, days_total - 3);
    return jsonb_build_object('duration_key','threeDays','extra_days',extra);
  end if;

  -- fallback
  return jsonb_build_object('duration_key','oneDay','extra_days',0);
end;
$$;


ALTER FUNCTION "public"."bd_infer_window_v2"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_covered_until" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bd_is_day_open"("p_partner_id" "uuid", "p_local_date" "date") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
declare
  oh jsonb;
  v_key text;
  intervals jsonb;

  closed_dates jsonb;
  forced_open_dates jsonb;
  is_closed boolean := false;
begin
  select opening_hours::jsonb into oh
  from public.partners
  where id = p_partner_id;

  if oh is null or (oh->>'type') is distinct from 'weekly_v1' then
    -- se non ho orari, assumo “aperto” per non rompere il sistema
    return true;
  end if;

  if (oh ? 'exceptions') then
    closed_dates := (oh->'exceptions'->'closed_dates');
    forced_open_dates := (oh->'exceptions'->'forced_open_dates');

    if closed_dates is not null then
      is_closed := exists (
        select 1
        from jsonb_array_elements_text(closed_dates) d
        where d = p_local_date::text
      );
    end if;

    if is_closed and forced_open_dates is not null then
      -- forced_open prevale
      is_closed := not exists (
        select 1
        from jsonb_array_elements_text(forced_open_dates) d
        where d = p_local_date::text
      );
    end if;
  end if;

  if is_closed then
    return false;
  end if;

  v_key := public.bd_weekday_key(p_local_date);
  intervals := oh->v_key;

  -- “aperto” se esiste almeno 1 fascia con close valida
  return (intervals is not null)
     and (jsonb_typeof(intervals) = 'array')
     and exists (
        select 1
        from jsonb_array_elements(intervals) it
        where coalesce(it->>'open','') <> ''
          and coalesce(it->>'close','') <> ''
     );
end;
$$;


ALTER FUNCTION "public"."bd_is_day_open"("p_partner_id" "uuid", "p_local_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bd_next_cutoff_at"("p_partner_id" "uuid", "p_from" timestamp with time zone DEFAULT "now"()) RETURNS timestamp with time zone
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
declare
  v_cutoff time;
  v_local timestamp;
  v_candidate_local timestamp;
begin
  select daily_cutoff_time into v_cutoff
  from public.partners
  where id = p_partner_id;

  if v_cutoff is null then
    -- fallback: come “fine giornata”
    v_cutoff := time '23:59:00';
  end if;

  v_local := (p_from at time zone 'Europe/Rome');
  v_candidate_local := date_trunc('day', v_local) + v_cutoff;

  if v_candidate_local <= v_local then
    v_candidate_local := v_candidate_local + interval '1 day';
  end if;

  return (v_candidate_local at time zone 'Europe/Rome');
end;
$$;


ALTER FUNCTION "public"."bd_next_cutoff_at"("p_partner_id" "uuid", "p_from" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bd_next_open_close_at"("p_partner_id" "uuid", "p_from_local_date" "date") RETURNS timestamp with time zone
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
declare
  d date := p_from_local_date;
  i int;
  close_t time;
begin
  for i in 0..14 loop
    close_t := public.bd_day_close_time_nullable(p_partner_id, d);
    if close_t is not null then
      return ((d::timestamp + close_t) at time zone 'Europe/Rome');
    end if;
    d := d + 1;
  end loop;

  -- fallback estremo: 23:59 del giorno p_from_local_date
  return ((p_from_local_date::timestamp + time '23:59:00') at time zone 'Europe/Rome');
end;
$$;


ALTER FUNCTION "public"."bd_next_open_close_at"("p_partner_id" "uuid", "p_from_local_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bd_next_window"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_current_covered_until" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
declare
  cur jsonb;
  k text;
  extra int;
  next_k text;
  next_extra int := 0;
  next_cov timestamptz;
begin
  cur := public.bd_infer_window_v2(p_partner_id, p_dropoff, p_current_covered_until);
  k := cur->>'duration_key';
  extra := coalesce((cur->>'extra_days')::int, 0);

  if k = 'threeHours' then
    next_k := 'oneDay';
    next_extra := 0;
  elsif k = 'oneDay' then
    next_k := 'oneAndHalfDay';
    next_extra := 0;
  elsif k = 'oneAndHalfDay' then
    next_k := 'twoDays';
    next_extra := 0;
  elsif k = 'twoDays' then
    next_k := 'threeDays';
    next_extra := 0;
  else
    -- threeDays con extra: aggiungi un giorno extra
    next_k := 'threeDays';
    next_extra := extra + 1;
  end if;

  next_cov := public.bd_calc_covered_until(p_partner_id, p_dropoff, next_k, next_extra);

  return jsonb_build_object(
    'duration_key', next_k,
    'extra_days', next_extra,
    'covered_until', next_cov
  );
end;
$$;


ALTER FUNCTION "public"."bd_next_window"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_current_covered_until" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bd_pricing_total_cents"("p_duration" "text", "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer) RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
declare
  s int;
  m int;
  l int;
begin
  case p_duration
    when 'threeHours' then
      s := 200;  m := 300;  l := 400;
    when 'oneDay' then
      s := 400;  m := 500;  l := 600;
    when 'oneAndHalfDay' then
      s := 600;  m := 750;  l := 900;
    when 'twoDays' then
      s := 750;  m := 900;  l := 1100;
    when 'threeDays' then
      s := 900;  m := 1100; l := 1300;
    else
      -- fallback prudente
      s := 200; m := 300; l := 400;
  end case;

  return (coalesce(p_bags_s,0) * s)
       + (coalesce(p_bags_m,0) * m)
       + (coalesce(p_bags_l,0) * l);
end;
$$;


ALTER FUNCTION "public"."bd_pricing_total_cents"("p_duration" "text", "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bd_pricing_total_cents_extended"("p_duration" "text", "p_extra_days" integer, "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer) RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
declare
  base_cents int;
  extra int := greatest(0, coalesce(p_extra_days,0)) * 200; -- 2€ = 200 cents
begin
  base_cents := public.bd_pricing_total_cents(p_duration, p_bags_s, p_bags_m, p_bags_l);
  return base_cents + extra;
end;
$$;


ALTER FUNCTION "public"."bd_pricing_total_cents_extended"("p_duration" "text", "p_extra_days" integer, "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bd_weekday_key"("p_date" "date") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
declare
  dow int := extract(dow from p_date); -- 0=sun ... 6=sat
begin
  return case dow
    when 1 then 'mon'
    when 2 then 'tue'
    when 3 then 'wed'
    when 4 then 'thu'
    when 5 then 'fri'
    when 6 then 'sat'
    else 'sun'
  end;
end;
$$;


ALTER FUNCTION "public"."bd_weekday_key"("p_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bd_window_for_moment"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_moment" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
declare
  t3h timestamptz;
  t1d timestamptz;
  t1h timestamptz;
  t2d timestamptz;
  t3d0 timestamptz;

  extra int := 0;
  t3d timestamptz;
begin
  if p_dropoff is null or p_moment is null then
    return jsonb_build_object('duration_key','threeHours','extra_days',0,'covered_until',null);
  end if;

  -- 3 ore
  t3h := p_dropoff + interval '3 hours';
  if p_moment <= t3h then
    return jsonb_build_object('duration_key','threeHours','extra_days',0,'covered_until',t3h);
  end if;

  -- 1 giorno (fino a chiusura / prossimo aperto)
  t1d := public.bd_calc_covered_until(p_partner_id, p_dropoff, 'oneDay', 0);
  if p_moment <= t1d then
    return jsonb_build_object('duration_key','oneDay','extra_days',0,'covered_until',t1d);
  end if;

  -- 1.5 giorni (fino alle 13:00 del giorno dopo)
  t1h := public.bd_calc_covered_until(p_partner_id, p_dropoff, 'oneAndHalfDay', 0);
  if p_moment <= t1h then
    return jsonb_build_object('duration_key','oneAndHalfDay','extra_days',0,'covered_until',t1h);
  end if;

  -- 2 giorni (fino a chiusura / prossimo aperto)
  t2d := public.bd_calc_covered_until(p_partner_id, p_dropoff, 'twoDays', 0);
  if p_moment <= t2d then
    return jsonb_build_object('duration_key','twoDays','extra_days',0,'covered_until',t2d);
  end if;

  -- 3 giorni (fisso fino a chiusura / prossimo aperto)
  t3d0 := public.bd_calc_covered_until(p_partner_id, p_dropoff, 'threeDays', 0);
  if p_moment <= t3d0 then
    return jsonb_build_object('duration_key','threeDays','extra_days',0,'covered_until',t3d0);
  end if;

  -- oltre 3 giorni: extra days (flat +2€/day nel tuo modello attuale)
  for extra in 1..60 loop
    t3d := public.bd_calc_covered_until(p_partner_id, p_dropoff, 'threeDays', extra);
    if p_moment <= t3d then
      return jsonb_build_object('duration_key','threeDays','extra_days',extra,'covered_until',t3d);
    end if;
  end loop;

  -- fallback estremo
  return jsonb_build_object('duration_key','threeDays','extra_days',60,'covered_until',t3d);
end;
$$;


ALTER FUNCTION "public"."bd_window_for_moment"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_moment" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_my_booking"("p_booking_id" "uuid", "p_reason" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
declare
  v_uid uuid := auth.uid();
  b record;

  v_dropoff timestamptz;
  v_now timestamptz := now();

  v_reason text;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode='P0001';
  end if;

  -- lock prenotazione
  select *
  into b
  from public.partner_bookings
  where id = p_booking_id
  for update;

  if b.id is null then
    raise exception 'Prenotazione non trovata.' using errcode='P0001';
  end if;

  if b.user_id <> v_uid then
    raise exception 'Non autorizzato.' using errcode='P0001';
  end if;

  if b.status not in ('pending','confirmed') then
    raise exception 'Prenotazione non annullabile (stato=%).', b.status using errcode='P0001';
  end if;

  if b.dropoff_effective_at is not null then
    raise exception 'Non puoi annullare: check-in già effettuato.' using errcode='P0001';
  end if;

  -- dropoff pianificato: preferisci dropoff_planned_at, fallback booking_date+start_time
  v_dropoff :=
    coalesce(
      b.dropoff_planned_at,
      case
        when b.booking_date is not null and b.start_time is not null
          then ((b.booking_date::text || ' ' || b.start_time::text)::timestamp at time zone 'Europe/Rome')
        else null
      end
    );

  if v_dropoff is null then
    raise exception 'Impossibile determinare l’orario di consegna (dropoff).' using errcode='P0001';
  end if;

  if v_now >= v_dropoff then
    raise exception 'Non puoi annullare: la prenotazione è già iniziata.' using errcode='P0001';
  end if;

  v_reason := nullif(trim(coalesce(p_reason,'')), '');

  update public.partner_bookings
  set status = 'cancelled_by_user',
      cancelled_at = coalesce(cancelled_at, v_now),
      cancel_reason = coalesce(v_reason, cancel_reason),
      updated_at = now()
  where id = p_booking_id;

  return jsonb_build_object(
    'ok', true,
    'message', 'Prenotazione annullata.',
    -- placeholder utile per il futuro: oggi può essere 0
    'refund_due_cents', greatest(coalesce(b.total_paid_cents,0),0),
    'payments_placeholder', true
  );
end;
$$;


ALTER FUNCTION "public"."cancel_my_booking"("p_booking_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."confirm_partner_payment"("p_request_id" "uuid", "p_payment_reference" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_partner_id uuid;
  v_status public.partner_request_status;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select pr.partner_id, pr.status
    into v_partner_id, v_status
  from public.partner_requests pr
  where pr.id = p_request_id
    and pr.user_id = v_uid;

  if v_partner_id is null then
    raise exception 'Request not found or not yours';
  end if;

  if v_status is distinct from 'awaiting_payment'::public.partner_request_status then
    raise exception 'Invalid status. Expected awaiting_payment, got %', v_status;
  end if;

  update public.partner_requests
  set status = 'paid',
      paid_at = now(),
      payment_reference = p_payment_reference,
      payment_required = false,
      updated_at = now()
  where id = p_request_id;

  update public.user_profiles
  set role = 'partner'
  where id = v_uid;

  update public.partners
  set is_active = true,
      status = 'approved',
      updated_at = now()
  where id = v_partner_id;
end;
$$;


ALTER FUNCTION "public"."confirm_partner_payment"("p_request_id" "uuid", "p_payment_reference" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_partner_booking_v2"("p_partner_id" "uuid", "p_contact_first_name" "text", "p_contact_last_name" "text", "p_contact_phone" "text", "p_contact_email" "text", "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer, "p_dropoff_planned_at" timestamp with time zone, "p_pickup_planned_at" timestamp with time zone, "p_notes" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
DECLARE
  v_uid uuid := auth.uid();

  v_base_capacity_u int;
  v_extra_s int;
  v_extra_m int;
  v_extra_l int;

  v_used_base_u int;
  v_used_extra_s int;
  v_used_extra_m int;
  v_used_extra_l int;

  v_base_remaining_u int;
  v_extra_remaining_s int;
  v_extra_remaining_m int;
  v_extra_remaining_l int;

  v_need_u int;
  v_excess_u int;

  -- allocation da extra
  xS int := 0;
  xM int := 0;
  xL int := 0;

  v_best_xS int := 0;
  v_best_xM int := 0;
  v_best_xL int := 0;
  v_found boolean := false;
  v_score int;

  v_booking_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nessun utente autenticato.' USING errcode='P0001';
  END IF;

  IF p_dropoff_planned_at IS NULL
     OR p_pickup_planned_at IS NULL
     OR p_dropoff_planned_at >= p_pickup_planned_at THEN
    RAISE EXCEPTION 'Intervallo non valido.' USING errcode='P0001';
  END IF;

  IF COALESCE(p_bags_s,0) < 0
     OR COALESCE(p_bags_m,0) < 0
     OR COALESCE(p_bags_l,0) < 0
     OR (COALESCE(p_bags_s,0)+COALESCE(p_bags_m,0)+COALESCE(p_bags_l,0)) = 0 THEN
    RAISE EXCEPTION 'Bagagli non validi.' USING errcode='P0001';
  END IF;

  -- lock partner
  SELECT base_capacity_u, extra_capacity_s, extra_capacity_m, extra_capacity_l
    INTO v_base_capacity_u, v_extra_s, v_extra_m, v_extra_l
  FROM public.partners
  WHERE id = p_partner_id
    AND is_active = true
    AND accepting_bookings = true
    AND status = 'approved'
  FOR UPDATE;

  IF v_base_capacity_u IS NULL THEN
    RAISE EXCEPTION 'Partner non prenotabile.' USING errcode='P0001';
  END IF;

  -- lock bookings overlapping (anti race)
  PERFORM 1
  FROM public.partner_bookings pb
  WHERE pb.partner_id = p_partner_id
    AND pb.status IN ('pending','confirmed','in_store')
    AND pb.dropoff_planned_at IS NOT NULL
    AND pb.pickup_planned_at IS NOT NULL
    AND tstzrange(pb.dropoff_planned_at, pb.pickup_planned_at, '[)') &&
        tstzrange(p_dropoff_planned_at, p_pickup_planned_at, '[)')
  FOR UPDATE;

  -- used in interval
  SELECT
    COALESCE(SUM(base_used_u), 0),
    COALESCE(SUM(extra_used_s), 0),
    COALESCE(SUM(extra_used_m), 0),
    COALESCE(SUM(extra_used_l), 0)
  INTO v_used_base_u, v_used_extra_s, v_used_extra_m, v_used_extra_l
  FROM public.partner_bookings pb
  WHERE pb.partner_id = p_partner_id
    AND pb.status IN ('pending','confirmed','in_store')
    AND pb.dropoff_planned_at IS NOT NULL
    AND pb.pickup_planned_at IS NOT NULL
    AND tstzrange(pb.dropoff_planned_at, pb.pickup_planned_at, '[)') &&
        tstzrange(p_dropoff_planned_at, p_pickup_planned_at, '[)');

  v_base_remaining_u := GREATEST(0, v_base_capacity_u - v_used_base_u);
  v_extra_remaining_s := GREATEST(0, v_extra_s - v_used_extra_s);
  v_extra_remaining_m := GREATEST(0, v_extra_m - v_used_extra_m);
  v_extra_remaining_l := GREATEST(0, v_extra_l - v_used_extra_l);

  v_need_u := COALESCE(p_bags_s,0)*1 + COALESCE(p_bags_m,0)*2 + COALESCE(p_bags_l,0)*4;

  IF v_need_u <= v_base_remaining_u THEN
    -- tutto base
    v_best_xS := 0;
    v_best_xM := 0;
    v_best_xL := 0;
    v_found := true;
  ELSE
    v_excess_u := v_need_u - v_base_remaining_u;

    -- cerco combinazione extra che copra excess_u senza superare bags richiesti e extra disponibili.
    -- Loop su L e M, calcolo S necessario.
    FOR xL IN 0..LEAST(COALESCE(p_bags_l,0), v_extra_remaining_l) LOOP
      FOR xM IN 0..LEAST(COALESCE(p_bags_m,0), v_extra_remaining_m) LOOP
        xS := GREATEST(0, v_excess_u - (4*xL) - (2*xM)); -- unità rimanenti da coprire con S

        IF xS <= LEAST(COALESCE(p_bags_s,0), v_extra_remaining_s) THEN
          -- score: minimizza unità da extra, poi numero di bag extra (preferisci usare base)
          v_score := (xS*1 + xM*2 + xL*4) * 1000 + (xS + xM + xL);

          IF v_found = false
             OR v_score < ((v_best_xS*1 + v_best_xM*2 + v_best_xL*4) * 1000 + (v_best_xS+v_best_xM+v_best_xL)) THEN
            v_best_xS := xS;
            v_best_xM := xM;
            v_best_xL := xL;
            v_found := true;
          END IF;
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  IF v_found = false THEN
    RAISE EXCEPTION 'Capacità insufficiente per l''intervallo selezionato.' USING errcode='P0001';
  END IF;

  -- inserisco booking con allocation
  INSERT INTO public.partner_bookings (
    partner_id, user_id, status,
    contact_first_name, contact_last_name, contact_phone, contact_email,
    bags_s, bags_m, bags_l, notes,
    dropoff_planned_at, pickup_planned_at,
    base_used_u, extra_used_s, extra_used_m, extra_used_l
  )
  VALUES (
    p_partner_id, v_uid, 'confirmed',
    p_contact_first_name, p_contact_last_name, p_contact_phone, p_contact_email,
    COALESCE(p_bags_s,0), COALESCE(p_bags_m,0), COALESCE(p_bags_l,0), p_notes,
    p_dropoff_planned_at, p_pickup_planned_at,
    v_need_u - (v_best_xS*1 + v_best_xM*2 + v_best_xL*4),
    v_best_xS, v_best_xM, v_best_xL
  )
  RETURNING id INTO v_booking_id;

  RETURN v_booking_id;
END;
$$;


ALTER FUNCTION "public"."create_partner_booking_v2"("p_partner_id" "uuid", "p_contact_first_name" "text", "p_contact_last_name" "text", "p_contact_phone" "text", "p_contact_email" "text", "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer, "p_dropoff_planned_at" timestamp with time zone, "p_pickup_planned_at" timestamp with time zone, "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_my_account"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_has_active boolean;
  v_partner_id uuid;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- 1) blocca se prenotazioni attive
  select exists (
    select 1
    from public.partner_bookings
    where user_id = v_uid
      and status in ('pending','confirmed')
  ) into v_has_active;

  if v_has_active then
    raise exception 'Non puoi eliminare l’account: hai prenotazioni attive.';
  end if;

  -- 2) trova eventuale partner associato
  select id into v_partner_id
  from public.partners
  where owner_id = v_uid
  limit 1;

  -- 3) elimina richieste partner
  delete from public.partner_requests
  where user_id = v_uid;

  -- 4) elimina partner (se esiste)
  if v_partner_id is not null then
    delete from public.partners
    where id = v_partner_id;
  end if;

  -- 5) elimina profilo applicativo
  delete from public.user_profiles
  where id = v_uid;

  -- 6) elimina auth user
  delete from auth.users
  where id = v_uid;

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


CREATE OR REPLACE FUNCTION "public"."ensure_partner_candidate_role"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.user_profiles(id, role)
  values (auth.uid(), 'partner_candidate')
  on conflict (id) do update
  set role = case
    when public.user_profiles.role = 'user' then 'partner_candidate'
    else public.user_profiles.role
  end;
end;
$$;


ALTER FUNCTION "public"."ensure_partner_candidate_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."finalize_partner_payment_webhook"("p_request_id" "uuid", "p_stripe_session_id" "text", "p_payment_reference" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_role text := auth.role();
  v_partner_id uuid;
  v_user_id uuid;
  v_status public.partner_request_status;
begin
  -- Permetti solo service_role (Edge Function con service key / webhook)
  if v_role is distinct from 'service_role' then
    raise exception 'Not authorized (service_role only)';
  end if;

  select pr.partner_id, pr.user_id, pr.status
    into v_partner_id, v_user_id, v_status
  from public.partner_requests pr
  where pr.id = p_request_id;

  if v_partner_id is null then
    raise exception 'Request not found';
  end if;

  if v_status is distinct from 'awaiting_payment'::public.partner_request_status then
    raise exception 'Invalid status. Expected awaiting_payment, got %', v_status;
  end if;

  update public.partner_requests
  set status = 'paid',
      paid_at = now(),
      payment_reference = coalesce(p_payment_reference, p_stripe_session_id),
      payment_required = false,
      updated_at = now()
  where id = p_request_id;

  update public.user_profiles
  set role = 'partner'
  where id = v_user_id;

  update public.partners
  set is_active = true,
      status = 'approved',
      updated_at = now()
  where id = v_partner_id;
end;
$$;


ALTER FUNCTION "public"."finalize_partner_payment_webhook"("p_request_id" "uuid", "p_stripe_session_id" "text", "p_payment_reference" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_booking_code"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_code text;
begin
  loop
    v_code := 'BD' || upper(substr(encode(gen_random_bytes(5), 'hex'), 1, 10));
    exit when not exists (
      select 1 from public.partner_bookings where booking_code = v_code
    );
  end loop;

  return v_code;
end;
$$;


ALTER FUNCTION "public"."generate_booking_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_booking_qr_payload"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;
  v_user_id uuid;
  v_status text;
  v_token uuid;
  v_partner_id uuid;
  v_dropoff timestamptz;
  v_pickup timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nessun utente autenticato.' USING errcode = 'P0001';
  END IF;

  SELECT (up.role = 'admin') INTO v_is_admin
  FROM public.user_profiles up
  WHERE up.id = v_uid;

  SELECT user_id, status, qr_token, partner_id, dropoff_planned_at, pickup_planned_at
  INTO v_user_id, v_status, v_token, v_partner_id, v_dropoff, v_pickup
  FROM public.partner_bookings
  WHERE id = p_booking_id;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Prenotazione non trovata.' USING errcode = 'P0001';
  END IF;

  -- Solo owner della prenotazione (o admin) può ottenere il QR
  IF COALESCE(v_is_admin,false) = false AND v_user_id <> v_uid THEN
    RAISE EXCEPTION 'Non autorizzato.' USING errcode = 'P0001';
  END IF;

  -- QR disponibile solo se "confirmed" o "in_store"
  IF v_status NOT IN ('confirmed','in_store') THEN
    RAISE EXCEPTION 'QR non disponibile per questo stato (%).', v_status
      USING errcode = 'P0001';
  END IF;

  RETURN jsonb_build_object(
    'booking_id', p_booking_id::text,
    'token', v_token::text,
    'partner_id', v_partner_id::text,
    'status', v_status,
    'dropoff_planned_at', v_dropoff,
    'pickup_planned_at', v_pickup
  );
END;
$$;


ALTER FUNCTION "public"."get_booking_qr_payload"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_late_fee_quote"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;
  b record;

  v_now timestamptz := now();

  v_paid_until timestamptz;
  v_deadline timestamptz;

  paid jsonb;
  req  jsonb;

  paid_key text;
  paid_extra int := 0;

  req_key text;
  req_extra int := 0;

  v_to_covered timestamptz;

  v_paid_total_guess int := 0;
  v_paid_total int := 0;

  v_required_total int := 0;
  v_amount int := 0;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'message', 'Nessun utente autenticato.');
  end if;

  select (up.role = 'admin') into v_is_admin
  from public.user_profiles up
  where up.id = v_uid;

  select * into b
  from public.partner_bookings
  where id = p_booking_id
  limit 1;

  if b.id is null then
    return jsonb_build_object('ok', false, 'message', 'Prenotazione non trovata.');
  end if;

  if coalesce(v_is_admin,false) = false and b.user_id <> v_uid then
    return jsonb_build_object('ok', false, 'message', 'Non autorizzato.');
  end if;

  if b.dropoff_effective_at is null then
    return jsonb_build_object('ok', false, 'message', 'Supplemento applicabile solo dopo il check-in.');
  end if;

  if b.pickup_effective_at is not null then
    return jsonb_build_object('ok', false, 'message', 'Prenotazione già completata.');
  end if;

  if b.dropoff_planned_at is null then
    return jsonb_build_object('ok', false, 'message', 'dropoff_planned_at mancante.');
  end if;

  -- paid_until: fonte di verità (covered_until), fallback su end_date/end_time o pickup_planned_at
  v_paid_until :=
    coalesce(
      b.covered_until,
      case
        when b.end_date is not null and b.end_time is not null
          then ((b.end_date::timestamp + b.end_time) at time zone 'Europe/Rome')
        else null
      end,
      b.pickup_planned_at,
      b.dropoff_planned_at + interval '3 hours'
    );

  if v_paid_until is null then
    return jsonb_build_object('ok', false, 'message', 'Impossibile determinare la copertura pagata (covered_until/end_date/end_time).');
  end if;

  -- tolleranza
  v_deadline := v_paid_until + interval '15 minutes';
  if v_now <= v_deadline then
    return jsonb_build_object('ok', false, 'message', 'Nessun supplemento: sei entro tolleranza.');
  end if;

  -- fascia "pagata" (per UX)
  paid := public.bd_infer_window_v2(b.partner_id, b.dropoff_planned_at, v_paid_until);
  paid_key := paid->>'duration_key';
  paid_extra := coalesce((paid->>'extra_days')::int, 0);

  -- totale pagato "atteso" dalla fascia pagata (fallback robusto)
  if paid_key = 'threeDays' and paid_extra > 0 then
    v_paid_total_guess := public.bd_pricing_total_cents_extended('threeDays', paid_extra, b.bags_s, b.bags_m, b.bags_l);
  else
    v_paid_total_guess := public.bd_pricing_total_cents(paid_key, b.bags_s, b.bags_m, b.bags_l);
  end if;

  -- totale pagato vero: preferisci DB (progressivo), ma non scendere sotto la stima
  v_paid_total := greatest(coalesce(b.total_paid_cents,0), v_paid_total_guess);

  -- fascia richiesta "adesso" (single-shot)
  req := public.bd_window_for_moment(b.partner_id, b.dropoff_planned_at, v_now);
  req_key := req->>'duration_key';
  req_extra := coalesce((req->>'extra_days')::int, 0);
  v_to_covered := (req->>'covered_until')::timestamptz;

  -- totale dovuto per la fascia attuale
  if req_key = 'threeDays' and req_extra > 0 then
    v_required_total := public.bd_pricing_total_cents_extended('threeDays', req_extra, b.bags_s, b.bags_m, b.bags_l);
  else
    v_required_total := public.bd_pricing_total_cents(req_key, b.bags_s, b.bags_m, b.bags_l);
  end if;

  -- differenza progressiva (SINGLE-SHOT)
  v_amount := greatest(0, v_required_total - v_paid_total);

  return jsonb_build_object(
    'ok', true,
    'amount_cents', v_amount,

    'paid_total_cents', v_paid_total,
    'required_total_cents', v_required_total,

    'from_duration', paid_key,
    'from_extra_days', paid_extra,
    'to_duration', req_key,
    'to_extra_days', req_extra,

    'from_covered_until', v_paid_until,
    'to_covered_until', v_to_covered,

    'message',
      case
        when v_amount = 0 then 'Nessun importo aggiuntivo.'
        else 'Supplemento calcolato (single-shot).'
      end
  );
end;
$$;


ALTER FUNCTION "public"."get_late_fee_quote"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_partner_availability_for_interval_v2"("p_partner_id" "uuid", "p_start_at" timestamp with time zone, "p_end_at" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    SET "row_security" TO 'off'
    AS $$
DECLARE
  v_base_capacity_u int;
  v_extra_s int;
  v_extra_m int;
  v_extra_l int;

  v_used_base_u int;
  v_used_extra_s int;
  v_used_extra_m int;
  v_used_extra_l int;

  v_base_remaining_u int;
  v_extra_remaining_s int;
  v_extra_remaining_m int;
  v_extra_remaining_l int;

  v_effective_s int;
  v_effective_m int;
  v_effective_l int;
  v_effective_total_u int;
BEGIN
  IF p_start_at IS NULL OR p_end_at IS NULL OR p_start_at >= p_end_at THEN
    RAISE EXCEPTION 'Intervallo non valido' USING errcode='P0001';
  END IF;

  SELECT base_capacity_u, extra_capacity_s, extra_capacity_m, extra_capacity_l
    INTO v_base_capacity_u, v_extra_s, v_extra_m, v_extra_l
  FROM public.partners
  WHERE id = p_partner_id;

  IF v_base_capacity_u IS NULL THEN
    RAISE EXCEPTION 'Partner non trovato' USING errcode='P0001';
  END IF;

  SELECT
    COALESCE(SUM(base_used_u), 0),
    COALESCE(SUM(extra_used_s), 0),
    COALESCE(SUM(extra_used_m), 0),
    COALESCE(SUM(extra_used_l), 0)
  INTO v_used_base_u, v_used_extra_s, v_used_extra_m, v_used_extra_l
  FROM public.partner_bookings pb
  WHERE pb.partner_id = p_partner_id
    AND pb.status IN ('pending','confirmed','in_store')
    AND pb.dropoff_planned_at IS NOT NULL
    AND pb.pickup_planned_at IS NOT NULL
    AND tstzrange(pb.dropoff_planned_at, pb.pickup_planned_at, '[)') &&
        tstzrange(p_start_at, p_end_at, '[)');

  v_base_remaining_u := GREATEST(0, v_base_capacity_u - v_used_base_u);
  v_extra_remaining_s := GREATEST(0, v_extra_s - v_used_extra_s);
  v_extra_remaining_m := GREATEST(0, v_extra_m - v_used_extra_m);
  v_extra_remaining_l := GREATEST(0, v_extra_l - v_used_extra_l);

  -- Derivate (solo display/UI)
  v_effective_s := v_base_capacity_u + v_extra_s;
  v_effective_m := floor(v_base_capacity_u::numeric/2)::int + v_extra_m;
  v_effective_l := floor(v_base_capacity_u::numeric/4)::int + v_extra_l;
  v_effective_total_u := (v_effective_s*1) + (v_effective_m*2) + (v_effective_l*4);

  RETURN jsonb_build_object(
    'partner_id', p_partner_id,
    'start_at', p_start_at,
    'end_at', p_end_at,

    'base_capacity_u', v_base_capacity_u,
    'base_used_u', v_used_base_u,
    'base_remaining_u', v_base_remaining_u,

    'extra_capacity_s', v_extra_s,
    'extra_capacity_m', v_extra_m,
    'extra_capacity_l', v_extra_l,

    'extra_used_s', v_used_extra_s,
    'extra_used_m', v_used_extra_m,
    'extra_used_l', v_used_extra_l,

    'extra_remaining_s', v_extra_remaining_s,
    'extra_remaining_m', v_extra_remaining_m,
    'extra_remaining_l', v_extra_remaining_l,

    'effective_capacity_s', v_effective_s,
    'effective_capacity_m', v_effective_m,
    'effective_capacity_l', v_effective_l,
    'effective_capacity_total_u', v_effective_total_u
  );
END;
$$;


ALTER FUNCTION "public"."get_partner_availability_for_interval_v2"("p_partner_id" "uuid", "p_start_at" timestamp with time zone, "p_end_at" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_partner_used_capacity_m"("p_id" "uuid", "check_time" timestamp with time zone) RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  used_m integer;
BEGIN
  SELECT COALESCE(SUM(
    bags_m + 
    CEIL(bags_s::float / 2.0) + 
    (bags_l * 2)
  ), 0)
  INTO used_m
  FROM public.partner_bookings
  WHERE partner_id = p_id
    AND status IN ('pending', 'confirmed') -- Conta solo prenotazioni attive
    AND check_time >= booking_start_time 
    AND check_time <= booking_end_time; -- Logica temporale semplificata (adatta se booking è per slot)
    
  RETURN used_m;
END;
$$;


ALTER FUNCTION "public"."get_partner_used_capacity_m"("p_id" "uuid", "check_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_partner_booking_accepting"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_ok boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.partners p
      WHERE p.id = NEW.partner_id
        AND p.is_active = true
        AND p.accepting_bookings = true
        AND p.status = 'approved'
    ) INTO v_ok;

    IF v_ok IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'Questo partner non accetta prenotazioni al momento.'
        USING errcode = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."guard_partner_booking_accepting"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."guard_partner_booking_partner_cancel"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;
  v_owner uuid;
BEGIN
  -- Blocca INSERT già annullato dal partner / rejected legacy
  IF TG_OP = 'INSERT' THEN
    IF NEW.status IN ('cancelled_by_partner','rejected') THEN
      RAISE EXCEPTION 'Non puoi inserire una prenotazione già rifiutata/annullata.'
        USING errcode = 'P0001';
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE: se già cancelled_by_partner -> irreversibile su stato/reason/rejected_at
  IF TG_OP = 'UPDATE' THEN
    IF OLD.status = 'cancelled_by_partner' THEN
      IF NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION 'Prenotazione rifiutata: stato non modificabile.'
          USING errcode = 'P0001';
      END IF;
      IF NEW.reject_reason IS DISTINCT FROM OLD.reject_reason THEN
        RAISE EXCEPTION 'Prenotazione rifiutata: motivazione non modificabile.'
          USING errcode = 'P0001';
      END IF;
      IF NEW.rejected_at IS DISTINCT FROM OLD.rejected_at THEN
        RAISE EXCEPTION 'Prenotazione rifiutata: timestamp non modificabile.'
          USING errcode = 'P0001';
      END IF;
      RETURN NEW;
    END IF;

    -- Non permetto settaggio "rejected" (non esiste più)
    IF NEW.status = 'rejected' THEN
      RAISE EXCEPTION 'Stato rejected non supportato: usare cancelled_by_partner.'
        USING errcode = 'P0001';
    END IF;

    -- Transizione a cancelled_by_partner: solo owner/admin + reason obbligatoria + set rejected_at
    IF NEW.status = 'cancelled_by_partner' AND OLD.status IS DISTINCT FROM NEW.status THEN
      IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Non autorizzato.' USING errcode = 'P0001';
      END IF;

      SELECT (up.role = 'admin') INTO v_is_admin
      FROM public.user_profiles up
      WHERE up.id = v_uid;

      SELECT p.owner_id INTO v_owner
      FROM public.partners p
      WHERE p.id = NEW.partner_id;

      IF v_owner IS NULL THEN
        RAISE EXCEPTION 'Partner non valido.' USING errcode = 'P0001';
      END IF;

      IF COALESCE(v_is_admin,false) = false AND v_owner <> v_uid THEN
        RAISE EXCEPTION 'Solo il proprietario (o admin) può rifiutare la prenotazione.'
          USING errcode = 'P0001';
      END IF;

      IF trim(COALESCE(NEW.reject_reason,'')) = '' THEN
        RAISE EXCEPTION 'Motivazione obbligatoria per rifiutare.'
          USING errcode = 'P0001';
      END IF;

      IF NEW.rejected_at IS NULL THEN
        NEW.rejected_at := now();
      END IF;
    END IF;

    -- Se qualcuno prova a scrivere reject_reason/rejected_at senza essere in cancelled_by_partner → blocco
    IF (NEW.reject_reason IS DISTINCT FROM OLD.reject_reason OR NEW.rejected_at IS DISTINCT FROM OLD.rejected_at)
       AND NEW.status <> 'cancelled_by_partner' THEN
      RAISE EXCEPTION 'reject_reason/rejected_at ammessi solo con status cancelled_by_partner.'
        USING errcode = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."guard_partner_booking_partner_cancel"() OWNER TO "postgres";


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


CREATE OR REPLACE FUNCTION "public"."on_booking_payment_insert"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  update public.partner_bookings pb
  set total_paid_cents = coalesce(pb.total_paid_cents, 0) + new.amount_cents,
      covered_until = case
        when new.kind = 'late_fee' and new.to_covered_until is not null
          then new.to_covered_until
        when new.kind = 'base' and pb.covered_until is null
          then coalesce(pb.pickup_planned_at, pb.dropoff_planned_at + interval '3 hours')
        else pb.covered_until
      end,
      updated_at = now()
  where pb.id = new.booking_id;

  return new;
end;
$$;


ALTER FUNCTION "public"."on_booking_payment_insert"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."on_partner_approved_update_role"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  -- Promuovi a partner SOLO quando il partner viene effettivamente attivato
  if coalesce(old.is_active,false) = false and coalesce(new.is_active,false) = true then
    update public.user_profiles
    set role = 'partner'
    where id = new.owner_id;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."on_partner_approved_update_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."partner_wizard_check_email"("p_email" "text") RETURNS TABLE("exists_user" boolean, "signup_flow" "text", "otp_verified" boolean, "profile_role" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
declare
  v_uid uuid;
  v_meta jsonb;
begin
  p_email := lower(trim(p_email));

  select u.id, u.raw_user_meta_data
    into v_uid, v_meta
  from auth.users u
  where lower(u.email) = p_email
  limit 1;

  if v_uid is null then
    exists_user := false;
    signup_flow := null;
    otp_verified := false;
    profile_role := null;
    return next;
    return;
  end if;

  exists_user := true;
  signup_flow := coalesce(v_meta->>'signup_flow', null);
  otp_verified := coalesce((v_meta->>'otp_verified')::boolean, false);

  select up.role into profile_role
  from public.user_profiles up
  where up.id = v_uid;

  return next;
end;
$$;


ALTER FUNCTION "public"."partner_wizard_check_email"("p_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pay_late_fee"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_b record;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'message', 'Nessun utente autenticato.');
  end if;

  select id, user_id, late_fee_required, late_fee_paid_at, pickup_pending_at, pickup_effective_at, status
  into v_b
  from public.partner_bookings
  where id = p_booking_id;

  if v_b.id is null then
    return jsonb_build_object('ok', false, 'message', 'Prenotazione non trovata.');
  end if;

  if v_b.user_id <> v_uid then
    return jsonb_build_object('ok', false, 'message', 'Non autorizzato.');
  end if;

  if coalesce(v_b.late_fee_required,false) = false then
    return jsonb_build_object('ok', false, 'message', 'Nessun supplemento richiesto.');
  end if;

  if v_b.late_fee_paid_at is not null then
    return jsonb_build_object('ok', true, 'message', 'Già pagato.');
  end if;

  update public.partner_bookings
  set late_fee_paid_at = now(),
      pickup_effective_at = coalesce(pickup_effective_at, pickup_pending_at, now()),
      pickup_pending_at = null,
      status = 'completed',
      updated_at = now()
  where id = p_booking_id;

  return jsonb_build_object('ok', true, 'message', 'Pagamento completato. Check-out concluso.');
end;
$$;


ALTER FUNCTION "public"."pay_late_fee"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."pay_late_fee_and_extend"("p_booking_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;

  b record;
  v_now timestamptz := now();

  v_quote jsonb;

  v_amount int := 0;
  v_paid_total int := 0;
  v_required_total int := 0;

  v_from_covered timestamptz;
  v_to_covered timestamptz;

  from_key text;
  to_key text;
  from_extra int := 0;
  to_extra int := 0;

  v_new_end_date date;
  v_new_end_time time;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'message', 'Nessun utente autenticato.');
  end if;

  select (up.role = 'admin') into v_is_admin
  from public.user_profiles up
  where up.id = v_uid;

  -- 🔒 lock riga prenotazione per evitare doppi pagamenti concorrenti
  select * into b
  from public.partner_bookings
  where id = p_booking_id
  for update;

  if b.id is null then
    return jsonb_build_object('ok', false, 'message', 'Prenotazione non trovata.');
  end if;

  if coalesce(v_is_admin,false) = false and b.user_id <> v_uid then
    return jsonb_build_object('ok', false, 'message', 'Non autorizzato.');
  end if;

  if b.dropoff_effective_at is null then
    return jsonb_build_object('ok', false, 'message', 'Pagamento possibile solo dopo il check-in.');
  end if;

  if b.pickup_effective_at is not null then
    return jsonb_build_object('ok', false, 'message', 'Prenotazione già completata.');
  end if;

  -- quote server-side (source of truth)
  v_quote := public.get_late_fee_quote(p_booking_id);

  if (v_quote->>'ok')::boolean is distinct from true then
    return jsonb_build_object('ok', false, 'message', coalesce(v_quote->>'message','Impossibile calcolare supplemento.'));
  end if;

  v_amount := coalesce((v_quote->>'amount_cents')::int, 0);
  v_paid_total := coalesce((v_quote->>'paid_total_cents')::int, 0);
  v_required_total := coalesce((v_quote->>'required_total_cents')::int, 0);

  v_from_covered := (v_quote->>'from_covered_until')::timestamptz;
  v_to_covered   := (v_quote->>'to_covered_until')::timestamptz;

  from_key := v_quote->>'from_duration';
  to_key := v_quote->>'to_duration';
  from_extra := coalesce((v_quote->>'from_extra_days')::int, 0);
  to_extra := coalesce((v_quote->>'to_extra_days')::int, 0);

  if v_amount <= 0 then
    return jsonb_build_object('ok', true, 'amount_cents', 0, 'message', 'Nessun supplemento da pagare.');
  end if;

  -- end_date/end_time locali
  v_new_end_date := (v_to_covered at time zone 'Europe/Rome')::date;
  v_new_end_time := (v_to_covered at time zone 'Europe/Rome')::time;

  -- log pagamento
  insert into public.booking_payments(
    booking_id, kind, amount_cents,
    from_covered_until, to_covered_until,
    from_duration_key, to_duration_key,
    paid_at, payment_reference
  ) values (
    p_booking_id, 'late_fee', v_amount,
    v_from_covered, v_to_covered,
    (from_key || case when from_key='threeDays' and from_extra>0 then ('+'||from_extra::text) else '' end),
    (to_key   || case when to_key='threeDays'   and to_extra>0   then ('+'||to_extra::text)   else '' end),
    v_now, 'mock'
  );

  -- aggiorna booking: copertura + totale pagato (portato al required_total)
  update public.partner_bookings
  set covered_until = v_to_covered,
      total_paid_cents = greatest(coalesce(total_paid_cents,0), v_required_total),
      end_date = v_new_end_date,
      end_time = v_new_end_time,
      updated_at = now()
  where id = p_booking_id;

  return jsonb_build_object(
    'ok', true,
    'amount_cents', v_amount,
    'paid_total_cents', v_required_total,
    'new_pickup_planned_at', v_to_covered,
    'message', 'Supplemento registrato (single-shot) e prenotazione riallineata.'
  );
end;
$$;


ALTER FUNCTION "public"."pay_late_fee_and_extend"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."process_booking_code"("p_code" "text", "p_force" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;
  v_booking record;
  v_owner uuid;
  v_now timestamptz := now();
  v_dropoff timestamptz;
  v_pickup timestamptz;
  v_need_pay boolean := false;
  v_action text;
  v_code text := upper(trim(coalesce(p_code,'')));
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'message', 'Nessun utente autenticato.');
  end if;

  select (up.role = 'admin') into v_is_admin
  from public.user_profiles up
  where up.id = v_uid;

  select * into v_booking
  from public.partner_bookings
  where booking_code = v_code
  limit 1;

  if v_booking.id is null then
    return jsonb_build_object('ok', false, 'message', 'Codice non valido.');
  end if;

  select owner_id into v_owner
  from public.partners
  where id = v_booking.partner_id;

  if coalesce(v_is_admin,false) = false and v_owner <> v_uid then
    return jsonb_build_object('ok', false, 'message', 'Non autorizzato per questa prenotazione.');
  end if;

  -- rejected trattiamolo come cancelled
  if lower(v_booking.status) in ('cancelled','canceled','rejected','cancelled_by_user','cancelled_by_partner','expired') then
    return jsonb_build_object('ok', false, 'message', 'Prenotazione annullata/rifiutata: non processabile.');
  end if;

  -- pianificati: preferisco dropoff_planned_at/pickup_planned_at, altrimenti fallback legacy
  if v_booking.dropoff_planned_at is null or v_booking.pickup_planned_at is null then
    v_dropoff := ((v_booking.booking_date::text || ' ' || v_booking.start_time::text)::timestamp at time zone 'Europe/Rome');
    v_pickup  := ((coalesce(v_booking.end_date, v_booking.booking_date)::text || ' ' || v_booking.end_time::text)::timestamp at time zone 'Europe/Rome');
  else
    v_dropoff := v_booking.dropoff_planned_at;
    v_pickup  := v_booking.pickup_planned_at;
  end if;

  -- già completata
  if v_booking.dropoff_effective_at is not null and v_booking.pickup_effective_at is not null then
    return jsonb_build_object(
      'ok', true,
      'action', 'already_done',
      'booking_id', v_booking.id,
      'message', 'Check-in e check-out già registrati.'
    );
  end if;

  -- AZIONE: se non c'è dropoff_effective => check-in, altrimenti check-out
  if v_booking.dropoff_effective_at is null then
    v_action := 'check_in';

    -- finestra check-in: da -30 min fino a prima del pickup (arrivare dopo va bene)
    if v_now < (v_dropoff - interval '30 minutes') then
      return jsonb_build_object('ok', false, 'action', v_action, 'booking_id', v_booking.id,
        'message', 'Troppo presto per il check-in.');
    end if;

    if v_now >= v_pickup then
      return jsonb_build_object('ok', false, 'action', v_action, 'booking_id', v_booking.id,
        'message', 'Orario di ritiro già passato: check-in non consentito.');
    end if;

update public.partner_bookings
set dropoff_effective_at = coalesce(dropoff_effective_at, v_now),
    status = 'in_store',
    updated_at = now()
where id = v_booking.id;

    return jsonb_build_object('ok', true, 'action', v_action, 'booking_id', v_booking.id,
      'message', 'Check-in registrato.');
  else
    v_action := 'check_out';

    -- check-out: se oltre pickup + 15 min => serve supplemento
    if v_now > (v_pickup + interval '15 minutes') then
      v_need_pay := true;
    end if;

    if v_need_pay and p_force is distinct from true then
      return jsonb_build_object(
        'ok', false,
        'action', v_action,
        'booking_id', v_booking.id,
        'require_payment', true,
        'message', 'Oltre la tolleranza: serve supplemento. Premi “Paga ora”.'
      );
    end if;

update public.partner_bookings
set pickup_effective_at = coalesce(pickup_effective_at, v_now),
    status = 'completed',
    updated_at = now()
where id = v_booking.id;


    return jsonb_build_object(
      'ok', true,
      'action', v_action,
      'booking_id', v_booking.id,
      'message', case when v_need_pay then 'Pagamento (mock) ok + check-out registrato.' else 'Check-out registrato.' end
    );
  end if;
end;
$$;


ALTER FUNCTION "public"."process_booking_code"("p_code" "text", "p_force" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."process_booking_qr"("p_booking_id" "uuid", "p_token" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;

  v_partner_id uuid;
  v_owner uuid;
  v_status text;
  v_db_token uuid;

  v_dropoff timestamptz;
  v_pickup  timestamptz;
  v_now timestamptz := now();

  -- ✅ finestra temporale (tweak qui):
  v_window_before interval := interval '2 hours';
  v_window_after  interval := interval '2 hours';

  v_action text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nessun utente autenticato.' USING errcode = 'P0001';
  END IF;

  SELECT (up.role = 'admin') INTO v_is_admin
  FROM public.user_profiles up
  WHERE up.id = v_uid;

  SELECT partner_id, status, qr_token, dropoff_planned_at, pickup_planned_at
  INTO v_partner_id, v_status, v_db_token, v_dropoff, v_pickup
  FROM public.partner_bookings
  WHERE id = p_booking_id;

  IF v_partner_id IS NULL THEN
    RAISE EXCEPTION 'Prenotazione non trovata.' USING errcode = 'P0001';
  END IF;

  SELECT owner_id INTO v_owner
  FROM public.partners
  WHERE id = v_partner_id;

  IF COALESCE(v_is_admin,false) = false AND v_owner <> v_uid THEN
    RAISE EXCEPTION 'Non autorizzato: non sei il proprietario del locale.'
      USING errcode = 'P0001';
  END IF;

  IF v_db_token IS NULL THEN
    RAISE EXCEPTION 'QR token mancante.' USING errcode = 'P0001';
  END IF;

  IF v_db_token <> p_token THEN
    RAISE EXCEPTION 'QR non valido.' USING errcode = 'P0001';
  END IF;

  -- Stati non processabili
  IF v_status IN ('cancelled','cancelled_by_user','cancelled_by_partner','expired','completed') THEN
    RAISE EXCEPTION 'Prenotazione non processabile (stato=%).', v_status
      USING errcode = 'P0001';
  END IF;

  -- Se per qualche motivo planned_at è null, prova a ricostruirli (best-effort)
  IF v_dropoff IS NULL OR v_pickup IS NULL THEN
    UPDATE public.partner_bookings
    SET dropoff_planned_at = COALESCE(dropoff_planned_at,
          ((booking_date::text || ' ' || start_time::text)::timestamp AT TIME ZONE 'Europe/Rome')),
        pickup_planned_at  = COALESCE(pickup_planned_at,
          ((COALESCE(end_date, booking_date)::text || ' ' || end_time::text)::timestamp AT TIME ZONE 'Europe/Rome'))
    WHERE id = p_booking_id
    RETURNING dropoff_planned_at, pickup_planned_at
    INTO v_dropoff, v_pickup;
  END IF;

  -- CHECK-IN: confirmed -> in_store
  IF v_status = 'confirmed' THEN
    IF v_dropoff IS NULL THEN
      RAISE EXCEPTION 'dropoff_planned_at mancante.' USING errcode = 'P0001';
    END IF;

    IF NOT (v_now >= (v_dropoff - v_window_before) AND v_now <= (v_dropoff + v_window_after)) THEN
      RAISE EXCEPTION 'Fuori finestra check-in.' USING errcode = 'P0001';
    END IF;

    UPDATE public.partner_bookings
    SET status = 'in_store',
        dropoff_effective_at = COALESCE(dropoff_effective_at, v_now)
    WHERE id = p_booking_id;

    v_action := 'check_in';

    RETURN jsonb_build_object(
      'ok', true,
      'action', v_action,
      'new_status', 'in_store',
      'dropoff_effective_at', v_now
    );
  END IF;

  -- CHECK-OUT: in_store -> completed
  IF v_status = 'in_store' THEN
    IF v_pickup IS NULL THEN
      RAISE EXCEPTION 'pickup_planned_at mancante.' USING errcode = 'P0001';
    END IF;

    IF NOT (v_now >= (v_pickup - v_window_before) AND v_now <= (v_pickup + v_window_after)) THEN
      RAISE EXCEPTION 'Fuori finestra check-out.' USING errcode = 'P0001';
    END IF;

    UPDATE public.partner_bookings
    SET status = 'completed',
        pickup_effective_at = COALESCE(pickup_effective_at, v_now)
    WHERE id = p_booking_id;

    v_action := 'check_out';

    RETURN jsonb_build_object(
      'ok', true,
      'action', v_action,
      'new_status', 'completed',
      'pickup_effective_at', v_now
    );
  END IF;

  -- Pending o altro
  RAISE EXCEPTION 'Stato non valido per lo scan (stato=%).', v_status
    USING errcode = 'P0001';
END;
$$;


ALTER FUNCTION "public"."process_booking_qr"("p_booking_id" "uuid", "p_token" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reject_partner_booking"("p_booking_id" "uuid", "p_reason" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_partner_id uuid;
  v_owner uuid;
  v_status text;
  v_is_admin boolean := false;
  v_reason text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nessun utente autenticato.' USING errcode = 'P0001';
  END IF;

  SELECT partner_id, status
    INTO v_partner_id, v_status
  FROM public.partner_bookings
  WHERE id = p_booking_id;

  IF v_partner_id IS NULL THEN
    RAISE EXCEPTION 'Prenotazione non trovata.' USING errcode = 'P0001';
  END IF;

  SELECT owner_id INTO v_owner
  FROM public.partners
  WHERE id = v_partner_id;

  SELECT (up.role = 'admin') INTO v_is_admin
  FROM public.user_profiles up
  WHERE up.id = v_uid;

  IF COALESCE(v_is_admin,false) = false AND v_owner <> v_uid THEN
    RAISE EXCEPTION 'Non autorizzato: non sei il proprietario del locale.'
      USING errcode = 'P0001';
  END IF;

  IF v_status = 'cancelled_by_partner' THEN
    RAISE EXCEPTION 'Prenotazione già rifiutata.' USING errcode = 'P0001';
  END IF;

  IF v_status IN ('completed','cancelled','cancelled_by_user','expired') THEN
    RAISE EXCEPTION 'Non puoi rifiutare una prenotazione già chiusa/annullata.'
      USING errcode = 'P0001';
  END IF;

  v_reason := nullif(trim(coalesce(p_reason, '')), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Motivazione obbligatoria.' USING errcode = 'P0001';
  END IF;

  UPDATE public.partner_bookings
  SET status = 'cancelled_by_partner',
      reject_reason = v_reason,
      rejected_at = now()
  WHERE id = p_booking_id;
END;
$$;


ALTER FUNCTION "public"."reject_partner_booking"("p_booking_id" "uuid", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_booking_qr_token"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    SET "row_security" TO 'off'
    AS $$
BEGIN
  IF NEW.qr_token IS NULL THEN
    NEW.qr_token := gen_random_uuid();
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_booking_qr_token"() OWNER TO "postgres";


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


CREATE OR REPLACE FUNCTION "public"."submit_partner_request"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_count int;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.partner_requests
  set status = 'submitted'::public.partner_request_status,
      updated_at = now()
  where user_id = auth.uid()
    and status = 'draft'::public.partner_request_status;

  get diagnostics v_count = row_count;

  if v_count = 0 then
    raise exception 'No draft request to submit (already submitted or not started).';
  end if;

  update public.user_profiles
  set role = 'partner_candidate'
  where id = auth.uid()
    and role in ('user','partner_candidate');
end;
$$;


ALTER FUNCTION "public"."submit_partner_request"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_booking_interval"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    SET "row_security" TO 'off'
    AS $$
BEGIN
  -- Consegna prevista
  IF NEW.booking_date IS NOT NULL AND NEW.start_time IS NOT NULL THEN
    NEW.dropoff_planned_at :=
      ((NEW.booking_date::text || ' ' || NEW.start_time::text)::timestamp
        AT TIME ZONE 'Europe/Rome');
  END IF;

  -- Ritiro previsto
  IF COALESCE(NEW.end_date, NEW.booking_date) IS NOT NULL
     AND NEW.end_time IS NOT NULL THEN
    NEW.pickup_planned_at :=
      ((COALESCE(NEW.end_date, NEW.booking_date)::text || ' ' || NEW.end_time::text)::timestamp
        AT TIME ZONE 'Europe/Rome');
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_booking_interval"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_partner_capacity_derived"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_base_s int;
  v_base_m int;
  v_base_l int;
  v_eff_s int;
  v_eff_m int;
  v_eff_l int;
BEGIN
  -- base convertita da unità
  v_base_s := GREATEST(0, NEW.base_capacity_u);
  v_base_m := floor(v_base_s::numeric / 2)::int;
  v_base_l := floor(v_base_s::numeric / 4)::int;

  v_eff_s := v_base_s + GREATEST(0, NEW.extra_capacity_s);
  v_eff_m := v_base_m + GREATEST(0, NEW.extra_capacity_m);
  v_eff_l := v_base_l + GREATEST(0, NEW.extra_capacity_l);

  NEW.capacity_s := v_eff_s;
  NEW.capacity_m := v_eff_m;
  NEW.capacity_l := v_eff_l;

  -- capacity = totale in unità equivalenti
  NEW.capacity := (v_eff_s * 1) + (v_eff_m * 2) + (v_eff_l * 4);

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_partner_capacity_derived"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end; $$;


ALTER FUNCTION "public"."touch_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."upsert_partner_request_draft"("p_partner_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_id uuid;
  v_last public.partner_request_status;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select status into v_last
  from public.partner_requests
  where user_id = auth.uid()
  order by created_at desc
  limit 1;

  if v_last is not null and v_last <> 'draft'::public.partner_request_status then
    raise exception 'You cannot start a new request. Current status is %', v_last;
  end if;

  select id into v_id
  from public.partner_requests
  where user_id = auth.uid()
    and status = 'draft'::public.partner_request_status
  order by created_at desc
  limit 1;

  if v_id is null then
    insert into public.partner_requests(user_id, partner_id, status, created_at)
    values (auth.uid(), p_partner_id, 'draft'::public.partner_request_status, now())
    returning id into v_id;
  else
    update public.partner_requests
    set partner_id = p_partner_id,
        updated_at = now()
    where id = v_id;
  end if;

  return v_id;
end;
$$;


ALTER FUNCTION "public"."upsert_partner_request_draft"("p_partner_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "storage"."add_prefixes"("_bucket_id" "text", "_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    prefixes text[];
BEGIN
    prefixes := "storage"."get_prefixes"("_name");

    IF array_length(prefixes, 1) > 0 THEN
        INSERT INTO storage.prefixes (name, bucket_id)
        SELECT UNNEST(prefixes) as name, "_bucket_id" ON CONFLICT DO NOTHING;
    END IF;
END;
$$;


ALTER FUNCTION "storage"."add_prefixes"("_bucket_id" "text", "_name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


ALTER FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."delete_leaf_prefixes"("bucket_ids" "text"[], "names" "text"[]) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_rows_deleted integer;
BEGIN
    LOOP
        WITH candidates AS (
            SELECT DISTINCT
                t.bucket_id,
                unnest(storage.get_prefixes(t.name)) AS name
            FROM unnest(bucket_ids, names) AS t(bucket_id, name)
        ),
        uniq AS (
             SELECT
                 bucket_id,
                 name,
                 storage.get_level(name) AS level
             FROM candidates
             WHERE name <> ''
             GROUP BY bucket_id, name
        ),
        leaf AS (
             SELECT
                 p.bucket_id,
                 p.name,
                 p.level
             FROM storage.prefixes AS p
                  JOIN uniq AS u
                       ON u.bucket_id = p.bucket_id
                           AND u.name = p.name
                           AND u.level = p.level
             WHERE NOT EXISTS (
                 SELECT 1
                 FROM storage.objects AS o
                 WHERE o.bucket_id = p.bucket_id
                   AND o.level = p.level + 1
                   AND o.name COLLATE "C" LIKE p.name || '/%'
             )
             AND NOT EXISTS (
                 SELECT 1
                 FROM storage.prefixes AS c
                 WHERE c.bucket_id = p.bucket_id
                   AND c.level = p.level + 1
                   AND c.name COLLATE "C" LIKE p.name || '/%'
             )
        )
        DELETE
        FROM storage.prefixes AS p
            USING leaf AS l
        WHERE p.bucket_id = l.bucket_id
          AND p.name = l.name
          AND p.level = l.level;

        GET DIAGNOSTICS v_rows_deleted = ROW_COUNT;
        EXIT WHEN v_rows_deleted = 0;
    END LOOP;
END;
$$;


ALTER FUNCTION "storage"."delete_leaf_prefixes"("bucket_ids" "text"[], "names" "text"[]) OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."delete_prefix"("_bucket_id" "text", "_name" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Check if we can delete the prefix
    IF EXISTS(
        SELECT FROM "storage"."prefixes"
        WHERE "prefixes"."bucket_id" = "_bucket_id"
          AND level = "storage"."get_level"("_name") + 1
          AND "prefixes"."name" COLLATE "C" LIKE "_name" || '/%'
        LIMIT 1
    )
    OR EXISTS(
        SELECT FROM "storage"."objects"
        WHERE "objects"."bucket_id" = "_bucket_id"
          AND "storage"."get_level"("objects"."name") = "storage"."get_level"("_name") + 1
          AND "objects"."name" COLLATE "C" LIKE "_name" || '/%'
        LIMIT 1
    ) THEN
    -- There are sub-objects, skip deletion
    RETURN false;
    ELSE
        DELETE FROM "storage"."prefixes"
        WHERE "prefixes"."bucket_id" = "_bucket_id"
          AND level = "storage"."get_level"("_name")
          AND "prefixes"."name" = "_name";
        RETURN true;
    END IF;
END;
$$;


ALTER FUNCTION "storage"."delete_prefix"("_bucket_id" "text", "_name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."delete_prefix_hierarchy_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    prefix text;
BEGIN
    prefix := "storage"."get_prefix"(OLD."name");

    IF coalesce(prefix, '') != '' THEN
        PERFORM "storage"."delete_prefix"(OLD."bucket_id", prefix);
    END IF;

    RETURN OLD;
END;
$$;


ALTER FUNCTION "storage"."delete_prefix_hierarchy_trigger"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."enforce_bucket_name_length"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


ALTER FUNCTION "storage"."enforce_bucket_name_length"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."extension"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    SELECT _parts[array_length(_parts,1)] INTO _filename;
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


ALTER FUNCTION "storage"."extension"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."filename"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$$;


ALTER FUNCTION "storage"."filename"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."foldername"("name" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


ALTER FUNCTION "storage"."foldername"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_level"("name" "text") RETURNS integer
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $$
SELECT array_length(string_to_array("name", '/'), 1);
$$;


ALTER FUNCTION "storage"."get_level"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_prefix"("name" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $_$
SELECT
    CASE WHEN strpos("name", '/') > 0 THEN
             regexp_replace("name", '[\/]{1}[^\/]+\/?$', '')
         ELSE
             ''
        END;
$_$;


ALTER FUNCTION "storage"."get_prefix"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_prefixes"("name" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE STRICT
    AS $$
DECLARE
    parts text[];
    prefixes text[];
    prefix text;
BEGIN
    -- Split the name into parts by '/'
    parts := string_to_array("name", '/');
    prefixes := '{}';

    -- Construct the prefixes, stopping one level below the last part
    FOR i IN 1..array_length(parts, 1) - 1 LOOP
            prefix := array_to_string(parts[1:i], '/');
            prefixes := array_append(prefixes, prefix);
    END LOOP;

    RETURN prefixes;
END;
$$;


ALTER FUNCTION "storage"."get_prefixes"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_size_by_bucket"() RETURNS TABLE("size" bigint, "bucket_id" "text")
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::bigint) as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


ALTER FUNCTION "storage"."get_size_by_bucket"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "next_key_token" "text" DEFAULT ''::"text", "next_upload_token" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "id" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


ALTER FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "next_key_token" "text", "next_upload_token" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_objects_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "start_after" "text" DEFAULT ''::"text", "next_token" "text" DEFAULT ''::"text") RETURNS TABLE("name" "text", "id" "uuid", "metadata" "jsonb", "updated_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(name COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(name from length($1) + 1)) > 0 THEN
                        substring(name from 1 for length($1) + position($2 IN substring(name from length($1) + 1)))
                    ELSE
                        name
                END AS name, id, metadata, updated_at
            FROM
                storage.objects
            WHERE
                bucket_id = $5 AND
                name ILIKE $1 || ''%'' AND
                CASE
                    WHEN $6 != '''' THEN
                    name COLLATE "C" > $6
                ELSE true END
                AND CASE
                    WHEN $4 != '''' THEN
                        CASE
                            WHEN position($2 IN substring(name from length($1) + 1)) > 0 THEN
                                substring(name from 1 for length($1) + position($2 IN substring(name from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                name COLLATE "C" > $4
                            END
                    ELSE
                        true
                END
            ORDER BY
                name COLLATE "C" ASC) as e order by name COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_token, bucket_id, start_after;
END;
$_$;


ALTER FUNCTION "storage"."list_objects_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "start_after" "text", "next_token" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."lock_top_prefixes"("bucket_ids" "text"[], "names" "text"[]) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_bucket text;
    v_top text;
BEGIN
    FOR v_bucket, v_top IN
        SELECT DISTINCT t.bucket_id,
            split_part(t.name, '/', 1) AS top
        FROM unnest(bucket_ids, names) AS t(bucket_id, name)
        WHERE t.name <> ''
        ORDER BY 1, 2
        LOOP
            PERFORM pg_advisory_xact_lock(hashtextextended(v_bucket || '/' || v_top, 0));
        END LOOP;
END;
$$;


ALTER FUNCTION "storage"."lock_top_prefixes"("bucket_ids" "text"[], "names" "text"[]) OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."objects_delete_cleanup"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_bucket_ids text[];
    v_names      text[];
BEGIN
    IF current_setting('storage.gc.prefixes', true) = '1' THEN
        RETURN NULL;
    END IF;

    PERFORM set_config('storage.gc.prefixes', '1', true);

    SELECT COALESCE(array_agg(d.bucket_id), '{}'),
           COALESCE(array_agg(d.name), '{}')
    INTO v_bucket_ids, v_names
    FROM deleted AS d
    WHERE d.name <> '';

    PERFORM storage.lock_top_prefixes(v_bucket_ids, v_names);
    PERFORM storage.delete_leaf_prefixes(v_bucket_ids, v_names);

    RETURN NULL;
END;
$$;


ALTER FUNCTION "storage"."objects_delete_cleanup"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."objects_insert_prefix_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    NEW.level := "storage"."get_level"(NEW."name");

    RETURN NEW;
END;
$$;


ALTER FUNCTION "storage"."objects_insert_prefix_trigger"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."objects_update_cleanup"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    -- NEW - OLD (destinations to create prefixes for)
    v_add_bucket_ids text[];
    v_add_names      text[];

    -- OLD - NEW (sources to prune)
    v_src_bucket_ids text[];
    v_src_names      text[];
BEGIN
    IF TG_OP <> 'UPDATE' THEN
        RETURN NULL;
    END IF;

    -- 1) Compute NEW−OLD (added paths) and OLD−NEW (moved-away paths)
    WITH added AS (
        SELECT n.bucket_id, n.name
        FROM new_rows n
        WHERE n.name <> '' AND position('/' in n.name) > 0
        EXCEPT
        SELECT o.bucket_id, o.name FROM old_rows o WHERE o.name <> ''
    ),
    moved AS (
         SELECT o.bucket_id, o.name
         FROM old_rows o
         WHERE o.name <> ''
         EXCEPT
         SELECT n.bucket_id, n.name FROM new_rows n WHERE n.name <> ''
    )
    SELECT
        -- arrays for ADDED (dest) in stable order
        COALESCE( (SELECT array_agg(a.bucket_id ORDER BY a.bucket_id, a.name) FROM added a), '{}' ),
        COALESCE( (SELECT array_agg(a.name      ORDER BY a.bucket_id, a.name) FROM added a), '{}' ),
        -- arrays for MOVED (src) in stable order
        COALESCE( (SELECT array_agg(m.bucket_id ORDER BY m.bucket_id, m.name) FROM moved m), '{}' ),
        COALESCE( (SELECT array_agg(m.name      ORDER BY m.bucket_id, m.name) FROM moved m), '{}' )
    INTO v_add_bucket_ids, v_add_names, v_src_bucket_ids, v_src_names;

    -- Nothing to do?
    IF (array_length(v_add_bucket_ids, 1) IS NULL) AND (array_length(v_src_bucket_ids, 1) IS NULL) THEN
        RETURN NULL;
    END IF;

    -- 2) Take per-(bucket, top) locks: ALL prefixes in consistent global order to prevent deadlocks
    DECLARE
        v_all_bucket_ids text[];
        v_all_names text[];
    BEGIN
        -- Combine source and destination arrays for consistent lock ordering
        v_all_bucket_ids := COALESCE(v_src_bucket_ids, '{}') || COALESCE(v_add_bucket_ids, '{}');
        v_all_names := COALESCE(v_src_names, '{}') || COALESCE(v_add_names, '{}');

        -- Single lock call ensures consistent global ordering across all transactions
        IF array_length(v_all_bucket_ids, 1) IS NOT NULL THEN
            PERFORM storage.lock_top_prefixes(v_all_bucket_ids, v_all_names);
        END IF;
    END;

    -- 3) Create destination prefixes (NEW−OLD) BEFORE pruning sources
    IF array_length(v_add_bucket_ids, 1) IS NOT NULL THEN
        WITH candidates AS (
            SELECT DISTINCT t.bucket_id, unnest(storage.get_prefixes(t.name)) AS name
            FROM unnest(v_add_bucket_ids, v_add_names) AS t(bucket_id, name)
            WHERE name <> ''
        )
        INSERT INTO storage.prefixes (bucket_id, name)
        SELECT c.bucket_id, c.name
        FROM candidates c
        ON CONFLICT DO NOTHING;
    END IF;

    -- 4) Prune source prefixes bottom-up for OLD−NEW
    IF array_length(v_src_bucket_ids, 1) IS NOT NULL THEN
        -- re-entrancy guard so DELETE on prefixes won't recurse
        IF current_setting('storage.gc.prefixes', true) <> '1' THEN
            PERFORM set_config('storage.gc.prefixes', '1', true);
        END IF;

        PERFORM storage.delete_leaf_prefixes(v_src_bucket_ids, v_src_names);
    END IF;

    RETURN NULL;
END;
$$;


ALTER FUNCTION "storage"."objects_update_cleanup"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."objects_update_level_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Ensure this is an update operation and the name has changed
    IF TG_OP = 'UPDATE' AND (NEW."name" <> OLD."name" OR NEW."bucket_id" <> OLD."bucket_id") THEN
        -- Set the new level
        NEW."level" := "storage"."get_level"(NEW."name");
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "storage"."objects_update_level_trigger"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."objects_update_prefix_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    old_prefixes TEXT[];
BEGIN
    -- Ensure this is an update operation and the name has changed
    IF TG_OP = 'UPDATE' AND (NEW."name" <> OLD."name" OR NEW."bucket_id" <> OLD."bucket_id") THEN
        -- Retrieve old prefixes
        old_prefixes := "storage"."get_prefixes"(OLD."name");

        -- Remove old prefixes that are only used by this object
        WITH all_prefixes as (
            SELECT unnest(old_prefixes) as prefix
        ),
        can_delete_prefixes as (
             SELECT prefix
             FROM all_prefixes
             WHERE NOT EXISTS (
                 SELECT 1 FROM "storage"."objects"
                 WHERE "bucket_id" = OLD."bucket_id"
                   AND "name" <> OLD."name"
                   AND "name" LIKE (prefix || '%')
             )
         )
        DELETE FROM "storage"."prefixes" WHERE name IN (SELECT prefix FROM can_delete_prefixes);

        -- Add new prefixes
        PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    END IF;
    -- Set the new level
    NEW."level" := "storage"."get_level"(NEW."name");

    RETURN NEW;
END;
$$;


ALTER FUNCTION "storage"."objects_update_prefix_trigger"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."operation"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


ALTER FUNCTION "storage"."operation"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."prefixes_delete_cleanup"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_bucket_ids text[];
    v_names      text[];
BEGIN
    IF current_setting('storage.gc.prefixes', true) = '1' THEN
        RETURN NULL;
    END IF;

    PERFORM set_config('storage.gc.prefixes', '1', true);

    SELECT COALESCE(array_agg(d.bucket_id), '{}'),
           COALESCE(array_agg(d.name), '{}')
    INTO v_bucket_ids, v_names
    FROM deleted AS d
    WHERE d.name <> '';

    PERFORM storage.lock_top_prefixes(v_bucket_ids, v_names);
    PERFORM storage.delete_leaf_prefixes(v_bucket_ids, v_names);

    RETURN NULL;
END;
$$;


ALTER FUNCTION "storage"."prefixes_delete_cleanup"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."prefixes_insert_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    PERFORM "storage"."add_prefixes"(NEW."bucket_id", NEW."name");
    RETURN NEW;
END;
$$;


ALTER FUNCTION "storage"."prefixes_insert_trigger"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "offsets" integer DEFAULT 0, "search" "text" DEFAULT ''::"text", "sortcolumn" "text" DEFAULT 'name'::"text", "sortorder" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
declare
    can_bypass_rls BOOLEAN;
begin
    SELECT rolbypassrls
    INTO can_bypass_rls
    FROM pg_roles
    WHERE rolname = coalesce(nullif(current_setting('role', true), 'none'), current_user);

    IF can_bypass_rls THEN
        RETURN QUERY SELECT * FROM storage.search_v1_optimised(prefix, bucketname, limits, levels, offsets, search, sortcolumn, sortorder);
    ELSE
        RETURN QUERY SELECT * FROM storage.search_legacy_v1(prefix, bucketname, limits, levels, offsets, search, sortcolumn, sortorder);
    END IF;
end;
$$;


ALTER FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer, "levels" integer, "offsets" integer, "search" "text", "sortcolumn" "text", "sortorder" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_legacy_v1"("prefix" "text", "bucketname" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "offsets" integer DEFAULT 0, "search" "text" DEFAULT ''::"text", "sortcolumn" "text" DEFAULT 'name'::"text", "sortorder" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select path_tokens[$1] as folder
           from storage.objects
             where objects.name ilike $2 || $3 || ''%''
               and bucket_id = $4
               and array_length(objects.path_tokens, 1) <> $1
           group by folder
           order by folder ' || v_sort_order || '
     )
     (select folder as "name",
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[$1] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where objects.name ilike $2 || $3 || ''%''
       and bucket_id = $4
       and array_length(objects.path_tokens, 1) = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


ALTER FUNCTION "storage"."search_legacy_v1"("prefix" "text", "bucketname" "text", "limits" integer, "levels" integer, "offsets" integer, "search" "text", "sortcolumn" "text", "sortorder" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_v1_optimised"("prefix" "text", "bucketname" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "offsets" integer DEFAULT 0, "search" "text" DEFAULT ''::"text", "sortcolumn" "text" DEFAULT 'name'::"text", "sortorder" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select (string_to_array(name, ''/''))[level] as name
           from storage.prefixes
             where lower(prefixes.name) like lower($2 || $3) || ''%''
               and bucket_id = $4
               and level = $1
           order by name ' || v_sort_order || '
     )
     (select name,
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[level] as "name",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where lower(objects.name) like lower($2 || $3) || ''%''
       and bucket_id = $4
       and level = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$_$;


ALTER FUNCTION "storage"."search_v1_optimised"("prefix" "text", "bucketname" "text", "limits" integer, "levels" integer, "offsets" integer, "search" "text", "sortcolumn" "text", "sortorder" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "start_after" "text" DEFAULT ''::"text", "sort_order" "text" DEFAULT 'asc'::"text", "sort_column" "text" DEFAULT 'name'::"text", "sort_column_after" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    sort_col text;
    sort_ord text;
    cursor_op text;
    cursor_expr text;
    sort_expr text;
BEGIN
    -- Validate sort_order
    sort_ord := lower(sort_order);
    IF sort_ord NOT IN ('asc', 'desc') THEN
        sort_ord := 'asc';
    END IF;

    -- Determine cursor comparison operator
    IF sort_ord = 'asc' THEN
        cursor_op := '>';
    ELSE
        cursor_op := '<';
    END IF;
    
    sort_col := lower(sort_column);
    -- Validate sort column  
    IF sort_col IN ('updated_at', 'created_at') THEN
        cursor_expr := format(
            '($5 = '''' OR ROW(date_trunc(''milliseconds'', %I), name COLLATE "C") %s ROW(COALESCE(NULLIF($6, '''')::timestamptz, ''epoch''::timestamptz), $5))',
            sort_col, cursor_op
        );
        sort_expr := format(
            'COALESCE(date_trunc(''milliseconds'', %I), ''epoch''::timestamptz) %s, name COLLATE "C" %s',
            sort_col, sort_ord, sort_ord
        );
    ELSE
        cursor_expr := format('($5 = '''' OR name COLLATE "C" %s $5)', cursor_op);
        sort_expr := format('name COLLATE "C" %s', sort_ord);
    END IF;

    RETURN QUERY EXECUTE format(
        $sql$
        SELECT * FROM (
            (
                SELECT
                    split_part(name, '/', $4) AS key,
                    name,
                    NULL::uuid AS id,
                    updated_at,
                    created_at,
                    NULL::timestamptz AS last_accessed_at,
                    NULL::jsonb AS metadata
                FROM storage.prefixes
                WHERE name COLLATE "C" LIKE $1 || '%%'
                    AND bucket_id = $2
                    AND level = $4
                    AND %s
                ORDER BY %s
                LIMIT $3
            )
            UNION ALL
            (
                SELECT
                    split_part(name, '/', $4) AS key,
                    name,
                    id,
                    updated_at,
                    created_at,
                    last_accessed_at,
                    metadata
                FROM storage.objects
                WHERE name COLLATE "C" LIKE $1 || '%%'
                    AND bucket_id = $2
                    AND level = $4
                    AND %s
                ORDER BY %s
                LIMIT $3
            )
        ) obj
        ORDER BY %s
        LIMIT $3
        $sql$,
        cursor_expr,    -- prefixes WHERE
        sort_expr,      -- prefixes ORDER BY
        cursor_expr,    -- objects WHERE
        sort_expr,      -- objects ORDER BY
        sort_expr       -- final ORDER BY
    )
    USING prefix, bucket_name, limits, levels, start_after, sort_column_after;
END;
$_$;


ALTER FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer, "levels" integer, "start_after" "text", "sort_order" "text", "sort_column" "text", "sort_column_after" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


ALTER FUNCTION "storage"."update_updated_at_column"() OWNER TO "supabase_storage_admin";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "auth"."audit_log_entries" (
    "instance_id" "uuid",
    "id" "uuid" NOT NULL,
    "payload" json,
    "created_at" timestamp with time zone,
    "ip_address" character varying(64) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE "auth"."audit_log_entries" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."audit_log_entries" IS 'Auth: Audit trail for user actions.';



CREATE TABLE IF NOT EXISTS "auth"."flow_state" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid",
    "auth_code" "text" NOT NULL,
    "code_challenge_method" "auth"."code_challenge_method" NOT NULL,
    "code_challenge" "text" NOT NULL,
    "provider_type" "text" NOT NULL,
    "provider_access_token" "text",
    "provider_refresh_token" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "authentication_method" "text" NOT NULL,
    "auth_code_issued_at" timestamp with time zone
);


ALTER TABLE "auth"."flow_state" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."flow_state" IS 'stores metadata for pkce logins';



CREATE TABLE IF NOT EXISTS "auth"."identities" (
    "provider_id" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "identity_data" "jsonb" NOT NULL,
    "provider" "text" NOT NULL,
    "last_sign_in_at" timestamp with time zone,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "email" "text" GENERATED ALWAYS AS ("lower"(("identity_data" ->> 'email'::"text"))) STORED,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL
);


ALTER TABLE "auth"."identities" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."identities" IS 'Auth: Stores identities associated to a user.';



COMMENT ON COLUMN "auth"."identities"."email" IS 'Auth: Email is a generated column that references the optional email property in the identity_data';



CREATE TABLE IF NOT EXISTS "auth"."instances" (
    "id" "uuid" NOT NULL,
    "uuid" "uuid",
    "raw_base_config" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
);


ALTER TABLE "auth"."instances" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."instances" IS 'Auth: Manages users across multiple sites.';



CREATE TABLE IF NOT EXISTS "auth"."mfa_amr_claims" (
    "session_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "authentication_method" "text" NOT NULL,
    "id" "uuid" NOT NULL
);


ALTER TABLE "auth"."mfa_amr_claims" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_amr_claims" IS 'auth: stores authenticator method reference claims for multi factor authentication';



CREATE TABLE IF NOT EXISTS "auth"."mfa_challenges" (
    "id" "uuid" NOT NULL,
    "factor_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "verified_at" timestamp with time zone,
    "ip_address" "inet" NOT NULL,
    "otp_code" "text",
    "web_authn_session_data" "jsonb"
);


ALTER TABLE "auth"."mfa_challenges" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_challenges" IS 'auth: stores metadata about challenge requests made';



CREATE TABLE IF NOT EXISTS "auth"."mfa_factors" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "friendly_name" "text",
    "factor_type" "auth"."factor_type" NOT NULL,
    "status" "auth"."factor_status" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "secret" "text",
    "phone" "text",
    "last_challenged_at" timestamp with time zone,
    "web_authn_credential" "jsonb",
    "web_authn_aaguid" "uuid",
    "last_webauthn_challenge_data" "jsonb"
);


ALTER TABLE "auth"."mfa_factors" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_factors" IS 'auth: stores metadata about factors';



COMMENT ON COLUMN "auth"."mfa_factors"."last_webauthn_challenge_data" IS 'Stores the latest WebAuthn challenge data including attestation/assertion for customer verification';



CREATE TABLE IF NOT EXISTS "auth"."oauth_authorizations" (
    "id" "uuid" NOT NULL,
    "authorization_id" "text" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "redirect_uri" "text" NOT NULL,
    "scope" "text" NOT NULL,
    "state" "text",
    "resource" "text",
    "code_challenge" "text",
    "code_challenge_method" "auth"."code_challenge_method",
    "response_type" "auth"."oauth_response_type" DEFAULT 'code'::"auth"."oauth_response_type" NOT NULL,
    "status" "auth"."oauth_authorization_status" DEFAULT 'pending'::"auth"."oauth_authorization_status" NOT NULL,
    "authorization_code" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '00:03:00'::interval) NOT NULL,
    "approved_at" timestamp with time zone,
    "nonce" "text",
    CONSTRAINT "oauth_authorizations_authorization_code_length" CHECK (("char_length"("authorization_code") <= 255)),
    CONSTRAINT "oauth_authorizations_code_challenge_length" CHECK (("char_length"("code_challenge") <= 128)),
    CONSTRAINT "oauth_authorizations_expires_at_future" CHECK (("expires_at" > "created_at")),
    CONSTRAINT "oauth_authorizations_nonce_length" CHECK (("char_length"("nonce") <= 255)),
    CONSTRAINT "oauth_authorizations_redirect_uri_length" CHECK (("char_length"("redirect_uri") <= 2048)),
    CONSTRAINT "oauth_authorizations_resource_length" CHECK (("char_length"("resource") <= 2048)),
    CONSTRAINT "oauth_authorizations_scope_length" CHECK (("char_length"("scope") <= 4096)),
    CONSTRAINT "oauth_authorizations_state_length" CHECK (("char_length"("state") <= 4096))
);


ALTER TABLE "auth"."oauth_authorizations" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."oauth_client_states" (
    "id" "uuid" NOT NULL,
    "provider_type" "text" NOT NULL,
    "code_verifier" "text",
    "created_at" timestamp with time zone NOT NULL
);


ALTER TABLE "auth"."oauth_client_states" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."oauth_client_states" IS 'Stores OAuth states for third-party provider authentication flows where Supabase acts as the OAuth client.';



CREATE TABLE IF NOT EXISTS "auth"."oauth_clients" (
    "id" "uuid" NOT NULL,
    "client_secret_hash" "text",
    "registration_type" "auth"."oauth_registration_type" NOT NULL,
    "redirect_uris" "text" NOT NULL,
    "grant_types" "text" NOT NULL,
    "client_name" "text",
    "client_uri" "text",
    "logo_uri" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "client_type" "auth"."oauth_client_type" DEFAULT 'confidential'::"auth"."oauth_client_type" NOT NULL,
    CONSTRAINT "oauth_clients_client_name_length" CHECK (("char_length"("client_name") <= 1024)),
    CONSTRAINT "oauth_clients_client_uri_length" CHECK (("char_length"("client_uri") <= 2048)),
    CONSTRAINT "oauth_clients_logo_uri_length" CHECK (("char_length"("logo_uri") <= 2048))
);


ALTER TABLE "auth"."oauth_clients" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."oauth_consents" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "scopes" "text" NOT NULL,
    "granted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revoked_at" timestamp with time zone,
    CONSTRAINT "oauth_consents_revoked_after_granted" CHECK ((("revoked_at" IS NULL) OR ("revoked_at" >= "granted_at"))),
    CONSTRAINT "oauth_consents_scopes_length" CHECK (("char_length"("scopes") <= 2048)),
    CONSTRAINT "oauth_consents_scopes_not_empty" CHECK (("char_length"(TRIM(BOTH FROM "scopes")) > 0))
);


ALTER TABLE "auth"."oauth_consents" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."one_time_tokens" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "token_type" "auth"."one_time_token_type" NOT NULL,
    "token_hash" "text" NOT NULL,
    "relates_to" "text" NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "one_time_tokens_token_hash_check" CHECK (("char_length"("token_hash") > 0))
);


ALTER TABLE "auth"."one_time_tokens" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."refresh_tokens" (
    "instance_id" "uuid",
    "id" bigint NOT NULL,
    "token" character varying(255),
    "user_id" character varying(255),
    "revoked" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "parent" character varying(255),
    "session_id" "uuid"
);


ALTER TABLE "auth"."refresh_tokens" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."refresh_tokens" IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';



CREATE SEQUENCE IF NOT EXISTS "auth"."refresh_tokens_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "auth"."refresh_tokens_id_seq" OWNER TO "supabase_auth_admin";


ALTER SEQUENCE "auth"."refresh_tokens_id_seq" OWNED BY "auth"."refresh_tokens"."id";



CREATE TABLE IF NOT EXISTS "auth"."saml_providers" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "entity_id" "text" NOT NULL,
    "metadata_xml" "text" NOT NULL,
    "metadata_url" "text",
    "attribute_mapping" "jsonb",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "name_id_format" "text",
    CONSTRAINT "entity_id not empty" CHECK (("char_length"("entity_id") > 0)),
    CONSTRAINT "metadata_url not empty" CHECK ((("metadata_url" = NULL::"text") OR ("char_length"("metadata_url") > 0))),
    CONSTRAINT "metadata_xml not empty" CHECK (("char_length"("metadata_xml") > 0))
);


ALTER TABLE "auth"."saml_providers" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."saml_providers" IS 'Auth: Manages SAML Identity Provider connections.';



CREATE TABLE IF NOT EXISTS "auth"."saml_relay_states" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "request_id" "text" NOT NULL,
    "for_email" "text",
    "redirect_to" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "flow_state_id" "uuid",
    CONSTRAINT "request_id not empty" CHECK (("char_length"("request_id") > 0))
);


ALTER TABLE "auth"."saml_relay_states" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."saml_relay_states" IS 'Auth: Contains SAML Relay State information for each Service Provider initiated login.';



CREATE TABLE IF NOT EXISTS "auth"."schema_migrations" (
    "version" character varying(255) NOT NULL
);


ALTER TABLE "auth"."schema_migrations" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."schema_migrations" IS 'Auth: Manages updates to the auth system.';



CREATE TABLE IF NOT EXISTS "auth"."sessions" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "factor_id" "uuid",
    "aal" "auth"."aal_level",
    "not_after" timestamp with time zone,
    "refreshed_at" timestamp without time zone,
    "user_agent" "text",
    "ip" "inet",
    "tag" "text",
    "oauth_client_id" "uuid",
    "refresh_token_hmac_key" "text",
    "refresh_token_counter" bigint,
    "scopes" "text",
    CONSTRAINT "sessions_scopes_length" CHECK (("char_length"("scopes") <= 4096))
);


ALTER TABLE "auth"."sessions" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sessions" IS 'Auth: Stores session data associated to a user.';



COMMENT ON COLUMN "auth"."sessions"."not_after" IS 'Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.';



COMMENT ON COLUMN "auth"."sessions"."refresh_token_hmac_key" IS 'Holds a HMAC-SHA256 key used to sign refresh tokens for this session.';



COMMENT ON COLUMN "auth"."sessions"."refresh_token_counter" IS 'Holds the ID (counter) of the last issued refresh token.';



CREATE TABLE IF NOT EXISTS "auth"."sso_domains" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "domain" "text" NOT NULL,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    CONSTRAINT "domain not empty" CHECK (("char_length"("domain") > 0))
);


ALTER TABLE "auth"."sso_domains" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sso_domains" IS 'Auth: Manages SSO email address domain mapping to an SSO Identity Provider.';



CREATE TABLE IF NOT EXISTS "auth"."sso_providers" (
    "id" "uuid" NOT NULL,
    "resource_id" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "disabled" boolean,
    CONSTRAINT "resource_id not empty" CHECK ((("resource_id" = NULL::"text") OR ("char_length"("resource_id") > 0)))
);


ALTER TABLE "auth"."sso_providers" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sso_providers" IS 'Auth: Manages SSO identity provider information; see saml_providers for SAML.';



COMMENT ON COLUMN "auth"."sso_providers"."resource_id" IS 'Auth: Uniquely identifies a SSO provider according to a user-chosen resource ID (case insensitive), useful in infrastructure as code.';



CREATE TABLE IF NOT EXISTS "auth"."users" (
    "instance_id" "uuid",
    "id" "uuid" NOT NULL,
    "aud" character varying(255),
    "role" character varying(255),
    "email" character varying(255),
    "encrypted_password" character varying(255),
    "email_confirmed_at" timestamp with time zone,
    "invited_at" timestamp with time zone,
    "confirmation_token" character varying(255),
    "confirmation_sent_at" timestamp with time zone,
    "recovery_token" character varying(255),
    "recovery_sent_at" timestamp with time zone,
    "email_change_token_new" character varying(255),
    "email_change" character varying(255),
    "email_change_sent_at" timestamp with time zone,
    "last_sign_in_at" timestamp with time zone,
    "raw_app_meta_data" "jsonb",
    "raw_user_meta_data" "jsonb",
    "is_super_admin" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "phone" "text" DEFAULT NULL::character varying,
    "phone_confirmed_at" timestamp with time zone,
    "phone_change" "text" DEFAULT ''::character varying,
    "phone_change_token" character varying(255) DEFAULT ''::character varying,
    "phone_change_sent_at" timestamp with time zone,
    "confirmed_at" timestamp with time zone GENERATED ALWAYS AS (LEAST("email_confirmed_at", "phone_confirmed_at")) STORED,
    "email_change_token_current" character varying(255) DEFAULT ''::character varying,
    "email_change_confirm_status" smallint DEFAULT 0,
    "banned_until" timestamp with time zone,
    "reauthentication_token" character varying(255) DEFAULT ''::character varying,
    "reauthentication_sent_at" timestamp with time zone,
    "is_sso_user" boolean DEFAULT false NOT NULL,
    "deleted_at" timestamp with time zone,
    "is_anonymous" boolean DEFAULT false NOT NULL,
    CONSTRAINT "users_email_change_confirm_status_check" CHECK ((("email_change_confirm_status" >= 0) AND ("email_change_confirm_status" <= 2)))
);


ALTER TABLE "auth"."users" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."users" IS 'Auth: Stores user login data within a secure schema.';



COMMENT ON COLUMN "auth"."users"."is_sso_user" IS 'Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.';



CREATE TABLE IF NOT EXISTS "public"."account_deletion_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."account_deletion_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."booking_payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "amount_cents" integer NOT NULL,
    "from_covered_until" timestamp with time zone,
    "to_covered_until" timestamp with time zone,
    "from_duration_key" "text",
    "to_duration_key" "text",
    "paid_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "payment_reference" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "booking_payments_amount_cents_check" CHECK (("amount_cents" >= 0)),
    CONSTRAINT "booking_payments_kind_check" CHECK (("kind" = ANY (ARRAY['base'::"text", 'late_fee'::"text"])))
);


ALTER TABLE "public"."booking_payments" OWNER TO "postgres";


COMMENT ON TABLE "public"."booking_payments" IS 'Storico pagamenti prenotazione. Ogni estensione crea una riga (late_fee).';



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
    "end_date" "date",
    "dropoff_planned_at" timestamp with time zone,
    "pickup_planned_at" timestamp with time zone,
    "dropoff_effective_at" timestamp with time zone,
    "pickup_effective_at" timestamp with time zone,
    "reject_reason" "text",
    "rejected_at" timestamp with time zone,
    "qr_token" "uuid",
    "booking_code" "text" DEFAULT "public"."generate_booking_code"() NOT NULL,
    "base_used_u" integer DEFAULT 0 NOT NULL,
    "extra_used_s" integer DEFAULT 0 NOT NULL,
    "extra_used_m" integer DEFAULT 0 NOT NULL,
    "extra_used_l" integer DEFAULT 0 NOT NULL,
    "late_fee_required" boolean DEFAULT false NOT NULL,
    "late_fee_amount_cents" integer,
    "late_fee_paid_at" timestamp with time zone,
    "pickup_pending_at" timestamp with time zone,
    "late_fee_covered_until" timestamp with time zone,
    "end_date_requested" "date",
    "end_time_requested" time without time zone,
    "covered_until" timestamp with time zone,
    "total_paid_cents" integer DEFAULT 0 NOT NULL,
    "cancelled_at" timestamp with time zone,
    "cancel_reason" "text",
    CONSTRAINT "partner_bookings_booking_code_format_check" CHECK (("booking_code" ~ '^BD[0-9A-F]{10}$'::"text")),
    CONSTRAINT "partner_bookings_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'confirmed'::"text", 'in_store'::"text", 'completed'::"text", 'cancelled'::"text", 'cancelled_by_user'::"text", 'cancelled_by_partner'::"text", 'expired'::"text"])))
);


ALTER TABLE "public"."partner_bookings" OWNER TO "postgres";


COMMENT ON COLUMN "public"."partner_bookings"."late_fee_amount_cents" IS 'Importo supplemento pagato (in centesimi).';



COMMENT ON COLUMN "public"."partner_bookings"."late_fee_paid_at" IS 'Quando il cliente paga il supplemento per ritardo (mock).';



COMMENT ON COLUMN "public"."partner_bookings"."late_fee_covered_until" IS 'Fino a quando il pagamento copre il deposito (es. prossimo cutoff).';



COMMENT ON COLUMN "public"."partner_bookings"."covered_until" IS 'Fino a quando la prenotazione è coperta/pagata (scadenza fascia corrente).';



COMMENT ON COLUMN "public"."partner_bookings"."total_paid_cents" IS 'Totale pagato finora (base + supplementi), in centesimi.';



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
    "message" "text",
    "admin_note" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reviewed_at" timestamp with time zone,
    "reviewed_by" "uuid",
    "contract_signed_url" "text",
    "contract_signed_at" timestamp with time zone,
    "docs_approved_at" timestamp with time zone,
    "payment_required" boolean DEFAULT false NOT NULL,
    "paid_at" timestamp with time zone,
    "payment_reference" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status" "public"."partner_request_status" DEFAULT 'draft'::"public"."partner_request_status" NOT NULL,
    "reject_reason" "text"
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
    "accepting_bookings" boolean DEFAULT true NOT NULL,
    "base_capacity_u" integer DEFAULT 0 NOT NULL,
    "extra_capacity_s" integer DEFAULT 0 NOT NULL,
    "extra_capacity_m" integer DEFAULT 0 NOT NULL,
    "extra_capacity_l" integer DEFAULT 0 NOT NULL,
    "accept_s" boolean DEFAULT true NOT NULL,
    "accept_m" boolean DEFAULT true NOT NULL,
    "accept_l" boolean DEFAULT true NOT NULL,
    "activated_at" timestamp with time zone,
    "daily_cutoff_time" time without time zone,
    CONSTRAINT "partners_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."partners" OWNER TO "postgres";


COMMENT ON TABLE "public"."partners" IS 'Attività partner collegate a auth.users (owner_id).';



COMMENT ON COLUMN "public"."partners"."daily_cutoff_time" IS 'Orario cutoff giornaliero per tariffa/estensioni. Es: 20:00 per bar; 23:59 per 24h.';



CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "full_name" "text",
    "avatar_url" "text",
    "kyc_status" "text" DEFAULT 'none'::"text" NOT NULL,
    "role" "text" DEFAULT 'user'::"text" NOT NULL,
    CONSTRAINT "user_profiles_kyc_status_check" CHECK (("kyc_status" = ANY (ARRAY['none'::"text", 'basic'::"text", 'verified'::"text"]))),
    CONSTRAINT "user_profiles_role_check" CHECK (("role" = ANY (ARRAY['user'::"text", 'partner_candidate'::"text", 'partner'::"text", 'admin'::"text"])))
);


ALTER TABLE "public"."user_profiles" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_profiles" IS 'Profili utente applicativi; PK = auth.users.id. Ruoli: user/partner/admin.';



CREATE TABLE IF NOT EXISTS "storage"."buckets" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "public" boolean DEFAULT false,
    "avif_autodetection" boolean DEFAULT false,
    "file_size_limit" bigint,
    "allowed_mime_types" "text"[],
    "owner_id" "text",
    "type" "storage"."buckettype" DEFAULT 'STANDARD'::"storage"."buckettype" NOT NULL
);


ALTER TABLE "storage"."buckets" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."buckets"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."buckets_analytics" (
    "name" "text" NOT NULL,
    "type" "storage"."buckettype" DEFAULT 'ANALYTICS'::"storage"."buckettype" NOT NULL,
    "format" "text" DEFAULT 'ICEBERG'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "storage"."buckets_analytics" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."buckets_vectors" (
    "id" "text" NOT NULL,
    "type" "storage"."buckettype" DEFAULT 'VECTOR'::"storage"."buckettype" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."buckets_vectors" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."migrations" (
    "id" integer NOT NULL,
    "name" character varying(100) NOT NULL,
    "hash" character varying(40) NOT NULL,
    "executed_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "storage"."migrations" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."objects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "bucket_id" "text",
    "name" "text",
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_accessed_at" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb",
    "path_tokens" "text"[] GENERATED ALWAYS AS ("string_to_array"("name", '/'::"text")) STORED,
    "version" "text",
    "owner_id" "text",
    "user_metadata" "jsonb",
    "level" integer
);


ALTER TABLE "storage"."objects" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."objects"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."prefixes" (
    "bucket_id" "text" NOT NULL,
    "name" "text" NOT NULL COLLATE "pg_catalog"."C",
    "level" integer GENERATED ALWAYS AS ("storage"."get_level"("name")) STORED NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "storage"."prefixes" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads" (
    "id" "text" NOT NULL,
    "in_progress_size" bigint DEFAULT 0 NOT NULL,
    "upload_signature" "text" NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "version" "text" NOT NULL,
    "owner_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_metadata" "jsonb"
);


ALTER TABLE "storage"."s3_multipart_uploads" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads_parts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "upload_id" "text" NOT NULL,
    "size" bigint DEFAULT 0 NOT NULL,
    "part_number" integer NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "etag" "text" NOT NULL,
    "owner_id" "text",
    "version" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."s3_multipart_uploads_parts" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."vector_indexes" (
    "id" "text" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL COLLATE "pg_catalog"."C",
    "bucket_id" "text" NOT NULL,
    "data_type" "text" NOT NULL,
    "dimension" integer NOT NULL,
    "distance_metric" "text" NOT NULL,
    "metadata_configuration" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."vector_indexes" OWNER TO "supabase_storage_admin";


ALTER TABLE ONLY "auth"."refresh_tokens" ALTER COLUMN "id" SET DEFAULT "nextval"('"auth"."refresh_tokens_id_seq"'::"regclass");



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "amr_id_pk" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."audit_log_entries"
    ADD CONSTRAINT "audit_log_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."flow_state"
    ADD CONSTRAINT "flow_state_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_provider_id_provider_unique" UNIQUE ("provider_id", "provider");



ALTER TABLE ONLY "auth"."instances"
    ADD CONSTRAINT "instances_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "mfa_amr_claims_session_id_authentication_method_pkey" UNIQUE ("session_id", "authentication_method");



ALTER TABLE ONLY "auth"."mfa_challenges"
    ADD CONSTRAINT "mfa_challenges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_last_challenged_at_key" UNIQUE ("last_challenged_at");



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_authorization_code_key" UNIQUE ("authorization_code");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_authorization_id_key" UNIQUE ("authorization_id");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_client_states"
    ADD CONSTRAINT "oauth_client_states_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_clients"
    ADD CONSTRAINT "oauth_clients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_user_client_unique" UNIQUE ("user_id", "client_id");



ALTER TABLE ONLY "auth"."one_time_tokens"
    ADD CONSTRAINT "one_time_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_token_unique" UNIQUE ("token");



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_entity_id_key" UNIQUE ("entity_id");



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."schema_migrations"
    ADD CONSTRAINT "schema_migrations_pkey" PRIMARY KEY ("version");



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."sso_domains"
    ADD CONSTRAINT "sso_domains_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."sso_providers"
    ADD CONSTRAINT "sso_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."users"
    ADD CONSTRAINT "users_phone_key" UNIQUE ("phone");



ALTER TABLE ONLY "auth"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."account_deletion_logs"
    ADD CONSTRAINT "account_deletion_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."booking_payments"
    ADD CONSTRAINT "booking_payments_pkey" PRIMARY KEY ("id");



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



ALTER TABLE ONLY "storage"."buckets_analytics"
    ADD CONSTRAINT "buckets_analytics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets"
    ADD CONSTRAINT "buckets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets_vectors"
    ADD CONSTRAINT "buckets_vectors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_name_key" UNIQUE ("name");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."prefixes"
    ADD CONSTRAINT "prefixes_pkey" PRIMARY KEY ("bucket_id", "level", "name");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."vector_indexes"
    ADD CONSTRAINT "vector_indexes_pkey" PRIMARY KEY ("id");



CREATE INDEX "audit_logs_instance_id_idx" ON "auth"."audit_log_entries" USING "btree" ("instance_id");



CREATE UNIQUE INDEX "confirmation_token_idx" ON "auth"."users" USING "btree" ("confirmation_token") WHERE (("confirmation_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE UNIQUE INDEX "email_change_token_current_idx" ON "auth"."users" USING "btree" ("email_change_token_current") WHERE (("email_change_token_current")::"text" !~ '^[0-9 ]*$'::"text");



CREATE UNIQUE INDEX "email_change_token_new_idx" ON "auth"."users" USING "btree" ("email_change_token_new") WHERE (("email_change_token_new")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "factor_id_created_at_idx" ON "auth"."mfa_factors" USING "btree" ("user_id", "created_at");



CREATE INDEX "flow_state_created_at_idx" ON "auth"."flow_state" USING "btree" ("created_at" DESC);



CREATE INDEX "identities_email_idx" ON "auth"."identities" USING "btree" ("email" "text_pattern_ops");



COMMENT ON INDEX "auth"."identities_email_idx" IS 'Auth: Ensures indexed queries on the email column';



CREATE INDEX "identities_user_id_idx" ON "auth"."identities" USING "btree" ("user_id");



CREATE INDEX "idx_auth_code" ON "auth"."flow_state" USING "btree" ("auth_code");



CREATE INDEX "idx_oauth_client_states_created_at" ON "auth"."oauth_client_states" USING "btree" ("created_at");



CREATE INDEX "idx_user_id_auth_method" ON "auth"."flow_state" USING "btree" ("user_id", "authentication_method");



CREATE INDEX "mfa_challenge_created_at_idx" ON "auth"."mfa_challenges" USING "btree" ("created_at" DESC);



CREATE UNIQUE INDEX "mfa_factors_user_friendly_name_unique" ON "auth"."mfa_factors" USING "btree" ("friendly_name", "user_id") WHERE (TRIM(BOTH FROM "friendly_name") <> ''::"text");



CREATE INDEX "mfa_factors_user_id_idx" ON "auth"."mfa_factors" USING "btree" ("user_id");



CREATE INDEX "oauth_auth_pending_exp_idx" ON "auth"."oauth_authorizations" USING "btree" ("expires_at") WHERE ("status" = 'pending'::"auth"."oauth_authorization_status");



CREATE INDEX "oauth_clients_deleted_at_idx" ON "auth"."oauth_clients" USING "btree" ("deleted_at");



CREATE INDEX "oauth_consents_active_client_idx" ON "auth"."oauth_consents" USING "btree" ("client_id") WHERE ("revoked_at" IS NULL);



CREATE INDEX "oauth_consents_active_user_client_idx" ON "auth"."oauth_consents" USING "btree" ("user_id", "client_id") WHERE ("revoked_at" IS NULL);



CREATE INDEX "oauth_consents_user_order_idx" ON "auth"."oauth_consents" USING "btree" ("user_id", "granted_at" DESC);



CREATE INDEX "one_time_tokens_relates_to_hash_idx" ON "auth"."one_time_tokens" USING "hash" ("relates_to");



CREATE INDEX "one_time_tokens_token_hash_hash_idx" ON "auth"."one_time_tokens" USING "hash" ("token_hash");



CREATE UNIQUE INDEX "one_time_tokens_user_id_token_type_key" ON "auth"."one_time_tokens" USING "btree" ("user_id", "token_type");



CREATE UNIQUE INDEX "reauthentication_token_idx" ON "auth"."users" USING "btree" ("reauthentication_token") WHERE (("reauthentication_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE UNIQUE INDEX "recovery_token_idx" ON "auth"."users" USING "btree" ("recovery_token") WHERE (("recovery_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "refresh_tokens_instance_id_idx" ON "auth"."refresh_tokens" USING "btree" ("instance_id");



CREATE INDEX "refresh_tokens_instance_id_user_id_idx" ON "auth"."refresh_tokens" USING "btree" ("instance_id", "user_id");



CREATE INDEX "refresh_tokens_parent_idx" ON "auth"."refresh_tokens" USING "btree" ("parent");



CREATE INDEX "refresh_tokens_session_id_revoked_idx" ON "auth"."refresh_tokens" USING "btree" ("session_id", "revoked");



CREATE INDEX "refresh_tokens_updated_at_idx" ON "auth"."refresh_tokens" USING "btree" ("updated_at" DESC);



CREATE INDEX "saml_providers_sso_provider_id_idx" ON "auth"."saml_providers" USING "btree" ("sso_provider_id");



CREATE INDEX "saml_relay_states_created_at_idx" ON "auth"."saml_relay_states" USING "btree" ("created_at" DESC);



CREATE INDEX "saml_relay_states_for_email_idx" ON "auth"."saml_relay_states" USING "btree" ("for_email");



CREATE INDEX "saml_relay_states_sso_provider_id_idx" ON "auth"."saml_relay_states" USING "btree" ("sso_provider_id");



CREATE INDEX "sessions_not_after_idx" ON "auth"."sessions" USING "btree" ("not_after" DESC);



CREATE INDEX "sessions_oauth_client_id_idx" ON "auth"."sessions" USING "btree" ("oauth_client_id");



CREATE INDEX "sessions_user_id_idx" ON "auth"."sessions" USING "btree" ("user_id");



CREATE UNIQUE INDEX "sso_domains_domain_idx" ON "auth"."sso_domains" USING "btree" ("lower"("domain"));



CREATE INDEX "sso_domains_sso_provider_id_idx" ON "auth"."sso_domains" USING "btree" ("sso_provider_id");



CREATE UNIQUE INDEX "sso_providers_resource_id_idx" ON "auth"."sso_providers" USING "btree" ("lower"("resource_id"));



CREATE INDEX "sso_providers_resource_id_pattern_idx" ON "auth"."sso_providers" USING "btree" ("resource_id" "text_pattern_ops");



CREATE UNIQUE INDEX "unique_phone_factor_per_user" ON "auth"."mfa_factors" USING "btree" ("user_id", "phone");



CREATE INDEX "user_id_created_at_idx" ON "auth"."sessions" USING "btree" ("user_id", "created_at");



CREATE UNIQUE INDEX "users_email_partial_key" ON "auth"."users" USING "btree" ("email") WHERE ("is_sso_user" = false);



COMMENT ON INDEX "auth"."users_email_partial_key" IS 'Auth: A partial unique index that applies only when is_sso_user is false';



CREATE INDEX "users_instance_id_email_idx" ON "auth"."users" USING "btree" ("instance_id", "lower"(("email")::"text"));



CREATE INDEX "users_instance_id_idx" ON "auth"."users" USING "btree" ("instance_id");



CREATE INDEX "users_is_anonymous_idx" ON "auth"."users" USING "btree" ("is_anonymous");



CREATE INDEX "idx_booking_payments_booking_id" ON "public"."booking_payments" USING "btree" ("booking_id");



CREATE INDEX "idx_booking_payments_paid_at" ON "public"."booking_payments" USING "btree" ("paid_at");



CREATE INDEX "idx_partner_bookings_covered_until" ON "public"."partner_bookings" USING "btree" ("covered_until");



CREATE UNIQUE INDEX "idx_partner_bookings_qr_token" ON "public"."partner_bookings" USING "btree" ("qr_token");



CREATE INDEX "idx_partner_photos_partner_id" ON "public"."partner_photos" USING "btree" ("partner_id");



CREATE INDEX "idx_partner_requests_user" ON "public"."partner_requests" USING "btree" ("user_id");



CREATE INDEX "idx_partners_accepting_bookings" ON "public"."partners" USING "btree" ("accepting_bookings");



CREATE INDEX "idx_partners_is_active" ON "public"."partners" USING "btree" ("is_active");



CREATE INDEX "idx_partners_owner_id" ON "public"."partners" USING "btree" ("owner_id");



CREATE INDEX "idx_partners_status" ON "public"."partners" USING "btree" ("status");



CREATE INDEX "idx_pb_interval_gist" ON "public"."partner_bookings" USING "gist" ("tstzrange"("dropoff_planned_at", "pickup_planned_at", '[)'::"text")) WHERE (("dropoff_planned_at" IS NOT NULL) AND ("pickup_planned_at" IS NOT NULL));



CREATE INDEX "idx_pb_partner_status" ON "public"."partner_bookings" USING "btree" ("partner_id", "status");



CREATE UNIQUE INDEX "partner_bookings_booking_code_key" ON "public"."partner_bookings" USING "btree" ("booking_code");



CREATE UNIQUE INDEX "partners_owner_id_key" ON "public"."partners" USING "btree" ("owner_id");



CREATE UNIQUE INDEX "ux_booking_payments_base_once" ON "public"."booking_payments" USING "btree" ("booking_id") WHERE ("kind" = 'base'::"text");



CREATE UNIQUE INDEX "ux_partner_requests_active_per_user" ON "public"."partner_requests" USING "btree" ("user_id") WHERE ("status" = ANY (ARRAY['draft'::"public"."partner_request_status", 'submitted'::"public"."partner_request_status", 'awaiting_payment'::"public"."partner_request_status"]));



CREATE UNIQUE INDEX "bname" ON "storage"."buckets" USING "btree" ("name");



CREATE UNIQUE INDEX "bucketid_objname" ON "storage"."objects" USING "btree" ("bucket_id", "name");



CREATE UNIQUE INDEX "buckets_analytics_unique_name_idx" ON "storage"."buckets_analytics" USING "btree" ("name") WHERE ("deleted_at" IS NULL);



CREATE INDEX "idx_multipart_uploads_list" ON "storage"."s3_multipart_uploads" USING "btree" ("bucket_id", "key", "created_at");



CREATE UNIQUE INDEX "idx_name_bucket_level_unique" ON "storage"."objects" USING "btree" ("name" COLLATE "C", "bucket_id", "level");



CREATE INDEX "idx_objects_bucket_id_name" ON "storage"."objects" USING "btree" ("bucket_id", "name" COLLATE "C");



CREATE INDEX "idx_objects_lower_name" ON "storage"."objects" USING "btree" (("path_tokens"["level"]), "lower"("name") "text_pattern_ops", "bucket_id", "level");



CREATE INDEX "idx_prefixes_lower_name" ON "storage"."prefixes" USING "btree" ("bucket_id", "level", (("string_to_array"("name", '/'::"text"))["level"]), "lower"("name") "text_pattern_ops");



CREATE INDEX "name_prefix_search" ON "storage"."objects" USING "btree" ("name" "text_pattern_ops");



CREATE UNIQUE INDEX "objects_bucket_id_level_idx" ON "storage"."objects" USING "btree" ("bucket_id", "level", "name" COLLATE "C");



CREATE UNIQUE INDEX "vector_indexes_name_bucket_id_idx" ON "storage"."vector_indexes" USING "btree" ("name", "bucket_id");



CREATE OR REPLACE TRIGGER "on_auth_user_otp_verified" AFTER UPDATE ON "auth"."users" FOR EACH ROW WHEN (("old"."raw_user_meta_data" IS DISTINCT FROM "new"."raw_user_meta_data")) EXECUTE FUNCTION "public"."handle_otp_verified_user"();



CREATE OR REPLACE TRIGGER "set_partners_updated_at" BEFORE UPDATE ON "public"."partners" FOR EACH ROW EXECUTE FUNCTION "public"."set_partners_updated_at"();



CREATE OR REPLACE TRIGGER "trg_booking_payments_after_insert" AFTER INSERT ON "public"."booking_payments" FOR EACH ROW EXECUTE FUNCTION "public"."on_booking_payment_insert"();



CREATE OR REPLACE TRIGGER "trg_partner_bookings_accepting_guard" BEFORE INSERT ON "public"."partner_bookings" FOR EACH ROW EXECUTE FUNCTION "public"."guard_partner_booking_accepting"();



CREATE OR REPLACE TRIGGER "trg_partner_bookings_cancel_guard" BEFORE INSERT OR UPDATE ON "public"."partner_bookings" FOR EACH ROW EXECUTE FUNCTION "public"."guard_partner_booking_partner_cancel"();



CREATE OR REPLACE TRIGGER "trg_partner_bookings_updated_at" BEFORE UPDATE ON "public"."partner_bookings" FOR EACH ROW EXECUTE FUNCTION "public"."set_timestamp_updated_at"();



CREATE OR REPLACE TRIGGER "trg_partner_requests_touch" BEFORE UPDATE ON "public"."partner_requests" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_partners_set_updated_at" BEFORE UPDATE ON "public"."partners" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_set_booking_qr_token" BEFORE INSERT ON "public"."partner_bookings" FOR EACH ROW EXECUTE FUNCTION "public"."set_booking_qr_token"();



CREATE OR REPLACE TRIGGER "trg_sync_booking_interval" BEFORE INSERT OR UPDATE ON "public"."partner_bookings" FOR EACH ROW EXECUTE FUNCTION "public"."sync_booking_interval"();



CREATE OR REPLACE TRIGGER "trg_sync_partner_capacity_derived_ins" BEFORE INSERT ON "public"."partners" FOR EACH ROW EXECUTE FUNCTION "public"."sync_partner_capacity_derived"();



CREATE OR REPLACE TRIGGER "trg_sync_partner_capacity_derived_upd" BEFORE UPDATE OF "base_capacity_u", "extra_capacity_s", "extra_capacity_m", "extra_capacity_l" ON "public"."partners" FOR EACH ROW EXECUTE FUNCTION "public"."sync_partner_capacity_derived"();



CREATE OR REPLACE TRIGGER "trigger_partner_approve_role" AFTER UPDATE OF "is_active" ON "public"."partners" FOR EACH ROW EXECUTE FUNCTION "public"."on_partner_approved_update_role"();



CREATE OR REPLACE TRIGGER "enforce_bucket_name_length_trigger" BEFORE INSERT OR UPDATE OF "name" ON "storage"."buckets" FOR EACH ROW EXECUTE FUNCTION "storage"."enforce_bucket_name_length"();



CREATE OR REPLACE TRIGGER "objects_delete_delete_prefix" AFTER DELETE ON "storage"."objects" FOR EACH ROW EXECUTE FUNCTION "storage"."delete_prefix_hierarchy_trigger"();



CREATE OR REPLACE TRIGGER "objects_insert_create_prefix" BEFORE INSERT ON "storage"."objects" FOR EACH ROW EXECUTE FUNCTION "storage"."objects_insert_prefix_trigger"();



CREATE OR REPLACE TRIGGER "objects_update_create_prefix" BEFORE UPDATE ON "storage"."objects" FOR EACH ROW WHEN ((("new"."name" <> "old"."name") OR ("new"."bucket_id" <> "old"."bucket_id"))) EXECUTE FUNCTION "storage"."objects_update_prefix_trigger"();



CREATE OR REPLACE TRIGGER "prefixes_create_hierarchy" BEFORE INSERT ON "storage"."prefixes" FOR EACH ROW WHEN (("pg_trigger_depth"() < 1)) EXECUTE FUNCTION "storage"."prefixes_insert_trigger"();



CREATE OR REPLACE TRIGGER "prefixes_delete_hierarchy" AFTER DELETE ON "storage"."prefixes" FOR EACH ROW EXECUTE FUNCTION "storage"."delete_prefix_hierarchy_trigger"();



CREATE OR REPLACE TRIGGER "update_objects_updated_at" BEFORE UPDATE ON "storage"."objects" FOR EACH ROW EXECUTE FUNCTION "storage"."update_updated_at_column"();



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "mfa_amr_claims_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "auth"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_challenges"
    ADD CONSTRAINT "mfa_challenges_auth_factor_id_fkey" FOREIGN KEY ("factor_id") REFERENCES "auth"."mfa_factors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."one_time_tokens"
    ADD CONSTRAINT "one_time_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "auth"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_flow_state_id_fkey" FOREIGN KEY ("flow_state_id") REFERENCES "auth"."flow_state"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_oauth_client_id_fkey" FOREIGN KEY ("oauth_client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sso_domains"
    ADD CONSTRAINT "sso_domains_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."booking_payments"
    ADD CONSTRAINT "booking_payments_booking_fk" FOREIGN KEY ("booking_id") REFERENCES "public"."partner_bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."booking_payments"
    ADD CONSTRAINT "booking_payments_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."partner_bookings"("id") ON DELETE CASCADE;



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



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."prefixes"
    ADD CONSTRAINT "prefixes_bucketId_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_upload_id_fkey" FOREIGN KEY ("upload_id") REFERENCES "storage"."s3_multipart_uploads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."vector_indexes"
    ADD CONSTRAINT "vector_indexes_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets_vectors"("id");



ALTER TABLE "auth"."audit_log_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."flow_state" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."identities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."instances" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_amr_claims" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_challenges" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_factors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."one_time_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."refresh_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."saml_providers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."saml_relay_states" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."schema_migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sso_domains" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sso_providers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "admin_manage_all_partners" ON "public"."partners" USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles" "up"
  WHERE (("up"."id" = "auth"."uid"()) AND ("up"."role" = 'admin'::"text"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."user_profiles" "up"
  WHERE (("up"."id" = "auth"."uid"()) AND ("up"."role" = 'admin'::"text")))));



CREATE POLICY "admin_manage_requests" ON "public"."partner_requests" USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = 'admin'::"text"))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = 'admin'::"text")))));



ALTER TABLE "public"."booking_payments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "booking_payments_select_admin" ON "public"."booking_payments" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles" "up"
  WHERE (("up"."id" = "auth"."uid"()) AND ("up"."role" = 'admin'::"text")))));



CREATE POLICY "booking_payments_select_partner_owner" ON "public"."booking_payments" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."partner_bookings" "b"
     JOIN "public"."partners" "p" ON (("p"."id" = "b"."partner_id")))
  WHERE (("b"."id" = "booking_payments"."booking_id") AND ("p"."owner_id" = "auth"."uid"())))));



CREATE POLICY "booking_payments_select_user" ON "public"."booking_payments" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."partner_bookings" "b"
  WHERE (("b"."id" = "booking_payments"."booking_id") AND ("b"."user_id" = "auth"."uid"())))));



CREATE POLICY "bp_insert_base_own" ON "public"."booking_payments" FOR INSERT WITH CHECK ((("kind" = 'base'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."partner_bookings" "pb"
  WHERE (("pb"."id" = "booking_payments"."booking_id") AND ("pb"."user_id" = "auth"."uid"()))))));



CREATE POLICY "bp_select_own" ON "public"."booking_payments" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."partner_bookings" "pb"
  WHERE (("pb"."id" = "booking_payments"."booking_id") AND ("pb"."user_id" = "auth"."uid"())))));



CREATE POLICY "bp_select_partner_owner" ON "public"."booking_payments" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."partner_bookings" "pb"
     JOIN "public"."partners" "p" ON (("p"."id" = "pb"."partner_id")))
  WHERE (("pb"."id" = "booking_payments"."booking_id") AND ("p"."owner_id" = "auth"."uid"())))));



CREATE POLICY "insert self" ON "public"."user_profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "own_requests" ON "public"."partner_requests" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "own_requests_insert" ON "public"."partner_requests" FOR INSERT WITH CHECK ((("user_id" = "auth"."uid"()) AND ("status" = 'draft'::"public"."partner_request_status")));



CREATE POLICY "owner_manage_partners" ON "public"."partners" USING (("auth"."uid"() = "owner_id")) WITH CHECK (("auth"."uid"() = "owner_id"));



ALTER TABLE "public"."partner_bookings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."partner_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."partners" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "partners_insert_self" ON "public"."partners" FOR INSERT WITH CHECK (("auth"."uid"() = "owner_id"));



CREATE POLICY "partners_select_own" ON "public"."partners" FOR SELECT USING (("auth"."uid"() = "owner_id"));



CREATE POLICY "partners_update_own" ON "public"."partners" FOR UPDATE USING (("auth"."uid"() = "owner_id")) WITH CHECK (("auth"."uid"() = "owner_id"));



CREATE POLICY "pb_insert_user" ON "public"."partner_bookings" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() = "user_id") AND (EXISTS ( SELECT 1
   FROM "public"."partners" "p"
  WHERE (("p"."id" = "partner_bookings"."partner_id") AND ("p"."is_active" = true) AND ("p"."accepting_bookings" = true) AND ("p"."status" = 'approved'::"text"))))));



CREATE POLICY "pb_select_admin" ON "public"."partner_bookings" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles" "up"
  WHERE (("up"."id" = "auth"."uid"()) AND ("up"."role" = 'admin'::"text")))));



CREATE POLICY "pb_select_own" ON "public"."partner_bookings" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "pb_select_owner" ON "public"."partner_bookings" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."partners" "p"
  WHERE (("p"."id" = "partner_bookings"."partner_id") AND ("p"."owner_id" = "auth"."uid"())))));



CREATE POLICY "public_read_active_partners" ON "public"."partners" FOR SELECT USING ((("is_active" = true) AND ("status" = 'approved'::"text")));



CREATE POLICY "read own profile" ON "public"."user_profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "update own profile" ON "public"."user_profiles" FOR UPDATE USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users cannot escalate role" ON "public"."user_profiles" FOR UPDATE USING (("auth"."uid"() = "id")) WITH CHECK (("role" = ANY (ARRAY['user'::"text", 'partner_candidate'::"text"])));



CREATE POLICY "Admin read all contracts" ON "storage"."objects" FOR SELECT TO "authenticated" USING ((("bucket_id" = 'partner-contracts'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = 'admin'::"text"))))));



CREATE POLICY "Utente upload contratto proprio" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK ((("bucket_id" = 'partner-contracts'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));



CREATE POLICY "allow authenticated read partner photos" ON "storage"."objects" FOR SELECT TO "authenticated" USING (("bucket_id" = 'partner-photos'::"text"));



CREATE POLICY "allow authenticated upload partner photos" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK (("bucket_id" = 'partner-photos'::"text"));



ALTER TABLE "storage"."buckets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets_analytics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets_vectors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."objects" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."prefixes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads_parts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."vector_indexes" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "auth" TO "anon";
GRANT USAGE ON SCHEMA "auth" TO "authenticated";
GRANT USAGE ON SCHEMA "auth" TO "service_role";
GRANT ALL ON SCHEMA "auth" TO "supabase_auth_admin";
GRANT ALL ON SCHEMA "auth" TO "dashboard_user";
GRANT USAGE ON SCHEMA "auth" TO "postgres";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT USAGE ON SCHEMA "storage" TO "postgres" WITH GRANT OPTION;
GRANT USAGE ON SCHEMA "storage" TO "anon";
GRANT USAGE ON SCHEMA "storage" TO "authenticated";
GRANT USAGE ON SCHEMA "storage" TO "service_role";
GRANT ALL ON SCHEMA "storage" TO "supabase_storage_admin";
GRANT ALL ON SCHEMA "storage" TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."email"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."jwt"() TO "postgres";
GRANT ALL ON FUNCTION "auth"."jwt"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."role"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."uid"() TO "dashboard_user";



REVOKE ALL ON FUNCTION "public"."admin_approve_partner_docs"("p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_approve_partner_docs"("p_request_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_approve_partner_docs"("p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_reject_partner_request"("p_request_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_reject_partner_request"("p_request_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_reject_partner_request"("p_request_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_reject_partner_request"("p_request_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."attach_contract_to_partner_request"("p_request_id" "uuid", "p_contract_path" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."attach_contract_to_partner_request"("p_request_id" "uuid", "p_contract_path" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."attach_contract_to_partner_request"("p_request_id" "uuid", "p_contract_path" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."bd_calc_covered_until"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_duration_key" "text", "p_extra_days" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."bd_calc_covered_until"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_duration_key" "text", "p_extra_days" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."bd_calc_covered_until"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_duration_key" "text", "p_extra_days" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."bd_day_close_time"("p_partner_id" "uuid", "p_local_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."bd_day_close_time"("p_partner_id" "uuid", "p_local_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bd_day_close_time"("p_partner_id" "uuid", "p_local_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."bd_day_close_time_nullable"("p_partner_id" "uuid", "p_local_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."bd_day_close_time_nullable"("p_partner_id" "uuid", "p_local_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bd_day_close_time_nullable"("p_partner_id" "uuid", "p_local_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."bd_infer_duration"("p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."bd_infer_duration"("p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."bd_infer_duration"("p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."bd_infer_window_v2"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_covered_until" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."bd_infer_window_v2"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_covered_until" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."bd_infer_window_v2"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_covered_until" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."bd_is_day_open"("p_partner_id" "uuid", "p_local_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."bd_is_day_open"("p_partner_id" "uuid", "p_local_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bd_is_day_open"("p_partner_id" "uuid", "p_local_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."bd_next_cutoff_at"("p_partner_id" "uuid", "p_from" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."bd_next_cutoff_at"("p_partner_id" "uuid", "p_from" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."bd_next_cutoff_at"("p_partner_id" "uuid", "p_from" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."bd_next_open_close_at"("p_partner_id" "uuid", "p_from_local_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."bd_next_open_close_at"("p_partner_id" "uuid", "p_from_local_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bd_next_open_close_at"("p_partner_id" "uuid", "p_from_local_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."bd_next_window"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_current_covered_until" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."bd_next_window"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_current_covered_until" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."bd_next_window"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_current_covered_until" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."bd_pricing_total_cents"("p_duration" "text", "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."bd_pricing_total_cents"("p_duration" "text", "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."bd_pricing_total_cents"("p_duration" "text", "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."bd_pricing_total_cents_extended"("p_duration" "text", "p_extra_days" integer, "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."bd_pricing_total_cents_extended"("p_duration" "text", "p_extra_days" integer, "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."bd_pricing_total_cents_extended"("p_duration" "text", "p_extra_days" integer, "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."bd_weekday_key"("p_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."bd_weekday_key"("p_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bd_weekday_key"("p_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."bd_window_for_moment"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_moment" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."bd_window_for_moment"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_moment" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."bd_window_for_moment"("p_partner_id" "uuid", "p_dropoff" timestamp with time zone, "p_moment" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_my_booking"("p_booking_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_my_booking"("p_booking_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."cancel_my_booking"("p_booking_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_my_booking"("p_booking_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."confirm_partner_payment"("p_request_id" "uuid", "p_payment_reference" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."confirm_partner_payment"("p_request_id" "uuid", "p_payment_reference" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."confirm_partner_payment"("p_request_id" "uuid", "p_payment_reference" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_partner_booking_v2"("p_partner_id" "uuid", "p_contact_first_name" "text", "p_contact_last_name" "text", "p_contact_phone" "text", "p_contact_email" "text", "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer, "p_dropoff_planned_at" timestamp with time zone, "p_pickup_planned_at" timestamp with time zone, "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_partner_booking_v2"("p_partner_id" "uuid", "p_contact_first_name" "text", "p_contact_last_name" "text", "p_contact_phone" "text", "p_contact_email" "text", "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer, "p_dropoff_planned_at" timestamp with time zone, "p_pickup_planned_at" timestamp with time zone, "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_partner_booking_v2"("p_partner_id" "uuid", "p_contact_first_name" "text", "p_contact_last_name" "text", "p_contact_phone" "text", "p_contact_email" "text", "p_bags_s" integer, "p_bags_m" integer, "p_bags_l" integer, "p_dropoff_planned_at" timestamp with time zone, "p_pickup_planned_at" timestamp with time zone, "p_notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."delete_my_account"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."delete_my_account"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_my_account"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_my_account"() TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_stale_unverified_users"("max_age_minutes" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."delete_stale_unverified_users"("max_age_minutes" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_stale_unverified_users"("max_age_minutes" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."ensure_partner_candidate_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."ensure_partner_candidate_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."ensure_partner_candidate_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."finalize_partner_payment_webhook"("p_request_id" "uuid", "p_stripe_session_id" "text", "p_payment_reference" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."finalize_partner_payment_webhook"("p_request_id" "uuid", "p_stripe_session_id" "text", "p_payment_reference" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."finalize_partner_payment_webhook"("p_request_id" "uuid", "p_stripe_session_id" "text", "p_payment_reference" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_booking_code"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_booking_code"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_booking_code"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_booking_qr_payload"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_booking_qr_payload"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_booking_qr_payload"("p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_late_fee_quote"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_late_fee_quote"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_late_fee_quote"("p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_partner_availability_for_interval_v2"("p_partner_id" "uuid", "p_start_at" timestamp with time zone, "p_end_at" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_partner_availability_for_interval_v2"("p_partner_id" "uuid", "p_start_at" timestamp with time zone, "p_end_at" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_partner_availability_for_interval_v2"("p_partner_id" "uuid", "p_start_at" timestamp with time zone, "p_end_at" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_partner_used_capacity_m"("p_id" "uuid", "check_time" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_partner_used_capacity_m"("p_id" "uuid", "check_time" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_partner_used_capacity_m"("p_id" "uuid", "check_time" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."guard_partner_booking_accepting"() TO "anon";
GRANT ALL ON FUNCTION "public"."guard_partner_booking_accepting"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."guard_partner_booking_accepting"() TO "service_role";



GRANT ALL ON FUNCTION "public"."guard_partner_booking_partner_cancel"() TO "anon";
GRANT ALL ON FUNCTION "public"."guard_partner_booking_partner_cancel"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."guard_partner_booking_partner_cancel"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_otp_verified_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_otp_verified_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_otp_verified_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."on_booking_payment_insert"() TO "anon";
GRANT ALL ON FUNCTION "public"."on_booking_payment_insert"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."on_booking_payment_insert"() TO "service_role";



GRANT ALL ON FUNCTION "public"."on_partner_approved_update_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."on_partner_approved_update_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."on_partner_approved_update_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."partner_wizard_check_email"("p_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."partner_wizard_check_email"("p_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."partner_wizard_check_email"("p_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."pay_late_fee"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."pay_late_fee"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pay_late_fee"("p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."pay_late_fee_and_extend"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."pay_late_fee_and_extend"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."pay_late_fee_and_extend"("p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."process_booking_code"("p_code" "text", "p_force" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."process_booking_code"("p_code" "text", "p_force" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."process_booking_code"("p_code" "text", "p_force" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."process_booking_qr"("p_booking_id" "uuid", "p_token" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."process_booking_qr"("p_booking_id" "uuid", "p_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."process_booking_qr"("p_booking_id" "uuid", "p_token" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."reject_partner_booking"("p_booking_id" "uuid", "p_reason" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."reject_partner_booking"("p_booking_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reject_partner_booking"("p_booking_id" "uuid", "p_reason" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_booking_qr_token"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_booking_qr_token"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_booking_qr_token"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_partners_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_partners_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_partners_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_timestamp_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_timestamp_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_timestamp_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."submit_partner_request"() TO "anon";
GRANT ALL ON FUNCTION "public"."submit_partner_request"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_partner_request"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_booking_interval"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_booking_interval"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_booking_interval"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_partner_capacity_derived"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_partner_capacity_derived"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_partner_capacity_derived"() TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."upsert_partner_request_draft"("p_partner_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."upsert_partner_request_draft"("p_partner_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."upsert_partner_request_draft"("p_partner_id" "uuid") TO "service_role";



GRANT ALL ON TABLE "auth"."audit_log_entries" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."audit_log_entries" TO "postgres";
GRANT SELECT ON TABLE "auth"."audit_log_entries" TO "postgres" WITH GRANT OPTION;



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."flow_state" TO "postgres";
GRANT SELECT ON TABLE "auth"."flow_state" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."flow_state" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."identities" TO "postgres";
GRANT SELECT ON TABLE "auth"."identities" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."identities" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."instances" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."instances" TO "postgres";
GRANT SELECT ON TABLE "auth"."instances" TO "postgres" WITH GRANT OPTION;



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_amr_claims" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_amr_claims" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_amr_claims" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_challenges" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_challenges" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_challenges" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_factors" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_factors" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_factors" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_authorizations" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_authorizations" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_client_states" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_client_states" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_clients" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_clients" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_consents" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_consents" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."one_time_tokens" TO "postgres";
GRANT SELECT ON TABLE "auth"."one_time_tokens" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."one_time_tokens" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."refresh_tokens" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."refresh_tokens" TO "postgres";
GRANT SELECT ON TABLE "auth"."refresh_tokens" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON SEQUENCE "auth"."refresh_tokens_id_seq" TO "dashboard_user";
GRANT ALL ON SEQUENCE "auth"."refresh_tokens_id_seq" TO "postgres";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."saml_providers" TO "postgres";
GRANT SELECT ON TABLE "auth"."saml_providers" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."saml_providers" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."saml_relay_states" TO "postgres";
GRANT SELECT ON TABLE "auth"."saml_relay_states" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."saml_relay_states" TO "dashboard_user";



GRANT SELECT ON TABLE "auth"."schema_migrations" TO "postgres" WITH GRANT OPTION;



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sessions" TO "postgres";
GRANT SELECT ON TABLE "auth"."sessions" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sessions" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sso_domains" TO "postgres";
GRANT SELECT ON TABLE "auth"."sso_domains" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sso_domains" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sso_providers" TO "postgres";
GRANT SELECT ON TABLE "auth"."sso_providers" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sso_providers" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."users" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."users" TO "postgres";
GRANT SELECT ON TABLE "auth"."users" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "public"."account_deletion_logs" TO "anon";
GRANT ALL ON TABLE "public"."account_deletion_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."account_deletion_logs" TO "service_role";



GRANT ALL ON TABLE "public"."booking_payments" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."booking_payments" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_payments" TO "service_role";



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



REVOKE ALL ON TABLE "storage"."buckets" FROM "supabase_storage_admin";
GRANT ALL ON TABLE "storage"."buckets" TO "supabase_storage_admin" WITH GRANT OPTION;
GRANT ALL ON TABLE "storage"."buckets" TO "anon";
GRANT ALL ON TABLE "storage"."buckets" TO "authenticated";
GRANT ALL ON TABLE "storage"."buckets" TO "service_role";
GRANT ALL ON TABLE "storage"."buckets" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "storage"."buckets_analytics" TO "service_role";
GRANT ALL ON TABLE "storage"."buckets_analytics" TO "authenticated";
GRANT ALL ON TABLE "storage"."buckets_analytics" TO "anon";



GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "service_role";
GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "authenticated";
GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "anon";



REVOKE ALL ON TABLE "storage"."objects" FROM "supabase_storage_admin";
GRANT ALL ON TABLE "storage"."objects" TO "supabase_storage_admin" WITH GRANT OPTION;
GRANT ALL ON TABLE "storage"."objects" TO "anon";
GRANT ALL ON TABLE "storage"."objects" TO "authenticated";
GRANT ALL ON TABLE "storage"."objects" TO "service_role";
GRANT ALL ON TABLE "storage"."objects" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "storage"."prefixes" TO "service_role";
GRANT ALL ON TABLE "storage"."prefixes" TO "authenticated";
GRANT ALL ON TABLE "storage"."prefixes" TO "anon";



GRANT ALL ON TABLE "storage"."s3_multipart_uploads" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "anon";



GRANT ALL ON TABLE "storage"."s3_multipart_uploads_parts" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "anon";



GRANT SELECT ON TABLE "storage"."vector_indexes" TO "service_role";
GRANT SELECT ON TABLE "storage"."vector_indexes" TO "authenticated";
GRANT SELECT ON TABLE "storage"."vector_indexes" TO "anon";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON SEQUENCES TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON FUNCTIONS TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON TABLES TO "dashboard_user";



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






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "service_role";




