<?php
/**
 * D1 · Dashboard (Figma «Admin panel» → 01 Dashboard va jonli xarita).
 *
 * Hamma raqam — bazadan, uchala buyurtma turi bo'yicha: texnika (orders),
 * yuk tashish (freight_orders), material yetkazish (material_orders).
 * «Texnika topilmadi» — muddati o'tgan tezkor zayavkalar (expired).
 *
 * D3: har bir vidjet alohida hisoblanadi; bittasining xatosi butun
 * sahifani buzmaydi — o'sha kartada «Qayta urinish» chiqadi.
 * Sahifa har 30 soniyada o'zi yangilanadi (oyna ko'rinib turganda).
 */
require_once 'config.php';
require_once 'includes/admin_stats.php';
requireAdmin();

$pageTitle = 'Dashboard';
$currentPage = 'dashboard';
$db = getDbConnection();
$db->exec("SET TIME ZONE 'Asia/Tashkent'");

$period = $_GET['period'] ?? 'day';
if (!in_array($period, ['day', 'week', 'month'], true)) {
    $period = 'day';
}
$periodSql = ['day' => "date_trunc('day', NOW())", 'week' => "NOW() - INTERVAL '7 days'", 'month' => "NOW() - INTERVAL '30 days'"][$period];
// Oldingi xuddi shunday oraliq — «kechagiga nisbatan»
$prevFrom = ['day' => "date_trunc('day', NOW()) - INTERVAL '1 day'", 'week' => "NOW() - INTERVAL '14 days'", 'month' => "NOW() - INTERVAL '60 days'"][$period];
$prevTo = ['day' => "NOW() - INTERVAL '1 day'", 'week' => "NOW() - INTERVAL '7 days'", 'month' => "NOW() - INTERVAL '30 days'"][$period];
$periodWord = ['day' => 'kechagiga', 'week' => "o'tgan haftaga", 'month' => "o'tgan oyga"][$period];

// Hamma buyurtmalar bitta ko'rinishda. st: done | cancelled | notfound | active
$ALL = "(
    SELECT 'equipment' AS kind, id, created_at, COALESCE(finished_at, updated_at) AS closed_at, total_amount AS amount,
           CASE status WHEN 'completed' THEN 'done' WHEN 'cancelled' THEN 'cancelled' WHEN 'rejected' THEN 'cancelled' ELSE 'active' END AS st
      FROM orders
    UNION ALL
    SELECT 'freight', id, created_at, COALESCE(finished_at, updated_at), price,
           CASE status WHEN 'done' THEN 'done' WHEN 'cancelled' THEN 'cancelled' ELSE 'active' END
      FROM freight_orders
    UNION ALL
    SELECT 'material', id, created_at, updated_at, total_amount,
           CASE status WHEN 'delivered' THEN 'done' WHEN 'cancelled' THEN 'cancelled' WHEN 'rejected' THEN 'cancelled' ELSE 'active' END
      FROM material_orders
    UNION ALL
    SELECT 'request', id, created_at, COALESCE(expires_at, updated_at), budget, 'notfound'
      FROM equipment_requests WHERE status = 'expired'
) a";

/** Vidjet: xato bo'lsa null qaytadi, sahifa davom etadi. */
function widget(callable $fn)
{
    try {
        return $fn();
    } catch (Throwable $e) {
        error_log('dashboard widget: ' . $e->getMessage());
        return null;
    }
}

function pctChange(float $now, float $prev): ?float
{
    if ($prev <= 0) {
        return null;
    }
    return round(($now - $prev) / $prev * 100);
}

function money($v): string
{
    return number_format((float) $v, 0, '.', ' ');
}

