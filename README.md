# 🧳 BagDrop – Flutter App

BagDrop è una piattaforma mobile che permette agli utenti di trovare attività partner (bar, negozi, hotel) dove lasciare i propri bagagli in modo sicuro.
L’app è sviluppata in **Flutter** e utilizza **Supabase** come backend per autenticazione, database e storage.

---

# 🚀 Funzionalità Principali

## 👤 Utente

* Registrazione tramite email + password
* Verifica email via codice OTP
* Login / Logout
* Mappa interattiva con marker dei partner
* Scheda dettagliata partner (foto, regole, prezzi, orari)
* **Prenotazione deposito bagagli presso un partner** (flusso base già attivo: dati contatto + numero bagagli S/M/L, creazione record `partner_bookings`)
* **Schermata “Le mie prenotazioni”**:

  * tab dedicata nella home utente
  * lista delle prenotazioni con card per ogni booking (nome attività, stato, data, numero bagagli)
  * accesso al dettaglio attività collegato alla prenotazione
  * riepilogo completo dei dati inseriti (contatto + bagagli S/M/L)

> N.B.: pagamento online, QR code e disponibilità in tempo reale sono ancora da implementare.

## 🏬 Partner

* Registrazione come attività
* Verifica OTP e creazione richiesta partner (`partner_requests`)
* Stato della richiesta: pending → approved → rejected
* Dashboard partner:

  * Info attività
  * Modifica scheda locale
  * Caricamento foto tramite Supabase Storage
  * Cambio stato locale (attivo/sospeso)
  * **Visualizzazione prenotazioni ricevute** (lista delle righe `partner_bookings` con dati contatto + bagagli)
* Future sezioni:

  * Scanner QR
  * Gestione capacità in tempo reale
  * Statistiche prenotazioni

## 🔐 Admin

* Login dedicato
* Dashboard di approvazione partner
* Accetta / rifiuta richieste con motivazione

---

# ⚙️ Architettura Backend (Supabase)

### 👥 Autenticazione

* Signup → OTP manuale
* Finché non viene verificato `otp_verified = true`, l'utente:

  * non accede all’app
  * non viene creato il profilo (`user_profiles`)
* Script automatico cron ogni 1 minuto:

  * elimina utenti non verificati da >15 min

### 🗄 Tabelle principali

* `auth.users` → Autenticazione Supabase
* `user_profiles` → Profili completati (creati solo se `otp_verified = true`)
* `partner_requests` → Domande partner in attesa di approvazione
* `partners` → Attività partner approvate
* `partner_photos` → Foto locali partner
* `partner_bookings` → Prenotazioni bagagli (nuovo flusso implementato)

### 🖼️ Storage

Bucket: `partner-photos`
Policy: gli utenti autenticati possono caricare e leggere.

---

# 📁 **Struttura delle Cartelle (Flutter)**

La struttura segue un’architettura pulita e modulare, dove ogni ruolo dell’app (utente, partner, admin) ha la propria sezione dedicata.

