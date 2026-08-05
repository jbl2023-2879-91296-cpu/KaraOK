<?php

declare(strict_types=1);

namespace KaraOK\Admin\Security;

use KaraOK\Admin\Support\ActivityLogger;

final class AuthService
{
    public function __construct(
        private readonly string $adminsFile,
        private readonly RateLimiter $limiter,
        private readonly ActivityLogger $logger,
        private readonly int $idleMinutes = 30,
    ) {
    }

    public function attempt(string $username, string $password): bool
    {
        $key = $username . '|' . ($_SERVER['REMOTE_ADDR'] ?? 'local');
        if ($this->limiter->blocked($key)) {
            $this->logger->log('auth.rate_limited');
            return false;
        }
        $users = $this->users();
        $user = $users[strtolower(trim($username))] ?? null;
        if (!is_array($user) || !($user['enabled'] ?? false) || !password_verify($password, (string) ($user['password_hash'] ?? ''))) {
            $this->limiter->hit($key);
            $this->logger->log('auth.failed');
            return false;
        }
        $this->limiter->clear($key);
        session_regenerate_id(true);
        $_SESSION['admin'] = ['id' => (string) ($user['id'] ?? $username), 'username' => (string) $user['username']];
        $_SESSION['last_activity'] = time();
        $this->logger->log('auth.succeeded');
        return true;
    }

    public function check(): bool
    {
        if (!isset($_SESSION['admin'], $_SESSION['last_activity'])) {
            return false;
        }
        if (time() - (int) $_SESSION['last_activity'] > ($this->idleMinutes * 60)) {
            $this->logout();
            return false;
        }
        $_SESSION['last_activity'] = time();
        return true;
    }

    public function logout(): void
    {
        if (isset($_SESSION['admin'])) {
            $this->logger->log('auth.logout');
        }
        $_SESSION = [];
        if (ini_get('session.use_cookies')) {
            $params = session_get_cookie_params();
            setcookie(session_name(), '', time() - 42000, $params['path'], $params['domain'], $params['secure'], $params['httponly']);
        }
        session_destroy();
    }

    /** @return array<string, array<string, mixed>> */
    private function users(): array
    {
        if (!is_file($this->adminsFile)) {
            return [];
        }
        $decoded = json_decode((string) file_get_contents($this->adminsFile), true);
        return is_array($decoded) ? $decoded : [];
    }
}
