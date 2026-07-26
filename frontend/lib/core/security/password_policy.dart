/// Client-side password checks for fast form feedback.
///
/// The backend remains authoritative and must enforce the same or stricter
/// policy for every password-changing endpoint.
abstract final class PasswordPolicy {
  static String? validate(String? value) {
    final password = value ?? '';
    if (password.length < 12 || password.length > 128) {
      return 'Use 12–128 characters.';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      return 'Include uppercase, lowercase, number, and symbol.';
    }
    return null;
  }
}
