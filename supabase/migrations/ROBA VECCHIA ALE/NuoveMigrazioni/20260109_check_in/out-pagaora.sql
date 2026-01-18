-- STEP A3 — RPC: process booking code (check-in/out + pay mock)
create or replace function public.process_booking_code(
  p_code text,
  p_force boolean default false
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
set row_security = off
as $$
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

grant execute on function public.process_booking_code(text, boolean) to authenticated;
