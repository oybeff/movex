<?php
/**
 * Zayavkalar va ularga kelgan takliflar.
 *
 * Katalogdan boshqa buyurtma yo'li: mijoz turni so'raydi, egalar narx
 * taklif qiladi, mijoz bittasini tanlaydi. Adminka bu oqimni umuman
 * ko'rmasdi — buyurtmalar sahifasida faqat tayyor buyurtma ko'rinardi,
 * ya'ni "javob kelmayapti" degan shikoyatni tekshirib bo'lmasdi.
 *
 * Sahifa faqat KO'RSATADI. Zayavkani bekor qilish yoki taklifni tanlash —
 * mijozning ishi, admin uning o'rniga qaror qabul qilmaydi.
 */
require_once 'config.php';
requireAdmin();

$pageTitle = 'Zayavkalar';
$currentPage = 'requests';

$page = isset($_GET['page']) ? max(1, intval($_GET['page'])) : 1;
$perPage = ITEMS_PER_PAGE;
$offset = ($page - 1) * $perPage;

$statusFilter = $_GET['status'] ?? '';

$db = getDbConnection();

$whereClause = '';
$params = [];
if (!empty($statusFilter)) {
    $whereClause = "WHERE r.status = ?";
    $params[] = $statusFilter;
}

$countStmt = $db->prepare("SELECT COUNT(*) as total FROM equipment_requests r $whereClause");
$countStmt->execute($params);
$totalRequests = $countStmt->fetch()['total'];
$totalPages = ceil($totalRequests / $perPage);

// Takliflar sonini alohida so'rov bilan emas, LEFT JOIN bilan olamiz:
// har bir qator uchun alohida so'rov ketsa, 50 ta zayavka = 51 ta so'rov.
$query = "
    SELECT
        r.id,
        r.equipment_type,
        r.start_date,
        r.end_date,
        r.delivery_address,
        r.budget,
        r.status,
        r.order_id,
        r.created_at,
        r.expires_at,
        u.full_name AS client_name,
        u.phone AS client_phone,
        COUNT(o.id) FILTER (WHERE o.status = 'pending') AS pending_offers,
        COUNT(o.id) AS total_offers,
        MIN(o.price_per_day) AS min_price,
        MAX(o.price_per_day) AS max_price
    FROM equipment_requests r
    JOIN users u ON r.client_id = u.id
    LEFT JOIN request_offers o ON o.request_id = r.id
    $whereClause
    GROUP BY r.id, u.full_name, u.phone
    ORDER BY r.created_at DESC
    LIMIT ? OFFSET ?
";

$params[] = $perPage;
$params[] = $offset;
$stmt = $db->prepare($query);
$stmt->execute($params);
$requests = $stmt->fetchAll();

