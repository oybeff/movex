<?php
/**
 * F1 · To'lovlar (Figma «Admin panel» 06).
 *
 * Ikki manba bitta sahifada:
 *   tx   — balance_transactions: to'ldirish (Rahmat), to'lov, daromad,
 *          qaytarish, pul yechish, sovg'a, e'lon narxi;
 *   card — card_payments: kartadagi hold va yechish (tarifli buyurtma).
 * Jarima va chargeback bizda yo'q — ular ko'rsatilmaydi (soxta raqam yo'q).
 *
 * Faqat ko'rish va eksport: pul harakati bu sahifadan bo'lmaydi.
 */
require_once 'config.php';
requireAdmin();
requirePagePerm('finance');
requireCsrfToken();
require_once __DIR__ . '/includes/user_lib.php';

$pageTitle = "To'lovlar";
$currentPage = 'balance';
$db = getDbConnection();

$tab = $_GET['tab'] ?? 'all';
$q = trim((string) ($_GET['q'] ?? ''));
$period = $_GET['period'] ?? '30';

$txNames = ['topup' => "To'ldirish", 'payment' => "To'lov", 'income' => 'Daromad', 'refund' => 'Qaytarish',
            'withdrawal' => 'Pul yechish', 'bonus' => "Sovg'a", 'listing_fee' => "E'lon narxi"];
$tabs = [
    'all' => 'Hammasi',
    'ok' => 'Muvaffaqiyatli',
    'topup' => "To'ldirish",
    'payment' => "To'lovlar",
    'refund' => 'Qaytarish',
    'withdrawal' => 'Pul yechish',
    'fail' => 'Xato / bekor',
    'card' => 'Karta (hold)',
];
if (!isset($tabs[$tab])) {
    $tab = 'all';
}
$periodSql = ['today' => "CURRENT_DATE", '7' => "NOW() - INTERVAL '7 days'", '30' => "NOW() - INTERVAL '30 days'", 'all' => "'-infinity'"][$period] ?? "NOW() - INTERVAL '30 days'";