// ------------------------------------------------------------------ KPI
$kpi = widget(function () use ($db, $ALL, $periodSql, $prevFrom, $prevTo) {
    $r = $db->query("
        SELECT
          COUNT(*) FILTER (WHERE st = 'active') AS active,
          COUNT(*) FILTER (WHERE kind <> 'request' AND created_at >= $periodSql) AS new_now,
          COUNT(*) FILTER (WHERE kind <> 'request' AND created_at >= $prevFrom AND created_at < $prevTo) AS new_prev,
          COALESCE(SUM(amount) FILTER (WHERE st = 'done' AND closed_at >= $periodSql), 0) AS turnover,
          COALESCE(SUM(amount) FILTER (WHERE st = 'done' AND closed_at >= $prevFrom AND closed_at < $prevTo), 0) AS turnover_prev,
          COUNT(*) FILTER (WHERE created_at >= $periodSql AND st IN ('cancelled','notfound')) AS cx_now,
          COUNT(*) FILTER (WHERE created_at >= $periodSql) AS all_now,
          COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days' AND st IN ('cancelled','notfound')) AS cx_30,
          COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days') AS all_30
        FROM $ALL")->fetch();
    return $r;
});

$drivers = widget(function () use ($db) {
    return $db->query("
        SELECT COUNT(*) AS total,
               COUNT(*) FILTER (WHERE is_online AND location_at > NOW() - INTERVAL '2 minutes') AS online
          FROM delivery_driver_profiles")->fetch();
});

// ------------------------------------------------------------------ Grafik
$chart = widget(function () use ($db, $ALL, $period) {
    if ($period === 'day') {
        $rows = $db->query("
            SELECT EXTRACT(HOUR FROM created_at)::int AS b,
                   COUNT(*) FILTER (WHERE st IN ('done','active')) AS ok,
                   COUNT(*) FILTER (WHERE st = 'cancelled') AS cx,
                   COUNT(*) FILTER (WHERE st = 'notfound') AS nf
              FROM $ALL WHERE created_at >= date_trunc('day', NOW())
             GROUP BY 1")->fetchAll();
        $buckets = [];
        for ($h = 0; $h < 24; $h++) {
            $buckets[$h] = ['label' => sprintf('%02d:00', $h), 'ok' => 0, 'cx' => 0, 'nf' => 0];
        }
        $nowKey = (int) date('G');
    } else {
        $days = $period === 'week' ? 7 : 30;
        $rows = $db->query("
            SELECT (created_at::date - (CURRENT_DATE - " . ($days - 1) . "))::int AS b,
                   COUNT(*) FILTER (WHERE st IN ('done','active')) AS ok,
                   COUNT(*) FILTER (WHERE st = 'cancelled') AS cx,
                   COUNT(*) FILTER (WHERE st = 'notfound') AS nf
              FROM $ALL WHERE created_at >= CURRENT_DATE - " . ($days - 1) . "
             GROUP BY 1")->fetchAll();
        $buckets = [];
        for ($i = 0; $i < $days; $i++) {
            $buckets[$i] = ['label' => date('d.m', strtotime('-' . ($days - 1 - $i) . ' days')), 'ok' => 0, 'cx' => 0, 'nf' => 0];
        }
        $nowKey = $days - 1;
    }
    foreach ($rows as $r) {
        if (isset($buckets[(int) $r['b']])) {
            $buckets[(int) $r['b']]['ok'] = (int) $r['ok'];
            $buckets[(int) $r['b']]['cx'] = (int) $r['cx'];
            $buckets[(int) $r['b']]['nf'] = (int) $r['nf'];
        }
    }
    return ['buckets' => $buckets, 'now' => $nowKey];
});

// ------------------------------------------------------------------ So'nggi buyurtmalar
$recent = widget(function () use ($db) {
    return $db->query("
        SELECT * FROM (
          SELECT 'equipment' AS kind, o.id, o.created_at, o.status, o.total_amount AS amount,
                 u.full_name, u.phone, e.type AS what, NULL AS what_name
            FROM orders o JOIN users u ON u.id = o.user_id LEFT JOIN equipment e ON e.id = o.equipment_id
          UNION ALL
          SELECT 'freight', f.id, f.created_at, f.status, f.price, u.full_name, u.phone, f.vehicle_code, NULL
            FROM freight_orders f JOIN users u ON u.id = f.client_id
          UNION ALL
          SELECT 'material', m.id, m.created_at, m.status, m.total_amount, u.full_name, u.phone, p.material_type, p.title
            FROM material_orders m JOIN users u ON u.id = m.buyer_id LEFT JOIN material_products p ON p.id = m.product_id
        ) x ORDER BY created_at DESC LIMIT 6")->fetchAll();
});

// ------------------------------------------------------------------ Turlar bo'yicha
$byType = widget(function () use ($db, $periodSql) {
    $rows = $db->query("
        SELECT e.type AS code, COUNT(*) AS n
          FROM orders o JOIN equipment e ON e.id = o.equipment_id
         WHERE o.created_at >= $periodSql
         GROUP BY e.type ORDER BY n DESC")->fetchAll();
    $list = [];
    foreach ($rows as $r) {
        $list[] = ['name' => equipmentTypeName($r['code']), 'n' => (int) $r['n']];
    }
    $fr = (int) $db->query("SELECT COUNT(*) FROM freight_orders WHERE created_at >= $periodSql")->fetchColumn();
    $mt = (int) $db->query("SELECT COUNT(*) FROM material_orders WHERE created_at >= $periodSql")->fetchColumn();
    if ($fr) { $list[] = ['name' => 'Yuk tashish', 'n' => $fr]; }
    if ($mt) { $list[] = ['name' => 'Materiallar', 'n' => $mt]; }
    usort($list, function ($a, $b) { return $b['n'] <=> $a['n']; });
    if (count($list) > 6) {
        $rest = array_sum(array_column(array_slice($list, 5), 'n'));
        $list = array_slice($list, 0, 5);
        $list[] = ['name' => 'Boshqalar', 'n' => $rest];
    }
    return $list;
});

// ------------------------------------------------------------------ CSV hisobot
if (($_GET['export'] ?? '') === 'csv') {
    $rows = $db->query("
        SELECT kind, id, created_at, st, amount FROM $ALL
         WHERE created_at >= $periodSql ORDER BY created_at")->fetchAll();
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="movex-hisobot-' . $period . '-' . date('Y-m-d') . '.csv"');
    $out = fopen('php://output', 'w');
    fwrite($out, "\xEF\xBB\xBF");
    fputcsv($out, ['Turi', 'ID', 'Yaratilgan', 'Holat', 'Summa']);
    $kindNames = ['equipment' => 'Texnika', 'freight' => 'Yuk tashish', 'material' => 'Material', 'request' => 'Topilmadi'];
    $stNames = ['done' => 'Yakunlangan', 'cancelled' => 'Bekor qilingan', 'notfound' => 'Texnika topilmadi', 'active' => 'Jarayonda'];
    foreach ($rows as $r) {
        fputcsv($out, [$kindNames[$r['kind']] ?? $r['kind'], $r['id'], $r['created_at'], $stNames[$r['st']] ?? $r['st'], (float) $r['amount']]);
    }
    exit;
}

// ------------------------------------------------------------------ Ko'rinish uchun
$counts = adminNavCounts($db);
$hour = (int) date('G');
$greet = $hour < 5 ? 'Xayrli tun' : ($hour < 12 ? 'Xayrli tong' : ($hour < 18 ? 'Xayrli kun' : 'Xayrli kech'));
$weekdays = ['Yakshanba', 'Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba'];
$months = ['', 'yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun', 'iyul', 'avgust', 'sentabr', 'oktabr', 'noyabr', 'dekabr'];
$today = $weekdays[(int) date('w')] . ', ' . (int) date('j') . '-' . $months[(int) date('n')];
$firstName = explode(' ', trim(getAdminUser()['full_name'] ?? ''))[0];

$statusUi = [
    'equipment' => ['pending' => ['Qidirilmoqda', 'warning'], 'confirmed' => ['Jarayonda', 'info'],
                    'completed' => ['Yakunlandi', 'success'], 'cancelled' => ['Bekor qilindi', 'secondary'], 'rejected' => ['Rad etildi', 'secondary']],
    'freight' => ['searching' => ['Qidirilmoqda', 'warning'], 'accepted' => ["Yo'lda", 'info'], 'loaded' => ['Yuklandi', 'info'],
                  'arrived' => ['Yetib keldi', 'info'], 'done' => ['Yakunlandi', 'success'], 'cancelled' => ['Bekor qilindi', 'secondary']],
    'material' => ['pending' => ['Sotuvchi kutilmoqda', 'warning'], 'confirmed' => ['Jarayonda', 'info'], 'delivered' => ['Yetkazildi', 'success'],
                   'cancelled' => ['Bekor qilindi', 'secondary'], 'rejected' => ['Rad etildi', 'secondary']],
];
$kindHref = ['equipment' => 'orders.php?id=', 'freight' => 'orders.php?kind=freight&id=', 'material' => 'orders.php?kind=material&id='];

function maskedPhone(?string $p): string
{
    $p = preg_replace('/\D/', '', (string) $p);
    if (strlen($p) < 12) {
        return $p ? '+' . $p : '';
    }
    return '+' . substr($p, 0, 3) . ' ' . substr($p, 3, 2) . ' *** ' . substr($p, -4, 2) . ' ' . substr($p, -2);
}

$attn = [
    ['drivers.php', 'file-check-2', 'Hujjatlar tekshiruvi', $counts['docs_pending'],
        $counts['docs_late'] ? $counts['docs_late'] . ' tasi 2 soatdan oshdi' : 'Haydovchilar ishga chiqishni kutmoqda', $counts['docs_late'] > 0, 'danger'],
    ['payouts.php', 'banknote', "Pul yechish so'rovlari", $counts['payouts_pending'],
        $counts['payouts_late'] ? $counts['payouts_late'] . ' tasi 24 soatdan beri kutmoqda' : 'Egalar pulini kutmoqda', $counts['payouts_late'] > 0, 'warn'],
    ['problems.php', 'shield-alert', 'Ochiq nizolar', $counts['problems_open'],
        $counts['problems_late'] ? $counts['problems_late'] . ' tasi 24 soatdan beri javobsiz' : 'Mijoz shikoyatlari', $counts['problems_late'] > 0, 'danger'],
    ['materials.php', 'brick-wall', 'Tovar moderatsiyasi', $counts['materials_pending'], "Katalogda ko'rinmayapti", false, 'warn'],
    ['requests.php', 'megaphone', 'Taklifsiz zayavkalar', $counts['requests_no_offers'], 'Bironta ega javob bermagan', false, 'warn'],
    ['equipment.php', 'map-pin-off', 'Joylashuvsiz texnika', $counts['equipment_no_coords'], "Xaritada va qidiruvda yo'q", false, 'secondary'],
];

include 'includes/header.php';
?>
<div class="content">
    <div class="page-head">
        <div>
            <h2><?= $greet ?><?= $firstName ? ', ' . htmlspecialchars($firstName) : '' ?></h2>
            <div class="sub"><?= $today ?> · yangilandi <?= date('H:i') ?> · har 30 soniyada avtomatik</div>
        </div>
        <div class="page-actions">
            <div class="seg">
                <?php foreach (['day' => 'Bugun', 'week' => 'Hafta', 'month' => 'Oy'] as $k => $v): ?>
                    <a href="?period=<?= $k ?>" class="<?= $period === $k ? 'active' : '' ?>"><?= $v ?></a>
                <?php endforeach; ?>
            </div>
            <a class="btn btn-secondary btn-sm" href="?period=<?= $period ?>&export=csv"><i data-lucide="download"></i> Hisobot</a>
        </div>
    </div>

    <?php if ($counts['searching_stuck'] > 0): ?>
        <div class="banner">
            <i data-lucide="triangle-alert"></i>
            <div>
                <b><?= $counts['searching_stuck'] ?> ta buyurtma 10 daqiqadan beri ijrochi topa olmayapti</b>
                <div class="sub">Yuk tashish, material yetkazish va tezkor zayavkalar. Haydovchilar yetishmayapti yoki radius tor.</div>
            </div>
            <a class="btn btn-secondary btn-sm" href="orders.php?filter=stuck">Ko'rish</a>
        </div>
    <?php endif; ?>

    <?php if ($kpi === null): ?>
        <div class="banner danger"><i data-lucide="circle-x"></i><div><b>Ko'rsatkichlarni olib bo'lmadi</b>
            <div class="sub">Baza so'roviga xato qaytdi — server jurnalida batafsil.</div></div>
            <a class="btn btn-secondary btn-sm" href="">Qayta urinish</a></div>
    <?php else:
        $ordersPct = pctChange((float) $kpi['new_now'], (float) $kpi['new_prev']);
        $turnPct = pctChange((float) $kpi['turnover'], (float) $kpi['turnover_prev']);
        $cxRate = $kpi['all_now'] > 0 ? $kpi['cx_now'] / $kpi['all_now'] * 100 : 0;
        $cxNorm = $kpi['all_30'] > 0 ? $kpi['cx_30'] / $kpi['all_30'] * 100 : 0;
        $cxDiff = round($cxRate - $cxNorm, 1);
    ?>
    <div class="stats-grid">
        <a class="stat-card" href="orders.php?filter=active">
            <div class="stat-header"><div class="stat-icon"><i data-lucide="clipboard-list"></i></div><div class="stat-title">Faol buyurtmalar</div></div>
            <div class="stat-value"><?= money($kpi['active']) ?></div>
            <div class="stat-change <?= $ordersPct === null ? '' : ($ordersPct >= 0 ? 'positive' : 'negative') ?>">
                <?php if ($ordersPct === null): ?>
                    Yangi: <?= (int) $kpi['new_now'] ?>
                <?php else: ?>
                    <i data-lucide="<?= $ordersPct >= 0 ? 'trending-up' : 'trending-down' ?>" style="width:14px;height:14px"></i>
                    <?= ($ordersPct >= 0 ? '+' : '') . $ordersPct ?>% yangi, <?= $periodWord ?> nisbatan
                <?php endif; ?>
            </div>
        </a>
        <div class="stat-card">
            <div class="stat-header"><div class="stat-icon"><i data-lucide="wallet"></i></div>
                <div class="stat-title"><?= $period === 'day' ? 'Bugungi aylanma' : ($period === 'week' ? 'Haftalik aylanma' : 'Oylik aylanma') ?></div></div>
            <div class="stat-value"><?= money($kpi['turnover']) ?> <span style="font-size:15px;font-weight:600">so'm</span></div>
            <div class="stat-change <?= $turnPct === null ? '' : ($turnPct >= 0 ? 'positive' : 'negative') ?>">
                <?php if ($turnPct === null): ?>
                    Yakunlangan buyurtmalar summasi
                <?php else: ?>
                    <i data-lucide="<?= $turnPct >= 0 ? 'trending-up' : 'trending-down' ?>" style="width:14px;height:14px"></i>
                    <?= ($turnPct >= 0 ? '+' : '') . $turnPct ?>% <?= $periodWord ?> nisbatan
                <?php endif; ?>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-header"><div class="stat-icon"><i data-lucide="user-check"></i></div><div class="stat-title">Onlayn haydovchilar</div></div>
            <?php if ($drivers === null): ?>
                <div class="stat-value">—</div><div class="stat-change">Ma'lumot olinmadi</div>
            <?php else: ?>
                <div class="stat-value"><?= (int) $drivers['online'] ?> / <?= (int) $drivers['total'] ?></div>
                <div class="stat-change"><?= $drivers['total'] ? round($drivers['online'] / $drivers['total'] * 100) : 0 ?>% onlayn · yuk mashinalari</div>
            <?php endif; ?>
        </div>
        <div class="stat-card">
            <div class="stat-header"><div class="stat-icon"><i data-lucide="circle-x"></i></div><div class="stat-title">Bekor qilish darajasi</div></div>
            <div class="stat-value"><?= number_format($cxRate, 1, ',', '') ?>%</div>
            <div class="stat-change <?= $cxDiff > 0 ? 'negative' : 'positive' ?>">
                <?= ($cxDiff >= 0 ? '+' : '') . number_format($cxDiff, 1, ',', '') ?> p.p. — <?= $cxDiff > 0 ? 'normadan yuqori' : 'normada' ?> (30 kun: <?= number_format($cxNorm, 1, ',', '') ?>%)
            </div>
        </div>
    </div>
    <?php endif; ?>

    <div class="dash-grid">
        <div class="dash-col">
            <div class="card">
                <div class="card-header">
                    <div class="card-title">Buyurtmalar — <?= $period === 'day' ? 'soatlar kesimida' : 'kunlar kesimida' ?></div>
                </div>
                <div class="card-body">
                    <?php if ($chart === null): ?>
                        <div class="empty-state"><i data-lucide="chart-no-axes-column"></i><div>Grafikni yuklab bo'lmadi</div>
                            <a class="btn btn-secondary btn-sm mt-1" href="">Qayta urinish</a></div>
                    <?php else:
                        $max = 1;
                        $tot = ['ok' => 0, 'cx' => 0, 'nf' => 0];
                        foreach ($chart['buckets'] as $b) {
                            $max = max($max, $b['ok'] + $b['cx'] + $b['nf']);
                            foreach ($tot as $k => $_) { $tot[$k] += $b[$k]; }
                        }
                    ?>
                        <div class="chart-legend">
                            <span><i style="background:var(--blue-500)"></i>Qabul qilingan · <?= $tot['ok'] ?></span>
                            <span><i style="background:var(--yellow-400)"></i>Bekor qilingan · <?= $tot['cx'] ?></span>
                            <span><i style="background:var(--red-500)"></i>Texnika topilmadi · <?= $tot['nf'] ?></span>
                        </div>
                        <div class="bars">
                            <?php foreach ($chart['buckets'] as $k => $b):
                                $h = function ($v) use ($max) { return $v ? max(2, round($v / $max * 100, 1)) : 0; };
                            ?>
                                <div class="bar <?= $k === $chart['now'] ? 'now' : '' ?>"
                                     data-tip="<?= $b['label'] ?> · <?= $b['ok'] ?> / <?= $b['cx'] ?> / <?= $b['nf'] ?>">
                                    <span class="ok" style="height:<?= $h($b['ok']) ?>%"></span>
                                    <span class="cx" style="height:<?= $h($b['cx']) ?>%"></span>
                                    <span class="nf" style="height:<?= $h($b['nf']) ?>%"></span>
                                </div>
                            <?php endforeach; ?>
                        </div>
                        <div class="bars-axis">
                            <?php $n = count($chart['buckets']); $step = max(1, (int) floor($n / 5));
                            foreach ($chart['buckets'] as $k => $b): if ($k % $step === 0 || $k === $n - 1): ?>
                                <span><?= $b['label'] ?></span>
                            <?php endif; endforeach; ?>
                        </div>
                    <?php endif; ?>
                </div>
            </div>

            <div class="card">
                <div class="card-header">
                    <div class="card-title">So'nggi buyurtmalar</div>
                    <a class="card-link" href="orders.php">Barchasi →</a>
                </div>
                <?php if ($recent === null): ?>
                    <div class="empty-state"><div>Ro'yxatni yuklab bo'lmadi</div><a class="btn btn-secondary btn-sm mt-1" href="">Qayta urinish</a></div>
                <?php elseif (!$recent): ?>
                    <div class="empty-state"><i data-lucide="inbox"></i><div>Hali buyurtma yo'q</div></div>
                <?php else: ?>
                    <div class="table-responsive"><table>
                        <thead><tr><th>ID</th><th>Mijoz</th><th>Xizmat</th><th>Holat</th><th class="text-right">Summa, so'm</th></tr></thead>
                        <tbody>
                        <?php foreach ($recent as $o):
                            $ui = $statusUi[$o['kind']][$o['status']] ?? [$o['status'], 'secondary'];
                            if ($o['kind'] === 'equipment') { $what = equipmentTypeName($o['what']); }
                            elseif ($o['kind'] === 'freight') { $what = 'Yuk tashish · ' . deliveryVehicleName($o['what']); }
                            else { $what = $o['what_name'] ?: materialTypeName($o['what']); }
                        ?>
                            <tr>
                                <td><a href="<?= $kindHref[$o['kind']] . (int) $o['id'] ?>" class="num">#<?= (int) $o['id'] ?></a></td>
                                <td><?= htmlspecialchars($o['full_name']) ?><span class="sub num"><?= maskedPhone($o['phone']) ?></span></td>
                                <td><?= htmlspecialchars($what) ?></td>
                                <td><span class="badge badge-<?= $ui[1] ?>"><?= $ui[0] ?></span></td>
                                <td class="text-right num"><?= in_array($o['status'], ['cancelled', 'rejected'], true) ? '—' : money($o['amount']) ?></td>
                            </tr>
                        <?php endforeach; ?>
                        </tbody>
                    </table></div>
                <?php endif; ?>
            </div>
        </div>

        <div class="dash-col">
            <div class="card" id="attention">
                <div class="card-header"><div class="card-title">Diqqat talab qiladi</div></div>
                <div class="card-body" style="padding-top:4px;padding-bottom:4px">
                    <?php $any = false; ?>
                    <ul class="attn-list">
                        <?php foreach ($attn as [$href, $icon, $title, $n, $sub, $late, $tone]):
                            if ($n <= 0) { continue; } $any = true; ?>
                            <li><a href="<?= $href ?>">
                                <span class="ic"><i data-lucide="<?= $icon ?>"></i></span>
                                <span><b><?= $title ?></b><small class="<?= $late ? 'late' : '' ?>"><?= htmlspecialchars($sub) ?></small></span>
                                <span class="cnt nav-count <?= $tone ?>"><?= (int) $n ?></span>
                                <i data-lucide="chevron-right" class="chev"></i>
                            </a></li>
                        <?php endforeach; ?>
                    </ul>
                    <?php if (!$any): ?>
                        <div class="empty-state"><i data-lucide="circle-check"></i><div>Hammasi joyida — kutayotgan ish yo'q</div></div>
                    <?php endif; ?>
                </div>
            </div>

            <div class="card">
                <div class="card-header"><div class="card-title">Xizmat turlari bo'yicha</div>
                    <span class="text-muted" style="font-size:12px"><?= ['day' => 'Bugun', 'week' => '7 kun', 'month' => '30 kun'][$period] ?></span></div>
                <div class="card-body">
                    <?php if ($byType === null): ?>
                        <div class="empty-state"><div>Yuklab bo'lmadi</div><a class="btn btn-secondary btn-sm mt-1" href="">Qayta urinish</a></div>
                    <?php elseif (!$byType): ?>
                        <div class="empty-state" style="padding:16px"><div>Bu davrda buyurtma yo'q</div></div>
                    <?php else: $mx = max(array_column($byType, 'n')); foreach ($byType as $t): ?>
                        <div class="hbar">
                            <span class="n"><?= htmlspecialchars($t['name']) ?></span>
                            <span class="track"><span class="fill" style="width:<?= round($t['n'] / $mx * 100) ?>%"></span></span>
                            <span class="v"><?= $t['n'] ?></span>
                        </div>
                    <?php endforeach; endif; ?>
                </div>
            </div>
        </div>
    </div>
</div>
<script>
// Har 30 s yangilash — faqat oyna ko'rinib turganda
setInterval(() => { if (document.visibilityState === 'visible') location.reload(); }, 30000);
</script>
<?php include 'includes/footer.php'; ?>
