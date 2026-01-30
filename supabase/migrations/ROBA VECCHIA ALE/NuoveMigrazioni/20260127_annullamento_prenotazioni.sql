alter table public.partner_bookings
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancel_reason text;


--------------

create or replace function public.cancel_my_booking(
  p_booking_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'auth'
set row_security to 'off'
as $$
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

-- (consigliato) limita EXECUTE agli utenti autenticati
revoke all on function public.cancel_my_booking(uuid, text) from public;
grant execute on function public.cancel_my_booking(uuid, text) to authenticated;


---