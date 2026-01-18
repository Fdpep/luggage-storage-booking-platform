-- ============================================
-- BagDrop - Migration unica QR + rifiuto irreversibile (no "rejected")
-- - rejected => cancelled_by_partner
-- - rifiuto irreversibile: status+reason+timestamp non modificabili
-- - QR statico: qr_token (uuid) + time window server-side
-- - RPC: get_booking_qr_payload / process_booking_qr / reject_partner_booking
-- ============================================

BEGIN;

-- 0) Safety: RLS ON (se già ON non fa danni)
ALTER TABLE public.partner_bookings ENABLE ROW LEVEL SECURITY;

-- 1) Rimuovo eventuale vecchio trigger/funzione che bloccava "rejected" (quello che ti ha dato P0001)
DROP TRIGGER IF EXISTS trg_partner_bookings_reject_guard ON public.partner_bookings;
DROP FUNCTION IF EXISTS public.guard_partner_booking_rejection();

-- 2) Colonne per rifiuto (se non esistono già)
ALTER TABLE public.partner_bookings
  ADD COLUMN IF NOT EXISTS reject_reason text,
  ADD COLUMN IF NOT EXISTS rejected_at timestamptz;

-- 3) end_date + nuovi timestamp (se non esistono già)
ALTER TABLE public.partner_bookings
  ADD COLUMN IF NOT EXISTS end_date date;

ALTER TABLE public.partner_bookings
  ADD COLUMN IF NOT EXISTS dropoff_planned_at timestamptz,
  ADD COLUMN IF NOT EXISTS pickup_planned_at  timestamptz,
  ADD COLUMN IF NOT EXISTS dropoff_effective_at timestamptz,
  ADD COLUMN IF NOT EXISTS pickup_effective_at  timestamptz;

-- 4) QR statico: token per booking
ALTER TABLE public.partner_bookings
  ADD COLUMN IF NOT EXISTS qr_token uuid;

-- 5) Backfill end_date
UPDATE public.partner_bookings
SET end_date = booking_date
WHERE end_date IS NULL;

-- 6) Tolgo constraint status (per poter fare conversioni senza blocchi)
ALTER TABLE public.partner_bookings
  DROP CONSTRAINT IF EXISTS partner_bookings_status_check;

-- 7) Converto eventuali record legacy
--    - rejected -> cancelled_by_partner (e resta la reason/ts)
UPDATE public.partner_bookings
SET status = 'cancelled_by_partner'
WHERE status = 'rejected';

-- 8) Constraint status ufficiale (SENZA 'rejected')
ALTER TABLE public.partner_bookings
  ADD CONSTRAINT partner_bookings_status_check
  CHECK (status IN (
    'pending',
    'confirmed',
    'in_store',
    'completed',
    'cancelled',              -- legacy
    'cancelled_by_user',
    'cancelled_by_partner',
    'expired'
  ));

-- 9) Funzione sync intervallo (planned_at) da booking_date + time + end_date
CREATE OR REPLACE FUNCTION public.sync_booking_interval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
SET row_security = off
AS $$
BEGIN
  -- Consegna prevista
  IF NEW.booking_date IS NOT NULL AND NEW.start_time IS NOT NULL THEN
    NEW.dropoff_planned_at :=
      ((NEW.booking_date::text || ' ' || NEW.start_time::text)::timestamp
        AT TIME ZONE 'Europe/Rome');
  END IF;

  -- Ritiro previsto
  IF COALESCE(NEW.end_date, NEW.booking_date) IS NOT NULL
     AND NEW.end_time IS NOT NULL THEN
    NEW.pickup_planned_at :=
      ((COALESCE(NEW.end_date, NEW.booking_date)::text || ' ' || NEW.end_time::text)::timestamp
        AT TIME ZONE 'Europe/Rome');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_booking_interval ON public.partner_bookings;
CREATE TRIGGER trg_sync_booking_interval
BEFORE INSERT OR UPDATE ON public.partner_bookings
FOR EACH ROW
EXECUTE FUNCTION public.sync_booking_interval();

