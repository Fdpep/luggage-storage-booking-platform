# 🧳 BagDrop – Flutter App

BagDrop è una piattaforma mobile che permette agli utenti di trovare attività partner (bar, negozi, hotel) dove lasciare i propri bagagli in modo sicuro.  
L’app è sviluppata in **Flutter** e utilizza **Supabase** come backend per autenticazione, database e storage.

---

# 🚀 Funzionalità Principali

## 👤 Utente
- Registrazione tramite email + password
- Verifica email via codice OTP
- Login / Logout
- Mappa interattiva con marker dei partner
- Scheda dettagliata partner (foto, regole, prezzi, orari)
- Prenotazioni (fase successiva)

## 🏬 Partner
- Registrazione come attività
- Verifica OTP e creazione richiesta partner (`partner_requests`)
- Stato della richiesta: pending → approved → rejected
- Dashboard partner:
  - Info attività
  - Modifica scheda locale
  - Caricamento foto tramite Supabase Storage
  - Cambio stato locale (attivo/sospeso)
- Future sezioni:
  - Prenotazioni
  - Scanner QR
  - Gestione capacità

## 🔐 Admin
- Login dedicato
- Dashboard di approvazione partner
- Accetta / rifiuta richieste con motivazione

---

# ⚙️ Architettura Backend (Supabase)

### 👥 Autenticazione
- Signup → OTP manuale
- Finché non viene verificato `otp_verified = true`, l'utente:
  - non accede all’app
  - non viene creato il profilo (`user_profiles`)
- Script automatico cron ogni 1 minuto:
  - elimina utenti non verificati da >15 min

### 🗄 Tabelle principali
auth.users # Autenticazione Supabase
user_profiles # Profili completati (creati solo se otp_verified = true)
partner_requests # Domande partner in attesa di approvazione
partners # Attività partner approvate
partner_photos # Foto locali partner

yaml
Copia codice

### 🖼️ Storage
Bucket: `partner-photos`  
Policy: gli utenti autenticati possono caricare e leggere.

---

Eccoti **una versione molto più chiara, ordinata e carina** della sezione *Struttura Cartelle (Flutter)*, con spiegazioni **cartella per cartella** e **file per file**, già pronta da incollare nel README.

Puoi copiarla così com'è.

---

# 📁 **Struttura delle Cartelle (Flutter)**

La struttura segue un’architettura pulita e modulare, dove ogni ruolo dell’app (utente, partner, admin) ha la propria sezione dedicata.

```
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
│     │      └── home_shell.dart  # Shell principale per utenti normali
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
│     │     │      ├── partner_signup_screen.dart        # Registrazione partner
│     │     │      ├── partner_registration_screen.dart   # Form con dati attività
│     │     │      ├── partner_application_screen.dart    # Riepilogo e invio domanda
│     │     │      └── partner_waiting_screen.dart        # Schermata "Richiesta in valutazione"
│     │     │
│     │     ├── detail/
│     │     │      └── partner_detail_screen.dart         # Scheda di dettaglio partner (vista utenti)
│     │     │
│     │     ├── dashboard/
│     │     │     ├── partner_shell.dart                  # Shell partner con bottom navigation
│     │     │     ├── pages/
│     │     │     │     ├── dashboard_page.dart           # Dashboard partner (stato attività)
│     │     │     │     ├── bookings_page.dart            # Prenotazioni (placeholder)
│     │     │     │     ├── scanner_page.dart             # Scanner QR (placeholder)
│     │     │     │     ├── spaces_page.dart              # Gestione posti/capacità (placeholder)
│     │     │     │     └── profile_page.dart             # Profilo partner
│     │     │     │
│     │     │     └── widgets/
│     │     │            └── partner_status_icon.dart      # Icona dinamica per bottom nav (pending / rejected)
│     │     │
│     │     └── dashboard/edit/
│     │            ├── partner_edit_screen.dart            # Modifica scheda locale
│     │            └── partner_photos_screen.dart          # Gestione foto (Storage)
│     │
│     └── admin/
│            └── admin_shell.dart       # Shell admin con lista richieste, approvazioni ecc.
│
```

---

# 📂 **Spiegazione Cartella per Cartella**

## 🧩 **root**

### `main.dart`

* Punto di ingresso dell’app.
* Inizializza Supabase.
* Carica le variabili `.env`.
* Mostra il `RootGate`.

---

## 🛣 **routes/**

### `auth_gate.dart`

Router principale:

* Decide se mostrare:
  ✔ Splash
  ✔ Login
  ✔ Home user
  ✔ Dashboard partner
  ✔ Dashboard admin
* In base al ruolo letto da `user_profiles.role`.

---

## 🎨 **theme/**

### `app_theme.dart`

* Tema Material 3 dell’app.
* Palette colori.
* Font Poppins.
* Stili generali.

---

## 🖼️ **schermate/splash/**

### `ingresso.dart`

* Mini-splash mostrato mentre AuthGate carica la sessione.

---

## 👤 **schermate/user/**

### `home_shell.dart`

* Shell principale per gli utenti normali.
* Contiene mappa, scheda partner e funzionalità dedicate.

---

## 🔐 **schermate/autenticazione/**

### `accesso.dart`

Login classico email + password.

### `registrazione.dart`

Signup utente normale.

### `reset_password.dart`

Schermata per recupero password via email.

### `verify_otp.dart`

