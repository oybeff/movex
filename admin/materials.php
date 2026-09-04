<?php
/**
 * Qurilish materiallari: tovarlarni moderatsiya qilish va buyurtmalar.
 *
 * Nega moderatsiya bor. Katalog — xaridor birinchi ko'radigan joy, va u
 * yerdagi axlat butun bo'limni o'ldiradi. Shuning uchun sotuvchi tovar
 * qo'shadi, admin esa tasdiqlaydi. Tasdiqsiz tovar katalogda YO'Q va uni
 * sotib ham bo'lmaydi.
 *
 * Narx yoki og'irlik o'zgartirilsa, tovar QAYTA shu yerga tushadi: aks
 * holda tasdiqlangan tovarni keyin istalgan narsaga almashtirib qo'yish
 * mumkin bo'lardi.
 *
 * MUHIM: bu sahifa buyurtmalarning PULIGA tegmaydi. Pul harakati
 * backend'dagi material_service da: muzlatish, yechish va sotuvchiga
 * o'tkazish faqat o'sha yerda. Bu yerda ikkinchi nusxa yozilsa, ikkovi
 * ertami-kechmi bir-biridan ajralib qolardi — payouts.php bilan aynan
 * shunday bo'lgan.
 */
require_once 'config.php';
requireAdmin();
requireCsrfToken();

$pageTitle = 'Qurilish materiallari';
$currentPage = 'materials';

$db = getDbConnection();
$message = '';
$messageType = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    $productId = intval($_POST['product_id'] ?? 0);
    $comment = sanitizeInput($_POST['moderation_comment'] ?? '');

    if ($productId > 0 && in_array($_POST['action'], ['approve', 'reject'], true)) {
        $newStatus = $_POST['action'] === 'approve' ? 'approved' : 'rejected';
        $stmt = $db->prepare(
            "UPDATE material_products
                SET status = ?, moderation_comment = ?, updated_at = NOW()
              WHERE id = ?"
        );
        $stmt->execute([$newStatus, $comment ?: null, $productId]);

        $message = $newStatus === 'approved'
            ? "Tovar #$productId tasdiqlandi va katalogda ko'rinadi"
            : "Tovar #$productId rad etildi";
        $messageType = $newStatus === 'approved' ? 'success' : 'error';
    }
}

$tab = $_GET['tab'] ?? 'products';
if (!in_array($tab, ['products', 'orders'], true)) {
    $tab = 'products';
}

$statusFilter = $_GET['status'] ?? ($tab === 'products' ? 'pending' : '');

