<?php
/**
 * C1 · Mijozlar ro'yxati (Figma «Admin panel» 03).
 *
 * Tablar: hammasi, faol (30 kun ichida kirgan), yangi (7 kun), ko'p bekor
 * qiluvchi (>30%, kamida 3 buyurtma), bloklangan, muzlatilgan, o'chirilgan
 * (C5: o'chirish o'zi bajariladi — ilovadan, 30 kun kutish yo'q).
 *
 * Statistika barcha buyurtma turlaridan (user_lib.clientStatsSql). Profil,
 * bloklash va boshqa amallar — user.php.
 */
require_once 'config.php';
requireAdmin();
requireCsrfToken();
require_once __DIR__ . '/includes/user_lib.php';

$pageTitle = 'Mijozlar';
$currentPage = 'users';
$db = getDbConnection();

// Eski havolalar: users.php?search=telefon — bitta topilsa, profilga
$q = trim((string) ($_GET['q'] ?? $_GET['search'] ?? ''));
$tab = $_GET['tab'] ?? 'all';
$tabs = [
    'all' => 'Hammasi',
    'active' => 'Faol (30 kun)',
    'new' => 'Yangi (7 kun)',
    'cancels' => "Ko'p bekor qiladi",
    'blocked' => 'Bloklangan',
    'frozen' => 'Muzlatilgan',
    'deleted' => "O'chirilgan",
];
if (!isset($tabs[$tab])) {
    $tab = 'all';
}
$sort = $_GET['sort'] ?? 'new';

$base = "FROM users u LEFT JOIN (" . clientStatsSql() . ") s ON s.uid = u.id WHERE u.role = 'client'";
$tabWhere = [
    'all' => "u.phone NOT LIKE 'deleted-%'",
    'active' => "u.phone NOT LIKE 'deleted-%' AND u.last_login_at > NOW() - INTERVAL '30 days'",
    'new' => "u.phone NOT LIKE 'deleted-%' AND u.created_at > NOW() - INTERVAL '7 days'",
    'cancels' => "u.phone NOT LIKE 'deleted-%' AND COALESCE(s.n, 0) >= 3 AND s.cx * 100 > s.n * 30",
    'blocked' => "u.phone NOT LIKE 'deleted-%' AND u.is_blocked",
    'frozen' => "u.phone NOT LIKE 'deleted-%' AND u.is_frozen",
    'deleted' => "u.phone LIKE 'deleted-%'",
];

$where = [$tabWhere[$tab]];
$params = [];
if ($q !== '') {
    $digits = preg_replace('/\D/', '', $q);
    $cond = 'u.full_name ILIKE ?';
    $params[] = '%' . $q . '%';
    if ($digits !== '') {
        $cond .= ' OR u.phone LIKE ?';
        $params[] = '%' . $digits . '%';
    }
    if (ctype_digit($q)) {
        $cond .= ' OR u.id = ?';
        $params[] = (int) $q;
    }
    $where[] = '(' . $cond . ')';
}
$whereSql = implode(' AND ', $where);

$counts = [];
foreach ($tabWhere as $k => $w) {
    $counts[$k] = (int) $db->query("SELECT COUNT(*) $base AND $w")->fetchColumn();
}

$total = $db->prepare("SELECT COUNT(*) $base AND $whereSql");
$total->execute($params);
$total = (int) $total->fetchColumn();

// Bitta topildi va eski havoladan kelindi — to'g'ri profilga
if (isset($_GET['search']) && $total === 1 && !isset($_GET['export'])) {
    $one = $db->prepare("SELECT u.id $base AND $whereSql");
    $one->execute($params);
    header('Location: user.php?id=' . (int) $one->fetchColumn());
    exit;
}

$orderBy = [
    'new' => 'u.created_at DESC',
    'orders' => 'COALESCE(s.n, 0) DESC, u.id DESC',
    'paid' => 'COALESCE(s.paid, 0) DESC, u.id DESC',
    'seen' => 'u.last_login_at DESC NULLS LAST',
][$sort] ?? 'u.created_at DESC';

