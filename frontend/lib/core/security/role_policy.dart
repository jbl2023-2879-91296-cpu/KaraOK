/// UI authorization policy. The API still performs authoritative RBAC checks.
abstract final class RolePolicy {
  static const owner = 'owner';
  static const technician = 'technician';
  static const admin = 'admin';

  static bool canRunAssessment(String? role) =>
      role == owner || role == technician;

  static bool canReadSystemLogs(String? role) => role == admin;
}
