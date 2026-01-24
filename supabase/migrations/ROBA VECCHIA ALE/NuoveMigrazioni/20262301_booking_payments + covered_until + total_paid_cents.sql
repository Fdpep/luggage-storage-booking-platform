begin;

-- =========================================================
-- A) partner_bookings: stato corrente pagamento/estensione
-- =========================================================
alter table public.partner_bookings
  add column if not exists covered_until timestamptz,
  add column if not exists total_paid_cents integer not null default 0;

comment on column public.partner_bookings.covered_until
is 'Fino a quando la prenotazione è coperta/pagata (scadenza fascia corrente).';

comment on column public.partner_bookings.total_paid_cents
is 'Totale pagato finora (base + supplementi), in centesimi.';

create index if not exists idx_partner_bookings_covered_until
  on public.partner_bookings (covered_until);

-- Backfill: se già esiste pickup_planned_at, usalo come copertura iniziale
update public.partner_bookings
set covered_until = coalesce(covered_until, pickup_planned_at)
where covered_until is null and pickup_planned_at is not null;

-- =========================================================
-- B) booking_payments: log pagamenti (base + supplementi)
-- =========================================================
create table if not exists public.booking_payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.partner_bookings(id) on delete cascade,

  kind text not null check (kind in ('base','late_fee')),

  amount_cents integer not null check (amount_cents >= 0),

  from_covered_until timestamptz,
  to_covered_until   timestamptz,

  from_duration_key text,
  to_duration_key   text,

  paid_at timestamptz not null default now(),
  payment_reference text, -- 'mock' / stripe id ecc.

  created_at timestamptz not null default now()
);

comment on table public.booking_payments
is 'Storico pagamenti prenotazione. Ogni estensione crea una riga (late_fee).';

create index if not exists idx_booking_payments_booking_id
  on public.booking_payments (booking_id);

create index if not exists idx_booking_payments_paid_at
  on public.booking_payments (paid_at);

-- =========================================================
-- C) RLS booking_payments (lettura per user/owner/admin)
-- =========================================================
alter table public.booking_payments enable row level security;

-- USER: può leggere i propri pagamenti (via join booking.user_id)
drop policy if exists "booking_payments_select_user" on public.booking_payments;
create policy "booking_payments_select_user"
on public.booking_payments
for select
to authenticated
using (
  exists (
    select 1
    from public.partner_bookings b
    where b.id = booking_id
      and b.user_id = auth.uid()
  )
);

-- PARTNER OWNER: può leggere i pagamenti delle prenotazioni del proprio partner
drop policy if exists "booking_payments_select_partner_owner" on public.booking_payments;
create policy "booking_payments_select_partner_owner"
on public.booking_payments
for select
to authenticated
using (
  exists (
    select 1
    from public.partner_bookings b
    join public.partners p on p.id = b.partner_id
    where b.id = booking_id
      and p.owner_id = auth.uid()
  )
);

-- ADMIN: può leggere tutto
drop policy if exists "booking_payments_select_admin" on public.booking_payments;
create policy "booking_payments_select_admin"
on public.booking_payments
for select
to authenticated
using (
  exists (
    select 1 from public.user_profiles up
    where up.id = auth.uid() and up.role = 'admin'
  )
);

-- Inserimenti/Update/Delete: SOLO via RPC security definer
revoke insert, update, delete on public.booking_payments from authenticated;

commit;


--- Estensione oltre 3 giorni (flat +2€ per giorno extra)

create or replace function public.bd_pricing_total_cents_extended(
  p_duration text,
  p_extra_days int,
  p_bags_s int,
  p_bags_m int,
  p_bags_l int
) returns int
language plpgsql
as $$
declare
  base_cents int;
  extra int := greatest(0, coalesce(p_extra_days,0)) * 200; -- 2€ = 200 cents
begin
  base_cents := public.bd_pricing_total_cents(p_duration, p_bags_s, p_bags_m, p_bags_l);
  return base_cents + extra;
end;
$$;


----nuova copertura = covered_until + 1 giorno

