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
    * regola di consumo (V2):
      * **prima** vengono consumati gli **extra dedicati** (`extra_capacity_*`) per la rispettiva taglia
      * **poi** l’eventuale eccedenza consuma lo **spazio generale** (`base_capacity_u`) in unità
    * la disponibilità viene verificata:
      * per taglia (rispettando `accept_*`)
      * e sul totale (`availableTotal`) calcolato in unità equivalenti sull’intervallo



* **Step “Bagagli” con barra dinamica di capacità**:

  * caricamento disponibilità tramite `PartnerBookingRepo.getPartnerAvailabilityForInterval(...)`
  * visualizzazione:

    * disponibili per taglia: **S / M / L**
    * **barra di progresso** che mostra quanto spazio totale viene occupato:

      * spazio totale in unità equivalenti (mezze M)
      * spazio già occupato da altre prenotazioni + selezione corrente
      * messaggio in rosso se la selezione supera la capacità
  * il numero di bagagli S/M/L è limitato in tempo reale:

    * per taglia (non puoi superare `availableS/M/L` calcolati con regola extra-first)
    * per spazio totale (non puoi superare `availableTotal` in unità equivalenti)

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
  
  * nei riepiloghi e nelle schermate prenotazione mostriamo:
    * **Consegna prevista**
    * **Ritiro scelto** (requested)
    * **Scadenza fascia** (effective end)


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
> * controlla sovrapposizioni tra intervallo richiesto e prenotazioni `pending/confirmed/in_store`
> * usa come source of truth: `base_capacity_u` + `extra_capacity_s/m/l` + `accept_s/m/l`
> * regola extra-first: prima extra dedicati, poi base in unità equivalenti
>   Non è ancora presente un enforcement atomico lato DB (RPC/trigger), né scheduling avanzato (slot generati automaticamente, regole complesse per “alto carico”, ecc.) né pagamento online.


---

## 🏬 Partner

### Flusso ufficiale (Sito Web)
La registrazione partner avviene tramite **wizard sul sito** (non più dall’app), perché app e sito condividono lo stesso database Supabase.

Workflow `partner_requests.status` (ENUM `partner_request_status`):
- `draft` → bozza creata/riusata dal sito
- `submitted` → richiesta inviata (in revisione)
- `awaiting_payment` → documenti approvati, pagamento richiesto
- `paid` → pagamento completato, ruolo `partner` e accesso alla `PartnerShell`
- `rejected` → richiesta rifiutata con motivazione

### UX lato App (gating)
Dopo login + OTP:
- `role = user` → app utente normale
- `role = partner_candidate` → schermate dedicate in base a `partner_requests.status`:
  - `draft` → schermata “Completa dal sito”
  - `submitted` → schermata “In revisione”
  - `awaiting_payment` → schermata “Pagamento richiesto” (con link al sito)
  - `rejected` → schermata “Rifiutato” con motivazione
- `role = partner` → accesso alla `PartnerShell`

### 📱 Schermate Partner Candidate (App)

Quando `user_profiles.role = partner_candidate`, l’utente NON entra nella PartnerShell.
L’accesso è gestito da `AuthGate` in base allo stato della richiesta `partner_requests.status`.

Schermate dedicate (cartella `schermate/partner/auth_partner/`):

- `PartnerOnboardingStartScreen`
  - mostrata quando:
    - non esiste ancora una richiesta
    - oppure `status = draft`
  - mostra messaggio:
    > “Completa la registrazione dal sito BagDrop”
  - contiene link/bottone verso il wizard web

- `PartnerWaitingScreen`
  - mostrata quando `status = submitted`
  - stato: documenti in revisione

- `PartnerPaymentRequiredScreen`
  - mostrata quando `status = awaiting_payment`
  - invita a controllare l’email o aprire il link di pagamento
  - dopo il pagamento e refresh session → accesso partner

- `PartnerRejectedScreen`
  - mostrata quando `status = rejected`
  - mostra `reject_reason` se presente

Solo quando:
- `status = paid`
- **e** `user_profiles.role = partner`

l’utente accede alla `PartnerShell`.



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


## 🌐 Onboarding Partner (Sito Web) — flusso ufficiale

