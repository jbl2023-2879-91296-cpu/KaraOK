<?php

declare(strict_types=1);

function layout(string $title, string $content, string $path): void
{
    $links = [
        '/' => 'Overview', '/users' => 'Users', '/demographics' => 'Demographics',
        '/usage' => 'Usage & engagement', '/assessments' => 'Assessments',
        '/quality' => 'Audio quality', '/amplifiers' => 'Amplifier settings',
        '/operations' => 'Operations & audit',
    ];
    $advanced = [
        '/tables' => 'Data catalog', '/relationships' => 'Relationships',
        '/analysis' => 'Schema health', '/recommendations' => 'Schema recommendations',
        '/analytics' => 'Legacy analytics', '/diagnostics' => 'API diagnostics',
        '/activity' => 'Local activity',
    ];
    $dates = $_SESSION['report_dates'] ?? [];
    $end = $dates['end'] ?? gmdate('Y-m-d', strtotime('yesterday UTC'));
    $preset = in_array((string)($dates['days'] ?? '30'), ['7','30','90'], true) ? (int)($dates['days'] ?? 30) : 30;
    $start = $dates['start'] ?? gmdate('Y-m-d', strtotime($end . ' UTC') - ($preset-1)*86400);
    $custom = ($dates['days'] ?? '') === 'custom' || ((strtotime($end) - strtotime($start))/86400 + 1) != $preset;
    $preserved = array_diff_key(array_filter($_GET, 'is_string'), array_flip(['days','start','end','refresh','export','page']));
    ?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title><?= h($title) ?> · KaraOK Admin Console</title>
    <link rel="stylesheet" href="/build/app.css">
</head>
<body>
<a class="skip-link" href="#main-content">Skip to content</a>
<div class="console-shell">
    <aside id="console-sidebar" data-sidebar class="console-sidebar hidden lg:flex">
        <a href="/" class="brand">
            <span class="brand-mark" aria-hidden="true">K</span>
            <span><strong>KaraOK</strong><small>ADMIN CONSOLE</small></span>
        </a>
        <nav aria-label="Main navigation" class="space-y-1 flex-1">
            <p class="nav-caption">Workspace</p>
            <?php foreach ($links as $url => $label):
                $active = $path === $url || ($url !== '/' && str_starts_with($path, $url . '/')); ?>
                <a class="nav-link <?= $active ? 'nav-active' : '' ?>" <?= $active ? 'aria-current="page"' : '' ?> href="<?= h(product_url($url)) ?>"><?= h($label) ?></a>
            <?php endforeach; ?>
            <details class="advanced-nav" <?= isset($advanced[$path]) ? 'open' : '' ?>>
                <summary>Advanced</summary>
                <?php foreach ($advanced as $url => $label): ?>
                    <a class="nav-link <?= $path === $url ? 'nav-active' : '' ?>" href="<?= h($url) ?>"><?= h($label) ?></a>
                <?php endforeach; ?>
            </details>
        </nav>
        <div class="sidebar-footer">
            <span class="status-dot" aria-hidden="true"></span> Secured administration
            <p>PHP console · HTTPS API</p>
        </div>
    </aside>
    <main class="console-main">
        <header class="console-header">
            <div class="flex items-center gap-3">
                <button data-sidebar-toggle aria-controls="console-sidebar" aria-expanded="false" class="btn lg:hidden" type="button">Menu</button>
                <div>
                    <p class="eyebrow">Workspace / <?= isset($advanced[$path]) ? 'Advanced' : 'Administration' ?></p>
                    <h1 class="text-xl font-semibold mt-1"><?= h($title) ?></h1>
                </div>
            </div>
            <details class="admin-menu">
                <summary class="btn"><?= h($_SESSION['admin']['username'] ?? 'Administrator') ?></summary>
                <div class="panel p-3">
                    <a class="nav-link" href="/settings">Console settings</a>
                    <form method="post" action="/logout">
                        <input type="hidden" name="_token" value="<?= h(\KaraOK\Admin\Security\Csrf::token()) ?>">
                        <button class="btn w-full mt-2">Sign out</button>
                    </form>
                </div>
            </details>
        </header>
        <?php if (isset($links[$path]) || in_array($path, ['/users/detail', '/assessments/detail'], true)): ?>
        <div class="report-toolbar">
            <?php if (empty($_SESSION['legacy_api'])): ?>
            <form method="get" class="date-form" data-date-form>
                <?php foreach ($preserved as $key => $value): ?>
                    <input type="hidden" name="<?= h($key) ?>" value="<?= h($value) ?>">
                <?php endforeach; ?>
                <label class="field">Period
                    <select class="input" name="days" data-period>
                        <?php foreach ([7,30,90] as $days): ?>
                            <option value="<?= $days ?>" <?= !$custom && $preset === $days ? 'selected' : '' ?>><?= $days ?> days</option>
                        <?php endforeach; ?>
                        <option value="custom" <?= $custom ? 'selected' : '' ?>>Custom range</option>
                    </select>
                </label>
                <label class="field">From<input class="input" type="date" name="start" value="<?= h($start) ?>" required></label>
                <label class="field">Through<input class="input" type="date" name="end" value="<?= h($end) ?>" max="<?= h(gmdate('Y-m-d', strtotime('yesterday UTC'))) ?>" required></label>
                <button class="btn" type="submit">Apply dates</button>
            </form>
            <?php else: ?><p class="muted text-sm">Connected API uses fixed reporting windows. Date filters require the backend update.</p><?php endif; ?>
            <div class="refresh-block">
                <a class="btn" href="<?= h(build_query_url($path, array_merge(array_filter($_GET, 'is_string'), ['refresh'=>'1']))) ?>">↻ Refresh</a>
                <?php if (empty($_SESSION['legacy_api'])): ?><small>Reporting timezone: UTC</small><?php endif; ?>
            </div>
        </div>
        <?php endif; ?>
        <section id="main-content" class="content-area" tabindex="-1"><?= $content ?></section>
        <footer class="console-footer">
            KaraOK · Instrumental audio intelligence
            <span>Last successful report: <?= h($_SESSION['last_report_refresh'] ?? 'No report fetched this session') ?></span>
        </footer>
    </main>
</div>
<script src="/assets/app.js" defer></script>
</body>
</html>
<?php
}
