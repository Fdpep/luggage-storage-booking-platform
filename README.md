# 🧳 BagDrop – Flutter App

BagDrop è una piattaforma mobile che permette agli utenti di trovare attività partner (bar, negozi, hotel, negozi di prossimità) dove lasciare i propri bagagli in modo sicuro.  
L’app è sviluppata in **Flutter** e utilizza **Supabase** come backend per autenticazione, database e storage.

---

# 🚀 Funzionalità Principali

## 👤 Utente

- Registrazione tramite email + password
- Verifica email via codice OTP
- Login / Logout
- Mappa interattiva con marker dei partner approvati e attivi
- Scheda dettagliata partner:
  - foto
  - descrizione
  - regole
  - prezzi
  - **orari di apertura per giorno della settimana (Lun–Dom)**
  - eventuali **chiusure straordinarie / aperture straordinarie**
  - posizione su mappa
- **Flusso di prenotazione deposito bagagli presso un partner**, con:
  - step guidati (**Contatto → Data e orario → Bagagli → Riepilogo**)
  - scelta della **modalità di durata**:
    - 3 ore veloci
    - durata personalizzata (fino a più giorni, incluso il caso “giorno e mezzo”)
  - selezione:
    - data/ora di **consegna** dei bagagli
    - data/ora di **ritiro** dei bagagli
  - inserimento:
    - nome, cognome, telefono, email, note
    - bagagli per taglia **S / M / L**
  - salvataggio in `partner_bookings` con:
    - riferimento all’utente (`user_id`)
    - riferimento al partner (`partner_id`)
    - dati di contatto “fotografati” (anche se l’utente cambia profilo in futuro)
    - numero di bagagli S/M/L
    - **data/ora di consegna** (`booking_date`, `start_time`)
    - **data/ora di ritiro** (`end_date`, `end_time`)
    - timestamp di creazione (`created_at`)
- **Schermata “Le mie prenotazioni”**:
  - tab dedicata nella home utente
  - lista delle prenotazioni con:
    - stato (confirmed/pending/cancelled)
    - data di creazione
    - **data/ora di consegna e ritiro**
    - **nome attività (partner)** caricato da `PartnerRepo.getPartnerById(...)`
    - totale bagagli
  - tap su una prenotazione → apre:
    - **scheda attività collegata** (`BookingPartnerDetailScreen`)
    - da cui si può vedere il riepilogo della prenotazione (`BookingRecapScreen`)

- **Profilo utente & gestione account**:
  - tab “Profilo” nella `HomeShell`
  - mostra:
    - email dell’account
    - nome, cognome e telefono letti dai metadata Supabase (`user.userMetadata`)
  - form per **modificare nome, cognome e telefono** con validazione base sul numero (solo cifre 9–15 caratteri)
  - pulsante rosso **“Elimina account”**:
    - apre una schermata dedicata (`DeleteAccountScreen`)
    - l’utente genera un **codice alfanumerico casuale**, che deve poi riscrivere per abilitare il tasto di conferma
    - viene chiamata la funzione SQL `public.delete_my_account()` su Supabase
    - l’eliminazione viene eseguita **solo se non esistono prenotazioni attive** collegate a quell’utente
    - dopo la cancellazione viene eseguito `auth.signOut()` lato client

> N.B.: la logica di slot orari è per ora **semplificata**: esiste una gestione base di data/ora di consegna/ritiro e il blocco modifiche per prenotazioni future, ma non è ancora presente un motore avanzato di disponibilità per singolo intervallo né il pagamento online.


---

## 🏬 Partner

- Registrazione come attività (flusso dedicato)
- Verifica OTP e creazione richiesta partner (`partner_requests`)
- Stato richiesta: `pending` → `approved` → `rejected`
- Dashboard partner (`PartnerShell`) con bottom navigation:

  - Dashboard (stato attività)
  - Prenotazioni
  - Scanner (placeholder)
  - Spazi (placeholder)
  - Profilo partner

