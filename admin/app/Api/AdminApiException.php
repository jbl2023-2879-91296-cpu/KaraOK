<?php

declare(strict_types=1);

namespace KaraOK\Admin\Api;

use RuntimeException;

final class AdminApiException extends RuntimeException
{
    public function __construct(string $message, public readonly int $status = 0)
    {
        parent::__construct($message, $status);
    }
}
