<?php
/**
 * T1 · Texnika moderatsiyasi ro'yxati, T2 · tekshiruv (Figma «Admin panel» 04).
 *
 * Yangi qo'shilgan texnika (ko'rib chiqilmagan) tepada. Bir xil davlat
 * raqami boshqa egada ham bo'lsa — qizil qator: bitta mashinani ikki
 * odam o'ziniki deb qo'yishi firibgarlik belgisi.
 *
 * «Tekshirildi» texnikani katalogdan yashirmaydi va ochmaydi — bu admin
 * navbati uchun belgi (equipment.reviewed_at/by). Takroriy raqamda tugma
 * o'chiq, toki admin «tekshirdim» deb belgilamaguncha.
 * Xarita ko'rinishi — equipment.php.
 */
require_once 'config.php';
requireAdmin();
requireCsrfToken();
require_once __DIR__ . '/includes/user_lib.php';

$pageTitle = 'Texnika';
$currentPage = 'equipment';
$db = getDbConnection();
$adminId = (int) ($_SESSION['admin_user_id'] ?? 0);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $eid = (int) ($_POST['equipment_id'] ?? 0);
    if (($_POST['action'] ?? '') === 'review') {
        $db->prepare('UPDATE equipment SET reviewed_at = NOW(), reviewed_by = ? WHERE id = ?')->execute([$adminId, $eid]);
        $db->prepare("INSERT INTO admin_actions (admin_id, action, entity, entity_id, payload) VALUES (?, 'equipment_review', 'equipment', ?, ?::jsonb)")
           ->execute([$adminId, $eid, json_encode(['dup_confirmed' => !empty($_POST['dup_ok'])])]);
        $_SESSION['eq_flash'] = 'Texnika #' . $eid . ' tekshirildi';
    }
    header('Location: texnika.php?' . http_build_query(array_diff_key($_GET, ['id' => 1])));
    exit;
}
$flash = $_SESSION['eq_flash'] ?? null;
unset($_SESSION['eq_flash']);

$dupSql = "EXISTS (SELECT 1 FROM equipment e2 WHERE e2.id <> e.id AND e2.owner_id <> e.owner_id AND e2.deleted_at IS NULL
                   AND e.plate_number IS NOT NULL AND e.plate_number <> ''
                   AND upper(replace(e2.plate_number, ' ', '')) = upper(replace(e.plate_number, ' ', '')))";
$tab = $_GET['tab'] ?? 'new';
$tabWhere = [
    'new' => 'e.reviewed_at IS NULL',
    'dup' => $dupSql,
    'all' => 'TRUE',
];
$tabNames = ['new' => 'Yangi (tekshirilmagan)', 'dup' => 'Takroriy raqam', 'all' => 'Hammasi'];
if (!isset($tabWhere[$tab])) {
    $tab = 'new';
}
$q = trim((string) ($_GET['q'] ?? ''));
$base = "FROM equipment e JOIN users u ON u.id = e.owner_id WHERE e.deleted_at IS NULL";
$counts = [];
foreach ($tabWhere as $k => $w) {
    $counts[$k] = (int) $db->query("SELECT COUNT(*) $base AND $w")->fetchColumn();
}
$where = [$tabWhere[$tab]];
$params = [];
if ($q !== '') {
    $where[] = '(e.plate_number ILIKE ? OR e.model ILIKE ? OR u.full_name ILIKE ? OR u.phone LIKE ?)';
    array_push($params, '%' . $q . '%', '%' . $q . '%', '%' . $q . '%', '%' . preg_replace('/\D/', '', $q) . '%');
}
$sel = "SELECT e.*, u.full_name, u.phone, u.is_blocked, r.full_name AS reviewer, $dupSql AS dup,
               (SELECT COUNT(*) FROM equipment_photos p WHERE p.equipment_id = e.id) AS photos_n,
               (SELECT COUNT(*) FROM driver_documents d WHERE d.user_id = e.owner_id AND d.status = 'approved') AS docs_ok,
               (SELECT COUNT(*) FROM driver_documents d WHERE d.user_id = e.owner_id) AS docs_n
          {BASE}";
