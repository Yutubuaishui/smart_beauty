import 'package:cloud_firestore/cloud_firestore.dart';

/// Resolves user role from Firestore. UI calls this service only.
class RoleService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _usersCollection = 'users';

  /// Returns "user" or "admin" for the given [uid]. Defaults to "user" if doc missing.
  Future<String> getUserRole(String uid) async {
    final doc = await _firestore.collection(_usersCollection).doc(uid).get();
    if (!doc.exists || doc.data() == null) return 'user';
    final role = doc.data()!['role'] as String?;
    if (role == 'admin') return 'admin';
    return 'user';
  }
}
