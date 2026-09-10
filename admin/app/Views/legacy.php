<?php

declare(strict_types=1);

use KaraOK\Admin\Security\Csrf;

function login_page(?string $error): void
{
    ?><!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Sign in · KaraOK Admin Console</title><link rel="stylesheet" href="/build/app.css"></head><body class="min-h-screen bg-slate-950 text-slate-100 grid place-items-center p-6"><main class="panel w-full max-w-md p-8"><div class="mb-8"><p class="eyebrow">Local administration</p><h1 class="text-3xl font-semibold">KaraOK Admin Console</h1><p class="muted mt-2">Secure analytics and record management through the Data Administration API.</p></div><?php if ($error): ?><div class="alert alert-error mb-5"><?= h($error) ?></div><?php endif; ?><form method="post" action="/login" class="space-y-5"><input type="hidden" name="_token" value="<?= h(Csrf::token()) ?>"><label class="field">Username<input class="input" name="username" autocomplete="username" required autofocus></label><label class="field">Password<input class="input" type="password" name="password" autocomplete="current-password" required></label><button class="btn btn-primary w-full" type="submit">Sign in</button></form></main></body></html><?php
}

/** @param array<string,mixed> $health @param list<array<string,mixed>> $tables @param array<string,mixed> $analytics @param list<array<string,mixed>> $activity */
function dashboard_view(array $health, array $tables, array $analytics, array $activity): string
{
    $rows = array_sum(array_map(static fn (array $t): int => (int) ($t['estimated_rows'] ?? 0), $tables));
    ob_start(); ?><div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><div class="stat"><span>API status</span><strong class="text-emerald-300"><?= h($health['status'] ?? 'unknown') ?></strong></div><div class="stat"><span>Managed tables</span><strong><?= count($tables) ?></strong></div><div class="stat"><span>Estimated records</span><strong><?= number_format($rows) ?></strong></div><div class="stat"><span>Active users</span><strong><?= number_format((int) ($analytics['users']['active_users'] ?? 0)) ?></strong></div></div><div class="panel mt-6 p-6"><div class="flex justify-between items-center"><div><p class="eyebrow">Connection</p><h2 class="section-title">Backend administration API is working</h2></div><span class="badge badge-ok">HTTPS API</span></div><p class="muted mt-2">The local console does not connect to MySQL and does not require an SSH tunnel. CRUD rules and audit logging are enforced by Flask.</p><div class="mt-5 flex gap-3 flex-wrap"><a class="btn btn-primary" href="/analytics">View analytics</a><a class="btn" href="/tables">Manage records</a></div></div><div class="panel mt-6 p-6"><h2 class="section-title">Recent local activity</h2><?= activity_table($activity) ?></div><?php return (string) ob_get_clean();
}

/** @param array<string,mixed> $health */
function diagnostics_view(object $env, array $health, float $latency): string
{
    ob_start(); ?><div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><div class="stat"><span>Status</span><strong class="text-emerald-300"><?= h($health['status'] ?? 'unknown') ?></strong></div><div class="stat"><span>Round trip</span><strong><?= h($latency) ?> ms</strong></div><div class="stat"><span>Managed database</span><strong><?= h($health['database_name'] ?? '—') ?></strong></div><div class="stat"><span>Tables</span><strong><?= number_format((int) ($health['table_count'] ?? 0)) ?></strong></div></div><div class="panel p-6 mt-6"><h2 class="section-title">Verified through HTTPS</h2><dl class="details"><dt>API endpoint</dt><dd><?= h($env->get('ADMIN_API_BASE_URL')) ?></dd><dt>MySQL server</dt><dd><?= h($health['server_version'] ?? '—') ?></dd><dt>API credential</dt><dd>Accepted (key never displayed)</dd><dt>Connection type</dt><dd>Data Administration API</dd></dl></div><?php return (string) ob_get_clean();
}

