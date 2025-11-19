-- 2025-11-13-02_init_partners.sql
-- Aggiunge RLS + policy + trigger updated_at per public.partners

begin;

--------------------------------------------------------------------------------
-- 1) ASSICURATI CHE LA TABELLA ESISTA (coerente con lo schema attuale)
--------------------------------------------------------------------------------
create table if not exists public.partners (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  address text,
  lat double precision,
  lng double precision,
  opening_hours jsonb,
  capacity integer not null default 0,
  price_2h numeric,
  price_per_day numeric,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.partners is
  'Attività partner collegate a auth.users (owner_id).';

create index if not exists idx_partners_owner_id on public.partners(owner_id);
create index if not exists idx_partners_is_active on public.partners(is_active);

--------------------------------------------------------------------------------
-- 2) RLS + POLICY
--------------------------------------------------------------------------------
alter table public.partners enable row level security;

-- pulizia policy
drop policy if exists "public_read_active_partners"   on public.partners;
drop policy if exists "owner_manage_partners"         on public.partners;
drop policy if exists "admin_manage_all_partners"     on public.partners;

-- a) CHIUNQUE (anche anon) può leggere le attività attive
create policy "public_read_active_partners"
  on public.partners
  for select
  using (is_active = true);

-- b) Il proprietario può inserire/aggiornare le PROPRIE attività
create policy "owner_manage_partners"
  on public.partners
  for all
  using (
    auth.uid() = owner_id
    and exists (
      select 1 from public.user_profiles up
      where up.id = auth.uid()
        and up.role in ('partner','admin')
    )
  )
  with check (
    auth.uid() = owner_id
    and exists (
      select 1 from public.user_profiles up
      where up.id = auth.uid()
        and up.role in ('partner','admin')
    )
  );

-- c) Gli admin possono gestire tutto
create policy "admin_manage_all_partners"
  on public.partners
  for all
  using (
    exists (
      select 1 from public.user_profiles up
      where up.id = auth.uid()
        and up.role = 'admin'
    )
  )
  with check (
    exists (
      select 1 from public.user_profiles up
      where up.id = auth.uid()
        and up.role = 'admin'
    )
  );

--------------------------------------------------------------------------------
-- 3) TRIGGER updated_at automatico
--------------------------------------------------------------------------------
create or replace function public.set_partners_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_partners_updated_at on public.partners;

create trigger set_partners_updated_at
  before update on public.partners
  for each row
  execute function public.set_partners_updated_at();

--------------------------------------------------------------------------------
-- 4) GRANT
--------------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select on public.partners to anon, authenticated;
grant insert, update, delete on public.partners to authenticated;

commit;



---------------------------------------------------------------------------
--DOPO AVER CREATO LA TABELLA CON IL CODICE SOPRA INSERIRE QUESTI COMANDI--


begin;

--------------------------------------------------------------------------------
-- 1) Aggiungo colonne di stato e motivo rifiuto a public.partners
--------------------------------------------------------------------------------
alter table public.partners
  add column if not exists status text not null default 'pending'
    check (status in ('pending','approved','rejected'));

alter table public.partners
  add column if not exists reject_reason text;

-- Indici utili
create index if not exists idx_partners_status on public.partners(status);

--------------------------------------------------------------------------------
-- 2) RLS + policy (aggiorno/sistemo)
--------------------------------------------------------------------------------
alter table public.partners enable row level security;

drop policy if exists "public_read_partners"          on public.partners;
drop policy if exists "public_read_active_partners"   on public.partners;
drop policy if exists "owner_manage_partners"         on public.partners;
drop policy if exists "admin_manage_all_partners"     on public.partners;

-- a) CHIUNQUE può leggere solo partner attivi E approvati
create policy "public_read_active_partners"
  on public.partners
  for select
  using (is_active = true and status = 'approved');

-- b) Il proprietario può inserire / aggiornare SOLO le sue attività
create policy "owner_manage_partners"
  on public.partners
  for all
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

-- c) L'ADMIN può gestire tutte le attività
--    (qui usiamo user_profiles.role = 'admin'; NON c'è ricorsione perché
--     la tabella è diversa).
create policy "admin_manage_all_partners"
  on public.partners
  for all
  using (
    exists (
      select 1
      from public.user_profiles up
      where up.id = auth.uid()
        and up.role = 'admin'
    )
  )
  with check (
    exists (
      select 1
      from public.user_profiles up
      where up.id = auth.uid()
        and up.role = 'admin'
    )
  );

--------------------------------------------------------------------------------
-- 3) Trigger per updated_at automatico (se non l'hai già)
--------------------------------------------------------------------------------
create or replace function public.set_partners_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_partners_updated_at on public.partners;

create trigger set_partners_updated_at
  before update on public.partners
  for each row
  execute function public.set_partners_updated_at();

commit;

--------------------------------------------------------------------------------
--Aggiungo colonne di telefonoregole a public.partners
--------------------------------------------------------------------------------

alter table public.partners
  add column description text,
  add column phone text,
  add column rules text;
