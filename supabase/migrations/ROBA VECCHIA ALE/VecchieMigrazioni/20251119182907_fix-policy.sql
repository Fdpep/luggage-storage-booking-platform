-- Consenti agli utenti autenticati di caricare foto nel bucket "partner-photos"
create policy "allow authenticated upload partner photos"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'partner-photos');

-- (facoltativo ma utile) consenti agli autenticati di leggere le foto
create policy "allow authenticated read partner photos"
on storage.objects
for select
to authenticated
using (bucket_id = 'partner-photos');