- **Onboarding partner a step (wizard)**

  - `PartnerSignUpScreen` (utente non loggato) e `PartnerRegistrationScreen` (utente già loggato) sono ora strutturati a step:
    - **Account** (solo signup)
    - **Dati attività + indirizzo**
    - **Capacità bagagli**
  - Nello step “Capacità bagagli”:
    - il partner dichiara lo **spazio generale** in termini di **bagagli M** (es. “posso tenere 10 M”)
    - il sistema calcola automaticamente lo spazio equivalente:
      - `1 M = 2 S = 0.5 L`
      - da cui si ricava:
        - `S_base = M * 2`
        - `M_base = M`
        - `L_base = floor(M * 0.5)`
    - per ogni taglia S/M/L il partner può:
      - **abilitare/disabilitare** la taglia (es. non accettare L)
      - **ridurre** la capacità generale con uno slider fino al massimo calcolato
    - lo step chiede anche se esiste **spazio extra dedicato per singola taglia**:
      - es. “armadietti solo per S”, “zona solo per L”
      - questo extra:
        - si somma solo alla taglia corrispondente
        - **non riduce** la capacità delle altre taglie
  - I valori finali usati per il salvataggio sono:
    - `capacity_s = capacity_generale_s + extra_s`
    - `capacity_m = capacity_generale_m + extra_m`
    - `capacity_l = capacity_generale_l + extra_l`
    - `capacity = capacity_s + capacity_m + capacity_l` (ridondante, per riassunto/filtri)

- Dashboard partner (`PartnerShell`) con bottom navigation:

  - Dashboard (stato attività)
  - Prenotazioni
  - Scanner (placeholder)
  - Spazi (placeholder)
  - Profilo partner

- **Scheda del locale modificabile** (`PartnerEditScreen`):

  - nome attività
  - indirizzo (in sola lettura, modificabile solo tramite supporto)
  - descrizione
  - telefono (con validazione base lato client)
  - regole deposito
  - **orari di apertura settimanali (formato `weekly_v1`)**:
    - editor grafico per ogni giorno (Lun–Dom)
    - fino a **due fasce orarie per giorno** (mattina / pomeriggio)
    - per ogni giorno si possono:
      - impostare “apre alle… / chiude alle…”
      - rimuovere la fascia (giorno chiuso)
    - **azioni rapide**:
      - copia gli orari del **Lunedì su Lun–Ven**
      - copia gli orari del **Lunedì su tutti i giorni**
      - imposta **tutti i giorni chiusi**
    - supporto a **eccezioni calendario**:
      - chiusure straordinarie (`closed_dates`)
      - aperture straordinarie (`forced_open_dates`)
    - i dati vengono salvati in `opening_hours` come:

      ```json
      {
        "type": "weekly_v1",
        "mon": [ { "open": "08:00", "close": "12:00" }, { "open": "15:00", "close": "20:00" } ],
        "tue": [],
        "wed": [],
        "thu": [],
        "fri": [],
        "sat": [],
        "sun": [],
        "exceptions": {
          "closed_dates": ["2025-12-25"],
          "forced_open_dates": ["2025-12-24"]
        }
      }
      ```

  - **capacità bagagli per taglia**:
    - `capacity_s`, `capacity_m`, `capacity_l`
    - `capacity` totale = somma S+M+L

  - **prezzi (vista, non configurazione)**:
    - il partner NON imposta più tariffe proprie
    - le tariffe effettive sono definite in una **configurazione globale BagDropPricing**
      e sono uguali per tutti i locali
    - nella scheda partner l’utente vede prezzi derivati da questa configurazione globale
      (es. “a partire da X € / giorno”), in sola lettura

  - stato `is_active` (attivo/sospeso su mappa)



- **Prenotazioni ricevute** (`PrenotazioniPage`):

  - lista delle righe in `partner_bookings` per quel partner
  - mostra:
    - nome e cognome del contatto
    - telefono, email
    - data di creazione
    - **data/ora di consegna e ritiro**
    - totale bagagli + dettaglio S/M/L
    - note
    - stato (confirmed / pending / cancelled)

- **Blocco modifiche orari/capacità con prenotazioni future**:

- **Blocco modifiche orari/capacità con prenotazioni future**:

  - `PartnerEditScreen` usa `PartnerBookingRepo.hasActiveFutureBookingsForPartner(partner.id)`
  - la funzione considera le prenotazioni con **fine prenotazione nel futuro**
    (in base a `end_date` / `end_time`)
  - se esistono prenotazioni future attive:
    - la sezione orari + capacità viene resa non interattiva (opacità + IgnorePointer)
    - viene mostrato un messaggio informativo
    - si possono comunque modificare descrizione, regole, telefono, stato attivo, ecc.

---

## 🔐 Admin

- Login dedicato
- Dashboard amministratore (`AdminShell`) con:
  - lista richieste partner (`partner_requests`)
  - accettazione / rifiuto richieste con motivazione
- Base per estensioni future:
  - gestione lista partner
  - lista utenti
  - log di sistema

---

# ⚙️ Architettura Backend (Supabase)

## 👥 Autenticazione

- Signup email + password
- Verifica OTP (utente normale e partner)
- `otp_verified` nei metadata dell’utente:
  - finché `otp_verified != true` l’utente:
    - non entra nell’area autenticata
    - non viene creato il record in `user_profiles`
- Trigger / processi di cleanup (cron lato Supabase):
  - eliminano utenti non verificati da più di X minuti (configurabile)

### Funzione `delete_my_account()`

- Funzione SQL `public.delete_my_account()` (PL/pgSQL, `security definer`) eseguita tramite `client.rpc('delete_my_account')`
- Comportamento:
  - legge l’`auth.uid()` dell’utente corrente
  - controlla se esistono **prenotazioni attive**:

    ```sql
    select exists (
      select 1
      from public.partner_bookings
      where user_id = v_user_id
        and status in ('pending', 'confirmed')
    ) into v_has_active;
    ```

  - se ci sono prenotazioni attive → `RAISE EXCEPTION` con messaggio:
    - l’account **non può essere eliminato**
  - se non ci sono prenotazioni attive:
    - elimina eventuali prenotazioni dell’utente (storico, opzionale)
    - elimina il profilo da `user_profiles`
    - elimina l’utente da `auth.users`
- Lato client, l’errore viene mostrato nella `DeleteAccountScreen` come messaggio leggibile.

## 🗄 Tabelle principali

- `auth.users` → autenticazione Supabase (email/password + metadata)
- `user_profiles` → profilo applicativo dell’utente:
  - `id` (PK, = `auth.users.id`)
  - `full_name`
  - `avatar_url`
  - `kyc_status` (`none` | `basic` | `verified`)
  - `role` (`user` | `partner` | `admin`)
- `partner_requests` → richieste partner:
  - `user_id`
  - `status` (`pending` | `approved` | `rejected`)
  - `reject_reason`
- `partners` → attività partner:- `partners` → attività partner:
  - id, owner_id
  - nome, indirizzo, lat/lng
  - `capacity_s`, `capacity_m`, `capacity_l`, `capacity` totale
  - regole, description, phone
  - eventuali campi di supporto per mostrare i **prezzi globali** (testi di vetrina),
    ma le tariffe reali sono definite esternamente in `BagDropPricing`
  - `opening_hours` (JSON `weekly_v1` + `exceptions`)
  - `is_active`, `status` (approved/pending/rejected)
