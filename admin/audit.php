<?php
/**
 * S9 · Audit jurnali, S10 · o'zgarish tafsiloti (Figma «Admin panel» 09).
 *
 * Manba — admin_actions: panel (auditLog) ham, backend ichki manzillari
 * ham yozadi. Faqat o'qish: tahrirlash va o'chirish yo'q. Rad etilgan
 * kirishlar admin_login_attempts dan qo'shiladi («Kirish rad etildi»).
 */
require_once 'config.php';
require_once 'includes/user_lib.php';
requireAdmin();
requirePerm('audit');

$db = getDbConnection();
$db->exec("SET TIME ZONE 'Asia/Tashkent'");
$pageTitle = 'Sozlamalar / Audit jurnali';
$currentPage = 'audit';

const AUDIT_LABELS = [
    'admin_login' => ['Panelga kirdi', 'Kirish'], 'login_locked' => ['Kirish bloklandi (5 xato)', 'Kirish'],
    'login_failed' => ['Kirish rad etildi', 'Kirish'], 'admin_password_reset' => ['Parolni tikladi', 'Kirish'],
    'admin_invited' => ['Admin taklif qilindi', 'Adminlar'], 'admin_invite_revoked' => ['Taklif bekor qilindi', 'Adminlar'],
    'admin_invite_accepted' => ['Taklifni qabul qildi', 'Adminlar'], 'admin_role_changed' => ['Admin roli o\'zgardi', 'Adminlar'],
    'admin_disabled' => ['Admin o\'chirildi', 'Adminlar'], 'admin_enabled' => ['Admin qayta faol', 'Adminlar'],
    'admin_devices_reset' => ['Qurilmalar unutildi', 'Adminlar'], 'roles_changed' => ['Rol ruxsatlari o\'zgardi', 'Adminlar'],
    'order_cancel' => ['Buyurtma bekor qilindi', 'Buyurtmalar'], 'order_reassign' => ['Ijrochi qayta tayinlandi', 'Buyurtmalar'],
    'order_requeue' => ['Qayta qidiruvga qaytarildi', 'Buyurtmalar'], 'order_note' => ['Ichki izoh', 'Buyurtmalar'],
    'dispute_resolve' => ['Nizo hal qilindi', 'Nizolar'], 'dispute_assign' => ['Nizo biriktirildi', 'Nizolar'],
    'support_close' => ['Chat yopildi', 'Yordam'], 'review_hide' => ['Sharh moderatsiyasi', 'Sharhlar'],
    'user_block' => ['Foydalanuvchi bloklandi', 'Foydalanuvchilar'], 'user_unblock' => ['Blokdan chiqarildi', 'Foydalanuvchilar'],
    'user_message' => ['Xabar yuborildi', 'Foydalanuvchilar'], 'user_sms' => ['SMS yuborildi', 'Foydalanuvchilar'],
    'user_freeze' => ['Muzlatildi', 'Foydalanuvchilar'], 'user_unfreeze' => ['Muzlatish olindi', 'Foydalanuvchilar'],
    'user_role' => ['Rol o\'zgardi', 'Foydalanuvchilar'], 'user_phone' => ['Telefon o\'zgardi', 'Foydalanuvchilar'],
    'user_password' => ['Parol o\'zgardi', 'Foydalanuvchilar'], 'user_grant_bonus' => ['Sovg\'a berildi', 'Moliya'],
    'user_cash_topup' => ['Naqd pul qabul qilindi', 'Moliya'], 'user_listing_fee' => ['E\'lon narxi o\'zgardi', 'Foydalanuvchilar'],
    'equipment_review' => ['Texnika tekshirildi', 'Texnika'], 'doc_review' => ['Hujjat ko\'rib chiqildi', 'Hujjatlar'],
    'payout_pay' => ['Pul yechish tasdiqlandi', 'Moliya'], 'payout_reject' => ['Pul yechish rad etildi', 'Moliya'],
    'settings_changed' => ['Sozlama o\'zgardi', 'Sozlamalar'], 'tariff_changed' => ['Tarif o\'zgardi', 'Sozlamalar'],
    'zone_changed' => ['Hudud o\'zgardi', 'Sozlamalar'], 'catalog_changed' => ['Katalog o\'zgardi', 'Sozlamalar'],
    'maintenance_on' => ['Texnik ishlar yoqildi', 'Sozlamalar'], 'maintenance_off' => ['Texnik ishlar o\'chirildi', 'Sozlamalar'],
    'listing_close' => ["E'lon yopildi", 'Buyurtmalar'], 'material_approve' => ['Material tasdiqlandi', 'Texnika'],
    'material_reject' => ['Material rad etildi', 'Texnika'], 'payout_sync' => ['Pul yechish holati tekshirildi', 'Moliya'],
    'push_draft' => ['Push qoralama', 'Push'], 'push_scheduled' => ['Push rejalashtirildi', 'Push'],
    'push_sent' => ['Push yuborildi', 'Push'], 'push_cancelled' => ['Push bekor qilindi', 'Push'], 'push_test' => ['Sinov push', 'Push'],
];
function auditLabel(string $a): string { return AUDIT_LABELS[$a][0] ?? str_replace('_', ' ', ucfirst($a)); }
function auditSection(string $a): string { return AUDIT_LABELS[$a][1] ?? 'Boshqa'; }