```text
lib/
│
├── main.dart                     # Entry point dell’app
│
├── routes/
│     └── auth_gate.dart          # Router principale che decide cosa mostrare:
│                                 # utente / partner / admin / splash / login
│
├── theme/
│     └── app_theme.dart          # Tema generale dell'app (colori, font, stile)
│
├── schermate/
│     ├── splash/
│     │      └── ingresso.dart    # Splash iniziale durante bootstrap
│     │
│     ├── user/
│     │      ├── home_shell.dart  # Shell principale per utenti normali (mappa + tab Prenotazioni + Profilo)
│     │      └── bookings/
│     │             ├── user_bookings_page.dart           # Tab "Le mie prenotazioni" lato utente (lista prenotazioni personali)
│     │             ├── booking_partner_detail_screen.dart# Dettaglio attività collegata ad una prenotazione (foto, info, mappa + bottoni)
│     │             └── booking_recap_screen.dart         # Riepilogo prenotazione (dati contatto + bagagli S/M/L + note)
│     │
│     ├── autenticazione/
│     │      ├── accesso.dart         # Login
│     │      ├── registrazione.dart   # Registrazione utente normale
│     │      ├── reset_password.dart  # Reset password
│     │      ├── verify_otp.dart      # Verifica OTP per utenti e partner
│     │      └── auth_actions.dart    # Funzioni comuni (logout, conferme, utility)
│     │
│     ├── partner/
│     │     ├── auth_partner/
│     │     │      ├── partner_signup_screen.dart        # Signup partner (account + dati base attività, incl. capacità S/M/L)
│     │     │      ├── partner_registration_screen.dart  # Form domanda partner (dati attività + capacità S/M/L, usata quando già loggato)
│     │     │      ├── partner_application_screen.dart   # Schermata che spiega il flusso e rimanda a login/registrazione
│     │     │      └── partner_waiting_screen.dart       # Schermata "Richiesta in valutazione / rifiutata"
│     │     │
│     │     ├── user_view/
│     │     │      ├── partner_detail_screen.dart        # Scheda di dettaglio partner (vista utenti, da qui parte "Prenota ora")
│     │     │      └── booking_flow_screen.dart          # Flusso prenotazione lato utente (stepper: Contatto → Bagagli → Riepilogo)
│     │     │
│     │     ├── dashboard/
│     │     │     ├── partner_shell.dart                 # Shell partner con bottom navigation
│     │     │     ├── pages/
│     │     │     │     ├── dashboard_page.dart          # Dashboard partner (stato attività)
│     │     │     │     ├── prenotazioni_page.dart       # Lista prenotazioni ricevute (partner_bookings)
│     │     │     │     ├── scanner_page.dart            # Scanner QR (placeholder)
│     │     │     │     ├── spaces_page.dart             # Gestione posti/capacità (placeholder)
│     │     │     │     └── profile_page.dart            # Profilo partner
│     │     │     │
│     │     │     └── widgets/
│     │     │            └── partner_status_icon.dart    # Icona dinamica per bottom nav (pending / rejected / ok)
│     │     │
│     │     └── dashboard/edit/
│     │            ├── partner_edit_screen.dart          # Modifica scheda locale (nome, descrizione, prezzi, regole, apertura, capacità totale)
│     │            └── partner_photos_screen.dart        # Gestione foto (Storage)
│     │
│     └── admin/
│            └── admin_shell.dart       # Shell admin con lista richieste, approvazioni ecc.
│
├── models/
│     ├── partner.dart                  # Modello attività partner (status, info, capacità totale e per taglia, ecc.)
│     └── partner_booking.dart          # Modello prenotazione partner_bookings (contatto + bagagli S/M/L + status)
│
└── services/
      └── supabase/
            ├── client.dart             # Inizializzazione client Supabase
            ├── partner_repo.dart       # Repo per gestire dati partner (submitPartnerApplication con capacity_s/m/l, getMyPartner, getPartnerById)
            ├── partner_booking_repo.dart  # Repo per creare e leggere prenotazioni partner_bookings
            └── partner_photo/
                   └── partner_photo_repo.dart  # Repo per gestione foto partner
```

---

# 📂 Spiegazione Cartella per Cartella

## 🧩 root

### `main.dart`

* Punto di ingresso dell’app.
* Inizializza Supabase.
* Carica le variabili `.env`.
* Mostra il `RootGate` / `AuthGate`.

---

## 🛣 routes/

### `auth_gate.dart`

Router principale:

* Decide se mostrare:

  * Splash
  * Login
  * Home user
  * Dashboard partner
  * Dashboard admin
* In base al ruolo letto da `user_profiles.role`.

---

## 🎨 theme/

### `app_theme.dart`

* Tema Material 3 dell’app.
* Palette colori.
* Font Poppins.
* Stili generali di input, card, ecc.

---

## 🖼 schermate/splash/

### `ingresso.dart`

* Mini-splash mostrato mentre AuthGate carica la sessione.

---

## 👤 schermate/user/

### `home_shell.dart`

* Shell principale per gli utenti normali.
* Contiene:

  * mappa utente (`UserMapPage`),
  * tab “Prenotazioni”,
  * tab “Profilo”.
* Gestisce:

  * drawer laterale (login / registrazione / supporto),
  * gating per le tab che richiedono autenticazione,
  * check OTP verificato su accesso.

### `bookings/user_bookings_page.dart`

* Tab **“Le mie prenotazioni”** lato utente.
* Usa `PartnerBookingRepo.getMyBookings()` per caricare le prenotazioni dell’utente loggato.
* Mostra una lista di card con:

  * stato prenotazione (confirmed / pending / cancelled),
  * data creazione,
  * **nome attività (partner)**,
  * numero totale di bagagli.
* Tap sulla card → apre `BookingPartnerDetailScreen` con il dettaglio dell’attività collegata.

