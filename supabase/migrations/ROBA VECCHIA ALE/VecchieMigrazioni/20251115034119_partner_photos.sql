create table public.partner_photos (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  url text not null,
  is_cover boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

-- (Opzionale ma consigliato) Indice per ricerche veloci per partner
create index if not exists idx_partner_photos_partner_id
  on public.partner_photos (partner_id);