/** @param array<string,mixed> $data */
function analytics_view(array $data): string
{
    ob_start(); ?><div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4"><div class="stat"><span>Total users</span><strong><?= number_format((int) ($data['users']['total_users'] ?? 0)) ?></strong></div><div class="stat"><span>Active users</span><strong><?= number_format((int) ($data['users']['active_users'] ?? 0)) ?></strong></div><div class="stat"><span>Completed results</span><strong><?= number_format((int) ($data['quality']['completed_results'] ?? 0)) ?></strong></div><div class="stat"><span>Average quality</span><strong><?= h($data['quality']['average_quality_score'] ?? '—') ?></strong></div></div><div class="grid gap-6 xl:grid-cols-2 mt-6"><div class="panel overflow-x-auto"><h2 class="section-title p-5">Assessment status</h2><table><thead><tr><th>Status</th><th>Total</th></tr></thead><tbody><?php foreach ($data['assessment_statuses'] ?? [] as $row): ?><tr><td><?= h($row['status']) ?></td><td><?= number_format((int) $row['total']) ?></td></tr><?php endforeach; ?></tbody></table></div><div class="panel p-5"><h2 class="section-title">API activity in 24 hours</h2><dl class="details"><dt>Requests</dt><dd><?= number_format((int) ($data['requests']['requests_24h'] ?? 0)) ?></dd><dt>Average duration</dt><dd><?= h($data['requests']['average_duration_ms'] ?? '—') ?> ms</dd><dt>Server errors</dt><dd><?= number_format((int) ($data['requests']['server_errors_24h'] ?? 0)) ?></dd></dl></div></div><div class="panel overflow-x-auto mt-6"><h2 class="section-title p-5">Assessments during the last 30 days</h2><table><thead><tr><th>Date</th><th>Total</th></tr></thead><tbody><?php foreach ($data['daily_assessments'] ?? [] as $row): ?><tr><td><?= h($row['day']) ?></td><td><?= number_format((int) $row['total']) ?></td></tr><?php endforeach; ?></tbody></table></div><?php return (string) ob_get_clean();
}

/** @param list<array<string,mixed>> $tables */
function tables_view(array $tables): string
{
    ob_start(); ?><div class="alert mb-5">Capabilities are intentionally table-specific. The API never accepts arbitrary SQL or schema changes.</div><div class="panel overflow-x-auto"><table><thead><tr><th>Data area</th><th>Table</th><th>Estimated rows</th><th>Storage</th><th>Capabilities</th><th></th></tr></thead><tbody><?php foreach ($tables as $table): ?><tr><td class="font-semibold"><?= h($table['label']) ?></td><td><code><?= h($table['name']) ?></code></td><td><?= number_format((int) $table['estimated_rows']) ?></td><td><?= h(bytes((int) $table['data_bytes'] + (int) $table['index_bytes'])) ?></td><td><?= capability_badges($table['capabilities']) ?></td><td class="whitespace-nowrap"><a class="btn" href="/table?table=<?= urlencode((string) $table['name']) ?>">Structure</a><?php if (!empty($table['capabilities']['read'])): ?> <a class="btn" href="/preview?table=<?= urlencode((string) $table['name']) ?>">Records</a><?php endif; ?></td></tr><?php endforeach; ?></tbody></table></div><?php return (string) ob_get_clean();
}

/** @param array<string,bool> $capabilities */
function capability_badges(array $capabilities): string
{
    $out = [];
    foreach (['read', 'create', 'update', 'delete'] as $name) if (!empty($capabilities[$name])) $out[] = '<span class="badge badge-' . ($name === 'delete' ? 'high' : 'ok') . '">' . h($name) . '</span>';
    return implode(' ', $out) ?: '<span class="muted">Metadata only</span>';
}

