ALTER TABLE public.partner_bookings
ADD COLUMN booking_date date NOT NULL DEFAULT (CURRENT_DATE),
ADD COLUMN start_time time NOT NULL DEFAULT '00:00',
ADD COLUMN end_time time NOT NULL DEFAULT '23:59';

