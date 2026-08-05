<?php

declare(strict_types=1);

namespace KaraOK\Admin\Config;

final class Environment
{
    /** @var array<string, string> */
    private array $values = [];

    public function __construct(string $file)
    {
        if (!is_file($file)) {
            return;
        }

        foreach (file($file, FILE_IGNORE_NEW_LINES) ?: [] as $line) {
            $line = trim($line);
            if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) {
                continue;
            }
            [$key, $value] = array_map('trim', explode('=', $line, 2));
            if ($key === '' || !preg_match('/^[A-Z][A-Z0-9_]*$/', $key)) {
                continue;
            }
            if (strlen($value) >= 2 && (($value[0] === '"' && str_ends_with($value, '"')) || ($value[0] === "'" && str_ends_with($value, "'")))) {
                $value = substr($value, 1, -1);
            }
            $this->values[$key] = $value;
        }
    }

    public function get(string $key, string $default = ''): string
    {
        return $_ENV[$key] ?? getenv($key) ?: ($this->values[$key] ?? $default);
    }

    public function bool(string $key, bool $default = false): bool
    {
        return filter_var($this->get($key, $default ? 'true' : 'false'), FILTER_VALIDATE_BOOL);
    }

    public function int(string $key, int $default): int
    {
        $value = filter_var($this->get($key, (string) $default), FILTER_VALIDATE_INT);
        return $value === false ? $default : $value;
    }
}
