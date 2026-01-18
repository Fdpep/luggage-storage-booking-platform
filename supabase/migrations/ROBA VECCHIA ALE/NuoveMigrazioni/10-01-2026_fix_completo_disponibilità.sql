ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS base_capacity_u integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS extra_capacity_s integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS extra_capacity_m integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS extra_capacity_l integer NOT NULL DEFAULT 0;

-- (opzionale, ma utile per UI e futuro)
ALTER TABLE public.partners
  ADD COLUMN IF NOT EXISTS accept_s boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS accept_m boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS accept_l boolean NOT NULL DEFAULT true;


ALTER TABLE public.partner_bookings
  ADD COLUMN IF NOT EXISTS base_used_u integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS extra_used_s integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS extra_used_m integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS extra_used_l integer NOT NULL DEFAULT 0;


CREATE INDEX IF NOT EXISTS idx_pb_partner_status
  ON public.partner_bookings (partner_id, status);

CREATE INDEX IF NOT EXISTS idx_pb_interval_gist
  ON public.partner_bookings
  USING gist (tstzrange(dropoff_planned_at, pickup_planned_at, '[)'));


CREATE OR REPLACE FUNCTION public.sync_partner_capacity_derived()
RETURNS trigger AS $$
DECLARE
  v_base_s int;
  v_base_m int;
  v_base_l int;
  v_eff_s int;
  v_eff_m int;
  v_eff_l int;
BEGIN
  -- base convertita da unità
  v_base_s := GREATEST(0, NEW.base_capacity_u);
  v_base_m := floor(v_base_s::numeric / 2)::int;
  v_base_l := floor(v_base_s::numeric / 4)::int;

  v_eff_s := v_base_s + GREATEST(0, NEW.extra_capacity_s);
  v_eff_m := v_base_m + GREATEST(0, NEW.extra_capacity_m);
  v_eff_l := v_base_l + GREATEST(0, NEW.extra_capacity_l);

  NEW.capacity_s := v_eff_s;
  NEW.capacity_m := v_eff_m;
  NEW.capacity_l := v_eff_l;

  -- capacity = totale in unità equivalenti
  NEW.capacity := (v_eff_s * 1) + (v_eff_m * 2) + (v_eff_l * 4);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_partner_capacity_derived ON public.partners;

CREATE TRIGGER trg_sync_partner_capacity_derived
BEFORE INSERT OR UPDATE OF base_capacity_u, extra_capacity_s, extra_capacity_m, extra_capacity_l
ON public.partners
FOR EACH ROW
EXECUTE FUNCTION public.sync_partner_capacity_derived();


