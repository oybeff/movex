<?php
require_once 'config.php';
requireAdmin();

$pageTitle = 'Buyurtmalar';
$currentPage = 'orders';

// Pagination
$page = isset($_GET['page']) ? max(1, intval($_GET['page'])) : 1;
$perPage = ITEMS_PER_PAGE;
$offset = ($page - 1) * $perPage;

// Filters
$statusFilter = $_GET['status'] ?? '';

// Build query
$db = getDbConnection();
$whereClause = '';
$params = [];

if (!empty($statusFilter)) {
    $whereClause = "WHERE o.status = ?";
    $params[] = $statusFilter;
}

// Get total count
$countQuery = "SELECT COUNT(*) as total FROM orders o $whereClause";
$countStmt = $db->prepare($countQuery);
$countStmt->execute($params);
$totalOrders = $countStmt->fetch()['total'];
$totalPages = ceil($totalOrders / $perPage);

// Get orders
$query = "
    SELECT 
        o.id,
        o.status,
        o.start_date,
        o.end_date,
        o.total_amount,
        o.commission,
        o.created_at,
        u.full_name as client_name,
        u.phone as client_phone,
        e.type as equipment_type,
        e.model as equipment_model,
        owner.full_name as owner_name
    FROM orders o
    JOIN users u ON o.user_id = u.id
    JOIN equipment e ON o.equipment_id = e.id
    JOIN users owner ON e.owner_id = owner.id
    $whereClause
    ORDER BY o.created_at DESC
    LIMIT ? OFFSET ?
";

$params[] = $perPage;
$params[] = $offset;

$stmt = $db->prepare($query);
$stmt->execute($params);
$orders = $stmt->fetchAll();

