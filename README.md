# 🧳 BagDrop – Flutter App

BagDrop è una piattaforma mobile che permette agli utenti di trovare attività partner (bar, negozi, hotel, negozi di prossimità) dove lasciare i propri bagagli in modo sicuro.
L’app è sviluppata in **Flutter** e utilizza **Supabase** come backend per autenticazione, database e storage.

---

# 🚀 Funzionalità Principali

## 👤 Utente

* Registrazione tramite email + password

* Verifica email via codice OTP

* Login / Logout

* Mappa interattiva con marker dei partner approvati e attivi

* Scheda dettagliata partner:

  * foto
  * descrizione
  * regole
  * prezzi
  * **orari di apertura per giorno della settimana (Lun–Dom)**
  * eventuali **chiusure straordinarie / aperture straordinarie**
  * posizione su mappa

* **Flusso di prenotazione deposito bagagli presso un partner**, con:

  * step guidati (**Contatto → Data e orario → Bagagli → Riepilogo**)
  * scelta della **modalità di durata**:

    * 3 ore veloci
    * durata personalizzata (fino a più giorni, incluso il caso “giorno e mezzo”)
  * selezione:

    * data/ora di **consegna** dei bagagli
    * data/ora di **ritiro** dei bagagli
  * inserimento:

    * nome, cognome, telefono, email, note
    * bagagli per taglia **S / M / L**
  * salvataggio in `partner_bookings` con:

    * riferimento all’utente (`user_id`)
    * riferimento al partner (`partner_id`)
    * dati di contatto “fotografati” (anche se l’utente cambia profilo in futuro)
    * numero di bagagli S/M/L
    * **data/ora di consegna** (`booking_date`, `start_time`)
    * **data/ora di ritiro** (`end_date`, `end_time`)
    * timestamp di creazione (`created_at`)
  * **controllo di disponibilità dinamico per intervallo**:

    * uso delle capacità del partner (`capacity_s/m/l` + `capacity` totale)
    * logica di equivalenza **1 S = 1 • 1 M = 2 • 1 L = 4** unità
    * verifica sia per **taglia** (S/M/L) sia per **spazio totale equivalente**

* **Step “Bagagli” con barra dinamica di capacità**:

  * caricamento disponibilità tramite `PartnerBookingRepo.getPartnerAvailabilityForInterval(...)`
  * visualizzazione:

    * disponibili per taglia: **S / M / L**
    * **barra di progresso** che mostra quanto spazio totale viene occupato:

      * spazio totale in unità equivalenti (mezze M)
      * spazio già occupato da altre prenotazioni + selezione corrente
      * messaggio in rosso se la selezione supera la capacità
  * il numero di bagagli S/M/L è limitato in tempo reale:

    * per taglia (non puoi superare `availableS/M/L`)
    * per spazio totale (non puoi superare `availableTotal`)

* **Schermata “Le mie prenotazioni”**:

  * tab dedicata nella home utente
  * lista delle prenotazioni con:

    * stato (confirmed/pending/cancelled)
    * data di creazione
    * **data/ora di consegna e ritiro**
    * **nome attività (partner)** caricato da `PartnerRepo.getPartnerById(...)`
    * totale bagagli
  * tap su una prenotazione → apre:

    * **scheda attività collegata** (`BookingPartnerDetailScreen`)
    * da cui si può vedere il riepilogo della prenotazione (`BookingRecapScreen`)

* **Profilo utente & gestione account**:

  * tab “Profilo” nella `HomeShell`
  * mostra:

    * email dell’account
    * nome, cognome e telefono letti dai metadata Supabase (`user.userMetadata`)
  * form per **modificare nome, cognome e telefono** con validazione base sul numero (solo cifre 9–15 caratteri)
  * pulsante rosso **“Elimina account”**:

    * apre una schermata dedicata (`DeleteAccountScreen`)
    * l’utente genera un **codice alfanumerico casuale**, che deve poi riscrivere per abilitare il tasto di conferma
    * viene chiamata la funzione SQL `public.delete_my_account()` su Supabase
    * l’eliminazione viene eseguita **solo se non esistono prenotazioni attive** collegate a quell’utente
    * dopo la cancellazione viene eseguito `auth.signOut()` lato client