CREATE OR REPLACE FUNCTION public.get_partner_availability_for_interval_v2(
  p_partner_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_base_capacity_u int;
  v_extra_s int;
  v_extra_m int;
  v_extra_l int;

  v_used_base_u int;
  v_used_extra_s int;
  v_used_extra_m int;
  v_used_extra_l int;

  v_base_remaining_u int;
  v_extra_remaining_s int;
  v_extra_remaining_m int;
  v_extra_remaining_l int;

  v_effective_s int;
  v_effective_m int;
  v_effective_l int;
  v_effective_total_u int;
BEGIN
  IF p_start_at >= p_end_at THEN
    RAISE EXCEPTION 'Intervallo non valido' USING errcode='P0001';
  END IF;

  SELECT base_capacity_u, extra_capacity_s, extra_capacity_m, extra_capacity_l
    INTO v_base_capacity_u, v_extra_s, v_extra_m, v_extra_l
  FROM public.partners
  WHERE id = p_partner_id;

  IF v_base_capacity_u IS NULL THEN
    RAISE EXCEPTION 'Partner non trovato' USING errcode='P0001';
  END IF;

  SELECT
    COALESCE(SUM(base_used_u), 0),
    COALESCE(SUM(extra_used_s), 0),
    COALESCE(SUM(extra_used_m), 0),
    COALESCE(SUM(extra_used_l), 0)
  INTO v_used_base_u, v_used_extra_s, v_used_extra_m, v_used_extra_l
  FROM public.partner_bookings pb
  WHERE pb.partner_id = p_partner_id
    AND pb.status IN ('pending','confirmed','in_store')
    AND tstzrange(pb.dropoff_planned_at, pb.pickup_planned_at, '[)') &&
        tstzrange(p_start_at, p_end_at, '[)');

  v_base_remaining_u := GREATEST(0, v_base_capacity_u - v_used_base_u);
  v_extra_remaining_s := GREATEST(0, v_extra_s - v_used_extra_s);
  v_extra_remaining_m := GREATEST(0, v_extra_m - v_used_extra_m);
  v_extra_remaining_l := GREATEST(0, v_extra_l - v_used_extra_l);

  -- Derivate (per UI): effettive per taglia (attenzione: base condivisa non è realmente “separata”, ma serve per display)
  v_effective_s := v_base_capacity_u + v_extra_s;
  v_effective_m := floor(v_base_capacity_u::numeric/2)::int + v_extra_m;
  v_effective_l := floor(v_base_capacity_u::numeric/4)::int + v_extra_l;
  v_effective_total_u := (v_effective_s*1) + (v_effective_m*2) + (v_effective_l*4);

  RETURN jsonb_build_object(
    'partner_id', p_partner_id,
    'start_at', p_start_at,
    'end_at', p_end_at,

    'base_capacity_u', v_base_capacity_u,
    'base_used_u', v_used_base_u,
    'base_remaining_u', v_base_remaining_u,

    'extra_capacity_s', v_extra_s,
    'extra_capacity_m', v_extra_m,
    'extra_capacity_l', v_extra_l,

    'extra_used_s', v_used_extra_s,
    'extra_used_m', v_used_extra_m,
    'extra_used_l', v_used_extra_l,

    'extra_remaining_s', v_extra_remaining_s,
    'extra_remaining_m', v_extra_remaining_m,
    'extra_remaining_l', v_extra_remaining_l,

    'effective_capacity_s', v_effective_s,
    'effective_capacity_m', v_effective_m,
    'effective_capacity_l', v_effective_l,
    'effective_capacity_total_u', v_effective_total_u
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_partner_availability_for_interval_v2(uuid, timestamptz, timestamptz)
TO authenticated, anon;


CREATE OR REPLACE FUNCTION public.create_partner_booking_v2(
  p_partner_id uuid,
  p_contact_first_name text,
  p_contact_last_name text,
  p_contact_phone text,
  p_contact_email text,
  p_bags_s int,
  p_bags_m int,
  p_bags_l int,
  p_dropoff_planned_at timestamptz,
  p_pickup_planned_at timestamptz,
  p_notes text default null
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
SET row_security = off
AS $$
DECLARE
  v_uid uuid := auth.uid();

  v_base_capacity_u int;
  v_extra_s int;
  v_extra_m int;
  v_extra_l int;

  v_used_base_u int;
  v_used_extra_s int;
  v_used_extra_m int;
  v_used_extra_l int;

  v_base_remaining_u int;
  v_extra_remaining_s int;
  v_extra_remaining_m int;
  v_extra_remaining_l int;

  v_need_u int;
  v_excess_u int;

  -- allocation da extra
  xS int := 0;
  xM int := 0;
  xL int := 0;

  v_best_xS int := 0;
  v_best_xM int := 0;
  v_best_xL int := 0;
  v_found boolean := false;
  v_score int;

  v_booking_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Nessun utente autenticato.' USING errcode='P0001';
  END IF;

  IF p_dropoff_planned_at IS NULL
     OR p_pickup_planned_at IS NULL
     OR p_dropoff_planned_at >= p_pickup_planned_at THEN
    RAISE EXCEPTION 'Intervallo non valido.' USING errcode='P0001';
  END IF;

  IF COALESCE(p_bags_s,0) < 0
     OR COALESCE(p_bags_m,0) < 0
     OR COALESCE(p_bags_l,0) < 0
     OR (COALESCE(p_bags_s,0)+COALESCE(p_bags_m,0)+COALESCE(p_bags_l,0)) = 0 THEN
    RAISE EXCEPTION 'Bagagli non validi.' USING errcode='P0001';
  END IF;

  -- lock partner
  SELECT base_capacity_u, extra_capacity_s, extra_capacity_m, extra_capacity_l
    INTO v_base_capacity_u, v_extra_s, v_extra_m, v_extra_l
  FROM public.partners
  WHERE id = p_partner_id
    AND is_active = true
    AND accepting_bookings = true
    AND status = 'approved'
  FOR UPDATE;

  IF v_base_capacity_u IS NULL THEN
    RAISE EXCEPTION 'Partner non prenotabile.' USING errcode='P0001';
  END IF;

  -- lock bookings overlapping (anti race)
  PERFORM 1
  FROM public.partner_bookings pb
  WHERE pb.partner_id = p_partner_id
    AND pb.status IN ('pending','confirmed','in_store')
    AND pb.dropoff_planned_at IS NOT NULL
    AND pb.pickup_planned_at IS NOT NULL
    AND tstzrange(pb.dropoff_planned_at, pb.pickup_planned_at, '[)') &&
        tstzrange(p_dropoff_planned_at, p_pickup_planned_at, '[)')
  FOR UPDATE;

  -- used in interval
  SELECT
    COALESCE(SUM(base_used_u), 0),
    COALESCE(SUM(extra_used_s), 0),
    COALESCE(SUM(extra_used_m), 0),
    COALESCE(SUM(extra_used_l), 0)
  INTO v_used_base_u, v_used_extra_s, v_used_extra_m, v_used_extra_l
  FROM public.partner_bookings pb
  WHERE pb.partner_id = p_partner_id
    AND pb.status IN ('pending','confirmed','in_store')
    AND pb.dropoff_planned_at IS NOT NULL
    AND pb.pickup_planned_at IS NOT NULL
    AND tstzrange(pb.dropoff_planned_at, pb.pickup_planned_at, '[)') &&
        tstzrange(p_dropoff_planned_at, p_pickup_planned_at, '[)');

  v_base_remaining_u := GREATEST(0, v_base_capacity_u - v_used_base_u);
  v_extra_remaining_s := GREATEST(0, v_extra_s - v_used_extra_s);
  v_extra_remaining_m := GREATEST(0, v_extra_m - v_used_extra_m);
  v_extra_remaining_l := GREATEST(0, v_extra_l - v_used_extra_l);

  v_need_u := COALESCE(p_bags_s,0)*1 + COALESCE(p_bags_m,0)*2 + COALESCE(p_bags_l,0)*4;

  IF v_need_u <= v_base_remaining_u THEN
    -- tutto base
    v_best_xS := 0;
    v_best_xM := 0;
    v_best_xL := 0;
    v_found := true;
  ELSE
    v_excess_u := v_need_u - v_base_remaining_u;

    -- cerco combinazione extra che copra excess_u senza superare bags richiesti e extra disponibili.
    -- Loop su L e M, calcolo S necessario.
    FOR xL IN 0..LEAST(COALESCE(p_bags_l,0), v_extra_remaining_l) LOOP
      FOR xM IN 0..LEAST(COALESCE(p_bags_m,0), v_extra_remaining_m) LOOP
        xS := GREATEST(0, v_excess_u - (4*xL) - (2*xM)); -- unità rimanenti da coprire con S

        IF xS <= LEAST(COALESCE(p_bags_s,0), v_extra_remaining_s) THEN
          -- score: minimizza unità da extra, poi numero di bag extra (preferisci usare base)
          v_score := (xS*1 + xM*2 + xL*4) * 1000 + (xS + xM + xL);

          IF v_found = false
             OR v_score < ((v_best_xS*1 + v_best_xM*2 + v_best_xL*4) * 1000 + (v_best_xS+v_best_xM+v_best_xL)) THEN
            v_best_xS := xS;
            v_best_xM := xM;
            v_best_xL := xL;
            v_found := true;
          END IF;
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  IF v_found = false THEN
    RAISE EXCEPTION 'Capacità insufficiente per l''intervallo selezionato.' USING errcode='P0001';
  END IF;

  -- inserisco booking con allocation
  INSERT INTO public.partner_bookings (
    partner_id, user_id, status,
    contact_first_name, contact_last_name, contact_phone, contact_email,
    bags_s, bags_m, bags_l, notes,
    dropoff_planned_at, pickup_planned_at,
    base_used_u, extra_used_s, extra_used_m, extra_used_l
  )
  VALUES (
    p_partner_id, v_uid, 'confirmed',
    p_contact_first_name, p_contact_last_name, p_contact_phone, p_contact_email,
    COALESCE(p_bags_s,0), COALESCE(p_bags_m,0), COALESCE(p_bags_l,0), p_notes,
    p_dropoff_planned_at, p_pickup_planned_at,
    v_need_u - (v_best_xS*1 + v_best_xM*2 + v_best_xL*4),
    v_best_xS, v_best_xM, v_best_xL
  )
  RETURNING id INTO v_booking_id;

  RETURN v_booking_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_partner_booking_v2(
  uuid, text, text, text, text, int, int, int, timestamptz, timestamptz, text
) TO authenticated;

DROP INDEX IF EXISTS public.idx_pb_interval_gist;

CREATE INDEX IF NOT EXISTS idx_pb_interval_gist
  ON public.partner_bookings
  USING gist (tstzrange(dropoff_planned_at, pickup_planned_at, '[)'))
  WHERE dropoff_planned_at IS NOT NULL AND pickup_planned_at IS NOT NULL;


DROP TRIGGER IF EXISTS trg_sync_partner_capacity_derived ON public.partners;

CREATE TRIGGER trg_sync_partner_capacity_derived_ins
BEFORE INSERT ON public.partners
FOR EACH ROW
EXECUTE FUNCTION public.sync_partner_capacity_derived();

CREATE TRIGGER trg_sync_partner_capacity_derived_upd
BEFORE UPDATE OF base_capacity_u, extra_capacity_s, extra_capacity_m, extra_capacity_l ON public.partners
FOR EACH ROW
EXECUTE FUNCTION public.sync_partner_capacity_derived();


CREATE OR REPLACE FUNCTION public.get_partner_availability_for_interval_v2(
  p_partner_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_base_capacity_u int;
  v_extra_s int;
  v_extra_m int;
  v_extra_l int;

  v_used_base_u int;
  v_used_extra_s int;
  v_used_extra_m int;
  v_used_extra_l int;

  v_base_remaining_u int;
  v_extra_remaining_s int;
  v_extra_remaining_m int;
  v_extra_remaining_l int;

  v_effective_s int;
  v_effective_m int;
  v_effective_l int;
  v_effective_total_u int;
BEGIN
  IF p_start_at IS NULL OR p_end_at IS NULL OR p_start_at >= p_end_at THEN
    RAISE EXCEPTION 'Intervallo non valido' USING errcode='P0001';
  END IF;

  SELECT base_capacity_u, extra_capacity_s, extra_capacity_m, extra_capacity_l
    INTO v_base_capacity_u, v_extra_s, v_extra_m, v_extra_l
  FROM public.partners
  WHERE id = p_partner_id;

  IF v_base_capacity_u IS NULL THEN
    RAISE EXCEPTION 'Partner non trovato' USING errcode='P0001';
  END IF;

  SELECT
    COALESCE(SUM(base_used_u), 0),
    COALESCE(SUM(extra_used_s), 0),
    COALESCE(SUM(extra_used_m), 0),
    COALESCE(SUM(extra_used_l), 0)
  INTO v_used_base_u, v_used_extra_s, v_used_extra_m, v_used_extra_l
  FROM public.partner_bookings pb
  WHERE pb.partner_id = p_partner_id
    AND pb.status IN ('pending','confirmed','in_store')
    AND pb.dropoff_planned_at IS NOT NULL
    AND pb.pickup_planned_at IS NOT NULL
    AND tstzrange(pb.dropoff_planned_at, pb.pickup_planned_at, '[)') &&
        tstzrange(p_start_at, p_end_at, '[)');

  v_base_remaining_u := GREATEST(0, v_base_capacity_u - v_used_base_u);
  v_extra_remaining_s := GREATEST(0, v_extra_s - v_used_extra_s);
  v_extra_remaining_m := GREATEST(0, v_extra_m - v_used_extra_m);
  v_extra_remaining_l := GREATEST(0, v_extra_l - v_used_extra_l);

  -- Derivate (solo display/UI)
  v_effective_s := v_base_capacity_u + v_extra_s;
  v_effective_m := floor(v_base_capacity_u::numeric/2)::int + v_extra_m;
  v_effective_l := floor(v_base_capacity_u::numeric/4)::int + v_extra_l;
  v_effective_total_u := (v_effective_s*1) + (v_effective_m*2) + (v_effective_l*4);

  RETURN jsonb_build_object(
    'partner_id', p_partner_id,
    'start_at', p_start_at,
    'end_at', p_end_at,

    'base_capacity_u', v_base_capacity_u,
    'base_used_u', v_used_base_u,
    'base_remaining_u', v_base_remaining_u,

    'extra_capacity_s', v_extra_s,
    'extra_capacity_m', v_extra_m,
    'extra_capacity_l', v_extra_l,

    'extra_used_s', v_used_extra_s,
    'extra_used_m', v_used_extra_m,
    'extra_used_l', v_used_extra_l,

    'extra_remaining_s', v_extra_remaining_s,
    'extra_remaining_m', v_extra_remaining_m,
    'extra_remaining_l', v_extra_remaining_l,

    'effective_capacity_s', v_effective_s,
    'effective_capacity_m', v_effective_m,
    'effective_capacity_l', v_effective_l,
    'effective_capacity_total_u', v_effective_total_u
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_partner_availability_for_interval_v2(uuid, timestamptz, timestamptz)
TO authenticated, anon;

