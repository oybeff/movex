<?php
/**
 * O1 · Buyurtmalar ro'yxati (Figma «Admin panel» → 02 Buyurtmalar).
 *
 * Hamma turdagi buyurtma bitta jadvalda (includes/orders_lib.php).
 * Tablar soni bilan; 10+ daqiqa ijrochi qidirilayotgan qator qizil fonda.
 * O1b — checkbox bilan tanlash: faqat eksport; xavfli amal (bekor qilish)
 * ommaviy qilinmaydi — faqat tafsilot sahifasida, bittadan.
 * O5 — natija yo'q: sabab + filtrlarni tozalash, eksport o'chirilgan.
 *
 * ?kind=..&id=.. — O2 tafsilot (includes/order_detail.php).
 */
require_once 'config.php';
require_once 'includes/orders_lib.php';
requireAdmin();
requireCsrfToken();

$db = getDbConnection();
$db->exec("SET TIME ZONE 'Asia/Tashkent'");

if (isset($_GET['id'])) {
    require 'includes/order_detail.php';
    exit;
}

$pageTitle = 'Operatsiyalar / Buyurtmalar';
$currentPage = 'orders';

$tab = $_GET['tab'] ?? 'all';
if (!isset(ORDER_TABS[$tab])) { $tab = 'all'; }
$filter = $_GET['filter'] ?? '';
if ($filter === 'stuck') { $tab = 'searching'; }
$kind = $_GET['kind_f'] ?? '';
$period = $_GET['period'] ?? 'all';
$payment = $_GET['payment'] ?? '';
$q = trim((string) ($_GET['q'] ?? ''));
$page = max(1, (int) ($_GET['page'] ?? 1));
$perPage = (int) ($_GET['per'] ?? 20);
if (!in_array($perPage, [20, 50, 100], true)) { $perPage = 20; }

// --------------------------------------------------------- WHERE (tabdan tashqari)
$where = [];
$params = [];
if ($kind !== '' && isset(ORDER_KINDS[$kind])) {
    $where[] = 'u.kind = :kind';
    $params[':kind'] = $kind;
}
$periods = ['today' => "date_trunc('day', NOW())", '7' => "NOW() - INTERVAL '7 days'", '30' => "NOW() - INTERVAL '30 days'"];
if (isset($periods[$period])) {
    $where[] = 'u.created_at >= ' . $periods[$period];
}
if (in_array($payment, ['balance', 'card', 'cash'], true)) {
    $where[] = 'u.payment = :pay';
    $params[':pay'] = $payment;
}
if ($q !== '') {
    $digits = preg_replace('/\D+/', '', $q);
    $or = ['LOWER(u.client_name) LIKE :ql', "LOWER(COALESCE(u.perf_name,'')) LIKE :ql2",
           "LOWER(REPLACE(COALESCE(u.plate,''),' ','')) LIKE :qp"];
    $params[':ql'] = '%' . mb_strtolower($q) . '%';
    $params[':ql2'] = $params[':ql'];
    $params[':qp'] = '%' . preg_replace('/\s+/', '', mb_strtolower($q)) . '%';
    if ($digits !== '') {
        if (strlen($digits) <= 9) {
            $or[] = 'u.id = :qid';
            $params[':qid'] = (int) $digits;
        }
        if (strlen($digits) >= 4) {
            $or[] = 'u.client_phone LIKE :qph';
            $params[':qph'] = '%' . $digits . '%';
        }
    }
    $where[] = '(' . implode(' OR ', $or) . ')';
}
if ($filter === 'stuck') {
    $where[] = 'u.stuck';
}
if ($filter === 'active') {
    $where[] = "u.st IN ('searching','assigned','progress')";
}
$base = $where ? ' WHERE ' . implode(' AND ', $where) : '';

$tabWhere = '';
if ($tab === 'dispute') {
    $tabWhere = ($base ? ' AND ' : ' WHERE ') . 'u.dispute';
} elseif ($tab !== 'all') {
    $tabWhere = ($base ? ' AND ' : ' WHERE ') . 'u.st = :tab';
}

$U = ordersUnionSql();

