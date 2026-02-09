/// App user model matching Firestore users collection.
class AppUser {
  final String uid;
  final String fullName;
  final String email;
  final String role;

  const AppUser({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.role,
  });

  bool get isAdmin => role == 'admin';
  bool get isUser => role == 'user';

  Map<String, dynamic> toMap() {
    return {
      'fullName': fullName,
      'email': email,
      'role': role,
    };
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      fullName: map['fullName'] as String? ?? '',
      email: map['email'] as String? ?? '',
      role: map['role'] as String? ?? 'user',
    );
  }
}
