/// Modello dati del profilo utente (tabella: public.user_profiles)
class UserProfile {
  final String id;           // UUID utente (auth.users.id) - chiave primaria
  final DateTime? createdAt; // timestamp creazione
  final String? fullName;    // nome completo
  final String? avatarUrl;   // URL avatar
  final String kycStatus;    // 'none' | 'basic' | 'verified'
  final String role;         // 'user' | 'partner' | 'admin'

  const UserProfile({
    required this.id,
    this.createdAt,
    this.fullName,
    this.avatarUrl,
    this.kycStatus = 'none',
    this.role = 'user',
  });

factory UserProfile.fromMap(Map<String, dynamic> map) {
  DateTime? parseDateTime(dynamic v) {
    if (v == null) return null;

    if (v is DateTime) {
      // Normalizza sempre all'orario locale del device
      return v.toLocal();
    }

    if (v is String) {
      // Gestisce sia 'YYYY-MM-DD' che ISO con timezone
      return DateTime.parse(v).toLocal();
    }

    return null;
  }

  return UserProfile(
    id: map['id'] as String,
    createdAt: parseDateTime(map['created_at']),
    fullName: map['full_name'] as String?,
    avatarUrl: map['avatar_url'] as String?,
    kycStatus: (map['kyc_status'] as String?) ?? 'none',
    role: (map['role'] as String?) ?? 'user',
  );
}


  Map<String, dynamic> toMap() {
    return {
      'id': id,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      'full_name': fullName,
      'avatar_url': avatarUrl,
      'kyc_status': kycStatus,
      'role': role,
    };
  }

  UserProfile copyWith({
    String? fullName,
    String? avatarUrl,
    String? kycStatus,
    String? role,
  }) {
    return UserProfile(
      id: id,
      createdAt: createdAt,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      kycStatus: kycStatus ?? this.kycStatus,
      role: role ?? this.role,
    );
  }

  bool get isUser    => role == 'user';
  bool get isPartner => role == 'partner';
  bool get isAdmin   => role == 'admin';
}
