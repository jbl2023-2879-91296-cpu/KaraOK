import 'package:flutter/material.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:karaok_app/core/network/api_exception.dart';

String? validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Enter your email address.';
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
      ? null
      : 'Enter a valid email address.';
}

class AppFormField extends StatelessWidget {
  const AppFormField({
    super.key,
    this.fieldKey,
    this.focusNode,
    required this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.validator,
    this.obscure = false,
    this.suffixIcon,
    this.keyboardType,
    this.maxLength,
    this.onChanged,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });
  final GlobalKey<FormFieldState<String>>? fieldKey;
  final FocusNode? focusNode;
  final TextEditingController controller;
  final String? label, hint, errorText;
  final String? Function(String?)? validator;
  final bool obscure;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final int? maxLength;
  final ValueChanged<String>? onChanged, onSubmitted;
  final TextInputAction textInputAction;
  @override
  Widget build(BuildContext context) => TextFormField(
    autovalidateMode: AutovalidateMode.onUserInteraction,
    key: fieldKey,
    focusNode: focusNode,
    controller: controller,
    validator: validator,
    obscureText: obscure,
    keyboardType: keyboardType,
    maxLength: maxLength,
    onChanged: onChanged,
    textInputAction: textInputAction,
    onFieldSubmitted: onSubmitted ?? (_) => FocusScope.of(context).nextFocus(),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      suffixIcon: suffixIcon,
      counterText: maxLength == null ? null : '',
      errorMaxLines: 3,
    ),
  );
}

/// Owns field anchors and focus so client and server errors use the same path.
class FormFeedback {
  final errors = <String, String>{};
  final keys = <String, GlobalKey<FormFieldState<String>>>{};
  final nodes = <String, FocusNode>{};
  String? banner;
  GlobalKey<FormFieldState<String>> key(String name) =>
      keys.putIfAbsent(name, () => GlobalKey<FormFieldState<String>>());
  FocusNode focus(String name) => nodes.putIfAbsent(name, FocusNode.new);
  void clear() {
    errors.clear();
    banner = null;
  }

  void receive(ApiException error, {Map<String, String> aliases = const {}}) {
    clear();
    for (final entry in error.fieldErrors.entries) {
      final name = aliases[entry.key] ?? entry.key;
      if (keys.containsKey(name)) errors[name] = entry.value;
    }
    if (errors.isEmpty) banner = error.message;
  }

  void reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final entry in keys.entries) {
        if (errors.containsKey(entry.key) ||
            entry.value.currentState?.hasError == true) {
          final context = entry.value.currentContext;
          if (context != null) {
            Scrollable.ensureVisible(
              context,
              alignment: .25,
              duration: const Duration(milliseconds: 220),
            );
            nodes[entry.key]?.requestFocus();
          }
          break;
        }
      }
    });
  }

  void dispose() {
    for (final node in nodes.values) {
      node.dispose();
    }
  }
}

class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.peach,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(color: AppColors.error)),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class PasswordChecklist extends StatelessWidget {
  const PasswordChecklist({super.key, required this.controller});
  final TextEditingController controller;
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) {
      final password = value.text;
      final rules = <String, bool>{
        '8–128 characters': password.length >= 8 && password.length <= 128,
        'Uppercase letter': RegExp(r'[A-Z]').hasMatch(password),
        'Lowercase letter': RegExp(r'[a-z]').hasMatch(password),
        'Number': RegExp(r'\d').hasMatch(password),
        'Symbol': RegExp(r'[^A-Za-z0-9]').hasMatch(password),
      };
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final rule in rules.entries)
              Semantics(
                label: '${rule.key}: ${rule.value ? 'met' : 'not met'}',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      rule.value ? Icons.check_circle : Icons.circle_outlined,
                      size: 16,
                      color: rule.value ? AppColors.success : AppColors.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      rule.key,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
