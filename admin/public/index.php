<?php

declare(strict_types=1);

use KaraOK\Admin\Api\AdminApiClient;
use KaraOK\Admin\Security\Csrf;
use KaraOK\Admin\Services\AnalysisService;
use KaraOK\Admin\Services\SensitiveColumnDetector;

require dirname(__DIR__) . '/config/bootstrap.php';
require ADMIN_ROOT . '/app/Views/product.php';
require ADMIN_ROOT . '/app/Views/legacy.php';
require ADMIN_ROOT . '/app/Views/layout.php';
require ADMIN_ROOT . '/app/Views/compatibility.php';

$path = rtrim((string) parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH), '/') ?: '/';
$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

if ($path === '/login') {
    if ($auth->check()) redirect('/');
    $error = null;
    if ($method === 'POST') {
        if (!Csrf::valid($_POST['_token'] ?? null)) {
            http_response_code(419);
            $error = 'Your form expired. Refresh the page and try again.';
        } elseif ($auth->attempt((string) ($_POST['username'] ?? ''), (string) ($_POST['password'] ?? ''))) {
            redirect('/');
        } else {
            $error = 'The credentials could not be verified. Try again shortly.';
        }
    }
    login_page($error);
    exit;
}

if (!$auth->check()) redirect('/login');

if ($path === '/logout' && $method === 'POST') {
    csrf_or_fail();
    $auth->logout();
    redirect('/login');
}

$settings = admin_settings();
if ($path === '/settings' && $method === 'POST') {
    csrf_or_fail();
    $settings = ['privacy_mode' => isset($_POST['privacy_mode'])];
    file_put_contents(ADMIN_ROOT . '/storage/private/settings.json', json_encode($settings, JSON_PRETTY_PRINT), LOCK_EX);
    $logger->log('settings.updated', $settings);
    redirect('/settings?saved=1');
}

