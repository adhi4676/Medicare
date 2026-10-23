import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'app_theme.dart';
import 'mongodb_service.dart';

/// Wraps Firebase Auth (registration, email/password login, phone OTP,
/// persistent session stream, and sign-out) plus device biometrics.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _biometricKey = 'biometric_enabled';

  String? _cachedPhoneNumber;
  String? get userPhoneNumber =>
      _auth.currentUser?.phoneNumber ?? _cachedPhoneNumber;

  /// Emits whenever the user signs in, signs out, or updates their profile
  /// (such as displayName on registration), and automatically restores the
  /// persisted session when the app restarts.
  Stream<User?> get authStateChanges => _auth.userChanges();
  User? get currentUser => _auth.currentUser;

  // ---------------------------------------------------------------------------
  // Email + password registration & login
  // ---------------------------------------------------------------------------
  Future<UserCredential> signUpWithEmail({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    final formattedPhone =
        phone.trim().startsWith('+') ? phone.trim() : '+91 ${phone.trim()}';
    _cachedPhoneNumber = formattedPhone;

    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await cred.user?.updateDisplayName(name.trim());
    await cred.user?.reload();

    // Save user profile (including phone number) to Firebase Cloud Firestore and MongoDB Atlas
    final uid = cred.user?.uid;
    if (uid != null) {
      final userData = {
        'uid': uid,
        'name': name.trim(),
        'phone': formattedPhone,
        'email': email.trim(),
        'createdAt': DateTime.now().toIso8601String(),
      };

      try {
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'name': name.trim(),
          'phone': formattedPhone,
          'email': email.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('Firestore user profile sync note: $e');
      }

      try {
        await MongoDbService.instance.saveUser(userData);
      } catch (e) {
        debugPrint('MongoDB user profile sync note: $e');
      }
    }

    return cred;
  }

  Future<UserCredential> signInWithEmail(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user;
    if (user != null) {
      final userData = {
        'uid': user.uid,
        'name': user.displayName ?? '',
        'email': user.email ?? email.trim(),
        'phone': user.phoneNumber ?? '',
        'lastLogin': DateTime.now().toIso8601String(),
      };
      MongoDbService.instance.saveUser(userData).catchError((_) => false);
    }
    return cred;
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  // ---------------------------------------------------------------------------
  // Phone + OTP
  // ---------------------------------------------------------------------------

  /// Sends an OTP to [phoneNumber] (E.164 format, e.g. +919876543210).
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(FirebaseAuthException e) onError,
    void Function()? onAutoVerified,
    int? resendToken,
  }) {
    return _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      forceResendingToken: resendToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await _auth.signInWithCredential(credential);
          onAutoVerified?.call();
        } on FirebaseAuthException catch (e) {
          onError(e);
        }
      },
      verificationFailed: onError,
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<UserCredential> verifyOtp(String verificationId, String smsCode) {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _auth.signInWithCredential(credential);
  }

  // ---------------------------------------------------------------------------
  // Biometrics (device unlock for an existing Firebase session)
  // ---------------------------------------------------------------------------
  Future<bool> isBiometricAvailable() async {
    if (kIsWeb) return false;
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isBiometricEnabled() async {
    if (kIsWeb) return false;
    try {
      return (await _storage.read(key: _biometricKey)) == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    if (kIsWeb) return;
    try {
      await _storage.write(key: _biometricKey, value: enabled.toString());
    } catch (_) {}
  }

  Future<bool> authenticateWithBiometrics() async {
    if (kIsWeb) return true;
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock MediCare to access your medicines',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  Future<void> signOut() => _auth.signOut();

  Future<void> updatePassword(String newPassword) async {
    final err = validateStrongPassword(newPassword);
    if (err != null) {
      throw FirebaseAuthException(code: 'weak-password', message: err);
    }
    await _auth.currentUser?.updatePassword(newPassword);
  }

  // ---------------------------------------------------------------------------
  // Strong Password Evaluation & Validation
  // ---------------------------------------------------------------------------
  static PasswordStrengthInfo evaluatePassword(String password) {
    final hasMinLength = password.length >= 8;
    final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
    final hasLowercase = RegExp(r'[a-z]').hasMatch(password);
    final hasDigit = RegExp(r'[0-9]').hasMatch(password);
    final hasSpecial =
        RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=/\\[\];~`]').hasMatch(password);

    return PasswordStrengthInfo(
      hasMinLength: hasMinLength,
      hasUppercase: hasUppercase,
      hasLowercase: hasLowercase,
      hasDigit: hasDigit,
      hasSpecial: hasSpecial,
    );
  }

  /// Validates that [value] is a strong password meeting all 5 criteria.
  static String? validateStrongPassword(String? value) {
    final pwd = value ?? '';
    if (pwd.isEmpty) return 'Enter a password';
    final info = evaluatePassword(pwd);
    if (!info.hasMinLength) {
      return 'Password must be at least 8 characters long';
    }
    if (!info.hasUppercase) {
      return 'Include at least 1 uppercase letter (A–Z)';
    }
    if (!info.hasLowercase) {
      return 'Include at least 1 lowercase letter (a–z)';
    }
    if (!info.hasDigit) {
      return 'Include at least 1 number (0–9)';
    }
    if (!info.hasSpecial) {
      return 'Include at least 1 special character (!@#\$%^&*)';
    }
    return null;
  }

  /// Turns Firebase error codes into clear, user-friendly messages.
  static String friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'weak-password':
        return 'Password is too weak. Use 8+ chars with uppercase, lowercase, number, and special symbol.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled in Firebase Console.';
      case 'user-not-found':
        return 'No account found with this email. Please create an account first.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password. Please check and try again.';
      case 'user-disabled':
        return 'This account has been disabled by an administrator.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please wait a moment and try again.';
      case 'invalid-phone-number':
        return 'Please enter a valid 10-digit mobile number.';
      case 'invalid-verification-code':
        return 'The 6-digit OTP code you entered is incorrect.';
      case 'session-expired':
        return 'The OTP code has expired. Please tap Resend Code.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }
}

class PasswordStrengthInfo {
  const PasswordStrengthInfo({
    required this.hasMinLength,
    required this.hasUppercase,
    required this.hasLowercase,
    required this.hasDigit,
    required this.hasSpecial,
  });

  final bool hasMinLength;
  final bool hasUppercase;
  final bool hasLowercase;
  final bool hasDigit;
  final bool hasSpecial;

  int get score =>
      (hasMinLength ? 1 : 0) +
      (hasUppercase ? 1 : 0) +
      (hasLowercase ? 1 : 0) +
      (hasDigit ? 1 : 0) +
      (hasSpecial ? 1 : 0);

  double get fraction => score / 5.0;
  bool get isStrong => score == 5;

  String get label {
    if (score == 0) return 'Enter Password';
    if (score <= 2) return 'Weak Password';
    if (score == 3) return 'Fair Password';
    if (score == 4) return 'Good Password';
    return 'Strong Password ✓';
  }

  Color get color {
    if (score <= 2) return Colors.redAccent;
    if (score == 3) return AppTheme.accentOrange;
    if (score == 4) return AppTheme.primary;
    return AppTheme.accentGreen;
  }
}

/// Interactive password strength bar + live 5-rule checklist widget.
class PasswordStrengthIndicator extends StatelessWidget {
  const PasswordStrengthIndicator({
    super.key,
    required this.password,
    this.showChecklist = true,
  });

  final String password;
  final bool showChecklist;

  @override
  Widget build(BuildContext context) {
    final info = AuthService.evaluatePassword(password);
    final theme = Theme.of(context);
    final isDark = AppTheme.isDark(context);

    final rules = <(String, bool)>[
      ('8+ chars', info.hasMinLength),
      ('Uppercase (A-Z)', info.hasUppercase),
      ('Lowercase (a-z)', info.hasLowercase),
      ('Number (0-9)', info.hasDigit),
      ('Special (!@#\$)', info.hasSpecial),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.darkSurfaceElevated.withValues(alpha: 0.65)
            : AppTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: password.isEmpty
              ? theme.dividerColor
              : info.color.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    info.isStrong
                        ? Icons.verified_user_rounded
                        : Icons.shield_outlined,
                    size: 16,
                    color: password.isEmpty
                        ? theme.textTheme.bodyMedium?.color
                        : info.color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    password.isEmpty ? 'Password Strength' : info.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: password.isEmpty
                          ? theme.textTheme.bodyMedium?.color
                          : info.color,
                    ),
                  ),
                ],
              ),
              Text(
                '${info.score}/5 rules',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: password.isEmpty ? 0.0 : info.fraction,
              minHeight: 6,
              color: info.color,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          if (showChecklist) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: rules.map((r) {
                final passed = r.$2;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: passed
                        ? AppTheme.accentGreen.withValues(alpha: 0.14)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.white),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: passed
                          ? AppTheme.accentGreen.withValues(alpha: 0.45)
                          : theme.dividerColor,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        passed
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 13,
                        color: passed
                            ? AppTheme.accentGreen
                            : theme.textTheme.bodyMedium?.color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        r.$1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              passed ? FontWeight.w700 : FontWeight.w500,
                          color: passed
                              ? AppTheme.accentGreen
                              : theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

