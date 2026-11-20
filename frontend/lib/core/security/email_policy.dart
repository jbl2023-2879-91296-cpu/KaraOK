import 'package:karaok_app/shared/widgets/form_feedback.dart';

const _allowedEmailDomains = String.fromEnvironment(
  'ALLOWED_EMAIL_DOMAINS',
  defaultValue:
      'gmail.com,googlemail.com,yahoo.com,yahoo.com.ph,ymail.com,rocketmail.com,'
      'outlook.com,hotmail.com,live.com,msn.com,icloud.com,me.com,mac.com,'
      'proton.me,protonmail.com,aol.com,zoho.com,gmx.com,mail.com,yandex.com',
);

String? validateRegistrationEmail(String? value) {
  final error = validateEmail(value);
  if (error != null) return error;
  final domain = value!.trim().toLowerCase().split('@').last;
  if (_allowedEmailDomains
      .split(',')
      .any((entry) => entry.trim().toLowerCase() == domain)) {
    return null;
  }
  return 'Use an email from a supported provider such as Gmail, Yahoo, Outlook or iCloud.';
}