Verifica codice OTP (sia utente normale che partner):

* blocco del pulsante indietro
* reinvio codice
* aggiornamento metadata Supabase

### `auth_actions.dart`

Utility globali per auth:

* logout confermato
* gestione redirect

---

## 🏬 **schermate/partner/**

Percorso completo delle schermate partner.

### 📌 auth_partner/

Flusso di onboard del partner:

* `partner_signup_screen.dart`
  Inserimento email + password.

* `partner_registration_screen.dart`
  Inserimento dati attività.

* `partner_application_screen.dart`
  Riepilogo e invio domanda.

* `partner_waiting_screen.dart`
  Mostrata finché l’admin non decide.

---

### 🔎 detail/

* `partner_detail_screen.dart`
  Scheda partner vista dal cliente: foto, recensioni future, info, orari.

---

### 🖥 dashboard/

* `partner_shell.dart`
  Shell partner con **bottom navigation**:

  * Dashboard
  * Prenotazioni
  * Scanner
  * Spazi
  * Profilo

* `pages/`
  Ogni tab della bottom navigation ha un file dedicato:

  | File                  | Funzione                                              |
  | --------------------- | ----------------------------------------------------- |
  | `dashboard_page.dart` | Panoramica dell’attività approvata                    |
  | `bookings_page.dart`  | Prenotazioni (fase futura)                            |
  | `scanner_page.dart`   | Scanner QR (fase futura)                              |
  | `spaces_page.dart`    | Stato capacità e posti (fase futura)                  |
  | `profile_page.dart`   | Dati account + azioni (modifica scheda, foto, logout) |

* `widgets/partner_status_icon.dart`
  Icona dinamica che mostra badge pending/rejected nella bottom nav.

* `edit/`
  Modifica dei dati del locale:

  * `partner_edit_screen.dart` → Nome, prezzi, capacità, regole, apertura
  * `partner_photos_screen.dart` → Foto con Supabase Storage

---

## 🛠 **schermate/admin/**

### `admin_shell.dart`

Dashboard amministratore:

* lista richieste partner
* approvazione / rifiuto
* gestione ruoli

---


# 🔄 Flussi Principali

## 🔐 Signup + OTP
1. L’utente registra email + password.
2. Riceve OTP (invio manuale).
3. Se verifica correttamente:
   - viene scritto `otp_verified = true` nei metadata
   - trigger Supabase crea automaticamente `user_profiles`
4. Se è un partner:
   - viene registrata la sua `partner_request`
   - finisce nella schermata **waiting**
   - Admin approva/rifiuta

## 🏬 Partner Approving
- **Pending:** blocco completo → PartnerWaitScreen o RestrictedScreen
- **Approved:** accesso completo alla dashboard partner
- **Rejected:** schermata che mostra motivazione + pulsante “Riprova”

---

# 🎨 UI/UX Attuale
- Tema Material 3 personalizzato
- Dashboard partner modulare
- Mappa utenti con marker partner
- Form dinamici con validazioni
- Caricamento foto con progress indicator
- Snakbars per feedback runtime

---

# 🧠 Funzionalità Completate

✔ Signup + Login  
✔ Verifica OTP manuale  
✔ Cleanup utenti non verificati  
✔ Partner flow completo (signup → richiesta → approvazione)  
✔ PartnerShell con bottom navigation  
✔ Modifica scheda locale partner  
✔ Supabase Storage per le foto  
✔ Mappa utente con partner reali  
✔ AdminShell base

---

# 🟦 Prossime Funzionalità da Implementare

## 1️⃣ Sistema Prenotazioni
- Creazione booking con relativa modifica delle tabelle e del form registrazione azienda
- Stato prenotazioni (in arrivo, attive, completate)
- Storico partner / utente
- Eventuale pagamento (Stripe)

## 2️⃣ Scanner QR
- Camera scanner
- Generazione QR prenotazione
- Check-in/out automatizzati

## 3️⃣ Miglioramento Dashboard Partner
- Statistiche
- Capacità in tempo reale
- Prenotazioni giornaliere

## 4️⃣ Dashboard Admin Avanzata
- Lista partner
- Lista utenti
- Logs
- Approvals più rapidi

## 5️⃣ Ottimizzazioni UX
- Onboarding animato
- Interazioni mappa più fluide
- Notifiche push
- Gestione email per rifiuto partner , accettazione e quant'altro..

---

# 🔧 Setup Sviluppo

## Configurare Supabase
Inserisci in `.env.android`:

SUPABASE_URL=YOUR_URL
SUPABASE_ANON_KEY=YOUR_KEY

go
Copia codice

Ricorda di registrarlo in `pubspec.yaml`:

```yaml
assets:
  - .env.android
Esegui l'app
arduino
Copia codice
flutter run --dart-define=SUPABASE_URL=xxx --dart-define=SUPABASE_ANON_KEY=xxx
🤝 Team & Contatti
Sviluppo curato da BagDrop Team
Supporto tecnico continuo tramite ChatGPT

📧 support@bagdrop.app
🌐 https://bagdrop.app

❤️ Licenza
Progetto privato – Tutti i diritti riservati BagDrop.

yaml
Copia codice

---

# 🎉 Fatto!  
Puoi **copiare e incollare l’intero blocco così com’è** nel file `README.md`.

Se vuoi aggiungere *immagini, badge o GIF demo*, generiamo la versione avanzata.