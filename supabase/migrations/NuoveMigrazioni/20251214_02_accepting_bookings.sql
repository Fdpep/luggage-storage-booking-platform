

-- 1) Colonna su partners
ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS accepting_bookings boolean NOT NULL DEFAULT true;

CREATE INDEX IF NOT EXISTS idx_partners_accepting_bookings
  ON public.partners (accepting_bookings);

-- 2) Abilito RLS su partner_bookings (prima NON era abilitata)
ALTER TABLE public.partner_bookings ENABLE ROW LEVEL SECURITY;

-- 3) Policy SELECT: utente vede le sue prenotazioni
DROP POLICY IF EXISTS pb_select_own ON public.partner_bookings;
CREATE POLICY pb_select_own
ON public.partner_bookings
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- 4) Policy SELECT: partner (owner) vede le prenotazioni del suo locale
DROP POLICY IF EXISTS pb_select_owner ON public.partner_bookings;
CREATE POLICY pb_select_owner
ON public.partner_bookings
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.partners p
    WHERE p.id = partner_id
      AND p.owner_id = auth.uid()
  )
);

-- 5) Policy SELECT: admin vede tutto
DROP POLICY IF EXISTS pb_select_admin ON public.partner_bookings;
CREATE POLICY pb_select_admin
ON public.partner_bookings
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.user_profiles up
    WHERE up.id = auth.uid()
      AND up.role = 'admin'
  )
);

-- 6) Policy INSERT: l’utente può inserire SOLO se:
--    - user_id = auth.uid()
--    - partner is_active = true
--    - partner accepting_bookings = true
--    - partner status = 'approved'
DROP POLICY IF EXISTS pb_insert_user ON public.partner_bookings;
CREATE POLICY pb_insert_user
ON public.partner_bookings
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND EXISTS (
    SELECT 1
    FROM public.partners p
    WHERE p.id = partner_id
      AND p.is_active = true
      AND p.accepting_bookings = true
      AND p.status = 'approved'
  )
);

-- 7) (Optional ma consigliato) Guard server-side anche senza RLS (defense-in-depth)
CREATE OR REPLACE FUNCTION public.guard_partner_booking_accepting()
RETURNS trigger AS $$
DECLARE
  v_ok boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.partners p
      WHERE p.id = NEW.partner_id
        AND p.is_active = true
        AND p.accepting_bookings = true
        AND p.status = 'approved'
    ) INTO v_ok;

    IF v_ok IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'Questo partner non accetta prenotazioni al momento.'
        USING errcode = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_partner_bookings_accepting_guard ON public.partner_bookings;
CREATE TRIGGER trg_partner_bookings_accepting_guard
BEFORE INSERT ON public.partner_bookings
FOR EACH ROW
EXECUTE FUNCTION public.guard_partner_booking_accepting();

-- 8) IMPORTANTE: se ora hai RLS su partner_bookings, la tua RPC di rifiuto
--    deve poter aggiornare senza essere bloccata (dipende dai permessi).
--    La rendiamo robusta: row_security=off.
CREATE OR REPLACE FUNCTION public.reject_partner_booking(
  p_booking_id uuid,
  p_reason text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
SET row_security = off
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_partner_id uuid;
  v_owner uuid;
  v_status text;
  v_is_admin boolean := false;
  v_reason text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nessun utente autenticato.' USING errcode = 'P0001';
  END IF;

  SELECT partner_id, status
    INTO v_partner_id, v_status
  FROM public.partner_bookings
  WHERE id = p_booking_id;

  IF v_partner_id IS NULL THEN
    RAISE EXCEPTION 'Prenotazione non trovata.' USING errcode = 'P0001';
  END IF;

  SELECT owner_id INTO v_owner
  FROM public.partners
  WHERE id = v_partner_id;

  SELECT (up.role = 'admin') INTO v_is_admin
  FROM public.user_profiles up
  WHERE up.id = v_uid;

  IF COALESCE(v_is_admin, false) = false AND v_owner <> v_uid THEN
    RAISE EXCEPTION 'Non autorizzato: non sei il proprietario del locale.'
      USING errcode = 'P0001';
  END IF;

  IF v_status = 'rejected' THEN
    RAISE EXCEPTION 'Prenotazione già rifiutata.' USING errcode = 'P0001';
  END IF;

  IF v_status IN ('completed','cancelled','cancelled_by_user','cancelled_by_partner','expired') THEN
    RAISE EXCEPTION 'Non puoi rifiutare una prenotazione già chiusa/annullata.'
      USING errcode = 'P0001';
  END IF;

  v_reason := nullif(trim(coalesce(p_reason, '')), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Motivazione obbligatoria.' USING errcode = 'P0001';
  END IF;

  UPDATE public.partner_bookings
  SET status = 'rejected',
      reject_reason = v_reason,
      rejected_at = now()
  WHERE id = p_booking_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reject_partner_booking(uuid, text) TO authenticated;

-- (Optional ma utile) anche delete_my_account diventa robusta con RLS
CREATE OR REPLACE FUNCTION "public"."delete_my_account"() RETURNS "void"
LANGUAGE "plpgsql" SECURITY DEFINER
SET "search_path" TO 'public', 'auth'
SET row_security = off
AS $$
declare
  v_user_id    uuid := auth.uid();
  v_has_active boolean;
begin
  if v_user_id is null then
    raise exception 'Nessun utente autenticato.';
  end if;

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

  delete from public.partner_bookings
  where user_id = v_user_id;

  delete from public.user_profiles
  where id = v_user_id;
end;
$$;
