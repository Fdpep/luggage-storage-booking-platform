CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public, auth
AS $$
declare
  v_user_id    uuid := auth.uid();
  v_has_active boolean;
begin
  if v_user_id is null then
    raise exception 'Nessun utente autenticato.';
  end if;

  -- 1) CONTROLLO PRENOTAZIONI ATTIVE
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

  -- 2) ELIMINA / PULISCI I DATI COLLEGATI ALL'UTENTE
  delete from public.partner_bookings
  where user_id = v_user_id;

  delete from public.user_profiles
  where id = v_user_id;

  -- Se hai altre tabelle legate all’utente, aggiungile qui
  -- es: delete from public.partners where owner_id = v_user_id;

  -- 3) ELIMINA L'UTENTE DA auth.users (qui servono i permessi del SECURITY DEFINER)
  delete from auth.users
  where id = v_user_id;
end;
$$;

ALTER FUNCTION public.delete_my_account() OWNER TO postgres;

GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;
