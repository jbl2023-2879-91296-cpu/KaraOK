import 'package:karaok_app/app/app_theme.dart';

import 'package:flutter/material.dart';

import 'package:karaok_app/core/security/password_policy.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/otp_verification_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  static const _accentColor = AppColors.primary;

  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _obscurePass = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_usernameCtrl, _emailCtrl, _passCtrl]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await AuthApi().startRegistration(
        username: _usernameCtrl.text.trim(),
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
        _error = error.message.contains('already')
            ? 'An account with this email or username already exists.'
            : error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not connect to server.';
        _loading = false;
      });
    }
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? 'Enter $label' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: AppColors.ink),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Account',
                  style: const TextStyle(
                    color: _accentColor,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text(
                  'Verify your email, then add personal details after login.',
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
                ),
                const SizedBox(height: 24),
                _LabeledField(
                  label: 'Username',
                  controller: _usernameCtrl,
                  hint: 'Choose a username',
                  validator: (value) {
                    final username = value?.trim() ?? '';
                    return RegExp(r'^[A-Za-z0-9_.-]{3,50}$').hasMatch(username)
                        ? null
                        : 'Use 3-50 letters, numbers, dots, dashes, or underscores';
                  },
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  label: 'Email',
                  controller: _emailCtrl,
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    final required = _required(value, 'your email');
                    if (required != null) return required;
                    return value!.contains('@') ? null : 'Enter a valid email';
                  },
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  label: 'Password',
                  controller: _passCtrl,
                  hint: '8-128 characters with mixed types',
                  obscure: _obscurePass,
                  maxLength: PasswordPolicy.maximumLength,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                  validator: PasswordPolicy.validate,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _signUp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text(
                            'Send Verification Code',
                            style: TextStyle(
                              color: AppColors.onPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          validator: validator,
          maxLength: maxLength,
          style: const TextStyle(color: AppColors.ink, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.muted, fontSize: 15),
            suffixIcon: suffixIcon,
            counterText: '',
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