$listSql = str_replace('{BASE}', "FROM equipment e JOIN users u ON u.id = e.owner_id LEFT JOIN users r ON r.id = e.reviewed_by
                                     WHERE e.deleted_at IS NULL AND " . implode(' AND ', $where), $sel);
$perPage = 30;
$total = $db->prepare("SELECT COUNT(*) FROM ($listSql) x");
$total->execute($params);
$total = (int) $total->fetchColumn();
$pages = max(1, (int) ceil($total / $perPage));
$page = min($pages, max(1, (int) ($_GET['page'] ?? 1)));
$offset = ($page - 1) * $perPage;
$st = $db->prepare($listSql . ' ORDER BY dup DESC, e.created_at DESC' . " LIMIT $perPage OFFSET $offset");
$st->execute($params);
$rows = $st->fetchAll();

$detail = null;
if (isset($_GET['id'])) {
    $d = $db->prepare(str_replace('{BASE}', 'FROM equipment e JOIN users u ON u.id = e.owner_id LEFT JOIN users r ON r.id = e.reviewed_by WHERE e.id = ?', $sel));
    $d->execute([(int) $_GET['id']]);
    $detail = $d->fetch() ?: null;
    if ($detail) {
        $ph = $db->prepare('SELECT url FROM equipment_photos WHERE equipment_id = ? ORDER BY is_primary DESC, id');
        $ph->execute([$detail['id']]);
        $photos = array_column($ph->fetchAll(), 'url');
        if (!$photos && $detail['photo_url']) {
            $photos = [$detail['photo_url']];
        }
        $dups = [];
        if ($detail['dup']) {
            $dd = $db->prepare("SELECT e2.id, e2.model, e2.type, u2.id AS uid, u2.full_name, u2.is_blocked FROM equipment e2 JOIN users u2 ON u2.id = e2.owner_id
                                WHERE e2.id <> ? AND e2.owner_id <> ? AND e2.deleted_at IS NULL
                                  AND upper(replace(e2.plate_number, ' ', '')) = upper(replace(?, ' ', ''))");
            $dd->execute([$detail['id'], $detail['owner_id'], $detail['plate_number']]);
            $dups = $dd->fetchAll();
        }
    }
}

function tqs(array $over = []): string
{
    $p = array_filter(array_merge($_GET, $over), function ($v) { return $v !== '' && $v !== null; });
    return '?' . http_build_query($p);
}

include 'includes/header.php';
?>
<div class="content">
    <?php if ($flash): ?><div class="alert alert-success"><?= htmlspecialchars($flash) ?></div><?php endif; ?>
    <div class="page-head">
        <div><h2>Texnika</h2><div class="sub">Yangi qo'shilgan texnika tekshiruvi · takroriy davlat raqami — qizil</div></div>
        <div class="page-actions"><a class="btn btn-secondary btn-sm" href="equipment.php"><i data-lucide="map"></i> Xaritada</a></div>
    </div>

    <div class="tabs">
        <?php foreach ($tabNames as $k => $label): ?>
            <a href="<?= htmlspecialchars(tqs(['tab' => $k, 'page' => null, 'id' => null])) ?>" class="<?= $tab === $k ? 'active' : '' ?>">
                <?= $label ?> <span class="nav-count <?= $k === 'dup' && $counts[$k] ? 'danger' : '' ?>"><?= $counts[$k] ?></span></a>
        <?php endforeach; ?>
    </div>
    <form class="filters" method="get">
        <input type="hidden" name="tab" value="<?= htmlspecialchars($tab) ?>">
        <div class="filter-search"><i data-lucide="search"></i><input type="search" name="q" value="<?= htmlspecialchars($q) ?>" placeholder="Davlat raqami, model, egasi"></div>
        <button class="btn btn-secondary btn-sm" type="submit">Qidirish</button>
    </form>

    <div class="card">
        <?php if (!$rows): ?>
            <div class="empty-state"><i data-lucide="truck"></i><div><b><?= $tab === 'new' ? 'Hammasi tekshirilgan' : 'Texnika topilmadi' ?></b></div></div>
        <?php else: ?>
        <div class="table-responsive"><table>
            <thead><tr><th>Texnika</th><th>Davlat raqami</th><th>Egasi</th><th>Egasining hujjatlari</th><th>Qo'shilgan</th><th>Holat</th><th style="width:40px"></th></tr></thead>
            <tbody>
            <?php foreach ($rows as $r): $href = htmlspecialchars(tqs(['id' => (int) $r['id']])); ?>
                <tr class="<?= $r['dup'] ? 'row-alert' : '' ?>" data-href="<?= $href ?>">
                    <td><b><?= htmlspecialchars(equipmentTypeName($r['type'])) ?></b><span class="sub"><?= htmlspecialchars((string) $r['model']) ?> · <?= (int) $r['photos_n'] ?: ($r['photo_url'] ? 1 : 0) ?> ta foto</span></td>
                    <td class="num <?= $r['dup'] ? 'text-danger' : '' ?>"><?= htmlspecialchars((string) $r['plate_number']) ?: '—' ?><?= $r['dup'] ? '<span class="sub text-danger">takror!</span>' : '' ?></td>
                    <td><a href="user.php?id=<?= (int) $r['owner_id'] ?>"><?= htmlspecialchars($r['full_name']) ?></a><span class="sub num"><?= htmlspecialchars(fmtPhone($r['phone'])) ?></span></td>
                    <td><?= (int) $r['docs_n'] === 0 ? '<span class="text-muted">topshirmagan</span>' : (int) $r['docs_ok'] . ' / ' . (int) $r['docs_n'] . ' tasdiqlangan' ?></td>
                    <td class="num"><?= date('d.m.Y', strtotime($r['created_at'])) ?></td>
                    <td><?php if ($r['reviewed_at']): ?><span class="badge badge-success">Tekshirilgan</span><span class="sub"><?= htmlspecialchars($r['reviewer'] ?? 'avtomatik') ?></span>
                        <?php else: ?><span class="badge badge-warning">Yangi</span><?php endif; ?></td>
                    <td><a class="icon-btn" href="<?= $href ?>" aria-label="Ochish"><i data-lucide="chevron-right"></i></a></td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table></div>
        <div class="table-foot"><span class="text-muted"><?= $offset + 1 ?>–<?= $offset + count($rows) ?> / <?= $total ?> ta</span>
            <div class="pagination" style="padding:0">
                <?php for ($i = max(1, $page - 2); $i <= min($pages, $page + 2); $i++): ?>
                    <?= $i === $page ? '<span class="active">' . $i . '</span>' : '<a href="' . htmlspecialchars(tqs(['page' => $i])) . '">' . $i . '</a>' ?>
                <?php endfor; ?>
            </div></div>
        <?php endif; ?>
    </div>
</div>

<?php if ($detail): ?>
<!-- T2 · tekshiruv drawer -->
<div class="drawer active" id="eqDrawer" role="dialog" aria-modal="true">
    <div class="drawer-panel">
        <div class="modal-header"><div><div class="modal-title"><?= htmlspecialchars(equipmentTypeName($detail['type'])) ?> · <?= htmlspecialchars((string) $detail['model']) ?></div>
            <div class="text-muted" style="font-size:12.5px">#<?= (int) $detail['id'] ?> · <?= htmlspecialchars((string) $detail['plate_number']) ?: 'raqamsiz' ?> · qo'shilgan <?= date('d.m.Y', strtotime($detail['created_at'])) ?></div></div>
            <a class="modal-close" href="<?= htmlspecialchars(tqs(['id' => null])) ?>" aria-label="Yopish">×</a></div>
        <div class="modal-body">
            <?php if ($detail['dup']): ?>
                <div class="banner danger"><i data-lucide="copy"></i><div><b>Takroriy davlat raqami</b>
                    <div class="sub">Shu raqam boshqa egada ham bor:
                        <?php foreach ($dups as $x): ?><a href="user.php?id=<?= (int) $x['uid'] ?>"><?= htmlspecialchars($x['full_name']) ?></a> (#<?= (int) $x['id'] ?> <?= htmlspecialchars(equipmentTypeName($x['type'])) ?><?= $x['is_blocked'] ? ', BLOKLANGAN' : '' ?>) <?php endforeach; ?>
                        — texpasport egasini solishtiring.</div></div></div>
            <?php endif; ?>
            <div class="form-section" style="margin-top:0">Suratlar</div>
            <?php if (empty($photos)): ?><div class="text-muted">Surat yuklanmagan</div><?php else: ?>
                <div class="eq-photos"><?php foreach ($photos as $p): ?><a href="<?= htmlspecialchars($p) ?>" target="_blank" rel="noopener"><img src="<?= htmlspecialchars($p) ?>" alt=""></a><?php endforeach; ?></div>
            <?php endif; ?>
            <div class="form-section">Ma'lumotlar</div>
            <div class="pay-rows">
                <div class="r"><span>Egasi</span><b><a href="user.php?id=<?= (int) $detail['owner_id'] ?>"><?= htmlspecialchars($detail['full_name']) ?></a><?= $detail['is_blocked'] ? ' · bloklangan' : '' ?></b></div>
                <div class="r"><span>Egasining hujjatlari</span><b><?= (int) $detail['docs_n'] === 0 ? 'topshirmagan' : (int) $detail['docs_ok'] . ' / ' . (int) $detail['docs_n'] . ' tasdiqlangan' ?></b></div>
                <div class="r"><span>Yil / quvvat</span><b><?= htmlspecialchars(trim(($detail['year'] ?: '—') . ' / ' . ($detail['power_hp'] ? $detail['power_hp'] . ' o.k.' : '—'))) ?></b></div>
                <div class="r"><span>Narx (kun)</span><b><?= $detail['price_per_day'] ? moneyFmt($detail['price_per_day']) . " so'm" : '—' ?></b></div>
                <div class="r"><span>Manzil</span><b><?= htmlspecialchars((string) $detail['address']) ?: '—' ?></b></div>
                <div class="r"><span>Holat</span><b><?= htmlspecialchars((string) $detail['status']) ?></b></div>
            </div>
            <?php if ($detail['docs_n'] > 0): ?><a class="btn btn-secondary btn-sm mt-1" href="drivers.php?user=<?= (int) $detail['owner_id'] ?>"><i data-lucide="file-check-2"></i> Texpasportni ko'rish</a><?php endif; ?>
        </div>
        <div class="modal-footer">
            <?php if ($detail['reviewed_at']): ?>
                <span class="text-muted" style="margin-right:auto;font-size:13px">Tekshirilgan: <?= htmlspecialchars($detail['reviewer'] ?? 'avtomatik (eski texnika)') ?>, <?= date('d.m.Y H:i', strtotime($detail['reviewed_at'])) ?></span>
            <?php else: ?>
                <form method="post" class="d-flex gap-1 align-center" style="width:100%">
                    <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
                    <input type="hidden" name="action" value="review">
                    <input type="hidden" name="equipment_id" value="<?= (int) $detail['id'] ?>">
                    <?php if ($detail['dup']): ?>
                        <label class="d-flex gap-1 align-center" style="font-size:12.5px;margin-right:auto"><input type="checkbox" name="dup_ok" value="1" id="dupOk"> Takrorni tekshirdim — muammo yo'q</label>
                    <?php endif; ?>
                    <a class="btn btn-secondary" href="<?= htmlspecialchars(tqs(['id' => null])) ?>" style="margin-left:auto">Yopish</a>
                    <button class="btn btn-primary" type="submit" id="btnReview" <?= $detail['dup'] ? 'disabled' : '' ?>><i data-lucide="check"></i> Tekshirildi</button>
                </form>
            <?php endif; ?>
        </div>
    </div>
</div>
<?php endif; ?>
<style>
    .eq-photos { display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; }
    .eq-photos img { width: 100%; height: 140px; object-fit: cover; border-radius: 10px; background: var(--gray-100); }
    .text-danger { color: var(--red-500); }
</style>
<script>
document.querySelectorAll('tr[data-href]').forEach(tr => tr.addEventListener('click', e => {
    if (e.target.closest('a,button,input')) return;
    location.href = tr.dataset.href;
}));
(() => {
    const ok = document.getElementById('dupOk'), btn = document.getElementById('btnReview');
    if (ok && btn) ok.addEventListener('change', () => { btn.disabled = !ok.checked; });
    const dr = document.getElementById('eqDrawer');
    if (dr) dr.addEventListener('click', e => { if (e.target === dr) location.href = <?= json_encode(tqs(['id' => null])) ?>; });
})();
</script>
<?php include 'includes/footer.php'; ?>