create or replace function public.get_late_fee_quote(
  p_booking_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;
  b record;

  v_now timestamptz := now();
  v_from_covered timestamptz;
  v_deadline timestamptz;

  v_new_covered timestamptz;

  v_from_duration text;
  v_to_duration text;

  v_from_cents int;
  v_to_cents int;
  v_amount int;

  v_extra_days int := 0;
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

v_from_covered :=
  coalesce(
    b.covered_until,
    b.pickup_planned_at,
    b.dropoff_planned_at + interval '3 hours'
  );
  if v_from_covered is null then
    return jsonb_build_object('ok', false, 'message', 'covered_until mancante.');
  end if;

  v_deadline := v_from_covered + interval '15 minutes';
  if v_now <= v_deadline then
    return jsonb_build_object('ok', false, 'message', 'Nessun supplemento: sei entro tolleranza.');
  end if;

  -- STEP ATTUALE (boundary semplice): estendi di 1 giorno rispetto alla copertura corrente
  v_new_covered := v_from_covered + interval '1 day';

  -- infer durata (da dropoff_planned_at a covered)
  v_from_duration := public.bd_infer_duration(b.dropoff_planned_at, v_from_covered);
  v_to_duration   := public.bd_infer_duration(b.dropoff_planned_at, v_new_covered);

  -- prezzi base fino a 3 giorni
  v_from_cents := public.bd_pricing_total_cents(v_from_duration, b.bags_s, b.bags_m, b.bags_l);
  v_to_cents   := public.bd_pricing_total_cents(v_to_duration,   b.bags_s, b.bags_m, b.bags_l);

  -- se oltre 3 giorni: aggiungi +2€ per extraDays (flat)
  if v_to_duration = 'threeDays' then
    -- calcola extraDays oltre 3 giorni guardando differenza date
    -- (approssimazione: ogni giorno oltre la copertura 3 giorni aggiunge 1)
    v_extra_days := greatest(0, (date((v_new_covered at time zone 'Europe/Rome')) - date((b.dropoff_planned_at at time zone 'Europe/Rome')) - 3));
    v_to_cents := public.bd_pricing_total_cents_extended('threeDays', v_extra_days, b.bags_s, b.bags_m, b.bags_l);
  end if;

  v_amount := greatest(0, v_to_cents - v_from_cents);

  return jsonb_build_object(
    'ok', true,
    'amount_cents', v_amount,
    'from_duration', v_from_duration,
    'to_duration', v_to_duration,
    'from_covered_until', v_from_covered,
    'to_covered_until', v_new_covered,
    'message', case when v_amount = 0 then 'Nessun importo aggiuntivo.' else 'Supplemento calcolato.' end
  );
end;
$$;

grant execute on function public.get_late_fee_quote(uuid) to authenticated;




---------------------------------------pay_late_fee_and_extend(booking_id) con log multipli

create or replace function public.pay_late_fee_and_extend(
  p_booking_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;

  b record;
  v_now timestamptz := now();
  v_quote jsonb;

  v_amount int := 0;
  v_from_covered timestamptz;
  v_to_covered timestamptz;

  v_from_duration text;
  v_to_duration text;

  v_new_end_date date;
  v_new_end_time time;
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
    return jsonb_build_object('ok', false, 'message', 'Pagamento possibile solo dopo il check-in.');
  end if;

  if b.pickup_effective_at is not null then
    return jsonb_build_object('ok', false, 'message', 'Prenotazione già completata.');
  end if;

  -- ricalcolo quote server-side (source of truth)
  v_quote := public.get_late_fee_quote(p_booking_id);

  if (v_quote->>'ok')::boolean is distinct from true then
    return jsonb_build_object('ok', false, 'message', coalesce(v_quote->>'message','Impossibile calcolare supplemento.'));
  end if;

  v_amount := coalesce((v_quote->>'amount_cents')::int, 0);
  v_from_covered := (v_quote->>'from_covered_until')::timestamptz;
  v_to_covered   := (v_quote->>'to_covered_until')::timestamptz;
  v_from_duration := v_quote->>'from_duration';
  v_to_duration   := v_quote->>'to_duration';

  -- end_date/end_time locali (trigger sync riallinea pickup_planned_at)
  v_new_end_date := (v_to_covered at time zone 'Europe/Rome')::date;
  v_new_end_time := (v_to_covered at time zone 'Europe/Rome')::time;

  -- 1) log pagamento (multi)
  insert into public.booking_payments(
    booking_id, kind, amount_cents,
    from_covered_until, to_covered_until,
    from_duration_key, to_duration_key,
    paid_at, payment_reference
  ) values (
    p_booking_id, 'late_fee', v_amount,
    v_from_covered, v_to_covered,
    v_from_duration, v_to_duration,
    v_now, 'mock'
  );

  -- 2) aggiorna booking: nuova copertura + totale pagato + end_date/end_time
  update public.partner_bookings
  set covered_until = v_to_covered,
      total_paid_cents = coalesce(total_paid_cents,0) + v_amount,
      end_date = v_new_end_date,
      end_time = v_new_end_time,
      updated_at = now()
  where id = p_booking_id;

  return jsonb_build_object(
    'ok', true,
    'amount_cents', v_amount,
    'new_pickup_planned_at', v_to_covered,
    'message', 'Pagamento (mock) registrato e prenotazione estesa.'
  );