// Tab sonlari — boshqa filtrlar hisobga olingan holda
$st = $db->prepare("SELECT u.st, COUNT(*) AS n, COUNT(*) FILTER (WHERE u.dispute) AS d,
                           COUNT(*) FILTER (WHERE u.stuck) AS late
                      FROM $U $base GROUP BY u.st");
$st->execute($params);
$tabCounts = array_fill_keys(array_keys(ORDER_TABS), 0);
$lateSearching = 0;
foreach ($st->fetchAll() as $r) {
    $tabCounts[$r['st']] = (int) $r['n'];
    $tabCounts['all'] += (int) $r['n'];
    $tabCounts['dispute'] += (int) $r['d'];
    $lateSearching += (int) $r['late'];
}

$listParams = $params;
if ($tab !== 'all' && $tab !== 'dispute') {
    $listParams[':tab'] = $tab;
}

// --------------------------------------------------------- Eksport (CSV)
if (($_GET['export'] ?? '') === 'csv') {
    $ids = array_filter(array_map('trim', explode(',', (string) ($_GET['ids'] ?? ''))));
    $extra = '';
    if ($ids) {
        $pairs = [];
        foreach ($ids as $i => $pair) {
            if (preg_match('/^(equipment|request|freight|material)-(\d+)$/', $pair, $m)) {
                $pairs[] = "(u.kind = :ek$i AND u.id = :ei$i)";
                $listParams[":ek$i"] = $m[1];
                $listParams[":ei$i"] = (int) $m[2];
            }
        }
        if ($pairs) {
            $extra = (($base || $tabWhere) ? ' AND ' : ' WHERE ') . '(' . implode(' OR ', $pairs) . ')';
        }
    }
    $st = $db->prepare("SELECT u.* FROM $U $base $tabWhere $extra ORDER BY u.created_at DESC LIMIT 10000");
    $st->execute($listParams);
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="buyurtmalar-' . date('Y-m-d-Hi') . '.csv"');
    $out = fopen('php://output', 'w');
    fwrite($out, "\xEF\xBB\xBF");
    fputcsv($out, ['ID', 'Turi', 'Yaratilgan', 'Mijoz', 'Telefon', 'Ijrochi', 'Xizmat', 'Qayerdan', 'Qayerga', 'km', 'Holat', "To'lov", 'Summa']);
    foreach ($st->fetchAll() as $r) {
        fputcsv($out, [$r['id'], ORDER_KINDS[$r['kind']], $r['created_at'], $r['client_name'], $r['client_phone'],
            $r['perf_name'], orderWhat($r), $r['addr_from'], $r['addr_to'], $r['km'], orderStatusBadge($r)[0],
            orderPaymentLabel($r)[0], (float) $r['amount']]);
    }
    exit;
}

// --------------------------------------------------------- Ro'yxat
$total = $tabCounts[$tab] ?? 0;
$pages = max(1, (int) ceil($total / $perPage));
$page = min($page, $pages);
$offset = ($page - 1) * $perPage;
$st = $db->prepare("SELECT u.* FROM $U $base $tabWhere
                    ORDER BY u.stuck DESC, u.created_at DESC
                    LIMIT $perPage OFFSET $offset");
$st->execute($listParams);
$rows = $st->fetchAll();

function qs(array $over = []): string
{
    $p = array_merge($_GET, $over);
    unset($p['export'], $p['ids']);
    $p = array_filter($p, function ($v) { return $v !== '' && $v !== null; });
    return '?' . http_build_query($p);
}

$hasFilters = $q !== '' || $kind !== '' || $period !== 'all' || $payment !== '' || $filter !== '';

include 'includes/header.php';
?>
<div class="content">
    <div class="page-head">
        <div>
            <h2>Buyurtmalar</h2>
            <div class="sub">Texnika, yuk tashish va materiallar — bitta ro'yxatda · yangilandi <?= date('H:i') ?></div>
        </div>
        <div class="page-actions">
            <?php if ($total > 0): ?>
                <a class="btn btn-secondary btn-sm" href="<?= htmlspecialchars(qs(['export' => 'csv'])) ?>&export=csv"><i data-lucide="download"></i> Eksport (CSV)</a>
            <?php else: ?>
                <span class="btn btn-secondary btn-sm disabled" title="Eksport qiladigan narsa yo'q"><i data-lucide="download"></i> Eksport (CSV)</span>
            <?php endif; ?>
        </div>
    </div>

    <div class="tabs">
        <?php foreach (ORDER_TABS as $k => $label):
            $n = $tabCounts[$k];
            $tone = ($k === 'dispute' && $n) || ($k === 'searching' && $lateSearching) ? 'danger' : ($k === $tab ? 'info' : '');
        ?>
            <a href="<?= htmlspecialchars(qs(['tab' => $k, 'page' => null, 'filter' => $filter === 'stuck' ? null : $filter])) ?>" class="<?= $tab === $k ? 'active' : '' ?>">
                <?= $label ?> <span class="nav-count <?= $tone === 'danger' ? 'danger' : '' ?>"><?= number_format($n, 0, '.', ' ') ?></span>
            </a>
        <?php endforeach; ?>
    </div>

    <form class="filters" method="get">
        <input type="hidden" name="tab" value="<?= htmlspecialchars($tab) ?>">
        <div class="filter-search">
            <i data-lucide="search"></i>
            <input type="search" name="q" value="<?= htmlspecialchars($q) ?>" placeholder="ID, telefon, ism, davlat raqami">
        </div>
        <select name="period" onchange="this.form.submit()">
            <?php foreach (['all' => 'Butun davr', 'today' => 'Bugun', '7' => '7 kun', '30' => '30 kun'] as $k => $v): ?>
                <option value="<?= $k ?>" <?= $period === (string) $k ? 'selected' : '' ?>><?= $v ?></option>
            <?php endforeach; ?>
        </select>
        <select name="kind_f" onchange="this.form.submit()">
            <option value="">Xizmat turi</option>
            <?php foreach (ORDER_KINDS as $k => $v): ?>
                <option value="<?= $k ?>" <?= $kind === $k ? 'selected' : '' ?>><?= $v ?></option>
            <?php endforeach; ?>
        </select>
        <select name="payment" onchange="this.form.submit()">
            <option value="">To'lov</option>
            <?php foreach (['balance' => 'Go wallet', 'card' => 'Karta', 'cash' => 'Naqd'] as $k => $v): ?>
                <option value="<?= $k ?>" <?= $payment === $k ? 'selected' : '' ?>><?= $v ?></option>
            <?php endforeach; ?>
        </select>
        <?php if ($filter === 'stuck'): ?>
            <input type="hidden" name="filter" value="stuck">
            <span class="chip">10+ daqiqa qidirilmoqda <a href="<?= htmlspecialchars(qs(['filter' => null])) ?>" aria-label="Olib tashlash">×</a></span>
        <?php elseif ($filter === 'active'): ?>
            <input type="hidden" name="filter" value="active">
            <span class="chip">Faol buyurtmalar <a href="<?= htmlspecialchars(qs(['filter' => null])) ?>" aria-label="Olib tashlash">×</a></span>
        <?php endif; ?>
        <button class="btn btn-secondary btn-sm" type="submit">Qidirish</button>
        <?php if ($hasFilters): ?><a class="btn btn-ghost btn-sm" href="orders.php?tab=<?= $tab ?>">Tozalash</a><?php endif; ?>
    </form>

    <div class="card">
        <?php if (!$rows): ?>
            <div class="empty-state">
                <i data-lucide="search-x"></i>
                <div><b>Hech narsa topilmadi</b></div>
                <div class="mt-1"><?= $q !== '' ? '«' . htmlspecialchars($q) . '» bo\'yicha tanlangan filtrlarda buyurtma yo\'q.' :
                    'Bu bo\'limda tanlangan filtrlar bo\'yicha buyurtma yo\'q.' ?></div>
                <?php if ($hasFilters): ?>
                    <a class="btn btn-secondary btn-sm mt-2" href="orders.php?tab=<?= $tab ?>"><i data-lucide="x"></i> Filtrlarni tozalash</a>
                <?php endif; ?>
            </div>
        <?php else: ?>
            <div class="table-responsive"><table class="orders-table">
                <thead><tr>
                    <th style="width:36px"><input type="checkbox" id="selAll" aria-label="Hammasini tanlash"></th>
                    <th>ID / vaqt</th><th>Mijoz</th><th>Ijrochi / xizmat</th><th>Manzil</th><th>Holat</th><th>To'lov</th>
                    <th class="text-right">Summa, so'm</th><th style="width:40px"></th>
                </tr></thead>
                <tbody>
                <?php foreach ($rows as $r):
                    [$stText, $stTone] = orderStatusBadge($r);
                    [$payM, $payS] = orderPaymentLabel($r);
                    $late = !empty($r['stuck']);
                    $href = orderHref($r['kind'], (int) $r['id']);
                ?>
                    <tr class="<?= $late || $r['dispute'] ? 'row-alert' : '' ?>" data-href="<?= $href ?>">
                        <td><input type="checkbox" class="sel" value="<?= $r['kind'] . '-' . (int) $r['id'] ?>" aria-label="Tanlash"></td>
                        <td><a href="<?= $href ?>" class="num"><b>#<?= (int) $r['id'] ?></b></a><span class="sub"><?= agoText($r['created_at']) ?></span></td>
                        <td><?= htmlspecialchars($r['client_name']) ?><span class="sub num"><?= maskPhone($r['client_phone']) ?></span></td>
                        <td>
                            <?= $r['perf_name'] ? htmlspecialchars($r['perf_name']) : '<span class="text-muted">—</span>' ?>
                            <span class="sub"><?= htmlspecialchars(ORDER_KINDS[$r['kind']] . ' · ' . orderWhat($r)) ?><?= $r['plate'] ? ' · ' . htmlspecialchars($r['plate']) : '' ?></span>
                        </td>
                        <td class="addr">
                            <?= htmlspecialchars($r['addr_from'] ? $r['addr_from'] . ' → ' . $r['addr_to'] : ($r['addr_to'] ?: '—')) ?>
                            <?php if ($r['km'] !== null): ?><span class="sub"><?= rtrim(rtrim(number_format((float) $r['km'], 1, '.', ''), '0'), '.') ?> km</span><?php endif; ?>
                        </td>
                        <td><span class="badge badge-<?= $stTone ?>"><?= htmlspecialchars($stText) ?></span></td>
                        <td><?= $payM ?><?php if ($payS): ?><span class="sub"><?= $payS ?></span><?php endif; ?></td>
                        <td class="text-right num"><?= $r['st'] === 'cancelled' ? '—' : moneyFmt($r['amount']) ?></td>
                        <td><a href="<?= $href ?>" class="icon-btn" aria-label="Ochish"><i data-lucide="chevron-right"></i></a></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table></div>

            <div class="table-foot">
                <span class="text-muted"><?= $offset + 1 ?>–<?= $offset + count($rows) ?> / <?= number_format($total, 0, '.', ' ') ?> ta</span>
                <div class="pagination" style="padding:0">
                    <?php if ($page > 1): ?><a href="<?= htmlspecialchars(qs(['page' => $page - 1])) ?>" aria-label="Oldingi">‹</a><?php endif; ?>
                    <?php
                    $from = max(1, $page - 2); $to = min($pages, $page + 2);
                    if ($from > 1) { echo '<a href="' . htmlspecialchars(qs(['page' => 1])) . '">1</a>'; if ($from > 2) { echo '<span>…</span>'; } }
                    for ($i = $from; $i <= $to; $i++) {
                        echo $i === $page ? '<span class="active">' . $i . '</span>' : '<a href="' . htmlspecialchars(qs(['page' => $i])) . '">' . $i . '</a>';
                    }
                    if ($to < $pages) { if ($to < $pages - 1) { echo '<span>…</span>'; } echo '<a href="' . htmlspecialchars(qs(['page' => $pages])) . '">' . $pages . '</a>'; }
                    ?>
                    <?php if ($page < $pages): ?><a href="<?= htmlspecialchars(qs(['page' => $page + 1])) ?>" aria-label="Keyingi">›</a><?php endif; ?>
                </div>
                <form method="get">
                    <?php foreach ($_GET as $k => $v): if ($k === 'per' || $k === 'page' || is_array($v)) { continue; } ?>
                        <input type="hidden" name="<?= htmlspecialchars($k) ?>" value="<?= htmlspecialchars($v) ?>">
                    <?php endforeach; ?>
                    <select name="per" onchange="this.form.submit()" style="width:auto;min-height:32px;padding:4px 8px">
                        <?php foreach ([20, 50, 100] as $n): ?><option value="<?= $n ?>" <?= $perPage === $n ? 'selected' : '' ?>><?= $n ?> / sahifa</option><?php endforeach; ?>
                    </select>
                </form>
            </div>
        <?php endif; ?>
    </div>

    <!-- O1b · ommaviy tanlash: faqat xavfsiz amallar -->
    <div class="bulk-bar" id="bulkBar">
        <span id="bulkCount">0 ta tanlandi</span>
        <a class="btn btn-sm" id="bulkExport" href="#"><i data-lucide="download"></i> Eksport</a>
        <button class="btn btn-sm" type="button" id="bulkClear"><i data-lucide="x"></i> Bekor</button>
        <span class="bulk-hint">Bekor qilish — faqat bittadan, buyurtma sahifasida</span>
    </div>
</div>
<script>
(() => {
    const boxes = [...document.querySelectorAll('.sel')];
    const all = document.getElementById('selAll');
    const bar = document.getElementById('bulkBar');
    const cnt = document.getElementById('bulkCount');
    const exp = document.getElementById('bulkExport');
    const base = <?= json_encode(qs(['export' => 'csv'])) ?>;
    const sync = () => {
        const sel = boxes.filter(b => b.checked).map(b => b.value);
        bar.classList.toggle('show', sel.length > 0);
        cnt.textContent = sel.length + ' ta tanlandi';
        exp.href = base + '&export=csv&ids=' + encodeURIComponent(sel.join(','));
        if (all) all.checked = sel.length === boxes.length && boxes.length > 0;
        boxes.forEach(b => b.closest('tr').classList.toggle('row-selected', b.checked));
    };
    boxes.forEach(b => b.addEventListener('change', sync));
    if (all) all.addEventListener('change', () => { boxes.forEach(b => b.checked = all.checked); sync(); });
    document.getElementById('bulkClear').addEventListener('click', () => { boxes.forEach(b => b.checked = false); sync(); });
    // Qatorni bosish — tafsilot (checkbox va havolalardan tashqari)
    document.querySelectorAll('tr[data-href]').forEach(tr => tr.addEventListener('click', e => {
        if (e.target.closest('input,a,button')) return;
        location.href = tr.dataset.href;
    }));
})();
</script>
<?php include 'includes/footer.php'; ?>
