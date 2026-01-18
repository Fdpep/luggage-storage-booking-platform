-- STEP A1 — Booking code BDXXXXXXXXXX (QR statico)

-- Serve per gen_random_bytes / gen_random_uuid
create extension if not exists pgcrypto;

-- 1) Colonna booking_code
alter table public.partner_bookings
  add column if not exists booking_code text;

-- 2) Funzione generator (BD + 10 HEX uppercase)
create or replace function public.generate_booking_code()
returns text
language plpgsql
as $$
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

-- 3) Default automatico per nuove righe
alter table public.partner_bookings
  alter column booking_code set default public.generate_booking_code();

-- 4) Backfill per righe esistenti
update public.partner_bookings
set booking_code = public.generate_booking_code()
where booking_code is null;

-- 5) NOT NULL
alter table public.partner_bookings
  alter column booking_code set not null;

-- 6) Unique + formato
create unique index if not exists partner_bookings_booking_code_key
  on public.partner_bookings (booking_code);

alter table public.partner_bookings
  drop constraint if exists partner_bookings_booking_code_format_check;

alter table public.partner_bookings
  add constraint partner_bookings_booking_code_format_check
  check (booking_code ~ '^BD[0-9A-F]{10}$');
