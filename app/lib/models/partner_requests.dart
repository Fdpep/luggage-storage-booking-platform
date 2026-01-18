/// Modello dati per public.partner_requests
class PartnerRequest {
  final String id;
  final String userId;
  final String partnerId;
  final String status; // 'draft' | 'submitted' | 'awaiting_payment' | 'paid' | 'rejected'
  final String? message;
  final String? adminNote;
  final String? rejectReason;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;   // auth.users.id admin
  final String? contractSignedUrl;
  final DateTime? contractSignedAt;


  PartnerRequest({
    required this.id,
    required this.userId,
    required this.partnerId,
    required this.status,
    required this.createdAt,
    this.message,
    this.adminNote,
    this.rejectReason,
    this.reviewedAt,
    this.reviewedBy,
    this.contractSignedUrl,
    this.contractSignedAt,
  });

  factory PartnerRequest.fromMap(Map<String, dynamic> map) {
    return PartnerRequest(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      partnerId: map['partner_id'] as String,
      status: map['status'] as String,
      message: map['message'] as String?,
      adminNote: map['admin_note'] as String?,
      rejectReason: map['reject_reason'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      reviewedAt: map['reviewed_at'] == null
          ? null
          : DateTime.tryParse(map['reviewed_at'] as String),
      reviewedBy: map['reviewed_by'] as String?,
      contractSignedUrl: map['contract_signed_url'] as String?,
      contractSignedAt: map['contract_signed_at'] == null
          ? null
          : DateTime.tryParse(map['contract_signed_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'partner_id': partnerId,
      'status': status,
      'message': message,
      'admin_note': adminNote,
      'reject_reason': rejectReason,
      'created_at': createdAt.toIso8601String(),
      'reviewed_at': reviewedAt?.toIso8601String(),
      'reviewed_by': reviewedBy,
      'contract_signed_url': contractSignedUrl,
      'contract_signed_at': contractSignedAt?.toIso8601String(),
    };
  }
}
