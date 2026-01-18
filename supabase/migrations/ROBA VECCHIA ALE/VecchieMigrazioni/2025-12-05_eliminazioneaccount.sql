create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id    uuid := auth.uid();
  v_has_active boolean;
begin
  if v_user_id is null then
    raise exception 'Nessun utente autenticato.';
  end if;

  --------------------------------------------------------------------
  -- 1) CONTROLLO PRENOTAZIONI ATTIVE
  --    "Attive" = status in ('pending','confirmed')
  --              e data oggi o futura.
  --    NB: se booking_date è TEXT, il cast booking_date::date funziona;
  --        se è già DATE, il cast è innocuo.
  --------------------------------------------------------------------
  select exists (
    select 1
    from public.partner_bookings
    where user_id = v_user_id
      and status in ('pending','confirmed')
      and booking_date::date >= current_date
  )
  into v_has_active;

  if v_has_active then
    raise exception
      'Hai ancora prenotazioni attive. Cancella o attendi la conclusione delle prenotazioni prima di eliminare l''account.'
      using errcode = 'P0001';
  end if;

  --------------------------------------------------------------------
  -- 2) ELIMINA / PULISCI I DATI COLLEGATI ALL'UTENTE
  --------------------------------------------------------------------

  -- Prenotazioni collegate (in realtà hai già ON DELETE CASCADE
  -- sul vincolo user_id → auth.users, quindi questo è opzionale.
  delete from public.partner_bookings
  where user_id = v_user_id;

  -- Profilo utente nella tabella user_profiles
  delete from public.user_profiles
  where id = v_user_id;

  -- Se hai altre tabelle legate all'utente, aggiungi qui i delete/anonimizzazioni.

  --------------------------------------------------------------------
  -- 3) ELIMINAZIONE DALL’AUTH
  --    (qui PRIMA avevi auth.admin.delete_user(v_user_id) → ERRORE)
  --------------------------------------------------------------------
  delete from auth.users
  where id = v_user_id;

end;
$$;

grant execute on function public.delete_my_account() to authenticated;
