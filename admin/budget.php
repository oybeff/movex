<?php
require_once 'config.php';
requireAdmin();

$pageTitle = 'Budjet Jamg\'armasi';
$currentPage = 'budget';

// Pagination
$page = isset($_GET['page']) ? max(1, intval($_GET['page'])) : 1;
$perPage = ITEMS_PER_PAGE;
$offset = ($page - 1) * $perPage;

// Filters
$searchQuery = $_GET['search'] ?? '';
$dateFrom = $_GET['date_from'] ?? '';
$dateTo = $_GET['date_to'] ?? '';

// Build query
$db = getDbConnection();

// Ulush qanday hisoblanayotgani — sozlamadan, qotirilgan matndan emas.
//
// Ilgari bu yerda "10% komissiya" deb yozilardi va jadval sarlavhasi ham
// "Komissiya (10%)" edi. Ulush esa allaqachon qat'iy 5 000 so'm: ustunda
// 5 000 turardi, sarlavhada 10% — admin qaysi biriga ishonishni bilmasdi.
$commissionMode = appSettingValue($db, 'commission_mode', 'fixed');
$commissionLabel = $commissionMode === 'percent'
    ? 'ijara summasining ' . appSettingValue($db, 'commission_percent', '10') . '%i'
    : 'har bir buyurtmadan qat\'iy ' . number_format((float)appSettingValue($db, 'commission_fixed', '5000'), 0, '.', ' ') . ' so\'m';
$whereConditions = [];
$params = [];

if (!empty($searchQuery)) {
    $whereConditions[] = "(u.full_name ILIKE ? OR e.type ILIKE ? OR e.model ILIKE ?)";
    $params[] = "%$searchQuery%";
    $params[] = "%$searchQuery%";
    $params[] = "%$searchQuery%";
}

if (!empty($dateFrom)) {
    $whereConditions[] = "br.created_at >= ?";
    $params[] = $dateFrom . ' 00:00:00';
}

if (!empty($dateTo)) {
    $whereConditions[] = "br.created_at <= ?";
    $params[] = $dateTo . ' 23:59:59';
}

$whereClause = !empty($whereConditions) ? 'WHERE ' . implode(' AND ', $whereConditions) : '';

// Get total count
$countQuery = "
    SELECT COUNT(*) as total 
    FROM budget_reserves br
    JOIN orders o ON br.order_id = o.id
    JOIN users u ON o.user_id = u.id
    JOIN equipment e ON o.equipment_id = e.id
    $whereClause
";
$countStmt = $db->prepare($countQuery);
$countStmt->execute($params);
$totalRecords = $countStmt->fetch()['total'];
$totalPages = ceil($totalRecords / $perPage);

// Get budget reserves
$query = "
    SELECT
        br.id,
        br.order_id,
        br.amount,
        br.description,
        br.created_at,
        o.total_amount as order_total,
        o.start_date,
        o.end_date,
        u.full_name as client_name,
        u.phone as client_phone,
        e.type as equipment_type,
        e.model as equipment_model,
        owner.full_name as owner_name
    FROM budget_reserves br
    JOIN orders o ON br.order_id = o.id
    JOIN users u ON o.user_id = u.id
    JOIN equipment e ON o.equipment_id = e.id
    JOIN users owner ON e.owner_id = owner.id
    $whereClause
    ORDER BY br.created_at DESC
    LIMIT ? OFFSET ?
";

$params[] = $perPage;
$params[] = $offset;

$stmt = $db->prepare($query);
$stmt->execute($params);
$reserves = $stmt->fetchAll();

