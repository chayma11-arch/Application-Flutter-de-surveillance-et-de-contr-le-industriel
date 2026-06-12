import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static Future<void>? _googleSignInInitialization;

  static Future<void> _initializeGoogleSignIn() {
    return _googleSignInInitialization ??= GoogleSignIn.instance.initialize();
  }

  // CURRENT USER
  static User? get currentUser => _auth.currentUser;

  // USER NAME
  static String get currentUserName {
    final user = _auth.currentUser;
    return user?.displayName ?? user?.email ?? "User";
  }

  // SIGNUP
  static Future<String?> signup(
    String name,
    String email,
    String password,
  ) async {
    try {
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);

      await userCredential.user?.updateDisplayName(name);
      await _auth.currentUser?.reload();

      if (_auth.currentUser == null) {
        return "User not created properly";
      }

      return null;
    } on FirebaseAuthException catch (e) {
      return e.code;
    } catch (e) {
      return e.toString();
    }
  }

  // LOGIN
  static Future<String?> login(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? "Login error";
    } catch (e) {
      return "Login failed";
    }
  }

  // GOOGLE SIGN-IN
  static Future<String?> googleSignIn() async {
    try {
      await _initializeGoogleSignIn();

      // Se deconnecter d'abord.
      await GoogleSignIn.instance.signOut();

      // Se connecter.
      final GoogleSignInAccount googleUser = await GoogleSignIn.instance
          .authenticate();

      // Obtenir l'authentification.
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      // Creer le credential.
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      // Se connecter a Firebase.
      await _auth.signInWithCredential(credential);

      return null;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return "cancelled";
      }
      debugPrint("GOOGLE ERROR: $e");
      return e.description ?? e.code.name;
    } catch (e) {
      debugPrint("GOOGLE ERROR: $e");
      return e.toString();
    }
  }

  // LOGOUT
  static Future<void> logout() async {
    await _auth.signOut();
    await _initializeGoogleSignIn();
    await GoogleSignIn.instance.signOut();
  }

  // RESET PASSWORD
  static Future<String?> resetPassword(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return "Error sending reset email";
    }
  }
}
