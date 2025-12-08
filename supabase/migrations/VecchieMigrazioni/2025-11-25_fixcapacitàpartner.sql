begin;

alter table public.partners
  add column if not exists capacity_s integer not null default 0,
  add column if not exists capacity_m integer not null default 0,
  add column if not exists capacity_l integer not null default 0;

-- opzionale: se vuoi inizializzare la capacità totale da quelle nuove
-- (se hai già dati reali, qui puoi fare una logica diversa)
update public.partners
set capacity = greatest(capacity, capacity_s + capacity_m + capacity_l);

commit;
