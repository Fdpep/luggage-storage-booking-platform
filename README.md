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
  * **controllo di disponibilità dinamico per intervallo (v2)**:

    * source of truth dal partner: `base_capacity_u` + `extra_capacity_s/m/l` + `accept_s/m/l`
    * logica unità equivalenti: **1 S = 1u • 1 M = 2u • 1 L = 4u**
    * per una richiesta (S/M/L) calcoliamo `need_u = S*1 + M*2 + L*4`
    * la disponibilità viene verificata:
      * per taglia (rispettando `accept_*`)
      * e sullo **spazio generale** (`base_capacity_u`) consumato dalle prenotazioni sovrapposte
    * la creazione prenotazione salva anche l’allocazione (quanto viene preso da base vs extra dedicati)


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
> * usa come source of truth: `base_capacity_u` + `extra_capacity_s/m/l` + `accept_s/m/l`
>   Non è ancora presente un sistema di scheduling avanzato (slot generati automaticamente, regole complesse per “alto carico”, ecc.) né il pagamento online.

---

## 🏬 Partner

* Registrazione come attività (flusso dedicato)

* Verifica OTP e creazione richiesta partner (`partner_requests`)

* Stato richiesta: `pending` → `approved` → `rejected`

* Dashboard partner (`PartnerShell`) con bottom navigation:

  * Dashboard (stato attività)
  * Prenotazioni
  * Scanner (QR / Codici)
  * Spazi (placeholder)
  * Profilo partner

* **Onboarding partner a step (wizard)**

  * `PartnerSignUpScreen` (utente non loggato) e `PartnerRegistrationScreen` (utente già loggato) sono ora strutturati a step:

    * **Account** (solo signup)
    * **Dati attività + indirizzo**
    * **Capacità bagagli**

### ✅ Modello capacità partner (v2 – base condivisa + extra dedicati)

Nel wizard “Capacità bagagli” il partner inserisce **una sola capacità generale** in bagagli **M** (es. “posso tenere 10 M”).

#### Unità equivalenti (u)
Per rendere coerenti le taglie usiamo unità equivalenti:
- `1 S = 1u`
- `1 M = 2u`
- `1 L = 4u`

#### Salvataggio su DB (source of truth)
Non salviamo 3 capacità “da sommare”. Salviamo:

- `base_capacity_u` → capacità generale in unità equivalenti (u)  
  - UI: input `baseM`  
  - DB: `base_capacity_u = baseM * 2`

- `extra_capacity_s`, `extra_capacity_m`, `extra_capacity_l` → extra dedicati per taglia  
  (armadietti, attaccapanni, zone dedicate…)

- `accept_s`, `accept_m`, `accept_l` → taglie accettate (toggle)

> Nota: i campi `capacity_s`, `capacity_m`, `capacity_l` e `capacity` vengono **derivati automaticamente via trigger** per UI/filtri.  
> La logica vera di prenotazione usa sempre `base_capacity_u` + extra.



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

  * **capacità bagagli (v2)**:

    * source of truth:
      * `base_capacity_u` (capacità generale condivisa, in unità equivalenti)
      * `extra_capacity_s`, `extra_capacity_m`, `extra_capacity_l` (extra dedicati)
      * `accept_s`, `accept_m`, `accept_l`
    * campi derivati (per UI/filtri, calcolati via trigger):
      * `capacity_s`, `capacity_m`, `capacity_l`, `capacity`


  * **prezzi (vista, non configurazione)**:

    * il partner NON imposta più tariffe proprie
    * le tariffe effettive sono definite in una **configurazione globale BagDropPricing**
      e sono uguali per tutti i locali
    * nella scheda partner l’utente vede prezzi derivati da questa configurazione globale
      (es. “a partire da X € / giorno”), in sola lettura

  * stato `is_active` (attivo/sospeso su mappa)

  * **toggle “Accetto prenotazioni”** (`accepting_bookings`):
  * separato da `is_active` (che riguarda visibilità/attività su mappa)
  * se `accepting_bookings = false`:
    * il locale può restare visibile (se `is_active = true`)
    * ma **non è prenotabile** dagli utenti


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


  * azioni:

    * **rifiuta prenotazione** (irreversibile) con **motivazione obbligatoria**
    * lo stato passa a `rejected` e viene salvata `reject_reason` + `rejected_at`
  
  * `partners` → attività partner:
  ...
  * `is_active` (attivo/sospeso su mappa)
  * `accepting_bookings` (boolean, default true) → abilita/disabilita la possibilità di ricevere nuove prenotazioni

## ✅ STEP QR / CHECK-IN / CHECK-OUT (Partner)

