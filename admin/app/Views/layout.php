<?php

declare(strict_types=1);

function layout(string $title, string $content, string $path): void
{
    $links = [
        '/' => 'Overview', '/users' => 'Users', '/demographics' => 'Demographics',
        '/usage' => 'Engagement', '/assessments' => 'Assessments',
        '/quality' => 'Audio quality', '/amplifiers' => 'Amplifiers',
        '/operations' => 'Operations',
    ];
    $advanced = [
        '/tables' => 'Data catalog', '/relationships' => 'Relationships',
        '/analysis' => 'Schema health', '/recommendations' => 'Schema recommendations',
        '/analytics' => 'Legacy analytics', '/diagnostics' => 'API diagnostics',
        '/activity' => 'Local activity',
    ];
    $icons = [
        '/' => 'M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z',
        '/users' => 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2 M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8 M20 21v-2a4 4 0 0 0-3-3.87 M16 3.13a4 4 0 0 1 0 7.75',
        '/demographics' => 'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M3 12h18 M12 3c4 5 4 13 0 18-4-5-4-13 0-18',
        '/usage' => 'M3 12h4l3-8 4 16 3-8h4',
        '/assessments' => 'M9 4H5v17h14V4h-4 M9 3h6v4H9z M8 12h8 M8 16h5',
        '/quality' => 'M4 10v4 M8 6v12 M12 3v18 M16 6v12 M20 10v4',
        '/amplifiers' => 'M4 3v7 M4 14v7 M12 3v11 M12 18v3 M20 3v3 M20 10v11 M1 10h6 M9 18h6 M17 6h6',
        '/operations' => 'M3 3v18h18 M7 14l4-5 4 3 6-8',
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
            <p class="nav-caption">Administration</p>
            <?php foreach ($links as $url => $label):
                $active = $path === $url || ($url !== '/' && str_starts_with($path, $url . '/')); ?>
                <a class="nav-link <?= $active ? 'nav-active' : '' ?>" <?= $active ? 'aria-current="page"' : '' ?> href="<?= h(product_url($url)) ?>"><svg class="nav-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="<?= h($icons[$url]) ?>"/></svg><span><?= h($label) ?></span></a>
            <?php endforeach; ?>
            <details class="advanced-nav" <?= isset($advanced[$path]) ? 'open' : '' ?>>
                <summary>Advanced</summary>
                <?php foreach ($advanced as $url => $label): ?>
                    <a class="nav-link <?= $path === $url ? 'nav-active' : '' ?>" <?= $path === $url ? 'aria-current="page"' : '' ?> href="<?= h($url) ?>"><?= h($label) ?></a>
                <?php endforeach; ?>
            </details>
        </nav>
        <div class="sidebar-note"><span class="eyebrow">KaraOK workspace</span><p>Insights for better sound.</p></div>
        <div class="sidebar-footer"><a href="/settings" <?= $path === '/settings' ? 'aria-current="page"' : '' ?>>Settings</a><span>Local console</span></div>
    </aside>
    <main class="console-main">
        <header class="console-header">
            <div class="flex items-center gap-3">
                <button data-sidebar-toggle aria-controls="console-sidebar" aria-expanded="false" class="btn lg:hidden" type="button">Menu</button>
                <div>
                    <p class="header-eyebrow">Workspace / Administration</p>
                    <h1 class="text-xl font-semibold mt-1"><?= h($title) ?></h1>
                </div>
            </div>
            <details class="admin-menu">
                <summary class="btn"><span class="admin-avatar" aria-hidden="true">K</span><span class="admin-name"><?= h($_SESSION['admin']['username'] ?? 'Administrator') ?></span><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg></summary>
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
                <button class="btn btn-primary" type="submit">Apply filters</button>
            </form>
            <?php else: ?><p class="muted text-sm">Connected API uses fixed reporting windows. Date filters require the backend update.</p><?php endif; ?>
            <div class="refresh-block">
                <a class="btn" href="<?= h(build_query_url($path, array_merge(array_filter($_GET, 'is_string'), ['refresh'=>'1']))) ?>">↻ Refresh</a>
                <?php if (empty($_SESSION['legacy_api'])): ?><small>UTC</small><?php endif; ?>
            </div>
        </div>
        <?php endif; ?>
        <section id="main-content" class="content-area" tabindex="-1"><?= $content ?></section>
        <footer class="console-footer">
            KaraOK Admin
            <span>Updated: <?= h($_SESSION['last_report_refresh'] ?? 'Not refreshed') ?></span>
        </footer>
    </main>
</div>
<script src="/assets/app.js" defer></script>
</body>
</html>
<?php
}
