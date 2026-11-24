<?php
/**
 * H1 · Haydovchilar ro'yxati (Figma «Admin panel» 04).
 *
 * Haydovchi = role 'owner' (MoveX GO Driver va mijoz ilovasidagi egalar).
 * Tablar edge case bo'yicha: tekshiruvda, rad etilgan, hujjati tugayapti
 * (30 kundan kam), muddati o'tgan, bloklangan, hujjatsiz. Manfiy (bo'sh)
 * mablag' — qizil: komissiya qarzi bizda yo'q (naqd komissiya oldindan
 * muzlatiladi), lekin balansi muzlatilgandan kam bo'lsa, buyurtma ololmaydi.
 *
 * Profil va bloklash — user.php (umumiy).
 */
require_once 'config.php';
requireAdmin();
requireCsrfToken();
require_once __DIR__ . '/includes/user_lib.php';

$pageTitle = 'Haydovchilar';
$currentPage = 'haydovchilar';
$db = getDbConnection();

$q = trim((string) ($_GET['q'] ?? ''));
$tab = $_GET['tab'] ?? 'all';
$tabs = [
    'all' => 'Hammasi',
    'pending' => 'Tekshiruvda',
    'rejected' => 'Rad etilgan',
    'expiring' => 'Hujjati tugayapti',
    'expired' => "Muddati o'tgan",
    'blocked' => 'Bloklangan',
    'nodocs' => 'Hujjatsiz',
];
if (!isset($tabs[$tab])) {
    $tab = 'all';
}

$docAgg = "SELECT user_id,
                  COUNT(*) AS docs,
                  COUNT(*) FILTER (WHERE status = 'pending') AS pend,
                  COUNT(*) FILTER (WHERE status = 'rejected') AS rej,
                  COUNT(*) FILTER (WHERE status = 'rejected' AND reject_reason LIKE 'Muddati o''tgan%') AS exp,
                  MIN(expires_on) FILTER (WHERE status = 'approved' AND expires_on IS NOT NULL) AS next_exp
             FROM driver_documents GROUP BY user_id";
$base = "FROM users u
         LEFT JOIN ($docAgg) d ON d.user_id = u.id
         LEFT JOIN (" . perfStatsSql() . ") s ON s.uid = u.id
         LEFT JOIN balances b ON b.user_id = u.id
         LEFT JOIN delivery_driver_profiles p ON p.user_id = u.id
         LEFT JOIN delivery_vehicles v ON v.code = p.vehicle_code
         WHERE u.role = 'owner' AND u.phone NOT LIKE 'deleted-%'";
$tabWhere = [
    'all' => 'TRUE',
    'pending' => 'COALESCE(d.pend, 0) > 0',
    'rejected' => 'COALESCE(d.rej, 0) > COALESCE(d.exp, 0)',
    'expiring' => "d.next_exp IS NOT NULL AND d.next_exp < CURRENT_DATE + 30",
    'expired' => 'COALESCE(d.exp, 0) > 0',
    'blocked' => 'u.is_blocked',
    'nodocs' => 'd.user_id IS NULL',
];

