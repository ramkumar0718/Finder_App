import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth_lib;
import '../../services/api_service.dart';

class VerifyLinkScreen extends StatefulWidget {
  final String email;
  final String? username;
  final bool isEmailChange;
  final String? newEmail;

  const VerifyLinkScreen({
    super.key,
    required this.email,
    this.username,
    this.isEmailChange = false,
    this.newEmail,
  });

  @override
  State<VerifyLinkScreen> createState() => _VerifyLinkScreenState();
}

class _VerifyLinkScreenState extends State<VerifyLinkScreen> {
  final fb_auth_lib.FirebaseAuth _auth = fb_auth_lib.FirebaseAuth.instance;
  
  // Resend timer
  Timer? _resendTimer;
  int _remainingSeconds = 60;
  bool _canResend = false;
  
  // Status flags
  bool _isProcessing = false;
  bool _isDone = false;

  // Stream subscription for reactive auth state listening
  StreamSubscription<fb_auth_lib.User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    _startListening();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  /// Listens reactively to Firebase auth/token changes.
  /// This fires immediately when the user clicks the verification link in their email.
  void _startListening() {
    _authSubscription = _auth.idTokenChanges().listen((user) async {
      if (_isDone || !mounted) return;

      if (widget.isEmailChange) {
        // Case 1: Token revoked → Firebase logged the user out automatically
        // This happens when the email change is finalized.
        if (user == null) {
          print('[VerifyEmail] Auth sign-out detected → email change confirmed.');
          await _handleEmailChangeSuccess();
        }
        // Case 2: A new token arrived — check if it has the new email
        else if (user.email?.toLowerCase() == widget.newEmail?.toLowerCase()) {
          print('[VerifyEmail] New email detected in token: ${user.email}');
          await _handleEmailChangeSuccess();
        }
        // Case 3: New token but still old email — call backend as fallback
        else {
          print('[VerifyEmail] Token refreshed, email still old. Checking backend...');
          await _checkBackendForNewEmail();
        }
      } else {
        // Standard signup verification
        if (user != null && user.emailVerified) {
          print('[VerifyEmail] Email verified (signup flow).');
          await _handleSignupVerificationSuccess();
        }
      }
    });
  }

  /// Called after detecting the email change was successful in Firebase.
  Future<void> _handleEmailChangeSuccess() async {
    if (_isDone || !mounted) return;
    _isDone = true;
    _authSubscription?.cancel();

    if (!mounted) return;
    setState(() => _isProcessing = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Email changed successfully! Please log in with your new email.'),
        duration: Duration(seconds: 3),
      ),
    );

    // Sign out (in case not already signed out by Firebase)
    await _auth.signOut();

    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  /// Called after detecting new email in the backend (fallback for token propagation delay).
  Future<void> _checkBackendForNewEmail() async {
    if (_isDone || !mounted) return;

    try {
      final profile = await ApiService().fetchUserProfile(forceRefresh: true);
      if (!mounted) return;
      
      if (profile != null) {
        final backendEmail = profile['email'] as String?;
        print('[VerifyEmail] Backend email: $backendEmail, target: ${widget.newEmail}');
        if (backendEmail?.toLowerCase() == widget.newEmail?.toLowerCase()) {
          await _handleEmailChangeSuccess();
        }
      }
    } catch (e) {
      print('[VerifyEmail] Backend check error: $e');
    }
  }

  /// Called when standard account signup verification is detected.
  Future<void> _handleSignupVerificationSuccess() async {
    if (_isDone || !mounted) return;
    _isDone = true;
    _authSubscription?.cancel();

    setState(() => _isProcessing = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Email verified successfully!')),
    );

    final profile = await ApiService().fetchUserProfile(forceRefresh: true);

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (profile != null) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to sync profile. Please try logging in.')),
      );
    }
  }


  Future<void> _manualCheck() async {
    if (_isProcessing || _isDone) return;
    setState(() => _isProcessing = true);

    try {
      final user = _auth.currentUser;
      if (user == null) {
        // Already signed out → email change success
        await _handleEmailChangeSuccess();
        return;
      }

      // Force a token refresh. This will trigger idTokenChanges() listener above.
      await user.reload();
      await user.getIdToken(true);

      // Give the stream a moment to fire
      await Future.delayed(const Duration(milliseconds: 500));

      if (!_isDone && mounted) {
        // If we're still not done, show a hint
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email not yet verified. Please click the link in your inbox.')),
        );
      }
    } catch (e) {
      if (e.toString().contains('no longer valid') || e.toString().contains('must sign in again')) {
        await _handleEmailChangeSuccess();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted && !_isDone) setState(() => _isProcessing = false);
    }
  }

  void _startResendTimer() {
    setState(() {
      _canResend = false;
      _remainingSeconds = 60;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _resendVerificationEmail() async {
    if (!_canResend) return;
    try {
      final user = _auth.currentUser;
      if (user != null) {
        if (widget.isEmailChange && widget.newEmail != null) {
          await user.verifyBeforeUpdateEmail(widget.newEmail!);
        } else {
          await user.sendEmailVerification();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Verification email resent!')),
          );
          _startResendTimer();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resend email: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final emailToShow = widget.isEmailChange ? widget.newEmail! : widget.email;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        elevation: 0,
        title: const Text('Verify Email'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (widget.isEmailChange) {
              Navigator.pop(context);
            } else {
              _auth.signOut();
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.mark_email_read_outlined,
                  size: 100,
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 30),
                const Text(
                  'Verify Your Account',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'A verification link has been sent to:',
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  emailToShow,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Please click the link in the email to verify your account. Once done, you can click the button below or wait for us to automatically detect it.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _manualCheck,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline, size: 24),
                    label: Text(
                      _isProcessing ? 'Checking...' : 'I Have Verified',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 3,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _canResend
                          ? 'Didn\'t receive the email?'
                          : 'Resend available in ${_remainingSeconds}s',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _canResend ? _resendVerificationEmail : null,
                      child: Text(
                        'Resend',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _canResend ? Colors.blueAccent : Colors.grey[400],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                TextButton(
                  onPressed: () {
                    if (widget.isEmailChange) {
                      Navigator.pop(context);
                    } else {
                      _auth.signOut();
                      Navigator.pushNamedAndRemoveUntil(
                        context, '/', (route) => false,
                      );
                    }
                  },
                  child: Text(
                    widget.isEmailChange ? 'Cancel' : 'Cancel / Go to Login',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