### `bookings/booking_partner_detail_screen.dart`

* Schermata di dettaglio **dell’attività** collegata a una prenotazione (vista dall’utente).
* Molto simile a `PartnerDetailScreen`, ma contestualizzata alla prenotazione:

  * foto del locale,
  * descrizione,
  * orari di apertura,
  * regole deposito,
  * contatti,
  * posizione su mappa.
* In basso mostra due bottoni:

  * **“Riepilogo”** → apre `BookingRecapScreen` con i dati della prenotazione.
  * **“QR code”** → placeholder che in futuro mostrerà il QR della prenotazione.

### `bookings/booking_recap_screen.dart`

* Schermata di **riepilogo prenotazione**.
* Mostra in forma strutturata:

  * dati partner (nome + indirizzo),
  * data creazione prenotazione,
  * dati di contatto inseriti dall’utente (nome, email, telefono),
  * numero di bagagli totali + S/M/L,
  * eventuali note.
* Pensata come “scheda riassuntiva” che l’utente può consultare quando arriva in struttura.

---

## 🔐 schermate/autenticazione/

### `accesso.dart`

* Login classico email + password.

### `registrazione.dart`

* Signup per utente normale (non partner).

### `reset_password.dart`

* Schermata per recupero password via email.

### `verify_otp.dart`

* Verifica codice OTP (sia utente normale che partner).
* Blocca il tasto back.
* Permette reinvio codice.
* Aggiorna metadata Supabase (`otp_verified`, ecc.).
* Nel flusso partner viene poi agganciata la creazione della richiesta/partner.

### `auth_actions.dart`

* Funzioni globali di auth:

  * logout con dialog di conferma
  * eventuali redirect comuni

---

## 🏬 schermate/partner/

### 📌 auth_partner/

Flusso di onboarding del partner:

* `partner_signup_screen.dart`

  * Registrazione account partner (email + password).
  * Raccolta **dati base attività** (nome, indirizzo, capacità totale derivata da S/M/L, prezzi, messaggio, lat/lng).
  * Salva i dati nel metadata `partner_signup`, inclusi i campi:

    * `capacity_s`, `capacity_m`, `capacity_l`
    * `capacity` (totale = somma S+M+L)
  * Alla fine manda alla schermata di verifica OTP (`SchermataVerifyOtp`).

* `partner_registration_screen.dart`

  * Form per inviare/rinviare una domanda partner da utente già loggato.
  * Usa `PartnerRepo.submitPartnerApplication` salvando in `partners`:

    * capacità per taglia (`capacity_s/m/l`)
    * capacità totale (somma)
    * coordinate geografiche, prezzi, ecc.
  * Alla fine porta alla `PartnerWaitingScreen`.

* `partner_application_screen.dart`

  * Spiega il flusso partner.
  * Permette di andare a login o registrazione utente.

* `partner_waiting_screen.dart`

  * Mostrata quando lo stato del partner è `pending` o `rejected`.
  * Se `rejected` mostra la motivazione e bottone “Riprova a inviare richiesta”.
  * Include sempre il pulsante per il logout.

---

### 🔎 user_view/

* `partner_detail_screen.dart`

  * Scheda partner vista dall’utente:

    * foto,
    * descrizione,
    * orari,
    * regole,
    * prezzi,
    * indirizzo,
    * mappa con marker.
  * Bottone fisso in basso **“Prenota ora”** che apre `BookingFlowScreen`.

* `booking_flow_screen.dart`

  * Flusso di prenotazione in **3 step**:

    1. Dati di contatto (nome, cognome, telefono, email, note).
    2. Selezione numero bagagli per taglia **S/M/L**.
    3. Riepilogo prenotazione.
  * Alla conferma:

    * chiama `PartnerBookingRepo.createBooking(...)`
    * crea una riga in `partner_bookings` con:

      * `partner_id`, `user_id`
      * contatto
      * `bags_s`, `bags_m`, `bags_l`
      * `notes`
    * mostra snackbar di conferma e torna alla scheda partner.

> N.B.: per ora non c’è controllo capacità né pagamento/QR; lo aggiungeremo in uno step successivo.

---

### 🖥 dashboard/

* `partner_shell.dart`

  * Shell partner con **bottom navigation**:

    * Dashboard
    * Prenotazioni
    * Scanner
    * Spazi
    * Profilo

