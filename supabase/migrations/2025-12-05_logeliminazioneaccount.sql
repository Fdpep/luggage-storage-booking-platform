--tabella log eliminazione degli account per invio della mail di eliminazione.

create table if not exists public.account_deletion_log (
  id bigserial primary key,
  user_id uuid not null,
  email text,
  created_at timestamptz default now()
);
