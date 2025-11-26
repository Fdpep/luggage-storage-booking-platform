begin;

create table if not exists public.partner_bookings (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,

  -- stato della prenotazione
  status text not null default 'confirmed' check (
    status in ('pending', 'confirmed', 'cancelled', 'completed')
  ),

  -- dati contatto (copiati dal form, così se l'utente cambia profilo non perdiamo lo storico)
  contact_first_name text not null,
  contact_last_name text not null,
  contact_phone text not null,
  contact_email text not null,

  -- bagagli richiesti
  bags_s integer not null default 0,
  bags_m integer not null default 0,
  bags_l integer not null default 0,

  -- note opzionali per il partner
  notes text,

  -- in futuro: fasce orarie / giorni
  -- start_time timestamptz,
  -- end_time   timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- semplice trigger per aggiornare updated_at
create or replace function public.set_timestamp_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_partner_bookings_updated_at on public.partner_bookings;

create trigger trg_partner_bookings_updated_at
before update on public.partner_bookings
for each row
execute function public.set_timestamp_updated_at();

commit;
