<?php

declare(strict_types=1);

namespace KaraOK\Admin\Security;

final class Csrf
{
    public static function token(): string
    {
        if (!isset($_SESSION['_csrf'])) {
            $_SESSION['_csrf'] = bin2hex(random_bytes(32));
        }
        return (string) $_SESSION['_csrf'];
    }

    public static function valid(?string $token): bool
    {
        return is_string($token) && hash_equals(self::token(), $token);
    }
}