La registrazione partner avviene tramite **wizard sul sito** (non più dall’app), perché app e sito condividono lo stesso database Supabase.

### Step del wizard
1. **Account** (signup/login + OTP)
2. **Attività** (nome, indirizzo, lat/lng da Maps)
3. **Orari** (formato `opening_hours.weekly_v1` + eccezioni)
4. **Capacità** (v2: base in M → unità equivalenti + extra per taglia)
5. **Riepilogo + Contratto firmato (PDF)**

### Cosa salva il sito (DB)
- Upsert su `partners` con:
  - dati attività + posizione
  - `opening_hours` (`weekly_v1`)
  - capacità v2:
    - `base_capacity_u`
    - `extra_capacity_s/m/l`
    - `accept_s/m/l`
- Creazione/riuso riga in `partner_requests` con **stato iniziale `draft`**
- Upload del contratto firmato su Storage bucket `partner-contracts`
- Collegamento del contratto alla richiesta (`partner_requests.contract_signed_url`, `contract_signed_at`)
- Invio richiesta → `partner_requests.status = submitted`
- Cambio ruolo utente → `user_profiles.role = partner_candidate`

> Importante: il client NON fa update diretti su `partner_requests` (RLS).  
> Tutto il flusso “request + submit + pagamento” passa da RPC `SECURITY DEFINER`.



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
* Il ritardo viene misurato rispetto a:
  * `pickup_planned_at` → che è la **scadenza fascia** (non il ritiro scelto)
* Se `pickup_effective_at > pickup_planned_at + 15 min`:
  * `require_payment = true`
  * UI mostra “Paga ora” (mock)


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


## 📩 Approve Admin → Email → Pagamento (Stripe Checkout)

### Obiettivo di business
Quando l’admin approva i documenti, il partner **NON entra subito** nell’area partner.
Deve prima completare il pagamento.

### Workflow stato richiesta (partner_requests.status)
1. Partner invia richiesta (`submitted`)
2. Admin approva documenti → `awaiting_payment`
3. Il partner completa il pagamento via **Stripe Checkout**
4. Stripe invia webhook → il sistema finalizza → `paid` + ruolo `partner`

### UX lato app
Se `role = partner_candidate`:
- `submitted` → schermata “In revisione”
- `awaiting_payment` → schermata “Pagamento richiesto”
- `rejected` → schermata “Rifiutato”
Solo dopo `paid` l’utente accede alla `PartnerShell`.

---

### 🧠 Implementazione tecnica (attuale)

#### Componenti
- **Edge Function** `create-partner-checkout-session`  
  Crea una sessione Stripe Checkout per la richiesta `awaiting_payment`.
- **Edge Function** `stripe-webhook`  
  Verifica firma Stripe e finalizza pagamento lato DB via RPC.
- **RPC DB** `finalize_partner_payment_webhook(...)`  
  Esegue la transizione atomica `awaiting_payment → paid` e aggiorna ruolo/partner.

#### Flow tecnico
1. Il partner (autenticato su Supabase) apre la pagina web di pagamento.
2. La pagina chiama `create-partner-checkout-session` passando JWT (Bearer).
3. La function crea una Checkout Session con metadata:
   - `partner_request_id`
   - `supabase_user_id`
4. Stripe a pagamento completato invia `checkout.session.completed` al webhook.
5. `stripe-webhook` verifica la firma con `STRIPE_WEBHOOK_SECRET` e chiama:
   - `finalize_partner_payment_webhook(p_request_id, p_stripe_session_id, p_payment_reference)`
6. Il partner riapre l’app → `AuthGate` rilegge ruolo e sblocca `PartnerShell`.

#### Requisiti di sicurezza
- `create-partner-checkout-session` richiede **Authorization: Bearer <JWT>**
- `stripe-webhook` NON usa JWT (Stripe non manda Authorization):
  - sulla function **JWT verification deve essere disabilitata** (solo per webhook)
- Firma webhook verificata con `stripe-signature` e body raw.


Effetti della RPC:

partner_requests.status: awaiting_payment → paid

user_profiles.role: partner_candidate → partner

partners.is_active = true

partners.status = 'approved'

Dopo il pagamento:

l’utente riapre l’app

