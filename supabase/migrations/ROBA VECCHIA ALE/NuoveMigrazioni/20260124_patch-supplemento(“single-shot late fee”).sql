------------------------1) Aggiungi helper: “in che fascia sono adesso?” → bd_window_for_moment
create or replace function public.bd_window_for_moment(
  p_partner_id uuid,
  p_dropoff timestamptz,
  p_moment timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
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

grant execute on function public.bd_window_for_moment(uuid, timestamptz, timestamptz) to authenticated;


-----------------2) Sostituisci get_late_fee_quote con versione “single-shot”

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

grant execute on function public.get_late_fee_quote(uuid) to authenticated;


-------------3) Sostituisci pay_late_fee_and_extend (v2) per pagare “single-shot”

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

grant execute on function public.pay_late_fee_and_extend(uuid) to authenticated;