$title = 'Overview';
$query = report_query();
$reportPages = ['/' => 'overview', '/demographics' => 'demographics', '/usage' => 'usage', '/quality' => 'quality', '/amplifiers' => 'amplifiers', '/operations' => 'operations'];
$content = '';
$viewBufferLevel = ob_get_level();
try {
    if (!$adminApi instanceof AdminApiClient) {
        throw new RuntimeException('Configure ADMIN_API_BASE_URL and ADMIN_API_KEY in admin/.env.');
    }

    if (isset($reportPages[$path])) {
        $section = $reportPages[$path];
        $title = readable($section);
        $dates = array_intersect_key($query, array_flip(['days','start','end']));
        $cacheKey = hash('sha256', $section . json_encode($dates));
        $cached = $_SESSION['product_cache'][$cacheKey] ?? null;
        if (!isset($_GET['refresh']) && $cached && time() - $cached['time'] < 30) {
            $data = $cached['data'];
        } else {
            $data = \KaraOK\Admin\Services\ReportLoader::load(
                static fn() => $adminApi->report($section, $dates),
                static fn() => $adminApi->health(),
                $section === 'overview' ? static fn() => $adminApi->analytics() : null,
            );
            // Bound the session cache without ever caching failures.
            if (count($_SESSION['product_cache'] ?? []) >= 12) $_SESSION['product_cache'] = [];
            $_SESSION['product_cache'][$cacheKey] = ['time'=>time(),'data'=>$data];
        }
        $_SESSION['last_report_refresh'] = $data['meta']['generated_at'];
        $_SESSION['legacy_api'] = ($data['mode'] ?? '') === 'legacy';
        $content = $_SESSION['legacy_api']
            ? compatibility_view($data['legacy'], $path)
            : product_report_view($section, $data);
    } elseif (in_array($path, ['/users', '/assessments'], true)) {
        $kind = ltrim($path, '/');
        $title = readable($kind);
        $data = \KaraOK\Admin\Services\ReportLoader::load(
            static fn() => $adminApi->directory($kind, $query),
            static fn() => $adminApi->health(),
        );
        $_SESSION['legacy_api'] = ($data['mode'] ?? '') === 'legacy';
        if ($_SESSION['legacy_api']) {
            $content = compatibility_view(null, $path);
        } else {
        if (($query['export'] ?? '') === '1') {
            $logger->log('report.exported', ['kind'=>$kind,'rows'=>count($data['rows'])]);
            export_directory($data, $kind);
        }
        $content = directory_view($kind, $data, $query);
        }
    } elseif (in_array($path, ['/users/detail', '/assessments/detail'], true)) {
        $kind = explode('/', $path)[1];
        $title = $kind === 'users' ? 'User details' : 'Assessment details';
        $content = detail_view($kind, $adminApi->detail($kind, (string)($query['id'] ?? ''), $query), $query);
    } elseif ($path === '/record/create') {
        $table = (string) ($_GET['table'] ?? $_POST['table'] ?? '');
        $details = $adminApi->table($table);
        if ($method === 'POST') {
            csrf_or_fail();
            $result = $adminApi->create($table, submitted_values($_POST['values'] ?? [], $details, 'creatable'));
            $logger->log('record.created', ['table' => $table, 'id' => (string) ($result['id'] ?? '')]);
            flash('Record created successfully.');
            redirect('/preview?table=' . urlencode($table));
        }
        $title = 'Create · ' . ($details['label'] ?: $table);
        $content = record_form_view('create', $table, $details, []);
    } elseif ($path === '/record/edit') {
        $table = (string) ($_GET['table'] ?? $_POST['table'] ?? '');
        $id = (string) ($_GET['id'] ?? $_POST['id'] ?? '');
        $details = $adminApi->table($table);
        if ($method === 'POST') {
            csrf_or_fail();
            unset($_SESSION['product_cache']);
            $adminApi->update($table, $id, submitted_values($_POST['values'] ?? [], $details, 'editable'));
            $logger->log('record.updated', ['table' => $table, 'id' => $id]);
            flash('Record updated successfully.');
            redirect('/preview?table=' . urlencode($table));
        }
        $recordSet = $adminApi->records($table, ['filter_column' => $details['primary_key'], 'filter_operator' => 'equals', 'filter_value' => $id]);
        $record = $recordSet['rows'][0] ?? null;
        if (!is_array($record)) throw new RuntimeException('Record not found.');
        $title = 'Edit · ' . ($details['label'] ?: $table);
        $content = record_form_view('edit', $table, $details, $record, $id);
    } elseif ($path === '/record/delete' && $method === 'POST') {
        csrf_or_fail();
        $table = (string) ($_POST['table'] ?? '');
        $id = (string) ($_POST['id'] ?? '');
        unset($_SESSION['product_cache']);
        $adminApi->delete($table, $id);
        $logger->log('record.deleted', ['table' => $table, 'id' => $id]);
        flash('Record deleted successfully.');
        redirect('/preview?table=' . urlencode($table));
    } elseif ($path === '/diagnostics') {
        $title = 'API diagnostics';
        $started = microtime(true);
        $health = $adminApi->health();
        $latency = round((microtime(true) - $started) * 1000, 1);
        $logger->log('admin_api.diagnostics', ['status' => 'ok']);
        $content = diagnostics_view($env, $health, $latency);
    } elseif ($path === '/analytics') {
        $title = 'Analytics';
        $content = analytics_view($adminApi->analytics());
    } elseif ($path === '/databases') {
        redirect('/tables');
    } elseif ($path === '/tables') {
        $title = 'Data catalog';
        $tables = $adminApi->tables();
        $logger->log('admin_api.catalog', ['table_count' => count($tables)]);
        $content = tables_view($tables);
    } elseif ($path === '/table') {
        $table = (string) ($_GET['table'] ?? '');
        $details = $adminApi->table($table);
        $title = (string) ($details['label'] ?: $table);
        $logger->log('table.opened', ['table' => $table]);
        $content = table_view($details);
    } elseif ($path === '/preview') {
        $table = (string) ($_GET['table'] ?? '');
        if ($table === '') redirect('/tables');
        $title = 'Records · ' . $table;
        $records = $adminApi->records($table, $_GET);
        mask_personal_rows($records, (bool) $settings['privacy_mode']);
        $logger->log('records.opened', ['table' => $table, 'page' => (int) ($records['pagination']['page'] ?? 1)]);
        $content = records_view($table, $records, take_flash());
    } elseif ($path === '/relationships') {
        $title = 'Relationships';
        $content = relationships_view($adminApi->relationships());
    } elseif (in_array($path, ['/analysis', '/recommendations', '/report.json'], true)) {
        $tables = $adminApi->tables();
        $columns = $indexes = [];
        foreach ($tables as $tableRow) {
            $name = (string) $tableRow['name'];
            $details = $adminApi->table($name);
            $columns[$name] = $details['columns'];
            $indexes[$name] = $details['indexes'];
        }
        $findings = (new AnalysisService())->analyze($tables, $columns, $indexes);
        $logger->log('schema.analysis', ['finding_count' => count($findings)]);
        if ($path === '/report.json') {
            header('Content-Type: application/json; charset=utf-8');
            header('Content-Disposition: attachment; filename="karaok-admin-schema-report.json"');
            echo json_encode(['database' => 'karaok_db', 'generated_at' => gmdate(DATE_ATOM), 'notice' => 'Structural observations require review before changes.', 'findings' => $findings], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
            exit;
        }
        $title = $path === '/analysis' ? 'Schema health' : 'Recommendations';
        $content = analysis_view($findings, $path === '/recommendations');
    } elseif ($path === '/activity') {
        $title = 'Local console activity';
        $content = activity_view($logger->recent());
    } elseif ($path === '/settings') {
        $title = 'Settings';
        $content = settings_view($settings, isset($_GET['saved']));
    } else {
        $health = $adminApi->health();
        $tables = $adminApi->tables();
        $analytics = $adminApi->analytics();
        $content = dashboard_view($health, $tables, $analytics, $logger->recent(8));
    }
} catch (Throwable $exception) {
    discard_view_buffers($viewBufferLevel);
    $isApiError = $exception instanceof \KaraOK\Admin\Api\AdminApiException;
    $logger->log($isApiError ? 'admin_api.error' : 'console.render_error', ['route' => $path, 'error_class' => $exception::class]);
    $content = error_view($exception->getMessage(), $isApiError);
}

layout($title, $content, $path);

function csrf_or_fail(): void
{
    if (!Csrf::valid($_POST['_token'] ?? null)) {
        http_response_code(419);
        exit('Expired request.');
    }
}

function flash(string $message): void { $_SESSION['_flash'] = $message; }
function take_flash(): ?string
{
    $message = $_SESSION['_flash'] ?? null;
    unset($_SESSION['_flash']);
    return is_string($message) ? $message : null;
}

/** @param mixed $submitted @param array<string,mixed> $details @return array<string,mixed> */
function submitted_values(mixed $submitted, array $details, string $flag): array
{
    $submitted = is_array($submitted) ? $submitted : [];
    $allowed = [];
    foreach ($details['columns'] ?? [] as $column) {
        if (!empty($column[$flag])) $allowed[(string) $column['name']] = true;
    }
    return array_intersect_key($submitted, $allowed);
}