AuthGate rilegge ruolo + stato

accesso automatico alla PartnerShell
---

# ⚙️ Architettura Backend (Supabase)


### AuthGate (Flutter)

L’accesso all’app è centralizzato in `routes/auth_gate.dart`.

Responsabilità:
- verifica sessione Supabase
- verifica OTP (`otp_verified`)
- carica `user_profiles.role`
- se `partner_candidate`, carica anche `partner_requests.status`
- gestisce polling automatico (20s) per aggiornamenti stato
- invalida correttamente polling su logout / resume app

È la **source of truth UX** per il routing post-login.


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
* `partner_requests` → richieste di onboarding partner (workflow)
  * `id`
  * `user_id` (owner della richiesta)
  * `partner_id` (collega l’attività in `partners`)
  * `status` (ENUM `partner_request_status`):
    * `draft` → bozza creata/riusata dal sito
    * `submitted` → inviata (in review)
    * `awaiting_payment` → documenti approvati, pagamento richiesto
    * `paid` → pagamento confermato, partner attivato
    * `rejected` → rifiutata (con motivazione)
  * `docs_approved_at`
  * `payment_required` (bool)
  * `paid_at`
  * `payment_reference` (test/stripe id)
  * `contract_signed_url` (path su Storage)
  * `contract_signed_at`
  * `reject_reason`
  * `updated_at` (auto aggiornato via trigger)
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
> `pickup_planned_at` viene calcolato su `end_date/end_time` (**scadenza fascia**).
> `end_date_requested/end_time_requested` non influenzano scheduling/capacity: servono per mostrare “ritiro scelto”.

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

## 🔒 RLS / RPC — Onboarding Partner (nuovo)

### RLS (partner_requests)
- SELECT: l’utente può leggere solo la propria richiesta (`user_id = auth.uid()`)
- INSERT: consentito solo per creare `draft/submitted` (ma idealmente si crea via RPC)
- UPDATE: **bloccato lato client** (nessuna policy update)  
  → ogni transizione di stato avviene via RPC `SECURITY DEFINER`

### RPC principali (server-side)
- `upsert_partner_request_draft(p_partner_id uuid) -> uuid`  
  Crea o riusa la richiesta “attiva” (`draft/submitted/awaiting_payment`) per l’utente e ritorna `request_id`.

- `submit_partner_request() -> void`  
  Porta `draft → submitted` e imposta `user_profiles.role = partner_candidate`.

- `admin_approve_partner_docs(p_request_id uuid) -> void`  
  Solo admin: porta a `awaiting_payment`, imposta `docs_approved_at`, `payment_required=true`.

- `confirm_partner_payment(p_request_id uuid, p_payment_reference text) -> void`  
  L’utente conferma il pagamento della PROPRIA richiesta:
  - `awaiting_payment → paid`
  - ruolo `user_profiles.role = partner`
  - attiva `partners` (`status=approved`, `is_active=true`, `activated_at=now()`)

> Nota: il pagamento Stripe reale verrà aggiunto dopo.  
> Per test esiste una pagina “pagamento finto” con un bottone che chiama `confirm_partner_payment(...)`.



## 💳 Stripe Payments (Partner onboarding)