$stats = $db->query("
    SELECT
        COUNT(*) AS total,
        COUNT(*) FILTER (WHERE status = 'open') AS open,
        COUNT(*) FILTER (WHERE status = 'assigned') AS assigned,
        COUNT(*) FILTER (WHERE status = 'cancelled') AS cancelled,
        COUNT(*) FILTER (WHERE status = 'expired') AS expired
    FROM equipment_requests
")->fetch();

// Javobsiz qolgan ochiq zayavkalar — bu sahifadagi eng muhim raqam.
// Ko'p bo'lsa, demak yo egalar yetishmaydi, yo radius juda tor.
$unanswered = $db->query("
    SELECT COUNT(*) AS n
    FROM equipment_requests r
    WHERE r.status = 'open'
      AND NOT EXISTS (
          SELECT 1 FROM request_offers o
          WHERE o.request_id = r.id AND o.status = 'pending'
      )
")->fetch()['n'];


include 'includes/header.php';
?>

<div class="content">
    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Jami Zayavkalar</div>
                    <div class="stat-value"><?= number_format($stats['total']) ?></div>
                </div>
                <div class="stat-icon primary">📣</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Ochiq</div>
                    <div class="stat-value"><?= number_format($stats['open']) ?></div>
                </div>
                <div class="stat-icon warning">⏳</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Buyurtmaga aylangan</div>
                    <div class="stat-value"><?= number_format($stats['assigned']) ?></div>
                </div>
                <div class="stat-icon success">✅</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Javobsiz ochiq</div>
                    <div class="stat-value"><?= number_format($unanswered) ?></div>
                    <div class="stat-change">taklif kelmagan</div>
                </div>
                <div class="stat-icon <?= $unanswered > 0 ? 'danger' : 'info' ?>">🔇</div>
            </div>
        </div>
    </div>

    <div class="card mb-3">
        <div class="card-body">
            <form method="GET" action="" class="d-flex gap-2" style="align-items: flex-end;">
                <div class="form-group" style="margin-bottom: 0;">
                    <label for="status">Status</label>
                    <select name="status" id="status">
                        <option value="">Barchasi</option>
                        <option value="open" <?= $statusFilter === 'open' ? 'selected' : '' ?>>Ochiq</option>
                        <option value="assigned" <?= $statusFilter === 'assigned' ? 'selected' : '' ?>>Buyurtmaga aylangan</option>
                        <option value="cancelled" <?= $statusFilter === 'cancelled' ? 'selected' : '' ?>>Bekor qilingan</option>
                        <option value="expired" <?= $statusFilter === 'expired' ? 'selected' : '' ?>>Muddati o'tgan</option>
                    </select>
                </div>

                <button type="submit" class="btn btn-primary">🔍 Filtrlash</button>

                <?php if (!empty($statusFilter)): ?>
                    <a href="requests.php" class="btn btn-secondary">✖️ Tozalash</a>
                <?php endif; ?>
            </form>
        </div>
    </div>

    <div class="card">
        <div class="card-header">
            <h3 class="card-title">Zayavkalar Ro'yxati</h3>
            <span class="badge badge-info"><?= number_format($totalRequests) ?> ta zayavka</span>
        </div>
        <div class="card-body">
            <div class="table-responsive">
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Mijoz</th>
                            <th>Texnika turi</th>
                            <th>Muddat</th>
                            <th>Manzil</th>
                            <th>Byudjet</th>
                            <th>Takliflar</th>
                            <th>Status</th>
                            <th>Yaratilgan</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php if (empty($requests)): ?>
                        <tr>
                            <td colspan="9" class="text-muted" style="text-align: center; padding: 24px;">
                                Zayavkalar yo'q
                            </td>
                        </tr>
                        <?php endif; ?>
                        <?php foreach ($requests as $r): ?>
                        <tr>
                            <td><strong>#<?= $r['id'] ?></strong></td>
                            <td>
                                <?= htmlspecialchars($r['client_name']) ?><br>
                                <small class="text-muted"><?= htmlspecialchars($r['client_phone']) ?></small>
                            </td>
                            <td>
                                <strong><?= htmlspecialchars(equipmentTypeName($r['equipment_type'])) ?></strong>
                            </td>
                            <td>
                                <?= formatDate($r['start_date'], 'd.m.Y') ?><br>
                                <small class="text-muted">→ <?= formatDate($r['end_date'], 'd.m.Y') ?></small>
                            </td>
                            <td>
                                <?php if (!empty($r['delivery_address'])): ?>
                                    <small><?= htmlspecialchars($r['delivery_address']) ?></small>
                                <?php else: ?>
                                    <small class="text-muted">—</small>
                                <?php endif; ?>
                            </td>
                            <td>
                                <?php if ($r['budget'] !== null): ?>
                                    <?= number_format($r['budget'], 0) ?> so'm
                                <?php else: ?>
                                    <small class="text-muted">ko'rsatilmagan</small>
                                <?php endif; ?>
                            </td>
                            <td>
                                <?php if ($r['total_offers'] > 0): ?>
                                    <span class="badge badge-<?= $r['pending_offers'] > 0 ? 'success' : 'secondary' ?>">
                                        <?= $r['total_offers'] ?>
                                    </span>
                                    <?php if ($r['min_price'] !== null): ?>
                                        <br><small class="text-muted">
                                            <?= number_format($r['min_price'], 0) ?><?php
                                            if ($r['max_price'] != $r['min_price']) {
                                                echo ' – ' . number_format($r['max_price'], 0);
                                            }
                                            ?> so'm/kun
                                        </small>
                                    <?php endif; ?>
                                <?php else: ?>
                                    <span class="badge badge-warning">0</span>
                                <?php endif; ?>
                            </td>
                            <td>
                                <?php
                                $statusClass = [
                                    'open' => 'warning',
                                    'assigned' => 'success',
                                    'cancelled' => 'danger',
                                    'expired' => 'secondary',
                                ][$r['status']] ?? 'secondary';

                                $statusText = [
                                    'open' => 'Ochiq',
                                    'assigned' => 'Buyurtmaga aylangan',
                                    'cancelled' => 'Bekor qilingan',
                                    'expired' => "Muddati o'tgan",
                                ][$r['status']] ?? ($r['status'] ?? '');
                                ?>
                                <span class="badge badge-<?= $statusClass ?>"><?= $statusText ?></span>
                                <?php if (!empty($r['order_id'])): ?>
                                    <br><small class="text-muted">buyurtma #<?= $r['order_id'] ?></small>
                                <?php endif; ?>
                            </td>
                            <td><?= formatDate($r['created_at'], 'd.m.Y H:i') ?></td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>

            <?php if ($totalPages > 1): ?>
                <div class="pagination">
                    <?php if ($page > 1): ?>
                        <a href="?page=<?= $page - 1 ?><?= $statusFilter ? '&status=' . urlencode($statusFilter) : '' ?>">← Oldingi</a>
                    <?php endif; ?>

                    <?php for ($i = max(1, $page - 2); $i <= min($totalPages, $page + 2); $i++): ?>
                        <?php if ($i === $page): ?>
                            <span class="active"><?= $i ?></span>
                        <?php else: ?>
                            <a href="?page=<?= $i ?><?= $statusFilter ? '&status=' . urlencode($statusFilter) : '' ?>"><?= $i ?></a>
                        <?php endif; ?>
                    <?php endfor; ?>

                    <?php if ($page < $totalPages): ?>
                        <a href="?page=<?= $page + 1 ?><?= $statusFilter ? '&status=' . urlencode($statusFilter) : '' ?>">Keyingi →</a>
                    <?php endif; ?>
                </div>
            <?php endif; ?>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>
