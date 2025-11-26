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

  final DateTime createdAt;
  final DateTime updatedAt;

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
    this.notes,
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
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