// Get statistics
$stats = $db->query("
    SELECT 
        COUNT(*) as total,
        COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending,
        COUNT(CASE WHEN status = 'confirmed' THEN 1 END) as confirmed,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed,
        COUNT(CASE WHEN status = 'cancelled' THEN 1 END) as cancelled,
        COALESCE(SUM(total_amount), 0) as total_revenue,
        COALESCE(SUM(commission), 0) as total_commission
    FROM orders
")->fetch();

include 'includes/header.php';
?>

<div class="content">
    <!-- Statistics -->
    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Jami Buyurtmalar</div>
                    <div class="stat-value"><?= number_format($stats['total']) ?></div>
                </div>
                <div class="stat-icon primary">📦</div>
            </div>
        </div>
        
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Kutilmoqda</div>
                    <div class="stat-value"><?= number_format($stats['pending']) ?></div>
                </div>
                <div class="stat-icon warning">⏳</div>
            </div>
        </div>
        
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Tasdiqlangan</div>
                    <div class="stat-value"><?= number_format($stats['confirmed']) ?></div>
                </div>
                <div class="stat-icon info">✅</div>
            </div>
        </div>
        
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Yakunlangan</div>
                    <div class="stat-value"><?= number_format($stats['completed']) ?></div>
                </div>
                <div class="stat-icon success">🎉</div>
            </div>
        </div>
    </div>
    
    <!-- Revenue Stats -->
    <div class="stats-grid" style="grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));">
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Umumiy Daromad</div>
                    <div class="stat-value"><?= number_format($stats['total_revenue'], 0) ?></div>
                    <div class="stat-change">so'm</div>
                </div>
                <div class="stat-icon success">💰</div>
            </div>
        </div>
        
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Platforma Komissiyasi</div>
                    <div class="stat-value"><?= number_format($stats['total_commission'], 0) ?></div>
                    <div class="stat-change">so'm</div>
                </div>
                <div class="stat-icon info">💵</div>
            </div>
        </div>
    </div>
    
    <!-- Filters -->
    <div class="card mb-3">
        <div class="card-body">
            <form method="GET" action="" class="d-flex gap-2" style="align-items: flex-end;">
                <div class="form-group" style="margin-bottom: 0;">
                    <label for="status">Status</label>
                    <select name="status" id="status">
                        <option value="">Barchasi</option>
                        <option value="pending" <?= $statusFilter === 'pending' ? 'selected' : '' ?>>Kutilmoqda</option>
                        <option value="confirmed" <?= $statusFilter === 'confirmed' ? 'selected' : '' ?>>Tasdiqlangan</option>
                        <option value="completed" <?= $statusFilter === 'completed' ? 'selected' : '' ?>>Yakunlangan</option>
                        <option value="cancelled" <?= $statusFilter === 'cancelled' ? 'selected' : '' ?>>Bekor qilingan</option>
                    </select>
                </div>

                <button type="submit" class="btn btn-primary">
                    🔍 Filtrlash
                </button>

                <?php if (!empty($statusFilter)): ?>
                    <a href="orders.php" class="btn btn-secondary">
                        ✖️ Tozalash
                    </a>
                <?php endif; ?>
            </form>
        </div>
    </div>

    <!-- Orders Table -->
    <div class="card">
        <div class="card-header">
            <h3 class="card-title">Buyurtmalar Ro'yxati</h3>
            <span class="badge badge-info"><?= number_format($totalOrders) ?> ta buyurtma</span>
        </div>
        <div class="card-body">
            <div class="table-responsive">
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Mijoz</th>
                            <th>Texnika</th>
                            <th>Egasi</th>
                            <th>Muddat</th>
                            <th>Summa</th>
                            <th>Komissiya</th>
                            <th>Status</th>
                            <th>Yaratilgan</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($orders as $order): ?>
                        <tr>
                            <td><strong>#<?= $order['id'] ?></strong></td>
                            <td>
                                <?= htmlspecialchars($order['client_name']) ?><br>
                                <small class="text-muted"><?= htmlspecialchars($order['client_phone']) ?></small>
                            </td>
                            <td>
                                <strong><?= htmlspecialchars($order['equipment_type']) ?></strong><br>
                                <small class="text-muted"><?= htmlspecialchars($order['equipment_model']) ?></small>
                            </td>
                            <td><?= htmlspecialchars($order['owner_name']) ?></td>
                            <td>
                                <?= formatDate($order['start_date'], 'd.m.Y') ?><br>
                                <small class="text-muted">→ <?= formatDate($order['end_date'], 'd.m.Y') ?></small>
                            </td>
                            <td><strong><?= number_format($order['total_amount'], 0) ?></strong> so'm</td>
                            <td><?= number_format($order['commission'], 0) ?> so'm</td>
                            <td>
                                <?php
                                $statusClass = [
                                    'pending' => 'warning',
                                    'confirmed' => 'info',
                                    'completed' => 'success',
                                    'cancelled' => 'danger',
                                    'rejected' => 'danger'
                                ][$order['status']] ?? 'secondary';

                                $statusText = [
                                    'pending' => 'Kutilmoqda',
                                    'confirmed' => 'Tasdiqlangan',
                                    'completed' => 'Yakunlangan',
                                    'cancelled' => 'Bekor qilingan',
                                    'rejected' => 'Rad etilgan'
                                ][$order['status']] ?? ($order['status'] ?? '');
                                ?>
                                <span class="badge badge-<?= $statusClass ?>">
                                    <?= $statusText ?>
                                </span>
                            </td>
                            <td><?= formatDate($order['created_at'], 'd.m.Y H:i') ?></td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>

            <!-- Pagination -->
            <?php if ($totalPages > 1): ?>
                <div class="pagination">
                    <?php if ($page > 1): ?>
                        <a href="?page=<?= $page - 1 ?><?= $statusFilter ? '&status=' . $statusFilter : '' ?>">
                            ← Oldingi
                        </a>
                    <?php endif; ?>

                    <?php for ($i = max(1, $page - 2); $i <= min($totalPages, $page + 2); $i++): ?>
                        <?php if ($i === $page): ?>
                            <span class="active"><?= $i ?></span>
                        <?php else: ?>
                            <a href="?page=<?= $i ?><?= $statusFilter ? '&status=' . $statusFilter : '' ?>">
                                <?= $i ?>
                            </a>
                        <?php endif; ?>
                    <?php endfor; ?>

                    <?php if ($page < $totalPages): ?>
                        <a href="?page=<?= $page + 1 ?><?= $statusFilter ? '&status=' . $statusFilter : '' ?>">
                            Keyingi →
                        </a>
                    <?php endif; ?>
                </div>
            <?php endif; ?>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>