/** @param array<string,mixed> $details */
function table_view(array $details): string
{
    $table = (string) $details['table']; ob_start(); ?><div class="mb-5 flex gap-3 flex-wrap"><?php if (!empty($details['capabilities']['read'])): ?><a class="btn btn-primary" href="/preview?table=<?= urlencode($table) ?>">View records</a><?php endif; ?><?php if (!empty($details['capabilities']['create'])): ?><a class="btn" href="/record/create?table=<?= urlencode($table) ?>">Create record</a><?php endif; ?><?= capability_badges($details['capabilities']) ?></div><div class="panel overflow-x-auto"><h2 class="section-title p-5">Columns</h2><table><thead><tr><th>#</th><th>Name</th><th>Type</th><th>Nullable</th><th>Key</th><th>API behavior</th></tr></thead><tbody><?php foreach ($details['columns'] as $c): ?><tr><td><?= h($c['position']) ?></td><td class="font-semibold"><?= h($c['name']) ?></td><td><?= h($c['column_type']) ?></td><td><?= h($c['nullable']) ?></td><td><?= h($c['column_key'] ?: '—') ?></td><td><?= !empty($c['hidden']) ? '<span class="badge badge-high">hidden</span>' : (!empty($c['editable']) ? '<span class="badge badge-ok">editable</span>' : '<span class="muted">read only</span>') ?></td></tr><?php endforeach; ?></tbody></table></div><div class="panel overflow-x-auto mt-6"><h2 class="section-title p-5">Indexes</h2><table><thead><tr><th>Name</th><th>Column</th><th>Sequence</th><th>Unique</th><th>Type</th></tr></thead><tbody><?php foreach ($details['indexes'] as $i): ?><tr><td><?= h($i['name']) ?></td><td><?= h($i['column_name']) ?></td><td><?= h($i['sequence']) ?></td><td><?= (int) $i['non_unique'] === 0 ? 'Yes' : 'No' ?></td><td><?= h($i['index_type']) ?></td></tr><?php endforeach; ?></tbody></table></div><?php return (string) ob_get_clean();
}

/** @param array<string,mixed> $records */
function records_view(string $table, array $records, ?string $flash): string
{
    $query = $_GET; $pagination = $records['pagination']; $pk = (string) $records['primary_key']; ob_start(); if ($flash): ?><div class="alert alert-ok mb-5"><?= h($flash) ?></div><?php endif; ?><div class="flex justify-between gap-3 mb-5 flex-wrap"><div class="alert">Credential fields and binary contents are removed by the backend before transmission.</div><?php if (!empty($records['capabilities']['create'])): ?><a class="btn btn-primary" href="/record/create?table=<?= urlencode($table) ?>">Create record</a><?php endif; ?></div><form class="panel p-5 mb-6 grid gap-3 lg:grid-cols-[1fr_180px_150px_1fr_auto]" method="get"><input type="hidden" name="table" value="<?= h($table) ?>"><input class="input" name="search" placeholder="Search text fields" value="<?= h($_GET['search'] ?? '') ?>"><select class="input" name="filter_column"><option value="">Filter column</option><?php foreach ($records['columns'] as $column): ?><option <?= ($_GET['filter_column'] ?? '') === $column['name'] ? 'selected' : '' ?> value="<?= h($column['name']) ?>"><?= h($column['name']) ?></option><?php endforeach; ?></select><select class="input" name="filter_operator"><option value="contains">Contains</option><option value="equals" <?= ($_GET['filter_operator'] ?? '') === 'equals' ? 'selected' : '' ?>>Equals</option></select><input class="input" name="filter_value" placeholder="Filter value" value="<?= h($_GET['filter_value'] ?? '') ?>"><button class="btn btn-primary">Apply</button><label class="check lg:col-span-5"><input type="checkbox" name="confirm_search" value="1" <?= ($_GET['confirm_search'] ?? '') === '1' ? 'checked' : '' ?>><span><strong>Confirm large-table search</strong><small>Required only for text searches on tables estimated at 100,000 records or more.</small></span></label></form><div class="panel overflow-x-auto"><table><thead><tr><?php foreach ($records['columns'] as $column): ?><th><a href="<?= h(build_query_url('/preview', array_merge($query, ['table' => $table, 'sort' => $column['name'], 'direction' => ($_GET['sort'] ?? '') === $column['name'] && ($_GET['direction'] ?? 'DESC') === 'ASC' ? 'DESC' : 'ASC', 'page' => 1]))) ?>"><?= h($column['name']) ?></a></th><?php endforeach; ?><th>Actions</th></tr></thead><tbody><?php foreach ($records['rows'] as $row): $id = (string) ($row[$pk] ?? ''); ?><tr><?php foreach ($records['columns'] as $column): $value = $row[$column['name']] ?? null; ?><td><?= $value === null ? '<span class="null">NULL</span>' : h(is_array($value) ? json_encode($value) : $value) ?></td><?php endforeach; ?><td class="whitespace-nowrap"><?php if (!empty($records['capabilities']['update'])): ?><a class="btn" href="/record/edit?table=<?= urlencode($table) ?>&id=<?= urlencode($id) ?>">Edit</a><?php endif; ?><?php if (!empty($records['capabilities']['delete'])): ?> <form class="inline" method="post" action="/record/delete"><input type="hidden" name="_token" value="<?= h(Csrf::token()) ?>"><input type="hidden" name="table" value="<?= h($table) ?>"><input type="hidden" name="id" value="<?= h($id) ?>"><button class="btn" data-confirm="Permanently delete <?= h($table) ?> record <?= h($id) ?>? Related records may also be removed." type="submit">Delete</button></form><?php endif; ?></td></tr><?php endforeach; ?><?php if (($records['rows'] ?? []) === []): ?><tr><td colspan="<?= count($records['columns']) + 1 ?>" class="muted text-center">No records matched.</td></tr><?php endif; ?></tbody></table></div><div class="flex justify-between mt-5"><span class="muted">Page <?= (int) $pagination['page'] ?> of <?= (int) $pagination['pages'] ?> · <?= number_format((int) $pagination['total']) ?> records</span><div><?php if ((int) $pagination['page'] > 1): ?><a class="btn" href="<?= h(build_query_url('/preview', array_merge($query, ['table' => $table, 'page' => (int) $pagination['page'] - 1]))) ?>">Previous</a><?php endif; ?> <?php if ((int) $pagination['page'] < (int) $pagination['pages']): ?><a class="btn" href="<?= h(build_query_url('/preview', array_merge($query, ['table' => $table, 'page' => (int) $pagination['page'] + 1]))) ?>">Next</a><?php endif; ?></div></div><?php return (string) ob_get_clean();
}

