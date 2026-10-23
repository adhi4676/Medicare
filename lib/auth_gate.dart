import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'app_theme.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Decides what to show on launch:
///  - signed out                      -> LoginScreen
///  - signed in + biometric enabled   -> BiometricLockScreen, then Home
///  - signed in                       -> Home
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = AuthService.instance;
  bool _unlocked = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData) {
          _unlocked = false;
          return const LoginScreen();
        }

        return FutureBuilder<bool>(
          future: _auth.isBiometricEnabled(),
          builder: (context, bioSnap) {
            if (!bioSnap.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (bioSnap.data! && !_unlocked) {
              return BiometricLockScreen(
                onUnlocked: () => setState(() => _unlocked = true),
              );
            }
            return const HomeScreen();
          },
        );
      },
    );
  }
}

class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  final _auth = AuthService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    final ok = await _auth.authenticateWithBiometrics();
    if (ok && mounted) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ResponsiveAuthShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 56,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'MediCare is locked',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Use your fingerprint or face ID to securely access your medicines and prescriptions.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _unlock,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Unlock with Biometrics'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _auth.signOut,
            child: const Text('Sign in with a different account'),
          ),
        ],
      ),
    );
  }
}
