<?php

declare(strict_types=1);

namespace KaraOK\Admin\Services;

final class SensitiveColumnDetector
{
    private const CREDENTIAL = ['password', 'passwd', 'password_hash', 'secret', 'token', 'api_key', 'access_key', 'refresh_token', 'otp', 'pin'];
    private const PERSONAL = ['email', 'phone', 'mobile', 'address', 'first_name', 'last_name', 'full_name', 'birth', 'dob', 'ip_address'];

    public function category(string $column): ?string
    {
        $name = strtolower($column);
        foreach (self::CREDENTIAL as $needle) {
            if ($name === $needle || str_contains($name, $needle)) {
                return 'credential';
            }
        }
        foreach (self::PERSONAL as $needle) {
            if ($name === $needle || str_contains($name, $needle)) {
                return 'personal';
            }
        }
        return null;
    }

    public function mask(mixed $value, string $category, bool $privacyMode): mixed
    {
        if ($value === null) {
            return null;
        }
        if ($category === 'credential') {
            return '[REDACTED]';
        }
        if (!$privacyMode) {
            return $value;
        }
        $text = (string) $value;
        if (str_contains($text, '@')) {
            [$left, $domain] = explode('@', $text, 2);
            return substr($left, 0, 1) . '***@' . $domain;
        }
        return strlen($text) <= 4 ? '****' : substr($text, 0, 2) . '***' . substr($text, -2);
    }
}
