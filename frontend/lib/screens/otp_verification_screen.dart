import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/user_session.dart';
import 'owner_home_screen.dart';
import 'technician_home_screen.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.email,
    this.developmentCode,
  });

  final String email;
  final String? developmentCode;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  bool _loading = false;
  String? _error;

  static const _accentColor = Color(0xFF4A90D9);

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await ApiService().verifyRegistration(
        email: widget.email,
        code: _otpController.text.trim(),
      );
      UserSession.instance.setUser(
        id: user['id'],
        name: user['name'],
        email: user['email'],
        userType: user['user_type'],
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => UserSession.instance.userType == 'owner'
              ? const OwnerHomeScreen()
              : const TechnicianHomeScreen(),
        ),
        (route) => false,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message.contains('Invalid')
            ? 'The verification code is invalid or has expired.'
            : 'Verification failed. Try again.';
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
          onPressed: _loading ? null : () => Navigator.pop(context),
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
                const Text(
                  'Verify Your Email',
                  style: TextStyle(
                    color: _accentColor,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the 6-digit code sent to ${widget.email}.',
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                if (widget.developmentCode != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Development OTP: ${widget.developmentCode}',
                    style: const TextStyle(color: Color(0xFFFFB74D)),
                  ),
                ],
                const SizedBox(height: 32),
                const Text(
                  'Verification Code',
                  style: TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _otpController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    letterSpacing: 8,
                  ),
                  validator: (value) => value == null ||
                          !RegExp(r'^\d{6}$').hasMatch(value.trim())
                      ? 'Enter the 6-digit code from your email'
                      : null,
                  decoration: InputDecoration(
                    hintText: '000000',
                    counterText: '',
                    hintStyle: const TextStyle(color: Color(0xFF444444)),
                    filled: true,
                    fillColor: const Color(0xFF1C1C2E),
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
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFF44336),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _verify,
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
                            'Verify Email',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