-- Backfill planned_at per righe esistenti (se NULL)
UPDATE public.partner_bookings
SET dropoff_planned_at =
      ((booking_date::text || ' ' || start_time::text)::timestamp AT TIME ZONE 'Europe/Rome')
WHERE dropoff_planned_at IS NULL AND booking_date IS NOT NULL AND start_time IS NOT NULL;

UPDATE public.partner_bookings
SET pickup_planned_at =
      ((COALESCE(end_date, booking_date)::text || ' ' || end_time::text)::timestamp AT TIME ZONE 'Europe/Rome')
WHERE pickup_planned_at IS NULL AND COALESCE(end_date, booking_date) IS NOT NULL AND end_time IS NOT NULL;

-- 10) Backfill qr_token + index unique
UPDATE public.partner_bookings
SET qr_token = gen_random_uuid()
WHERE qr_token IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_partner_bookings_qr_token
ON public.partner_bookings (qr_token);

-- 11) Trigger per garantire qr_token su INSERT
CREATE OR REPLACE FUNCTION public.set_booking_qr_token()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF NEW.qr_token IS NULL THEN
    NEW.qr_token := gen_random_uuid();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_booking_qr_token ON public.partner_bookings;
CREATE TRIGGER trg_set_booking_qr_token
BEFORE INSERT ON public.partner_bookings
FOR EACH ROW
EXECUTE FUNCTION public.set_booking_qr_token();

-- 12) Guard: rifiuto irreversibile (cancelled_by_partner) + reason obbligatoria + solo owner/admin
CREATE OR REPLACE FUNCTION public.guard_partner_booking_partner_cancel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
SET row_security = off
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;
  v_owner uuid;
BEGIN
  -- Blocca INSERT già annullato dal partner / rejected legacy
  IF TG_OP = 'INSERT' THEN
    IF NEW.status IN ('cancelled_by_partner','rejected') THEN
      RAISE EXCEPTION 'Non puoi inserire una prenotazione già rifiutata/annullata.'
        USING errcode = 'P0001';
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE: se già cancelled_by_partner -> irreversibile su stato/reason/rejected_at
  IF TG_OP = 'UPDATE' THEN
    IF OLD.status = 'cancelled_by_partner' THEN
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

    -- Non permetto settaggio "rejected" (non esiste più)
    IF NEW.status = 'rejected' THEN
      RAISE EXCEPTION 'Stato rejected non supportato: usare cancelled_by_partner.'
        USING errcode = 'P0001';
    END IF;

    -- Transizione a cancelled_by_partner: solo owner/admin + reason obbligatoria + set rejected_at
    IF NEW.status = 'cancelled_by_partner' AND OLD.status IS DISTINCT FROM NEW.status THEN
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

      IF COALESCE(v_is_admin,false) = false AND v_owner <> v_uid THEN
        RAISE EXCEPTION 'Solo il proprietario (o admin) può rifiutare la prenotazione.'
          USING errcode = 'P0001';
      END IF;

      IF trim(COALESCE(NEW.reject_reason,'')) = '' THEN
        RAISE EXCEPTION 'Motivazione obbligatoria per rifiutare.'
          USING errcode = 'P0001';
      END IF;

      IF NEW.rejected_at IS NULL THEN
        NEW.rejected_at := now();
      END IF;
    END IF;

    -- Se qualcuno prova a scrivere reject_reason/rejected_at senza essere in cancelled_by_partner → blocco
    IF (NEW.reject_reason IS DISTINCT FROM OLD.reject_reason OR NEW.rejected_at IS DISTINCT FROM OLD.rejected_at)
       AND NEW.status <> 'cancelled_by_partner' THEN
      RAISE EXCEPTION 'reject_reason/rejected_at ammessi solo con status cancelled_by_partner.'
        USING errcode = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_partner_bookings_cancel_guard ON public.partner_bookings;
CREATE TRIGGER trg_partner_bookings_cancel_guard
BEFORE INSERT OR UPDATE ON public.partner_bookings
FOR EACH ROW
EXECUTE FUNCTION public.guard_partner_booking_partner_cancel();