### Secrets Supabase (Edge Functions)
Configurati con:
```bash
supabase secrets set \
  STRIPE_SECRET_KEY="sk_test_..." \
  STRIPE_WEBHOOK_SECRET="whsec_..." \
  STRIPE_PARTNER_PRICE_ID="price_..." \
  PAYMENT_SUCCESS_URL="http://localhost:5500/payment.html" \
  PAYMENT_CANCEL_URL="http://localhost:5500/payment.html"


⚠️ In Supabase Dashboard → Edge Functions → `stripe-webhook` → **Disable JWT verification** (solo per questa function).


### Logs Edge Functions (Supabase CLI)
Per vedere i log:
- via Dashboard: Project → Edge Functions → Logs
- oppure in locale con `supabase functions serve`

Nota: alcune versioni CLI non supportano `supabase functions logs --project-ref ...`.



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
│     │     │      ├── partner_onboarding_start_screen.dart
│     │     │      ├── partner_payment_required_screen.dart
│     │     │      ├── partner_rejected_screen.dart
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

NOTA BENE : partner signup , registration ed application sono deprecate. Ora si fa da sito.

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
      * calcola consumo su intervallo con regola **extra-first**
        (prima extra dedicati per taglia, poi base in unità)
      * restituisce:
        * `availableS/M/L` (extra rimasti + base residuo convertito)
        * `availableTotal` (totale disponibile in unità equivalenti sull’intervallo)



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

  * **Pricing (single source of truth) – BagDropPricing**:

    * tutta la logica prezzi + fasce orarie è centralizzata in `lib/config/bagdrop_pricing.dart`
      (così eventuali cambi tariffe/regole si fanno in **un solo file**)

    * **Fasce tariffarie (pricing windows)**:
      - **3 ore**
      - **Tutto il giorno** → scade alla **chiusura del locale** del giorno di consegna
      - **1 giorno e mezzo** → scade alle **13:00 del giorno successivo**
      - **2 giorni**, **3 giorni**, … (estendibile)

    * **Regola chiave (scadenza fascia)**:
      - l’utente può scegliere un “ritiro” anche **prima**
      - ma la prenotazione viene **normalizzata** alla **scadenza della fascia** in cui ricade
      - quindi il **supplemento / ritardo** scatta **solo dopo la scadenza fascia**, non dopo il ritiro scelto

    * **Doppio orario salvato** (per recap e trasparenza):
      - `end_date_requested` + `end_time_requested` → **ritiro scelto dall’utente**
      - `end_date` + `end_time` → **scadenza fascia (effective end)** usata per:
        - calcolo disponibilità intervallo (capacity overlap)
        - calcolo prezzo base della prenotazione
        - trigger `pickup_planned_at`

    * nel flow, quando l’utente seleziona data/ora:
      - validiamo **solo** consegna e ritiro richiesto (devono stare negli orari di apertura)
      - poi calcoliamo la **scadenza fascia** tramite `BagDropPricing.normalizeBookingInterval(...)`


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
      -- ritiro scelto dall’utente (UI / trasparenza)
  * `  end_date_requested date `,
  * `  end_time_requested time `,

  * `createdAt`, `updatedAt`

> Nota: `end_date/end_time` rappresentano la **scadenza fascia (effective end)** calcolata lato client tramite BagDropPricing.
> L’orario scelto dall’utente viene salvato separatamente in `end_date_requested/end_time_requested`.
> Il trigger `sync_booking_interval` costruisce `pickup_planned_at` usando **end_date/end_time** (scadenza fascia).


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
    * source of truth V2:
      * `base_capacity_u`, `extra_capacity_s/m/l`, `accept_s/m/l`
    * fallback legacy (solo se V2 mancante):
      * deriva `base_capacity_u` da `capacity_m/s/l` o `capacity` (compatibilità dati vecchi)
    * regola extra-first:
      * prima consuma extra dedicati per taglia, poi base in unità (u)
    * considera prenotazioni attive:
      * `status in ('pending','confirmed','in_store')`


  * `getPartnerAvailabilityForInterval({...})`:

    * calcola la disponibilità per **uno specifico intervallo**:

      * `startDate + startTime` → inizio
      * `endDate + endTime` → fine
    * considera:

      * solo prenotazioni per quel partner
      * solo `status in ('pending', 'confirmed', 'in_store')`
      * solo prenotazioni che **si sovrappongono** all’intervallo richiesto
    * regola extra-first:
      * prima consuma extra dedicati per taglia, poi base in unità
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
5. Viene creata/riusata una riga in `partner_requests` con `status = 'draft'` (poi `submitted` alla conferma).
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


### ✅ Prenotazione riprendibile (requirement)
Il flusso prenotazione deve essere **riprendibile in qualsiasi stato**:
- se l’utente chiude l’app durante lo stepper, al riavvio deve poter riprendere
- la bozza può vivere lato client (storage) e/o lato DB (estensione futura)
- la conferma finale resta vincolata a disponibilità e validazioni dell’intervallo

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
  * salvataggio source of truth V2:
    * `base_capacity_u` (da input M convertito in unità)
    * `extra_capacity_s/m/l`
    * `accept_s/m/l`
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
