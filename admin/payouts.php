<?php
/**
 * Pul yechish arizalari.
 *
 * Texnika egasi ilovada ariza beradi, admin shu yerda ko'rib chiqadi.
 * Pul kartaga MULTICARD orqali o'tadi (POST /payment/credit) — admin bank
 * ilovasida qo'lda o'tkazmaydi.
 *
 * MUHIM: bu sahifa pulni O'ZI HARAKATLANTIRMAYDI. Ilgari harakatlantirardi
 * va payout_service dagi mantiqni takrorlardi — ikkisi ajralib ketishi
 * mumkin edi. Endi panel backend'ning ichki manziliga murojaat qiladi
 * (internalApiPost), ya'ni pul harakati BITTA joyda: payout_service.
 *
 * Uchta amal:
 *   pay    — kartaga o'tkazish (balansdan yechish faqat shlyuz
 *            tasdiqlaganidan keyin);
 *   reject — rad etish, pul egasida qoladi;
 *   sync   — holatni shlyuzdan so'rash. Javob kelmagan holat uchun:
 *            so'rovni QAYTARISH man etilgan, aks holda bir arizaga pul
 *            ikki marta ketardi.
 */
require_once 'config.php';
requireAdmin();
if (!adminCan('payouts') && !adminCan('finance')) requirePerm('payouts');
if ($_SERVER['REQUEST_METHOD'] === 'POST') requirePerm('payouts', 'full');
requireCsrfToken();
// Audit (S9): har bir o'zgartiruvchi so'rov jurnalga — maydonlar bilan.
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $auditFields = array_diff_key($_POST, ['csrf_token' => 1, 'password' => 1, 'new_password' => 1]);
    array_walk_recursive($auditFields, function (&$v) { $v = mb_substr((string) $v, 0, 200); });
    auditLog('payout_' . preg_replace('/\W/', '', (string) ($_POST['action'] ?? 'change')), 'payout', (int) ($_POST['request_id'] ?? 0) ?: null, $auditFields);
}


$pageTitle = 'Pul Yechish Arizalari';
$currentPage = 'payouts';

$db = getDbConnection();
$message = '';
$messageType = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'], $_POST['request_id'])) {
    $requestId = intval($_POST['request_id']);
    $action = $_POST['action'];
    $adminComment = sanitizeInput($_POST['admin_comment'] ?? '');

    $endpoints = [
        'paid'     => ['/payouts/internal/' . $requestId . '/pay',
                       'Pul kartaga o\'tkazildi, balansdan yechildi'],
        'rejected' => ['/payouts/internal/' . $requestId . '/reject',
                       'Ariza rad etildi, pul egasida qoldi'],
        'sync'     => ['/payouts/internal/' . $requestId . '/sync',
                       'Holat shlyuzdan yangilandi'],
    ];

    if (!isset($endpoints[$action])) {
        $message = 'Noma\'lum amal';
        $messageType = 'error';
    } else {
        [$path, $successMessage] = $endpoints[$action];
        $result = internalApiPost($path, [
            'admin_comment' => $adminComment ?: null,
            'admin_id' => $_SESSION['admin_user_id'] ?? null,
        ]);

        if ($result['ok']) {
            $status = $result['data']['status'] ?? '';
            $gateway = $result['data']['rahmat_status'] ?? '';
            $message = $successMessage;
            if ($action === 'sync' || ($status === 'pending' && $gateway !== '')) {
                // Pul yo'lda (draft/progress). Bu xato emas, lekin admin
                // "to'landi" deb o'ylab qolmasligi kerak.
                $message .= ' — holat: ' . ($gateway ?: $status);
            }
            $messageType = 'success';
        } else {
            $message = $result['error'];
            $messageType = 'error';
        }
    }
}

// ----------------------------------------------------------------- F2 · ro'yxat (Figma «Admin panel» 06)
require_once __DIR__ . '/includes/user_lib.php';

