begin;

--------------------------------------------------------------------------------
-- 1) DISATTIVA VECCHIO TRIGGER CHE CREAVA SUBITO user_profiles
--------------------------------------------------------------------------------

-- La funzione vecchia:
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user();

--------------------------------------------------------------------------------
-- 2) NUOVA FUNZIONE: CREA user_profiles SOLO QUANDO L’UTENTE È VERIFICATO
--------------------------------------------------------------------------------

create or replace function public.handle_verified_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Usiamo solo l'id; gli altri campi hanno già default nella tua tabella
  insert into public.user_profiles (id)
  values (new.id)
  on conflict (id) do nothing;

  return new;
end;
$$;

-- Trigger: scatta quando l’utente passa da NON VERIFICATO a VERIFICATO
create trigger on_auth_user_verified
after update on auth.users
for each row
when (
  (old.confirmed_at is null and new.confirmed_at is not null)
  or (old.email_confirmed_at is null and new.email_confirmed_at is not null)
)
execute function public.handle_verified_user();

--------------------------------------------------------------------------------
-- 3) FUNZIONE: CANCELLA UTENTI NON VERIFICATI PIÙ VECCHI DI N MINUTI
--------------------------------------------------------------------------------

create or replace function public.delete_stale_unverified_users(max_age_minutes int)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  delete from auth.users
  where confirmed_at is null
    and created_at < now() - (max_age_minutes || ' minutes')::interval;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

--------------------------------------------------------------------------------
-- 4) JOB CRON: OGNI MINUTO PULISCE GLI UTENTI NON VERIFICATI DA 15 MINUTI
--------------------------------------------------------------------------------

-- Se esiste già un job con lo stesso nome non succede nulla di male perché
-- la migration viene eseguita una sola volta sul DB.
select cron.schedule(
  'cleanup-unverified-users',
  '* * * * *',                       -- ogni minuto
  $$select public.delete_stale_unverified_users(15);$$
);

commit;
