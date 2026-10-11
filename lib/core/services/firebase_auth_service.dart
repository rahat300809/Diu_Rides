import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firebase Auth Service for DIU Rides
/// Provides Firebase email code sending, verification, and authentication.
class FirebaseAuthService {
  FirebaseAuthService._();
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Check current Firebase user
  static User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Send verification email code / link to student email
  static Future<bool> sendEmailVerification({required String email}) async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        debugPrint('[Firebase Auth] Verification email dispatched to $email');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[Firebase Auth] sendEmailVerification error: $e');
      return false;
    }
  }

  /// Sign up with email & password via Firebase
  static Future<UserCredential?> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (cred.user != null && !cred.user!.emailVerified) {
        await cred.user!.sendEmailVerification();
      }
      return cred;
    } catch (e) {
      debugPrint('[Firebase Auth] signUpWithEmail error: $e');
      return null;
    }
  }

  /// Sign in with email & password via Firebase
  static Future<UserCredential?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      debugPrint('[Firebase Auth] signInWithEmail error: $e');
      return null;
    }
  }

  /// Sign out
  static Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('[Firebase Auth] signOut error: $e');
    }
  }
}
