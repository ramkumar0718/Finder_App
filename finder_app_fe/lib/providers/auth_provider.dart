import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get currentUserUid => _auth.currentUser?.uid;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  // --- Auth Methods ---

  Future<void> signUp(String email, String password) async {
    _setLoading(true);
    _setError(null);
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      _setError(e.message);
    } catch (_) {
      _setError('An unexpected error occurred.');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> login(String email, String password) async {
    _setLoading(true);
    _setError(null);
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      _setError(e.message);
    } catch (_) {
      _setError('An unexpected error occurred.');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    _setLoading(true);
    _setError(null);
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError('An unexpected error occurred.');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    _setLoading(true);
    _setError(null);
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        throw Exception('User not logged in');
      }

      // Re-authenticate user with current password
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);

      // Now change the password
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') {
        _setError('Current password is incorrect. Please try again.');
      } else if (e.code == 'weak-password') {
        _setError(
          'New password is too weak. Please choose a stronger password.',
        );
      } else {
        _setError(e.message ?? 'Failed to change password');
      }
    } catch (e) {
      _setError('An unexpected error occurred.');
    } finally {
      _setLoading(false);
    }
  }

  // --- Social Sign-In Methods ---

  Future<void> signInWithGoogle() async {
    _setLoading(true);
    _setError(null);

    try {
      // Trigger the Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // User canceled the sign-in
        _setLoading(false);
        return;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      await _auth.signInWithCredential(credential);

      // Sync user data with backend
      await ApiService().syncGoogleUser(googleUser);
    } on FirebaseAuthException catch (e) {
      _setError(e.message ?? 'Google sign-in failed');
    } catch (e) {
      _setError('An error occurred during Google sign-in: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signInWithApple() async {
    _setLoading(true);
    _setError(null);

    try {
      // Check if Apple Sign-In is available (iOS 13+ or macOS 10.15+)
      final isAvailable = await SignInWithApple.isAvailable();

      if (!isAvailable) {
        _setError('Apple Sign-In is not available on this device');
        _setLoading(false);
        return;
      }

      // Request credential for the currently signed in Apple account
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      // Create an OAuthCredential from the credential returned by Apple
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      // Sign in to Firebase with the Apple credential
      await _auth.signInWithCredential(oauthCredential);

      // Sync user data with backend
      await ApiService().syncAppleUser(appleCredential);
    } on FirebaseAuthException catch (e) {
      _setError(e.message ?? 'Apple sign-in failed');
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        // User canceled the sign-in
        _setLoading(false);
        return;
      }
      _setError('Apple sign-in failed: ${e.message}');
    } catch (e) {
      _setError('An error occurred during Apple sign-in: $e');
    } finally {
      _setLoading(false);
    }
  }

  // --- OTP Methods (Django Backend) ---

  Future<bool> sendOTP(String email, {String? username}) async {
    _setLoading(true);
    _setError(null);

    final result = await ApiService().sendOTP(email, username: username);

    _setLoading(false);

    if (result['success']) {
      return true;
    } else {
      _setError(result['error']);
      return false;
    }
  }

  Future<bool> verifyOTP(String email, String otpCode) async {
    _setLoading(true);
    _setError(null);

    final result = await ApiService().verifyOTP(email, otpCode);

    _setLoading(false);

    if (result['success']) {
      return true;
    } else {
      _setError(result['error']);
      return false;
    }
  }

  Future<bool> resendOTP(String email) async {
    _setLoading(true);
    _setError(null);

    final result = await ApiService().resendOTP(email);

    _setLoading(false);

    if (result['success']) {
      return true;
    } else {
      _setError(result['error']);
      return false;
    }
  }
}
