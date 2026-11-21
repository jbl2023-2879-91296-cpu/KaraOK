import 'package:flutter/material.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:karaok_app/core/security/password_policy.dart';
import 'package:karaok_app/core/security/submit_guard.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/shared/widgets/app_widgets.dart';
import 'package:karaok_app/shared/widgets/form_feedback.dart';
import 'package:karaok_app/shared/widgets/otp_countdown.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.challenge, this.authApi});

  final OtpChallenge challenge;
  final AuthApi? authApi;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen>
    with GuardedSubmit<ResetPasswordScreen> {
  @override
  Iterable<String> get submitActions => const ['forgot_resend', 'forgot_reset'];

  late OtpChallenge _challenge = widget.challenge;
  final _form = GlobalKey<FormState>();
  final _feedback = FormFeedback();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  AuthApi get _api => widget.authApi ?? AuthApi();

  @override
  void dispose() {
    _feedback.dispose();
    _code.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (_loading || guard('forgot_reset').isLocked) return;
    setState(_feedback.clear);
    if (!_form.currentState!.validate()) {
      _feedback.reveal();
      return;
    }
    final code = _code.text.trim();
    final password = _password.text;
    setState(() => _loading = true);
    try {
      if (await guard('forgot_reset').recordAttempt() != null || !mounted) {
        return;
      }
      await _api.resetPassword(
        email: _challenge.email,
        challengeId: _challenge.challengeId,
        code: code,
        newPassword: password,
      );
      await OtpChallenge.clear('password_reset');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated. Sign in with your new password.'),
        ),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(initialIdentifier: _challenge.email),
        ),
        (_) => false,
      );
    } on ApiException catch (error) {
      await applyRetryAfter('forgot_reset', error);
      if (!mounted) return;
      setState(() => _feedback.receive(error));
      _feedback.reveal();
    } catch (_) {
      if (mounted) {
        setState(() => _feedback.banner = 'Could not connect to the server.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<OtpChallenge?> _resend() async {
    if (_loading) return null;
    setState(() {
      _loading = true;
      _feedback.clear();
    });
    try {
      if (await guard('forgot_resend').recordAttempt() != null || !mounted) {
        return null;
      }
      final data = await _api.resendPasswordReset(
        email: _challenge.email,
        challengeId: _challenge.challengeId,
      );
      final active = OtpChallenge.fromResponse(_challenge.email, data);
      await active.save('password_reset');
      if (mounted) {
        setState(() {
          _challenge = active;
          _code.clear();
        });
      }
      return active;
    } on ApiException catch (error) {
      await applyRetryAfter('forgot_resend', error);
      if (mounted) setState(() => _feedback.banner = error.message);
      return null;
    } catch (_) {
      if (mounted) {
        setState(() => _feedback.banner = 'Could not resend the code.');
      }
      return null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPageScaffold(
    title: 'Reset password',
    maxContentWidth: 480,
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_feedback.banner case final banner?)
            FormErrorBanner(message: banner, onRetry: _loading ? null : _reset),
          AppSectionHeader(
            title: 'Choose a new password',
            subtitle:
                'If an account exists for ${_challenge.email}, a reset code was sent.',
          ),
          AppFormField(
            fieldKey: _feedback.key('code'),
            focusNode: _feedback.focus('code'),
            label: 'Reset code',
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            errorText: _feedback.errors['code'],
            onChanged: (_) => setState(() => _feedback.errors.remove('code')),
            validator: (value) =>
                RegExp(r'^[0-9]{6}$').hasMatch(value?.trim() ?? '')
                ? null
                : 'Enter the 6-digit code from your email.',
          ),
          OtpCountdown(
            challenge: _challenge,
            onResend: _resend,
            enabled: !_loading,
            lockRemaining: guard('forgot_resend').remaining,
          ),
          AppFormField(
            fieldKey: _feedback.key('new_password'),
            focusNode: _feedback.focus('new_password'),
            label: 'New password',
            controller: _password,
            obscure: _obscure,
            maxLength: PasswordPolicy.maximumLength,
            validator: PasswordPolicy.validate,
            errorText: _feedback.errors['new_password'],
            onChanged: (_) =>
                setState(() => _feedback.errors.remove('new_password')),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show passwords' : 'Hide passwords',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
            ),
          ),
          PasswordChecklist(controller: _password),
          AppFormField(
            fieldKey: _feedback.key('confirm_password'),
            focusNode: _feedback.focus('confirm_password'),
            label: 'Confirm new password',
            controller: _confirmation,
            obscure: _obscure,
            validator: (value) => (value?.isEmpty ?? true)
                ? 'Confirm your password.'
                : value != _password.text
                ? 'Passwords must match.'
                : null,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _reset(),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppPrimaryButton(
            label: guard('forgot_reset').label('Update password'),
            onPressed: guard('forgot_reset').isLocked ? null : _reset,
            isLoading: _loading,
          ),
        ],
      ),
    ),
  );
}
