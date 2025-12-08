// Modello per prenotazioni del partner
class PartnerBooking {
  final String id;
  final String partnerId;
  final String userId;
  final String status;

  final String firstName;
  final String lastName;
  final String phone;
  final String email;

  final int bagsS;
  final int bagsM;
  final int bagsL;
  final String? notes;

  /// Nuovi campi per data + orari della prenotazione
  final DateTime bookingDate; // solo data (00:00)
  final String startTime; // "HH:MM:SS" (come arriva da Supabase)
  final String endTime; // "HH:MM:SS"

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? endDate;

  PartnerBooking({
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
    required this.createdAt,
    required this.updatedAt,
    required this.bookingDate,
    required this.startTime,
    required this.endTime,
    this.notes,
    this.endDate,
  });

  factory PartnerBooking.fromMap(Map<String, dynamic> map) {
    return PartnerBooking(
      id: map['id'] as String,
      partnerId: map['partner_id'] as String,
      userId: map['user_id'] as String,
      status: map['status'] as String,
      firstName: map['contact_first_name'] as String,
      lastName: map['contact_last_name'] as String,
      phone: map['contact_phone'] as String,
      email: map['contact_email'] as String,
      bagsS: map['bags_s'] as int,
      bagsM: map['bags_m'] as int,
      bagsL: map['bags_l'] as int,
      notes: map['notes'] as String?,

      // nuovi campi:
      bookingDate: DateTime.parse(map['booking_date'] as String),
      endDate: map['end_date'] == null
          ? null
          : DateTime.parse(map['end_date'] as String),
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String,

      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
