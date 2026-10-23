import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_service.dart';
import 'app_theme.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.resendToken,
  });

  final String phoneNumber;
  final String verificationId;
  final int? resendToken;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const int _resendSeconds = 30;

  final _auth = AuthService.instance;
  final _otpCtrl = TextEditingController();

  late String _verificationId = widget.verificationId;
  late int? _resendToken = widget.resendToken;

  Timer? _timer;
  int _secondsLeft = _resendSeconds;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
      }
      if (mounted) setState(() => _secondsLeft--);
    });
  }

  void _showMessage(String message, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ));
  }

  Future<void> _verify() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) {
      _showMessage('Enter the 6-digit code');
      return;
    }
    setState(() => _loading = true);
    try {
      await _auth.verifyOtp(_verificationId, code);
      if (!mounted) return;
      // Pop back to the root; AuthGate will now show the Home screen.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      _showMessage(AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _loading = true);
    try {
      await _auth.sendOtp(
        phoneNumber: widget.phoneNumber,
        resendToken: _resendToken,
        onCodeSent: (id, token) {
          _verificationId = id;
          _resendToken = token;
          if (mounted) setState(() => _loading = false);
          _startTimer();
          _showMessage('A new code has been sent', error: false);
        },
        onError: (e) {
          if (mounted) setState(() => _loading = false);
          _showMessage(AuthService.friendlyError(e));
        },
        onAutoVerified: () {
          if (!mounted) return;
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      );
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      _showMessage('Could not resend the code. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ResponsiveAuthShell(
      showBackButton: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.sms_outlined,
                size: 44,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Verify your number',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the 6-digit code sent to\n${widget.phoneNumber}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _otpCtrl,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofillHints: const [AutofillHints.oneTimeCode],
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 14,
              color: AppTheme.textPrimary,
            ),
            decoration: const InputDecoration(
              counterText: '',
              hintText: '••••••',
            ),
            onChanged: (v) {
              if (v.length == 6 && !_loading) _verify();
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : _verify,
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text('Verify & Continue'),
          ),
          const SizedBox(height: 16),
          Center(
            child: _secondsLeft > 0
                ? Text(
                    'Resend code in 0:${_secondsLeft.toString().padLeft(2, '0')}',
                    style: theme.textTheme.bodyMedium,
                  )
                : TextButton.icon(
                    onPressed: _loading ? null : _resend,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Resend code'),
                  ),
          ),
        ],
      ),
    );
  }
}
