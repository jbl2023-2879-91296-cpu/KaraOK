import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  bool _instructionsSent = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiService().requestPasswordReset(
        _emailController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('If the account exists, reset instructions were sent.'),
        ),
      );
      setState(() => _instructionsSent = true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not connect to the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await ApiService().resetPassword(
        token: _tokenController.text.trim(),
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset. Please sign in.')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen(initialIdentifier: _emailController.text.trim())),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not connect to the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        title: const Text('Forgot Password'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Recover your account',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _instructionsSent
                    ? 'Enter the one-time token from your email and choose a new password.'
                    : 'Enter your verified email address and we will send password reset instructions.',
                style: const TextStyle(color: Color(0xFFAAAAAA), height: 1.4),
              ),
              const SizedBox(height: 24),
              if (!_instructionsSent) TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                    return 'Enter a valid email address.';
                  }
                  return null;
                },
                decoration: const InputDecoration(labelText: 'Email address'),
              ),
              if (_instructionsSent) ...[
                TextFormField(
                  controller: _tokenController,
                  autocorrect: false,
                  validator: (value) => (value?.trim().length ?? 0) < 20
                      ? 'Enter the complete reset token.'
                      : null,
                  decoration: const InputDecoration(labelText: 'Reset token'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  validator: (value) {
                    final password = value ?? '';
                    if (password.length < 12 ||
                        !RegExp(r'[A-Z]').hasMatch(password) ||
                        !RegExp(r'[a-z]').hasMatch(password) ||
                        !RegExp(r'\d').hasMatch(password) ||
                        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
                      return 'Use 12+ characters with mixed case, a number, and a symbol.';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(labelText: 'New password'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmController,
                  obscureText: true,
                  validator: (value) => value != _passwordController.text
                      ? 'The passwords do not match.'
                      : null,
                  decoration: const InputDecoration(labelText: 'Confirm new password'),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loading ? null : (_instructionsSent ? _resetPassword : _requestReset),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_instructionsSent ? 'Reset password' : 'Send reset instructions'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
