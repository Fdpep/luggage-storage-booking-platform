# partner_services

Servizi legati alla gestione delle **foto dei partner** (locali BagDrop).

Questa cartella contiene la logica per:

- caricare le immagini su Supabase Storage;
- gestire i metadati delle foto nella tabella `public.partner_photos` (DB).

---

## File presenti

### `partner_photo_storage.dart`

Servizio che si occupa **solo dello Storage** (file fisici):

- usa il bucket Supabase Storage `partner-photos`;
- carica i bytes di un'immagine sotto il path `<partnerId>/<fileName>`;
- imposta il `contentType` corretto (es. `image/jpeg`);
- restituisce l'**URL pubblico** del file caricato.

Non tocca il database, non crea record in tabelle:  
si occupa esclusivamente di mettere il file nel posto giusto e restituire l'URL.

Uso tipico (semplificato):

```dart
final storage = const PartnerPhotoStorage();
final url = await storage.uploadPartnerPhoto(
  partnerId: partnerId,
  fileName: 'cover.jpg',
  bytes: imageBytes,
  contentType: 'image/jpeg',
);
// Poi l'URL viene salvato nel DB tramite PartnerPhotoRepo.


/*
Dove vanno davvero le foto? E cos’è l’URL?

Per “URL” si intende un puntatore, non del file in sé.

Il flusso è così:

L’utente sceglie una foto dal telefono.

Flutter legge il file → diventa bytes (Uint8List).

Noi chiamiamo:

uploadPartnerPhoto(... bytes ...)


Supabase Storage (vai su storage dal sito supabase) salva i bytes nel bucket partner-photos
in un “percorso” tipo:

partner-photos /
  <partnerId> /
    cover.jpg
    1.jpg
    2.jpg


 QUI stanno i file veri.

Supabase ci restituisce un URL pubblico (tipo https://xyz.supabase.co/storage/v1/object/public/partner-photos/<partnerId>/cover.jpg).

Noi salviamo solo quell’URL nella tabella partner_photos.url.

Quindi:

file reale → nel bucket partner-photos (Storage)

record nel DB → partner_photos con url che punta a quel file

E nella UI userai semplicemente:

Image.network(photo.url)

per mostrare la foto. */