- `partner_photos` → foto locali partner
- `partner_bookings` → prenotazioni bagagli:

  ```sql
  create table if not exists public.partner_bookings (
    id uuid primary key default gen_random_uuid(),
    partner_id uuid not null references public.partners(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,

    status text not null default 'confirmed' check (
      status in ('pending', 'confirmed', 'cancelled', 'completed')
    ),

    contact_first_name text not null,
    contact_last_name  text not null,
    contact_phone      text not null,
    contact_email      text not null,

    bags_s integer not null default 0,
    bags_m integer not null default 0,
    bags_l integer not null default 0,

    notes text,

    -- nuova gestione fasce orarie / giorni
    booking_date date,   -- giorno di consegna
    start_time   time,   -- orario di consegna
    end_date     date,   -- giorno di ritiro
    end_time     time,   -- orario di ritiro

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  );

> ⚠️ La struttura reale in Supabase può includere campi aggiuntivi legati al pricing
> (es. importo totale, valuta, eventuale snapshot della configurazione applicata al momento
> della prenotazione). Il concetto chiave è:
>
> - il **calcolo** del prezzo avviene a partire dalla configurazione globale `BagDropPricing`
> - il partner non definisce tariffe personalizzate
> - il totale visualizzato lato utente e lato partner è coerente con quella configurazione
>   e, se necessario, viene salvato nella riga di `partner_bookings` come “prezzo a quella data”.


````

> ⚠️ Al momento gli orari/slot sono solo **previsti** (commento in migration). Il sistema gestisce prenotazioni “semplici” senza logica di overlap per fascia oraria.

## 🖼 Storage

* Bucket: `partner-photos`
* Policy: gli utenti autenticati possono caricare e leggere le foto dei partner (con RLS sul `partner_id` dove necessario).

---

# 📁 Struttura delle Cartelle (Flutter)

```text
lib/
│
├── main.dart
│
├── routes/
│     └── auth_gate.dart
│
├── theme/
│     └── app_theme.dart
│
├── schermate/
│     ├── splash/
│     │      └── ingresso.dart
│     │
│     ├── user/
│     │      ├── home_shell.dart
│     │      └── bookings/
│     │             ├── user_bookings_page.dart
│     │             ├── booking_partner_detail_screen.dart
│     │             └── booking_recap_screen.dart
│     │
│     ├── autenticazione/
│     │      ├── accesso.dart
│     │      ├── registrazione.dart
│     │      ├── reset_password.dart
│     │      ├── verify_otp.dart
│     │      ├── auth_actions.dart
│     │      └── delete_account_screen.dart
│     │
│     ├── partner/
│     │     ├── auth_partner/
│     │     │      ├── partner_signup_screen.dart
│     │     │      ├── partner_registration_screen.dart
│     │     │      ├── partner_application_screen.dart
│     │     │      └── partner_waiting_screen.dart
│     │     │
│     │     ├── user_view/
│     │     │      ├── partner_detail_screen.dart
│     │     │      └── booking_flow_screen.dart
│     │     │
│     │     ├── dashboard/
│     │     │     ├── partner_shell.dart
│     │     │     ├── pages/
│     │     │     │     ├── dashboard_page.dart
│     │     │     │     ├── prenotazioni_page.dart
│     │     │     │     ├── scanner_page.dart
│     │     │     │     ├── spaces_page.dart
│     │     │     │     └── profile_page.dart
│     │     │     │
│     │     │     └── widgets/
│     │     │            └── partner_status_icon.dart
│     │     │
│     │     └── dashboard/edit/
│     │            ├── partner_edit_screen.dart
│     │            └── partner_photos_screen.dart
│     │
│     └── admin/
│            └── admin_shell.dart
│
├── models/
│     ├── partner.dart
│     ├── partner_booking.dart
│     └── user_profile.dart
│
└── services/
      └── supabase/
            ├── client.dart
            ├── partner_repo.dart
            ├── partner_booking_repo.dart
            ├── user_repo.dart
            └── partner_photo/
                   └── partner_photo_repo.dart
