-- STEP 1: Booking rejection (status=rejected + reason) + irreversibilità + RPC

-- 1) Nuove colonne
ALTER TABLE public.partner_bookings
  ADD COLUMN IF NOT EXISTS reject_reason text,
  ADD COLUMN IF NOT EXISTS rejected_at timestamptz;

-- 2) Aggiorno constraint status (compatibile con la tua evoluzione stati)
ALTER TABLE public.partner_bookings
  DROP CONSTRAINT IF EXISTS partner_bookings_status_check;

ALTER TABLE public.partner_bookings
  ADD CONSTRAINT partner_bookings_status_check
  CHECK (status IN (
    -- vecchi stati (attuali in app)
    'pending',
    'confirmed',
    'cancelled',
    'completed',

    -- stati “futuri” che avevi già previsto in una migration
    'in_store',
    'cancelled_by_user',
    'cancelled_by_partner',
    'expired',

    -- ✅ nuovo stato irreversibile
    'rejected'
  ));

-- 3) Trigger guard: (a) non puoi inserire rejected in INSERT
--                  (b) solo owner/admin può passare a rejected
--                  (c) rejected è irreversibile (stato + reason + timestamp bloccati)
CREATE OR REPLACE FUNCTION public.guard_partner_booking_rejection()
RETURNS trigger AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;
  v_owner uuid;
BEGIN
  -- blocco INSERT con rejected (non deve esistere un insert "già rifiutato")
  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'rejected' THEN
      RAISE EXCEPTION 'Non puoi inserire una prenotazione con stato rejected.'
        USING errcode = 'P0001';
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF TG_OP = 'UPDATE' THEN
    -- (c) irreversibilità: se già rejected, non puoi cambiare stato/reason/rejected_at
    IF OLD.status = 'rejected' THEN
      IF NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION 'Prenotazione rifiutata: stato non modificabile.'
          USING errcode = 'P0001';
      END IF;

      IF NEW.reject_reason IS DISTINCT FROM OLD.reject_reason THEN
        RAISE EXCEPTION 'Prenotazione rifiutata: motivazione non modificabile.'
          USING errcode = 'P0001';
      END IF;

      IF NEW.rejected_at IS DISTINCT FROM OLD.rejected_at THEN
        RAISE EXCEPTION 'Prenotazione rifiutata: timestamp non modificabile.'
          USING errcode = 'P0001';
      END IF;

      RETURN NEW;
    END IF;

    -- (b) transizione a rejected: owner/admin + motivazione obbligatoria
    IF NEW.status = 'rejected' AND OLD.status IS DISTINCT FROM NEW.status THEN
      IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Non autorizzato.' USING errcode = 'P0001';
      END IF;

      SELECT (up.role = 'admin') INTO v_is_admin
      FROM public.user_profiles up
      WHERE up.id = v_uid;

      SELECT p.owner_id INTO v_owner
      FROM public.partners p
      WHERE p.id = NEW.partner_id;

      IF v_owner IS NULL THEN
        RAISE EXCEPTION 'Partner non valido.' USING errcode = 'P0001';
      END IF;

      IF COALESCE(v_is_admin, false) = false AND v_owner <> v_uid THEN
        RAISE EXCEPTION 'Solo il proprietario del locale può rifiutare la prenotazione.'
          USING errcode = 'P0001';
      END IF;

      IF trim(COALESCE(NEW.reject_reason, '')) = '' THEN
        RAISE EXCEPTION 'Motivazione obbligatoria per rifiutare.'
          USING errcode = 'P0001';
      END IF;

      -- set automatico rejected_at se non valorizzato
      IF NEW.rejected_at IS NULL THEN
        NEW.rejected_at := now();
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_partner_bookings_reject_guard ON public.partner_bookings;

CREATE TRIGGER trg_partner_bookings_reject_guard
BEFORE INSERT OR UPDATE ON public.partner_bookings
FOR EACH ROW
EXECUTE FUNCTION public.guard_partner_booking_rejection();

-- 4) RPC: chiamata “ufficiale” dal client per rifiutare con motivazione
CREATE OR REPLACE FUNCTION public.reject_partner_booking(
  p_booking_id uuid,
  p_reason text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
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