/** @param array<string,mixed> $details @param array<string,mixed> $record */
function record_form_view(string $mode, string $table, array $details, array $record, string $id = ''): string
{
    $flag = $mode === 'create' ? 'creatable' : 'editable'; ob_start(); ?><div class="alert mb-5"><?= $mode === 'create' ? 'Create a validated record through the backend API.' : 'Only fields approved by the backend policy can be changed.' ?></div><form method="post" class="panel p-6 max-w-3xl space-y-5"><input type="hidden" name="_token" value="<?= h(Csrf::token()) ?>"><input type="hidden" name="table" value="<?= h($table) ?>"><?php if ($id !== ''): ?><input type="hidden" name="id" value="<?= h($id) ?>"><?php endif; ?><?php foreach ($details['columns'] as $column): if (empty($column[$flag])) continue; $name = (string) $column['name']; ?><label class="field"><?= h(str_replace('_', ' ', ucfirst($name))) ?><span class="muted"> · <?= h($column['column_type']) ?></span><?= field_control($column, $record[$name] ?? '') ?></label><?php endforeach; ?><div class="flex gap-3"><button class="btn btn-primary" type="submit"><?= $mode === 'create' ? 'Create record' : 'Save changes' ?></button><a class="btn" href="/preview?table=<?= urlencode($table) ?>">Cancel</a></div></form><?php return (string) ob_get_clean();
}

/** @param array<string,mixed> $column */
function field_control(array $column, mixed $value): string
{
    $name = h((string) $column['name']);
    if (str_starts_with((string) $column['column_type'], 'tinyint(1)')) {
        return '<select class="input" name="values[' . $name . ']"><option value="1"' . ((string) $value === '1' ? ' selected' : '') . '>Enabled / true</option><option value="0"' . ((string) $value === '0' ? ' selected' : '') . '>Disabled / false</option></select>';
    }
    if ((string) $column['data_type'] === 'enum' && preg_match_all("/'((?:[^'\\\\]|\\\\.)*)'/", (string) $column['column_type'], $matches)) {
        $html = '<select class="input" name="values[' . $name . ']">';
        foreach ($matches[1] as $option) $html .= '<option value="' . h($option) . '"' . ((string) $value === $option ? ' selected' : '') . '>' . h($option) . '</option>';
        return $html . '</select>';
    }
    $type = in_array((string) $column['data_type'], ['int', 'bigint', 'smallint', 'tinyint', 'float', 'double', 'decimal'], true) ? 'number' : 'text';
    $step = in_array((string) $column['data_type'], ['float', 'double', 'decimal'], true) ? ' step="any"' : '';
    return '<input class="input" type="' . $type . '"' . $step . ' name="values[' . $name . ']" value="' . h($value) . '" required>';
}