```

---

# 📂 Dettaglio file principali

## 👤 schermate/user/home_shell.dart

* Shell principale per utenti:

  * mappa (`UserMapPage`)
  * tab “Prenotazioni”
  * tab “Profilo”
* Gestisce:

  * Drawer con login/registrazione/supporto
  * gating per tab che richiedono autenticazione
  * check OTP verificato (`otp_verified`) all’accesso
* Tab “Profilo”:

  * legge metadata `first_name`, `last_name`, `phone`
  * form per modificarli (salvati in `auth.updateUser(UserAttributes(data: ...))`)
  * mostra email
  * bottone **“Elimina account”** che apre `DeleteAccountScreen` e alla riuscita torna alla root.

## 🔐 schermate/autenticazione/delete_account_screen.dart

* Schermata di conferma eliminazione:

  * spiega cosa succede alla cancellazione (dati, prenotazioni, accesso)
  * bottone **“Genera codice di conferma”**
  * mostra il codice generato (selezionabile)
  * campo per riscrivere il codice (abilitato solo dopo la generazione)
  * bottone rosso **“Conferma eliminazione”**:

    * valida il codice
    * chiama `supabase.rpc('delete_my_account')`
    * se la funzione SQL solleva errore (es. prenotazioni attive) → mostra messaggio
    * se va a buon fine → `auth.signOut()` + snackbar + pop verso root

## 🧳 schermate/user/bookings/

 * carica le prenotazioni utente via `PartnerBookingRepo.getMyBookings()`
  * mostra card con:
    * stato (chip colorato)
    * data di creazione
    * **data/ora di consegna e ritiro**
    * nome partner (caricato da `PartnerRepo.getPartnerById`)
    * numero totale bagagli

* `booking_partner_detail_screen.dart`:

  * simile a `partner_detail_screen.dart` ma contestualizzata alla prenotazione
  * mostra:
    * foto, descrizione, prezzi di riferimento del partner
    * **orari di apertura (weekly_v1 + eccezioni)**
    * regole, contatti, mappa
    * **riassunto della prenotazione corrente**:
      * data/ora di consegna
      * data/ora di ritiro
      * numero bagagli per taglia
      * eventuale prezzo totale calcolato (dal modello di pricing globale)
  * bottoni in basso:
    * “Riepilogo” (apre `BookingRecapScreen`)
    * “QR code” (placeholder)

* `booking_recap_screen.dart`:

  * riepilogo statico della prenotazione:
    * dati partner
    * contatto (nome, email, telefono)
    * bagagli totali e per taglia
    * **data/ora di consegna e ritiro**
    * eventuale **prezzo totale** (calcolato lato client in base a durata e numero di bagagli)
    * note

## 🏬 schermate/partner/user_view/

* `partner_detail_screen.dart`:

  * scheda partner vista dall’utente (da mappa o lista)
  * mostra:

    * foto
    * descrizione
    * prezzi (2h / giorno)
    * **orari di apertura**:

      * se `opening_hours.type == 'weekly_v1'`:

        * renderizzazione per giorno (Lun–Dom) in ordine
        * supporto a più intervalli (es. 08–12, 15–20)
        * “Chiuso” quando non ci sono intervalli
      * se sono presenti `exceptions`:

        * elenco di chiusure straordinarie (date) o mostra “No”
        * elenco di aperture straordinarie o mostra “No”
    * regole deposito
    * contatti (telefono, indirizzo)
    * mappa (Google Maps lite)
  * bottone fisso in basso **“Prenota ora”** → `BookingFlowScreen`.

* `booking_flow_screen.dart`:

  * stepper (UI) per prenotazione:

    1. Dati di contatto
    2. Data e orario
    3. Bagagli (S/M/L)
    4. Riepilogo finale

  * **Step data e orario**:
    * due modalità:
      * **3 ore**: l’utente sceglie giorno + orario di consegna, il ritiro viene impostato automaticamente a +3h (stesso giorno, compatibilmente con gli orari del locale)
      * **durata personalizzata**: l’utente sceglie giorno/ora di consegna e giorno/ora di ritiro (anche su più giorni, es. “giorno e mezzo”)
    * il riepilogo mostra sempre:
      * “Consegna: data · ora”
      * “Ritiro: data · ora”

  * valida:
    * nome/cognome
    * email (contiene `@`)
    * telefono (solo cifre, lunghezza minima)
    * almeno un bagaglio
    * coerenza tra data/ora di consegna e ritiro (ritiro > consegna)

  * **Pricing (base)**:
    * usa una **configurazione globale BagDropPricing**, definita lato BagDrop e uguale per tutti i partner
    * la configurazione contiene tariffe per:
      * taglia **S/M/L**
      * durata (3h, 1 giorno, 1.5 giorni, 2 giorni, 3 giorni, …)
    * il totale è calcolato lato client in base a:
      * durata selezionata
      * numero di bagagli per taglia
    * il riepilogo mostra:
      * dettaglio per taglia (es. “2× S • 1× M”)
      * durata
      * **prezzo totale** applicato dalle tariffe globali BagDrop (non modificabile dal partner)


  * alla conferma crea record in `partner_bookings` via `PartnerBookingRepo.createBooking(...)` compilando:
    * `booking_date`, `start_time` (consegna)
    * `end_date`, `end_time` (ritiro)
    * dati di contatto
    * S/M/L
    * note

## ✏️ schermate/partner/dashboard/edit/partner_edit_screen.dart

* Carica il locale associato all’utente (`getMyPartner`)
* Popola:

  * nome, indirizzo (read-only), descrizione
  * telefono, regole
  * capacità S/M/L
  * prezzi
  * `opening_hours` convertito/normalizzato in `weekly_v1`
  * eccezioni calendario (se presenti)
  * `is_active`
* Editor orari (`OpeningHoursEditor`):

  * per ogni giorno:

    * fascia mattina: apertura/chiusura
    * fascia pomeriggio: apertura/chiusura (opzionale)
  * azioni rapide (toolbar):

    * “Lun → Lun–Ven”
    * “Lun → tutti i giorni”
    * “Tutti chiusi”
* Editor eccezioni (`OpeningExceptionsEditor`):

  * chiusure straordinarie
  * aperture straordinarie
* Se ci sono prenotazioni future (`hasActiveFutureBookingsForPartner`):

  * sezione orari + capacità disabilitata (ignorata nel salvataggio)
  * messaggio di warning in rosso
* `_save()`:

  * valida capacità (≥ 0, somma > 0)

  * normalizza prezzi (virgola/punto)

  * costruisce `opening_hours` con:

    ```dart
    {
      'type': 'weekly_v1',
      ..._openingHoursStructured,
      if (_openingExceptions != null) 'exceptions': _openingExceptions,
    }
    ```

  * chiama `PartnerRepo.updateBasics(...)`.

---

## 📦 Modelli & Repository

### `models/user_profile.dart` + `services/supabase/user_repo.dart`

* `UserProfile`:

  * mappa la tabella `user_profiles`
  * campi:

    * `id`
    * `created_at`
    * `full_name`
    * `avatar_url`
    * `kyc_status`
    * `role`
* `UserRepo`:

  * `getMe()` → legge `user_profiles` per l’utente loggato
  * `upsertMe(...)` → aggiorna/crea profilo per l’utente corrente (with upsert)

### `models/partner_booking.dart`

* Modello per `partner_bookings`:

  * `id`, `partnerId`, `userId`
  * `status`
  * `firstName`, `lastName`, `phone`, `email`
  * `bagsS`, `bagsM`, `bagsL`
  * `notes`
  * `createdAt`, `updatedAt`

### `services/supabase/partner_booking_repo.dart`

* Gestisce le operazioni sulle prenotazioni:

  * `createBooking({...})`:

    * richiede utente loggato
    * inserisce in `partner_bookings` con contatto + S/M/L + note
    * status di default `confirmed`

  * `getMyBookings()`:

    * tutte le prenotazioni per l’utente corrente

  * `getBookingsForPartner(String partnerId)`:

    * tutte le prenotazioni di una determinata attività

  * `hasActiveFutureBookingsForPartner(String partnerId)`:

    * controlla se ci sono prenotazioni **non cancellate** con `created_at >= oggi`
    * usato per bloccare modifiche orari/capacità in `partner_edit_screen.dart`

> In futuro potrà essere esteso a lavorare con `booking_date` / `start_time` / `end_time` appena aggiunti a schema.

---

# 🔄 Flussi Principali

## 🔐 Signup + OTP

1. L’utente inserisce email + password.
2. Viene mandato un OTP alla mail.
3. L’utente inserisce l’OTP nella `verify_otp.dart`:

   * se valido → viene impostato `otp_verified = true` nel metadata
   * per utenti normali → creato record in `user_profiles`
   * per partner → process collegato alla creazione/aggiornamento di `partners` e `partner_requests`
4. Finché non è verificato → niente accesso ad area autenticata.

## 🏬 Onboarding Partner

1. Il partner compila il wizard:

   * `PartnerSignUpScreen` → se NON è loggato (include step Account)
   * `PartnerRegistrationScreen` → se è già loggato come utente normale

2. Nel wizard vengono raccolti:

   * **Dati account** (solo signup)
   * **Dati attività + indirizzo** (con geocoding/coordinate)
   * **Capacità bagagli** tramite nuovo flusso:

     - il partner indica quanti **bagagli M** può tenere nello **spazio generale**
     - il sistema calcola lo spazio equivalente in S e L (`1 M = 2 S = 0.5 L`)
     - per ogni taglia S/M/L il partner può:
       - decidere se accettarla o disabilitarla
       - abbassare la capacità generale tramite slider (rispetto al massimo teorico)
     - opzionalmente può dichiarare **spazio extra dedicato a S/M/L** che:
       - viene aggiunto solo alla singola taglia
       - non consuma capacità delle altre taglie

   * Alla fine del wizard vengono calcolati i valori “effettivi”:

     - `capacity_s = generale_s + extra_s`
     - `capacity_m = generale_m + extra_m`
     - `capacity_l = generale_l + extra_l`
     - `capacity = somma S+M+L` (campo ridondante)

3. Viene creata/aggiornata una riga in `partners` con:

   * capacità S/M/L finali + totale
   * prezzi
   * coordinate, ecc.

4. Viene (ri)creata una riga in `partner_requests` con `status = 'pending'`.

5. Finché non è approvato:

   * l’utente partner vede `PartnerWaitingScreen` (in caso di `rejected` mostra anche motivo e può reinviare domanda aggiornando i dati).

6. Se admin approva:

   * il partner accede alla `PartnerShell` (dashboard) e può modificare scheda, orari, ecc.


## 📦 Prenotazioni (stato attuale)

1. L’utente apre la **scheda partner** (`PartnerDetailScreen`) dalla mappa.
2. Clicca **“Prenota ora”** → `BookingFlowScreen`.
3. Step 1 – Contatto:
   * inserisce nome, cognome, email, telefono, note.
4. Step 2 – Data e orario:
   * sceglie:
     * modalità **3 ore** (con ritiro auto-calcolato sullo stesso giorno)
     * oppure **durata personalizzata** (giorno/ora di consegna e giorno/ora di ritiro, anche su più giorni).
5. Step 3 – Bagagli:
   * seleziona numero di bagagli S/M/L (almeno 1 in totale).
6. Step 4 – Riepilogo:
   * vede un riepilogo completo con:
     * partner
     * contatto
     * bagagli
     * **data/ora di consegna e ritiro**
     * durata
     * **prezzo totale stimato** in base alla configurazione globale di pricing.
7. Conferma:
   * viene creato il record in `partner_bookings` con:
     * `booking_date`, `start_time`
     * `end_date`, `end_time`
     * contatto + S/M/L + note.
8. Lato utente:
   * in “Le mie prenotazioni” vede tutte le prenotazioni create, con data/ora e stato.
9. Lato partner:
   * in “Prenotazioni” vede tutte le prenotazioni ricevute con data/ora di consegna/ritiro.

> La logica di disponibilità per fascia oraria è per ora **di base**: le date/ore sono memorizzate e usate per bloccare modifiche future, ma l’algoritmo di overlap e slot avanzati verrà introdotto in una fase successiva.

---

# 🧠 Funzionalità completate

* ✔ Signup + Login
* ✔ Verifica OTP manuale
* ✔ Cleanup utenti non verificati
* ✔ Flusso partner (signup → richiesta → waiting → approvazione)
* ✔ PartnerShell con bottom navigation
* ✔ Modifica scheda locale partner
* ✔ Storage foto partner
* ✔ Mappa utente con partner reali
* ✔ AdminShell base
* ✔ Flusso prenotazione con slot base:

  * `BookingFlowScreen` lato utente:
    * Step: Contatto → Data e orario → Bagagli S/M/L → Riepilogo
    * selezione giorno/ora di consegna e ritiro (3h o durata personalizzata)
    * calcolo prezzo stimato tramite configurazione globale `BagDropPricing`
  * creazione record in `partner_bookings` con:
    * dati contatto
    * S/M/L
    * note
    * `booking_date`, `start_time`, `end_date`, `end_time`
  * `PrenotazioniPage` lato partner (lista prenotazioni con date/ore)
  * Tab “Le mie prenotazioni” lato utente
  * `BookingPartnerDetailScreen` + `BookingRecapScreen` con riepilogo completo (inclusa data/ora e prezzo)

* ✔ Nuovi orari partner:

  * editor settimanale `weekly_v1` con eccezioni (chiusure/aperture straordinarie)
  * render lato utente per orari + eccezioni

* ✔ Profilo utente:

  * visualizzazione/modifica nome, cognome, telefono
  * flusso **eliminazione account** con codice di conferma e blocco se ci sono prenotazioni attive

* ✔ **Wizard capacità partner (nuovo modello M → S/L + extra)**

  * `PartnerSignUpScreen` e `PartnerRegistrationScreen` usano uno **step dedicato “Capacità”**:
    * il partner dichiara lo spazio generale in numero di bagagli M
    * il sistema calcola lo spazio equivalente in S e L con rapporto `1 M = 2 S = 0.5 L`
    * il partner può:
      * attivare/disattivare singole taglie S/M/L
      * ridurre la capacità generale per taglia con slider (fino al massimo teorico)
      * dichiarare spazio **extra dedicato** per S/M/L (armadietti, area speciale, ecc.)
  * il wizard produce e salva in `partners` i campi:
    * `capacity_s`, `capacity_m`, `capacity_l`
    * `capacity` (totale)
  * **Stato attuale**: i valori vengono usati come limiti statici di capacità; il **motore di disponibilità dinamica per fascia oraria** non è ancora implementato e verrà introdotto nella fase successiva.

---

# 🟦 Prossime Funzionalità

## 1️⃣ Sistema Prenotazioni (evoluzione)

* Evoluzione del motore di slot orari a partire da `opening_hours`:
  * generazione automatica degli slot prenotabili in base alle fasce di apertura (mattina/pomeriggio)
  * vincoli più rigidi su prenotazioni che sconfinano vicino alla chiusura

* Calcolo disponibilità **per intervallo** usando anche la nuova capacità S/M/L:

  * uso dei campi `capacity_s`, `capacity_m`, `capacity_l`, `capacity` come **limiti dinamici**
  * gestione overlap avanzata tra prenotazioni sullo stesso giorno e fascia oraria
  * logica di conversione coerente con il modello d’onboarding:
    * `1 M = 2 S = 0.5 L`
    * consumo capacità quando arrivano prenotazioni miste (es. 1 L = 2 slot M, ecc.)
  * distinzione tra:
    * **spazio generale condiviso** (derivato dai M di base)
    * **spazio extra dedicato per taglia** (es. solo S) che non entra nel “pool” condiviso

* UI migliorata per mostrare in modo chiaro:

  * data + fascia oraria in:
    * riepilogo
    * lista “Le mie prenotazioni”
    * lista prenotazioni partner
  * eventuale indicatore di **capacità residua** per partner / giorno / fascia

* Possibile estensione del modello di pricing:

  * tariffe differenziate per alta/bassa stagione
  * eventuali sovrapprezzi per notte o orari “speciali”.


## 2️⃣ QR Code

* Generazione QR dalla prenotazione (`partner_bookings.id`).
* Scanner lato partner.
* Stati aggiuntivi (es. `checked_in`, `checked_out`).

## 3️⃣ Pagamenti

* Integrazione provider (Stripe o simili):

  * prenotazione in stato `pending`
  * conferma post pagamento → `confirmed`

## 4️⃣ Dashboard Partner avanzata

* Statistiche giornaliere/mensili.
* Calendario prenotazioni.
* Capacità real-time.

## 5️⃣ Admin avanzato

* Gestione elenco partner, utenti, log.
* Filtri e ricerca.

---

# 🔧 Setup Sviluppo

## Configurare Supabase

In `.env.android`:

```env
SUPABASE_URL=YOUR_URL
SUPABASE_ANON_KEY=YOUR_KEY
```

In `pubspec.yaml`:

```yaml
assets:
  - .env.android
```

Eseguire:

```bash
flutter run --dart-define=SUPABASE_URL=xxx --dart-define=SUPABASE_ANON_KEY=xxx
```

---

# 🤝 Contatti

Sviluppo curato da BagDrop Team.

📧 [support@bagdrop.app](mailto:support@bagdrop.app)
🌐 [https://bagdrop.app](https://bagdrop.app)

---

# ❤️ Licenza

Progetto privato – Tutti i diritti riservati BagDrop.
