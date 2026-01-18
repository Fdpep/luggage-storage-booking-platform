begin;

-- 1) Elimina vecchi trigger/funzioni legati alla creazione profili
drop trigger if exists on_auth_user_created on auth.users;
drop trigger if exists on_auth_user_verified on auth.users;
drop trigger if exists on_auth_user_otp_verified on auth.users;

drop function if exists public.handle_new_user();
drop function if exists public.handle_verified_user();
drop function if exists public.handle_otp_verified_user();

-- 2) Funzione: crea user_profiles SOLO quando otp_verified passa a true
create or replace function public.handle_otp_verified_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_verified boolean;
  new_verified boolean;
begin
  old_verified := coalesce((old.raw_user_meta_data->>'otp_verified')::boolean, false);
  new_verified := coalesce((new.raw_user_meta_data->>'otp_verified')::boolean, false);

  -- Da non verificato a verificato
  if old_verified = false and new_verified = true then
    insert into public.user_profiles (id)
    values (new.id)
    on conflict (id) do nothing;
  end if;

  return new;
end;
$$;

-- 3) Trigger: parte quando cambiano i metadati (quindi anche otp_verified)
create trigger on_auth_user_otp_verified
after update on auth.users
for each row
when (old.raw_user_meta_data is distinct from new.raw_user_meta_data)
execute function public.handle_otp_verified_user();

commit;



begin;

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
  where coalesce((raw_user_meta_data->>'otp_verified')::boolean, false) = false
    and created_at < now() - (max_age_minutes || ' minutes')::interval;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

commit;


select cron.schedule(
  'cleanup-unverified-users',
  '* * * * *',
  $$select public.delete_stale_unverified_users(15);$$
);
