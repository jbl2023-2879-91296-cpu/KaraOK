<?php

declare(strict_types=1);

namespace KaraOK\Admin\Support;

final class ActivityLogger
{
    public function __construct(private readonly string $file)
    {
    }

    /** @param array<string, scalar|null> $context */
    public function log(string $event, array $context = []): void
    {
        unset($context['password'], $context['sql'], $context['row'], $context['token']);
        $record = [
            'time' => gmdate(DATE_ATOM),
            'event' => preg_replace('/[^a-z0-9_.-]/i', '', $event),
            'admin' => $_SESSION['admin']['username'] ?? null,
            'ip_hash' => hash('sha256', (string) ($_SERVER['REMOTE_ADDR'] ?? 'cli')),
            'context' => $context,
        ];
        file_put_contents($this->file, json_encode($record, JSON_UNESCAPED_SLASHES) . PHP_EOL, FILE_APPEND | LOCK_EX);
    }

    /** @return list<array<string, mixed>> */
    public function recent(int $limit = 100): array
    {
        if (!is_file($this->file)) {
            return [];
        }
        $lines = file($this->file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
        $rows = [];
        foreach (array_slice(array_reverse($lines), 0, max(1, min(500, $limit))) as $line) {
            $decoded = json_decode($line, true);
            if (is_array($decoded)) {
                $rows[] = $decoded;
            }
        }
        return $rows;
    }
}
