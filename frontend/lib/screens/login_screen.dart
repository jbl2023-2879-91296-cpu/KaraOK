import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/user_session.dart';
import 'signup_screen.dart';
import 'technician_home_screen.dart';
import 'owner_home_screen.dart';
import 'forgot_password_screen.dart';
import 'change_password_screen.dart';

class LoginScreen extends StatefulWidget {
  /// Pre-selected user type coming from splash ('technician' or 'owner')
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
  String? _error;

  static const _accentColor = Color(0xFF4A90D9);

  @override
  void initState() {
    super.initState();
    _identifierCtrl = TextEditingController(text: widget.initialIdentifier);
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
      final res = await ApiService().login(
        identifier: _identifierCtrl.text.trim(),
        password: _passCtrl.text,
      );
      UserSession.instance.setUser(
        id: res['id'],
        name: res['name'],
        email: res['email'],
        userType: res['user_type'],
        requiresPasswordChange: res['requires_password_change'] == true,
      );
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

  void _continueAsGuest() {
    UserSession.instance.setGuest('owner');
    _navigateHome();
  }

  void _navigateHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => UserSession.instance.userType == 'owner'
            ? const OwnerHomeScreen()
            : const TechnicianHomeScreen(),
      ),
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
                // Username or email
                _FieldLabel('Username or Email'),
                const SizedBox(height: 6),
                _AuthField(
                  controller: _identifierCtrl,
                  hint: 'Username or email address',
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Enter your username or email';
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
                      'Continue as Guest',
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
                  '⚠ Guest sessions are not saved. Your recordings and results will be lost when you exit.',
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
