// lib/config/bagdrop_pricing.dart

class BagDropPricingInterval {
  final DateTime start; // consegna effettiva
  final DateTime userEnd; // ritiro scelto dall'utente (UI)
  final BagDropDuration duration; // fascia tariffaria determinata
  final DateTime effectiveEnd; // scadenza reale della fascia (da salvare a DB)
  final bool upgraded; // true se abbiamo scalato fascia (es. 3h -> 1d)
  final int extraDays;

  /// Giorni extra OLTRE i 3 giorni (0 se <=3 giorni)

  const BagDropPricingInterval({
    required this.start,
    required this.userEnd,
    required this.duration,
    required this.effectiveEnd,
    required this.upgraded,
    required this.extraDays,
  });
}

/// Tipi di durata supportati dal listino BagDrop.
/// (Per adesso lo teniamo pronto per il futuro calcolo prezzi nel flow.)
enum BagDropDuration {
  threeHours, // 3 ore
  oneDay, // 1 giorno
  oneAndHalfDay, // 1 giorno e mezzo
  twoDays, // 2 giorni
  threeDays, // 3 giorni
}

/// Configurazione prezzi **globali** di BagDrop.
/// Tutti i partner usano queste tariffe, non sono personalizzabili per locale.
///
/// N.B.: i valori sono di esempio, sostituiscili con il tuo listino reale.
class BagDropPricing {
  // ==========
  // TAGLIA S
  // ==========

  /// Prezzo per 3 ore, taglia Small.
  static const double s3h = 2.0;

  /// Prezzo per 1 giorno intero, taglia Small.
  static const double s1d = 4.0;

  /// Prezzo per 1 giorno e mezzo (3h + giorno successivo), taglia Small.
  static const double s1_5d = 6.0;

  /// Prezzo per 2 giorni interi, taglia Small.
  static const double s2d = 7.5;

  /// Prezzo per 3 giorni interi, taglia Small.
  static const double s3d = 9.0;

  // ==========
  // TAGLIA M
  // ==========

  /// Prezzo per 3 ore, taglia Medium.
  /// Esempio: un bagaglio M per 3 ore costa 3 €.
  static const double m3h = 3.0;

  /// Prezzo per 1 giorno, taglia Medium.
  static const double m1d = 5.0;

  /// Prezzo per 1 giorno e mezzo, taglia Medium.
  static const double m1_5d = 7.5;

  /// Prezzo per 2 giorni, taglia Medium.
  static const double m2d = 9.0;

  /// Prezzo per 3 giorni, taglia Medium.
  static const double m3d = 11.0;

  // ==========
  // TAGLIA L
  // ==========

  /// Prezzo per 3 ore, taglia Large.
  static const double l3h = 4.0;

  /// Prezzo per 1 giorno, taglia Large.
  static const double l1d = 6.0;

  /// Prezzo per 1 giorno e mezzo, taglia Large.
  static const double l1_5d = 9.0;

  /// Prezzo per 2 giorni, taglia Large.
  static const double l2d = 11.0;

  /// Prezzo per 3 giorni, taglia Large.
  static const double l3d = 13.0;

  // 💰 Calcolo prezzo totale
  // ====================================

  /// Calcola il prezzo totale in base a:
  /// - durata scelta
  /// - numero di bagagli S / M / L
  ///
  /// Esempio:
  ///   BagDropPricing.totalFor(
  ///     duration: BagDropDuration.threeHours,
  ///     bagsS: 1,
  ///     bagsM: 2,
  ///     bagsL: 0,
  ///   );
  static double totalFor({
    required BagDropDuration duration,
    required int bagsS,
    required int bagsM,
    required int bagsL,
    int extraDays = 0,
  }) {
    double priceS;
    double priceM;
    double priceL;

    switch (duration) {
      case BagDropDuration.threeHours:
        priceS = s3h;
        priceM = m3h;
        priceL = l3h;
        break;
      case BagDropDuration.oneDay:
        priceS = s1d;
        priceM = m1d;
        priceL = l1d;
        break;
      case BagDropDuration.oneAndHalfDay:
        priceS = s1_5d;
        priceM = m1_5d;
        priceL = l1_5d;
        break;
      case BagDropDuration.twoDays:
        priceS = s2d;
        priceM = m2d;
        priceL = l2d;
        break;
      case BagDropDuration.threeDays:
        priceS = s3d;
        priceM = m3d;
        priceL = l3d;
        break;
    }

    double base = priceS * bagsS + priceM * bagsM + priceL * bagsL;

    // ✅ Oltre 3 giorni: +2€ per bagaglio per ogni giorno extra (indipendente dalla taglia)
    if (duration == BagDropDuration.threeDays && extraDays > 0) {
      final bagCount = bagsS + bagsM + bagsL;
      base += extraDays * 2.0 * bagCount;
    }

    return base;
  }

