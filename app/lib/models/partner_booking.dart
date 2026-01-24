// lib/models/partner_booking.dart
class PartnerBooking {
  final String id;
  final String partnerId;
  final String userId;

  /// Stato logico della prenotazione:
  /// pending / confirmed / cancelled / completed
  final String status;

  /// Se rifiutata dal partner
  final String? rejectReason;
  final DateTime? rejectedAt;

  /// Dati di contatto (mappati 1:1 sulle colonne contact_*)
  final String firstName;
  final String lastName;
  final String phone;
  final String email;

  /// Numero di bagagli per taglia
  final int bagsS;
  final int bagsM;
  final int bagsL;

  final String? notes;

  /// Timestamps tecnici
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Vecchio modello "giorno + ora"
  ///
  /// booking_date: solo data (giorno di inizio deposito)
  /// end_date: giorno di fine deposito (può coincidere con booking_date)
  /// start_time / end_time: orari nelle rispettive giornate
  final DateTime bookingDate;
  final DateTime? endDate;
  final String startTime; // 'HH:MM:SS' (o 'HH:MM')
  final String endTime; // 'HH:MM:SS' (o 'HH:MM')

  final DateTime? endDateRequested;
  final String? endTimeRequested;

  /// Nuovo modello "timestamp completi"
  ///
  /// Calcolati via trigger su Supabase e già backfillati:
  /// - dropoff_planned_at  = consegna prevista
  /// - pickup_planned_at   = ritiro previsto
  /// - dropoff_effective_at / pickup_effective_at = effettivi (per quando
  ///   implementeremo lo scan QR in entrata/uscita)
  final DateTime? dropoffPlannedAt;
  final DateTime? pickupPlannedAt;
  final DateTime? dropoffEffectiveAt;
  final DateTime? pickupEffectiveAt;

  final String bookingCode; // BDXXXXXXXXXX

  final bool lateFeeRequired;
  final int? lateFeeAmountCents;
  final DateTime? lateFeePaidAt;

  final DateTime? coveredUntil;
  final int totalPaidCents;

  const PartnerBooking({
    required this.id,
    required this.partnerId,
    required this.userId,
    required this.status,
    this.rejectReason,
    this.rejectedAt,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    required this.bagsS,
    required this.bagsM,
    required this.bagsL,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    required this.bookingDate,
    this.endDate,
    required this.startTime,
    required this.endTime,
    this.endDateRequested,
    this.endTimeRequested,
    required this.bookingCode,
    this.dropoffPlannedAt,
    this.pickupPlannedAt,
    this.dropoffEffectiveAt,
    this.pickupEffectiveAt,

    this.lateFeeRequired = false,
    this.lateFeeAmountCents,
    this.lateFeePaidAt,

    this.coveredUntil,
    this.totalPaidCents = 0,
  });

  /// Numero totale di bagagli (S+M+L)
  int get totalBags => bagsS + bagsM + bagsL;

  /// Timestamp di copertura (se presente) in locale
  DateTime? get coveredUntilLocal => coveredUntil?.toLocal();

  /// Consegna prevista:
  /// usiamo sempre booking_date + start_time interpretati come orari locali.
  DateTime get plannedDropoffLocal {
    return _combineDateAndTime(bookingDate, startTime);
  }

  /// Ritiro previsto:
  /// usiamo (end_date o booking_date) + end_time interpretati come orari locali.
  DateTime get plannedPickupLocal {
    final d = endDate ?? bookingDate;
    return _combineDateAndTime(d, endTime);
  }

  //ritiro scelto dall'utente
  DateTime get requestedPickupLocal {
    final d = endDateRequested ?? endDate ?? bookingDate;
    final t = endTimeRequested ?? endTime;
    return _combineDateAndTime(d, t);
  }

  DateTime get requestedPickupAtLocal => requestedPickupLocal.toLocal();

  /// Planned (preferisci i timestamp completi se presenti)
  DateTime get plannedDropoffAtLocal =>
      (dropoffPlannedAt ?? plannedDropoffLocal).toLocal();

  DateTime get plannedPickupAtLocal =>
      (pickupPlannedAt ?? plannedPickupLocal).toLocal();

  /// Effective (se presenti)
  DateTime? get effectiveDropoffAtLocal => dropoffEffectiveAt?.toLocal();
  DateTime? get effectivePickupAtLocal => pickupEffectiveAt?.toLocal();

  /// Status “logico” usato per UI (uguale lato utente e lato partner)
  String get uiStatus {
    final s = status.toLowerCase();

    // cancellate / scadute
    if (s == 'cancelled' ||
        s == 'canceled' ||
        s == 'cancelled_by_user' ||
        s == 'cancelled_by_partner' ||
        s == 'expired') {
      return 'cancelled';
    }

    // rifiutata dal partner: vogliamo mantenerla distinta
    if (s == 'rejected') return 'rejected';

    // derivati dagli effettivi
    if (pickupEffectiveAt != null) return 'completed';
    if (dropoffEffectiveAt != null) return 'in_store';

    return s; // pending / confirmed
  }

  bool get isInStore => uiStatus == 'in_store';
  bool get isCompleted => uiStatus == 'completed';