$where = [$tabWhere[$tab]];
$params = [];
if ($q !== '') {
    $digits = preg_replace('/\D/', '', $q);
    $cond = 'u.full_name ILIKE ? OR p.plate ILIKE ?';
    $params[] = '%' . $q . '%';
    $params[] = '%' . $q . '%';
    $cond .= ' OR EXISTS (SELECT 1 FROM equipment e WHERE e.owner_id = u.id AND e.plate_number ILIKE ?)';
    $params[] = '%' . $q . '%';
    if ($digits !== '') {
        $cond .= ' OR u.phone LIKE ?';
        $params[] = '%' . $digits . '%';
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

$perPage = 30;
$pages = max(1, (int) ceil($total / $perPage));
$page = min($pages, max(1, (int) ($_GET['page'] ?? 1)));
$offset = ($page - 1) * $perPage;
$st = $db->prepare("SELECT u.id, u.full_name, u.phone, u.created_at, u.last_login_at, u.is_blocked, u.is_frozen, u.blocked_until,
                           COALESCE(d.docs, 0) AS docs, COALESCE(d.pend, 0) AS pend, COALESCE(d.rej, 0) AS rej, COALESCE(d.exp, 0) AS exp, d.next_exp,
                           COALESCE(s.done, 0) AS done, COALESCE(s.earned, 0) AS earned,
                           COALESCE(b.balance, 0) - COALESCE(b.frozen_balance, 0) AS available,
                           p.plate, p.is_online, v.name AS truck,
                           (SELECT string_agg(DISTINCT e.type, ',') FROM equipment e WHERE e.owner_id = u.id AND e.deleted_at IS NULL) AS eq_types,
                           (SELECT ROUND(AVG(r.rating)::numeric, 1) FROM reviews r JOIN equipment e ON e.id = r.equipment_id
                             WHERE e.owner_id = u.id AND NOT r.hidden) AS rating
                    $base AND $whereSql
                    ORDER BY COALESCE(d.pend, 0) DESC, u.created_at DESC
                    LIMIT $perPage OFFSET $offset");
$st->execute($params);
$rows = $st->fetchAll();

function hqs(array $over = []): string
{
    $p = array_filter(array_merge($_GET, $over), function ($v) { return $v !== '' && $v !== null; });
    return '?' . http_build_query($p);
}

/** Hujjatlar holati: [matn, rang] */
function docBadge(array $r): array
{
    if ((int) $r['docs'] === 0) return ['Hujjatsiz', 'secondary'];
    if ((int) $r['exp'] > 0) return ["Muddati o'tgan", 'danger'];
    if ((int) $r['rej'] > 0) return ['Rad etilgan', 'danger'];
    if ((int) $r['pend'] > 0) return ['Tekshiruvda · ' . (int) $r['pend'], 'warning'];
    if ($r['next_exp'] && strtotime($r['next_exp']) < strtotime('+30 days')) {
        return ['Tugayapti · ' . date('d.m.Y', strtotime($r['next_exp'])), 'warning'];
    }
    return ['Tasdiqlangan', 'success'];
}

include 'includes/header.php';
?>
<div class="content">
    <div class="page-head">
        <div>
            <h2>Haydovchilar</h2>
            <div class="sub">Texnika egalari va yuk mashinasi haydovchilari (MoveX GO Driver)</div>
        </div>
    </div>

    <div class="tabs">
        <?php foreach ($tabs as $k => $label): ?>
            <a href="<?= htmlspecialchars(hqs(['tab' => $k, 'page' => null])) ?>" class="<?= $tab === $k ? 'active' : '' ?>">
                <?= $label ?> <span class="nav-count <?= in_array($k, ['expired', 'pending'], true) && $counts[$k] ? 'danger' : '' ?>"><?= $counts[$k] ?></span>
            </a>
        <?php endforeach; ?>
    </div>

    <form class="filters" method="get">
        <input type="hidden" name="tab" value="<?= htmlspecialchars($tab) ?>">
        <div class="filter-search">
            <i data-lucide="search"></i>
            <input type="search" name="q" value="<?= htmlspecialchars($q) ?>" placeholder="Ism, telefon yoki davlat raqami">
        </div>
        <button class="btn btn-secondary btn-sm" type="submit">Qidirish</button>
        <?php if ($q !== ''): ?><a class="btn btn-ghost btn-sm" href="haydovchilar.php?tab=<?= $tab ?>">Tozalash</a><?php endif; ?>
    </form>

    <div class="card">
        <?php if (!$rows): ?>
            <div class="empty-state"><i data-lucide="user-round-search"></i><div><b>Haydovchi topilmadi</b></div></div>
        <?php else: ?>
            <div class="table-responsive"><table>
                <thead><tr><th>Haydovchi</th><th>Texnika / mashina</th><th>Hujjatlar</th><th class="text-right">Bajargan</th>
                    <th class="text-right">Reyting</th><th class="text-right">Bo'sh mablag'</th><th>Holat</th><th>Oxirgi kirish</th><th style="width:40px"></th></tr></thead>
                <tbody>
                <?php foreach ($rows as $r):
                    [$dt, $dc] = docBadge($r);
                    [$ut, $uc] = userStatusBadge($r);
                    $href = 'user.php?id=' . (int) $r['id'];
                    $types = array_filter(explode(',', (string) $r['eq_types']));
                    $what = [];
                    if ($r['truck']) $what[] = $r['truck'] . ($r['plate'] ? ' · ' . $r['plate'] : '');
                    foreach ($types as $tp) $what[] = equipmentTypeName($tp);
                ?>
                    <tr data-href="<?= $href ?>" class="<?= $r['is_blocked'] || (int) $r['exp'] > 0 ? 'row-alert' : '' ?>">
                        <td><div class="person" style="margin:0"><div class="user-avatar"><?= htmlspecialchars(initials($r['full_name'])) ?></div>
                            <div><a href="<?= $href ?>"><b><?= htmlspecialchars($r['full_name']) ?></b></a><small class="num" style="white-space:nowrap"><?= htmlspecialchars(fmtPhone($r['phone'])) ?></small></div></div></td>
                        <td><?= $what ? htmlspecialchars(implode(', ', $what)) : '<span class="text-muted">—</span>' ?>
                            <?php if ($r['truck']): ?><span class="sub"><?= $r['is_online'] ? '● onlayn' : 'oflayn' ?></span><?php endif; ?></td>
                        <td><span class="badge badge-<?= $dc ?>"><?= htmlspecialchars($dt) ?></span></td>
                        <td class="text-right num"><?= (int) $r['done'] ?><span class="sub"><?= moneyFmt($r['earned']) ?></span></td>
                        <td class="text-right num"><?= $r['rating'] ? $r['rating'] . ' ★' : '—' ?></td>
                        <td class="text-right num <?= (float) $r['available'] < 0 ? 'text-danger' : '' ?>"><?= moneyFmt($r['available']) ?></td>
                        <td><span class="badge badge-<?= $uc ?>"><?= htmlspecialchars($ut) ?></span></td>
                        <td class="text-muted"><?= lastSeenText($r['last_login_at']) ?></td>
                        <td><a href="<?= $href ?>" class="icon-btn" aria-label="Ochish"><i data-lucide="chevron-right"></i></a></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table></div>
            <div class="table-foot">
                <span class="text-muted"><?= $offset + 1 ?>–<?= $offset + count($rows) ?> / <?= $total ?> ta</span>
                <div class="pagination" style="padding:0">
                    <?php for ($i = max(1, $page - 2); $i <= min($pages, $page + 2); $i++): ?>
                        <?= $i === $page ? '<span class="active">' . $i . '</span>' : '<a href="' . htmlspecialchars(hqs(['page' => $i])) . '">' . $i . '</a>' ?>
                    <?php endfor; ?>
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