$stats = $db->query("
    SELECT
        COUNT(*) FILTER (WHERE status = 'pending')  AS pending,
        COUNT(*) FILTER (WHERE status = 'approved') AS approved,
        COUNT(*) FILTER (WHERE status = 'rejected') AS rejected,
        COUNT(*)                                    AS total
    FROM material_products
")->fetch();

$orderStats = $db->query("
    SELECT
        COUNT(*)                                          AS total,
        COUNT(*) FILTER (WHERE status = 'pending')        AS pending,
        COALESCE(SUM(total_amount) FILTER (WHERE status = 'delivered'), 0) AS turnover,
        COALESCE(SUM(commission)   FILTER (WHERE status = 'delivered'), 0) AS commission
    FROM material_orders
")->fetch();

// --- tovarlar ---
$productWhere = '';
$productParams = [];
if ($tab === 'products' && $statusFilter !== '' && $statusFilter !== 'all') {
    $productWhere = 'WHERE p.status = ?';
    $productParams[] = $statusFilter;
}

$products = [];
if ($tab === 'products') {
    $stmt = $db->prepare("
        SELECT p.*, u.full_name AS owner_name, u.phone AS owner_phone,
               (SELECT COUNT(*) FROM material_photos ph WHERE ph.product_id = p.id) AS photo_count,
               (SELECT COUNT(*) FROM material_orders o WHERE o.product_id = p.id) AS order_count
          FROM material_products p
          JOIN users u ON p.owner_id = u.id
          $productWhere
         ORDER BY
               -- Moderatsiya kutayotganlar eng tepada: sotuvchi kutib
               -- turibdi va tovari hech kimga ko'rinmayapti.
               CASE p.status WHEN 'pending' THEN 0 ELSE 1 END,
               p.created_at DESC
         LIMIT 100
    ");
    $stmt->execute($productParams);
    $products = $stmt->fetchAll();
}

// --- buyurtmalar ---
$orders = [];
if ($tab === 'orders') {
    $orderWhere = '';
    $orderParams = [];
    if ($statusFilter !== '' && $statusFilter !== 'all') {
        $orderWhere = 'WHERE o.status = ?';
        $orderParams[] = $statusFilter;
    }
    $stmt = $db->prepare("
        SELECT o.*, p.title AS product_title, p.material_type,
               b.full_name AS buyer_name, b.phone AS buyer_phone,
               s.full_name AS seller_name, s.phone AS seller_phone
          FROM material_orders o
          JOIN material_products p ON o.product_id = p.id
          JOIN users b ON o.buyer_id = b.id
          JOIN users s ON o.seller_id = s.id
          $orderWhere
         ORDER BY o.created_at DESC
         LIMIT 100
    ");
    $stmt->execute($orderParams);
    $orders = $stmt->fetchAll();
}

include 'includes/header.php';
?>

<div class="content">
    <?php if ($message): ?>
        <div class="alert alert-<?= $messageType === 'success' ? 'success' : 'danger' ?>">
            <?= htmlspecialchars($message) ?>
        </div>
    <?php endif; ?>

    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Moderatsiyada</div>
                    <div class="stat-value"><?= number_format($stats['pending']) ?></div>
                    <div class="stat-change">katalogda ko'rinmaydi</div>
                </div>
                <div class="stat-icon <?= $stats['pending'] > 0 ? 'warning' : 'success' ?>">⏳</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Sotuvda</div>
                    <div class="stat-value"><?= number_format($stats['approved']) ?></div>
                    <div class="stat-change"><?= number_format($stats['rejected']) ?> ta rad etilgan</div>
                </div>
                <div class="stat-icon success">🧱</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Buyurtmalar</div>
                    <div class="stat-value"><?= number_format($orderStats['total']) ?></div>
                    <div class="stat-change"><?= number_format($orderStats['pending']) ?> ta javob kutmoqda</div>
                </div>
                <div class="stat-icon primary">📦</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Yetkazilgan aylanma</div>
                    <div class="stat-value"><?= number_format($orderStats['turnover'], 0, '.', ' ') ?></div>
                    <div class="stat-change">
                        ulush: <?= number_format($orderStats['commission'], 0, '.', ' ') ?> so'm
                    </div>
                </div>
                <div class="stat-icon success">💰</div>
            </div>
        </div>
    </div>

    <div class="card mb-3">
        <div class="card-body">
            <div style="display:flex; gap:10px; flex-wrap:wrap; align-items:center;">
                <a href="?tab=products&status=pending"
                   class="btn <?= $tab === 'products' ? 'btn-primary' : '' ?>">🧱 Tovarlar</a>
                <a href="?tab=orders"
                   class="btn <?= $tab === 'orders' ? 'btn-primary' : '' ?>">📦 Buyurtmalar</a>

                <form method="GET" action="" style="display:flex; gap:10px; margin-left:auto;">
                    <input type="hidden" name="tab" value="<?= htmlspecialchars($tab) ?>">
                    <select name="status">
                        <?php
                        $options = $tab === 'products'
                            ? ['pending' => 'Moderatsiyada', 'approved' => 'Sotuvda',
                               'rejected' => 'Rad etilgan', 'all' => 'Hammasi']
                            : ['' => 'Hammasi', 'pending' => 'Javob kutmoqda',
                               'confirmed' => 'Tasdiqlangan', 'delivered' => 'Yetkazilgan',
                               'cancelled' => 'Bekor qilingan', 'rejected' => 'Rad etilgan'];
                        foreach ($options as $value => $label): ?>
                            <option value="<?= $value ?>" <?= $statusFilter === (string)$value ? 'selected' : '' ?>>
                                <?= $label ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                    <button type="submit" class="btn btn-primary">Filtrlash</button>
                </form>
            </div>
        </div>
    </div>

    <?php if ($tab === 'products'): ?>
    <div class="card">
        <div class="card-header">
            <h3 class="card-title">Tovarlar</h3>
            <span class="badge badge-info"><?= count($products) ?> ta</span>
        </div>
        <div class="card-body" style="overflow-x:auto;">
            <?php if (empty($products)): ?>
                <p style="padding:24px; text-align:center; color:#6b7280;">Tovar yo'q</p>
            <?php else: ?>
            <table>
                <thead>
                    <tr>
                        <th>#</th>
                        <th>Sotuvchi</th>
                        <th>Tovar</th>
                        <th>Narx</th>
                        <th>Ombor</th>
                        <th>Status</th>
                        <th>Amal</th>
                    </tr>
                </thead>
                <tbody>
                <?php foreach ($products as $p): ?>
                    <tr>
                        <td><strong>#<?= (int)$p['id'] ?></strong></td>
                        <td>
                            <?= htmlspecialchars($p['owner_name']) ?><br>
                            <small class="text-muted"><?= htmlspecialchars($p['owner_phone']) ?></small>
                        </td>
                        <td style="max-width:300px;">
                            <strong><?= htmlspecialchars($p['title']) ?></strong><br>
                            <span class="badge badge-secondary">
                                <?= htmlspecialchars(materialTypeName($p['material_type'])) ?>
                            </span>
                            <?php if ($p['photo_count'] > 0): ?>
                                <span class="badge badge-info">📷 <?= (int)$p['photo_count'] ?></span>
                            <?php endif; ?>
                            <?php if (!empty($p['description'])): ?>
                                <br><small class="text-muted">
                                    <?= htmlspecialchars(mb_substr($p['description'], 0, 90)) ?>
                                </small>
                            <?php endif; ?>
                            <?php if (!empty($p['address'])): ?>
                                <br><small class="text-muted">📍 <?= htmlspecialchars($p['address']) ?></small>
                            <?php endif; ?>
                        </td>
                        <td style="white-space:nowrap;">
                            <strong><?= number_format($p['price_per_unit'], 0, '.', ' ') ?></strong> so'm<br>
                            <small class="text-muted">
                                / <?= htmlspecialchars(materialUnitName($p['unit'])) ?>
                                · <?= rtrim(rtrim(number_format($p['unit_weight_kg'], 2, '.', ' '), '0'), '.') ?> kg
                            </small>
                            <?php if ($p['delivery_price_per_km'] !== null): ?>
                                <br><small class="text-muted">
                                    yetkazish: <?= number_format($p['delivery_price_per_km'], 0, '.', ' ') ?>/km
                                </small>
                            <?php endif; ?>
                        </td>
                        <td style="white-space:nowrap;">
                            <?php if ($p['available_quantity'] === null): ?>
                                <small class="text-muted">cheklanmagan</small>
                            <?php else: ?>
                                <?= number_format($p['available_quantity'], 0, '.', ' ') ?>
                                <small class="text-muted"><?= htmlspecialchars(materialUnitName($p['unit'])) ?></small>
                            <?php endif; ?>
                            <br><small class="text-muted">
                                eng kam: <?= number_format($p['min_quantity'], 0, '.', ' ') ?>
                            </small>
                            <?php if ($p['order_count'] > 0): ?>
                                <br><small class="text-muted">📦 <?= (int)$p['order_count'] ?> buyurtma</small>
                            <?php endif; ?>
                        </td>
                        <td>
                            <?php
                            [$badge, $label] = [
                                'pending'  => ['warning', 'Moderatsiyada'],
                                'approved' => ['success', 'Sotuvda'],
                                'rejected' => ['danger', 'Rad etilgan'],
                            ][$p['status']] ?? ['secondary', $p['status']];
                            ?>
                            <span class="badge badge-<?= $badge ?>"><?= $label ?></span>
                            <?php if (!empty($p['moderation_comment'])): ?>
                                <br><small class="text-muted">
                                    <?= htmlspecialchars($p['moderation_comment']) ?>
                                </small>
                            <?php endif; ?>
                        </td>
                        <td>
                            <form method="POST" action=""
                                  style="display:flex; gap:6px; flex-wrap:wrap; align-items:center;">
                                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                <input type="hidden" name="product_id" value="<?= (int)$p['id'] ?>">
                                <input type="text" name="moderation_comment" placeholder="Sabab"
                                       style="width:110px; padding:4px 8px; font-size:13px;">
                                <?php if ($p['status'] !== 'approved'): ?>
                                    <button type="submit" name="action" value="approve"
                                            class="btn btn-primary" style="padding:4px 10px; font-size:13px;">
                                        Tasdiqlash
                                    </button>
                                <?php endif; ?>
                                <?php if ($p['status'] !== 'rejected'): ?>
                                    <button type="submit" name="action" value="reject"
                                            class="btn" style="padding:4px 10px; font-size:13px;"
                                            onclick="return confirm('Tovar rad etilsinmi? U katalogdan yo\'qoladi.')">
                                        Rad etish
                                    </button>
                                <?php endif; ?>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
            <?php endif; ?>
        </div>
    </div>

    <?php else: ?>
    <div class="card">
        <div class="card-header">
            <h3 class="card-title">Buyurtmalar</h3>
            <span class="badge badge-info"><?= count($orders) ?> ta</span>
        </div>
        <div class="card-body" style="overflow-x:auto;">
            <div class="alert alert-info" style="margin-bottom:16px;">
                Bu ro'yxat faqat KO'RSATADI. Buyurtmani tasdiqlash, yetkazilgan
                deb belgilash va bekor qilish — ilovadagi xaridor va sotuvchining
                ishi, chunki pul harakati backend'da yuritiladi.
            </div>
            <?php if (empty($orders)): ?>
                <p style="padding:24px; text-align:center; color:#6b7280;">Buyurtma yo'q</p>
            <?php else: ?>
            <table>
                <thead>
                    <tr>
                        <th>#</th>
                        <th>Tovar</th>
                        <th>Xaridor</th>
                        <th>Sotuvchi</th>
                        <th>Miqdor va mashina</th>
                        <th>Summa</th>
                        <th>Status</th>
                        <th>Sana</th>
                    </tr>
                </thead>
                <tbody>
                <?php foreach ($orders as $o): ?>
                    <tr>
                        <td><strong>#<?= (int)$o['id'] ?></strong></td>
                        <td style="max-width:220px;">
                            <?= htmlspecialchars($o['product_title']) ?><br>
                            <span class="badge badge-secondary">
                                <?= htmlspecialchars(materialTypeName($o['material_type'])) ?>
                            </span>
                        </td>
                        <td>
                            <?= htmlspecialchars($o['buyer_name']) ?><br>
                            <small class="text-muted"><?= htmlspecialchars($o['buyer_phone']) ?></small>
                        </td>
                        <td>
                            <?= htmlspecialchars($o['seller_name']) ?><br>
                            <small class="text-muted"><?= htmlspecialchars($o['seller_phone']) ?></small>
                        </td>
                        <td style="white-space:nowrap;">
                            <?= number_format($o['quantity'], 0, '.', ' ') ?>
                            <?= htmlspecialchars(materialUnitName($o['unit'])) ?><br>
                            <small class="text-muted">
                                <?= number_format($o['weight_kg'], 0, '.', ' ') ?> kg ·
                                <?= htmlspecialchars(deliveryVehicleName($o['vehicle_code'])) ?>
                                × <?= (int)$o['trips'] ?>
                            </small>
                        </td>
                        <td style="white-space:nowrap;">
                            <strong><?= number_format($o['total_amount'], 0, '.', ' ') ?></strong> so'm<br>
                            <small class="text-muted">
                                tovar <?= number_format($o['goods_amount'], 0, '.', ' ') ?>
                                + yetkazish <?= number_format($o['delivery_fee'], 0, '.', ' ') ?>
                            </small><br>
                            <small class="text-muted">
                                ulush (sotuvchidan): <?= number_format($o['commission'], 0, '.', ' ') ?>
                            </small>
                        </td>
                        <td>
                            <?php
                            [$badge, $label] = [
                                'pending'   => ['warning', 'Javob kutmoqda'],
                                'confirmed' => ['info', 'Tasdiqlangan'],
                                'delivered' => ['success', 'Yetkazilgan'],
                                'cancelled' => ['secondary', 'Bekor qilingan'],
                                'rejected'  => ['danger', 'Rad etilgan'],
                            ][$o['status']] ?? ['secondary', $o['status']];
                            ?>
                            <span class="badge badge-<?= $badge ?>"><?= $label ?></span>
                            <?php if ((float)$o['frozen_amount'] > 0): ?>
                                <br><small class="text-muted">
                                    muzlatilgan: <?= number_format($o['frozen_amount'], 0, '.', ' ') ?>
                                </small>
                            <?php endif; ?>
                        </td>
                        <td style="white-space:nowrap;">
                            <?= date('d.m.Y H:i', strtotime($o['created_at'])) ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
            <?php endif; ?>
        </div>
    </div>
    <?php endif; ?>
</div>

<?php include 'includes/footer.php'; ?>
