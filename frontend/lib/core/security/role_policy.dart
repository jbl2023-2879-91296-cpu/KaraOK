/// UI authorization policy. The API still performs authoritative RBAC checks.
abstract final class RolePolicy {
  static const user = 'user';
  static const admin = 'admin';

  static bool canRunAssessment(String? role) => role == user;

  static bool canReadSystemLogs(String? role) => role == admin;
}
