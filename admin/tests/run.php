<?php

declare(strict_types=1);

require dirname(__DIR__) . '/config/bootstrap.php';

use KaraOK\Admin\Config\Environment;
use KaraOK\Admin\Api\AdminApiClient;
use KaraOK\Admin\Services\AnalysisService;
use KaraOK\Admin\Services\SensitiveColumnDetector;

require ADMIN_ROOT . '/app/Views/product.php';
require ADMIN_ROOT . '/app/Views/legacy.php';
require ADMIN_ROOT . '/app/Views/compatibility.php';

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

$tests['CSV formula injection is neutralized including leading whitespace'] = static function (): void {
    foreach (["=SUM(A1)", "+cmd", "-1+2", "@SUM(A1)", "  =1+1", "\t=1+1", "\rpayload"] as $value) {
        assert_same("'" . $value, csv_cell($value));
    }
    assert_same('normal text', csv_cell('normal text'));
    assert_same('', csv_cell(null));
};
$tests['Product tables escape stored HTML and display null as not collected'] = static function (): void {
    $html = data_table('Test', [['username'=>'<script>alert(1)</script>', 'score'=>null]]);
    assert_same(false, str_contains($html, '<script>'));
    assert_same(true, str_contains($html, '&lt;script&gt;'));
    assert_same(true, str_contains($html, 'Not collected'));
};
$tests['Zero baseline and missing metrics are never fabricated'] = static function (): void {
    $html = metric_grid(['average_score'=>null,'assessments'=>0], ['average_score'=>40,'assessments'=>0]);
    assert_same(true, str_contains($html,'Unavailable'));
    assert_same(true, str_contains($html,'no baseline'));
    assert_same(false, str_contains($html,'NAN'));
};
$tests['Privacy masking modifies the actual record rows'] = static function (): void {
    $records = ['rows'=>[['email'=>'ada@example.test']]];
    mask_personal_rows($records,true);
    assert_same('a***@example.test',$records['rows'][0]['email']);
};
$tests['Empty chart and API error give useful states'] = static function (): void {
    assert_same(true,str_contains(trend_chart('Empty',[],'total',['start'=>'2026-09-01','end'=>'2026-09-07']),'No observations'));
    $_GET = [];
    assert_same(true,str_contains(error_view('Offline'),'Retry request'));
    assert_same(false,str_contains(error_view('Offline'),'Live API data'));
};

$tests['Overview uses real legacy data when report route is absent'] = static function (): void {
    $legacy = ['users'=>['total_users'=>7], 'quality'=>['average_quality_score'=>null]];
    $result = \KaraOK\Admin\Services\ReportLoader::load(
        static fn()=>throw new \KaraOK\Admin\Api\AdminApiException('The requested URL was not found on the server.',404),
        static fn()=>['status'=>'ok'], static fn()=>$legacy
    );
    assert_same('legacy', $result['mode']);
    assert_same($legacy, $result['legacy']);
};
$tests['Report fallback never hides authentication or database failures'] = static function (): void {
    foreach ([0,400,401,403,500] as $status) {
        try {
            \KaraOK\Admin\Services\ReportLoader::load(
                static fn()=>throw new \KaraOK\Admin\Api\AdminApiException('failure',$status),
                static fn()=>throw new RuntimeException('Health must not be called'),
                static fn()=>throw new RuntimeException('Legacy must not be called')
            );
            throw new RuntimeException('Expected original error');
        } catch (\KaraOK\Admin\Api\AdminApiException $error) { assert_same($status,$error->status); }
    }
};
$tests['Modern reports retain their payload and skip fallback'] = static function (): void {
    $data = ['meta'=>['timezone'=>'UTC'],'metrics'=>['assessments'=>2]];
    $result = \KaraOK\Admin\Services\ReportLoader::load(
        static fn()=>$data,
        static fn()=>throw new RuntimeException('Unexpected health call'),
        static fn()=>throw new RuntimeException('Unexpected legacy call')
    );
    assert_same($data,$result);
};

$tests['An unhealthy base URL does not activate compatibility mode'] = static function (): void {
    $legacyCalled = false;
    assert_throws(static function () use (&$legacyCalled): void {
        \KaraOK\Admin\Services\ReportLoader::load(
            static fn()=>throw new \KaraOK\Admin\Api\AdminApiException('Missing',404),
            static fn()=>throw new \KaraOK\Admin\Api\AdminApiException('Unauthorized',401),
            static function () use (&$legacyCalled) { $legacyCalled=true; return []; }
        );
    });
    assert_same(false,$legacyCalled);
};
$tests['Compatibility view labels legacy populations and offers working record tools'] = static function (): void {
    $html = compatibility_view(['users'=>['total_users'=>7], 'quality'=>['average_quality_score'=>null]], '/');
    assert_same(true,str_contains($html,'including administrators'));
    assert_same(true,str_contains($html,'Rolling 30-day'));
    assert_same(true,str_contains($html,'/preview?table=user'));
    assert_same(false,str_contains($html,'data-date-form'));
    assert_same(false,str_contains($html,'0.00'));
    $unavailable = compatibility_view(null,'/users');
    assert_same(true,str_contains($unavailable,'Open existing user directory'));
    assert_same(false,str_contains($unavailable,'matching users'));
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
