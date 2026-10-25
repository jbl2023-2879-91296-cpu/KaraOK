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
    required this.email,
    this.developmentCode,
    this.authApi,
  });

  final String email;
  final String? developmentCode;
  final AuthApi? authApi;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
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
    if (_loading) return;
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
      final user = await (widget.authApi ?? AuthApi()).verifyRegistration(
        email: widget.email,
        code: _otpController.text.trim(),
      );
      try {
        await SecureTokenStore.instance.saveLastIdentifier(widget.email);
      } catch (_) {
        // Account creation succeeds even if the convenience value cannot save.
      }
      UserSession.instance.setUserFromMap(user);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AppShell()),
        (route) => false,
      );
    } on ApiException catch (error) {
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
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Email verification',
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
              subtitle: 'Enter the 6-digit code sent to ${widget.email}.',
            ),
            if (widget.developmentCode != null) ...[
              Text(
                'Development OTP: ${widget.developmentCode}',
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
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: AppPrimaryButton(
                label: 'Verify Email',
                onPressed: _verify,
                isLoading: _loading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