  /// Utility per formattare un prezzo in euro con due decimali.
  /// Esempio: 3.0 -> "3,00 €"
  static String formatEuro(double value) {
    final txt = value.toStringAsFixed(2).replaceAll('.', ',');
    return '$txt €';
  }

  // =======================================================
  //  Calcolo automatico della durata tariffaria
  // =======================================================
  //
  // NON è ancora usato nel tuo flow (per ora scegli tu 3h / 1 giorno),
  // ma lo metto già qui perché ti servirà per il discorso "giorno e mezzo".

  /// Stima la durata tariffaria più adatta, dato un orario di deposito
  /// [start] e uno di ritiro [end].
  ///
  /// Logica proposta (puoi affinarla):
  /// - se la durata è <= 3 ore → threeHours
  /// - se deposito e ritiro sono lo stesso giorno → oneDay
  /// - se ritiro è il giorno dopo e entro le 13:00 → oneDayAndHalf
  /// - se durata <= 48h → twoDays
  /// - altrimenti → threeDays
  static BagDropDuration inferDuration({
    required DateTime start,
    required DateTime end,
  }) {
    if (!end.isAfter(start)) {
      // Caso patologico: ritiro <= deposito → consideriamo almeno 3 ore
      return BagDropDuration.threeHours;
    }

    final diff = end.difference(start);
    final hours = diff.inMinutes / 60.0;

    // Fino a 3 ore → tariffa 3h
    if (hours <= 3.0) {
      return BagDropDuration.threeHours;
    }

    // Stesso giorno → tariffa 1 giorno
    if (_isSameCalendarDay(start, end)) {
      return BagDropDuration.oneDay;
    }

    // Giorno successivo con ritiro "mattina / pranzo" → 1,5 giorni
    //
    // Esempio che hai fatto:
    // - deposito: oggi ore 19
    // - ritiro: domani ore 9
    //
    // Qui consideriamo "1,5 giorni" se il ritiro è il giorno dopo
    // e prima di una certa ora (cutoff, es. 13:00).
    final nextDay = start.add(const Duration(days: 1));
    final isNextDay = _isSameCalendarDay(nextDay, end);

    if (isNextDay) {
      // soglia ritiro: ore 13:00 del giorno dopo
      final cutoff = DateTime(end.year, end.month, end.day, 13, 0);
      if (end.isBefore(cutoff) || end.isAtSameMomentAs(cutoff)) {
        return BagDropDuration.oneAndHalfDay;
      }
    }

    // Fino a 48h → 2 giorni
    if (hours <= 48.0) {
      return BagDropDuration.twoDays;
    }

    // Oltre → 3 giorni (per ora limitiamoci qui)
    return BagDropDuration.threeDays;
  }

  static bool _isSameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Normalizza l'intervallo:
  /// - determina la fascia (duration) a partire da start + userEnd
  /// - calcola effectiveEnd = scadenza della fascia (quella che conta per ritardo/supplemento)
  ///
  /// getCloseForDay deve ritornare l'orario di chiusura del locale per quel giorno
  /// come DateTime (stesso giorno, in locale). Se non disponibile, usa 23:59.
  static BagDropPricingInterval normalizeBookingInterval({
    required DateTime start,
    required DateTime userEnd,
    required DateTime? Function(DateTime day) getCloseForDay,
    DateTime Function(DateTime day)? getOneAndHalfDayCutoffForDay,
  }) {
    // 1) Fascia tariffaria "stimata" dalla scelta utente
    var duration = inferDuration(start: start, end: userEnd);

    // 2) Calcolo scadenza reale della fascia
    DateTime effectiveEnd = _effectiveEndForDuration(
      start: start,
      duration: duration,
      getCloseForDay: getCloseForDay,
      getOneAndHalfDayCutoffForDay: getOneAndHalfDayCutoffForDay,
    );

    bool upgraded = false;

    // 3) Caso chiave: se 3h sforano la chiusura, scalo alla fascia successiva (1 giorno fino a chiusura)
    //    Questo evita prenotazioni che diventano "in ritardo" appena scadono le 3 ore perché il locale era già chiuso.
    if (duration == BagDropDuration.threeHours) {
      final close = _closeOrFallback(getCloseForDay, _dateOnly(start));
      final threeHoursEnd = start.add(const Duration(hours: 3));

      if (close != null && threeHoursEnd.isAfter(close)) {
        // scala a tutto il giorno
        duration = BagDropDuration.oneDay;
        effectiveEnd = _effectiveEndForDuration(
          start: start,
          duration: duration,
          getCloseForDay: getCloseForDay,
          getOneAndHalfDayCutoffForDay: getOneAndHalfDayCutoffForDay,
        );
        upgraded = true;
      }
    }

    // 4) ✅ Gestione oltre 3 giorni: calcolo extraDays e aggiorno effectiveEnd
    int extraDays = 0;

    if (duration == BagDropDuration.threeDays) {
      final startDay = _dateOnly(start);
      final userDay = _dateOnly(userEnd);
      final dayIndex = userDay.difference(startDay).inDays; // 0=stesso giorno

      // threeDays copre fino a startDay + 2
      if (dayIndex > 2) {
        extraDays = dayIndex - 2;

        final targetDay = startDay.add(Duration(days: 2 + extraDays));
        final close = _closeOrFallback(getCloseForDay, targetDay);
        effectiveEnd =
            close ??
            DateTime(targetDay.year, targetDay.month, targetDay.day, 23, 59);
      }
    }

    return BagDropPricingInterval(
      start: start,
      userEnd: userEnd,
      duration: duration,
      effectiveEnd: effectiveEnd,
      upgraded: upgraded,
      extraDays: extraDays,
    );
  }