end;
$$;

grant execute on function public.pay_late_fee_and_extend(uuid) to authenticated;


---1) Helper: weekday key + close time dal JSON opening_hours

create or replace function public.bd_weekday_key(p_date date)
returns text
language plpgsql
as $$
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


create or replace function public.bd_day_close_time(
  p_partner_id uuid,
  p_local_date date
) returns time
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
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

grant execute on function public.bd_day_close_time(uuid, date) to authenticated;



--2) Helper: calcolare covered_until per una fascia

create or replace function public.bd_calc_covered_until(
  p_partner_id uuid,
  p_dropoff timestamptz,   -- dropoff_planned_at (o effective, ma planned va bene)
  p_duration_key text,     -- 'threeHours','oneDay','oneAndHalfDay','twoDays','threeDays'
  p_extra_days int default 0
) returns timestamptz
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
declare
  d0 date;        -- giorno consegna (locale)
  close_t time;
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
    close_t := public.bd_day_close_time(p_partner_id, d0);
    return ((d0::timestamp + close_t) at time zone 'Europe/Rome');
  end if;

  if p_duration_key = 'oneAndHalfDay' then
    target_date := d0 + 1;
    return ((target_date::timestamp + time '13:00:00') at time zone 'Europe/Rome');
  end if;

  if p_duration_key = 'twoDays' then
    target_date := d0 + 1;
    close_t := public.bd_day_close_time(p_partner_id, target_date);
    return ((target_date::timestamp + close_t) at time zone 'Europe/Rome');
  end if;

  -- threeDays (con extra_days opzionale)
  target_date := d0 + 2 + extra;
  close_t := public.bd_day_close_time(p_partner_id, target_date);
  return ((target_date::timestamp + close_t) at time zone 'Europe/Rome');
end;
$$;

grant execute on function public.bd_calc_covered_until(uuid, timestamptz, text, int) to authenticated;



-----3) Helper: capire “fascia corrente” + calcolare “fascia successiva”