> N.B.: esiste un **motore di disponibilità per intervallo “base”**:
>
> * controlla sovrapposizioni tra intervallo richiesto e prenotazioni `pending/confirmed`
> * usa capacità S/M/L + **capacità totale equivalente**
>   Non è ancora presente un sistema di scheduling avanzato (slot generati automaticamente, regole complesse per “alto carico”, ecc.) né il pagamento online.

---

## 🏬 Partner

* Registrazione come attività (flusso dedicato)

* Verifica OTP e creazione richiesta partner (`partner_requests`)

* Stato richiesta: `pending` → `approved` → `rejected`

* Dashboard partner (`PartnerShell`) con bottom navigation:

  * Dashboard (stato attività)
  * Prenotazioni
  * Scanner (placeholder)
  * Spazi (placeholder)
  * Profilo partner

* **Onboarding partner a step (wizard)**

  * `PartnerSignUpScreen` (utente non loggato) e `PartnerRegistrationScreen` (utente già loggato) sono ora strutturati a step:

    * **Account** (solo signup)
    * **Dati attività + indirizzo**
    * **Capacità bagagli**
  * Nello step “Capacità bagagli”:

    * il partner dichiara lo **spazio generale** in termini di **bagagli M** (es. “posso tenere 10 M”)
    * il sistema calcola automaticamente lo spazio equivalente:

      * `1 M = 2 S = 0.5 L`
      * da cui si ricava:

        * `S_base = M * 2`
        * `M_base = M`
        * `L_base = floor(M * 0.5)`
    * per ogni taglia S/M/L il partner può:

      * **abilitare/disabilitare** la taglia (es. non accettare L)
      * **ridurre** la capacità generale con uno slider fino al massimo calcolato
    * lo step chiede anche se esiste **spazio extra dedicato per singola taglia**:

      * es. “armadietti solo per S”, “zona solo per L”
      * questo extra:

        * si somma solo alla taglia corrispondente
        * **non riduce** la capacità delle altre taglie
  * I valori finali usati per il salvataggio sono:

    * `capacity_s = capacity_generale_s + extra_s`
    * `capacity_m = capacity_generale_m + extra_m`
    * `capacity_l = capacity_generale_l + extra_l`
    * `capacity = capacity_s + capacity_m + capacity_l` (ridondante, per riassunto/filtri)

* **Scheda del locale modificabile** (`PartnerEditScreen`):

  * nome attività

  * indirizzo (in sola lettura, modificabile solo tramite supporto)

  * descrizione

  * telefono (con validazione base lato client)

  * regole deposito

  * **orari di apertura settimanali (formato `weekly_v1`)**:

    * editor grafico per ogni giorno (Lun–Dom)
    * fino a **due fasce orarie per giorno** (mattina / pomeriggio)
    * per ogni giorno si possono:

      * impostare “apre alle… / chiude alle…”
      * rimuovere la fascia (giorno chiuso)
    * **azioni rapide**:

      * copia gli orari del **Lunedì su Lun–Ven**
      * copia gli orari del **Lunedì su tutti i giorni**
      * imposta **tutti i giorni chiusi**
    * supporto a **eccezioni calendario**:

      * chiusure straordinarie (`closed_dates`)
      * aperture straordinarie (`forced_open_dates`)
    * i dati vengono salvati in `opening_hours` come:

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

  * **capacità bagagli per taglia**:

    * `capacity_s`, `capacity_m`, `capacity_l`
    * `capacity` totale = somma S+M+L
    * usate dal motore di disponibilità per intervallo

  * **prezzi (vista, non configurazione)**:

    * il partner NON imposta più tariffe proprie
    * le tariffe effettive sono definite in una **configurazione globale BagDropPricing**
      e sono uguali per tutti i locali
    * nella scheda partner l’utente vede prezzi derivati da questa configurazione globale
      (es. “a partire da X € / giorno”), in sola lettura

  * stato `is_active` (attivo/sospeso su mappa)

