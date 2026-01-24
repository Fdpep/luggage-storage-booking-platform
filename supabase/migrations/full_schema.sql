


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



CREATE TYPE "public"."partner_request_status" AS ENUM (
    'draft',
    'submitted',
    'awaiting_payment',
    'paid',
    'rejected'
);


ALTER TYPE "public"."partner_request_status" OWNER TO "postgres";


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



CREATE UNIQUE INDEX "ux_partner_requests_active_per_user" ON "public"."partner_requests" USING "btree" ("user_id") WHERE ("status" = ANY (ARRAY['draft'::"public"."partner_request_status", 'submitted'::"public"."partner_request_status", 'awaiting_payment'::"public"."partner_request_status"]));



CREATE OR REPLACE TRIGGER "set_partners_updated_at" BEFORE UPDATE ON "public"."partners" FOR EACH ROW EXECUTE FUNCTION "public"."set_partners_updated_at"();



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



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



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



GRANT ALL ON TABLE "public"."account_deletion_logs" TO "anon";
GRANT ALL ON TABLE "public"."account_deletion_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."account_deletion_logs" TO "service_role";



GRANT ALL ON TABLE "public"."booking_payments" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."booking_payments" TO "authenticated";
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

