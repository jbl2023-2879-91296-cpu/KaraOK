<?php

declare(strict_types=1);

namespace KaraOK\Admin\Security;

final class RateLimiter
{
    public function __construct(private readonly string $file, private readonly int $maxAttempts = 5, private readonly int $windowSeconds = 900)
    {
    }

    public function blocked(string $key): bool
    {
        $data = $this->read();
        $cutoff = time() - $this->windowSeconds;
        $attempts = array_filter($data[$this->hash($key)] ?? [], static fn (int $at): bool => $at >= $cutoff);
        return count($attempts) >= $this->maxAttempts;
    }

    public function hit(string $key): void
    {
        $data = $this->read();
        $hash = $this->hash($key);
        $cutoff = time() - $this->windowSeconds;
        $data[$hash] = array_values(array_filter($data[$hash] ?? [], static fn (int $at): bool => $at >= $cutoff));
        $data[$hash][] = time();
        $this->write($data);
    }

    public function clear(string $key): void
    {
        $data = $this->read();
        unset($data[$this->hash($key)]);
        $this->write($data);
    }

    private function hash(string $key): string
    {
        return hash('sha256', strtolower(trim($key)));
    }

    /** @return array<string, list<int>> */
    private function read(): array
    {
        if (!is_file($this->file)) {
            return [];
        }
        $decoded = json_decode((string) file_get_contents($this->file), true);
        return is_array($decoded) ? $decoded : [];
    }

    /** @param array<string, list<int>> $data */
    private function write(array $data): void
    {
        file_put_contents($this->file, json_encode($data, JSON_PRETTY_PRINT), LOCK_EX);
    }
}
