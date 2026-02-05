alter table public.partner_bookings
  add column if not exists checkin_photo_bucket text not null default 'booking-checkin-photos',
  add column if not exists checkin_photo_path text,
  add column if not exists checkin_photo_uploaded_at timestamptz,
  add column if not exists checkin_photo_expires_at timestamptz,
  add column if not exists checkin_photo_deleted_at timestamptz;

create index if not exists partner_bookings_checkin_photo_expires_idx
  on public.partner_bookings (checkin_photo_expires_at)
  where checkin_photo_path is not null;


insert into storage.buckets (id, name, public)
values ('booking-checkin-photos', 'booking-checkin-photos', false)
on conflict (id) do nothing;

-- READ
drop policy if exists "partner read booking checkin photos" on storage.objects;
create policy "partner read booking checkin photos"
on storage.objects for select
using (
  bucket_id = 'booking-checkin-photos'
  and exists (
    select 1
    from public.partner_bookings b
    join public.partners p on p.id = b.partner_id
    where p.owner_id = auth.uid()
      and storage.objects.name = (b.partner_id::text || '/' || b.id::text || '/checkin.jpg')
  )
);

-- UPLOAD (INSERT)
drop policy if exists "partner upload booking checkin photos" on storage.objects;
create policy "partner upload booking checkin photos"
on storage.objects for insert
with check (
  bucket_id = 'booking-checkin-photos'
  and exists (
    select 1
    from public.partner_bookings b
    join public.partners p on p.id = b.partner_id
    where p.owner_id = auth.uid()
      and storage.objects.name = (b.partner_id::text || '/' || b.id::text || '/checkin.jpg')
  )
);

-- OVERWRITE (UPDATE)
drop policy if exists "partner update booking checkin photos" on storage.objects;
create policy "partner update booking checkin photos"
on storage.objects for update
using (
  bucket_id = 'booking-checkin-photos'
  and exists (
    select 1
    from public.partner_bookings b
    join public.partners p on p.id = b.partner_id
    where p.owner_id = auth.uid()
      and storage.objects.name = (b.partner_id::text || '/' || b.id::text || '/checkin.jpg')
  )
);

-- (opzionale) DELETE
drop policy if exists "partner delete booking checkin photos" on storage.objects;
create policy "partner delete booking checkin photos"
on storage.objects for delete
using (
  bucket_id = 'booking-checkin-photos'
  and exists (
    select 1
    from public.partner_bookings b
    join public.partners p on p.id = b.partner_id
    where p.owner_id = auth.uid()
      and storage.objects.name = (b.partner_id::text || '/' || b.id::text || '/checkin.jpg')
  )
);