* `pages/`

  * `dashboard_page.dart`

    * Panoramica stato attività.

  * `prenotazioni_page.dart`

    * **Lista prenotazioni ricevute dal partner**.
    * Usa `PartnerBookingRepo.getBookingsForPartner(partner.id)` per caricare le righe da `partner_bookings`.
    * Mostra:

      * nome e cognome contatto,
      * telefono ed email,
      * data creazione,
      * numero totale bagagli e dettaglio S/M/L,
      * note,
      * stato prenotazione (confirmed / pending / cancelled).

  * `scanner_page.dart`

    * Placeholder per scanner QR (da implementare).

  * `spaces_page.dart`

    * Placeholder per gestione posti / capacità in tempo reale (da implementare).

  * `profile_page.dart`

    * Dati account.
    * Azioni varie (es. modificare scheda, aprire foto, logout).

* `widgets/partner_status_icon.dart`

  * Icona dinamica usata nella bottom nav, con badge in base allo stato partner:

    * pending
    * rejected
    * approvato

---

### ✏️ dashboard/edit/

* `partner_edit_screen.dart`

  * Modifica scheda locale:

    * nome attività,

    * indirizzo (solo lettura),

    * descrizione,

    * telefono,

    * regole deposito,

    * orari apertura (campo testo salvato in `opening_hours["text"]`),

    * **capacità totale** (per ora un solo numero),

    * prezzi 2h / giorno,

    * stato `is_active` (attivo/sospeso).

  > La capacità S/M/L è già gestita in fase di registrazione, ma qui al momento si modifica solo la capacità totale. L’aggiornamento dell’edit per S/M/L è fra le cose ancora da fare.

* `partner_photos_screen.dart`

  * Gestione foto del locale:

    * upload su Supabase Storage (`partner-photos`)
    * lista foto per partner
    * delete foto

---

## 🛠 schermate/admin/

### `admin_shell.dart`

Dashboard amministratore:

* lista richieste partner
* approvazione / rifiuto
* gestione ruoli (base)

---

## 📦 Modelli & Services

### `models/partner.dart`

* Modello attività partner.
* Include:

  * id, owner_id
  * nome, indirizzo, lat/lng
  * `capacity` (totale)
  * **`capacity_s`, `capacity_m`, `capacity_l`** (capacità per taglia, usate per gestione futura capacità realtime)
  * prezzi
  * campi descrittivi (description, phone, rules)
  * stato richiesta (`status`, `reject_reason`)
  * `opening_hours` (mappa, spesso usata con chiave `"text"`)

### `models/partner_booking.dart`

* Modello per la tabella `partner_bookings`.
* Campi principali:

  * id, partner_id, user_id
  * status
  * contact_first_name / last_name / phone / email
  * `bags_s`, `bags_m`, `bags_l`
  * notes
  * created_at, updated_at

### `services/supabase/partner_repo.dart`

* Repository per operazioni sulla tabella `partners`.
* Funzioni principali:

  * `getMyPartner()` → restituisce il partner dell’utente loggato.
  * `getPartnerById(String partnerId)` → carica i dati di una specifica attività, usato nella sezione “Le mie prenotazioni” per mostrare nome/indirizzo del partner a partire da una prenotazione.
  * `updateBasics(...)` → aggiorna campi base (nome, address, capacity, prezzi, descrizione, telefono, regole, opening_hours, is_active).
  * `submitPartnerApplication(...)`

    * crea/aggiorna un partner per l’utente corrente,
    * salva:

      * `capacity_s`, `capacity_m`, `capacity_l`
      * `capacity` (totale)
      * status = `pending`, `is_active = false`, altri campi base
    * crea una riga in `partner_requests` con `status = pending`.

### `services/supabase/partner_booking_repo.dart`

* Repository per gestire il flusso prenotazioni (`partner_bookings`).

* `createBooking(...)`

  * richiede utente loggato,
  * inserisce una nuova prenotazione con:

    * `partner_id`, `user_id`
    * contatto
    * `bags_s/m/l`
    * `notes`
    * status di default `confirmed`.

* `getMyBookings()`

  * prenotazioni dell’utente corrente (lato app utente).

* `getBookingsForPartner(String partnerId)`

  * tutte le prenotazioni associate a un partner (lato dashboard partner).

---

# 🔄 Flussi Principali

## 🔐 Signup + OTP

1. L’utente registra email + password.
2. Riceve OTP (invio manuale).
3. Se verifica correttamente:

   * viene scritto `otp_verified = true` nei metadata
   * un trigger Supabase crea automaticamente `user_profiles`
