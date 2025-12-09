// lib/models/partner_booking.dart
class PartnerBooking {
  final String id;
  final String partnerId;
  final String userId;

  /// Stato logico della prenotazione:
  /// pending / confirmed / cancelled / completed
  final String status;

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
  final String endTime;   // 'HH:MM:SS' (o 'HH:MM')

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

  const PartnerBooking({
    required this.id,
    required this.partnerId,
    required this.userId,
    required this.status,
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
    this.dropoffPlannedAt,
    this.pickupPlannedAt,
    this.dropoffEffectiveAt,
    this.pickupEffectiveAt,
  });

  /// Numero totale di bagagli (S+M+L)
  int get totalBags => bagsS + bagsM + bagsL;

  /// Consegna prevista "sicura":
  /// - se dropoff_planned_at è valorizzato dal DB → lo usiamo
  /// - altrimenti combiniamo booking_date + start_time
  DateTime get plannedDropoffLocal {
    if (dropoffPlannedAt != null) return dropoffPlannedAt!;
    return _combineDateAndTime(bookingDate, startTime);
  }

  /// Ritiro previsto "sicuro":
  /// - se pickup_planned_at è valorizzato dal DB → lo usiamo
  /// - altrimenti combiniamo (end_date o booking_date) + end_time
  DateTime get plannedPickupLocal {
    if (pickupPlannedAt != null) return pickupPlannedAt!;
    final d = endDate ?? bookingDate;
    return _combineDateAndTime(d, endTime);
  }

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

    return DateTime(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
      second,
    );
  }

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
      firstName: (map['contact_first_name'] as String?) ?? '',
      lastName: (map['contact_last_name'] as String?) ?? '',
      phone: (map['contact_phone'] as String?) ?? '',
      email: (map['contact_email'] as String?) ?? '',
      bagsS: (map['bags_s'] as int?) ?? 0,
      bagsM: (map['bags_m'] as int?) ?? 0,
      bagsL: (map['bags_l'] as int?) ?? 0,
      notes: map['notes'] as String?,
      createdAt:
          parseDateTime(map['created_at']) ?? DateTime.now().toLocal(),
      updatedAt:
          parseDateTime(map['updated_at']) ?? DateTime.now().toLocal(),
      bookingDate: parseDate(map['booking_date']),
      endDate: map['end_date'] != null ? parseDate(map['end_date']) : null,
      startTime: parseTime(map['start_time'], fallback: '00:00:00'),
      endTime: parseTime(map['end_time'], fallback: '23:59:00'),
      dropoffPlannedAt: parseDateTime(map['dropoff_planned_at']),
      pickupPlannedAt: parseDateTime(map['pickup_planned_at']),
      dropoffEffectiveAt: parseDateTime(map['dropoff_effective_at']),
      pickupEffectiveAt: parseDateTime(map['pickup_effective_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'partner_id': partnerId,
      'user_id': userId,
      'status': status,
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
      'booking_date':
          DateTime(bookingDate.year, bookingDate.month, bookingDate.day)
              .toIso8601String(),
      'end_date': endDate != null
          ? DateTime(endDate!.year, endDate!.month, endDate!.day)
              .toIso8601String()
          : null,
      'start_time': startTime,
      'end_time': endTime,
      'dropoff_planned_at':
          dropoffPlannedAt?.toUtc().toIso8601String(),
      'pickup_planned_at':
          pickupPlannedAt?.toUtc().toIso8601String(),
      'dropoff_effective_at':
          dropoffEffectiveAt?.toUtc().toIso8601String(),
      'pickup_effective_at':
          pickupEffectiveAt?.toUtc().toIso8601String(),
    };
  }
}
