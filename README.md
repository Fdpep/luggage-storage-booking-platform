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
  - step guidati (Contatto → Bagagli → Riepilogo)
  - inserimento:
    - nome, cognome, telefono, email, note
    - bagagli per taglia **S / M / L**
  - salvataggio in `partner_bookings` con:
    - riferimento all’utente (`user_id`)
    - riferimento al partner (`partner_id`)
    - dati di contatto “fotografati” (anche se l’utente cambia profilo in futuro)
    - numero di bagagli S/M/L
    - timestamp di creazione (`created_at`)
- **Schermata “Le mie prenotazioni”**:
  - tab dedicata nella home utente
  - lista delle prenotazioni con:
    - stato (confirmed/pending/cancelled)
    - data di creazione
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

> N.B.: **Data/orario di deposito, slot orari e pagamento online** sono pianificati come estensioni future. Al momento le prenotazioni non hanno ancora `booking_date`, `start_time`, `end_time` in tabella: si lavora solo con il `created_at`.

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
  - prezzi:
    - prezzo per 2h
    - prezzo per giorno
  - stato `is_active` (attivo/sospeso su mappa)

- **Prenotazioni ricevute** (`PrenotazioniPage`):

  - lista delle righe in `partner_bookings` per quel partner
  - mostra:
    - nome e cognome del contatto
    - telefono, email
    - data di creazione
    - totale bagagli + dettaglio S/M/L
    - note
    - stato (confirmed / pending / cancelled)

- **Blocco modifiche orari/capacità con prenotazioni future**:

  - `PartnerEditScreen` usa `PartnerBookingRepo.hasActiveFutureBookingsForPartner(partner.id)`
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
- `partners` → attività partner:
  - id, owner_id
  - nome, indirizzo, lat/lng
  - `capacity_s`, `capacity_m`, `capacity_l`, `capacity` totale
  - prezzi, regole, description, phone
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

    -- in futuro: fasce orarie / giorni
    -- booking_date date,
    -- start_time   time,
    -- end_time     time,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  );
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

* `user_bookings_page.dart`:

  * carica le prenotazioni utente via `PartnerBookingRepo.getMyBookings()`
  * mostra card con:

    * stato (chip colorato)
    * data di creazione
    * nome partner (caricato da `PartnerRepo.getPartnerById`)
    * numero totale bagagli
* `booking_partner_detail_screen.dart`:

  * simile a `partner_detail_screen.dart` ma contestualizzata alla prenotazione
  * mostra:

    * foto, descrizione, prezzi
    * **orari di apertura (weekly_v1 + eccezioni)**
    * regole, contatti, mappa
  * bottoni in basso:

    * “Riepilogo” (apre `BookingRecapScreen`)
    * “QR code” (placeholder)
* `booking_recap_screen.dart`:

  * riepilogo statico:

    * dati partner
    * contatto (nome, email, telefono)
    * bagagli totali e per taglia
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
    2. Bagagli (S/M/L)
    3. Riepilogo finale
  * valida:

    * nome/cognome
    * email (contiene `@`)
    * telefono (solo cifre, lunghezza minima)
    * almeno un bagaglio
  * alla conferma crea record in `partner_bookings` via `PartnerBookingRepo.createBooking(...)`.

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

1. Partner compila `partner_signup_screen.dart` (o `partner_registration_screen.dart` se già loggato).
2. Viene creata/aggiornata una riga `partners` con:

   * capacità S/M/L + totale
   * prezzi
   * coordinate, ecc.
3. Viene creata una riga in `partner_requests` con `status = 'pending'`.
4. Finché non è approvato:

   * l’utente partner vede `PartnerWaitingScreen` (in caso di `rejected` mostra anche motivo).
5. Se admin approva:

   * partner vede `PartnerShell` (dashboard).

## 📦 Prenotazioni (stato attuale)

1. L’utente apre la **scheda partner** (`PartnerDetailScreen`) dalla mappa.
2. Clicca **“Prenota ora”** → `BookingFlowScreen`.
3. Step 1:

   * inserisce nome, cognome, email, telefono, note.
4. Step 2:

   * seleziona numero di bagagli S/M/L (almeno 1 in totale).
5. Step 3:

   * vede un riepilogo (partner, contatto, bagagli, note).
6. Conferma:

   * viene creato il record in `partner_bookings`.
7. Lato utente:

   * in “Le mie prenotazioni” vede tutte le prenotazioni create.
8. Lato partner:

   * in “Prenotazioni” vede tutte le prenotazioni ricevute.

> Al momento **non esiste ancora la logica di slot giornalieri/orari** né database di `booking_date`, `start_time`, `end_time`. Questi campi sono commentati in migration e previsti per la versione successiva del sistema di prenotazione.

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
* ✔ Flusso prenotazione base:

  * BookingFlowScreen lato utente (dati contatto + bagagli S/M/L)
  * creazione record in `partner_bookings`
  * PrenotazioniPage lato partner (lista prenotazioni)
  * Tab “Le mie prenotazioni” lato utente
  * BookingPartnerDetailScreen + BookingRecapScreen
* ✔ Nuovi orari partner:

  * editor settimanale `weekly_v1` con eccezioni (chiusure/aperture straordinarie)
  * render lato utente per orari + eccezioni
* ✔ Profilo utente:

  * visualizzazione/modifica nome, cognome, telefono
  * flusso **eliminazione account** con codice di conferma e blocco se ci sono prenotazioni attive

---

# 🟦 Prossime Funzionalità

## 1️⃣ Sistema Prenotazioni (evoluzione)

* Aggiunta di:

  * `booking_date`
  * `start_time` / `end_time`
* Slot orari generati dinamicamente in base a `opening_hours` (mattina/pomeriggio).
* Calcolo disponibilità **per intervallo** (non solo globale).
* UI migliorata per mostrare:

  * data + fascia oraria in modo evidente:

    * in riepilogo
    * in lista “Le mie prenotazioni”
    * in lista prenotazioni partner

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
