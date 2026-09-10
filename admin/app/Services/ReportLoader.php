<?php

declare(strict_types=1);

namespace KaraOK\Admin\Services;

use KaraOK\Admin\Api\AdminApiException;

final class ReportLoader
{
    /** A missing feature may fall back only after the API itself is verified. */
    public static function load(callable $report, callable $health, ?callable $legacy = null): array
    {
        try {
            return $report();
        } catch (AdminApiException $error) {
            if ($error->status !== 404) throw $error;
            $connection = $health();
            if (($connection['status'] ?? null) !== 'ok') throw $error;
            return [
                'mode' => 'legacy',
                'legacy' => $legacy !== null ? $legacy() : null,
                'meta' => ['generated_at' => gmdate(DATE_ATOM)],
            ];
        }
    }
}