4. Se è un partner:

   * attraverso i dati salvati in `partner_signup` / `partner_registration_screen` viene creata/aggiornata una riga in `partners` e una riga in `partner_requests`
   * lo stato parte da `pending`
   * finisce nella schermata di attesa (`PartnerWaitingScreen`) finché l’admin non decide.

## 🏬 Partner Approving

* **Pending:** blocco completo → PartnerWaitingScreen.
* **Approved:** accesso alla dashboard partner (`PartnerShell`).
* **Rejected:** PartnerWaitingScreen mostra motivazione + bottone “Riprova a inviare richiesta”.

## 📦 Prenotazioni (stato attuale)

Flusso già implementato:

1. Utente apre la **scheda partner** (`PartnerDetailScreen`).

2. Clicca **“Prenota ora”** → si apre `BookingFlowScreen`.

3. Step 1 → inserisce **dati contatto**.

4. Step 2 → seleziona **numero bagagli S/M/L**.

5. Step 3 → vede un **riepilogo**.

6. Clic su **“Conferma prenotazione”**:

   * viene creato un record in `partner_bookings`.

7. Lato partner:

   * nella tab “Prenotazioni” (`PrenotazioniPage`) vede la lista di tutte le prenotazioni con:

     * nome/cognome,
     * contatti,
     * data,
     * numero bagagli (totale + S/M/L),
     * note,
     * stato.

8. Lato utente:

   * nella tab “Prenotazioni” (`UserBookingsPage`) vede la lista **delle proprie prenotazioni**:

     * card con stato, data, numero di bagagli e nome dell’attività.
   * tap su una card:

     * apre `BookingPartnerDetailScreen` con il **dettaglio dell’attività** collegata,
     * da lì può:

       * aprire il **riepilogo prenotazione** (`BookingRecapScreen`),
       * in futuro, mostrare il QR code per il check-in/out (placeholder già presente).

Cose **non ancora** implementate nel flusso prenotazioni:

* Controllo capacità residua per taglia (S/M/L) prima di creare la prenotazione.
* Calcolo e visualizzazione **disponibilità in tempo reale** (posti occupati/restanti).
* QR code di check-in / check-out (solo placeholder lato UI).
* Pagamento online.

---

# 🧠 Funzionalità Completate

✔ Signup + Login
✔ Verifica OTP manuale
✔ Cleanup utenti non verificati
✔ Flusso partner (signup → metadata partner_signup → richiesta partner → waiting screen)
✔ PartnerShell con bottom navigation
✔ Modifica scheda locale partner
✔ Supabase Storage per le foto
✔ Mappa utente con partner reali
✔ AdminShell base
✔ **Flusso prenotazione base**:

* BookingFlowScreen lato utente
* creazione record `partner_bookings`
* PrenotazioniPage lato partner
* **Tab “Le mie prenotazioni” lato utente** con:

  * lista booking personali (`UserBookingsPage`),
  * dettaglio attività per prenotazione (`BookingPartnerDetailScreen`),
  * riepilogo dei dati inseriti (`BookingRecapScreen`).

---

# 🟦 Prossime Funzionalità da Implementare

## 1️⃣ Sistema Prenotazioni (step successivi)

* Controllo capacità S/M/L:

  * leggere `capacity_s/m/l` del partner,
  * sommare bagagli già prenotati,
  * bloccare nuove prenotazioni se non c’è spazio.
* Disponibilità in tempo reale su `PartnerDetailScreen` e/o `BookingPartnerDetailScreen`.
* Eventuale pagamento (Stripe o altro).
* QR code associato alla prenotazione (generazione, visualizzazione in app, validazione lato partner).

## 2️⃣ Scanner QR

* Camera scanner.
* Generazione QR prenotazione.
* Check-in/out automatizzati.

## 3️⃣ Miglioramento Dashboard Partner

* Statistiche per giorno / mese.
* Capacità in tempo reale.
* Prenotazioni giornaliere e calendario.

## 4️⃣ Dashboard Admin Avanzata

* Lista partner.
* Lista utenti.
* Logs.
* Approvals più rapidi.

## 5️⃣ Ottimizzazioni UX

* Onboarding animato.
* Interazioni mappa più fluide.
* Notifiche push.
* Gestione email per rifiuto/accettazione partner, conferma prenotazioni, ecc.

---

# 🔧 Setup Sviluppo

## Configurare Supabase

Inserisci in `.env.android`:

```env
SUPABASE_URL=YOUR_URL
SUPABASE_ANON_KEY=YOUR_KEY
```

Ricorda di registrarlo in `pubspec.yaml`:

```yaml
assets:
  - .env.android
```

Esegui l'app:

```bash
flutter run --dart-define=SUPABASE_URL=xxx --dart-define=SUPABASE_ANON_KEY=xxx
```

---

# 📌 Riepilogo file coinvolti nelle ultime modifiche

Schema rapido dei file toccati per il **flusso prenotazioni + capacità S/M/L**:

1. **`lib/schermate/partner/user_view/booking_flow_screen.dart`**

   * Flusso di prenotazione in 3 step lato utente.
   * Valida contatti e numero bagagli.
   * Crea il record in `partner_bookings` tramite `PartnerBookingRepo`.

2. **`lib/services/supabase/partner_booking_repo.dart`**

   * Espone `createBooking`, `getMyBookings`, `getBookingsForPartner`.
   * Si occupa di inserire/selezionare dalla tabella `partner_bookings`.

3. **`lib/models/partner_booking.dart`**

   * Modello Dart per `partner_bookings`.
   * Espone campi contatto, `bags_s/m/l`, status, timestamps.

4. **`lib/schermate/partner/dashboard/pages/prenotazioni_page.dart`**

   * Lista prenotazioni lato partner.
   * Usa `PartnerBookingRepo.getBookingsForPartner`.
   * Mostra card con:

     * nome/cognome,
     * contatti,
     * data,
     * bagagli S/M/L + totale,
     * note,
     * stato.

5. **`lib/schermate/partner/auth_partner/partner_signup_screen.dart`**

   * Aggiunti i campi per **capacità S/M/L** in fase di registrazione partner.
   * Calcola `capacity` totale come somma (S+M+L).
   * Salva nel metadata `partner_signup`:

     * `capacity_s`, `capacity_m`, `capacity_l`, `capacity`, `price2h`, `pricePerDay`, `lat`, `lng`, `message`.

6. **`lib/schermate/partner/auth_partner/partner_registration_screen.dart`**

   * Form di domanda partner da utente loggato.
   * Usa campi separati per capacità **S/M/L**.
   * Chiama `PartnerRepo.submitPartnerApplication` passando:

     * `capacityS`, `capacityM`, `capacityL`, `capacity` (totale), prezzi, lat/lng, message.

7. **`lib/services/supabase/partner_repo.dart`**

   * `submitPartnerApplication(...)` aggiornato/importante:

     * scrive su `partners` anche `capacity_s`, `capacity_m`, `capacity_l` oltre a `capacity` totale.
     * crea la riga `partner_requests` associata.
   * Aggiunto `getPartnerById(String partnerId)` per caricare i dati di un partner a partire dall’id (usato nella sezione “Le mie prenotazioni”).

8. **`lib/schermate/partner/user_view/partner_detail_screen.dart`**

   * Integra il bottone **“Prenota ora”** che apre `BookingFlowScreen`.
   * Mostra info partner che l’utente vede subito prima della prenotazione.

9. **`lib/schermate/user/bookings/user_bookings_page.dart`**

   * Nuova tab **“Le mie prenotazioni”** lato utente.
   * Carica le prenotazioni personali tramite `getMyBookings`.
   * Mostra una lista di card con partner, stato, data, numero di bagagli.
   * Tap su card → apre `BookingPartnerDetailScreen`.

10. **`lib/schermate/user/bookings/booking_partner_detail_screen.dart`**

    * Dettaglio attività collegata ad una prenotazione.
    * Mostra foto, descrizione, prezzi, orari, regole, contatti, mappa.
    * In basso bottoni:

      * **“Riepilogo”** → apre `BookingRecapScreen`.
      * **“QR code”** → placeholder per integrazione futura.

11. **`lib/schermate/user/bookings/booking_recap_screen.dart`**

    * Schermata di riepilogo prenotazione:

      * dati partner,
      * dati di contatto dell’utente,
      * bagagli totali e per taglia,
      * eventuali note.

---

# 🤝 Team & Contatti

Sviluppo curato da BagDrop Team
Supporto tecnico continuo tramite ChatGPT

📧 [support@bagdrop.app](mailto:support@bagdrop.app)
🌐 [https://bagdrop.app](https://bagdrop.app)

---

# ❤️ Licenza

Progetto privato – Tutti i diritti riservati BagDrop.