$select = "SELECT u.id, u.full_name, u.phone, u.created_at, u.last_login_at, u.is_blocked, u.is_frozen,
                  u.blocked_until, COALESCE(s.n, 0) AS n, COALESCE(s.cx, 0) AS cx, COALESCE(s.paid, 0) AS paid
           $base AND $whereSql ORDER BY $orderBy";

if (($_GET['export'] ?? '') === 'csv') {
    $st = $db->prepare($select . ' LIMIT 50000');
    $st->execute($params);
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="mijozlar-' . date('Y-m-d') . '.csv"');
    $out = fopen('php://output', 'w');
    fwrite($out, "\xEF\xBB\xBF");
    fputcsv($out, ['ID', 'Ism', 'Telefon', "Ro'yxatdan", 'Buyurtmalar', "Jami to'lagan", 'Bekor %', 'Holat', 'Oxirgi kirish']);
    foreach ($st as $r) {
        $pct = cancelPct($r['n'], $r['cx']);
        fputcsv($out, [$r['id'], $r['full_name'], $r['phone'], date('d.m.Y', strtotime($r['created_at'])), $r['n'],
                       (int) $r['paid'], $pct === null ? '' : $pct, userStatusBadge($r, $pct)[0],
                       $r['last_login_at'] ? date('d.m.Y H:i', strtotime($r['last_login_at'])) : '']);
    }
    fclose($out);
    exit;
}

$perPage = 30;
$pages = max(1, (int) ceil($total / $perPage));
$page = min($pages, max(1, (int) ($_GET['page'] ?? 1)));
$offset = ($page - 1) * $perPage;
$st = $db->prepare($select . " LIMIT $perPage OFFSET $offset");
$st->execute($params);
$rows = $st->fetchAll();

function uqs(array $over = []): string
{
    $p = array_merge($_GET, $over);
    unset($p['export'], $p['search']);
    $p = array_filter($p, function ($v) { return $v !== '' && $v !== null; });
    return '?' . http_build_query($p);
}

