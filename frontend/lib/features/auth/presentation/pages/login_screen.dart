import 'package:karaok_app/shared/widgets/app_widgets.dart';
import 'package:karaok_app/shared/widgets/form_feedback.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:karaok_app/app/app_shell.dart';
import 'package:karaok_app/core/security/guest_assessment_service.dart';
import 'package:karaok_app/core/security/secure_token_store.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/account/presentation/pages/change_password_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/forgot_password_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialIdentifier, this.authApi});

  final String? initialIdentifier;
  final AuthApi? authApi;

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
  final _feedback = FormFeedback();

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
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;
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
      final res = await (widget.authApi ?? AuthApi()).login(
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
      if (!mounted) return;
      UserSession.instance.setUserFromMap(res);
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
      if (!mounted) return;
      setState(() {
        _feedback.receive(e, aliases: const {'identifier': 'email'});
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
    if (!UserSession.instance.isLoggedIn) {
      UserSession.instance.setGuest('user');
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AppShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Sign in',
      automaticallyImplyLeading: false,
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back),
        onPressed: () async {
          if (!await Navigator.maybePop(context) && mounted) {
            _navigateHome();
          }
        },
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              FormErrorBanner(
                message: _error!,
                onRetry: _loading ? null : _login,
              ),
            const AppSectionHeader(
              title: 'Welcome back',
              subtitle: 'Sign in to continue',
            ),
            _AuthField(
              label: 'Email',
              fieldKey: _feedback.key('email'),
              focusNode: _feedback.focus('email'),
              errorText: _feedback.errors['email'],
              onChanged: (_) =>
                  setState(() => _feedback.errors.remove('email')),
              keyboardType: TextInputType.emailAddress,
              controller: _identifierCtrl,
              hint: 'you@example.com',
              suffixIcon: _hasRememberedIdentifier
                  ? IconButton(
                      tooltip: 'Forget saved account',
                      onPressed: _loading ? null : _forgetRememberedIdentifier,
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.muted,
                        size: 20,
                      ),
                    )
                  : null,
              validator: validateEmail,
            ),
            const SizedBox(height: 16),
            _AuthField(
              label: 'Password',
              fieldKey: _feedback.key('password'),
              focusNode: _feedback.focus('password'),
              errorText: _feedback.errors['password'],
              onChanged: (_) =>
                  setState(() => _feedback.errors.remove('password')),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _login(),
              controller: _passCtrl,
              hint: '••••••••',
              obscure: _obscure,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.muted,
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
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Login button
            SizedBox(
              width: double.infinity,
              child: AppPrimaryButton(
                label: 'Log In',
                onPressed: _login,
                isLoading: _loading,
              ),
            ),
            const SizedBox(height: 16),
            // Sign up redirect
            AppPromptLink(
              prompt: "Don't have an account?",
              action: 'Sign Up',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SignUpScreen()),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            // Divider
            Row(
              children: [
                const Expanded(child: Divider(color: AppColors.outline)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or', style: TextStyle(color: AppColors.muted)),
                ),
                const Expanded(child: Divider(color: AppColors.outline)),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: AppSecondaryButton(
                label: 'Continue as Guest (3 evaluations)',
                icon: Icons.person_outline,
                onPressed: _loading ? null : _continueAsGuest,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Guest mode allows three audio evaluations on this device. Guest reports stay on this device and remain separate from account history.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.suffixIcon,
    this.validator,
    this.fieldKey,
    this.focusNode,
    this.errorText,
    this.onChanged,
    this.keyboardType,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final GlobalKey<FormFieldState<String>>? fieldKey;
  final FocusNode? focusNode;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;
  final bool obscure;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

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
      onChanged: onChanged,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
    );
  }
}