create or replace function public.bd_infer_window_v2(
  p_partner_id uuid,
  p_dropoff timestamptz,
  p_covered_until timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
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

grant execute on function public.bd_infer_window_v2(uuid, timestamptz, timestamptz) to authenticated;




---3.2 Calcolare la fascia successiva (upgrade)

create or replace function public.bd_next_window(
  p_partner_id uuid,
  p_dropoff timestamptz,
  p_current_covered_until timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
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

grant execute on function public.bd_next_window(uuid, timestamptz, timestamptz) to authenticated;


---4) Update RPC get_late_fee_quote e pay_late_fee_and_extend

---4.1 get_late_fee_quote (v2)

create or replace function public.get_late_fee_quote(
  p_booking_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;
  b record;

  v_now timestamptz := now();
  v_from_covered timestamptz;
  v_deadline timestamptz;

  cur jsonb;
  nxt jsonb;

  from_key text;
  from_extra int := 0;
  to_key text;
  to_extra int := 0;

  v_to_covered timestamptz;

  v_from_cents int;
  v_to_cents int;
  v_amount int;
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

v_from_covered :=
  coalesce(
    b.covered_until,
    b.pickup_planned_at,
    b.dropoff_planned_at + interval '3 hours'
  );
  if v_from_covered is null then
    return jsonb_build_object('ok', false, 'message', 'covered_until mancante.');
  end if;

  v_deadline := v_from_covered + interval '15 minutes';
  if v_now <= v_deadline then
    return jsonb_build_object('ok', false, 'message', 'Nessun supplemento: sei entro tolleranza.');
  end if;

  -- finestra corrente e prossima finestra (upgrade)
  cur := public.bd_infer_window_v2(b.partner_id, b.dropoff_planned_at, v_from_covered);
  nxt := public.bd_next_window(b.partner_id, b.dropoff_planned_at, v_from_covered);

  from_key := cur->>'duration_key';
  from_extra := coalesce((cur->>'extra_days')::int, 0);

  to_key := nxt->>'duration_key';
  to_extra := coalesce((nxt->>'extra_days')::int, 0);
  v_to_covered := (nxt->>'covered_until')::timestamptz;

  -- prezzi:
  -- fino a 3 giorni: bd_pricing_total_cents
  -- oltre: bd_pricing_total_cents_extended('threeDays', extra_days, ...)
  if from_key = 'threeDays' and from_extra > 0 then
    v_from_cents := public.bd_pricing_total_cents_extended('threeDays', from_extra, b.bags_s, b.bags_m, b.bags_l);
  else
    v_from_cents := public.bd_pricing_total_cents(from_key, b.bags_s, b.bags_m, b.bags_l);
  end if;

  if to_key = 'threeDays' and to_extra > 0 then
    v_to_cents := public.bd_pricing_total_cents_extended('threeDays', to_extra, b.bags_s, b.bags_m, b.bags_l);
  else
    v_to_cents := public.bd_pricing_total_cents(to_key, b.bags_s, b.bags_m, b.bags_l);
  end if;

  v_amount := greatest(0, v_to_cents - v_from_cents);

  return jsonb_build_object(
    'ok', true,
    'amount_cents', v_amount,
    'from_duration', from_key,
    'from_extra_days', from_extra,
    'to_duration', to_key,
    'to_extra_days', to_extra,
    'from_covered_until', v_from_covered,
    'to_covered_until', v_to_covered,
    'message', case when v_amount = 0 then 'Nessun importo aggiuntivo.' else 'Supplemento calcolato.' end
  );
end;
$$;

grant execute on function public.get_late_fee_quote(uuid) to authenticated;


---4.2 pay_late_fee_and_extend (v2)

create or replace function public.pay_late_fee_and_extend(
  p_booking_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;

  b record;
  v_now timestamptz := now();
  v_quote jsonb;

  v_amount int := 0;
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
  v_from_covered := (v_quote->>'from_covered_until')::timestamptz;
  v_to_covered   := (v_quote->>'to_covered_until')::timestamptz;

  from_key := v_quote->>'from_duration';
  to_key := v_quote->>'to_duration';
  from_extra := coalesce((v_quote->>'from_extra_days')::int, 0);
  to_extra := coalesce((v_quote->>'to_extra_days')::int, 0);

  -- end_date/end_time locali (trigger sync riallinea pickup_planned_at)
  v_new_end_date := (v_to_covered at time zone 'Europe/Rome')::date;
  v_new_end_time := (v_to_covered at time zone 'Europe/Rome')::time;

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

  update public.partner_bookings
  set covered_until = v_to_covered,
      total_paid_cents = coalesce(total_paid_cents,0) + v_amount,
      end_date = v_new_end_date,
      end_time = v_new_end_time,
      updated_at = now()
  where id = p_booking_id;

  return jsonb_build_object(
    'ok', true,
    'amount_cents', v_amount,
    'new_pickup_planned_at', v_to_covered,
    'message', 'Pagamento (mock) registrato e prenotazione estesa.'
  );
end;
$$;

grant execute on function public.pay_late_fee_and_extend(uuid) to authenticated;


----STEP 1 — SQL: trovare “prossimo giorno aperto” e la sua chiusura

create or replace function public.bd_is_day_open(
  p_partner_id uuid,
  p_local_date date
) returns boolean
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
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

grant execute on function public.bd_is_day_open(uuid, date) to authenticated;


-----1.2: helper “close time del giorno” solo se aperto, altrimenti NULL

create or replace function public.bd_day_close_time_nullable(
  p_partner_id uuid,
  p_local_date date
) returns time
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
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

grant execute on function public.bd_day_close_time_nullable(uuid, date) to authenticated;


---1.3: helper “trova il prossimo giorno aperto” (entro max 14gg) e ritorna covered_until


create or replace function public.bd_next_open_close_at(
  p_partner_id uuid,
  p_from_local_date date
) returns timestamptz
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
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

grant execute on function public.bd_next_open_close_at(uuid, date) to authenticated;



-----STEP 2 — aggiornare bd_calc_covered_until per saltare i giorni chiusi

create or replace function public.bd_calc_covered_until(
  p_partner_id uuid,
  p_dropoff timestamptz,
  p_duration_key text,
  p_extra_days int default 0
) returns timestamptz
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
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


--------------patch fallback minimo per   calcolare supplemento

create or replace function public.get_late_fee_quote(
  p_booking_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;
  b record;

  v_now timestamptz := now();
  v_from_covered timestamptz;
  v_deadline timestamptz;

  cur jsonb;
  nxt jsonb;

  from_key text;
  from_extra int := 0;
  to_key text;
  to_extra int := 0;

  v_to_covered timestamptz;

  v_from_cents int;
  v_to_cents int;
  v_amount int;
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

  -- ✅ guardia: ci serve un dropoff (planned) per calcolare fallback e finestre
  if b.dropoff_planned_at is null then
    return jsonb_build_object('ok', false, 'message', 'dropoff_planned_at mancante.');
  end if;

  -- ✅ PATCH: fallback robusto
  v_from_covered :=
    coalesce(
      b.covered_until,
      b.pickup_planned_at,
      b.dropoff_planned_at + interval '3 hours'
    );

  v_deadline := v_from_covered + interval '15 minutes';
  if v_now <= v_deadline then
    return jsonb_build_object('ok', false, 'message', 'Nessun supplemento: sei entro tolleranza.');
  end if;

  -- finestra corrente e prossima finestra (upgrade)
  cur := public.bd_infer_window_v2(b.partner_id, b.dropoff_planned_at, v_from_covered);
  nxt := public.bd_next_window(b.partner_id, b.dropoff_planned_at, v_from_covered);

  from_key := cur->>'duration_key';
  from_extra := coalesce((cur->>'extra_days')::int, 0);

  to_key := nxt->>'duration_key';
  to_extra := coalesce((nxt->>'extra_days')::int, 0);
  v_to_covered := (nxt->>'covered_until')::timestamptz;

  -- prezzi:
  if from_key = 'threeDays' and from_extra > 0 then
    v_from_cents := public.bd_pricing_total_cents_extended('threeDays', from_extra, b.bags_s, b.bags_m, b.bags_l);
  else
    v_from_cents := public.bd_pricing_total_cents(from_key, b.bags_s, b.bags_m, b.bags_l);
  end if;

  if to_key = 'threeDays' and to_extra > 0 then
    v_to_cents := public.bd_pricing_total_cents_extended('threeDays', to_extra, b.bags_s, b.bags_m, b.bags_l);
  else
    v_to_cents := public.bd_pricing_total_cents(to_key, b.bags_s, b.bags_m, b.bags_l);
  end if;

  v_amount := greatest(0, v_to_cents - v_from_cents);

  return jsonb_build_object(
    'ok', true,
    'amount_cents', v_amount,
    'from_duration', from_key,
    'from_extra_days', from_extra,
    'to_duration', to_key,
    'to_extra_days', to_extra,
    'from_covered_until', v_from_covered,
    'to_covered_until', v_to_covered,
    'message', case when v_amount = 0 then 'Nessun importo aggiuntivo.' else 'Supplemento calcolato.' end
  );
end;
$$;

grant execute on function public.get_late_fee_quote(uuid) to authenticated;