// Get statistics
$stats = $db->query("
    SELECT
        COUNT(*) as total_count,
        COALESCE(SUM(amount), 0) as total_amount,
        COALESCE(SUM(CASE WHEN created_at >= NOW() - INTERVAL '30 days' THEN amount ELSE 0 END), 0) as last_month,
        COALESCE(SUM(CASE WHEN created_at >= NOW() - INTERVAL '7 days' THEN amount ELSE 0 END), 0) as last_week,
        COALESCE(SUM(CASE WHEN DATE(created_at) = CURRENT_DATE THEN amount ELSE 0 END), 0) as today
    FROM budget_reserves
")->fetch();

include 'includes/header.php';
?>

<div class="content">
    <!-- Statistics -->
    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Jami Budjet</div>
                    <div class="stat-value"><?= number_format($stats['total_amount'], 0) ?></div>
                    <div class="stat-change">so'm</div>
                </div>
                <div class="stat-icon success">💰</div>
            </div>
        </div>
        
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Bugun</div>
                    <div class="stat-value"><?= number_format($stats['today'], 0) ?></div>
                    <div class="stat-change">so'm</div>
                </div>
                <div class="stat-icon primary">📅</div>
            </div>
        </div>
        
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Bu Hafta</div>
                    <div class="stat-value"><?= number_format($stats['last_week'], 0) ?></div>
                    <div class="stat-change">so'm</div>
                </div>
                <div class="stat-icon info">📊</div>
            </div>
        </div>
        
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Bu Oy</div>
                    <div class="stat-value"><?= number_format($stats['last_month'], 0) ?></div>
                    <div class="stat-change">so'm</div>
                </div>
                <div class="stat-icon warning">📈</div>
            </div>
        </div>
    </div>

    <!-- Filters -->
    <div class="card mb-3">
        <div class="card-body">
            <form method="GET" action="" class="d-flex gap-2" style="align-items: flex-end; flex-wrap: wrap;">
                <div class="form-group" style="margin-bottom: 0;">
                    <label for="search">Qidirish</label>
                    <input
                        type="text"
                        id="search"
                        name="search"
                        placeholder="Buyurtma, client, texnika..."
                        value="<?= htmlspecialchars($searchQuery) ?>"
                    >
                </div>

                <div class="form-group" style="margin-bottom: 0;">
                    <label for="date_from">Sanadan</label>
                    <input
                        type="date"
                        id="date_from"
                        name="date_from"
                        value="<?= htmlspecialchars($dateFrom) ?>"
                    >
                </div>

                <div class="form-group" style="margin-bottom: 0;">
                    <label for="date_to">Sanagacha</label>
                    <input
                        type="date"
                        id="date_to"
                        name="date_to"
                        value="<?= htmlspecialchars($dateTo) ?>"
                    >
                </div>

                <button type="submit" class="btn btn-primary">
                    🔍 Filtrlash
                </button>

                <?php if (!empty($searchQuery) || !empty($dateFrom) || !empty($dateTo)): ?>
                    <a href="budget.php" class="btn btn-secondary">
                        ✖️ Tozalash
                    </a>
                <?php endif; ?>
            </form>
        </div>
    </div>

    <!-- Budget Reserves Table -->
    <div class="card">
        <div class="card-header">
            <h3 class="card-title">Budjet Jamg'armasi Ro'yxati</h3>
            <span class="badge badge-info"><?= number_format($totalRecords) ?> ta yozuv</span>
        </div>
        <div class="card-body">
            <div class="alert alert-info mb-3">
                <strong>ℹ️ Ma'lumot:</strong> Bu yerda har bir yakunlangan buyurtmadan olingan ulush ko'rsatilgan —
                hozir <strong><?= $commissionLabel ?></strong>. Ulushni texnika egasi to'laydi, mijoz emas.
                Bu pul tizim budjetiga tegishli va marketing, texnik xizmat va boshqa xarajatlar uchun ishlatiladi.
                Rejimni «Platforma ulushi» sahifasida almashtirish mumkin.
            </div>

            <div class="table-responsive">
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Buyurtma</th>
                            <th>Client</th>
                            <th>Texnika</th>
                            <th>Owner</th>
                            <th>Buyurtma Summasi</th>
                            <th>Komissiya</th>
                            <th>Sana</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php if (empty($reserves)): ?>
                        <tr>
                            <td colspan="8" style="text-align: center; padding: 2rem;">
                                <div style="color: var(--text-muted);">
                                    📭 Hozircha budjet jamg'armasi yo'q
                                </div>
                            </td>
                        </tr>
                        <?php else: ?>
                        <?php foreach ($reserves as $reserve): ?>
                        <tr>
                            <td><strong>#<?= $reserve['id'] ?></strong></td>
                            <td>
                                <a href="orders.php?search=<?= $reserve['order_id'] ?>" style="color: var(--primary-color);">
                                    #<?= $reserve['order_id'] ?>
                                </a><br>
                                <small class="text-muted">
                                    <?= formatDate($reserve['start_date'], 'd.m.Y') ?> -
                                    <?= formatDate($reserve['end_date'], 'd.m.Y') ?>
                                </small>
                            </td>
                            <td>
                                <?= htmlspecialchars($reserve['client_name']) ?><br>
                                <small class="text-muted"><?= htmlspecialchars($reserve['client_phone']) ?></small>
                            </td>
                            <td>
                                <strong><?= htmlspecialchars(equipmentTypeName($reserve['equipment_type'])) ?></strong><br>
                                <small class="text-muted"><?= htmlspecialchars($reserve['equipment_model']) ?></small>
                            </td>
                            <td><?= htmlspecialchars($reserve['owner_name']) ?></td>
                            <td>
                                <strong><?= number_format($reserve['order_total'], 0) ?></strong> so'm
                            </td>
                            <td>
                                <strong style="color: var(--success-color);">
                                    <?= number_format($reserve['amount'], 0) ?>
                                </strong> so'm
                            </td>
                            <td><?= formatDate($reserve['created_at'], 'd.m.Y H:i') ?></td>
                        </tr>
                        <?php endforeach; ?>
                        <?php endif; ?>
                    </tbody>
                </table>
            </div>

            <!-- Pagination -->
            <?php if ($totalPages > 1): ?>
                <div class="pagination">
                    <?php
                    $queryParams = [];
                    if ($searchQuery) $queryParams[] = 'search=' . urlencode($searchQuery);
                    if ($dateFrom) $queryParams[] = 'date_from=' . $dateFrom;
                    if ($dateTo) $queryParams[] = 'date_to=' . $dateTo;
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

