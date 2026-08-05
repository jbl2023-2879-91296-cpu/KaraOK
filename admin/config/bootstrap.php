<?php

declare(strict_types=1);

use KaraOK\Admin\Config\Environment;
use KaraOK\Admin\Api\AdminApiClient;
use KaraOK\Admin\Security\AuthService;
use KaraOK\Admin\Security\RateLimiter;
use KaraOK\Admin\Support\ActivityLogger;

define('ADMIN_ROOT', dirname(__DIR__));

$composer = ADMIN_ROOT . '/vendor/autoload.php';
if (is_file($composer)) {
    require $composer;
} else {
    spl_autoload_register(static function (string $class): void {
        $prefix = 'KaraOK\\Admin\\';
        if (str_starts_with($class, $prefix)) {
            $file = ADMIN_ROOT . '/app/' . str_replace('\\', '/', substr($class, strlen($prefix))) . '.php';
            if (is_file($file)) {
                require $file;
            }
        }
    });
}

$env = new Environment(ADMIN_ROOT . '/.env');
date_default_timezone_set($env->get('APP_TIMEZONE', 'Asia/Manila'));

if (PHP_SAPI !== 'cli') {
    ini_set('session.use_strict_mode', '1');
    ini_set('session.use_only_cookies', '1');
    session_name($env->get('SESSION_NAME', 'karaok_admin'));
    session_set_cookie_params([
        'lifetime' => 0,
        'path' => '/',
        'secure' => (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off'),
        'httponly' => true,
        'samesite' => 'Strict',
    ]);
    session_start();
    header('X-Content-Type-Options: nosniff');
    header('X-Frame-Options: DENY');
    header('Referrer-Policy: no-referrer');
    header("Permissions-Policy: camera=(), microphone=(), geolocation=()");
    header("Content-Security-Policy: default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; form-action 'self'; frame-ancestors 'none'; base-uri 'none'");
}

$logger = new ActivityLogger(ADMIN_ROOT . '/storage/logs/activity.jsonl');
$auth = new AuthService(
    ADMIN_ROOT . '/storage/private/admins.json',
    new RateLimiter(ADMIN_ROOT . '/storage/private/login-attempts.json'),
    $logger,
    max(5, $env->int('SESSION_IDLE_MINUTES', 30)),
);
$adminApi = null;
try {
    $adminApi = new AdminApiClient($env);
} catch (Throwable) {
    // The login page remains available while API configuration is incomplete.
}

/** @return array{privacy_mode: bool} */
function admin_settings(): array
{
    $defaults = ['privacy_mode' => true];
    $file = ADMIN_ROOT . '/storage/private/settings.json';
    if (!is_file($file)) {
        return $defaults;
    }
    $data = json_decode((string) file_get_contents($file), true);
    return is_array($data) ? array_merge($defaults, $data) : $defaults;
}

function h(mixed $value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function bytes(mixed $value): string
{
    $size = (float) $value;
    foreach (['B', 'KB', 'MB', 'GB', 'TB'] as $unit) {
        if ($size < 1024 || $unit === 'TB') {
            return number_format($size, $unit === 'B' ? 0 : 1) . ' ' . $unit;
        }
        $size /= 1024;
    }
    return '0 B';
}

function redirect(string $url): never
{
    header('Location: ' . $url, true, 303);
    exit;
}