function entityLink(string $entity, $id): string {
    if ($id === null || $id === '') return '';
    $id = (int) $id;
    $map = ['user' => "user.php?id=$id", 'admin' => 'admins.php', 'dispute' => "problems.php?id=$id",
            'equipment' => "texnika.php?id=$id", 'push' => "push.php?id=$id",
            'order' => "orders.php?kind=order&id=$id", 'freight' => "orders.php?kind=freight&id=$id",
            'material' => "orders.php?kind=material&id=$id", 'request' => "orders.php?kind=request&id=$id"];
    return $map[$entity] ?? '';
}
function entityText(string $entity, $id): string {
    $names = ['user' => 'Foydalanuvchi', 'admin' => 'Admin', 'dispute' => 'Nizo', 'equipment' => 'Texnika', 'push' => 'Push',
              'order' => 'Buyurtma', 'freight' => 'Yuk', 'material' => 'Material', 'request' => 'Zayavka', 'support' => 'Chat',
              'review' => 'Sharh', 'settings' => 'Sozlamalar', 'payout' => 'Pul yechish', 'tariff' => 'Tarif', 'zone' => 'Hudud',
              'document' => 'Hujjat', 'login' => 'Kirish'];
    return ($names[$entity] ?? $entity) . ($id !== null && $id !== '' ? ' #' . $id : '');
}

// ------------------------------------------------------------- filtrlar
$period = $_GET['period'] ?? 'today';
$periods = ['today' => 'Bugun', '7d' => '7 kun', '30d' => '30 kun', 'all' => 'Hammasi'];
if (!isset($periods[$period])) $period = 'today';
$adminF = (int) ($_GET['admin'] ?? 0);
$sectionF = (string) ($_GET['section'] ?? '');
$q = trim((string) ($_GET['q'] ?? ''));
$showFails = !isset($_GET['nofails']);

$where = [];
$params = [];
$whereL = ["NOT l.success"];
$paramsL = [];
$since = ['today' => "date_trunc('day', NOW())", '7d' => "NOW() - INTERVAL '7 days'", '30d' => "NOW() - INTERVAL '30 days'", 'all' => "'epoch'"][$period];
$where[] = "a.created_at >= $since";
$whereL[] = "l.created_at >= $since";
if ($adminF) { $where[] = 'a.admin_id = ?'; $params[] = $adminF; $whereL[] = 'l.user_id = ?'; $paramsL[] = $adminF; }
if ($sectionF !== '') {
    $acts = array_keys(array_filter(AUDIT_LABELS, fn($v) => $v[1] === $sectionF));
    if ($acts) { $where[] = 'a.action IN (' . implode(',', array_fill(0, count($acts), '?')) . ')'; $params = array_merge($params, $acts); }
    if ($sectionF !== 'Kirish') $showFails = false;
}
if ($q !== '') {
    $where[] = "(a.entity_id::text = ? OR a.ip ILIKE ? OR x.full_name ILIKE ? OR a.payload::text ILIKE ?)";
    array_push($params, ltrim($q, '#'), "%$q%", "%$q%", "%$q%");
    $whereL[] = "(l.ip ILIKE ? OR l.login ILIKE ?)";
    array_push($paramsL, "%$q%", "%$q%");
}

$perPage = 25;
$page = max(1, (int) ($_GET['page'] ?? 1));
$offset = ($page - 1) * $perPage;

