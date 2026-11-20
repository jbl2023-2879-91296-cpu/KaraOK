import 'package:karaok_app/shared/widgets/otp_countdown.dart';
import 'package:karaok_app/core/security/submit_guard.dart';
import 'package:karaok_app/shared/widgets/app_widgets.dart';
import 'package:karaok_app/shared/widgets/form_feedback.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:flutter/material.dart';

import 'package:karaok_app/app/app_shell.dart';
import 'package:karaok_app/core/security/secure_token_store.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.challenge,
    this.developmentCode,
    this.authApi,
  });

  final OtpChallenge challenge;
  final String? developmentCode;
  final AuthApi? authApi;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with GuardedSubmit<OtpVerificationScreen> {
  @override
  Iterable<String> get submitActions => ['register_verify', 'register_resend'];
  late OtpChallenge _challenge = widget.challenge;
  late String? _developmentCode = widget.developmentCode;
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  bool _loading = false;
  final _feedback = FormFeedback();

  @override
  void dispose() {
    _otpController.dispose();
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_loading || guard('register_verify').isLocked) return;
    setState(_feedback.clear);
    if (!_formKey.currentState!.validate()) {
      _feedback.reveal();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _feedback.clear();
    });
    try {
      if (await guard('register_verify').recordAttempt() != null || !mounted) {
        return;
      }
      final user = await (widget.authApi ?? AuthApi()).verifyRegistration(
        email: _challenge.email,
        challengeId: _challenge.challengeId,
        code: _otpController.text.trim(),
      );
      try {
        await SecureTokenStore.instance.saveLastIdentifier(_challenge.email);
      } catch (_) {
        // Account creation succeeds even if the convenience value cannot save.
      }
      await OtpChallenge.clear('registration');
      UserSession.instance.setUserFromMap(user);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AppShell()),
        (route) => false,
      );
    } on ApiException catch (error) {
      await applyRetryAfter('register_verify', error);
      if (!mounted) return;
      setState(() {
        _feedback.receive(error, aliases: const {'otp': 'code'});
        _loading = false;
      });
      _feedback.reveal();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _feedback.banner = 'Could not connect to server.';
      });
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
      if (await guard('register_resend').recordAttempt() != null || !mounted) {
        return null;
      }
      final json = await (widget.authApi ?? AuthApi()).resendRegistration(
        email: _challenge.email,
        challengeId: _challenge.challengeId,
      );
      final updated = OtpChallenge.fromResponse(_challenge.email, json);
      await updated.save('registration');
      if (mounted) {
        setState(() {
          _challenge = updated;
          _developmentCode = json['development_code'] as String?;
          _otpController.clear();
        });
      }
      return updated;
    } on ApiException catch (error) {
      await applyRetryAfter('register_resend', error);
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
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Email verification',
      maxContentWidth: 480,
      automaticallyImplyLeading: !_loading,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_feedback.banner != null)
              AppErrorState(
                message: _feedback.banner!,
                onRetry: _loading ? null : _verify,
                isRetrying: _loading,
              ),
            AppSectionHeader(
              title: 'Verify Your Email',
              subtitle: 'Enter the 6-digit code sent to ${_challenge.email}.',
            ),
            if (_developmentCode != null) ...[
              Text(
                'Development OTP: $_developmentCode',
                style: const TextStyle(color: AppColors.orangeInk),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            const Text(
              'Verification Code',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              autovalidateMode: AutovalidateMode.onUserInteraction,
              key: _feedback.key('code'),
              focusNode: _feedback.focus('code'),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _verify(),
              onChanged: (_) => setState(() => _feedback.errors.remove('code')),
              controller: _otpController,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 22,
                letterSpacing: 8,
              ),
              validator: (value) =>
                  value == null || !RegExp(r'^\d{6}$').hasMatch(value.trim())
                  ? 'Enter the 6-digit code from your email'
                  : null,
              decoration: InputDecoration(
                errorText: _feedback.errors['code'],
                constraints: const BoxConstraints(minHeight: 48),
                hintText: '000000',
                counterText: '',
                hintStyle: const TextStyle(color: AppColors.muted),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const Text(
              'If you already have an account, check your email for next steps.',
            ),
            OtpCountdown(
              challenge: _challenge,
              onResend: _resend,
              enabled: !_loading,
              lockRemaining: guard('register_resend').remaining,
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: AppPrimaryButton(
                label: guard('register_verify').label('Verify Email'),
                onPressed: guard('register_verify').isLocked ? null : _verify,
                isLoading: _loading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
