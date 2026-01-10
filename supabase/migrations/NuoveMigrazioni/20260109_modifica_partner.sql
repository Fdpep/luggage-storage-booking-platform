-- 1. AGGIUNTA COLONNE A PARTNER_REQUESTS
ALTER TABLE public.partner_requests 
ADD COLUMN IF NOT EXISTS contract_signed_url text,
ADD COLUMN IF NOT EXISTS contract_signed_at timestamptz;

-- 2. SETUP STORAGE POLICY (Bucket: partner-contracts)
-- Assicurati di aver creato il bucket 'partner-contracts' come PRIVATO dalla dashboard prima di eseguire
INSERT INTO storage.buckets (id, name, public) 
VALUES ('partner-contracts', 'partner-contracts', false) 
ON CONFLICT (id) DO NOTHING;

-- Policy: Utente può caricare solo nella propria cartella
CREATE POLICY "Utente upload contratto proprio" 
ON storage.objects FOR INSERT 
TO authenticated 
WITH CHECK ( bucket_id = 'partner-contracts' AND (storage.foldername(name))[1] = auth.uid()::text );

-- Policy: Admin può leggere tutto
CREATE POLICY "Admin read all contracts" 
ON storage.objects FOR SELECT 
TO authenticated 
USING ( bucket_id = 'partner-contracts' AND EXISTS (SELECT 1 FROM public.user_profiles WHERE id = auth.uid() AND role = 'admin') );

-- 3. LOGICA CAPACITÀ EQUIVALENTE (VIEW + FUNCTION)
-- Questa funzione calcola la capacità occupata in unità "M" per un partner in una certa data/ora
-- Formula: S=0.5M, M=1M, L=2M
CREATE OR REPLACE FUNCTION get_partner_used_capacity_m(p_id uuid, check_time timestamptz)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  used_m integer;
BEGIN
  SELECT COALESCE(SUM(
    bags_m + 
    CEIL(bags_s::float / 2.0) + 
    (bags_l * 2)
  ), 0)
  INTO used_m
  FROM public.partner_bookings
  WHERE partner_id = p_id
    AND status IN ('pending', 'confirmed') -- Conta solo prenotazioni attive
    AND check_time >= booking_start_time 
    AND check_time <= booking_end_time; -- Logica temporale semplificata (adatta se booking è per slot)
    
  RETURN used_m;
END;
$$;

-- 4. TRIGGER FONDAMENTALE PER ADMIN (AuthGate Fix)
-- Quando admin mette partners.status = 'approved', aggiorna automaticamente user_profiles.role = 'partner'
CREATE OR REPLACE FUNCTION on_partner_approved_update_role()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status != 'approved' THEN
    UPDATE public.user_profiles
    SET role = 'partner'
    WHERE id = NEW.owner_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trigger_partner_approve_role
AFTER UPDATE ON public.partners
FOR EACH ROW
EXECUTE FUNCTION on_partner_approved_update_role();