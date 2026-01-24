-- Aggiungo i campi requested
ALTER TABLE public.partner_bookings
ADD COLUMN end_date_requested date,
ADD COLUMN end_time_requested time;

-- Backfill requested per record esistenti: requested = quello attuale
UPDATE public.partner_bookings
SET
  end_date_requested = COALESCE(end_date, booking_date),
  end_time_requested = end_time
WHERE end_date_requested IS NULL OR end_time_requested IS NULL;

--aggiunta colonne per orari riepilogo
ALTER TABLE public.partner_bookings
ADD COLUMN IF NOT EXISTS end_date_requested date,
ADD COLUMN IF NOT EXISTS end_time_requested time;