$tab = $_GET['tab'] ?? 'pending';
$q = trim((string) ($_GET['q'] ?? ''));
$tabWhere = [
    'pending' => "pr.status = 'pending' AND pr.rahmat_uuid IS NULL",
    'sent' => "pr.status = 'pending' AND pr.rahmat_uuid IS NOT NULL",
    'paid' => "pr.status = 'paid'",
    'bank' => "pr.status = 'rejected' AND pr.rahmat_error IS NOT NULL",
    'rejected' => "pr.status = 'rejected' AND pr.rahmat_error IS NULL",
    'all' => 'TRUE',
];
$tabNames = ['pending' => 'Kutilmoqda', 'sent' => 'Bankka yuborilgan', 'paid' => 'Bajarildi',
             'bank' => 'Bank rad etdi', 'rejected' => 'Rad etilgan', 'all' => 'Hammasi'];
if (!isset($tabWhere[$tab])) {
    $tab = 'pending';
}
$counts = [];
foreach ($tabWhere as $k => $w) {
    $counts[$k] = (int) $db->query("SELECT COUNT(*) FROM payout_requests pr WHERE $w")->fetchColumn();
}
$where = [$tabWhere[$tab]];
$params = [];
if ($q !== '') {
    $digits = preg_replace('/\D/', '', $q);
    $c = 'u.full_name ILIKE ?';
    $params[] = '%' . $q . '%';
    if ($digits !== '') {
        $c .= ' OR u.phone LIKE ? OR pr.id::text = ?';
        $params[] = '%' . $digits . '%';
        $params[] = $digits;
    }
    $where[] = '(' . $c . ')';
}
$selectSql = "SELECT pr.*, u.full_name, u.phone, u.is_blocked, u.is_frozen, u.role,
                   b.balance, b.frozen_balance, b.bonus_balance,
                   (SELECT COUNT(*) FROM payout_requests x WHERE x.user_id = pr.user_id AND x.created_at::date = pr.created_at::date) AS same_day,
                   (SELECT COUNT(*) FROM driver_documents d WHERE d.user_id = pr.user_id) AS docs,
                   (SELECT COUNT(*) FROM driver_documents d WHERE d.user_id = pr.user_id AND d.status <> 'approved') AS docs_bad,
                   a.full_name AS processed_name
              FROM payout_requests pr
              JOIN users u ON u.id = pr.user_id
              LEFT JOIN balances b ON b.user_id = pr.user_id
              LEFT JOIN users a ON a.id = pr.processed_by";
$listSql = $selectSql . ' WHERE ' . implode(' AND ', $where);

if (($_GET['export'] ?? '') === 'csv') {
    $st = $db->prepare($listSql . ' ORDER BY pr.created_at DESC LIMIT 50000');
    $st->execute($params);
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="pul-yechish-' . date('Y-m-d') . '.csv"');
    $out = fopen('php://output', 'w');
    fwrite($out, "\xEF\xBB\xBF");
    fputcsv($out, ['ID', 'Sana', 'Haydovchi', 'Telefon', "So'ralgan", 'Ulush', "O'tkaziladi", 'Karta', 'Holat', 'Shlyuz', 'Xato']);
    foreach ($st as $r) {
        fputcsv($out, [$r['id'], date('d.m.Y H:i', strtotime($r['created_at'])), $r['full_name'], $r['phone'], (int) $r['amount'],
                       (int) $r['commission'], (int) $r['payout_amount'], '**** ' . substr(preg_replace('/\D/', '', $r['card_number']), -4),
                       $r['status'], $r['rahmat_status'], $r['rahmat_error']]);
    }
    fclose($out);
    exit;
}

$perPage = 30;
$total = $db->prepare("SELECT COUNT(*) FROM ($listSql) x");
$total->execute($params);
$total = (int) $total->fetchColumn();
$pages = max(1, (int) ceil($total / $perPage));
$page = min($pages, max(1, (int) ($_GET['page'] ?? 1)));
$offset = ($page - 1) * $perPage;
$st = $db->prepare($listSql . ' ORDER BY pr.created_at ' . ($tab === 'pending' ? 'ASC' : 'DESC') . " LIMIT $perPage OFFSET $offset");
$st->execute($params);
$requests = $st->fetchAll();

const BIG_PAYOUT = 5000000;

