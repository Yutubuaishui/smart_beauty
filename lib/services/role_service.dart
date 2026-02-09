import 'package:cloud_firestore/cloud_firestore.dart';

/// Resolves user role from Firestore. UI calls this service only.
class RoleService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _usersCollection = 'users';

  /// Returns "user" or "admin" for the given [uid]. Defaults to "user" if doc missing.
  Future<String> getUserRole(String uid) async {
  try {
    final doc = await _firestore.collection(_usersCollection).doc(uid).get();
    
    // Check if document exists and has data
    if (!doc.exists || doc.data() == null) {
      return 'user'; // Default for new sign-ups
    }

    // Safely extract role, defaulting to 'user' if the field is missing
    final data = doc.data()!;
    return data['role'] as String? ?? 'user';
    
  } catch (e) {
    print("Error fetching role: $e");
    return 'user'; // Fallback if anything goes wrong (network, permissions, etc.)
  }
}
}
