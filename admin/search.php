<?php
/**
 * Umumiy qidiruv (yuqori paneldagi maydon, Ctrl+K).
 * Raqam — buyurtma ID (hamma turdagi) va telefon; matn — ism, texnika
 * modeli, davlat raqami (texnika va yuk mashinasi).
 */
require_once 'config.php';
requireAdmin();

$pageTitle = 'Qidiruv';
$currentPage = '';
$db = getDbConnection();

$q = trim((string) ($_GET['q'] ?? ''));
$digits = preg_replace('/\D+/', '', $q);
$like = '%' . str_replace(['%', '_'], ['\%', '\_'], mb_strtolower($q)) . '%';

$results = ['orders' => [], 'users' => [], 'vehicles' => []];

if ($q !== '') {
    // Buyurtma ID: «123», «#123», «MX-123»
    if ($digits !== '' && strlen($digits) <= 9) {
        $id = (int) $digits;
        $st = $db->prepare("
            SELECT 'equipment' AS kind, o.id, o.status, o.total_amount AS amount, o.created_at, u.full_name AS client
              FROM orders o LEFT JOIN users u ON u.id = o.user_id WHERE o.id = :id1
            UNION ALL
            SELECT 'freight', f.id, f.status, f.price, f.created_at, u.full_name
              FROM freight_orders f LEFT JOIN users u ON u.id = f.client_id WHERE f.id = :id2
            UNION ALL
            SELECT 'material', m.id, m.status, m.total_amount, m.created_at, u.full_name
              FROM material_orders m LEFT JOIN users u ON u.id = m.buyer_id WHERE m.id = :id3");
        $st->execute([':id1' => $id, ':id2' => $id, ':id3' => $id]);
        $results['orders'] = $st->fetchAll();
    }

    // Foydalanuvchi: telefon (kamida 4 raqam) yoki ism
    $params = [':like' => $like];
    $phoneSql = '';
    if (strlen($digits) >= 4) {
        $phoneSql = ' OR phone LIKE :phone';
        $params[':phone'] = '%' . $digits . '%';
    }
    $st = $db->prepare("SELECT id, full_name, phone, role, is_blocked, created_at FROM users
                         WHERE LOWER(full_name) LIKE :like $phoneSql
                         ORDER BY created_at DESC LIMIT 20");
    $st->execute($params);
    $results['users'] = $st->fetchAll();

    // Davlat raqami / model
    $plateLike = '%' . preg_replace('/\s+/', '', mb_strtolower($q)) . '%';
    $st = $db->prepare("
        SELECT 'equipment' AS kind, e.id, e.type, e.model AS name,
               e.plate_number AS plate, u.full_name AS owner, u.phone AS owner_phone
          FROM equipment e LEFT JOIN users u ON u.id = e.owner_id
         WHERE e.deleted_at IS NULL
           AND (LOWER(REPLACE(COALESCE(e.plate_number,''),' ','')) LIKE :plate1 OR LOWER(e.model) LIKE :like)
        UNION ALL
        SELECT 'truck', d.user_id, d.vehicle_code, d.vehicle_code, d.plate, u.full_name, u.phone
          FROM delivery_driver_profiles d LEFT JOIN users u ON u.id = d.user_id
         WHERE LOWER(REPLACE(COALESCE(d.plate,''),' ','')) LIKE :plate2
         LIMIT 20");
    $st->execute([':plate1' => $plateLike, ':plate2' => $plateLike, ':like' => $like]);
    $results['vehicles'] = $st->fetchAll();
}

$kindLabel = ['equipment' => 'Texnika', 'freight' => 'Yuk tashish', 'material' => 'Material'];
$kindHref = [
    'equipment' => 'orders.php?id=',
    'freight' => 'orders.php?kind=freight&id=',
    'material' => 'orders.php?kind=material&id=',
];
$total = count($results['orders']) + count($results['users']) + count($results['vehicles']);

include 'includes/header.php';
?>
<div class="content">
    <div class="page-head">
        <div>
            <h2>Qidiruv</h2>
            <div class="sub"><?= $q === '' ? 'Buyurtma ID, telefon, ism yoki davlat raqamini yozing' :
                '«' . htmlspecialchars($q) . '» — ' . $total . ' ta natija' ?></div>
        </div>
    </div>

    <?php if ($q !== '' && $total === 0): ?>
        <div class="card"><div class="empty-state"><i data-lucide="search-x"></i><div>Hech narsa topilmadi</div></div></div>
    <?php endif; ?>

    <?php if ($results['orders']): ?>
        <div class="card">
            <div class="card-header"><div class="card-title">Buyurtmalar</div></div>
            <div class="table-responsive"><table>
                <thead><tr><th>ID</th><th>Turi</th><th>Mijoz</th><th>Holat</th><th class="text-right">Summa</th><th>Sana</th></tr></thead>
                <tbody>
                <?php foreach ($results['orders'] as $o): ?>
                    <tr>
                        <td><a href="<?= $kindHref[$o['kind']] . (int) $o['id'] ?>">#<?= (int) $o['id'] ?></a></td>
                        <td><?= $kindLabel[$o['kind']] ?></td>
                        <td><?= htmlspecialchars($o['client'] ?? '—') ?></td>
                        <td><span class="badge badge-secondary"><?= htmlspecialchars($o['status']) ?></span></td>
                        <td class="text-right num"><?= number_format((float) $o['amount'], 0, '.', ' ') ?></td>
                        <td class="text-muted"><?= date('d.m.Y H:i', strtotime($o['created_at'])) ?></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table></div>
        </div>
    <?php endif; ?>

    <?php if ($results['users']): ?>
        <div class="card">
            <div class="card-header"><div class="card-title">Foydalanuvchilar</div></div>
            <div class="table-responsive"><table>
                <thead><tr><th>Ism</th><th>Telefon</th><th>Rol</th><th>Holat</th><th>Ro'yxatdan o'tgan</th></tr></thead>
                <tbody>
                <?php foreach ($results['users'] as $u): ?>
                    <tr>
                        <td><a href="users.php?search=<?= urlencode($u['phone']) ?>"><?= htmlspecialchars($u['full_name']) ?></a></td>
                        <td class="num">+<?= htmlspecialchars($u['phone']) ?></td>
                        <td><?= htmlspecialchars($u['role']) ?></td>
                        <td><?= $u['is_blocked'] ? '<span class="badge badge-danger">Bloklangan</span>' : '<span class="badge badge-success">Faol</span>' ?></td>
                        <td class="text-muted"><?= date('d.m.Y', strtotime($u['created_at'])) ?></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table></div>
        </div>
    <?php endif; ?>

    <?php if ($results['vehicles']): ?>
        <div class="card">
            <div class="card-header"><div class="card-title">Texnika va yuk mashinalari</div></div>
            <div class="table-responsive"><table>
                <thead><tr><th>Davlat raqami</th><th>Nomi</th><th>Egasi</th><th>Turi</th></tr></thead>
                <tbody>
                <?php foreach ($results['vehicles'] as $v): ?>
                    <tr>
                        <td class="num"><b><?= htmlspecialchars($v['plate'] ?: '—') ?></b></td>
                        <td><?= htmlspecialchars($v['kind'] === 'equipment' ? equipmentTypeName($v['type']) . ' ' . $v['name'] : $v['name']) ?></td>
                        <td><a href="users.php?search=<?= urlencode((string) $v['owner_phone']) ?>"><?= htmlspecialchars($v['owner'] ?? '—') ?></a></td>
                        <td><?= $v['kind'] === 'equipment' ? 'Texnika' : 'Yuk mashinasi' ?></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table></div>
        </div>
    <?php endif; ?>
</div>
<?php include 'includes/footer.php'; ?>
