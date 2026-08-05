<?php

declare(strict_types=1);

require dirname(__DIR__) . '/config/bootstrap.php';

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "This command is CLI-only.\n");
    exit(1);
}
$username = trim((string) ($argv[1] ?? ''));
if (!preg_match('/^[a-zA-Z0-9._-]{3,64}$/', $username)) {
    fwrite(STDERR, "Usage: php scripts/create-admin.php <username>\nUsername must be 3-64 safe characters.\n");
    exit(1);
}
fwrite(STDOUT, 'Password (12+ characters): ');
$password = trim((string) fgets(STDIN));
if (strlen($password) < 12) {
    fwrite(STDERR, "Password must contain at least 12 characters.\n");
    exit(1);
}
$file = ADMIN_ROOT . '/storage/private/admins.json';
$users = is_file($file) ? json_decode((string) file_get_contents($file), true) : [];
$users = is_array($users) ? $users : [];
$users[strtolower($username)] = [
    'id' => bin2hex(random_bytes(8)),
    'username' => $username,
    'password_hash' => password_hash($password, PASSWORD_DEFAULT),
    'enabled' => true,
    'created_at' => gmdate(DATE_ATOM),
];
file_put_contents($file, json_encode($users, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), LOCK_EX);
fwrite(STDOUT, "Local admin saved.\n");
