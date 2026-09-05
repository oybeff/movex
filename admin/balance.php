<?php
require_once 'config.php';
requireAdmin();

$pageTitle = 'Balans va Tranzaksiyalar';
$currentPage = 'balance';

// Pagination
$page = isset($_GET['page']) ? max(1, intval($_GET['page'])) : 1;
$perPage = ITEMS_PER_PAGE;
$offset = ($page - 1) * $perPage;

// Filters
$statusFilter = $_GET['status'] ?? '';
$typeFilter = $_GET['type'] ?? '';
$searchQuery = $_GET['search'] ?? '';

// Build query
$db = getDbConnection();
$whereConditions = [];
$params = [];

if (!empty($statusFilter)) {
    $whereConditions[] = "bt.status = ?";
    $params[] = $statusFilter;
}

if (!empty($typeFilter)) {
    if ($typeFilter === 'deposit') {
        $whereConditions[] = "bt.type IN ('topup', 'income', 'refund', 'bonus')";
    } elseif ($typeFilter === 'withdrawal') {
        $whereConditions[] = "bt.type = 'payment'";
    }
}

if (!empty($searchQuery)) {
    $whereConditions[] = "u.full_name ILIKE ?";
    $params[] = "%$searchQuery%";
}

$whereClause = !empty($whereConditions) ? 'WHERE ' . implode(' AND ', $whereConditions) : '';

// Get total count
$countQuery = "
    SELECT COUNT(*) as total 
    FROM balance_transactions bt
    JOIN users u ON bt.user_id = u.id
    $whereClause
";
$countStmt = $db->prepare($countQuery);
$countStmt->execute($params);
$totalTransactions = $countStmt->fetch()['total'];
$totalPages = ceil($totalTransactions / $perPage);

// Get transactions
$query = "
    SELECT
        bt.id,
        bt.amount,
        bt.type,
        bt.status,
        bt.payment_method,
        bt.description,
        bt.created_at,
        u.full_name as user_name,
        u.phone as user_phone
    FROM balance_transactions bt
    JOIN users u ON bt.user_id = u.id
    $whereClause
    ORDER BY bt.created_at DESC
    LIMIT ? OFFSET ?
";

$params[] = $perPage;
$params[] = $offset;

$stmt = $db->prepare($query);
$stmt->execute($params);
$transactions = $stmt->fetchAll();

