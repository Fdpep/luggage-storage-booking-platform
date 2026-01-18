create type partner_request_status as enum (
  'draft',
  'submitted',
  'docs_approved',
  'awaiting_payment',
  'paid',
  'rejected'
);

alter table partner_requests
  add column if not exists status partner_request_status not null default 'draft',
  add column if not exists docs_approved_at timestamptz,
  add column if not exists payment_required boolean not null default false,
  add column if not exists paid_at timestamptz,
  add column if not exists payment_reference text;

-- status diventa derivato
-- approved SOLO dopo pagamento
alter table partners
  add column if not exists activated_at timestamptz;

alter table partner_requests enable row level security;

create policy "partner can read own request"
on partner_requests
for select
using (user_id = auth.uid());

create policy "users cannot escalate role"
on user_profiles
for update
using (auth.uid() = id)
with check (
  role in ('user', 'partner_candidate')
);

create or replace function submit_partner_request()
returns void
language plpgsql
security definer
as $$
begin
  update partner_requests
  set status = 'submitted'
  where user_id = auth.uid()
    and status = 'draft';
end;
$$;


create or replace function admin_approve_partner_docs(p_request_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  -- verifica admin
  if not exists (
    select 1 from user_profiles
    where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'Not authorized';
  end if;

  update partner_requests
  set
    status = 'docs_approved',
    docs_approved_at = now(),
    payment_required = true
  where id = p_request_id;
end;
$$;


create or replace function confirm_partner_payment(p_request_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_user_id uuid;
begin
  select user_id into v_user_id
  from partner_requests
  where id = p_request_id
    and status = 'docs_approved';

  if v_user_id is null then
    raise exception 'Invalid request';
  end if;

  update partner_requests
  set
    status = 'paid',
    paid_at = now()
  where id = p_request_id;

  update user_profiles
  set role = 'partner'
  where id = v_user_id;

  update partners
  set
    status = 'approved',
    is_active = true,
    activated_at = now()
  where owner_id = v_user_id;
end;
$$;


-- 1) Un partner può avere UNA sola richiesta "attiva" (draft/submitted/docs_approved/awaiting_payment)
-- (paid/rejected possono esistere nello storico)
create unique index if not exists ux_partner_requests_active_per_user
on partner_requests(user_id)
where status in ('draft','submitted','docs_approved','awaiting_payment');

-- 2) Sempre utile: updated_at
alter table partner_requests
  add column if not exists updated_at timestamptz not null default now();

create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end; $$;

drop trigger if exists trg_partner_requests_touch on partner_requests;
create trigger trg_partner_requests_touch
before update on partner_requests
for each row execute function touch_updated_at();


alter table partner_requests enable row level security;

-- LETTURA: ok (già ce l’hai)
drop policy if exists "partner can read own request" on partner_requests;
create policy "partner can read own request"
on partner_requests
for select
using (user_id = auth.uid());

-- INSERT: l’utente può inserire SOLO la sua richiesta e SOLO draft/submitted
drop policy if exists "partner can create own request" on partner_requests;
create policy "partner can create own request"
on partner_requests
for insert
with check (
  user_id = auth.uid()
  and status in ('draft','submitted')
);

-- UPDATE: BLOCCATO (niente update diretti dal client)
drop policy if exists "partner can update own request" on partner_requests;
-- non creare policy update => per default è negato

create or replace function upsert_partner_request_draft(
  p_partner_id uuid
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- se esiste una richiesta "attiva", riusa quella
  select id into v_id
  from partner_requests
  where user_id = auth.uid()
    and status in ('draft','submitted','docs_approved','awaiting_payment')
  limit 1;

  if v_id is null then
    insert into partner_requests(user_id, partner_id, status, created_at)
    values (auth.uid(), p_partner_id, 'draft', now())
    returning id into v_id;
  end if;

  return v_id;
end;
$$;

create or replace function submit_partner_request()
returns void
language plpgsql
security definer
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update partner_requests
  set status = 'submitted'
  where user_id = auth.uid()
    and status = 'draft';

  -- ruolo candidato (non partner!)
  update user_profiles
  set role = 'partner_candidate'
  where id = auth.uid()
    and role <> 'admin';
end;
$$;


create or replace function admin_approve_partner_docs(p_request_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  if not exists (
    select 1 from user_profiles
    where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'Not authorized';
  end if;

  update partner_requests
  set
    status = 'awaiting_payment',
    docs_approved_at = now(),
    payment_required = true
  where id = p_request_id
    and status in ('submitted','docs_approved'); -- tollerante
end;
$$;

create or replace function confirm_partner_payment(
  p_request_id uuid,
  p_payment_reference text default null
)
returns void
language plpgsql
security definer
as $$
declare
  v_user_id uuid;
begin
  -- L'utente può confermare SOLO la propria richiesta
  select user_id into v_user_id
  from partner_requests
  where id = p_request_id
    and user_id = auth.uid()
    and status = 'awaiting_payment';

  if v_user_id is null then
    raise exception 'Invalid request';
  end if;

  update partner_requests
  set
    status = 'paid',
    paid_at = now(),
    payment_reference = coalesce(p_payment_reference, payment_reference)
  where id = p_request_id;

  update user_profiles
  set role = 'partner'
  where id = v_user_id;

  update partners
  set
    status = 'approved',
    is_active = true,
    activated_at = now()
  where owner_id = v_user_id;
end;
$$;


create or replace function admin_approve_partner_docs(p_request_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  if not exists (
    select 1 from user_profiles
    where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'Not authorized';
  end if;

  update partner_requests
  set
    status = 'awaiting_payment',
    docs_approved_at = now(),
    payment_required = true
  where id = p_request_id
    and status in ('submitted','docs_approved'); -- tollerante
end;
$$;


create or replace function confirm_partner_payment(
  p_request_id uuid,
  p_payment_reference text default null
)
returns void
language plpgsql
security definer
as $$
declare
  v_user_id uuid;
begin
  select user_id into v_user_id
  from partner_requests
  where id = p_request_id
    and user_id = auth.uid()
    and status = 'awaiting_payment';

  if v_user_id is null then
    raise exception 'Invalid request';
  end if;

  update partner_requests
  set
    status = 'paid',
    paid_at = now(),
    payment_reference = coalesce(p_payment_reference, payment_reference)
  where id = p_request_id;

  update user_profiles
  set role = 'partner'
  where id = v_user_id;

  update partners
  set
    status = 'approved',
    is_active = true,
    activated_at = now()
  where owner_id = v_user_id;
end;
$$;

-- 1) imposta un default sicuro
alter table user_profiles
  alter column role set default 'user';

-- 2) evita valori strani: consenti solo questi
alter table user_profiles
  drop constraint if exists user_profiles_role_check;

alter table user_profiles
  add constraint user_profiles_role_check
  check (role in ('user','partner_candidate','partner','admin'));

  drop policy if exists "users cannot escalate role" on user_profiles;

create policy "users cannot escalate role"
on user_profiles
for update
using (auth.uid() = id)
with check (
  role in ('user', 'partner_candidate')
);

create or replace function upsert_partner_request_draft(p_partner_id uuid)
returns uuid
language plpgsql
security definer
as $$
declare
  v_id uuid;
begin
  -- crea draft se non esiste, altrimenti riusa l’ultimo draft
  select id into v_id
  from partner_requests
  where user_id = auth.uid()
    and status = 'draft'
  order by created_at desc
  limit 1;

  if v_id is null then
    insert into partner_requests (user_id, partner_id, status, created_at)
    values (auth.uid(), p_partner_id, 'draft', now())
    returning id into v_id;
  else
    update partner_requests
    set partner_id = p_partner_id
    where id = v_id;
  end if;

  return v_id;
end;
$$;

create or replace function submit_partner_request()
returns void
language plpgsql
security definer
as $$
begin
  update partner_requests
  set status = 'submitted'
  where user_id = auth.uid()
    and status = 'draft';

  -- ✅ diventa partner_candidate appena invia la richiesta
  update user_profiles
  set role = 'partner_candidate'
  where id = auth.uid()
    and role = 'user';
end;
$$;


-- 1) elimina il vecchio check
alter table public.partner_requests
  drop constraint if exists partner_requests_status_check;

-- 2) crea check coerente con il flusso partner-candidate
alter table public.partner_requests
  add constraint partner_requests_status_check
  check (
    status = any (
      array[
        'draft'::text,
        'submitted'::text,
        'docs_approved'::text,
        'awaiting_payment'::text,
        'paid'::text,
        'rejected'::text
      ]
    )
  );

-- 3) imposta default sensato
alter table public.partner_requests
  alter column status set default 'draft';