* **Prenotazioni ricevute** (`PrenotazioniPage`):

  * lista delle righe in `partner_bookings` per quel partner
  * mostra:

    * nome e cognome del contatto
    * telefono, email
    * data di creazione
    * **data/ora di consegna e ritiro**
    * totale bagagli + dettaglio S/M/L
    * note
    * stato (confirmed / pending / cancelled)

* **Blocco modifiche orari/capacità con prenotazioni future**:

  * `PartnerEditScreen` usa `PartnerBookingRepo.hasActiveFutureBookingsForPartner(partner.id)`
  * la funzione considera le prenotazioni con **intervallo che arriva a oggi o oltre**:

    * usa `booking_date` / `end_date` (e non solo `created_at`)
    * ignora le prenotazioni `cancelled`
  * se esistono prenotazioni future attive:

    * la sezione orari + capacità viene resa non interattiva (opacità + IgnorePointer)
    * viene mostrato un messaggio informativo
    * si possono comunque modificare descrizione, regole, telefono, stato attivo, ecc.

---

## 🔐 Admin

* Login dedicato
* Dashboard amministratore (`AdminShell`) con:

  * lista richieste partner (`partner_requests`)
  * accettazione / rifiuto richieste con motivazione
* Base per estensioni future:

  * gestione lista partner
  * lista utenti
  * log di sistema

---

# ⚙️ Architettura Backend (Supabase)

## 👥 Autenticazione

* Signup email + password
* Verifica OTP (utente normale e partner)
* `otp_verified` nei metadata dell’utente:

  * finché `otp_verified != true` l’utente:

    * non entra nell’area autenticata
    * non viene creato il record in `user_profiles`
* Trigger / processi di cleanup (cron lato Supabase):

  * eliminano utenti non verificati da più di X minuti (configurabile)

### Funzione `delete_my_account()`

* Funzione SQL `public.delete_my_account()` (PL/pgSQL, `security definer`) eseguita tramite `client.rpc('delete_my_account')`
* Comportamento:

  * legge l’`auth.uid()` dell’utente corrente

  * controlla se esistono **prenotazioni attive**:

    ```sql
    select exists (
      select 1
      from public.partner_bookings
      where user_id = v_user_id
        and status in ('pending', 'confirmed')
    ) into v_has_active;
    ```

  * se ci sono prenotazioni attive → `RAISE EXCEPTION` con messaggio:

    * l’account **non può essere eliminato**

  * se non ci sono prenotazioni attive:

    * elimina eventuali prenotazioni dell’utente (storico, opzionale)
    * elimina il profilo da `user_profiles`
    * elimina l’utente da `auth.users`
* Lato client, l’errore viene mostrato nella `DeleteAccountScreen` come messaggio leggibile.

## 🗄 Tabelle principali

* `auth.users` → autenticazione Supabase (email/password + metadata)
* `user_profiles` → profilo applicativo dell’utente:

  * `id` (PK, = `auth.users.id`)
  * `full_name`
  * `avatar_url`
  * `kyc_status` (`none` | `basic` | `verified`)
  * `role` (`user` | `partner` | `admin`)
* `partner_requests` → richieste partner:

  * `user_id`
  * `status` (`pending` | `approved` | `rejected`)
  * `reject_reason`
* `partners` → attività partner:

  * id, owner_id
  * nome, indirizzo, lat/lng
  * `capacity_s`, `capacity_m`, `capacity_l`, `capacity` totale
  * regole, description, phone
  * eventuali campi di supporto per mostrare i **prezzi globali** (testi di vetrina),
    ma le tariffe reali sono definite esternamente in `BagDropPricing`
  * `opening_hours` (JSON `weekly_v1` + `exceptions`)
  * `is_active`, `status` (approved/pending/rejected)
