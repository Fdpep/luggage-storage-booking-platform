-- Migration: init_user_profiles
-- Scopo: creare la tabella dei profili utente con RLS e trigger di popolamento automatico.
-- Nota: tutti i blocchi sono commentati in italiano per chiarezza.


-- Tabella public.user_profiles: contiene le info base del profilo (nome, avatar, stato KYC, ruolo)
-- . La PK è l’id dell’utente (auth.users.id).
-- 
-- RLS (Row Level Security): abilito RLS e definisco policy tali che ognuno può leggere/inserire/aggiornare
--  solo il proprio profilo (auth.uid() = id).
-- 
-- Trigger on_auth_user_created: ogni volta che si crea un utente in auth.users,
-- inserisco automaticamente una riga in user_profiles con lo stesso id.
-- Così l’app può fare upsert o update senza preoccuparsi dell’inserimento “prima volta”.

begin;

--------------------------------------------------------------------------------
-- 1) TABELLA PROFILI UTENTE
--------------------------------------------------------------------------------
create table if not exists public.user_profiles (
  -- Chiave primaria = id utente Supabase (auth.users)
  id uuid primary key references auth.users(id) on delete cascade,

  -- Timestamp creazione (server-side, fuso orario mantenuto)
  created_at timestamptz not null default now(),

  -- Dati anagrafici di base (opzionali per ora)
  full_name  text,           -- nome completo dell'utente (facoltativo)
  avatar_url text,           -- URL avatar (facoltativo)

  -- Stato KYC (verifica minima/avanzata)
  kyc_status text not null default 'none'
    check (kyc_status in ('none','basic','verified')),

  -- Ruolo applicativo (user/partner/admin) - default = utente normale
  role text not null default 'user'
    check (role in ('user','partner','admin'))
);

comment on table public.user_profiles is
  'Profili utente applicativi; PK = auth.users.id. RLS: ogni utente vede/modifica solo sé stesso.';

--------------------------------------------------------------------------------
-- 2) ABILITA RLS + POLICY MINIME
--------------------------------------------------------------------------------
alter table public.user_profiles enable row level security;

-- Per idempotenza nei re-run delle migrazioni:
drop policy if exists "read own profile"   on public.user_profiles;
drop policy if exists "update own profile" on public.user_profiles;
drop policy if exists "insert self"        on public.user_profiles;

-- a) SELECT: l'utente può leggere solo il proprio profilo
create policy "read own profile"
  on public.user_profiles
  for select
  using (auth.uid() = id);

-- b) UPDATE: l'utente può aggiornare solo il proprio profilo
create policy "update own profile"
  on public.user_profiles
  for update
  using (auth.uid() = id);

-- c) INSERT: l'utente può inserire una riga solo per sé stesso
create policy "insert self"
  on public.user_profiles
  for insert
  with check (auth.uid() = id);

--------------------------------------------------------------------------------
-- 3) GRANTS (uso schema + permessi base per ruoli applicativi)
--    Supabase imposta già permessi ragionevoli; qui rendiamo esplicito l'essenziale.
--------------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select, insert, update on public.user_profiles to authenticated;

--------------------------------------------------------------------------------
-- 4) TRIGGER: AUTO-INSERIMENTO PROFILO QUANDO NASCE UN UTENTE IN auth.users
--------------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer                 -- eseguita con privilegi del proprietario
set search_path = public
as $$
begin
  -- Quando si crea un utente in auth.users, inseriamo (se manca) il relativo profilo.
  insert into public.user_profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

-- rimuove il trigger se già esiste (idempotenza)
drop trigger if exists on_auth_user_created on auth.users;

-- crea il trigger che scatta dopo l'inserimento in auth.users
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

commit;