### Codice prenotazione (manuale + QR)

Ogni prenotazione è associata a un codice nel formato:

**BD + 10 caratteri HEX** (12 caratteri totali)  
dove i 10 caratteri sono `0-9` e `A-F`.

Esempio: `BD1A2B3C4D5E`

Questo codice:

* può essere contenuto in un **QR Code** mostrato dall’utente
* può essere inserito **manualmente** dal partner (fallback se scanner non funziona)

### Scanner partner: HUB (non apre camera subito)

Lo scanner partner **non apre più subito la fotocamera**.  
Mostra invece una pagina “hub” con:

* **Scansiona QR** → apre la camera (`mobile_scanner`)
* **Inserisci codice manualmente** → dialog con input `BD...`
* **Area esito** (success/errore)
* **Paga ora (placeholder)** → per ora simula un pagamento e “forza” l’operazione (mock)

> Nota emulatore: se scansionando ti appare una “stanza 3D con gatto” e ti chiede **ALT** per muoverti, è la **Virtual Scene** della camera dell’Android Emulator. Su telefono reale vedrai la fotocamera vera.

### RPC server-side: `process_booking_code(p_code, p_force)`

Per registrare check-in / check-out in modo robusto (e bypassare limitazioni RLS lato client) usiamo una RPC:

`public.process_booking_code(p_code text, p_force boolean default false)`

Comportamento (alto livello):

* verifica che l’utente sia **owner del partner** (o admin)
* trova la prenotazione tramite `booking_code`
* se `dropoff_effective_at` è `NULL` → **check-in**
* altrimenti → **check-out**
* se il check-out supera `pickup_planned_at + 15 minuti`:
  * risponde `require_payment = true`
  * la UI mostra “**Paga ora**”
  * premendo “Paga ora (mock)” richiama la stessa RPC con `p_force = true`

### Tolleranza e supplemento (checkout)

* Tolleranza: **15 minuti**
* Se oltre tolleranza:
  * il sistema richiede “Paga ora” (placeholder)
  * una volta premuto, si procede al check-out comunque (mock payment / force)

### Stato `rejected` nello scanner

Nel flusso check-in/out (scanner) lo stato `rejected` viene trattato come `cancelled`: **non è processabile**.
> N.B.: la parte “rejected irreversibile” lato prenotazioni partner rimane invariata come già descritta.


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
  * Capacità (v2):
    * `base_capacity_u` (int) → capacità generale condivisa in unità equivalenti (u)
    * `extra_capacity_s`, `extra_capacity_m`, `extra_capacity_l` (int) → extra dedicati per taglia
    * `accept_s`, `accept_m`, `accept_l` (bool) → taglie accettate
    * campi derivati via trigger (per UI/filtri): `capacity_s`, `capacity_m`, `capacity_l`, `capacity`
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

    -- codice per QR / inserimento manuale (formato BD + 10 HEX)
    booking_code text unique,

    status text not null default 'confirmed' check (
      status in ('pending', 'confirmed', 'cancelled', 'completed', 'rejected')
    ),

    -- rifiuto partner (definitivo)
    reject_reason text,
    rejected_at timestamptz,

    contact_first_name text not null,
    contact_last_name  text not null,
    contact_phone      text not null,
    contact_email      text not null,

    bags_s integer not null default 0,
    bags_m integer not null default 0,
    bags_l integer not null default 0,

    notes text,

    -- gestione fasce orarie / giorni (input user)
    booking_date date,   -- giorno di consegna
    start_time   time,   -- orario di consegna
    end_date     date,   -- giorno di ritiro
    end_time     time,   -- orario di ritiro

    -- timestamp completi (calcolati via trigger)
    dropoff_planned_at   timestamptz,
    pickup_planned_at    timestamptz,
    dropoff_effective_at timestamptz, -- check-in effettivo
    pickup_effective_at  timestamptz, -- check-out effettivo

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  );


