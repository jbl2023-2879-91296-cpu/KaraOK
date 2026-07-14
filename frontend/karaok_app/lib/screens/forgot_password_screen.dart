import 'package:flutter/material.dart';

import '../services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _resetRequested = false;
  bool _loading = false;
  bool _obscure = true;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _tokenController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });
    try {
      final response = await ApiService().requestPasswordReset(email);
      final developmentToken = response['reset_token'];
      if (developmentToken is String) _tokenController.text = developmentToken;
      setState(() {
        _resetRequested = true;
        _message = developmentToken is String
            ? 'Development reset token generated below.'
            : 'If the account exists, reset instructions have been sent.';
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Could not connect to the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final password = _passwordController.text;
    if (_tokenController.text.trim().isEmpty) {
      setState(() => _error = 'Enter the reset token.');
      return;
    }
    if (password.length < 12 ||
        !RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      setState(() => _error = 'Use 12+ characters with mixed case, a number, and a symbol.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiService().resetPassword(
        token: _tokenController.text.trim(),
        password: password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset. You can now log in.')),
      );
      Navigator.pop(context);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Could not connect to the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Recover your account',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Request a single-use token. For development demos it is shown here; production should deliver it by email.',
              style: TextStyle(color: Color(0xFFAAAAAA), height: 1.4),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              enabled: !_resetRequested,
              decoration: const InputDecoration(labelText: 'Email address'),
            ),
            const SizedBox(height: 16),
            if (!_resetRequested)
              ElevatedButton(
                onPressed: _loading ? null : _requestReset,
                child: const Text('Request reset token'),
              ),
            if (_resetRequested) ...[
              TextField(
                controller: _tokenController,
                decoration: const InputDecoration(labelText: 'Reset token'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'New password',
                  helperText: '12+ characters, mixed case, number and symbol',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loading ? null : _resetPassword,
                child: const Text('Set new password'),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!, style: const TextStyle(color: Colors.greenAccent)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
    );
  }
}
