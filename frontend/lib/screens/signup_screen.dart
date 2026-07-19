import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'otp_verification_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConf = true;
  bool _loading = false;
  String? _error;
  String _userType = 'owner';

  static const _accentColor = Color(0xFF4A90D9);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiService().startRegistration(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        userType: _userType,
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
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message.contains('already')
            ? 'An account with this email already exists.'
            : 'Registration failed. Try again.';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
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
                const SizedBox(height: 8),
                Text(
                  'Create Account',
                  style: TextStyle(
                    color: _accentColor,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Create an account to save your results',
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),
                _FieldLabel('Account type'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _userType,
                  items: const [
                    DropdownMenuItem(value: 'owner', child: Text('Owner')),
                    DropdownMenuItem(
                      value: 'technician',
                      child: Text('Technician'),
                    ),
                  ],
                  onChanged: _loading
                      ? null
                      : (value) => setState(() => _userType = value ?? 'owner'),
                  decoration: const InputDecoration(
                    hintText: 'Select account type',
                  ),
                ),
                const SizedBox(height: 16),
                // Username
                _FieldLabel('Username'),
                const SizedBox(height: 6),
                _AuthField(
                  controller: _nameCtrl,
                  hint: 'Choose a username',
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your name' : null,
                ),
                const SizedBox(height: 16),
                // Email
                _FieldLabel('Email'),
                const SizedBox(height: 6),
                _AuthField(
                  controller: _emailCtrl,
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter your email';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Password
                _FieldLabel('Password'),
                const SizedBox(height: 6),
                _AuthField(
                  controller: _passCtrl,
                  hint: '12+ characters, mixed case, number and symbol',
                  obscure: _obscurePass,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                      color: const Color(0xFF666666),
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter a password';
                    if (v.length < 12) {
                      return 'Password must be at least 12 characters';
                    }
                    if (!RegExp(r'[A-Z]').hasMatch(v) ||
                        !RegExp(r'[a-z]').hasMatch(v) ||
                        !RegExp(r'\d').hasMatch(v) ||
                        !RegExp(r'[^A-Za-z0-9]').hasMatch(v)) {
                      return 'Use upper/lowercase, a number, and a symbol';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Confirm password
                _FieldLabel('Confirm Password'),
                const SizedBox(height: 6),
                _AuthField(
                  controller: _confirmCtrl,
                  hint: '••••••••',
                  obscure: _obscureConf,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConf ? Icons.visibility_off : Icons.visibility,
                      color: const Color(0xFF666666),
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConf = !_obscureConf),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Confirm your password';
                    if (v != _passCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                // Error
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFF44336),
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                // Sign Up button
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
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Send Verification Code',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                // Already have account
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(color: Color(0xFF888888), fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
                      child: Text(
                        'Log In',
                        style: TextStyle(
                          color: _accentColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared field widgets (same as login_screen) ───────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFFCCCCCC),
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.suffixIcon,
    this.validator,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF444444)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFF1C1C2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        errorStyle: const TextStyle(color: Color(0xFFF44336)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