// Get statistics
$stats = $db->query("
    SELECT
        COUNT(*) as total_transactions,
        COALESCE(SUM(CASE WHEN type IN ('topup', 'income', 'refund', 'bonus') THEN amount ELSE 0 END), 0) as total_deposits,
        COALESCE(SUM(CASE WHEN type = 'payment' THEN amount ELSE 0 END), 0) as total_withdrawals,
        COALESCE(SUM(CASE WHEN status = 'pending' THEN amount ELSE 0 END), 0) as pending_amount,
        COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending_count
    FROM balance_transactions
")->fetch();

// Get total balance
$totalBalance = $db->query("SELECT COALESCE(SUM(balance), 0) as total FROM balances")->fetch()['total'];

include 'includes/header.php';
?>

<div class="content">
    <!-- Statistics -->
    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Umumiy Balans</div>
                    <div class="stat-value"><?= number_format($totalBalance, 0) ?></div>
                    <div class="stat-change">so'm</div>
                </div>
                <div class="stat-icon success">💰</div>
            </div>
        </div>
        
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Jami To'lovlar</div>
                    <div class="stat-value"><?= number_format($stats['total_deposits'], 0) ?></div>
                    <div class="stat-change">so'm</div>
                </div>
                <div class="stat-icon primary">📥</div>
            </div>
        </div>
        
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Jami Yechimlar</div>
                    <div class="stat-value"><?= number_format($stats['total_withdrawals'], 0) ?></div>
                    <div class="stat-change">so'm</div>
                </div>
                <div class="stat-icon warning">📤</div>
            </div>
        </div>
        
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Kutilmoqda</div>
                    <div class="stat-value"><?= number_format($stats['pending_count']) ?></div>
                    <div class="stat-change"><?= number_format($stats['pending_amount'], 0) ?> so'm</div>
                </div>
                <div class="stat-icon info">⏳</div>
            </div>
        </div>
    </div>
    
    <!-- Filters -->
    <div class="card mb-3">
        <div class="card-body">
            <form method="GET" action="" class="d-flex gap-2" style="align-items: flex-end; flex-wrap: wrap;">
                <div class="form-group" style="margin-bottom: 0;">
                    <label for="search">Foydalanuvchi</label>
                    <input 
                        type="text" 
                        id="search" 
                        name="search" 
                        placeholder="Ism bo'yicha qidirish..."
                        value="<?= htmlspecialchars($searchQuery) ?>"
                    >
                </div>

                <div class="form-group" style="margin-bottom: 0;">
                    <label for="type">Turi</label>
                    <select name="type" id="type">
                        <option value="">Barchasi</option>
                        <option value="deposit" <?= $typeFilter === 'deposit' ? 'selected' : '' ?>>To'lov</option>
                        <option value="withdrawal" <?= $typeFilter === 'withdrawal' ? 'selected' : '' ?>>Yechim</option>
                    </select>
                </div>

                <div class="form-group" style="margin-bottom: 0;">
                    <label for="status">Status</label>
                    <select name="status" id="status">
                        <option value="">Barchasi</option>
                        <option value="pending" <?= $statusFilter === 'pending' ? 'selected' : '' ?>>Kutilmoqda</option>
                        <option value="completed" <?= $statusFilter === 'completed' ? 'selected' : '' ?>>Yakunlangan</option>
                        <option value="failed" <?= $statusFilter === 'failed' ? 'selected' : '' ?>>Muvaffaqiyatsiz</option>
                    </select>
                </div>

                <button type="submit" class="btn btn-primary">
                    🔍 Filtrlash
                </button>

                <?php if (!empty($searchQuery) || !empty($statusFilter) || !empty($typeFilter)): ?>
                    <a href="balance.php" class="btn btn-secondary">
                        ✖️ Tozalash
                    </a>
                <?php endif; ?>
            </form>
        </div>
    </div>

    <!-- Transactions Table -->
    <div class="card">
        <div class="card-header">
            <h3 class="card-title">Tranzaksiyalar Ro'yxati</h3>
            <span class="badge badge-info"><?= number_format($totalTransactions) ?> ta tranzaksiya</span>
        </div>
        <div class="card-body">
            <div class="table-responsive">
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Foydalanuvchi</th>
                            <th>Turi</th>
                            <th>Summa</th>
                            <th>To'lov Usuli</th>
                            <th>Status</th>
                            <th>Izoh</th>
                            <th>Sana</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($transactions as $transaction): ?>
                        <tr>
                            <td><strong>#<?= $transaction['id'] ?></strong></td>
                            <td>
                                <?= htmlspecialchars($transaction['user_name']) ?><br>
                                <small class="text-muted"><?= htmlspecialchars($transaction['user_phone']) ?></small>
                            </td>
                            <td>
                                <?php
                                $isDeposit = in_array($transaction['type'], ['topup', 'income', 'refund', 'bonus']);
                                // Ro'yxat TO'LIQ bo'lishi shart: yetishmagan turda pastdagi
                                // `?? $transaction['type']` xom kodni chiqaradi. Aynan shunday
                                // "withdrawal" jadvalda inglizcha bo'lib turardi — qolganlari
                                // o'zbekcha bo'lgani holda. Bazada 5 tur bor: topup, refund,
                                // income, payment, withdrawal.
                                $typeLabel = [
                                    'topup' => '📥 To\'ldirish',
                                    'income' => '💰 Daromad',
                                    'payment' => '📤 To\'lov',
                                    'refund' => '↩️ Qaytarish',
                                    'withdrawal' => '🏧 Pul yechish'
                                ];
                                ?>
                                <?php if ($isDeposit): ?>
                                    <span class="badge badge-success"><?= $typeLabel[$transaction['type']] ?? $transaction['type'] ?></span>
                                <?php else: ?>
                                    <span class="badge badge-warning"><?= $typeLabel[$transaction['type']] ?? $transaction['type'] ?></span>
                                <?php endif; ?>
                            </td>
                            <td>
                                <strong style="color: <?= $isDeposit ? 'var(--success-color)' : 'var(--warning-color)' ?>">
                                    <?= $isDeposit ? '+' : '-' ?>
                                    <?= number_format($transaction['amount'], 0) ?>
                                </strong> so'm
                            </td>
                            <td>
                                <?php
                                $methodLabels = [
                                    'payme' => 'Payme',
                                    'click' => 'Click',
                                    'uzum' => 'Uzum',
                                    'cash' => 'Naqd',
                                    'card' => 'Karta'
                                ];
                                $paymentMethod = $transaction['payment_method'];
                                if ($paymentMethod) {
                                    echo $methodLabels[$paymentMethod] ?? ucfirst($paymentMethod);
                                } else {
                                    echo '<span class="text-muted">—</span>';
                                }
                                ?>
                            </td>
                            <td>
                                <?php
                                $statusClass = [
                                    'pending' => 'warning',
                                    'completed' => 'success',
                                    'failed' => 'danger',
                                    'canceled' => 'secondary'
                                ][$transaction['status']] ?? 'secondary';

                                $statusText = [
                                    'pending' => 'Kutilmoqda',
                                    'completed' => 'Yakunlangan',
                                    'failed' => 'Muvaffaqiyatsiz',
                                    'canceled' => 'Bekor qilingan'
                                ][$transaction['status']] ?? ($transaction['status'] ?? '');
                                ?>
                                <span class="badge badge-<?= $statusClass ?>">
                                    <?= $statusText ?>
                                </span>
                            </td>
                            <td>
                                <small><?= htmlspecialchars($transaction['description'] ?? '-') ?></small>
                            </td>
                            <td><?= formatDate($transaction['created_at'], 'd.m.Y H:i') ?></td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>

            <!-- Pagination -->
            <?php if ($totalPages > 1): ?>
                <div class="pagination">
                    <?php
                    $queryParams = [];
                    if ($statusFilter) $queryParams[] = 'status=' . $statusFilter;
                    if ($typeFilter) $queryParams[] = 'type=' . $typeFilter;
                    if ($searchQuery) $queryParams[] = 'search=' . urlencode($searchQuery);
                    $queryString = !empty($queryParams) ? '&' . implode('&', $queryParams) : '';
                    ?>

                    <?php if ($page > 1): ?>
                        <a href="?page=<?= $page - 1 ?><?= $queryString ?>">← Oldingi</a>
                    <?php endif; ?>

                    <?php for ($i = max(1, $page - 2); $i <= min($totalPages, $page + 2); $i++): ?>
                        <?php if ($i === $page): ?>
                            <span class="active"><?= $i ?></span>
                        <?php else: ?>
                            <a href="?page=<?= $i ?><?= $queryString ?>"><?= $i ?></a>
                        <?php endif; ?>
                    <?php endfor; ?>

                    <?php if ($page < $totalPages): ?>
                        <a href="?page=<?= $page + 1 ?><?= $queryString ?>">Keyingi →</a>
                    <?php endif; ?>
                </div>
            <?php endif; ?>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>

