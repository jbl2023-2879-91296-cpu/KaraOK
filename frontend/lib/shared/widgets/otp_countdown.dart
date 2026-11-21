import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:karaok_app/core/security/auth_limits.dart';
import 'package:karaok_app/core/security/secure_token_store.dart';

class OtpChallenge {
  const OtpChallenge({
    required this.email,
    required this.challengeId,
    required this.expiresAt,
    required this.resendAvailableAt,
    required this.skewSeconds,
  });

  factory OtpChallenge.fromResponse(
    String email,
    Map<String, dynamic> json, {
    DateTime Function()? now,
  }) => OtpChallenge(
    email: email.trim().toLowerCase(),
    challengeId: json['challenge_id'] as String,
    expiresAt: json['expires_at'] as int,
    resendAvailableAt: json['resend_available_at'] as int,
    skewSeconds:
        (json['server_time'] as int) -
        (now ?? DateTime.now)().millisecondsSinceEpoch ~/ 1000,
  );

  final String email, challengeId;
  final int expiresAt, resendAvailableAt, skewSeconds;

  Duration untilExpiry(DateTime now) => _until(expiresAt, now);
  Duration untilResend(DateTime now) => _until(resendAvailableAt, now);
  Duration _until(int epoch, DateTime now) => Duration(
    seconds: (epoch - skewSeconds - now.millisecondsSinceEpoch ~/ 1000).clamp(
      0,
      86400,
    ),
  );

  static String _key(String purpose) => 'karaok_otp_$purpose';

  Future<void> save(String purpose) async {
    try {
      await SecureTokenStore.instance.writeAuthState(
        _key(purpose),
        jsonEncode({
          'email': email,
          'challenge_id': challengeId,
          'expires_at': expiresAt,
          'resend_available_at': resendAvailableAt,
          'skew': skewSeconds,
        }),
      );
    } catch (_) {
      // The challenge still works on the current screen.
    }
  }

  static Future<OtpChallenge?> restore(String purpose, String email) async {
    try {
      final raw = await SecureTokenStore.instance.readAuthState(_key(purpose));
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final challenge = OtpChallenge(
        email: json['email'] as String,
        challengeId: json['challenge_id'] as String,
        expiresAt: json['expires_at'] as int,
        resendAvailableAt: json['resend_available_at'] as int,
        skewSeconds: json['skew'] as int,
      );
      if (challenge.untilExpiry(DateTime.now()) == Duration.zero) {
        await clear(purpose);
        return null;
      }
      return challenge.email == email.trim().toLowerCase() ? challenge : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String purpose) async {
    try {
      await SecureTokenStore.instance.deleteAuthState(_key(purpose));
    } catch (_) {
      // A code consumed on the server cannot be used again.
    }
  }
}

class OtpCountdown extends StatefulWidget {
  const OtpCountdown({
    super.key,
    required this.challenge,
    required this.onResend,
    this.lockRemaining = Duration.zero,
    this.enabled = true,
    this.now = DateTime.now,
  });

  final OtpChallenge challenge;
  final Future<OtpChallenge?> Function() onResend;
  final Duration lockRemaining;
  final bool enabled;
  final DateTime Function() now;

  @override
  State<OtpCountdown> createState() => _OtpCountdownState();
}

class _OtpCountdownState extends State<OtpCountdown> {
  late OtpChallenge _challenge = widget.challenge;
  Timer? _timer;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void didUpdateWidget(OtpCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.challenge != oldWidget.challenge) _challenge = widget.challenge;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      final updated = await widget.onResend();
      if (updated != null && mounted) setState(() => _challenge = updated);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now();
    final expiry = _challenge.untilExpiry(now);
    final cooldown = _challenge.untilResend(now);
    final wait = cooldown > widget.lockRemaining
        ? cooldown
        : widget.lockRemaining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          expiry > Duration.zero
              ? 'Code expires in ${countdownLabel(expiry)}'
              : 'Code expired. Request a new code.',
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: widget.enabled && !_sending && wait == Duration.zero
              ? _resend
              : null,
          child: Text(
            wait > Duration.zero
                ? 'Resend code in ${countdownLabel(wait)}'
                : 'Resend code',
          ),
        ),
      ],
    );
  }
}
