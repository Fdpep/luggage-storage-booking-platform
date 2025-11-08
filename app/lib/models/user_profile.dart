//A cosa serve user_profile.dart e perché in models/?
//
//È il modello dati del profilo: una classe Dart con campi tipizzati (id, createdAt, fullName, ecc.).
//
//In models/ perché è il posto “canonico” per i domain models (entity/DTO) dell’app.
//
//Vantaggi:
//
//autocomplete e controlli statici del compilatore
//
//meno errori di battitura sui nomi colonne
//
//conversioni centralizzate fromMap() / toMap()
//
//separa i dettagli di storage (Supabase) dalla logica applicativa



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
    return UserProfile(
      id: map['id'] as String,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'] as String),
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
}