$sqlA = "SELECT 'a' AS src, a.id, a.created_at, a.admin_id, x.full_name, COALESCE(x.admin_role,'super_admin') AS admin_role,
                a.action, a.entity, a.entity_id::text AS entity_id, a.payload::text AS payload, a.ip, a.user_agent
         FROM admin_actions a LEFT JOIN users x ON x.id = a.admin_id WHERE " . implode(' AND ', $where);
$sqlL = "SELECT 'l' AS src, l.id, l.created_at, l.user_id, NULL, NULL, 'login_failed', 'login', l.login,
                json_build_object('stage', l.stage)::text, l.ip, l.user_agent
         FROM admin_login_attempts l WHERE " . implode(' AND ', $whereL);
$union = $showFails ? "($sqlA) UNION ALL ($sqlL)" : $sqlA;
$allParams = $showFails ? array_merge($params, $paramsL) : $params;

$cnt = $db->prepare("SELECT COUNT(*) FROM ($union) t");
$cnt->execute($allParams);
$total = (int) $cnt->fetchColumn();
$pages = max(1, (int) ceil($total / $perPage));
if (isset($_GET['export'])) {
    // CSV — joriy filtrlar bo'yicha, 50 000 qatorgacha (Figma E10: katta hajm cheklanadi).
    $ex = $db->prepare("SELECT * FROM ($union) t ORDER BY created_at DESC LIMIT 50000");
    $ex->execute($allParams);
    auditLog('audit_export', 'settings', null, ['period' => $period, 'rows' => $total]);
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="audit_' . date('Y-m-d_Hi') . '.csv"');
    $out = fopen('php://output', 'w');
    fwrite($out, "\xEF\xBB\xBF");
    fputcsv($out, ['Vaqt', 'Admin', 'Harakat', 'Obyekt', 'IP', 'Qurilma', "Ma'lumot"]);
    foreach ($ex as $r) {
        fputcsv($out, [$r['created_at'], $r['src'] === 'l' ? "Noma'lum" : ($r['full_name'] ?: 'Avto'), auditLabel((string) $r['action']),
                       $r['entity'] . ($r['entity_id'] !== null ? ' #' . $r['entity_id'] : ''), $r['ip'], uaShort($r['user_agent']), $r['payload']]);
    }
    exit;
}
$st = $db->prepare("SELECT * FROM ($union) t ORDER BY created_at DESC LIMIT $perPage OFFSET $offset");
$st->execute($allParams);
$rows = $st->fetchAll();

