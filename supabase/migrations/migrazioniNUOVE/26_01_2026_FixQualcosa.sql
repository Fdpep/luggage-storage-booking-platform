-- 0) (Consigliato) FK per integrità
alter table public.booking_payments
  add constraint booking_payments_booking_fk
  foreign key (booking_id) references public.partner_bookings(id)
  on delete cascade;

-- 1) GRANT (se mancavano)
grant select, insert on public.booking_payments to authenticated;

-- 2) RLS
alter table public.booking_payments enable row level security;

-- L’utente vede i pagamenti delle sue prenotazioni
create policy "bp_select_own"
on public.booking_payments
for select
using (
  exists (
    select 1
    from public.partner_bookings pb
    where pb.id = booking_payments.booking_id
      and pb.user_id = auth.uid()
  )
);

-- L’utente può inserire SOLO pagamento base per le sue prenotazioni
create policy "bp_insert_base_own"
on public.booking_payments
for insert
with check (
  booking_payments.kind = 'base'
  and exists (
    select 1
    from public.partner_bookings pb
    where pb.id = booking_payments.booking_id
      and pb.user_id = auth.uid()
  )
);

-- (Opzionale) il partner owner vede i pagamenti delle prenotazioni del suo locale
create policy "bp_select_partner_owner"
on public.booking_payments
for select
using (
  exists (
    select 1
    from public.partner_bookings pb
    join public.partners p on p.id = pb.partner_id
    where pb.id = booking_payments.booking_id
      and p.owner_id = auth.uid()
  )
);

-- 3) Evita duplicati: 1 solo pagamento base per booking
create unique index if not exists ux_booking_payments_base_once
on public.booking_payments (booking_id)
where kind = 'base';

-- 4) Trigger: quando entra un pagamento, aggiorna cache su partner_bookings
create or replace function public.on_booking_payment_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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

drop trigger if exists trg_booking_payments_after_insert on public.booking_payments;

create trigger trg_booking_payments_after_insert
after insert on public.booking_payments
for each row execute function public.on_booking_payment_insert();