  /// Helper per combinare data + stringa ora "HH:MM[:SS]"
  static DateTime _combineDateAndTime(DateTime date, String timeStr) {
    if (timeStr.isEmpty) {
      return DateTime(date.year, date.month, date.day);
    }

    final parts = timeStr.split(':');
    int hour = 0;
    int minute = 0;
    int second = 0;

    if (parts.isNotEmpty) {
      hour = int.tryParse(parts[0]) ?? 0;
    }
    if (parts.length > 1) {
      minute = int.tryParse(parts[1]) ?? 0;
    }
    if (parts.length > 2) {
      second = int.tryParse(parts[2]) ?? 0;
    }

    return DateTime(date.year, date.month, date.day, hour, minute, second);
  }

  bool get isLateFeePending => lateFeeRequired && lateFeePaidAt == null;

  // ---------- FROM / TO MAP ----------

  factory PartnerBooking.fromMap(Map<String, dynamic> map) {
    DateTime? parseDateTime(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v.toLocal();
      if (v is String) return DateTime.parse(v).toLocal();
      throw ArgumentError('Invalid DateTime value: $v');
    }

    DateTime parseDate(dynamic v) {
      if (v is DateTime) {
        // Normalizzo a mezzanotte per sicurezza
        return DateTime(v.year, v.month, v.day);
      }
      if (v is String) {
        // Può essere 'YYYY-MM-DD' o ISO completo
        final dt = DateTime.parse(v);
        return DateTime(dt.year, dt.month, dt.day);
      }
      throw ArgumentError('Invalid Date value: $v');
    }

    String parseTime(dynamic v, {String fallback = '00:00:00'}) {
      if (v == null) return fallback;
      if (v is String) return v;
      return v.toString();
    }

    return PartnerBooking(
      id: map['id'] as String,
      partnerId: map['partner_id'] as String,
      userId: map['user_id'] as String,
      status: (map['status'] as String?) ?? 'confirmed',
      rejectReason: map['reject_reason'] as String?,
      rejectedAt: parseDateTime(map['rejected_at']),
      firstName: (map['contact_first_name'] as String?) ?? '',
      lastName: (map['contact_last_name'] as String?) ?? '',
      phone: (map['contact_phone'] as String?) ?? '',
      email: (map['contact_email'] as String?) ?? '',
      bagsS: (map['bags_s'] as int?) ?? 0,
      bagsM: (map['bags_m'] as int?) ?? 0,
      bagsL: (map['bags_l'] as int?) ?? 0,
      notes: map['notes'] as String?,
      createdAt: parseDateTime(map['created_at']) ?? DateTime.now().toLocal(),
      updatedAt: parseDateTime(map['updated_at']) ?? DateTime.now().toLocal(),
      bookingDate: parseDate(map['booking_date']),
      endDate: map['end_date'] != null ? parseDate(map['end_date']) : null,
      startTime: parseTime(map['start_time'], fallback: '00:00:00'),
      endTime: parseTime(map['end_time'], fallback: '23:59:00'),
      endDateRequested: map['end_date_requested'] != null
          ? parseDate(map['end_date_requested'])
          : null,
      endTimeRequested: map['end_time_requested'] != null
          ? parseTime(map['end_time_requested'], fallback: '')
          : null,
      bookingCode: (map['booking_code'] as String?) ?? '',
      dropoffPlannedAt: parseDateTime(map['dropoff_planned_at']),
      pickupPlannedAt: parseDateTime(map['pickup_planned_at']),
      dropoffEffectiveAt: parseDateTime(map['dropoff_effective_at']),
      pickupEffectiveAt: parseDateTime(map['pickup_effective_at']),
      lateFeeRequired: (map['late_fee_required'] as bool?) ?? false,
      lateFeeAmountCents: map['late_fee_amount_cents'] as int?,
      lateFeePaidAt: parseDateTime(map['late_fee_paid_at']),
      coveredUntil: parseDateTime(map['covered_until']),
      totalPaidCents: (map['total_paid_cents'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'partner_id': partnerId,
      'user_id': userId,
      'status': status,
      'reject_reason': rejectReason,
      'rejected_at': rejectedAt?.toUtc().toIso8601String(),
      'contact_first_name': firstName,
      'contact_last_name': lastName,
      'contact_phone': phone,
      'contact_email': email,
      'bags_s': bagsS,
      'bags_m': bagsM,
      'bags_l': bagsL,
      'notes': notes,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'booking_date': DateTime(
        bookingDate.year,
        bookingDate.month,
        bookingDate.day,
      ).toIso8601String(),
      'end_date': endDate != null
          ? DateTime(
              endDate!.year,
              endDate!.month,
              endDate!.day,
            ).toIso8601String()
          : null,
      'start_time': startTime,
      'end_time': endTime,
      'end_date_requested': endDateRequested != null
          ? DateTime(
              endDateRequested!.year,
              endDateRequested!.month,
              endDateRequested!.day,
            ).toIso8601String()
          : null,
      'end_time_requested': endTimeRequested,
      'booking_code': bookingCode,
      'dropoff_planned_at': dropoffPlannedAt?.toUtc().toIso8601String(),
      'pickup_planned_at': pickupPlannedAt?.toUtc().toIso8601String(),
      'dropoff_effective_at': dropoffEffectiveAt?.toUtc().toIso8601String(),
      'pickup_effective_at': pickupEffectiveAt?.toUtc().toIso8601String(),
      'late_fee_required': lateFeeRequired,
      'late_fee_amount_cents': lateFeeAmountCents,
      'late_fee_paid_at': lateFeePaidAt?.toUtc().toIso8601String(),
      'covered_until': coveredUntil?.toUtc().toIso8601String(),
      'total_paid_cents': totalPaidCents,
    };
  }
}
