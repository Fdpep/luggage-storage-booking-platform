create or replace function public.process_booking_code(
  p_code text,
  p_force boolean default false,
  p_action text default null,
  p_checkin_photo_path text default null,
  p_ack_photo boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'auth'
set row_security to 'off'
as $function$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;
  v_booking record;
  v_owner uuid;
  v_now timestamptz := now();
  v_dropoff timestamptz;
  v_pickup timestamptz;
  v_cutoff timestamptz; -- ✅ cutoff reale per no-show/checkin
  v_need_pay boolean := false;
  v_action text;
  v_code text := upper(trim(coalesce(p_code,'')));
  v_expected_path text;
  v_bucket text := 'booking-checkin-photos';
  v_mode text := lower(trim(coalesce(p_action, '')));
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

  if lower(v_booking.status) in ('cancelled','canceled','rejected','cancelled_by_user','cancelled_by_partner','expired') then
    return jsonb_build_object('ok', false, 'message', 'Prenotazione annullata/rifiutata: non processabile.');
  end if;

  -- calcolo dropoff/pickup "base" (legacy fallback)
  if v_booking.dropoff_planned_at is null or v_booking.pickup_planned_at is null then
    v_dropoff := ((v_booking.booking_date::text || ' ' || v_booking.start_time::text)::timestamp at time zone 'Europe/Rome');
    v_pickup  := ((coalesce(v_booking.end_date, v_booking.booking_date)::text || ' ' || v_booking.end_time::text)::timestamp at time zone 'Europe/Rome');
  else
    v_dropoff := v_booking.dropoff_planned_at;
    v_pickup  := v_booking.pickup_planned_at;
  end if;

  -- ✅ cutoff reale: prima covered_until, poi pickup_planned_at, poi legacy pickup
  v_cutoff := coalesce(v_booking.covered_until, v_booking.pickup_planned_at, v_pickup);

  v_expected_path := (v_booking.partner_id::text || '/' || v_booking.id::text || '/checkin.jpg');

  -- già fatto (normal completed con timestamps)
  if v_booking.dropoff_effective_at is not null and v_booking.pickup_effective_at is not null then
    return jsonb_build_object(
      'ok', true,
      'action', 'already_done',
      'booking_id', v_booking.id,
      'message', 'Check-in e check-out già registrati.'
    );
  end if;

  -- ✅ blocco esplicito su completed (incl. no-show)
  if lower(v_booking.status) = 'completed' then
    return jsonb_build_object(
      'ok', false,
      'code', 'BD_BOOKING_COMPLETED',
      'booking_id', v_booking.id,
      'completion_reason', coalesce(v_booking.completion_reason, 'normal'),
      'message',
        case
          when coalesce(v_booking.completion_reason, 'normal') = 'no_show'
               or v_booking.dropoff_effective_at is null
          then 'Prenotazione già chiusa (no-show): non processabile.'
          else 'Prenotazione già completata: non processabile.'
        end
    );
  end if;

  if v_booking.dropoff_effective_at is null then
    v_action := 'check_in';
  else
    v_action := 'check_out';
  end if;

  -- PREVIEW: nessun side-effect
  if v_mode = 'preview' then
    if v_action = 'check_in' then
      if v_cutoff is not null and v_now >= v_cutoff then
        return jsonb_build_object(
          'ok', true,
          'action', v_action,
          'booking_id', v_booking.id,
          'checkin_allowed', false,
          'code', 'BD_NO_SHOW',
          'cutoff_at', v_cutoff,
          'message', 'Prenotazione scaduta: il cliente non si è presentato (no-show).'
        );
      end if;

      if v_now < v_dropoff then
        return jsonb_build_object(
          'ok', true,
          'action', v_action,
          'booking_id', v_booking.id,
          'checkin_allowed', false,
          'not_before', v_dropoff,
          'message', 'Check-in disponibile dalle ' || to_char(v_dropoff at time zone 'Europe/Rome','HH24:MI')
        );
      end if;

      return jsonb_build_object(
        'ok', true,
        'action', v_action,
        'booking_id', v_booking.id,
        'checkin_allowed', true,
        'message', 'Pronto per confermare il check-in.'
      );
    else
      if v_now > (v_pickup + interval '15 minutes') then
        v_need_pay := true;
      end if;

      return jsonb_build_object(
        'ok', true,
        'action', v_action,
        'booking_id', v_booking.id,
        'require_payment', v_need_pay,
        'checkin_photo_bucket', coalesce(v_booking.checkin_photo_bucket, v_bucket),
        'checkin_photo_path', v_booking.checkin_photo_path,
        'message', case when v_need_pay then 'Checkout oltre tolleranza: potrebbe servire supplemento.' else 'Pronto per confermare il check-out.' end
      );
    end if;
  end if;

  -- ESECUZIONE: se p_action nullo, usa auto; altrimenti rispetta
  if v_mode in ('check_in','check_out') then
    v_action := v_mode;
  end if;

  -- ✅ enforcement NO-SHOW in execution (hard, senza aspettare cron)
  if lower(v_booking.status) in ('confirmed','pending')
     and v_booking.dropoff_effective_at is null
     and v_booking.pickup_effective_at is null
     and v_cutoff is not null
     and v_now >= v_cutoff
  then
    update public.partner_bookings
    set status = 'completed',
        completion_reason = 'no_show',
        updated_at = now()
    where id = v_booking.id;

    return jsonb_build_object(
      'ok', false,
      'code', 'BD_NO_SHOW',
      'booking_id', v_booking.id,
      'cutoff_at', v_cutoff,
      'message', 'Prenotazione scaduta: il cliente non si è presentato (no-show).'
    );
  end if;

  if v_action = 'check_in' then
    -- NON prima del dropoff previsto
    if v_now < v_dropoff then
      return jsonb_build_object(
        'ok', false,
        'code', 'BD_CHECKIN_TOO_EARLY',
        'action', v_action,
        'booking_id', v_booking.id,
        'not_before', v_dropoff,
        'message', 'Check-in disponibile dalle ' || to_char(v_dropoff at time zone 'Europe/Rome','HH24:MI')
      );
    end if;

    -- ✅ NON dopo cutoff reale (covered_until / pickup_planned)
    if v_cutoff is not null and v_now >= v_cutoff then
      return jsonb_build_object(
        'ok', false,
        'code', 'BD_CHECKIN_TOO_LATE',
        'action', v_action,
        'booking_id', v_booking.id,
        'cutoff_at', v_cutoff,
        'message', 'Prenotazione scaduta: check-in non consentito.'
      );
    end if;

    if nullif(trim(coalesce(p_checkin_photo_path,'')), '') is null then
      return jsonb_build_object(
        'ok', false,
        'code', 'BD_PHOTO_REQUIRED',
        'action', v_action,
        'booking_id', v_booking.id,
        'message', 'Foto bagaglio obbligatoria per completare il check-in.'
      );
    end if;

    if trim(p_checkin_photo_path) <> v_expected_path then
      return jsonb_build_object(
        'ok', false,
        'code', 'BD_PHOTO_PATH_INVALID',
        'action', v_action,
        'booking_id', v_booking.id,
        'message', 'Percorso foto non valido.'
      );
    end if;

    update public.partner_bookings
    set dropoff_effective_at = coalesce(dropoff_effective_at, v_now),
        status = 'in_store',
        completion_reason = 'normal',
        checkin_photo_bucket = v_bucket,
        checkin_photo_path = p_checkin_photo_path,
        checkin_photo_uploaded_at = v_now,
        checkin_photo_expires_at = (v_now + interval '7 days'),
        updated_at = now()
    where id = v_booking.id;

    return jsonb_build_object(
      'ok', true,
      'action', v_action,
      'booking_id', v_booking.id,
      'message', 'Check-in registrato.'
    );
  else
    -- check-out: conferma foto se presente
    if v_booking.checkin_photo_path is not null and p_ack_photo is distinct from true then
      return jsonb_build_object(
        'ok', false,
        'code', 'BD_PHOTO_CONFIRM_REQUIRED',
        'action', v_action,
        'booking_id', v_booking.id,
        'message', 'Conferma esplicita richiesta: verifica foto bagaglio prima del check-out.'
      );
    end if;

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
        completion_reason = 'normal',
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
$function$;
