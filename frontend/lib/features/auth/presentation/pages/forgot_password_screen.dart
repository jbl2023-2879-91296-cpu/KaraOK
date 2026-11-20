import 'package:karaok_app/shared/widgets/otp_countdown.dart';
import 'package:karaok_app/core/security/submit_guard.dart';
import 'package:karaok_app/shared/widgets/app_widgets.dart';
import 'package:karaok_app/shared/widgets/form_feedback.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:flutter/material.dart';

import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/auth/presentation/pages/reset_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.authApi});

  final AuthApi? authApi;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with GuardedSubmit<ForgotPasswordScreen> {
  @override
  Iterable<String> get submitActions => ['forgot'];
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _loading = false;
  final _feedback = FormFeedback();

  @override
  void dispose() {
    _emailController.dispose();
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    if (_loading || guard('forgot').isLocked) return;
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
      final email = _emailController.text.trim();
      var challenge = await OtpChallenge.restore('password_reset', email);
      if (challenge == null) {
        if (await guard('forgot').recordAttempt() != null || !mounted) return;
        final response = await (widget.authApi ?? AuthApi())
            .requestPasswordReset(email);
        challenge = OtpChallenge.fromResponse(email, response);
        await challenge.save('password_reset');
      }
      if (!mounted) return;
      final activeChallenge = challenge;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(
            challenge: activeChallenge,
            authApi: widget.authApi,
          ),
        ),
      );
    } on ApiException catch (error) {
      await applyRetryAfter('forgot', error);
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

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Forgot Password',
      maxContentWidth: 480,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_feedback.banner != null)
              AppErrorState(
                message: _feedback.banner!,
                onRetry: _loading ? null : _requestReset,
                isRetrying: _loading,
              ),
            const AppSectionHeader(
              title: 'Recover your account',
              subtitle:
                  'Enter your verified email address to request a password reset code.',
            ),
            TextFormField(
              autovalidateMode: AutovalidateMode.onUserInteraction,
              key: _feedback.key('email'),
              focusNode: _feedback.focus('email'),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _requestReset(),
              onChanged: (_) =>
                  setState(() => _feedback.errors.remove('email')),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              validator: validateEmail,
              decoration: InputDecoration(
                labelText: 'Email address',
                errorText: _feedback.errors['email'],
                constraints: const BoxConstraints(minHeight: 48),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: AppPrimaryButton(
                label: guard('forgot').label('Send reset code'),
                onPressed: guard('forgot').isLocked ? null : _requestReset,
                isLoading: _loading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