// ------------------------------------------------------------- KPI (bugun)
$kpi = $db->query("
    SELECT
      (SELECT COALESCE(SUM(amount), 0) FROM balance_transactions WHERE type = 'payment' AND status = 'completed' AND created_at >= CURRENT_DATE)
      + (SELECT COALESCE(SUM(amount), 0) FROM card_payments WHERE status = 'charged' AND updated_at >= CURRENT_DATE) AS turnover,
      (SELECT COALESCE(SUM(amount), 0) FROM budget_reserves WHERE created_at >= CURRENT_DATE) AS commission,
      (SELECT COALESCE(SUM(frozen_balance), 0) FROM balances) AS frozen,
      (SELECT COALESCE(SUM(amount), 0) FROM card_payments WHERE status = 'active') AS holds,
      (SELECT COUNT(*) FROM card_payments WHERE status = 'active') AS holds_n,
      (SELECT COUNT(*) FROM balance_transactions WHERE status IN ('canceled', 'failed') AND created_at >= CURRENT_DATE)
      + (SELECT COUNT(*) FROM card_payments WHERE status = 'failed' AND updated_at >= CURRENT_DATE) AS failed
")->fetch();

// ------------------------------------------------------------- ro'yxat
if ($tab === 'card') {
    $where = ["cp.created_at >= $periodSql"];
    $params = [];
    if ($q !== '') {
        $digits = preg_replace('/\D/', '', $q);
        $where[] = '(u.full_name ILIKE ?' . ($digits !== '' ? ' OR u.phone LIKE ? OR cp.order_id::text = ? OR cp.request_id::text = ?' : '') . ')';
        $params[] = '%' . $q . '%';
        if ($digits !== '') { $params[] = '%' . $digits . '%'; $params[] = $digits; $params[] = $digits; }
    }
    $listSql = "SELECT cp.id, cp.created_at, cp.amount, cp.status, cp.error, cp.order_id, cp.request_id, cp.user_id,
                       u.full_name, u.phone, c.pan, c.ps
                  FROM card_payments cp JOIN users u ON u.id = cp.user_id LEFT JOIN user_cards c ON c.id = cp.card_id
                 WHERE " . implode(' AND ', $where) . ' ORDER BY cp.created_at DESC';
} else {
    $tabWhere = [
        'all' => 'TRUE', 'ok' => "bt.status = 'completed'", 'topup' => "bt.type = 'topup'",
        'payment' => "bt.type IN ('payment', 'listing_fee')", 'refund' => "bt.type = 'refund'",
        'withdrawal' => "bt.type = 'withdrawal'", 'fail' => "bt.status IN ('canceled', 'failed')",
    ];
    $where = [$tabWhere[$tab], "bt.created_at >= $periodSql"];
    $params = [];
    if ($q !== '') {
        $digits = preg_replace('/\D/', '', $q);
        $where[] = '(u.full_name ILIKE ? OR bt.description ILIKE ?' . ($digits !== '' ? ' OR u.phone LIKE ? OR bt.id::text = ? OR bt.order_id::text = ?' : '') . ')';
        $params[] = '%' . $q . '%';
        $params[] = '%' . $q . '%';
        if ($digits !== '') { $params[] = '%' . $digits . '%'; $params[] = $digits; $params[] = $digits; }
    }
    $listSql = "SELECT bt.*, u.full_name, u.phone FROM balance_transactions bt JOIN users u ON u.id = bt.user_id
                 WHERE " . implode(' AND ', $where) . ' ORDER BY bt.created_at DESC';
}

if (($_GET['export'] ?? '') === 'csv') {
    $st = $db->prepare($listSql . ' LIMIT 100000');
    $st->execute($params);
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="tolovlar-' . date('Y-m-d') . '.csv"');
    $out = fopen('php://output', 'w');
    fwrite($out, "\xEF\xBB\xBF");
    if ($tab === 'card') {
        fputcsv($out, ['ID', 'Sana', 'Mijoz', 'Telefon', 'Buyurtma', 'Karta', 'Summa', 'Holat', 'Xato']);
        foreach ($st as $r) {
            fputcsv($out, [$r['id'], date('d.m.Y H:i', strtotime($r['created_at'])), $r['full_name'], $r['phone'],
                           $r['order_id'] ?: ('zayavka ' . $r['request_id']), strtoupper((string) $r['ps']) . ' ' . substr((string) $r['pan'], -4),
                           (int) $r['amount'], $r['status'], $r['error']]);
        }
    } else {
        fputcsv($out, ['ID', 'Sana', 'Foydalanuvchi', 'Telefon', 'Turi', 'Usul', 'Izoh', 'Buyurtma', 'Summa', 'Holat']);
        foreach ($st as $r) {
            fputcsv($out, [$r['id'], date('d.m.Y H:i', strtotime($r['created_at'])), $r['full_name'], $r['phone'],
                           $txNames[$r['type']] ?? $r['type'], $r['payment_method'], $r['description'], $r['order_id'], (int) $r['amount'], $r['status']]);
        }
    }
    fclose($out);
    exit;
}

$perPage = 50;
$total = $db->prepare("SELECT COUNT(*) FROM ($listSql) x");
$total->execute($params);
$total = (int) $total->fetchColumn();
$pages = max(1, (int) ceil($total / $perPage));
$page = min($pages, max(1, (int) ($_GET['page'] ?? 1)));
$offset = ($page - 1) * $perPage;
$st = $db->prepare($listSql . " LIMIT $perPage OFFSET $offset");
$st->execute($params);
$rows = $st->fetchAll();

function bqs(array $over = []): string
{
    $p = array_filter(array_merge($_GET, $over), function ($v) { return $v !== '' && $v !== null; });
    unset($p['export']);
    return '?' . http_build_query($p);
}

/** Holat yorlig'i: tushunarli sabab bilan. */
function txBadge(array $r): array
{
    switch ($r['status']) {
        case 'completed': return ['Muvaffaqiyatli', 'success'];
        case 'pending': return [$r['type'] === 'topup' ? "Kutilmoqda — to'lov tasdiqlanmagan" : 'Kutilmoqda', 'warning'];
        case 'canceled': return [$r['type'] === 'topup' ? "Bekor — to'lov bo'lmadi" : 'Bekor qilingan', 'secondary'];
        case 'failed': return ['Xato', 'danger'];
    }
    return [$r['status'], 'secondary'];
}

function cardBadge(array $r): array
{
    $m = ['active' => ['Hold — bloklangan', 'warning'], 'charged' => ['Yechildi', 'success'],
          'cancelled' => ['Hold yechildi (qaytdi)', 'secondary'], 'failed' => ['Xato', 'danger'],
          'unknown' => ["Noma'lum — shlyuz javobsiz", 'warning']];
    return $m[$r['status']] ?? [$r['status'], 'secondary'];
}

include 'includes/header.php';
?>
<div class="content">
    <div class="page-head">
        <div><h2>To'lovlar</h2>
            <div class="sub">Balans harakatlari (Rahmat / Multicard) va karta hold'lari · faqat ko'rish va eksport</div></div>
        <div class="page-actions">
            <?php if ($total > 0): ?><a class="btn btn-secondary btn-sm" href="<?= htmlspecialchars(bqs(['export' => 'csv'])) ?>"><i data-lucide="download"></i> Eksport (CSV)</a><?php endif; ?>
        </div>
    </div>

    <div class="stats-grid" style="grid-template-columns:repeat(4,minmax(0,1fr))">
        <div class="stat-card"><div class="stat-title"><i data-lucide="credit-card"></i> Aylanma (bugun)</div>
            <div class="stat-value"><?= moneyFmt($kpi['turnover']) ?></div><div class="stat-change">so'm · Go wallet va karta orqali to'lovlar</div></div>
        <div class="stat-card"><div class="stat-title"><i data-lucide="tag"></i> MoveX komissiyasi (bugun)</div>
            <div class="stat-value"><?= moneyFmt($kpi['commission']) ?></div><div class="stat-change"><a href="budget.php">Platforma daromadi →</a></div></div>
        <div class="stat-card"><div class="stat-title"><i data-lucide="lock"></i> Muzlatilgan</div>
            <div class="stat-value"><?= moneyFmt((float) $kpi['frozen'] + (float) $kpi['holds']) ?></div>
            <div class="stat-change">balanslarda <?= moneyFmt($kpi['frozen']) ?> · kartada <?= (int) $kpi['holds_n'] ?> ta hold</div></div>
        <div class="stat-card"><div class="stat-title"><i data-lucide="triangle-alert"></i> Muvaffaqiyatsiz (bugun)</div>
            <div class="stat-value <?= $kpi['failed'] ? 'text-danger' : '' ?>"><?= (int) $kpi['failed'] ?> ta</div>
            <div class="stat-change">bekor qilingan to'ldirish va karta xatolari</div></div>
    </div>

    <div class="tabs">
        <?php foreach ($tabs as $k => $label): ?>
            <a href="<?= htmlspecialchars(bqs(['tab' => $k, 'page' => null])) ?>" class="<?= $tab === $k ? 'active' : '' ?>"><?= $label ?></a>
        <?php endforeach; ?>
    </div>

    <form class="filters" method="get">
        <input type="hidden" name="tab" value="<?= htmlspecialchars($tab) ?>">
        <div class="filter-search"><i data-lucide="search"></i>
            <input type="search" name="q" value="<?= htmlspecialchars($q) ?>" placeholder="Tranzaksiya ID, buyurtma, ism, telefon"></div>
        <select name="period" onchange="this.form.submit()">
            <?php foreach (['today' => 'Bugun', '7' => '7 kun', '30' => '30 kun', 'all' => 'Butun davr'] as $k => $v): ?>
                <option value="<?= $k ?>" <?= $period === (string) $k ? 'selected' : '' ?>><?= $v ?></option>
            <?php endforeach; ?>
        </select>
        <button class="btn btn-secondary btn-sm" type="submit">Qidirish</button>
    </form>

    <div class="card">
        <?php if (!$rows): ?>
            <div class="empty-state"><i data-lucide="receipt"></i><div><b>Tanlangan davrda yozuv yo'q</b></div></div>
        <?php elseif ($tab === 'card'): ?>
            <div class="table-responsive"><table>
                <thead><tr><th>Hold</th><th>Buyurtma / mijoz</th><th>Karta</th><th class="text-right">Summa, so'm</th><th>Holat</th></tr></thead>
                <tbody>
                <?php foreach ($rows as $r): [$bt, $bc] = cardBadge($r); ?>
                    <tr class="<?= $r['status'] === 'failed' ? 'row-alert' : '' ?>">
                        <td><b>#C-<?= (int) $r['id'] ?></b><span class="sub"><?= date('d.m H:i', strtotime($r['created_at'])) ?></span></td>
                        <td><?php if ($r['order_id']): ?><a href="<?= orderHref('equipment', (int) $r['order_id']) ?>">#<?= (int) $r['order_id'] ?></a><?php else: ?><a href="<?= orderHref('request', (int) $r['request_id']) ?>">zayavka #<?= (int) $r['request_id'] ?></a><?php endif; ?>
                            <span class="sub"><a href="user.php?id=<?= (int) $r['user_id'] ?>"><?= htmlspecialchars($r['full_name']) ?></a></span></td>
                        <td class="num"><?= $r['pan'] ? htmlspecialchars(strtoupper((string) $r['ps'])) . ' •• ' . htmlspecialchars(substr((string) $r['pan'], -4)) : '—' ?></td>
                        <td class="text-right num"><?= moneyFmt($r['amount']) ?></td>
                        <td><span class="badge badge-<?= $bc ?>"><?= htmlspecialchars($bt) ?></span><?php if ($r['error']): ?><span class="sub text-danger"><?= htmlspecialchars($r['error']) ?></span><?php endif; ?></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table></div>
        <?php else: ?>
            <div class="table-responsive"><table>
                <thead><tr><th>Tranzaksiya</th><th>Foydalanuvchi</th><th>Turi</th><th>Izoh / buyurtma</th><th class="text-right">Summa, so'm</th><th>Holat</th></tr></thead>
                <tbody>
                <?php foreach ($rows as $r):
                    [$bt, $bc] = txBadge($r);
                    $plus = in_array($r['type'], ['topup', 'income', 'refund', 'bonus'], true);
                ?>
                    <tr class="<?= $r['status'] === 'failed' ? 'row-alert' : '' ?>">
                        <td><b>#TX-<?= (int) $r['id'] ?></b><span class="sub"><?= date('d.m.Y H:i', strtotime($r['created_at'])) ?></span></td>
                        <td><a href="user.php?id=<?= (int) $r['user_id'] ?>"><?= htmlspecialchars($r['full_name']) ?></a><span class="sub num"><?= htmlspecialchars(fmtPhone($r['phone'])) ?></span></td>
                        <td><span class="badge badge-secondary no-dot"><?= $txNames[$r['type']] ?? htmlspecialchars($r['type']) ?></span>
                            <?php if ($r['payment_method']): ?><span class="sub"><?= htmlspecialchars($r['payment_method']) ?><?= $r['rahmat_card_pan'] ? ' · •• ' . htmlspecialchars(substr((string) $r['rahmat_card_pan'], -4)) : '' ?></span><?php endif; ?></td>
                        <td style="font-size:12.5px"><?= htmlspecialchars((string) $r['description']) ?>
                            <?php if ($r['order_id']): ?><span class="sub"><a href="<?= orderHref('equipment', (int) $r['order_id']) ?>">buyurtma #<?= (int) $r['order_id'] ?></a></span><?php endif; ?></td>
                        <td class="text-right num <?= $plus ? 'text-success' : '' ?>"><?= ($plus ? '+' : '−') . moneyFmt($r['amount']) ?></td>
                        <td><span class="badge badge-<?= $bc ?>"><?= htmlspecialchars($bt) ?></span>
                            <?php if ($r['rahmat_status'] && $r['status'] !== 'completed'): ?><span class="sub">shlyuz: <?= htmlspecialchars($r['rahmat_status']) ?></span><?php endif; ?>
                            <?php if ($r['rahmat_receipt_url']): ?><span class="sub"><a href="<?= htmlspecialchars($r['rahmat_receipt_url']) ?>" target="_blank" rel="noopener">chek</a></span><?php endif; ?></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table></div>
        <?php endif; ?>
        <?php if ($rows): ?>
        <div class="table-foot"><span class="text-muted"><?= $offset + 1 ?>–<?= $offset + count($rows) ?> / <?= number_format($total, 0, '.', ' ') ?> ta</span>
            <div class="pagination" style="padding:0">
                <?php if ($page > 1): ?><a href="<?= htmlspecialchars(bqs(['page' => $page - 1])) ?>">‹</a><?php endif; ?>
                <?php for ($i = max(1, $page - 2); $i <= min($pages, $page + 2); $i++): ?>
                    <?= $i === $page ? '<span class="active">' . $i . '</span>' : '<a href="' . htmlspecialchars(bqs(['page' => $i])) . '">' . $i . '</a>' ?>
                <?php endfor; ?>
                <?php if ($page < $pages): ?><a href="<?= htmlspecialchars(bqs(['page' => $page + 1])) ?>">›</a><?php endif; ?>
            </div></div>
        <?php endif; ?>
    </div>
</div>
<style>.text-danger { color: var(--red-500); } .text-success { color: var(--green-600, #15803d); } .stat-title svg { width: 15px; height: 15px; vertical-align: -2px; }</style>
<?php include 'includes/footer.php'; ?>