* `partner_photos` → foto locali partner
* `partner_bookings` → prenotazioni bagagli:

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

    -- gestione fasce orarie / giorni
    booking_date date,   -- giorno di consegna
    start_time   time,   -- orario di consegna
    end_date     date,   -- giorno di ritiro
    end_time     time,   -- orario di ritiro

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  );
  ```

> Il sistema usa questi campi per:
>
> * calcolare la **disponibilità per intervallo** (vedi `PartnerBookingRepo.getPartnerAvailabilityForInterval`)
> * bloccare modifiche orari/capacità quando esistono prenotazioni future
>   Il **calcolo del prezzo** avviene a partire dalla configurazione globale `BagDropPricing`; il partner non definisce tariffe personalizzate.

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
├── config/
│     └── bagdrop_pricing.dart
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

* `user_bookings_page.dart`:

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
    * prezzi (3h / giorno) derivati da `BagDropPricing`
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
    * controlli:

      * niente date nel passato
      * massimo 7 giorni in avanti
      * rispetto degli orari di apertura (`opening_hours` + eccezioni)
      * durata massima 7 giorni

  * **Disponibilità per intervallo**:

    * dopo aver scelto data/ora, viene chiamato:

      * `PartnerBookingRepo.getPartnerAvailabilityForInterval(...)`
    * la funzione:

      * legge `capacity_s/m/l` e `capacity` dal partner
      * calcola la capacità totale in **unità equivalenti** (1S = 1, 1M = 2, 1L = 4)
      * considera le prenotazioni `pending/confirmed` che **si sovrappongono** all’intervallo richiesto
      * somma i bagagli S/M/L di quelle prenotazioni in unità equivalenti

  * **Step bagagli**:

    * l’utente sceglie il numero di bagagli S/M/L
    * in base alla disponibilità caricata:

      * limiti per taglia:

        * `bagsS <= availableS`, `bagsM <= availableM`, `bagsL <= availableL` (se configurati)
      * limite di spazio totale:

        * `(1*S + 2*M + 4*L) <= availableTotal`
    * UI:

      * per ogni taglia una riga con:

        * descrizione
        * display “Disponibili: X”
        * pulsanti `+ / -`
      * **barra dinamica di spazio totale**:

        * mostra `occupato / capacità` in unità equivalenti (convertito a numero umano, es. “3.5 / 8.0 unità”)
        * colora la barra in rosso se la selezione supera la capacità
        * messaggio esplicativo e legenda: `1 S = 1 • 1 M = 2 • 1 L = 4 unità`

  * **Pricing (base)**:

    * usa una **configurazione globale BagDropPricing**, definita lato BagDrop e uguale per tutti i partner
    * la configurazione contiene tariffe per:

      * taglia **S/M/L**
      * durata (3h, 1 giorno, 1.5 giorni, 2 giorni, 3 giorni, …)
    * il totale è calcolato lato client in base a:

      * durata selezionata (derivata da `start/end`)
      * numero di bagagli per taglia
    * nel riepilogo e nello step bagagli viene mostrata:

      * **anteprima del prezzo** (step bagagli)
      * **prezzo totale finale** (riepilogo)

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
  * prezzi (da BagDropPricing)
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
  * `bookingDate`, `startTime`, `endDate`, `endTime`
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

  * `getPartnerAvailability(String partnerId)`:

    * disponibilità “grezza” complessiva del partner (ignorando data/orario)
    * usa:

      * `capacity_s`, `capacity_m`, `capacity_l`, `capacity`
      * totale in **unità equivalenti**: `1 S = 1`, `1 M = 2`, `1 L = 4`
    * considera tutte le prenotazioni **non cancellate** (`status != 'cancelled'`)

  * `getPartnerAvailabilityForInterval({...})`:

    * calcola la disponibilità per **uno specifico intervallo**:

      * `startDate + startTime` → inizio
      * `endDate + endTime` → fine
    * considera:

      * solo prenotazioni per quel partner
      * solo `status in ('pending', 'confirmed')`
      * solo prenotazioni che **si sovrappongono** all’intervallo richiesto
    * restituisce:

      * capacità per taglia S/M/L
      * `capacityTotal` in unità equivalenti
      * `usedS/M/L` e `usedTotal`
      * `availableS/M/L` e `availableTotal`
    * viene usato da `BookingFlowScreen` per:

      * limitare la selezione di S/M/L
      * riempire la **barra dinamica di capacità**

  * `hasActiveFutureBookingsForPartner(String partnerId)`:

    * controlla se ci sono prenotazioni **non cancellate** il cui intervallo arriva a oggi o oltre
    * usa `booking_date` / `end_date` per capire se l’intervallo è futuro/attivo
    * usato per bloccare modifiche orari/capacità in `partner_edit_screen.dart`

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
   * **Capacità bagagli** tramite nuovo flusso basato su M → S/L + extra
3. Vengono calcolati i valori “effettivi”:

   * `capacity_s`, `capacity_m`, `capacity_l`
   * `capacity` (somma)
4. Viene creata/aggiornata una riga in `partners` con capacità finali + dati base.
5. Viene (ri)creata una riga in `partner_requests` con `status = 'pending'`.
6. Finché non è approvato:

   * l’utente partner vede `PartnerWaitingScreen` (e, se `rejected`, il motivo).
7. Se admin approva:

   * il partner accede alla `PartnerShell`.

## 📦 Prenotazioni (stato attuale)

1. L’utente apre la **scheda partner** (`PartnerDetailScreen`) dalla mappa.
2. Clicca **“Prenota ora”** → `BookingFlowScreen`.
3. Step 1 – Contatto:

   * inserisce nome, cognome, email, telefono, note.
4. Step 2 – Data e orario:

   * sceglie:

     * modalità **3 ore**
     * oppure **durata personalizzata** (anche su più giorni).
   * viene validata:

     * assenza di passato
     * massimo 7 giorni dal giorno corrente
     * rispetto orari di apertura
5. **Caricamento disponibilità per intervallo**:

   * in base a data/ora scelte, viene chiamato `getPartnerAvailabilityForInterval`
   * la disponibilità viene usata nello step successivo.
6. Step 3 – Bagagli:

   * selezione numero bagagli S/M/L (minimo 1 in totale)
   * limiti S/M/L e spazio totale gestiti in tempo reale
   * barra dinamica di capacità aggiornata ad ogni modifica
   * anteprima del prezzo per la combinazione corrente
7. Step 4 – Riepilogo:

   * riepilogo completo con:

     * partner
     * contatto
     * bagagli S/M/L
     * **data/ora di consegna e ritiro**
     * durata
     * **prezzo totale stimato** (da `BagDropPricing`)
8. Conferma:

   * viene creato il record in `partner_bookings` con tutti i campi
   * controlli finali di disponibilità di sicurezza lato client
9. Lato utente:

   * in “Le mie prenotazioni” vede tutte le prenotazioni create.
10. Lato partner:

    * in “Prenotazioni” vede tutte le prenotazioni ricevute con date/ore e dettaglio S/M/L.

> Il sistema implementa un **motore di disponibilità per intervallo di livello base**: controlla overlap e capacità, ma non genera ancora slot “a griglia” né ha logiche di overbooking avanzate.

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

* ✔ **Flusso prenotazione con slot base + disponibilità per intervallo**:

  * `BookingFlowScreen` lato utente:

    * Step: Contatto → Data e orario → Bagagli S/M/L → Riepilogo
    * selezione giorno/ora di consegna e ritiro (3h o durata personalizzata)
    * validazione con orari di apertura + limiti 7 giorni
  * **Motore di disponibilità per intervallo**:

    * `PartnerBookingRepo.getPartnerAvailabilityForInterval`
    * uso di `capacity_s/m/l` + `capacity` e unità equivalenti (1S=1, 1M=2, 1L=4)
    * controllo S/M/L + spazio totale
  * **UI capacità**:

    * riga per taglia con massimo disponibili
    * barra dinamica di spazio totale (colore rosso se oltre capacità)
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

* ✔ **Wizard capacità partner (modello M → S/L + extra)**:

  * step dedicato “Capacità”
  * salvataggio capacità S/M/L + totale
  * integrazione con motore di disponibilità per intervallo

---

# 🟦 Prossime Funzionalità

(resto invariato, solo più consapevoli del motore attuale)

## 1️⃣ Sistema Prenotazioni (evoluzione)

* Evoluzione del motore di slot orari oltre la logica attuale:

  * generazione automatica degli slot prenotabili in base alle fasce di apertura
  * vincoli più rigidi su prenotazioni vicine alla chiusura
  * regole per alta occupazione / limiti per fascia

* Possibili estensioni:

  * stagionalità prezzo
  * sovrapprezzi per notte, ecc.

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
