begin;

-- =========================================================
-- 1) Partners: cutoff giornaliero (chiusura)
--    - per partner 24h: metti 23:59:00
--    - per bar/negozi: metti es. 20:00:00
-- =========================================================
alter table public.partners
  add column if not exists daily_cutoff_time time;

comment on column public.partners.daily_cutoff_time
is 'Orario cutoff giornaliero per tariffa/estensioni. Es: 20:00 per bar; 23:59 per 24h.';

-- =========================================================
-- 2) Bookings: stato supplemento
-- =========================================================
alter table public.partner_bookings
  add column if not exists late_fee_paid_at timestamptz,
  add column if not exists late_fee_amount_cents integer,
  add column if not exists late_fee_covered_until timestamptz;

comment on column public.partner_bookings.late_fee_paid_at
is 'Quando il cliente paga il supplemento per ritardo (mock).';

comment on column public.partner_bookings.late_fee_amount_cents
is 'Importo supplemento pagato (in centesimi).';

comment on column public.partner_bookings.late_fee_covered_until
is 'Fino a quando il pagamento copre il deposito (es. prossimo cutoff).';

-- =========================================================
-- 3) Helper: pricing (replica dei prezzi Dart in SQL)
--    Durations: threeHours, oneDay, oneAndHalfDay, twoDays, threeDays
-- =========================================================
create or replace function public.bd_pricing_total_cents(
  p_duration text,
  p_bags_s int,
  p_bags_m int,
  p_bags_l int
) returns int
language plpgsql
as $$
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

-- =========================================================
-- 4) Helper: infer durata (stessa logica del Dart inferDuration)
-- =========================================================
create or replace function public.bd_infer_duration(
  p_start timestamptz,
  p_end   timestamptz
) returns text
language plpgsql
as $$
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

-- =========================================================
-- 5) Helper: prossimo cutoff (chiusura) dopo un timestamp
-- =========================================================
create or replace function public.bd_next_cutoff_at(
  p_partner_id uuid,
  p_from timestamptz default now()
) returns timestamptz
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
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

grant execute on function public.bd_next_cutoff_at(uuid, timestamptz) to authenticated;

-- =========================================================
-- 6) RPC: quote supplemento (differenza tariffe + nuovo pickup)
-- =========================================================
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
  v_pickup timestamptz;
  v_deadline timestamptz;

  v_new_pickup timestamptz;

  v_from_duration text;
  v_to_duration text;

  v_from_cents int;
  v_to_cents int;
  v_diff int;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'message', 'Nessun utente autenticato.');
  end if;

  select (up.role = 'admin') into v_is_admin
  from public.user_profiles up
  where up.id = v_uid;

  select *
  into b
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

  v_pickup := b.pickup_planned_at;
  if v_pickup is null then
    return jsonb_build_object('ok', false, 'message', 'pickup_planned_at mancante.');
  end if;

  v_deadline := v_pickup + interval '15 minutes';

  if v_now <= v_deadline then
    return jsonb_build_object(
      'ok', false,
      'message', 'Nessun supplemento: sei entro l’orario/tolleranza.'
    );
  end if;

  -- nuovo pickup = prossimo cutoff del partner
  v_new_pickup := public.bd_next_cutoff_at(b.partner_id, v_now);

  -- durata "attuale" e durata "dopo estensione"
  v_from_duration := public.bd_infer_duration(b.dropoff_planned_at, b.pickup_planned_at);
  v_to_duration   := public.bd_infer_duration(b.dropoff_planned_at, v_new_pickup);

  v_from_cents := public.bd_pricing_total_cents(v_from_duration, b.bags_s, b.bags_m, b.bags_l);
  v_to_cents   := public.bd_pricing_total_cents(v_to_duration,   b.bags_s, b.bags_m, b.bags_l);

  v_diff := greatest(0, v_to_cents - v_from_cents);

  return jsonb_build_object(
    'ok', true,
    'amount_cents', v_diff,
    'from_duration', v_from_duration,
    'to_duration', v_to_duration,
    'new_pickup_planned_at', v_new_pickup,
    'message', case when v_diff = 0 then 'Nessun importo aggiuntivo.' else 'Supplemento calcolato.' end
  );
end;
$$;

grant execute on function public.get_late_fee_quote(uuid) to authenticated;

-- =========================================================
-- 7) RPC: paga supplemento + estendi end_date/end_time (mock)
-- =========================================================
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
  v_pickup timestamptz;
  v_deadline timestamptz;

  v_new_pickup timestamptz;
  v_new_end_date date;
  v_new_end_time time;

  v_quote jsonb;
  v_amount int;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'message', 'Nessun utente autenticato.');
  end if;

  select (up.role = 'admin') into v_is_admin
  from public.user_profiles up
  where up.id = v_uid;

  select *
  into b
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

  v_pickup := b.pickup_planned_at;
  if v_pickup is null then
    return jsonb_build_object('ok', false, 'message', 'pickup_planned_at mancante.');
  end if;

  v_deadline := v_pickup + interval '15 minutes';

  if v_now <= v_deadline then
    return jsonb_build_object('ok', false, 'message', 'Non sei oltre la tolleranza: nessun supplemento.');
  end if;

  -- usa la quote ufficiale
  v_quote := public.get_late_fee_quote(p_booking_id);

  if (v_quote->>'ok')::boolean is distinct from true then
    return jsonb_build_object('ok', false, 'message', coalesce(v_quote->>'message','Impossibile calcolare supplemento.'));
  end if;

  v_amount := coalesce((v_quote->>'amount_cents')::int, 0);
  v_new_pickup := (v_quote->>'new_pickup_planned_at')::timestamptz;

  -- end_date/end_time locali (così trigger sync_booking_interval riallinea pickup_planned_at)
  v_new_end_date := (v_new_pickup at time zone 'Europe/Rome')::date;
  v_new_end_time := (v_new_pickup at time zone 'Europe/Rome')::time;

  update public.partner_bookings
  set late_fee_paid_at = v_now,
      late_fee_amount_cents = v_amount,
      late_fee_covered_until = v_new_pickup,
      end_date = v_new_end_date,
      end_time = v_new_end_time,
      updated_at = now()
  where id = p_booking_id;

  return jsonb_build_object(
    'ok', true,
    'amount_cents', v_amount,
    'new_pickup_planned_at', v_new_pickup,
    'message', 'Pagamento (mock) registrato e prenotazione estesa.'
  );
end;
$$;

grant execute on function public.pay_late_fee_and_extend(uuid) to authenticated;

commit;
