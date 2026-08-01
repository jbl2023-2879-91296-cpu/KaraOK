import 'package:flutter/material.dart';
import 'package:karaok_app/app/app_shell.dart';
import 'package:karaok_app/core/security/guest_assessment_service.dart';
import 'package:karaok_app/core/security/secure_token_store.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/core/storage/guest_assessment_store.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/account/presentation/pages/change_password_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/forgot_password_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialIdentifier});

  final String? initialIdentifier;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _identifierCtrl;
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _hasRememberedIdentifier = false;
  String? _error;

  static const _accentColor = Color(0xFF4A90D9);

  @override
  void initState() {
    super.initState();
    _identifierCtrl = TextEditingController(text: widget.initialIdentifier);
    _loadRememberedIdentifier();
  }

  Future<void> _loadRememberedIdentifier() async {
    final saved = await SecureTokenStore.instance.readLastIdentifier();
    if (!mounted) return;
    if (_identifierCtrl.text.trim().isEmpty && saved?.isNotEmpty == true) {
      _identifierCtrl.text = saved!;
    }
    setState(() => _hasRememberedIdentifier = saved?.isNotEmpty == true);
  }

  Future<void> _forgetRememberedIdentifier() async {
    await SecureTokenStore.instance.clearLastIdentifier();
    if (!mounted) return;
    _identifierCtrl.clear();
    setState(() => _hasRememberedIdentifier = false);
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await AuthApi().login(
        identifier: _identifierCtrl.text.trim(),
        password: _passCtrl.text,
      );
      try {
        await SecureTokenStore.instance.saveLastIdentifier(
          res['email'] as String? ?? _identifierCtrl.text.trim(),
        );
      } catch (_) {
        // Remembering the identifier is a convenience and must not block login.
      }
      UserSession.instance.setUserFromMap(res);
      try {
        await GuestAssessmentStore.instance.clearAll();
      } catch (_) {
        // Authentication succeeds even if local guest cleanup must retry.
      }
      if (UserSession.instance.requiresPasswordChange) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => const ChangePasswordScreen(forceChange: true),
          ),
          (route) => false,
        );
        return;
      }
      _navigateHome();
    } on ApiException catch (e) {
      final body = e.message;
      setState(() {
        _error = body.contains('Invalid')
            ? 'Invalid username/email or password.'
            : 'Login failed. Try again.';
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Could not connect to server.';
        _loading = false;
      });
    }
  }

  Future<void> _continueAsGuest() async {
    if (!await GuestAssessmentService.instance.canAssess()) {
      if (!mounted) return;
      setState(() {
        _error =
            'This device has used all three guest evaluations. Sign in or create an account to continue.';
      });
      return;
    }
    if (!mounted) return;
    UserSession.instance.setGuest('user');
    _navigateHome();
  }

  void _navigateHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AppShell()),
      (route) => false,
    );
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
                // Header
                Text(
                  'Welcome back',
                  style: TextStyle(
                    color: _accentColor,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Sign in to continue',
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 36),
                _FieldLabel('Username or Email'),
                const SizedBox(height: 6),
                _AuthField(
                  controller: _identifierCtrl,
                  hint: 'Username or email address',
                  suffixIcon: _hasRememberedIdentifier
                      ? IconButton(
                          tooltip: 'Forget saved account',
                          onPressed: _loading
                              ? null
                              : _forgetRememberedIdentifier,
                          icon: const Icon(
                            Icons.close,
                            color: Color(0xFF666666),
                            size: 20,
                          ),
                        )
                      : null,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Enter your username or email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                // Password
                _FieldLabel('Password'),
                const SizedBox(height: 6),
                _AuthField(
                  controller: _passCtrl,
                  hint: '••••••••',
                  obscure: _obscure,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      color: const Color(0xFF666666),
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter your password';
                    return null;
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ForgotPasswordScreen(),
                      ),
                    ),
                    child: Text(
                      'Forgot password?',
                      style: TextStyle(color: _accentColor),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                // Error message
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
                const SizedBox(height: 8),
                // Login button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
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
                            'Log In',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                // Sign up redirect
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Don't have an account? ",
                      style: TextStyle(color: Color(0xFF888888), fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SignUpScreen(),
                          ),
                        );
                      },
                      child: Text(
                        'Sign Up',
                        style: TextStyle(
                          color: _accentColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // Divider
                Row(
                  children: [
                    const Expanded(child: Divider(color: Color(0xFF2A2A3E))),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'or',
                        style: TextStyle(
                          color: Color(0xFF666666),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider(color: Color(0xFF2A2A3E))),
                  ],
                ),
                const SizedBox(height: 24),
                // Guest button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _continueAsGuest,
                    icon: const Icon(
                      Icons.person_outline,
                      color: Color(0xFF888888),
                    ),
                    label: const Text(
                      'Continue as Guest (3 evaluations)',
                      style: TextStyle(
                        color: Color(0xFFAAAAAA),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: Color(0xFF3A3A5E),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Guest mode allows three audio evaluations on this device. Results are shown once and are not added to history.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 11,
                    height: 1.5,
                  ),
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

// ── Shared small widgets ──────────────────────────────────────────────────────

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
    this.suffixIcon,
    this.validator,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
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