```md
> La determinazione di `dropoff_planned_at` e `pickup_planned_at` avviene via trigger SQL (es. `sync_booking_interval`),
> sincronizzando i campi `booking_date/start_time/end_date/end_time` con i timestamp completi.

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

## 🔒 RLS / RPC importanti

* `partner_bookings` ha RLS attiva per lettura (utente, owner, admin)
* Per aggiornare i campi di check-in/out dal partner usiamo una RPC `SECURITY DEFINER`:

  * `public.process_booking_code(p_code, p_force)`

---

# 📷 Permessi Fotocamera



## Android

In `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```
## IOS 
In `ios/Runner/Info.plist`:

```<key>NSCameraUsageDescription</key>
<string>Serve la fotocamera per scansionare i QR delle prenotazioni.</string>
```


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
│     │     │     |     ├── scanner_page.dart
│     │     │     |     ├── partner_scan_camera_screen.dart
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



## 🏬 schermate/partner/dashboard/pages/scanner_page.dart

* Pagina HUB con:
  * bottoni “Scansiona QR” e “Inserisci codice”
  * area esito (success/errore)
  * pulsante “Paga ora (mock)” se `require_payment = true`

## 📷 schermate/partner/dashboard/pages/partner_scan_camera_screen.dart

* Schermata camera con `mobile_scanner` che:
  * legge un QR
  * estrae un codice `BD[0-9A-F]{10}`
  * ritorna il codice alla pagina HUB



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

  * **Disponibilità per intervallo (v2)**:

    * dopo aver scelto data/ora, viene chiamato:

      * `PartnerBookingRepo.getPartnerAvailabilityForInterval(...)`
    * la funzione:

      * legge dal partner la source of truth:
        * `base_capacity_u`, `extra_capacity_s/m/l`, `accept_s/m/l`
      * calcola la richiesta utente in unità equivalenti:
        * `need_u = S*1 + M*2 + L*4`
      * considera le prenotazioni `pending/confirmed` che **si sovrappongono** all’intervallo
      * calcola quanto spazio **base** e **extra** è già consumato nell’intervallo
      * restituisce:
        * `availableS/M/L` (per taglia, rispettando accept + extra)
        * `availableTotal` (sulla base condivisa in unità equivalenti)


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

  * `rejectBooking({bookingId, reason})`:
    * chiama la RPC `public.reject_partner_booking(p_booking_id, p_reason)`
    * imposta lo stato a `rejected` (irreversibile) e salva motivazione + timestamp

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

  * `processBookingCode({required String code, bool force = false})`:
    * chiama la RPC `public.process_booking_code(p_code, p_force)`
    * gestisce check-in / check-out e risposta `require_payment`

  * `getBookingById(String bookingId)`:
    * recupera una prenotazione specifica (utile per mostrare dettagli dopo esito)

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
3. Vengono salvati i valori **source of truth**:

   * `base_capacity_u` (base condivisa in unità equivalenti)
   * `extra_capacity_s/m/l`
   * `accept_s/m/l`
4. `capacity_s/m/l` e `capacity` vengono **derivati via trigger** (per UI/filtri), non sono più input primari.
5. Viene (ri)creata una riga in `partner_requests` con `status = 'pending'`.
6. Finché non è approvato:

   * l’utente partner vede `PartnerWaitingScreen` (e, se `rejected`, il motivo).
7. Se admin approva:

   * il partner accede alla `PartnerShell`.

## 📦 Prenotazioni (stato attuale)

1. L’utente apre la **scheda partner** (`PartnerDetailScreen`) dalla mappa.
* La creazione di una prenotazione è consentita solo se il partner:
  * `status = approved`
  * `is_active = true`
  * `accepting_bookings = true`
2. Clicca **“Prenota ora”** → `BookingFlowScreen`.
  * disabilitato se `partner.accepting_bookings = false`
  * testo alternativo: “Prenotazioni sospese”
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
    * può **rifiutare** una prenotazione con **motivazione** → stato `rejected` (definitivo)

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

* ✔ Scanner partner con HUB + camera + inserimento manuale codice
* ✔ Check-in / check-out via RPC `process_booking_code` con tolleranza 15 minuti e “Paga ora” (mock payment / force)


* ✔ **Flusso prenotazione con slot base + disponibilità per intervallo**:

  * `BookingFlowScreen` lato utente:

    * Step: Contatto → Data e orario → Bagagli S/M/L → Riepilogo
    * selezione giorno/ora di consegna e ritiro (3h o durata personalizzata)
    * validazione con orari di apertura + limiti 7 giorni
  * **Motore di disponibilità per intervallo (v2)**:

    * `PartnerBookingRepo.getPartnerAvailabilityForInterval`
    * source of truth: `base_capacity_u` + `extra_capacity_s/m/l` + `accept_s/m/l`
    * unità equivalenti: `1S=1u, 1M=2u, 1L=4u`
    * controllo sia per taglia (accept + extra) sia per base condivisa (`base_capacity_u`)

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
## 2️⃣ QR Code / Codici (stato attuale)

* ✅ Scanner partner con HUB + camera + inserimento manuale
* ✅ Check-in/out con tolleranza e supplemento (mock payment)
* ⏳ Generazione/mostra codice lato utente dentro “Le mie prenotazioni” (UI completa)
* ⏳ Pagamento reale (Stripe) + gestione supplementi reali

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
