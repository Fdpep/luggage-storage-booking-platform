-- 1) Aggiungo la colonna end_date (solo data, senza orario)
ALTER TABLE public.partner_bookings
ADD COLUMN end_date date;

-- 2) Backfill: per tutte le prenotazioni esistenti,
--    se end_date è NULL la mettiamo uguale a booking_date
UPDATE public.partner_bookings
SET end_date = booking_date
WHERE end_date IS NULL;


--AGGIUNTA DI CAMPI PER STATI FUTURI--

ALTER TABLE public.partner_bookings
ADD COLUMN dropoff_planned_at timestamptz,
ADD COLUMN pickup_planned_at  timestamptz,
ADD COLUMN dropoff_effective_at timestamptz,
ADD COLUMN pickup_effective_at  timestamptz;



--AGGIORNAMENTO ENUM PER STATI FUTURI--

ALTER TABLE public.partner_bookings
  DROP CONSTRAINT partner_bookings_status_check;

ALTER TABLE public.partner_bookings
  ADD CONSTRAINT partner_bookings_status_check
  CHECK (status IN (
    'pending',            -- prenotata ma non ancora pagata/confirm (se servirà)
    'confirmed',          -- pagata + confermata, in attesa consegna
    'in_store',           -- bagagli consegnati, in magazzino
    'completed',          -- chiusa correttamente (ritiro ok)
    'cancelled_by_user',  -- cancellata dall’utente
    'cancelled_by_partner', -- cancellata dal partner
    'expired'             -- mai consegnata o mai ritirata nei tempi
  ));




-- STEP 3.1: funzione di sync
CREATE OR REPLACE FUNCTION public.sync_booking_interval()
RETURNS trigger AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER;






-- STEP 3.2: trigger
DROP TRIGGER IF EXISTS trg_sync_booking_interval ON public.partner_bookings;

CREATE TRIGGER trg_sync_booking_interval
BEFORE INSERT OR UPDATE ON public.partner_bookings
FOR EACH ROW
EXECUTE FUNCTION public.sync_booking_interval();
