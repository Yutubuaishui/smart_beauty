import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

/// Handles Firebase Authentication. UI calls this service only.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _usersCollection = 'users';

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Creates Firebase user and Firestore doc with role "user".
  Future<void> signUp({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) throw Exception('Account created but user is null');

    await _firestore.collection(_usersCollection).doc(user.uid).set({
      'fullName': fullName.trim(),
      'email': email.trim(),
      'role': 'user',
    });
  }

  /// Signs in with email and password.
  Future<void> login({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Signs out.
  Future<void> logout() async {
    await _auth.signOut();
  }

  /// Returns current user's Firestore data as [AppUser], or null if not found.
  Future<AppUser?> getCurrentAppUser() async {
    final user = currentUser;
    if (user == null) return null;
    final doc = await _firestore.collection(_usersCollection).doc(user.uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return AppUser.fromMap(user.uid, doc.data()!);
  }
}
