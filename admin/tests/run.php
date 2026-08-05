<?php

declare(strict_types=1);

require dirname(__DIR__) . '/config/bootstrap.php';

use KaraOK\Admin\Config\Environment;
use KaraOK\Admin\Api\AdminApiClient;
use KaraOK\Admin\Services\AnalysisService;
use KaraOK\Admin\Services\SensitiveColumnDetector;

$tests = [];
$tests['API client accepts HTTPS endpoints'] = static function (): void {
    $file = tempnam(sys_get_temp_dir(), 'karaok-api-env-');
    file_put_contents($file, "ADMIN_API_BASE_URL=https://example.test/api/admin/data\nADMIN_API_KEY=test-key-that-is-longer-than-thirty-two-characters\n");
    $client = new AdminApiClient(new Environment($file));
    assert_same(AdminApiClient::class, $client::class);
    unlink($file);
};
$tests['API client refuses insecure remote HTTP endpoints'] = static function (): void {
    $file = tempnam(sys_get_temp_dir(), 'karaok-api-env-');
    file_put_contents($file, "ADMIN_API_BASE_URL=http://example.test/api/admin/data\nADMIN_API_KEY=test-key-that-is-longer-than-thirty-two-characters\n");
    assert_throws(static fn () => new AdminApiClient(new Environment($file)));
    unlink($file);
};
$tests['sensitive detector separates credentials and personal values'] = static function (): void {
    $detector = new SensitiveColumnDetector();
    assert_same('credential', $detector->category('password_hash'));
    assert_same('credential', $detector->category('refresh_token'));
    assert_same('personal', $detector->category('email_address'));
    assert_same(null, $detector->category('assessment_id'));
};
$tests['credential values are always redacted'] = static function (): void {
    $detector = new SensitiveColumnDetector();
    assert_same('[REDACTED]', $detector->mask('never-show-this', 'credential', false));
    assert_same('j***@example.test', $detector->mask('jr@example.test', 'personal', true));
};
$tests['environment parser reads booleans and integers'] = static function (): void {
    $file = tempnam(sys_get_temp_dir(), 'karaok-env-');
    file_put_contents($file, "FEATURE=true\nCOUNT=7\nQUOTED=\"safe value\"\n");
    $env = new Environment($file);
    assert_same(true, $env->bool('FEATURE'));
    assert_same(7, $env->int('COUNT', 1));
    assert_same('safe value', $env->get('QUOTED'));
    unlink($file);
};
$tests['analysis labels structural evidence conservatively'] = static function (): void {
    $tables = [['name' => 'events', 'estimated_rows' => 100001]];
    $columns = ['events' => [['name' => 'payload', 'data_type' => 'longtext', 'column_key' => '']]];
    $findings = (new AnalysisService())->analyze($tables, $columns, ['events' => []]);
    assert_same('confirmed', $findings[0]['confidence']);
    assert_same('inferred', $findings[2]['confidence']);
};

$failed = 0;
foreach ($tests as $name => $test) {
    try {
        $test();
        echo "PASS {$name}\n";
    } catch (Throwable $error) {
        $failed++;
        fwrite(STDERR, "FAIL {$name}: {$error->getMessage()}\n");
    }
}
echo sprintf("\n%d tests, %d failed\n", count($tests), $failed);
exit($failed === 0 ? 0 : 1);

function assert_same(mixed $expected, mixed $actual): void
{
    if ($expected !== $actual) {
        throw new RuntimeException('Expected ' . var_export($expected, true) . ', got ' . var_export($actual, true));
    }
}

function assert_throws(callable $callback): void
{
    try {
        $callback();
    } catch (Throwable) {
        return;
    }
    throw new RuntimeException('Expected an exception.');
}
