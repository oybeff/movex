<?php
require_once 'config.php';
requireAdmin();

$pageTitle = 'Dashboard';
$currentPage = 'dashboard';

// Get statistics
$db = getDbConnection();

// Users stats
$usersStats = $db->query("
    SELECT 
        COUNT(*) as total,
        COUNT(CASE WHEN role = 'client' THEN 1 END) as clients,
        COUNT(CASE WHEN role = 'owner' THEN 1 END) as owners,
        COUNT(CASE WHEN created_at >= NOW() - INTERVAL '7 days' THEN 1 END) as new_week
    FROM users
")->fetch();

// Equipment stats
$equipmentStats = $db->query("
    SELECT 
        COUNT(*) as total,
        COUNT(CASE WHEN available = true THEN 1 END) as available,
        COUNT(CASE WHEN available = false THEN 1 END) as busy
    FROM equipment
")->fetch();

// Orders stats
$ordersStats = $db->query("
    SELECT 
        COUNT(*) as total,
        COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending,
        COUNT(CASE WHEN status = 'confirmed' THEN 1 END) as confirmed,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed,
        COUNT(CASE WHEN created_at >= NOW() - INTERVAL '7 days' THEN 1 END) as new_week
    FROM orders
")->fetch();

// Balance stats
$balanceStats = $db->query("
    SELECT 
        COALESCE(SUM(balance), 0) as total_balance,
        COUNT(*) as total_accounts
    FROM balances
")->fetch();

$transactionsCount = $db->query("SELECT COUNT(*) as count FROM balance_transactions")->fetch()['count'];

// Budget stats
$budgetStats = $db->query("
    SELECT
        COALESCE(SUM(amount), 0) as total_budget,
        COUNT(*) as total_records,
        COALESCE(SUM(CASE WHEN created_at >= NOW() - INTERVAL '7 days' THEN amount ELSE 0 END), 0) as week_budget
    FROM budget_reserves
")->fetch();

// Recent orders
$recentOrders = $db->query("
    SELECT 
        o.id,
        o.status,
        o.total_amount,
        o.created_at,
        u.full_name as client_name,
        e.type as equipment_type,
        e.model as equipment_model
    FROM orders o
    JOIN users u ON o.user_id = u.id
    JOIN equipment e ON o.equipment_id = e.id
    ORDER BY o.created_at DESC
    LIMIT 10
")->fetchAll();

include 'includes/header.php';
?>

<div class="content">
    <!-- Stats Grid -->
    <div class="stats-grid">
        <!-- Users Card -->
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Foydalanuvchilar</div>
                    <div class="stat-value"><?= number_format($usersStats['total']) ?></div>
                    <div class="stat-change positive">
                        +<?= $usersStats['new_week'] ?> bu hafta
                    </div>
                </div>
                <div class="stat-icon primary">
                    👥
                </div>
            </div>
        </div>
        
        <!-- Equipment Card -->
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Texnikalar</div>
                    <div class="stat-value"><?= number_format($equipmentStats['total']) ?></div>
                    <div class="stat-change">
                        <?= $equipmentStats['available'] ?> mavjud
                    </div>
                </div>
                <div class="stat-icon secondary">
                    🚜
                </div>
            </div>
        </div>
        
        <!-- Orders Card -->
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Buyurtmalar</div>
                    <div class="stat-value"><?= number_format($ordersStats['total']) ?></div>
                    <div class="stat-change positive">
                        +<?= $ordersStats['new_week'] ?> bu hafta
                    </div>
                </div>
                <div class="stat-icon warning">
                    📦
                </div>
            </div>
        </div>
        
        <!-- Balance Card -->
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Umumiy Balans</div>
                    <div class="stat-value"><?= number_format($balanceStats['total_balance'], 0) ?></div>
                    <div class="stat-change">
                        <?= number_format($transactionsCount) ?> tranzaksiya
                    </div>
                </div>
                <div class="stat-icon success">
                    💰
                </div>
            </div>
        </div>

        <!-- Budget Card -->
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Budjet Jamg'armasi</div>
                    <div class="stat-value"><?= number_format($budgetStats['total_budget'], 0) ?></div>
                    <div class="stat-change positive">
                        +<?= number_format($budgetStats['week_budget'], 0) ?> bu hafta
                    </div>
                </div>
                <div class="stat-icon info">
                    🏦
                </div>
            </div>
        </div>
    </div>
    
    <!-- Recent Orders -->
    <div class="card">
        <div class="card-header">
            <h3 class="card-title">So'nggi Buyurtmalar</h3>
            <a href="orders.php" class="btn btn-sm btn-primary">Barchasini ko'rish</a>
        </div>
        <div class="card-body">
            <div class="table-responsive">
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Mijoz</th>
                            <th>Texnika</th>
                            <th>Summa</th>
                            <th>Status</th>
                            <th>Sana</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($recentOrders as $order): ?>
                        <tr>
                            <td>#<?= $order['id'] ?></td>
                            <td><?= htmlspecialchars($order['client_name']) ?></td>
                            <td><?= htmlspecialchars(equipmentTypeName($order['equipment_type']) . ' — ' . $order['equipment_model']) ?></td>
                            <td><?= number_format($order['total_amount'], 0) ?> so'm</td>
                            <td>
                                <?php
                                $statusClass = [
                                    'pending' => 'warning',
                                    'confirmed' => 'info',
                                    'completed' => 'success',
                                    'cancelled' => 'danger',
                                    'rejected' => 'danger'
                                ][$order['status']] ?? 'secondary';

                                $statusLabel = [
                                    'pending' => 'Kutilmoqda',
                                    'confirmed' => 'Tasdiqlangan',
                                    'completed' => 'Bajarilgan',
                                    'cancelled' => 'Bekor qilingan',
                                    'rejected' => 'Rad etilgan'
                                ][$order['status']] ?? ucfirst($order['status'] ?? '');
                                ?>
                                <span class="badge badge-<?= $statusClass ?>">
                                    <?= $statusLabel ?>
                                </span>
                            </td>
                            <td><?= formatDate($order['created_at'], 'd.m.Y H:i') ?></td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>

