<?php

declare(strict_types=1);

/** Product views deliberately accept already bounded, sanitized API payloads. */
function report_query(): array
{
    $query = array_filter($_GET, static fn($v) => is_string($v));
    $dates = array_intersect_key($query, array_flip(['days', 'start', 'end']));
    if ($dates !== []) $_SESSION['report_dates'] = $dates;
    return array_merge($_SESSION['report_dates'] ?? [], $query);
}

function product_url(string $path, array $extra = []): string
{
    return build_query_url($path, array_merge($_SESSION['report_dates'] ?? [], $extra));
}

function readable(string $key): string { return ucwords(str_replace('_', ' ', $key)); }
function metric_value(mixed $value): string
{
    if ($value === null) return 'Unavailable';
    if (is_array($value)) return h(json_encode($value, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
    return h(is_numeric($value) ? number_format((float)$value, floor((float)$value) == (float)$value ? 0 : 2) : $value);
}
function csv_cell(mixed $value): string
{
    $value = is_array($value) ? json_encode($value, JSON_UNESCAPED_UNICODE) : (string)($value ?? '');
    return preg_match('/^[\s\x00-\x20]*[=+@\-]/u', $value) || preg_match('/^[\t\r\n]/', $value) ? "'" . $value : $value;
}
function export_directory(array $data, string $kind): never
{
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="karaok-' . $kind . '.csv"');
    $out = fopen('php://output', 'w');
    if ($data['rows'] !== []) {
        fputcsv($out, array_keys($data['rows'][0]), ',', '"', '');
        foreach ($data['rows'] as $row) fputcsv($out, array_map('csv_cell', $row), ',', '"', '');
    }
    fclose($out);
    exit;
}
function metric_grid(array $metrics, array $previous = [], string $scope = 'Selected period'): string
{
    ob_start(); ?><div class="metric-grid"><?php foreach ($metrics as $key => $value): ?><article class="stat"><span><?= h(readable($key)) ?></span><strong><?= metric_value($value) ?></strong><small class="muted"><?= h($scope) ?><?php if (array_key_exists($key, $previous) && $value !== null): ?> · <?php if ($previous[$key] === null || (float)$previous[$key] == 0): ?>Comparison unavailable (no baseline)<?php else: ?><?= h(sprintf('%+.1f%%', 100 * ((float)$value-(float)$previous[$key])/(float)$previous[$key])) ?> vs preceding period<?php endif; ?><?php endif; ?></small></article><?php endforeach; ?></div><?php return (string)ob_get_clean();
}

function data_table(string $title, array $rows, string $note = '', bool $links = true): string
{
    ob_start(); ?><article class="panel report-table"><div class="panel-heading"><h2 class="section-title"><?= h($title) ?></h2><?php if ($note): ?><p class="muted text-sm mt-1"><?= h($note) ?></p><?php endif; ?></div><?php if (!$rows): ?><div class="empty-state"><strong>No matching records</strong><p>Try a wider reporting period or different filters.</p></div><?php else: ?><div class="table-scroll" tabindex="0" role="region" aria-label="<?= h($title) ?>"><table><thead><tr><?php foreach (array_keys($rows[0]) as $key): ?><th scope="col"><?= h(readable($key)) ?></th><?php endforeach; ?></tr></thead><tbody><?php foreach ($rows as $row): ?><tr><?php foreach ($row as $key => $value): ?><td><?php if ($links && in_array($key, ['user_id','assessment_id'], true) && $value !== null): ?><a class="text-sky-300 underline underline-offset-4" href="<?= h(product_url($key === 'user_id' ? '/users/detail' : '/assessments/detail', ['id' => $value])) ?>">#<?= h($value) ?></a><?php elseif (str_contains($key, 'status') && $value !== null): ?><span class="badge <?= in_array($value,['Completed','verified','generated'],true) ? 'badge-ok' : ($value === 'Failed' ? 'badge-high' : '') ?>"><?= h($value) ?></span><?php elseif (in_array($key,['verified','is_active'],true)): ?><?= $value ? 'Yes' : 'No' ?><?php else: ?><?= $value === null ? '<span class="muted">Not collected</span>' : (is_array($value) ? '<pre class="json-value">'.h(json_encode($value,JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE)).'</pre>' : h($value)) ?><?php endif; ?></td><?php endforeach; ?></tr><?php endforeach; ?></tbody></table></div><?php endif; ?></article><?php return (string)ob_get_clean();
}

/** SVG uses attributes, not inline styles, to respect the console's CSP. */
function trend_chart(string $title, array $rows, string $value, array $meta, bool $zero = true): string
{
    $map = [];
    foreach ($rows as $row) $map[(string)$row['day']] = $row[$value];
    $days = [];
    for ($d = new DateTimeImmutable($meta['start']); $d <= new DateTimeImmutable($meta['end']); $d = $d->modify('+1 day')) {
        $days[$d->format('Y-m-d')] = $map[$d->format('Y-m-d')] ?? ($zero ? 0 : null);
    }
    $max = max(1, ...array_map(static fn($v) => (float)$v, array_values($days)));
    $points = []; $i = 0; $segments = []; $circles = [];
    foreach ($days as $day => $count) {
        $x = 45 + 610 * $i / max(1, count($days)-1); $i++;
        if ($count === null) { if ($points) $segments[] = implode(' ', $points); $points = []; continue; }
        $y = 170 - 140*(float)$count/$max;
        $points[] = round($x,2) . ',' . round($y,2);
        $circles[] = '<circle cx="'.round($x,2).'" cy="'.round($y,2).'" r="2.5"><title>'.h($day.': '.$count).'</title></circle>';
    }
    if ($points) $segments[] = implode(' ', $points);
    ob_start(); ?><article class="panel p-5"><h2 class="section-title"><?= h($title) ?></h2><p class="muted text-sm mt-1">Daily · UTC · <?= h(readable($value)) ?></p><?php if (!$rows): ?><div class="empty-state">No observations in this period.</div><?php else: ?><svg class="trend-chart" viewBox="0 0 700 210" role="img" aria-label="<?= h($title) ?>. Daily values in the table below."><line x1="45" y1="170" x2="655" y2="170" stroke="#334155"/><line x1="45" y1="30" x2="655" y2="30" stroke="#25324a"/><text x="3" y="35"><?= h(round($max,1)) ?></text><text x="20" y="175">0</text><?php foreach ($segments as $segment): ?><polyline points="<?= h($segment) ?>" fill="none" stroke="#70b8f0" stroke-width="2.5"/><?php endforeach; ?><g fill="#70b8f0"><?= implode('', $circles) ?></g><text x="45" y="200"><?= h($meta['start']) ?></text><text x="655" y="200" text-anchor="end"><?= h($meta['end']) ?></text></svg><details><summary>View daily values</summary><?= data_table('Daily values', array_map(static fn($day,$n)=>['day'=>$day,$value=>$n],array_keys($days),array_values($days)), '', false) ?></details><?php endif; ?></article><?php return (string)ob_get_clean();
}
function bars(string $title, array $rows, string $label, string $value, string $note = ''): string
{
    $max = max(1,...array_map(static fn($r)=>(float)$r[$value],$rows));
    ob_start(); ?><article class="panel p-5"><h2 class="section-title"><?= h($title) ?></h2><p class="muted text-sm mt-1 mb-5"><?= h($note) ?></p><?php if (!$rows): ?><div class="empty-state">No observations in this period.</div><?php endif; ?><?php foreach ($rows as $row): ?><div class="bar-row"><div class="flex justify-between gap-4 text-sm"><span><?= h($row[$label]) ?></span><strong><?= metric_value($row[$value]) ?></strong></div><meter min="0" max="<?= h($max) ?>" value="<?= h($row[$value]) ?>" aria-label="<?= h($row[$label].': '.$row[$value]) ?>"></meter></div><?php endforeach; ?></article><?php return (string)ob_get_clean();
}

function product_report_view(string $section, array $data): string
{
    $meta = $data['meta'];
    ob_start(); ?><div class="report-intro"><div><p class="eyebrow">KaraOK intelligence</p><h2 class="text-2xl font-semibold mt-1"><?= h(['overview'=>'Understand your audio community','demographics'=>'Who uses KaraOK?','usage'=>'From registration to repeat assessment','quality'=>'Instrumental audio quality','amplifiers'=>'Amplifier recommendations','operations'=>'Service operations'][$section]) ?></h2><p class="muted mt-2"><?= h($meta['start'].' – '.$meta['end']) ?> · UTC · Complete days</p></div><span class="badge badge-ok">Live API data</span></div>
    <p class="coverage-note"><?= h($meta['coverage']) ?> Scores evaluate instrumental audio, not singing ability.</p>
    <?php if ($section === 'overview'): ?>
        <?php
        $headline = ['registered_users_lifetime'=>$data['lifetime']['registered_users'],
            'new_registrations'=>$data['metrics']['new_registrations'],
            'assessments'=>$data['metrics']['assessments'],
            'average_audio_quality_score'=>$data['metrics']['average_audio_quality_score']];
        $summary = [];
        foreach ($data['metrics'] as $key=>$value) {
            $summary[] = ['measure'=>readable($key),'selected_period'=>$value,'preceding_period'=>$data['previous'][$key]];
        }
        $accounts = [];
        foreach ($data['lifetime'] as $key=>$value) $accounts[] = ['account_measure'=>readable($key),'users'=>$value];
        ?>
        <?= metric_grid($headline, $data['previous'], 'Period unless labelled lifetime') ?>
        <div class="report-columns">
            <?= trend_chart('Assessment activity', $data['trend'], 'total', $meta) ?>
            <?= trend_chart('New registrations', $data['registrations'], 'total', $meta) ?>
            <?= data_table('Assessment and registration summary', $summary, 'UTC period versus immediately preceding equal period. Rate is percent; processing time is median seconds.', false) ?>
            <?= data_table('Account base', $accounts, 'Lifetime totals for non-administrator users; current activation and verification state.', false) ?>
            <?= bars('Assessment status', $data['statuses'], 'status', 'total', 'All assessment attempts in the selected period') ?>
            <?= bars('Popular genres', $data['genres'], 'genre', 'total', 'Upload genre: top 20, including missing genre') ?>
        </div>
        <?= data_table('Recent assessments', $data['recent'], 'Latest 10 in the selected period') ?>
    <?php elseif ($section === 'demographics'): ?>
        <div class="alert mb-5">Age as of <?= h($meta['age_reference']) ?> UTC. Counts and percentages use all registered non-administrator users, including unknown or invalid birthdays. Ages over 120 are classified as invalid. Participation counts distinct users with any assessment in the selected period.</div>
        <?= bars('Age distribution', $data['ages'], 'age_group', 'users', 'Lifetime account base') ?><?= data_table('Age and participation', $data['ages']) ?>
        <div class="report-columns"><?= data_table('Countries', $data['country'], 'Top 25 · percentage of all non-administrator users') ?><?= data_table('Cities', $data['city'], 'Top 25 · identical city names grouped together · percentage of all users') ?></div>
    <?php elseif ($section === 'usage'): ?>
        <div class="alert mb-5">Active means a registered user started at least one stored assessment, regardless of outcome. Daily, weekly and monthly values cover the trailing 1, 7 and 30 complete days ending <?= h($meta['end']) ?>; other metrics use the selected period.</div>
        <?= metric_grid($data['metrics'], [], 'See activity windows above') ?>
        <div class="report-columns"><?= bars('First-time and returning assessors',$data['assessors'],'assessor_type','users','First-time: earliest stored assessment is within the period. Returning: an earlier assessment exists.') ?><?= trend_chart('Daily assessment-active users',$data['daily'],'active_users',$meta) ?></div>
        <h2 class="section-title mt-6 mb-3">Registration cohort conversion</h2><?= metric_grid($data['conversion'], [], 'Registered in period · observed through period end') ?>
        <p class="coverage-note">Conversion denominator: users registered in the selected period. Numerator: those with a first assessment after registration and before period end. Mean delay excludes unconverted users. Recent registrations have less time to convert; deleted history can undercount participation.</p>
        <?= bars('Assessment activity by weekday',array_map(static fn($r)=>['day'=>['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][(int)$r['weekday']],'assessments'=>$r['assessments']],$data['weekdays']),'day','assessments','UTC · counts, not normalized for the number of each weekday') ?>
        <p class="coverage-note">Retention cohorts are not reported: history completeness and deleted-event coverage are not recorded.</p>
    <?php elseif ($section === 'quality'): ?>
        <div class="report-columns"><?= bars('Score distribution',$data['scores'],'score_band','assessments','All period assessments · missing scores shown separately · scores on 0–100 scale') ?><?= trend_chart('Completed assessment quality',$data['trend'],'average_score',$meta,false) ?></div>
        <?= data_table('Genre comparison',$data['genres'],'Score averages include non-null scores of completed assessments. Failure denominator: all attempts in that genre. Top 25 genres.') ?>
        <a class="btn btn-primary mt-5" href="<?= h(product_url('/assessments')) ?>">Browse assessments</a>
    <?php elseif ($section === 'amplifiers'): ?>
        <?php if (!$data['enabled']): ?><div class="alert">Unavailable: settings recommendations are disabled by the backend feature flag.</div><?php else: ?>
        <?= metric_grid($data['metrics'], [], 'Lifetime') ?><div class="report-columns"><?= bars('Recommendation outcomes',$data['statuses'],'status','recommendations','Generated in the selected period') ?><?= bars('Genre usage',$data['genres'],'genre','recommendations','Top 25 genres') ?></div>
        <?= data_table('Recommended knob positions',$data['positions'],'10-percentage-point buckets normalized to each recorded physical scale. These are recommended values, not proof of physical application.') ?>
        <?= data_table('Versions and confidence',$data['versions'],'Top 50 combinations · provisional confidence is displayed as recorded') ?>
        <?= data_table('Recorded verification outcomes',$data['verified'],'Latest 50 linked outcomes. Difference = verification score minus original score; observational, not causal improvement.') ?>
        <a class="btn mt-5" href="/preview?table=amplifier_profile">Inspect saved profiles</a> <a class="btn mt-5" href="/preview?table=settings_recommendation">Inspect recommendations</a>
        <?php endif; ?>
    <?php else: ?>
        <?= metric_grid($data['metrics']) ?><p class="coverage-note">Source: api_request_log. Includes app, administrator and background requests. Errors are HTTP 400–599; error rate divides these by all logged requests. Latency is the arithmetic mean in milliseconds. This is operational traffic, not engagement.</p>
        <?= data_table('Assessments needing attention',$data['attention'],'Latest 50 failed, pending or processing assessments in the period') ?><?= data_table('Audit history',$data['audit'],'Latest 50 events in the period; sensitive event details omitted') ?>
        <div class="flex flex-wrap gap-3 mt-5"><a class="btn" href="/diagnostics">Connection diagnostics</a><a class="btn" href="/activity">Local console activity</a><a class="btn" href="/preview?table=assessment">Controlled assessment management</a></div>
    <?php endif; ?>
    <details class="panel p-5 mt-6"><summary>Metric definitions and data coverage</summary><div class="prose-notes"><p><?= h($meta['window']) ?> Generated <?= h($meta['generated_at']) ?>. Non-administrator users are defined by user.role = user; deactivated accounts remain in analytics.</p><p>Sources: user, assessment, audio_analysis_result and audio_upload; amplifier_profile and settings_recommendation when enabled; audit_log and api_request_log for operations. Unique assessment keys prevent multiplying rows across result/upload joins.</p><p>Completion rate: completed assessments / all period attempts. Average audio quality: mean of non-null completed result scores (see scored completed assessments for its denominator). Typical processing time: median nonnegative processing_time of completed assessments, in seconds. Null observations are excluded, never treated as zero. A missing denominator or preceding baseline makes comparisons unavailable.</p><p>Preceding comparison covers the same number of complete days immediately before this period. Percent changes are relative changes, including for rates. Deleted records are absent; failed API requests never produce substitute metrics. Reports are queried on demand with a 30-second, per-session cache; Refresh bypasses it.</p></div></details>
    <?php return (string)ob_get_clean();
}

function directory_view(string $kind, array $data, array $query): string
{
    $users = $kind === 'users';
    ob_start(); ?><div class="report-intro"><div><p class="eyebrow"><?= $users ? 'People' : 'Audio assessments' ?></p><h2 class="text-2xl font-semibold mt-1"><?= number_format((int)$data['total']) ?> matching <?= h($kind) ?></h2><p class="muted mt-2"><?= $users ? 'Registration date' : 'Assessment date' ?> follows the top-bar period · UTC. Registered non-administrator users only.</p></div><a class="btn" href="<?= h(product_url('/'.$kind, array_merge($query,['export'=>'1','page'=>1]))) ?>">Export CSV · first 100</a></div>
    <form class="panel directory-filters" method="get"><input type="hidden" name="days" value="<?= h($query['days'] ?? '30') ?>"><?php foreach (['start','end','user_id'] as $f): if (isset($query[$f])): ?><input type="hidden" name="<?= h($f) ?>" value="<?= h($query[$f]) ?>"><?php endif; endforeach; ?>
    <label class="field">Search <?= $users ? 'name, username or ID' : 'user, ID or purpose' ?><input class="input" name="search" maxlength="100" value="<?= h($query['search'] ?? '') ?>" placeholder="Find a user…"></label>
    <label class="field">Status<select class="input" name="status"><option value="">All statuses</option><?php foreach ($users ? ['enabled','deactivated'] : ['Pending','Processing','Completed','Failed'] as $v): ?><option <?= ($query['status'] ?? '') === $v ? 'selected' : '' ?>><?= h($v) ?></option><?php endforeach; ?></select></label>
    <?php if ($users): ?>
    <label class="field">Verification<select class="input" name="verified"><option value="">All accounts</option><option value="yes" <?= ($query['verified'] ?? '') === 'yes' ? 'selected' : '' ?>>Verified</option><option value="no" <?= ($query['verified'] ?? '') === 'no' ? 'selected' : '' ?>>Unverified</option></select></label>
    <?php foreach (['age_min'=>'Minimum age','age_max'=>'Maximum age','country'=>'Country (exact)','city'=>'City (exact)'] as $f=>$label): ?><label class="field"><?= h($label) ?><input class="input" name="<?= h($f) ?>" value="<?= h($query[$f] ?? '') ?>" <?= str_starts_with($f,'age') ? 'type="number" min="0" max="120"' : 'maxlength="100"' ?>></label><?php endforeach; ?>
    <?php else: ?><label class="field">Genre (exact)<input class="input" name="genre" maxlength="50" value="<?= h($query['genre'] ?? '') ?>"></label><?php endif; ?>
    <label class="field">Sort by<select class="input" name="sort"><?php foreach ($users ? ['date','username','id'] : ['date','username','id','score'] as $f): ?><option value="<?= h($f) ?>" <?= ($query['sort'] ?? 'date') === $f ? 'selected' : '' ?>><?= h(readable($f)) ?></option><?php endforeach; ?></select></label><label class="field">Direction<select class="input" name="direction"><option value="DESC">Descending</option><option value="ASC" <?= ($query['direction'] ?? '') === 'ASC' ? 'selected' : '' ?>>Ascending</option></select></label>
    <div class="flex gap-2 items-end"><button class="btn btn-primary">Apply filters</button><a class="btn" href="<?= h(product_url('/'.$kind)) ?>">Reset</a></div></form>
    <?= data_table($users ? 'User directory' : 'Assessment records',$data['rows'],$users ? 'Contacts are always masked. Age reference: '.$data['age_reference'].'. Assessment count and last activity are lifetime.' : 'Duration and processing time are seconds. Audio-quality score uses the recorded 0–100 scale.') ?>
    <nav class="pagination" aria-label="Directory pages"><span class="muted">Page <?= h($data['page']) ?> of <?= h($data['pages']) ?> · 25 per page</span><div class="flex gap-2"><?php if ($data['page']>1): ?><a class="btn" href="<?= h(product_url('/'.$kind,array_merge($query,['page'=>$data['page']-1]))) ?>">Previous</a><?php endif; ?><?php if ($data['page']<$data['pages']): ?><a class="btn" href="<?= h(product_url('/'.$kind,array_merge($query,['page'=>$data['page']+1]))) ?>">Next</a><?php endif; ?></div></nav><?php return (string)ob_get_clean();
}

function detail_view(string $kind, array $data, array $query): string
{
    $profile=$data['profile'];$users=$kind==='users';
    ob_start(); ?><a class="text-sky-300 underline" href="<?= h(product_url('/'.$kind)) ?>">← Back to <?= h($kind) ?></a><div class="report-intro mt-5"><h2 class="text-2xl font-semibold"><?= h($users ? $profile['username'] : 'Assessment #'.$profile['assessment_id']) ?></h2><a class="btn" href="/record/edit?table=<?= $users ? 'user' : 'assessment' ?>&amp;id=<?= h($users ? $profile['user_id'] : $profile['assessment_id']) ?>"><?= $users ? 'Manage activation' : 'Manage status' ?></a></div>
    <article class="panel p-5"><h2 class="section-title"><?= $users ? 'Profile' : 'Recorded assessment details' ?></h2><?php if ($users): ?><p class="muted text-sm mt-2">Age as of <?= h($data['age_reference']) ?> UTC ? contacts masked</p><?php endif; ?><dl class="profile-details"><?php foreach ($profile as $key=>$value): ?><dt><?= h(readable($key)) ?></dt><dd><?= $value === null ? '<span class="muted">Not collected</span>' : (is_array($value) ? '<pre class="json-value">'.h(json_encode($value,JSON_PRETTY_PRINT)).'</pre>' : h($value)) ?></dd><?php endforeach; ?></dl></article>
    <?php if ($users): ?>
    <div class="report-columns"><?= trend_chart('Audio-quality score trend',$data['scores'],'average_score',$data['meta'],false) ?><?= bars('Genre preferences',$data['genres'],'genre','assessments','Selected period · upload genres') ?></div><?= data_table('Saved amplifier profiles',$data['profiles'],'Lifetime · latest 50. Availability follows the recommendations feature flag. Positions are recorded values.') ?>
    <a class="btn btn-primary mt-5" href="<?= h(product_url('/assessments',['user_id'=>$profile['user_id']])) ?>">Browse assessment history</a>
    <?php else: ?><div class="alert mt-5">Audio quality is scored on 0–100. Duration and processing time: seconds. Noise: dBFS. Distortion: analyzer estimated score, not THD percent. Bass and treble: energy percentages. Sharpness: normalized score. Flatness: mean spectral flatness. Loudness stores integrated LUFS with a dBFS fallback; the stored field does not identify which unit was used.</div><p class="coverage-note">Recorded grading and profile versions are shown above when present. Playable audio and report images are not exposed by the administration API.</p><?php endif; ?>
    <?php return (string)ob_get_clean();
}

/** @param array<string,mixed> $records */
function mask_personal_rows(array &$records, bool $privacy): void
{
    if (!$privacy) return;
    $detector = new \KaraOK\Admin\Services\SensitiveColumnDetector();
    if (!isset($records['rows'])) return;
    foreach ($records['rows'] as &$row) {
        foreach ($row as $column => &$value) {
            $category = $detector->category((string) $column);
            if ($category !== null) $value = $detector->mask($value, $category, true);
        }
        unset($value);
    }
    unset($row);
}