/**
 * Avtomatik tekshiruvlar (F2/F4): [[matn, 'danger'|'warning'], ...].
 * Qizil — o'tkazishdan oldin albatta tekshirish kerak. Ikkinchi admin
 * tasdig'i (4-eyes) yo'q — egasi qarori (24.11.2026), faqat belgi.
 */
function payoutChecks(array $r): array
{
    $out = [];
    if ($r['is_blocked']) $out[] = ['Akkaunt bloklangan', 'danger'];
    if ($r['is_frozen']) $out[] = ['Akkaunt muzlatilgan', 'danger'];
    if ((int) $r['docs'] > 0 && (int) $r['docs_bad'] > 0) $out[] = ['Hujjatlar tasdiqlanmagan', 'danger'];
    if ((int) $r['same_day'] > 3) $out[] = ['Kunlik limit: ' . (int) $r['same_day'] . "-so'rov", 'danger'];
    if ($r['status'] === 'pending' && (float) $r['balance'] < (float) $r['amount']) $out[] = ['Balans yetmaydi', 'danger'];
    $holder = mb_strtolower(trim((string) $r['card_holder']));
    if ($holder !== '') {
        $hit = false;
        foreach (preg_split('/\s+/', mb_strtolower((string) $r['full_name'])) as $w) {
            if (mb_strlen($w) >= 3 && mb_strpos($holder, mb_substr($w, 0, 4)) !== false) {
                $hit = true;
            }
        }
        if (!$hit) $out[] = ['Karta egasi ismi mos kelmaydi?', 'warning'];
    }
    if ((float) $r['amount'] >= BIG_PAYOUT) $out[] = ['Katta summa (5 mln dan ortiq)', 'warning'];
    return $out;
}

function pqs(array $over = []): string
{
    $p = array_filter(array_merge($_GET, $over), function ($v) { return $v !== '' && $v !== null; });
    unset($p['export']);
    return '?' . http_build_query($p);
}

function hasDanger(array $checks): bool
{
    foreach ($checks as $c) {
        if ($c[1] === 'danger') return true;
    }
    return false;
}

// ----------------------------------------------------------------- F3 · tafsilot
$detail = null;
if (isset($_GET['id'])) {
    $d = $db->prepare($selectSql . ' WHERE pr.id = ?');
    $d->execute([(int) $_GET['id']]);
    $detail = $d->fetch() ?: null;
}
$autoRow = $db->query("SELECT value #>> '{}' FROM app_settings WHERE key = 'payout_auto_enabled'")->fetchColumn();
$auto = $autoRow === '1';