include 'includes/header.php';
?>
<div class="content">
    <div class="page-head">
        <div>
            <h2>Mijozlar</h2>
            <div class="sub">Mijoz ilovasidan ro'yxatdan o'tganlar (telefon + SMS + PIN). Haydovchilar — alohida bo'limda.</div>
        </div>
        <div class="page-actions">
            <?php if ($total > 0): ?>
                <a class="btn btn-secondary btn-sm" href="<?= htmlspecialchars(uqs(['export' => 'csv'])) ?>"><i data-lucide="download"></i> Eksport (CSV)</a>
            <?php endif; ?>
        </div>
    </div>

    <div class="tabs">
        <?php foreach ($tabs as $k => $label): ?>
            <a href="<?= htmlspecialchars(uqs(['tab' => $k, 'page' => null])) ?>" class="<?= $tab === $k ? 'active' : '' ?>">
                <?= $label ?> <span class="nav-count <?= in_array($k, ['blocked'], true) && $counts[$k] ? 'danger' : '' ?>"><?= number_format($counts[$k], 0, '.', ' ') ?></span>
            </a>
        <?php endforeach; ?>
    </div>

    <form class="filters" method="get">
        <input type="hidden" name="tab" value="<?= htmlspecialchars($tab) ?>">
        <div class="filter-search">
            <i data-lucide="search"></i>
            <input type="search" name="q" value="<?= htmlspecialchars($q) ?>" placeholder="Ism, telefon yoki ID">
        </div>
        <select name="sort" onchange="this.form.submit()">
            <?php foreach (['new' => 'Yangilari tepada', 'orders' => "Ko'p buyurtma", 'paid' => "Ko'p to'lagan", 'seen' => 'Oxirgi kirish'] as $k => $v): ?>
                <option value="<?= $k ?>" <?= $sort === $k ? 'selected' : '' ?>><?= $v ?></option>
            <?php endforeach; ?>
        </select>
        <button class="btn btn-secondary btn-sm" type="submit">Qidirish</button>
        <?php if ($q !== ''): ?><a class="btn btn-ghost btn-sm" href="users.php?tab=<?= $tab ?>">Tozalash</a><?php endif; ?>
    </form>

    <?php if ($tab === 'deleted'): ?>
        <div class="alert alert-info"><i data-lucide="info"></i>
            <div>Akkauntni mijoz o'zi ilovadan o'chiradi (Google Play talabi). Ism va telefon o'chiriladi, buyurtma va
                to'lovlar ikkinchi tomon uchun saqlanadi. Ochiq nizo, balans yoki faol buyurtma bo'lsa — ilova o'chirishga ruxsat bermaydi.</div></div>
    <?php endif; ?>

    <div class="card">
        <?php if (!$rows): ?>
            <div class="empty-state">
                <i data-lucide="users"></i>
                <div><b>Hech kim topilmadi</b></div>
                <div class="mt-1"><?= $q !== '' ? '«' . htmlspecialchars($q) . '» bo\'yicha bu bo\'limda mijoz yo\'q.' : 'Bu bo\'limda hozircha mijoz yo\'q.' ?></div>
            </div>
        <?php else: ?>
            <div class="table-responsive"><table>
                <thead><tr>
                    <th>Mijoz</th><th>Ro'yxatdan o'tgan</th><th class="text-right">Buyurtmalar</th>
                    <th class="text-right">Jami to'lagan</th><th class="text-right">Bekor %</th><th>Holat</th><th>Oxirgi kirish</th><th style="width:40px"></th>
                </tr></thead>
                <tbody>
                <?php foreach ($rows as $r):
                    $pct = cancelPct($r['n'], $r['cx']);
                    [$bt, $bc] = userStatusBadge($r, $pct);
                    $href = 'user.php?id=' . (int) $r['id'];
                ?>
                    <tr data-href="<?= $href ?>" class="<?= $r['is_blocked'] ? 'row-alert' : '' ?>">
                        <td>
                            <div class="person" style="margin:0">
                                <div class="user-avatar"><?= htmlspecialchars(initials($r['full_name'])) ?></div>
                                <div><a href="<?= $href ?>"><b><?= htmlspecialchars($r['full_name'] ?: 'Ism kiritilmagan') ?></b></a>
                                    <small class="num" style="white-space:nowrap"><?= isDeletedUser($r) ? '—' : htmlspecialchars(fmtPhone($r['phone'])) ?></small></div>
                            </div>
                        </td>
                        <td class="num"><?= date('d.m.Y', strtotime($r['created_at'])) ?></td>
                        <td class="text-right num"><?= (int) $r['n'] ?></td>
                        <td class="text-right num"><?= moneyFmt($r['paid']) ?></td>
                        <td class="text-right num <?= $pct !== null && $pct > 30 ? 'text-danger' : '' ?>"><?= $pct === null ? '—' : $pct . '%' ?></td>
                        <td><span class="badge badge-<?= $bc ?>"><?= htmlspecialchars($bt) ?></span></td>
                        <td class="text-muted"><?= lastSeenText($r['last_login_at']) ?></td>
                        <td><a href="<?= $href ?>" class="icon-btn" aria-label="Ochish"><i data-lucide="chevron-right"></i></a></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table></div>
            <div class="table-foot">
                <span class="text-muted"><?= $offset + 1 ?>–<?= $offset + count($rows) ?> / <?= number_format($total, 0, '.', ' ') ?> ta</span>
                <div class="pagination" style="padding:0">
                    <?php if ($page > 1): ?><a href="<?= htmlspecialchars(uqs(['page' => $page - 1])) ?>">‹</a><?php endif; ?>
                    <?php for ($i = max(1, $page - 2); $i <= min($pages, $page + 2); $i++): ?>
                        <?= $i === $page ? '<span class="active">' . $i . '</span>' : '<a href="' . htmlspecialchars(uqs(['page' => $i])) . '">' . $i . '</a>' ?>
                    <?php endfor; ?>
                    <?php if ($page < $pages): ?><a href="<?= htmlspecialchars(uqs(['page' => $page + 1])) ?>">›</a><?php endif; ?>
                </div>
            </div>
        <?php endif; ?>
    </div>
</div>
<script>
document.querySelectorAll('tr[data-href]').forEach(tr => tr.addEventListener('click', e => {
    if (e.target.closest('input,a,button')) return;
    location.href = tr.dataset.href;
}));
</script>
<?php include 'includes/footer.php'; ?>