create or replace function public.process_booking_code(
  p_code text,
  p_force boolean default false,
  p_action text default null,                 -- 'preview' | 'check_in' | 'check_out' | null(auto)
  p_checkin_photo_path text default null,     -- richiesto in check-in
  p_ack_photo boolean default false           -- richiesto in check-out se esiste foto
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'auth'
set row_security to 'off'
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

  if v_booking.dropoff_planned_at is null or v_booking.pickup_planned_at is null then
    v_dropoff := ((v_booking.booking_date::text || ' ' || v_booking.start_time::text)::timestamp at time zone 'Europe/Rome');
    v_pickup  := ((coalesce(v_booking.end_date, v_booking.booking_date)::text || ' ' || v_booking.end_time::text)::timestamp at time zone 'Europe/Rome');
  else
    v_dropoff := v_booking.dropoff_planned_at;
    v_pickup  := v_booking.pickup_planned_at;
  end if;

  v_expected_path := (v_booking.partner_id::text || '/' || v_booking.id::text || '/checkin.jpg');

  if v_booking.dropoff_effective_at is not null and v_booking.pickup_effective_at is not null then
    return jsonb_build_object(
      'ok', true,
      'action', 'already_done',
      'booking_id', v_booking.id,
      'message', 'Check-in e check-out già registrati.'
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

      if v_now >= v_pickup then
        return jsonb_build_object(
          'ok', true,
          'action', v_action,
          'booking_id', v_booking.id,
          'checkin_allowed', false,
          'message', 'Orario di ritiro già passato: check-in non consentito.'
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

  if v_action = 'check_in' then
    -- ✅ nuova regola: NON prima del dropoff previsto
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

    if v_now >= v_pickup then
      return jsonb_build_object(
        'ok', false,
        'code', 'BD_CHECKIN_TOO_LATE',
        'action', v_action,
        'booking_id', v_booking.id,
        'message', 'Orario di ritiro già passato: check-in non consentito.'
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

create or replace function public.process_booking_code(p_code text, p_force boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'auth'
set row_security to 'off'
as $$
begin
  return public.process_booking_code(p_code, p_force, null, null, false);
end;
$$;

grant all on function public.process_booking_code(text, boolean, text, text, boolean) to anon, authenticated, service_role;
grant all on function public.process_booking_code(text, boolean) to anon, authenticated, service_role;




---RPC nuova: public.process_booking_code_v2

create or replace function public.process_booking_code_v2(
  p_code text,
  p_force boolean default false,
  p_action text default 'auto',              -- 'preview' | 'check_in' | 'check_out' | 'auto'
  p_checkin_photo_path text default null,    -- required on check_in
  p_ack_photo boolean default false          -- required on check_out if photo exists
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'auth'
set row_security to 'off'
as $$
declare
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;

  v_booking record;
  v_owner uuid;

  v_now timestamptz := now();
  v_code text := upper(trim(coalesce(p_code,'')));

  v_dropoff timestamptz;
  v_pickup timestamptz;

  v_need_pay boolean := false;
  v_action text := lower(trim(coalesce(p_action,'auto')));

  v_expected_path text;
  v_bucket text := 'booking-checkin-photos';

  v_checkin_allowed boolean := true;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED', 'message', 'Nessun utente autenticato.');
  end if;

  -- valida formato codice (robusto server-side)
  if v_code !~* '^BD[0-9A-F]{10}$' then
    return jsonb_build_object('ok', false, 'code', 'CODE_INVALID', 'message', 'Codice non valido.');
  end if;

  select (up.role = 'admin') into v_is_admin
  from public.user_profiles up
  where up.id = v_uid;

  -- PREVIEW: niente lock, nessun side-effect
  if v_action = 'preview' then
    select * into v_booking
    from public.partner_bookings
    where booking_code = v_code
    limit 1;

    if v_booking.id is null then
      return jsonb_build_object('ok', false, 'code', 'CODE_NOT_FOUND', 'message', 'Codice non valido.');
    end if;

    select owner_id into v_owner
    from public.partners
    where id = v_booking.partner_id;

    if coalesce(v_is_admin,false) = false and v_owner <> v_uid then
      return jsonb_build_object('ok', false, 'code', 'NOT_AUTHORIZED', 'message', 'Non autorizzato per questa prenotazione.');
    end if;

    if lower(v_booking.status) in ('cancelled','canceled','rejected','cancelled_by_user','cancelled_by_partner','expired') then
      return jsonb_build_object('ok', false, 'code', 'BOOKING_NOT_PROCESSABLE',
        'message', 'Prenotazione annullata/rifiutata: non processabile.');
    end if;

    if v_booking.dropoff_planned_at is null or v_booking.pickup_planned_at is null then
      v_dropoff := ((v_booking.booking_date::text || ' ' || v_booking.start_time::text)::timestamp at time zone 'Europe/Rome');
      v_pickup  := ((coalesce(v_booking.end_date, v_booking.booking_date)::text || ' ' || v_booking.end_time::text)::timestamp at time zone 'Europe/Rome');
    else
      v_dropoff := v_booking.dropoff_planned_at;
      v_pickup  := v_booking.pickup_planned_at;
    end if;

    if v_booking.dropoff_effective_at is not null and v_booking.pickup_effective_at is not null then
      return jsonb_build_object(
        'ok', true,
        'action', 'already_done',
        'booking_id', v_booking.id,
        'message', 'Check-in e check-out già registrati.'
      );
    end if;

    if v_booking.dropoff_effective_at is null then
      -- NEXT: check-in
      if v_now < v_dropoff then
        v_checkin_allowed := false;
      end if;

      if v_now >= v_pickup then
        v_checkin_allowed := false;
        return jsonb_build_object(
          'ok', true,
          'action', 'check_in',
          'booking_id', v_booking.id,
          'checkin_allowed', false,
          'message', 'Orario di ritiro già passato: check-in non consentito.'
        );
      end if;

      return jsonb_build_object(
        'ok', true,
        'action', 'check_in',
        'booking_id', v_booking.id,
        'checkin_allowed', v_checkin_allowed,
        'not_before', case when v_checkin_allowed then null else v_dropoff end,
        'message',
          case
            when v_checkin_allowed then 'Pronto per confermare il check-in.'
            else 'Check-in disponibile dalle ' || to_char(v_dropoff at time zone 'Europe/Rome','DD/MM HH24:MI')
          end
      );
    else
      -- NEXT: check-out
      if v_now > (v_pickup + interval '15 minutes') then
        v_need_pay := true;
      end if;

      return jsonb_build_object(
        'ok', true,
        'action', 'check_out',
        'booking_id', v_booking.id,
        'require_payment', v_need_pay,
        'checkin_photo_bucket', coalesce(v_booking.checkin_photo_bucket, v_bucket),
        'checkin_photo_path', v_booking.checkin_photo_path,
        'message', case when v_need_pay then 'Checkout oltre tolleranza: potrebbe servire supplemento.' else 'Pronto per confermare il check-out.' end
      );
    end if;
  end if;

  -- AZIONI CHE SCRIVONO: lock row FOR UPDATE (race-safe)
  select * into v_booking
  from public.partner_bookings
  where booking_code = v_code
  limit 1
  for update;

  if v_booking.id is null then
    return jsonb_build_object('ok', false, 'code', 'CODE_NOT_FOUND', 'message', 'Codice non valido.');
  end if;

  select owner_id into v_owner
  from public.partners
  where id = v_booking.partner_id;

  if coalesce(v_is_admin,false) = false and v_owner <> v_uid then
    return jsonb_build_object('ok', false, 'code', 'NOT_AUTHORIZED', 'message', 'Non autorizzato per questa prenotazione.');
  end if;

  if lower(v_booking.status) in ('cancelled','canceled','rejected','cancelled_by_user','cancelled_by_partner','expired') then
    return jsonb_build_object('ok', false, 'code', 'BOOKING_NOT_PROCESSABLE',
      'message', 'Prenotazione annullata/rifiutata: non processabile.');
  end if;

  if v_booking.dropoff_planned_at is null or v_booking.pickup_planned_at is null then
    v_dropoff := ((v_booking.booking_date::text || ' ' || v_booking.start_time::text)::timestamp at time zone 'Europe/Rome');
    v_pickup  := ((coalesce(v_booking.end_date, v_booking.booking_date)::text || ' ' || v_booking.end_time::text)::timestamp at time zone 'Europe/Rome');
  else
    v_dropoff := v_booking.dropoff_planned_at;
    v_pickup  := v_booking.pickup_planned_at;
  end if;

  v_expected_path := (v_booking.partner_id::text || '/' || v_booking.id::text || '/checkin.jpg');

  if v_booking.dropoff_effective_at is not null and v_booking.pickup_effective_at is not null then
    return jsonb_build_object(
      'ok', true,
      'action', 'already_done',
      'booking_id', v_booking.id,
      'message', 'Check-in e check-out già registrati.'
    );
  end if;

  -- resolve 'auto'
  if v_action = 'auto' or v_action is null or v_action = '' then
    if v_booking.dropoff_effective_at is null then
      v_action := 'check_in';
    else
      v_action := 'check_out';
    end if;
  end if;

  -- =========================
  -- CHECK-IN
  -- =========================
  if v_action = 'check_in' then
    if v_booking.dropoff_effective_at is not null then
      return jsonb_build_object('ok', false, 'code', 'ALREADY_CHECKED_IN', 'action', 'check_in',
        'booking_id', v_booking.id, 'message', 'Check-in già registrato.');
    end if;

    -- ✅ nuova regola: check-in SOLO da dropoff previsto in poi
    if v_now < v_dropoff then
      return jsonb_build_object(
        'ok', false,
        'code', 'BD_CHECKIN_TOO_EARLY',
        'action', 'check_in',
        'booking_id', v_booking.id,
        'not_before', v_dropoff,
        'message', 'Check-in disponibile dalle ' || to_char(v_dropoff at time zone 'Europe/Rome','DD/MM HH24:MI')
      );
    end if;

    if v_now >= v_pickup then
      return jsonb_build_object(
        'ok', false,
        'code', 'BD_CHECKIN_TOO_LATE',
        'action', 'check_in',
        'booking_id', v_booking.id,
        'message', 'Orario di ritiro già passato: check-in non consentito.'
      );
    end if;

    -- foto obbligatoria
    if nullif(trim(coalesce(p_checkin_photo_path,'')), '') is null then
      return jsonb_build_object(
        'ok', false,
        'code', 'BD_PHOTO_REQUIRED',
        'action', 'check_in',
        'booking_id', v_booking.id,
        'message', 'Foto bagaglio obbligatoria per completare il check-in.'
      );
    end if;

    -- hardening path
    if trim(p_checkin_photo_path) <> v_expected_path then
      return jsonb_build_object(
        'ok', false,
        'code', 'BD_PHOTO_PATH_INVALID',
        'action', 'check_in',
        'booking_id', v_booking.id,
        'message', 'Percorso foto non valido.'
      );
    end if;

    -- verifica che il file esista davvero in storage
    if not exists (
      select 1
      from storage.objects o
      where o.bucket_id = v_bucket
        and o.name = p_checkin_photo_path
    ) then
      return jsonb_build_object(
        'ok', false,
        'code', 'BD_PHOTO_NOT_FOUND',
        'action', 'check_in',
        'booking_id', v_booking.id,
        'message', 'Foto non trovata nello storage (riprovare).'
      );
    end if;

    update public.partner_bookings
    set dropoff_effective_at = v_now,
        status = 'in_store',
        checkin_photo_bucket = v_bucket,
        checkin_photo_path = p_checkin_photo_path,
        checkin_photo_uploaded_at = v_now,
        checkin_photo_uploaded_by = v_uid,
        checkin_photo_expires_at = (v_now + interval '7 days'),
        updated_at = now()
    where id = v_booking.id;

    return jsonb_build_object(
      'ok', true,
      'action', 'check_in',
      'booking_id', v_booking.id,
      'checkin_photo_bucket', v_bucket,
      'checkin_photo_path', p_checkin_photo_path,
      'message', 'Check-in registrato.'
    );
  end if;

  -- =========================
  -- CHECK-OUT
  -- =========================
  if v_action = 'check_out' then
    if v_booking.dropoff_effective_at is null then
      return jsonb_build_object('ok', false, 'code', 'NOT_CHECKED_IN', 'action', 'check_out',
        'booking_id', v_booking.id, 'message', 'Check-in non ancora registrato.');
    end if;

    if v_booking.pickup_effective_at is not null then
      return jsonb_build_object('ok', true, 'action', 'already_done', 'booking_id', v_booking.id,
        'message', 'Check-out già registrato.');
    end if;

    -- ack obbligatorio se esiste foto
    if v_booking.checkin_photo_path is not null and p_ack_photo is distinct from true then
      return jsonb_build_object(
        'ok', false,
        'code', 'BD_PHOTO_CONFIRM_REQUIRED',
        'action', 'check_out',
        'booking_id', v_booking.id,
        'message', 'Conferma esplicita richiesta: verifica foto bagaglio prima del check-out.'
      );
    end if;

    -- late fee / mock pay
    if v_now > (v_pickup + interval '15 minutes') then
      v_need_pay := true;
    end if;

    if v_need_pay and p_force is distinct from true then
      return jsonb_build_object(
        'ok', false,
        'action', 'check_out',
        'booking_id', v_booking.id,
        'require_payment', true,
        'message', 'Oltre la tolleranza: serve supplemento. Premi “Paga ora”.'
      );
    end if;

    update public.partner_bookings
    set pickup_effective_at = v_now,
        status = 'completed',
        -- ✅ dopo check-out: accorcia TTL a 24h (se c'è foto)
        checkin_photo_expires_at = case
          when checkin_photo_path is null then null
          else least(coalesce(checkin_photo_expires_at, v_now + interval '7 days'), v_now + interval '24 hours')
        end,
        updated_at = now()
    where id = v_booking.id;

    return jsonb_build_object(
      'ok', true,
      'action', 'check_out',
      'booking_id', v_booking.id,
      'message', case when v_need_pay then 'Pagamento (mock) ok + check-out registrato.' else 'Check-out registrato.' end
    );
  end if;

  return jsonb_build_object(
    'ok', false,
    'code', 'ACTION_INVALID',
    'message', 'Azione non valida.'
  );
end;
$$;

-- permessi: solo utenti autenticati (consigliato)
revoke all on function public.process_booking_code_v2(text, boolean, text, text, boolean) from public;
grant execute on function public.process_booking_code_v2(text, boolean, text, text, boolean) to authenticated, service_role;



----- RPC “pulita” per preview (senza passare params extra).

create or replace function public.preview_booking_code_v2(p_code text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'auth'
set row_security to 'off'
as $$
begin
  return public.process_booking_code_v2(p_code, false, 'preview', null, false);
end;
$$;

revoke all on function public.preview_booking_code_v2(text) from public;
grant execute on function public.preview_booking_code_v2(text) to authenticated, service_role;
