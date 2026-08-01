import 'dart:async';

import 'package:flutter/material.dart';
import 'package:karaok_app/app/app_shell.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/core/storage/guest_assessment_store.dart';
import 'package:karaok_app/features/account/presentation/pages/change_password_screen.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';

/// Resolves persisted authentication before any account-dependent UI is built.
class SessionBootstrapScreen extends StatefulWidget {
  const SessionBootstrapScreen({super.key, this.authApi});

  final AuthApi? authApi;

  @override
  State<SessionBootstrapScreen> createState() => _SessionBootstrapScreenState();
}

class _SessionBootstrapScreenState extends State<SessionBootstrapScreen> {
  Widget? _destination;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final session = UserSession.instance;
    if (session.isLoggedIn) {
      if (!session.isGuest) {
        unawaited(_clearGuestReports());
      }
      _finishWithCurrentSession();
      return;
    }

    if (mounted) {
      setState(() {
        _destination = null;
        _error = null;
      });
    }

    try {
      final user = await (widget.authApi ?? AuthApi()).restoreSession();
      if (user == null) {
        session.setGuest('user');
      } else {
        session.setUserFromMap(user);
        unawaited(_clearGuestReports());
      }
      if (!mounted) return;
      _finishWithCurrentSession();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'KaraOK could not reconnect to restore your account. Your saved session has not been removed.';
      });
    }
  }

  Future<void> _clearGuestReports() async {
    try {
      await GuestAssessmentStore.instance.clearAll();
    } catch (_) {
      // Retry on a later authenticated startup.
    }
  }

  void _finishWithCurrentSession() {
    if (!mounted) return;
    final session = UserSession.instance;
    setState(() {
      _destination = session.requiresPasswordChange
          ? const ChangePasswordScreen(forceChange: true)
          : const AppShell();
      _error = null;
    });
  }

  void _continueAsGuest() {
    UserSession.instance.setGuest('user');
    _finishWithCurrentSession();
  }

  @override
  Widget build(BuildContext context) {
    if (_destination case final destination?) return destination;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: _error == null
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF4A90D9)),
                      SizedBox(height: 18),
                      Text(
                        'Restoring your session…',
                        style: TextStyle(color: Color(0xFFCCCCCC)),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_outlined,
                        color: Color(0xFFFFB74D),
                        size: 48,
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Could not restore your session',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFAAAAAA),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _restore,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _continueAsGuest,
                        child: const Text('Continue as Guest'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