-- 13) RPC: rifiuto partner (irreversibile) -> status = cancelled_by_partner
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

  IF COALESCE(v_is_admin,false) = false AND v_owner <> v_uid THEN
    RAISE EXCEPTION 'Non autorizzato: non sei il proprietario del locale.'
      USING errcode = 'P0001';
  END IF;

  IF v_status = 'cancelled_by_partner' THEN
    RAISE EXCEPTION 'Prenotazione già rifiutata.' USING errcode = 'P0001';
  END IF;

  IF v_status IN ('completed','cancelled','cancelled_by_user','expired') THEN
    RAISE EXCEPTION 'Non puoi rifiutare una prenotazione già chiusa/annullata.'
      USING errcode = 'P0001';
  END IF;

  v_reason := nullif(trim(coalesce(p_reason, '')), '');
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Motivazione obbligatoria.' USING errcode = 'P0001';
  END IF;

  UPDATE public.partner_bookings
  SET status = 'cancelled_by_partner',
      reject_reason = v_reason,
      rejected_at = now()
  WHERE id = p_booking_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reject_partner_booking(uuid, text) TO authenticated;

-- 14) RPC: payload QR (utente) - token statico + info utili
CREATE OR REPLACE FUNCTION public.get_booking_qr_payload(
  p_booking_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
SET row_security = off
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;
  v_user_id uuid;
  v_status text;
  v_token uuid;
  v_partner_id uuid;
  v_dropoff timestamptz;
  v_pickup timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nessun utente autenticato.' USING errcode = 'P0001';
  END IF;

  SELECT (up.role = 'admin') INTO v_is_admin
  FROM public.user_profiles up
  WHERE up.id = v_uid;

  SELECT user_id, status, qr_token, partner_id, dropoff_planned_at, pickup_planned_at
  INTO v_user_id, v_status, v_token, v_partner_id, v_dropoff, v_pickup
  FROM public.partner_bookings
  WHERE id = p_booking_id;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Prenotazione non trovata.' USING errcode = 'P0001';
  END IF;

  -- Solo owner della prenotazione (o admin) può ottenere il QR
  IF COALESCE(v_is_admin,false) = false AND v_user_id <> v_uid THEN
    RAISE EXCEPTION 'Non autorizzato.' USING errcode = 'P0001';
  END IF;

  -- QR disponibile solo se "confirmed" o "in_store"
  IF v_status NOT IN ('confirmed','in_store') THEN
    RAISE EXCEPTION 'QR non disponibile per questo stato (%).', v_status
      USING errcode = 'P0001';
  END IF;

  RETURN jsonb_build_object(
    'booking_id', p_booking_id::text,
    'token', v_token::text,
    'partner_id', v_partner_id::text,
    'status', v_status,
    'dropoff_planned_at', v_dropoff,
    'pickup_planned_at', v_pickup
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_booking_qr_payload(uuid) TO authenticated;

-- 15) RPC: scan partner (check-in / check-out) con finestra temporale
CREATE OR REPLACE FUNCTION public.process_booking_qr(
  p_booking_id uuid,
  p_token uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
SET row_security = off
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := false;

  v_partner_id uuid;
  v_owner uuid;
  v_status text;
  v_db_token uuid;

  v_dropoff timestamptz;
  v_pickup  timestamptz;
  v_now timestamptz := now();

  -- ✅ finestra temporale (tweak qui):
  v_window_before interval := interval '2 hours';
  v_window_after  interval := interval '2 hours';

  v_action text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nessun utente autenticato.' USING errcode = 'P0001';
  END IF;

  SELECT (up.role = 'admin') INTO v_is_admin
  FROM public.user_profiles up
  WHERE up.id = v_uid;

  SELECT partner_id, status, qr_token, dropoff_planned_at, pickup_planned_at
  INTO v_partner_id, v_status, v_db_token, v_dropoff, v_pickup
  FROM public.partner_bookings
  WHERE id = p_booking_id;

  IF v_partner_id IS NULL THEN
    RAISE EXCEPTION 'Prenotazione non trovata.' USING errcode = 'P0001';
  END IF;

  SELECT owner_id INTO v_owner
  FROM public.partners
  WHERE id = v_partner_id;

  IF COALESCE(v_is_admin,false) = false AND v_owner <> v_uid THEN
    RAISE EXCEPTION 'Non autorizzato: non sei il proprietario del locale.'
      USING errcode = 'P0001';
  END IF;

  IF v_db_token IS NULL THEN
    RAISE EXCEPTION 'QR token mancante.' USING errcode = 'P0001';
  END IF;

  IF v_db_token <> p_token THEN
    RAISE EXCEPTION 'QR non valido.' USING errcode = 'P0001';
  END IF;

  -- Stati non processabili
  IF v_status IN ('cancelled','cancelled_by_user','cancelled_by_partner','expired','completed') THEN
    RAISE EXCEPTION 'Prenotazione non processabile (stato=%).', v_status
      USING errcode = 'P0001';
  END IF;

  -- Se per qualche motivo planned_at è null, prova a ricostruirli (best-effort)
  IF v_dropoff IS NULL OR v_pickup IS NULL THEN
    UPDATE public.partner_bookings
    SET dropoff_planned_at = COALESCE(dropoff_planned_at,
          ((booking_date::text || ' ' || start_time::text)::timestamp AT TIME ZONE 'Europe/Rome')),
        pickup_planned_at  = COALESCE(pickup_planned_at,
          ((COALESCE(end_date, booking_date)::text || ' ' || end_time::text)::timestamp AT TIME ZONE 'Europe/Rome'))
    WHERE id = p_booking_id
    RETURNING dropoff_planned_at, pickup_planned_at
    INTO v_dropoff, v_pickup;
  END IF;

  -- CHECK-IN: confirmed -> in_store
  IF v_status = 'confirmed' THEN
    IF v_dropoff IS NULL THEN
      RAISE EXCEPTION 'dropoff_planned_at mancante.' USING errcode = 'P0001';
    END IF;

    IF NOT (v_now >= (v_dropoff - v_window_before) AND v_now <= (v_dropoff + v_window_after)) THEN
      RAISE EXCEPTION 'Fuori finestra check-in.' USING errcode = 'P0001';
    END IF;

    UPDATE public.partner_bookings
    SET status = 'in_store',
        dropoff_effective_at = COALESCE(dropoff_effective_at, v_now)
    WHERE id = p_booking_id;

    v_action := 'check_in';

    RETURN jsonb_build_object(
      'ok', true,
      'action', v_action,
      'new_status', 'in_store',
      'dropoff_effective_at', v_now
    );
  END IF;

  -- CHECK-OUT: in_store -> completed
  IF v_status = 'in_store' THEN
    IF v_pickup IS NULL THEN
      RAISE EXCEPTION 'pickup_planned_at mancante.' USING errcode = 'P0001';
    END IF;

    IF NOT (v_now >= (v_pickup - v_window_before) AND v_now <= (v_pickup + v_window_after)) THEN
      RAISE EXCEPTION 'Fuori finestra check-out.' USING errcode = 'P0001';
    END IF;

    UPDATE public.partner_bookings
    SET status = 'completed',
        pickup_effective_at = COALESCE(pickup_effective_at, v_now)
    WHERE id = p_booking_id;

    v_action := 'check_out';

    RETURN jsonb_build_object(
      'ok', true,
      'action', v_action,
      'new_status', 'completed',
      'pickup_effective_at', v_now
    );
  END IF;

  -- Pending o altro
  RAISE EXCEPTION 'Stato non valido per lo scan (stato=%).', v_status
    USING errcode = 'P0001';
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_booking_qr(uuid, uuid) TO authenticated;

-- 16) (Ri)creo policies essenziali su partner_bookings (select/insert) se vuoi essere sicuro
--     NB: update policies NON le metto: gli update passano via RPC (SECURITY DEFINER).

DROP POLICY IF EXISTS pb_select_own ON public.partner_bookings;
CREATE POLICY pb_select_own
ON public.partner_bookings
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

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

-- insert: utente può inserire solo se partner prenotabile (is_active + accepting + approved)
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

COMMIT;
