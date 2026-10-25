import 'package:karaok_app/shared/widgets/app_widgets.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:karaok_app/shared/widgets/form_feedback.dart';
import 'package:karaok_app/features/auth/presentation/pages/forgot_password_screen.dart';

import 'package:flutter/material.dart';

import 'package:karaok_app/core/security/password_policy.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/otp_verification_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, this.authApi});
  final AuthApi? authApi;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _confirmCtrl = TextEditingController();
  final _feedback = FormFeedback();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _obscurePass = true;
  bool _loading = false;
  bool _confirmTouched = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_confirmCtrl, _emailCtrl, _passCtrl]) {
      controller.dispose();
    }
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (_loading) return;
    _submitted = true;
    setState(_feedback.clear);
    if (!_formKey.currentState!.validate()) {
      _feedback.reveal();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await (widget.authApi ?? AuthApi()).startRegistration(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      if (!mounted) return;
      final serverEmail = response['email'];
      final verificationEmail = serverEmail is String && serverEmail.isNotEmpty
          ? serverEmail
          : _emailCtrl.text.trim().toLowerCase();
      setState(() => _loading = false);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            email: verificationEmail,
            developmentCode: response['development_code'] as String?,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _feedback.receive(error);
        if (error.statusCode == 409 && _feedback.errors.isEmpty) {
          _feedback.errors['email'] = error.message;
          _feedback.banner = null;
        }
        _error = _feedback.banner;
        _loading = false;
      });
      _feedback.reveal();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not connect to server.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Account',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              FormErrorBanner(
                message: _error!,
                onRetry: _loading ? null : _signUp,
              ),
            const AppSectionHeader(
              title: 'Create Account',
              subtitle:
                  'Verify your email, then add personal details after login.',
            ),
            _LabeledField(
              fieldKey: _feedback.key('email'),
              focusNode: _feedback.focus('email'),
              errorText: _feedback.errors['email'],
              onChanged: (_) =>
                  setState(() => _feedback.errors.remove('email')),
              label: 'Email',
              controller: _emailCtrl,
              hint: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
              validator: validateEmail,
            ),
            const SizedBox(height: 16),
            _LabeledField(
              fieldKey: _feedback.key('password'),
              focusNode: _feedback.focus('password'),
              errorText: _feedback.errors['password'],
              onChanged: (_) {
                setState(() => _feedback.errors.remove('password'));
                if (_confirmTouched || _submitted) {
                  _feedback.key('confirm_password').currentState?.validate();
                }
              },
              label: 'Password',
              controller: _passCtrl,
              hint: '8-128 characters with mixed types',
              obscure: _obscurePass,
              maxLength: PasswordPolicy.maximumLength,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePass ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
              validator: PasswordPolicy.validate,
            ),
            PasswordChecklist(controller: _passCtrl),
            _LabeledField(
              fieldKey: _feedback.key('confirm_password'),
              focusNode: _feedback.focus('confirm_password'),
              onChanged: (_) => _confirmTouched = true,
              label: 'Confirm password',
              controller: _confirmCtrl,
              hint: 'Enter your password again',
              obscure: _obscurePass,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _signUp(),
              validator: (value) => value == null || value.isEmpty
                  ? 'Confirm your password.'
                  : value != _passCtrl.text
                  ? 'Passwords must match.'
                  : null,
            ),
            if (_feedback.errors.containsKey('email'))
              Wrap(
                children: [
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LoginScreen(
                          initialIdentifier: _emailCtrl.text.trim(),
                        ),
                      ),
                    ),
                    child: const Text('Sign in'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ForgotPasswordScreen(),
                      ),
                    ),
                    child: const Text('Reset password'),
                  ),
                ],
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: AppPrimaryButton(
                label: 'Send Verification Code',
                onPressed: _signUp,
                isLoading: _loading,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                const Text(
                  'Already have an account? ',
                  style: TextStyle(color: AppColors.muted),
                ),
                TextButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  child: const Text('Log In'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.suffixIcon,
    this.validator,
    this.maxLength,
    this.fieldKey,
    this.focusNode,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final int? maxLength;
  final GlobalKey<FormFieldState<String>>? fieldKey;
  final FocusNode? focusNode;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    return AppFormField(
      fieldKey: fieldKey,
      focusNode: focusNode,
      controller: controller,
      label: label,
      hint: hint,
      errorText: errorText,
      validator: validator,
      obscure: obscure,
      suffixIcon: suffixIcon,
      keyboardType: keyboardType,
      maxLength: maxLength,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
    );
  }
}
