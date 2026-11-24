<?php
/**
 * Karkas: chap menyu va yuqori panel — Figma «Admin panel» → Komponentlar
 * (Nav item, Sidebar, Topbar). Menyuda faqat ISHLAYDIGAN bo'limlar:
 * maketdagi hali yozilmagan bo'limlar (jonli xarita, yordam chatlari, push,
 * rollar, audit) tayyor bo'lganda qo'shiladi — bo'sh sahifaga havola
 * qo'yilmaydi.
 */
require_once __DIR__ . '/admin_stats.php';

$adminUser = getAdminUser();
$navCounts = adminNavCounts(getDbConnection());
$attention = adminAttentionTotal($navCounts);
$cur = $currentPage ?? '';

$navSections = [
    '' => [
        ['dashboard', 'index.php', 'layout-dashboard', 'Dashboard', null, ''],
    ],
    'Operatsiyalar' => [
        ['orders', 'orders.php', 'clipboard-list', 'Buyurtmalar', $navCounts['orders_active'], ''],
        ['requests', 'requests.php', 'megaphone', 'Zayavkalar', $navCounts['requests_no_offers'], 'warn'],
        ['listings', 'listings.php', 'newspaper', "E'lonlar", $navCounts['listings_taken'], ''],
        ['materials', 'materials.php', 'brick-wall', 'Materiallar', $navCounts['materials_pending'], 'warn'],
        ['problems', 'problems.php', 'shield-alert', 'Nizolar', $navCounts['problems_open'], 'danger'],
        ['support', 'support.php', 'messages-square', 'Yordam chatlari', $navCounts['support_waiting'], 'danger'],
    ],
    'Foydalanuvchilar' => [
        ['users', 'users.php', 'users', 'Mijozlar', null, ''],
        ['haydovchilar', 'haydovchilar.php', 'user-round-check', 'Haydovchilar', null, ''],
        ['drivers', 'drivers.php', 'file-check-2', 'Hujjatlar tekshiruvi', $navCounts['docs_pending'], 'warn'],
        ['equipment', 'texnika.php', 'truck', 'Texnika', $navCounts['equipment_no_coords'], 'warn'],
        ['reviews', 'reviews.php', 'star', 'Sharhlar', $navCounts['reviews_flagged'], 'warn'],
    ],
    'Moliya' => [
        ['balance', 'balance.php', 'credit-card', "To'lovlar", null, ''],
        ['payouts', 'payouts.php', 'banknote', 'Pul yechish', $navCounts['payouts_pending'], 'warn'],
        ['budget', 'budget.php', 'piggy-bank', 'Platforma daromadi', null, ''],
    ],
    'Tizim' => [
        ['tariffs', 'tariffs.php', 'tag', 'Tariflar va narxlar', null, ''],
        ['zones', 'zones.php', 'map', 'Hududlar va narxlar', null, ''],
        ['catalog', 'catalog.php', 'layers', 'Katalog', null, ''],
        ['commission', 'commission.php', 'sliders-horizontal', 'Sozlamalar', null, ''],
        ['backup', 'backup.php', 'database', 'Zaxira nusxa', null, ''],
        ['system', 'system.php', 'server', 'Tizim holati', null, ''],
    ],
];

$initials = '';
foreach (preg_split('/\s+/', trim($adminUser['full_name'] ?? 'A')) as $w) {
    if ($w !== '' && strlen($initials) < 2) {
        $initials .= mb_strtoupper(mb_substr($w, 0, 1));
    }
}
?>
<!DOCTYPE html>
<html lang="uz">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= htmlspecialchars($pageTitle ?? 'Admin panel') ?> · MoveX GO</title>
    <link rel="icon" type="image/png" href="assets/favicon.png">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap">
    <link rel="stylesheet" href="assets/css/style.css?v=<?= @filemtime(__DIR__ . '/../assets/css/style.css') ?>">
    <style>
        /* Foydalanuvchini boshqarish paneli — bosilganda ochiladi */
        tr.hidden { display: none; }
    </style>
</head>
<body>
<div class="dashboard">
    <aside class="sidebar" id="sidebar">
        <div class="sidebar-header">
            <div class="sidebar-logo">M</div>
            <div class="sidebar-brand">MoveX <span>GO</span></div>
            <div class="sidebar-tag">ADMIN</div>
        </div>
        <nav class="sidebar-nav">
            <?php foreach ($navSections as $section => $items): ?>
                <?php if ($section !== ''): ?>
                    <div class="nav-section"><?= htmlspecialchars($section) ?></div>
                <?php endif; ?>
                <ul>
                    <?php foreach ($items as [$key, $href, $icon, $label, $count, $tone]): ?>
                        <li>
                            <a href="<?= $href ?>" class="<?= $cur === $key ? 'active' : '' ?>">
                                <i data-lucide="<?= $icon ?>"></i>
                                <?= htmlspecialchars($label) ?>
                                <?php if ($count): ?>
                                    <span class="nav-count <?= $tone ?>"><?= (int) $count ?></span>
                                <?php endif; ?>
                            </a>
                        </li>
                    <?php endforeach; ?>
                </ul>
            <?php endforeach; ?>
        </nav>
        <div class="sidebar-user">
            <div class="user-avatar"><?= htmlspecialchars($initials ?: 'A') ?></div>
            <div class="user-details">
                <div class="user-name"><?= htmlspecialchars($adminUser['full_name'] ?? '') ?></div>
                <div class="user-role">Administrator</div>
            </div>
            <a href="logout.php" class="logout" title="Chiqish" aria-label="Chiqish"><i data-lucide="log-out"></i></a>
        </div>
    </aside>
    <div class="sidebar-backdrop" id="sidebarBackdrop"></div>

    <main class="main-content">
        <header class="header">
            <div class="header-left">
                <button class="menu-toggle" id="toggleSidebar" aria-label="Menyu"><i data-lucide="menu"></i></button>
                <h1><?= htmlspecialchars($pageTitle ?? 'Admin panel') ?></h1>
            </div>
            <div class="header-right">
                <form class="top-search" action="search.php" method="get" role="search">
                    <i data-lucide="search"></i>
                    <input type="search" name="q" id="globalSearch" placeholder="Buyurtma ID, telefon, davlat raqami…"
                           value="<?= htmlspecialchars($_GET['q'] ?? '') ?>" autocomplete="off">
                    <kbd>Ctrl K</kbd>
                </form>
                <span class="health-chip" id="healthChip" title="API holati"><span class="label">Tekshirilmoqda…</span></span>
                <a href="index.php#attention" class="icon-btn" title="Diqqat talab qiladi" aria-label="Diqqat talab qiladi">
                    <i data-lucide="bell"></i>
                    <?php if ($attention > 0): ?><span class="dot"><?= $attention > 99 ? '99+' : $attention ?></span><?php endif; ?>
                </a>
            </div>
        </header>