// S10 tafsilot
$detail = null;
if (isset($_GET['id'])) {
    $d = $db->prepare("SELECT a.*, x.full_name, COALESCE(x.admin_role,'super_admin') AS admin_role FROM admin_actions a
                       LEFT JOIN users x ON x.id = a.admin_id WHERE a.id = ?");
    $d->execute([(int) $_GET['id']]);
    $detail = $d->fetch() ?: null;
}

$admins = $db->query("SELECT id, full_name FROM users WHERE role = 'admin' ORDER BY full_name")->fetchAll();
$sections = array_values(array_unique(array_column(AUDIT_LABELS, 1)));
function aqs(array $over = []): string {
    $p = array_merge($_GET, $over);
    unset($p['id']);
    return 'audit.php?' . http_build_query(array_filter($p, fn($v) => $v !== null && $v !== ''));
}
function scalarText($v): string {
    if (is_bool($v)) return $v ? 'ha' : "yo'q";
    if ($v === null) return '—';
    if (is_array($v)) return json_encode($v, JSON_UNESCAPED_UNICODE);
    return (string) $v;
}

include 'includes/header.php';
?>
<div class="content">
    <div class="page-head">
        <div><h2>Audit jurnali</h2><div class="sub">Barcha admin harakatlari · o'zgartirib yoki o'chirib bo'lmaydi</div></div>
        <div class="page-actions"><a class="btn btn-secondary" href="<?= htmlspecialchars(aqs(['export' => 1, 'page' => null])) ?>"><i data-lucide="download"></i> Eksport</a></div>
    </div>

    <form class="filters" method="get">
        <div class="filter-search"><i data-lucide="search"></i>
            <input type="search" name="q" value="<?= htmlspecialchars($q) ?>" placeholder="Obyekt ID, admin, IP yoki matn"></div>
        <select name="period" onchange="this.form.submit()"><?php foreach ($periods as $k => $v): ?><option value="<?= $k ?>" <?= $k === $period ? 'selected' : '' ?>><?= $v ?></option><?php endforeach; ?></select>
        <select name="admin" onchange="this.form.submit()"><option value="">Admin: hammasi</option>
            <?php foreach ($admins as $a): ?><option value="<?= (int) $a['id'] ?>" <?= $adminF === (int) $a['id'] ? 'selected' : '' ?>><?= htmlspecialchars($a['full_name']) ?></option><?php endforeach; ?></select>
        <select name="section" onchange="this.form.submit()"><option value="">Bo'lim: hammasi</option>
            <?php foreach ($sections as $s): ?><option <?= $sectionF === $s ? 'selected' : '' ?>><?= htmlspecialchars($s) ?></option><?php endforeach; ?></select>
        <button class="btn btn-secondary btn-sm" type="submit">Qidirish</button>
        <?php if ($q !== '' || $adminF || $sectionF !== '' || $period !== 'today'): ?><a class="btn btn-ghost btn-sm" href="audit.php">Tozalash</a><?php endif; ?>
    </form>

    <div class="card">
        <?php if (!$rows): ?>
            <div class="empty-state"><i data-lucide="history"></i><div><b>Bu davrda harakat yo'q</b></div><div>Davrni kengaytiring yoki filtrni olib tashlang.</div></div>
        <?php else: ?>
        <div class="table-responsive"><table>
            <thead><tr><th style="width:150px">Vaqt</th><th>Admin</th><th>Harakat</th><th>Obyekt</th><th>IP / qurilma</th><th style="width:40px"></th></tr></thead>
            <tbody>
            <?php foreach ($rows as $r):
                $p = json_decode((string) $r['payload'], true) ?: [];
                $fail = $r['src'] === 'l';
                $sub = $p['reason'] ?? ($p['note'] ?? ($p['text'] ?? ''));
                if (!$sub && isset($p['name'])) $sub = $p['name'] . (isset($p['role']) ? ' · ' . (ADMIN_ROLES[$p['role']] ?? $p['role']) : '');
                if ($fail) $sub = ['password' => "Noto'g'ri parol", 'sms' => "Noto'g'ri SMS kod", 'reset' => 'Parolni tiklash kodi'][$p['stage'] ?? ''] ?? '';
                $href = $fail ? '' : aqs(['id' => null]) . '&id=' . (int) $r['id'];
                $link = $fail ? '' : entityLink((string) $r['entity'], $r['entity_id']);
            ?>
                <tr class="<?= $fail || $r['action'] === 'login_locked' ? 'audit-fail' : '' ?>" <?= $href ? 'data-href="' . htmlspecialchars($href) . '"' : '' ?>>
                    <td class="num"><?= date('d.m H:i:s', strtotime($r['created_at'])) ?></td>
                    <td><?php if ($fail): ?>Noma'lum<small class="sub">—</small>
                        <?php elseif ($r['full_name']): ?><b><?= htmlspecialchars($r['full_name']) ?></b><small class="sub"><?= ADMIN_ROLES[$r['admin_role']] ?? '' ?></small>
                        <?php else: ?><span class="badge badge-secondary">Avto</span><?php endif; ?></td>
                    <td><b><?= htmlspecialchars(auditLabel((string) $r['action'])) ?></b><?php if ($sub): ?><small class="sub"><?= htmlspecialchars(mb_strimwidth((string) $sub, 0, 80, '…')) ?></small><?php endif; ?></td>
                    <td><?php if ($fail): ?><span class="num"><?= htmlspecialchars((string) $r['entity_id']) ?></span>
                        <?php elseif ($link): ?><a href="<?= htmlspecialchars($link) ?>"><?= htmlspecialchars(entityText((string) $r['entity'], $r['entity_id'])) ?></a>
                        <?php else: ?><?= htmlspecialchars(entityText((string) $r['entity'], $r['entity_id'])) ?><?php endif; ?></td>
                    <td><span class="num"><?= htmlspecialchars($r['ip'] ?: '—') ?></span><small class="sub"><?= htmlspecialchars(uaShort($r['user_agent'])) ?></small></td>
                    <td><?php if ($href): ?><a class="icon-btn" href="<?= htmlspecialchars($href) ?>" aria-label="Tafsilot"><i data-lucide="chevron-right"></i></a><?php endif; ?></td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table></div>
        <div class="table-foot">
            <span class="text-muted"><?= $offset + 1 ?>–<?= $offset + count($rows) ?> / <?= number_format($total, 0, '', ' ') ?> ta</span>
            <div class="pagination" style="padding:0">
                <?php for ($i = max(1, $page - 2); $i <= min($pages, $page + 2); $i++): ?>
                    <?= $i === $page ? '<span class="active">' . $i . '</span>' : '<a href="' . htmlspecialchars(aqs(['page' => $i])) . '">' . $i . '</a>' ?>
                <?php endfor; ?>
            </div>
        </div>
        <?php endif; ?>
    </div>
</div>

<?php if ($detail):
    $p = json_decode((string) $detail['payload'], true) ?: [];
    $before = is_array($p['before'] ?? null) ? $p['before'] : null;
    $after = is_array($p['after'] ?? null) ? $p['after'] : null;
    $rest = array_diff_key($p, ['before' => 1, 'after' => 1]);
    $link = entityLink((string) $detail['entity'], $detail['entity_id']);
?>
<!-- S10 · O'zgarish tafsiloti -->
<div class="drawer active" id="auditDrawer">
    <div class="drawer-panel" role="dialog" aria-modal="true" aria-labelledby="adTitle">
        <div class="drawer-head"><div><div class="card-title" id="adTitle"><?= htmlspecialchars(auditLabel((string) $detail['action'])) ?></div>
            <div class="text-muted" style="font-size:12.5px"><?= date('d.m.Y, H:i:s', strtotime($detail['created_at'])) ?></div></div>
            <a class="icon-btn" href="<?= htmlspecialchars(aqs()) ?>" aria-label="Yopish"><i data-lucide="x"></i></a></div>
        <div class="drawer-body">
            <dl class="kv">
                <dt>Admin</dt><dd><?= $detail['full_name'] ? htmlspecialchars($detail['full_name']) . ' (' . (ADMIN_ROLES[$detail['admin_role']] ?? '') . ')' : 'Tizim (avto)' ?></dd>
                <dt>Obyekt</dt><dd><?= $link ? '<a href="' . htmlspecialchars($link) . '">' . htmlspecialchars(entityText((string) $detail['entity'], $detail['entity_id'])) . '</a>' : htmlspecialchars(entityText((string) $detail['entity'], $detail['entity_id'])) ?></dd>
                <dt>IP / qurilma</dt><dd><span class="num"><?= htmlspecialchars($detail['ip'] ?: '—') ?></span> · <?= htmlspecialchars(uaShort($detail['user_agent'])) ?></dd>
                <?php if (!empty($p['reason']) || !empty($p['note'])): ?><dt>Sabab</dt><dd><?= htmlspecialchars((string) ($p['reason'] ?? $p['note'])) ?></dd><?php endif; ?>
            </dl>
            <?php if ($before !== null || $after !== null):
                $keys = array_unique(array_merge(array_keys($before ?? []), array_keys($after ?? []))); ?>
                <div class="form-section">O'zgarishlar (<?= count($keys) ?>)</div>
                <table class="diff-table"><tbody>
                <?php foreach ($keys as $k): ?>
                    <tr><td><?= htmlspecialchars((string) $k) ?></td>
                        <td><span class="diff-old"><?= htmlspecialchars(scalarText($before[$k] ?? null)) ?></span></td>
                        <td><i data-lucide="arrow-right" style="width:14px;height:14px;color:var(--muted)"></i></td>
                        <td><span class="diff-new"><?= htmlspecialchars(scalarText($after[$k] ?? null)) ?></span></td></tr>
                <?php endforeach; ?>
                </tbody></table>
            <?php endif; ?>
            <?php $rest = array_diff_key($rest, ['reason' => 1, 'note' => 1]); if ($rest): ?>
                <div class="form-section">Ma'lumot</div>
                <dl class="kv"><?php foreach ($rest as $k => $v): ?><dt><?= htmlspecialchars((string) $k) ?></dt><dd><?= htmlspecialchars(scalarText($v)) ?></dd><?php endforeach; ?></dl>
            <?php endif; ?>
            <p class="text-muted" style="font-size:12px;margin-top:16px"><i data-lucide="lock" style="width:13px;height:13px;vertical-align:-2px"></i> Jurnal yozuvi o'zgartirilmaydi va o'chirilmaydi.</p>
        </div>
    </div>
</div>
<?php endif; ?>
<script>
document.querySelectorAll('tr[data-href]').forEach(tr => tr.addEventListener('click', e => {
    if (e.target.closest('a,button')) return;
    location.href = tr.dataset.href;
}));
</script>
<?php include 'includes/footer.php'; ?>
