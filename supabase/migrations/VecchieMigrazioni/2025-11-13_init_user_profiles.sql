-- 2025-11-13-01_init_user_profiles.sql
-- Crea/gestisce la tabella user_profiles + RLS + trigger auto-inserimento

begin;

--------------------------------------------------------------------------------
-- 1) TABELLA PROFILI UTENTE (se non esiste)
--------------------------------------------------------------------------------
create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  full_name  text,
  avatar_url text,
  kyc_status text not null default 'none'
    check (kyc_status in ('none','basic','verified')),
  role text not null default 'user'
    check (role in ('user','partner','admin'))
);

comment on table public.user_profiles is
  'Profili utente applicativi; PK = auth.users.id. Ruoli: user/partner/admin.';

--------------------------------------------------------------------------------
-- 2) RLS + POLICY
--------------------------------------------------------------------------------
alter table public.user_profiles enable row level security;

-- pulizia policy se già esistono
drop policy if exists "read own profile or admin"   on public.user_profiles;
drop policy if exists "update own profile or admin" on public.user_profiles;

-- SELECT:
-- - l'utente vede solo il proprio profilo
-- - gli admin vedono tutti
create policy "read own profile or admin"
  on public.user_profiles
  for select
  using (
    auth.uid() = id
    or exists (
      select 1 from public.user_profiles up
      where up.id = auth.uid()
        and up.role = 'admin'
    )
  );

-- UPDATE:
-- - l'utente può aggiornare solo il proprio profilo
-- - l'admin può aggiornare chiunque
create policy "update own profile or admin"
  on public.user_profiles
  for update
  using (
    auth.uid() = id
    or exists (
      select 1 from public.user_profiles up
      where up.id = auth.uid()
        and up.role = 'admin'
    )
  )
  with check (
    auth.uid() = id
    or exists (
      select 1 from public.user_profiles up
      where up.id = auth.uid()
        and up.role = 'admin'
    )
  );

--------------------------------------------------------------------------------
-- 3) GRANT
--------------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select, insert, update on public.user_profiles to authenticated;

--------------------------------------------------------------------------------
-- 4) TRIGGER: CREA il profilo quando nasce un utente in auth.users
--------------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

commit;



---------------------------------------------------------------------------------------------------
-- IN CASO DI ERRORE PER ACCESSO PARTNER DOPO AVER CREATO LA TABELLA COPIARE IL CODICE QUI SOTTO 


-- begin;

-- -- Assicuriamoci che RLS sia attivo
-- alter table public.user_profiles enable row level security;

-- -- Elimina le policy vecchie (anche se i nomi non coincidono, è idempotente)
-- drop policy if exists "read own profile"        on public.user_profiles;
-- drop policy if exists "update own profile"      on public.user_profiles;
-- drop policy if exists "insert self"             on public.user_profiles;
-- drop policy if exists "read own profile or admin"   on public.user_profiles;
-- drop policy if exists "update own profile or admin" on public.user_profiles;

-- -- SELECT: l'utente vede SOLO il proprio profilo
-- create policy "read own profile"
--   on public.user_profiles
--   for select
--   using (auth.uid() = id);

-- -- UPDATE: l'utente può aggiornare SOLO il proprio profilo
-- create policy "update own profile"
--   on public.user_profiles
--   for update
--   using (auth.uid() = id)
--   with check (auth.uid() = id);

-- -- (opzionale) INSERT lato client: solo se volessi permettere ai client di inserirsi da soli.
-- -- In pratica noi usiamo il trigger handle_new_user, quindi questa non è strettamente necessaria.
-- create policy "insert self"
--   on public.user_profiles
--   for insert
--   with check (auth.uid() = id);

-- commit;