import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/user_session.dart';
import '../widgets/app_navigation_drawer.dart';
import 'login_screen.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.forceChange = false});

  final bool forceChange;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validateNewPassword(String? value) {
    final password = value ?? '';
    if (password.length < 12 ||
        !RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      return 'Use 12+ characters with mixed case, a number, and a symbol.';
    }
    if (!widget.forceChange && password == _currentController.text) {
      return 'Choose a password different from the current password.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiService().changePassword(
        currentPassword: widget.forceChange ? null : _currentController.text,
        newPassword: _newController.text,
      );
      final email = UserSession.instance.email;
      await ApiService().clearTokens();
      UserSession.instance.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed. Please log in again.')),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(initialIdentifier: email),
        ),
        (route) => false,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message.contains('incorrect')
            ? 'The current password is incorrect.'
            : error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not connect to the server.';
        _loading = false;
      });
    }
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback toggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          onPressed: toggle,
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
        ),
      ),
    );
  }

  Widget _accountDetails(UserSession session) {
    final role = session.userType == 'owner' ? 'Owner' : 'Technician';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Account Details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2A3E)),
          ),
          child: Column(
            children: [
              _AccountDetailRow(
                icon: Icons.person_outline,
                label: 'Username',
                value: session.name ?? 'Not available',
              ),
              const Divider(height: 24, color: Color(0xFF2A2A3E)),
              _AccountDetailRow(
                icon: Icons.email_outlined,
                label: 'Email',
                value: session.email ?? 'Not available',
              ),
              const Divider(height: 24, color: Color(0xFF2A2A3E)),
              _AccountDetailRow(
                icon: Icons.badge_outlined,
                label: 'Account type',
                value: role,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = UserSession.instance;

    return PopScope(
      canPop: !widget.forceChange,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        drawer: widget.forceChange ? null : const AppNavigationDrawer(),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: const Color(0xFF0D0D0D),
          leading: widget.forceChange ? null : const AppDrawerButton(),
          title: Text(
            widget.forceChange ? 'Password Change Required' : 'Settings',
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (!widget.forceChange) ...[
                  _accountDetails(session),
                  const SizedBox(height: 28),
                  const Text(
                    'Change Password',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  widget.forceChange
                      ? 'You signed in with a temporary password. Change it now before continuing.'
                      : 'Enter your current password, then choose a new secure password.',
                  style: const TextStyle(color: Color(0xFFAAAAAA), height: 1.4),
                ),
                const SizedBox(height: 24),
                if (!widget.forceChange) ...[
                  _passwordField(
                    controller: _currentController,
                    label: 'Current password',
                    obscure: _obscureCurrent,
                    toggle: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Enter your current password.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                _passwordField(
                  controller: _newController,
                  label: 'New password',
                  obscure: _obscureNew,
                  toggle: () => setState(() => _obscureNew = !_obscureNew),
                  validator: _validateNewPassword,
                ),
                const SizedBox(height: 16),
                _passwordField(
                  controller: _confirmController,
                  label: 'Retype new password',
                  obscure: _obscureConfirm,
                  toggle: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  validator: (value) => value != _newController.text
                      ? 'The new passwords do not match.'
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirm password change'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountDetailRow extends StatelessWidget {
  const _AccountDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF4A90D9), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