/** @param list<array<string,mixed>> $relations */
function relationships_view(array $relations): string
{
    ob_start(); ?><div class="alert mb-5">Confirmed foreign-key relationships reported by the backend API.</div><div class="panel overflow-x-auto"><table><thead><tr><th>Constraint</th><th>Child</th><th>Parent</th><th>On update</th><th>On delete</th></tr></thead><tbody><?php foreach ($relations as $r): ?><tr><td><?= h($r['name']) ?></td><td><?= h($r['child_table']) ?>.<?= h($r['child_column']) ?></td><td><?= h($r['parent_table']) ?>.<?= h($r['parent_column']) ?></td><td><?= h($r['update_rule']) ?></td><td><?= h($r['delete_rule']) ?></td></tr><?php endforeach; ?></tbody></table></div><?php return (string) ob_get_clean();
}

/** @param list<array<string,string>> $findings */
function analysis_view(array $findings, bool $recommendations): string
{
    ob_start(); ?><div class="flex gap-3 mb-5"><a class="btn" href="/report.json">Download JSON report</a></div><div class="alert mb-5"><?= $recommendations ? 'Recommendations require review; this page never changes the schema.' : 'Confirmed findings come from API metadata. Inferred findings must be verified.' ?></div><div class="space-y-3"><?php foreach ($findings as $f): ?><article class="panel p-5 flex gap-4"><span class="badge badge-<?= h($f['severity']) ?>"><?= h($f['severity']) ?></span><div><h2 class="font-semibold"><?= h($f['title']) ?> <span class="badge"><?= h($f['confidence']) ?></span></h2><p class="muted text-sm mt-1"><?= h($f['scope']) ?></p><p class="mt-3"><?= h($f['recommendation']) ?></p></div></article><?php endforeach; ?></div><?php return (string) ob_get_clean();
}

/** @param list<array<string,mixed>> $rows */
function activity_view(array $rows): string { return '<div class="panel p-5">' . activity_table($rows) . '</div>'; }
/** @param list<array<string,mixed>> $rows */
function activity_table(array $rows): string
{
    ob_start(); ?><div class="overflow-x-auto mt-4"><table><thead><tr><th>Time (UTC)</th><th>Event</th><th>Admin</th><th>Context</th></tr></thead><tbody><?php foreach ($rows as $row): ?><tr><td><?= h($row['time'] ?? '') ?></td><td><?= h($row['event'] ?? '') ?></td><td><?= h($row['admin'] ?? '—') ?></td><td><code><?= h(json_encode($row['context'] ?? [], JSON_UNESCAPED_SLASHES)) ?></code></td></tr><?php endforeach; ?></tbody></table></div><?php return (string) ob_get_clean();
}

/** @param array<string,bool> $settings */
function settings_view(array $settings, bool $saved): string
{
    ob_start(); if ($saved): ?><div class="alert alert-ok mb-5">Settings saved locally.</div><?php endif; ?><form class="panel p-6 max-w-2xl space-y-5" method="post"><input type="hidden" name="_token" value="<?= h(Csrf::token()) ?>"><label class="check"><input type="checkbox" name="privacy_mode" <?= $settings['privacy_mode'] ? 'checked' : '' ?>><span><strong>Privacy Mode</strong><small>Mask likely personal fields after the API response arrives.</small></span></label><button class="btn btn-primary">Save local settings</button></form><?php return (string) ob_get_clean();
}

function error_view(string $message, bool $apiFailure = true): string
{
    $title = $apiFailure ? 'Administration API request failed.' : 'Console page could not be rendered.';
    $hint = $apiFailure
        ? 'Check API diagnostics for connectivity and backend errors.'
        : 'A local console error interrupted this page. Navigation remains available; retry after updating the console.';
    return '<div class="alert alert-error" role="alert"><strong>' . h($title) . '</strong><p class="mt-2">'
        . h($message) . '</p><p class="mt-3">' . h($hint)
        . '</p><a class="btn mt-4" href="' . h(build_query_url((string)parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH), array_merge(array_filter($_GET, 'is_string'), ['refresh'=>'1'])))
        . '">Retry request</a></div>';
}

/** @param array<string,mixed> $params */
function build_query_url(string $path, array $params): string
{
    foreach ($params as $key => $value) if ($value === '' || $value === null) unset($params[$key]);
    return $path . '?' . http_build_query($params);
}