include 'includes/header.php';
?>
<div class="content">
    <?php if ($message): ?>
        <div class="alert alert-<?= $messageType === 'success' ? 'success' : 'error' ?>"><?= htmlspecialchars($message) ?></div>
    <?php endif; ?>

    <div class="page-head">
        <div><h2>Pul yechish so'rovlari</h2>
            <div class="sub">Haydovchi ilovasi → «Pul yechish» · Multicard orqali kartaga · ulush ariza summasidan ushlanadi</div></div>
        <div class="page-actions">
            <a class="btn btn-secondary btn-sm" href="commission.php"><i data-lucide="sliders-horizontal"></i> Qoidalar</a>
            <?php if ($total > 0): ?><a class="btn btn-secondary btn-sm" href="<?= htmlspecialchars(pqs(['export' => 'csv'])) ?>"><i data-lucide="download"></i> Eksport</a><?php endif; ?>
        </div>
    </div>

    <div class="alert alert-info"><i data-lucide="info"></i>
        <div><b>Avtomatik rejim <?= $auto ? 'yoqilgan' : "o'chirilgan" ?>.</b>
            <?= $auto ? "So'rov yaratilishi bilan pul kartaga yuboriladi." : "Har bir so'rovni admin «Kartaga o'tkazish» bilan yuboradi." ?>
            Natija noma'lum bo'lsa qayta yuborish MAN — faqat «Holatni tekshirish».</div>
    </div>

    <?php if ($detail):
        $checks = payoutChecks($detail);
        $bankErr = $detail['status'] === 'rejected' && $detail['rahmat_error'];
        $digitsD = preg_replace('/\D/', '', $detail['card_number']);
    ?>
    <div class="card" id="detail">
        <div class="card-header"><div><div class="card-title">W-<?= (int) $detail['id'] ?> · <?= moneyFmt($detail['amount']) ?> so'm</div>
            <div class="text-muted" style="font-size:12.5px"><?= htmlspecialchars($detail['full_name']) ?> · •••• <?= htmlspecialchars(substr($digitsD, -4)) ?><?= $detail['card_holder'] ? ' · ' . htmlspecialchars($detail['card_holder']) : '' ?></div></div>
            <a class="icon-btn" href="<?= htmlspecialchars(pqs(['id' => null])) ?>" aria-label="Yopish"><i data-lucide="x"></i></a></div>
        <div class="card-body">
            <?php if ($bankErr): ?>
                <div class="banner danger"><i data-lucide="triangle-alert"></i><div><b>Bank rad etdi: <?= htmlspecialchars($detail['rahmat_error']) ?></b>
                    <div class="sub">Ko'p hollarda karta bloklangan yoki onlayn o'tkazmalar o'chirilgan. Pul haydovchi balansida qoldi (muzlatish yechildi).</div></div></div>
            <?php endif; ?>
            <ul class="timeline">
                <li class="done"><span class="dot"><i data-lucide="check"></i></span><div><div class="t">So'rov yaratildi</div>
                    <div class="s">Haydovchi ilovasi · ulush <?= moneyFmt($detail['commission']) ?> · kartaga <?= moneyFmt($detail['payout_amount']) ?></div></div>
                    <span class="time"><?= date('d.m H:i', strtotime($detail['created_at'])) ?></span></li>
                <li class="<?= hasDanger($checks) ? 'bad' : 'done' ?>"><span class="dot"><?= hasDanger($checks) ? '' : '<i data-lucide="check"></i>' ?></span>
                    <div><div class="t">Avtomatik tekshiruvlar</div>
                    <div class="s"><?= $checks ? htmlspecialchars(implode(' · ', array_map(function ($c) { return $c[0]; }, $checks))) : 'Hujjatlar ✓ · balans ✓ · kunlik limit ✓' ?></div></div></li>
                <li class="<?= $detail['rahmat_uuid'] ? 'done' : ($detail['status'] === 'pending' ? 'now' : 'todo') ?>"><span class="dot"><?= $detail['rahmat_uuid'] ? '<i data-lucide="check"></i>' : '' ?></span>
                    <div><div class="t">Bankka yuborildi</div><div class="s"><?= $detail['rahmat_uuid'] ? 'Multicard · ref ' . htmlspecialchars(substr($detail['rahmat_uuid'], 0, 12)) . ($detail['rahmat_status'] ? ' · ' . htmlspecialchars($detail['rahmat_status']) : '') : 'hali yuborilmagan' ?></div></div></li>
                <?php if ($detail['status'] === 'paid'): ?>
                    <li class="done"><span class="dot"><i data-lucide="check"></i></span><div><div class="t">Kartaga tushdi</div>
                        <div class="s"><?= $detail['processed_name'] ? htmlspecialchars($detail['processed_name']) . ' · ' : '' ?><?php if ($detail['rahmat_receipt_url']): ?><a href="<?= htmlspecialchars($detail['rahmat_receipt_url']) ?>" target="_blank" rel="noopener">chek</a><?php endif; ?></div></div>
                        <span class="time"><?= $detail['processed_at'] ? date('d.m H:i', strtotime($detail['processed_at'])) : '' ?></span></li>
                <?php elseif ($detail['status'] === 'rejected'): ?>
                    <li class="bad"><span class="dot"></span><div><div class="t" style="color:var(--red-500)"><?= $bankErr ? 'Bank rad etdi' : 'Admin rad etdi' ?></div>
                        <div class="s"><?= htmlspecialchars($bankErr ? $detail['rahmat_error'] : ($detail['admin_comment'] ?: 'sabab yozilmagan')) ?></div></div>
                        <span class="time"><?= $detail['processed_at'] ? date('d.m H:i', strtotime($detail['processed_at'])) : '' ?></span></li>
                    <li class="done"><span class="dot"><i data-lucide="check"></i></span><div><div class="t">Balansga qaytarildi</div>
                        <div class="s">+ <?= moneyFmt($detail['amount']) ?> so'm muzlatishdan chiqdi · haydovchiga bildirishnoma</div></div></li>
                <?php endif; ?>
            </ul>
            <?php if ($bankErr): ?>
                <div class="form-section">Keyingi qadam</div>
                <div class="pay-rows">
                    <div class="r"><span>Qayta yuborish</span><b>haydovchi yangi so'rov beradi (karta bank bilan hal qilingach)</b></div>
                    <div class="r"><span>Shu kundagi so'rovlar</span><b><?= (int) $detail['same_day'] ?></b></div>
                </div>
            <?php endif; ?>
            <div class="d-flex gap-1 mt-2">
                <a class="btn btn-secondary btn-sm" href="user.php?id=<?= (int) $detail['user_id'] ?>"><i data-lucide="message-square"></i> Haydovchiga yozish</a>
                <?php if ($detail['status'] === 'pending' && ($detail['rahmat_uuid'] || $detail['rahmat_error'])): ?>
                    <form method="post"><input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                        <input type="hidden" name="request_id" value="<?= (int) $detail['id'] ?>">
                        <button class="btn btn-primary btn-sm" type="submit" name="action" value="sync"><i data-lucide="refresh-cw"></i> Holatni tekshirish</button></form>
                <?php endif; ?>
            </div>
        </div>
    </div>
    <?php endif; ?>

    <div class="tabs">
        <?php foreach ($tabNames as $k => $label): ?>
            <a href="<?= htmlspecialchars(pqs(['tab' => $k, 'page' => null, 'id' => null])) ?>" class="<?= $tab === $k ? 'active' : '' ?>">
                <?= $label ?> <span class="nav-count <?= $k === 'bank' && $counts[$k] ? 'danger' : '' ?>"><?= number_format($counts[$k], 0, '.', ' ') ?></span></a>
        <?php endforeach; ?>
    </div>

    <form class="filters" method="get">
        <input type="hidden" name="tab" value="<?= htmlspecialchars($tab) ?>">
        <div class="filter-search"><i data-lucide="search"></i>
            <input type="search" name="q" value="<?= htmlspecialchars($q) ?>" placeholder="Ism, telefon yoki so'rov raqami"></div>
        <button class="btn btn-secondary btn-sm" type="submit">Qidirish</button>
    </form>

    <div class="card">
        <?php if (!$requests): ?>
            <div class="empty-state"><i data-lucide="banknote"></i><div><b>So'rov yo'q</b></div></div>
        <?php else: ?>
        <div class="table-responsive"><table>
            <thead><tr><th>So'rov</th><th>Haydovchi / karta</th><th class="text-right">So'ralgan</th><th class="text-right">Ulush</th>
                <th class="text-right">O'tkaziladi</th><th>Holat / tekshiruv</th><th style="width:240px"></th></tr></thead>
            <tbody>
            <?php foreach ($requests as $r):
                $checks = $r['status'] === 'pending' ? payoutChecks($r) : [];
                $bad = hasDanger($checks);
                $digits = preg_replace('/\D/', '', $r['card_number']);
                $badges = ['pending' => [$r['rahmat_uuid'] ? 'info' : 'warning', $r['rahmat_uuid'] ? 'Bankda · ' . ($r['rahmat_status'] ?: 'kutilmoqda') : 'Kutilmoqda'],
                           'paid' => ['success', 'Bajarildi'],
                           'rejected' => ['danger', $r['rahmat_error'] ? 'Bank rad etdi' : 'Rad etilgan']];
                [$bc, $bt] = $badges[$r['status']] ?? ['secondary', $r['status']];
            ?>
                <tr class="<?= $bad || ($r['status'] === 'rejected' && $r['rahmat_error']) ? 'row-alert' : '' ?>">
                    <td><a href="<?= htmlspecialchars(pqs(['id' => (int) $r['id']])) ?>#detail"><b>W-<?= (int) $r['id'] ?></b></a><span class="sub"><?= date('d.m H:i', strtotime($r['created_at'])) ?></span></td>
                    <td><div class="person" style="margin:0"><div class="user-avatar"><?= htmlspecialchars(initials($r['full_name'])) ?></div>
                        <div><a href="user.php?id=<?= (int) $r['user_id'] ?>"><b><?= htmlspecialchars($r['full_name']) ?></b></a>
                        <small class="num" title="<?= htmlspecialchars(trim(chunk_split($digits, 4, ' '))) ?>">•••• <?= htmlspecialchars(substr($digits, -4)) ?><?= $r['card_holder'] ? ' · ' . htmlspecialchars($r['card_holder']) : '' ?></small></div></div></td>
                    <td class="text-right num"><?= moneyFmt($r['amount']) ?></td>
                    <td class="text-right num text-muted"><?= (float) $r['commission'] > 0 ? '− ' . moneyFmt($r['commission']) : '0' ?></td>
                    <td class="text-right num"><b><?= moneyFmt($r['payout_amount']) ?></b></td>
                    <td><span class="badge badge-<?= $bc ?>"><?= htmlspecialchars($bt) ?></span>
                        <?php foreach ($checks as $chk): ?><span class="sub <?= $chk[1] === 'danger' ? 'text-danger' : 'text-warning' ?>">● <?= htmlspecialchars($chk[0]) ?></span><?php endforeach; ?>
                        <?php if ($r['status'] !== 'pending' && $r['rahmat_error']): ?><span class="sub text-danger"><?= htmlspecialchars($r['rahmat_error']) ?></span><?php endif; ?>
                        <?php if ($r['admin_comment']): ?><span class="sub"><?= htmlspecialchars($r['admin_comment']) ?></span><?php endif; ?>
                    </td>
                    <td>
                        <?php if ($r['status'] === 'pending'): ?>
                            <form method="POST" class="d-flex gap-1" style="flex-wrap:wrap">
                                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                <input type="hidden" name="request_id" value="<?= (int) $r['id'] ?>">
                                <input type="hidden" name="admin_comment" value="">
                                <?php if ($r['rahmat_uuid'] || $r['rahmat_error']): ?>
                                    <button type="submit" name="action" value="sync" class="btn btn-secondary btn-sm">Holatni tekshirish</button>
                                <?php else: ?>
                                    <button type="submit" name="action" value="paid" class="btn btn-primary btn-sm"
                                        data-confirm="<?= htmlspecialchars(($bad ? "DIQQAT: tekshiruvda muammo bor!\n" : '') . 'Kartaga ' . moneyFmt($r['payout_amount']) . " so'm HOZIR o'tkaziladi. Balansdan " . moneyFmt($r['amount']) . " so'm yechiladi. Davom etasizmi?") ?>">Kartaga o'tkazish</button>
                                    <button type="submit" name="action" value="rejected" class="btn btn-sm" data-reject="1">Rad etish</button>
                                <?php endif; ?>
                            </form>
                        <?php else: ?>
                            <a class="btn btn-ghost btn-sm" href="<?= htmlspecialchars(pqs(['id' => (int) $r['id']])) ?>#detail">Tafsilot</a>
                        <?php endif; ?>
                    </td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table></div>
        <div class="table-foot"><span class="text-muted"><?= $offset + 1 ?>–<?= $offset + count($requests) ?> / <?= $total ?> ta</span>
            <div class="pagination" style="padding:0">
                <?php for ($i = max(1, $page - 2); $i <= min($pages, $page + 2); $i++): ?>
                    <?= $i === $page ? '<span class="active">' . $i . '</span>' : '<a href="' . htmlspecialchars(pqs(['page' => $i])) . '">' . $i . '</a>' ?>
                <?php endfor; ?>
            </div></div>
        <?php endif; ?>
    </div>
</div>
<style>.text-warning { color: var(--yellow-700); } .text-danger { color: var(--red-500); }</style>
<script>
document.querySelectorAll('[data-confirm]').forEach(b => b.addEventListener('click', e => {
    if (!confirm(b.dataset.confirm)) e.preventDefault();
}));
document.querySelectorAll('[data-reject]').forEach(b => b.addEventListener('click', e => {
    const c = prompt("Rad etish sababi (haydovchi ko'radi):");
    if (c === null) { e.preventDefault(); return; }
    b.form.admin_comment.value = c;
}));
</script>
<?php include 'includes/footer.php'; ?>
