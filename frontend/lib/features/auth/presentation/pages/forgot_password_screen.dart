import 'package:karaok_app/shared/widgets/form_feedback.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:flutter/material.dart';

import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.authApi});

  final AuthApi? authApi;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _loading = false;
  final _feedback = FormFeedback();

  @override
  void dispose() {
    _emailController.dispose();
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
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
      await (widget.authApi ?? AuthApi()).requestPasswordReset(
        _emailController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If the account exists, a temporary password was sent.',
          ),
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              LoginScreen(initialIdentifier: _emailController.text.trim()),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _feedback.receive(error));
      _feedback.reveal();
    } catch (_) {
      if (mounted) {
        setState(() => _feedback.banner = 'Could not connect to the server.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Forgot Password'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_feedback.banner != null)
                FormErrorBanner(
                  message: _feedback.banner!,
                  onRetry: _loading ? null : _requestReset,
                ),
              const Text(
                'Recover your account',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your verified email address. We will send a temporary password that you can use to sign in. You must change it immediately after login.',
                style: TextStyle(color: AppColors.muted, height: 1.4),
              ),
              const SizedBox(height: 24),
              TextFormField(
                autovalidateMode: AutovalidateMode.onUserInteraction,
                key: _feedback.key('email'),
                focusNode: _feedback.focus('email'),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _requestReset(),
                onChanged: (_) =>
                    setState(() => _feedback.errors.remove('email')),
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: validateEmail,
                decoration: InputDecoration(
                  labelText: 'Email address',
                  errorText: _feedback.errors['email'],
                  constraints: const BoxConstraints(minHeight: 48),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _loading ? null : _requestReset,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send temporary password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