  /// Scadenza della fascia tariffaria.
  static DateTime _effectiveEndForDuration({
    required DateTime start,
    required BagDropDuration duration,
    required DateTime? Function(DateTime day) getCloseForDay,
    DateTime Function(DateTime day)? getOneAndHalfDayCutoffForDay,
  }) {
    final startDay = _dateOnly(start);

    switch (duration) {
      case BagDropDuration.threeHours:
        return start.add(const Duration(hours: 3));

      case BagDropDuration.oneDay:
        {
          final close = _closeOrFallback(getCloseForDay, startDay);
          return close ?? DateTime(start.year, start.month, start.day, 23, 59);
        }

      case BagDropDuration.oneAndHalfDay:
        {
          final nextDay = startDay.add(const Duration(days: 1));

          // default: 13:00 del giorno dopo
          final cutoff = (getOneAndHalfDayCutoffForDay != null)
              ? getOneAndHalfDayCutoffForDay(nextDay)
              : DateTime(nextDay.year, nextDay.month, nextDay.day, 13, 0);

          // opzionale: non oltre la chiusura di quel giorno
          final closeNext = _closeOrFallback(getCloseForDay, nextDay);
          if (closeNext != null && cutoff.isAfter(closeNext)) {
            return closeNext;
          }
          return cutoff;
        }

      case BagDropDuration.twoDays:
        {
          // 2 giorni -> fino a chiusura del secondo giorno (startDay + 1)
          final day = startDay.add(const Duration(days: 1));
          final close = _closeOrFallback(getCloseForDay, day);
          return close ?? DateTime(day.year, day.month, day.day, 23, 59);
        }

      case BagDropDuration.threeDays:
        {
          // 3 giorni -> fino a chiusura del terzo giorno (startDay + 2)
          final day = startDay.add(const Duration(days: 2));
          final close = _closeOrFallback(getCloseForDay, day);
          return close ?? DateTime(day.year, day.month, day.day, 23, 59);
        }
    }
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime? _closeOrFallback(
    DateTime? Function(DateTime day) getCloseForDay,
    DateTime day,
  ) {
    return getCloseForDay(day);
  }

  static int lateFeeDiffCents({
    required BagDropDuration from,
    required BagDropDuration to,
    required int bagsS,
    required int bagsM,
    required int bagsL,
    required int extraDaysFrom, // per ora 0
    required int extraDaysTo, // per ora 0
  }) {
    double fromTotal = totalFor(
      duration: from,
      bagsS: bagsS,
      bagsM: bagsM,
      bagsL: bagsL,
    );
    double toTotal = totalFor(
      duration: to,
      bagsS: bagsS,
      bagsM: bagsM,
      bagsL: bagsL,
    );

    final bagCount = bagsS + bagsM + bagsL;

    // extra days oltre 3 giorni: +2€ per bagaglio per giorno extra
    if (to == BagDropDuration.threeDays && extraDaysTo > 0) {
      toTotal += extraDaysTo * 2.0 * bagCount;
    }
    if (from == BagDropDuration.threeDays && extraDaysFrom > 0) {
      fromTotal += extraDaysFrom * 2.0 * bagCount;
    }

    final diff = (toTotal - fromTotal);
    final clamped = diff < 0 ? 0 : diff;
    return (clamped * 100).round();
  }
}
