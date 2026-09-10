<?php

declare(strict_types=1);

function compatibility_notice(): string
{
    return '<div class="alert mb-5"><strong>Connected to an older administration API.</strong>'
        . '<p class="mt-2">Your API connection and credentials work, but this backend does not expose the new reporting routes. '
        . 'Existing analytics and record tools remain available. The expanded reports require the matching backend update and service restart.</p>'
        . '<p class="mt-2">No deployment or database changes have been performed.</p></div>';
}

function compatibility_view(?array $data, string $path): string
{
    $links = [
        '/users' => ['user', 'Open existing user directory'],
        '/assessments' => ['assessment', 'Open existing assessment records'],
        '/amplifiers' => ['amplifier_profile', 'Open existing amplifier profiles'],
        '/operations' => ['audit_log', 'Open existing audit records'],
        '/quality' => ['audio_analysis_result', 'Open recorded audio analysis'],
    ];
    $html = compatibility_notice();
    if ($data === null) {
        $html .= '<div class="panel p-6"><h2 class="section-title">This page requires the updated backend</h2>'
            . '<p class="muted mt-3">Date-filtered reports, demographic aggregates and the enhanced directories are unavailable on the connected API. '
            . 'The existing record browser has its own search, filters and permitted management actions.</p>';
        if (isset($links[$path])) {
            [$table, $label] = $links[$path];
            $html .= '<a class="btn btn-primary mt-4" href="/preview?table=' . h($table) . '">' . h($label) . '</a> ';
        }
        return $html . '<a class="btn mt-4" href="/">Open available overview</a></div>';
    }
    $html .= '<div class="report-intro"><div><p class="eyebrow">Available backend analytics</p>'
        . '<h2 class="text-2xl font-semibold mt-1">KaraOK overview</h2></div><span class="badge badge-ok">API connected</span></div>'
        . '<p class="coverage-note">Legacy API data: all registered accounts, including administrators. '
        . 'Guest assessments remain device-local. Custom dates and period comparisons are not supported by this endpoint. '
        . 'Account enabled status is not assessment activity. Audio scores measure instrumental quality, not singing.</p>';
    $html .= metric_grid([
        'registered_accounts' => $data['users']['total_users'] ?? null,
        'enabled_accounts' => $data['users']['active_users'] ?? null,
        'unverified_accounts' => $data['users']['unverified_users'] ?? null,
        'administrator_accounts' => $data['users']['admin_users'] ?? null,
    ], [], 'Lifetime · includes administrator accounts');
    $html .= '<div class="report-columns">';
    $html .= data_table('Recorded audio quality', [[
        'scored_results' => $data['quality']['completed_results'] ?? null,
        'average_score' => $data['quality']['average_quality_score'] ?? null,
    ]], 'Lifetime · all non-null result scores, regardless of assessment status. Score scale: 0–100.', false);
    $html .= data_table('API traffic', [[
        'requests' => $data['requests']['requests_24h'] ?? null,
        'server_errors' => $data['requests']['server_errors_24h'] ?? null,
        'mean_duration_ms' => $data['requests']['average_duration_ms'] ?? null,
    ]], 'Rolling 24 hours · all logged traffic, including administration. Server errors: HTTP 500 and above.', false);
    $html .= data_table('Assessment status', $data['assessment_statuses'] ?? [], 'Lifetime · all stored assessments.', false);
    $html .= data_table('Daily assessments', $data['daily_assessments'] ?? [],
        'Rolling 30-day query from the legacy API; current day may be partial. Database session timezone is not reported by this endpoint.', false);
    return $html . '</div><div class="flex flex-wrap gap-3 mt-5">'
        . '<a class="btn" href="/preview?table=user">User records</a>'
        . '<a class="btn" href="/preview?table=assessment">Assessment records</a>'
        . '<a class="btn" href="/diagnostics">API diagnostics</a></div>';
}
