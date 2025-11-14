begin;

--------------------------------------------------------------------------------
-- 1) Tabella partner_requests
--------------------------------------------------------------------------------
create table if not exists public.partner_requests (
  id uuid primary key default gen_random_uuid(),

  -- utente che invia la richiesta (auth.users.id)
  user_id uuid not null references auth.users(id) on delete cascade,

  -- partner su cui si riferisce la richiesta
  partner_id uuid not null references public.partners(id) on delete cascade,

  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),

  message text,        -- testo inviato dall'azienda (es. note, info aggiuntive)
  admin_note text,     -- motivazione decisione admin

  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) -- admin che ha deciso
);

comment on table public.partner_requests is
  'Richieste di partnership BagDrop.';

create index if not exists idx_partner_requests_user
  on public.partner_requests(user_id);

create index if not exists idx_partner_requests_status
  on public.partner_requests(status);

--------------------------------------------------------------------------------
-- 2) RLS + policy
--------------------------------------------------------------------------------
alter table public.partner_requests enable row level security;

drop policy if exists "own_requests" on public.partner_requests;
drop policy if exists "admin_manage_requests" on public.partner_requests;

-- a) L'utente vede SOLO le sue richieste (es. storico)
create policy "own_requests"
  on public.partner_requests
  for select
  using (auth.uid() = user_id);

-- (se vuoi che l'utente possa reinviare una richiesta via INSERT lato client)
create policy "own_requests_insert"
  on public.partner_requests
  for insert
  with check (auth.uid() = user_id);

-- b) L'ADMIN vede e gestisce TUTTE le richieste
create policy "admin_manage_requests"
  on public.partner_requests
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
-- 3) GRANT
--------------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select, insert on public.partner_requests to authenticated;

commit;
