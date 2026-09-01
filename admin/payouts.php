<?php
/**
 * Pul yechish arizalari.
 *
 * Texnika egasi ilovada ariza beradi, admin shu yerda ko'rib chiqadi.
 * Pul o'tkazish qo'lda bajariladi (karta orqali), bu sahifa faqat hisobni
 * yuritadi: to'landi deb belgilanganda summa balansdan yechiladi.
 *
 * MUHIM: pul harakati bilan bog'liq mantiq backend'dagi payout_service
 * bilan bir xil bo'lishi shart — u yerda ham xuddi shunday yoziladi.
 */
require_once 'config.php';
requireAdmin();
requireCsrfToken();

$pageTitle = 'Pul Yechish Arizalari';
$currentPage = 'payouts';

$db = getDbConnection();
$message = '';
$messageType = '';

// Arizani hal qilish
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'], $_POST['request_id'])) {
    $requestId = intval($_POST['request_id']);
    $action = $_POST['action'];
    $adminComment = sanitizeInput($_POST['admin_comment'] ?? '');

    try {
        $db->beginTransaction();

        // Arizani va balansni bloklab olamiz: bir vaqtda ikki admin
        // bir arizani ikki marta o'tkazib yubormasligi kerak
        $stmt = $db->prepare("SELECT * FROM payout_requests WHERE id = ? FOR UPDATE");
        $stmt->execute([$requestId]);
        $request = $stmt->fetch();

        if (!$request) {
            throw new Exception('Ariza topilmadi');
        }
        if ($request['status'] !== 'pending') {
            throw new Exception('Ariza allaqachon ko\'rib chiqilgan: ' . $request['status']);
        }

        $stmt = $db->prepare("SELECT * FROM balances WHERE user_id = ? FOR UPDATE");
        $stmt->execute([$request['user_id']]);
        $balance = $stmt->fetch();

        if (!$balance) {
            throw new Exception('Foydalanuvchi balansi topilmadi');
        }

        $amount = $request['amount'];

        if ($action === 'paid') {
            if ($balance['frozen_balance'] < $amount || $balance['balance'] < $amount) {
                throw new Exception('Balansdagi ma\'lumot arizaga mos kelmaydi, qo\'lda tekshiring');
            }

            // To'landi: balansdan yechamiz va muzlatishni olib tashlaymiz
            $stmt = $db->prepare(
                "UPDATE balances SET balance = balance - ?, frozen_balance = frozen_balance - ?
                 WHERE user_id = ?"
            );
            $stmt->execute([$amount, $amount, $request['user_id']]);

            $stmt = $db->prepare(
                "INSERT INTO balance_transactions (user_id, amount, type, status, description, created_at)
                 VALUES (?, ?, 'withdrawal', 'completed', ?, NOW())"
            );
            $stmt->execute([
                $request['user_id'],
                $amount,
                'Pul yechish #' . $requestId,
            ]);

            $newStatus = 'paid';
            $message = 'Ariza to\'langan deb belgilandi';
        } elseif ($action === 'rejected') {
            // Rad etildi: faqat muzlatishni olib tashlaymiz, pul egasida qoladi
            $stmt = $db->prepare(
                "UPDATE balances
                 SET frozen_balance = GREATEST(frozen_balance - ?, 0)
                 WHERE user_id = ?"
            );
            $stmt->execute([$amount, $request['user_id']]);

            $newStatus = 'rejected';
            $message = 'Ariza rad etildi, pul egasida qoldi';
        } else {
            throw new Exception('Noma\'lum amal');
        }

        $stmt = $db->prepare(
            "UPDATE payout_requests
             SET status = ?, admin_comment = ?, processed_by = ?, processed_at = NOW(), updated_at = NOW()
             WHERE id = ?"
        );
        $stmt->execute([$newStatus, $adminComment ?: null, $_SESSION['admin_user_id'], $requestId]);

        $db->commit();
        $messageType = 'success';
    } catch (Exception $e) {
        $db->rollBack();
        $message = $e->getMessage();
        $messageType = 'error';
    }
}

// Pagination va filtrlar
$page = isset($_GET['page']) ? max(1, intval($_GET['page'])) : 1;
$perPage = ITEMS_PER_PAGE;
$offset = ($page - 1) * $perPage;

$statusFilter = $_GET['status'] ?? 'pending';
$searchQuery = $_GET['search'] ?? '';

$whereConditions = [];
$params = [];

if ($statusFilter !== 'all') {
    $whereConditions[] = "pr.status = ?";
    $params[] = $statusFilter;
}

if (!empty($searchQuery)) {
    $whereConditions[] = "(u.full_name ILIKE ? OR u.phone ILIKE ?)";
    $params[] = "%$searchQuery%";
    $params[] = "%$searchQuery%";
}

$whereClause = !empty($whereConditions) ? 'WHERE ' . implode(' AND ', $whereConditions) : '';

$countQuery = "
    SELECT COUNT(*) as total
    FROM payout_requests pr
    JOIN users u ON pr.user_id = u.id
    $whereClause
";
$countStmt = $db->prepare($countQuery);
$countStmt->execute($params);
$totalRecords = $countStmt->fetch()['total'];
$totalPages = max(1, ceil($totalRecords / $perPage));

$query = "
    SELECT
        pr.id, pr.amount, pr.status, pr.card_number, pr.card_holder,
        pr.comment, pr.admin_comment, pr.created_at, pr.processed_at,
        u.full_name, u.phone,
        b.balance, b.frozen_balance
    FROM payout_requests pr
    JOIN users u ON pr.user_id = u.id
    LEFT JOIN balances b ON b.user_id = pr.user_id
    $whereClause
    ORDER BY pr.created_at DESC
    LIMIT $perPage OFFSET $offset
";
$stmt = $db->prepare($query);
$stmt->execute($params);
$requests = $stmt->fetchAll();

// Statistika
$stats = $db->query("
    SELECT
        COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending_count,
        COALESCE(SUM(CASE WHEN status = 'pending' THEN amount END), 0) as pending_amount,
        COALESCE(SUM(CASE WHEN status = 'paid' THEN amount END), 0) as paid_amount,
        COALESCE(SUM(CASE WHEN status = 'paid' AND processed_at >= NOW() - INTERVAL '30 days'
                          THEN amount END), 0) as paid_month
    FROM payout_requests
")->fetch();

include 'includes/header.php';
?>

<div class="content">
    <?php if ($message): ?>
        <div class="alert alert-<?= $messageType === 'success' ? 'success' : 'error' ?>">
            <?= htmlspecialchars($message) ?>
        </div>
    <?php endif; ?>

    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Kutilmoqda</div>
                    <div class="stat-value"><?= number_format($stats['pending_count']) ?></div>
                    <div class="stat-change"><?= number_format($stats['pending_amount'], 0) ?> so'm</div>
                </div>
                <div class="stat-icon warning">⏳</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Oxirgi 30 kun</div>
                    <div class="stat-value"><?= number_format($stats['paid_month'], 0) ?></div>
                    <div class="stat-change">so'm to'langan</div>
                </div>
                <div class="stat-icon primary">📅</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Jami to'langan</div>
                    <div class="stat-value"><?= number_format($stats['paid_amount'], 0) ?></div>
                    <div class="stat-change">so'm</div>
                </div>
                <div class="stat-icon success">✅</div>
            </div>
        </div>
    </div>

    <div class="card mb-3">
        <div class="card-body">
            <form method="GET" action="" class="d-flex gap-2" style="align-items: flex-end; flex-wrap: wrap;">
                <div class="form-group" style="margin-bottom: 0;">
                    <label for="status">Holat</label>
                    <select id="status" name="status">
                        <?php foreach (['pending' => 'Kutilmoqda', 'paid' => 'To\'langan',
                                        'rejected' => 'Rad etilgan', 'all' => 'Hammasi'] as $value => $label): ?>
                            <option value="<?= $value ?>" <?= $statusFilter === $value ? 'selected' : '' ?>>
                                <?= $label ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>

                <div class="form-group" style="margin-bottom: 0;">
                    <label for="search">Qidirish</label>
                    <input type="text" id="search" name="search"
                           placeholder="Ism yoki telefon..."
                           value="<?= htmlspecialchars($searchQuery) ?>">
                </div>

                <button type="submit" class="btn btn-primary">Filtrlash</button>
                <a href="payouts.php" class="btn">Tozalash</a>
            </form>
        </div>
    </div>

    <div class="card">
        <div class="card-body" style="overflow-x: auto;">
            <?php if (empty($requests)): ?>
                <p style="padding: 24px; text-align: center; color: #6b7280;">
                    Arizalar yo'q
                </p>
            <?php else: ?>
            <table>
                <thead>
                    <tr>
                        <th>#</th>
                        <th>Texnika egasi</th>
                        <th>Summa</th>
                        <th>Karta</th>
                        <th>Balans</th>
                        <th>Sana</th>
                        <th>Holat</th>
                        <th>Amal</th>
                    </tr>
                </thead>
                <tbody>
                <?php foreach ($requests as $r): ?>
                    <tr>
                        <td><?= (int) $r['id'] ?></td>
                        <td>
                            <?= htmlspecialchars($r['full_name']) ?><br>
                            <small style="color:#6b7280;"><?= htmlspecialchars($r['phone']) ?></small>
                        </td>
                        <td><strong><?= number_format($r['amount'], 0) ?></strong> so'm</td>
                        <td>
                            <?php
                            // To'liq raqam faqat shu yerda ko'rsatiladi — pulni
                            // o'tkazish uchun kerak. API'da u hech qachon
                            // to'liq qaytmaydi.
                            $digits = preg_replace('/\D/', '', $r['card_number']);
                            $pretty = trim(chunk_split($digits, 4, ' '));
                            ?>
                            <code><?= htmlspecialchars($pretty) ?></code>
                            <?php if (!empty($r['card_holder'])): ?>
                                <br><small style="color:#6b7280;"><?= htmlspecialchars($r['card_holder']) ?></small>
                            <?php endif; ?>
                        </td>
                        <td>
                            <?= number_format($r['balance'] ?? 0, 0) ?><br>
                            <small style="color:#6b7280;">
                                muzlatilgan: <?= number_format($r['frozen_balance'] ?? 0, 0) ?>
                            </small>
                        </td>
                        <td><?= date('d.m.Y H:i', strtotime($r['created_at'])) ?></td>
                        <td>
                            <?php
                            $badges = [
                                'pending'  => ['warning', 'Kutilmoqda'],
                                'paid'     => ['success', 'To\'langan'],
                                'rejected' => ['error', 'Rad etilgan'],
                            ];
                            [$badgeClass, $badgeText] = $badges[$r['status']] ?? ['', $r['status']];
                            ?>
                            <span class="badge badge-<?= $badgeClass ?>"><?= $badgeText ?></span>
                            <?php if (!empty($r['admin_comment'])): ?>
                                <br><small style="color:#6b7280;"><?= htmlspecialchars($r['admin_comment']) ?></small>
                            <?php endif; ?>
                        </td>
                        <td>
                            <?php if ($r['status'] === 'pending'): ?>
                                <form method="POST" style="display:flex; gap:6px; flex-wrap:wrap; align-items:center;">
                                    <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                    <input type="hidden" name="request_id" value="<?= (int) $r['id'] ?>">
                                    <input type="text" name="admin_comment" placeholder="Izoh"
                                           style="width:120px; padding:4px 8px; font-size:13px;">
                                    <button type="submit" name="action" value="paid"
                                            class="btn btn-primary" style="padding:4px 10px; font-size:13px;"
                                            onclick="return confirm('Pul haqiqatan o\'tkazildimi? Summa balansdan yechiladi.')">
                                        To'landi
                                    </button>
                                    <button type="submit" name="action" value="rejected"
                                            class="btn" style="padding:4px 10px; font-size:13px;"
                                            onclick="return confirm('Arizani rad etasizmi?')">
                                        Rad etish
                                    </button>
                                </form>
                            <?php else: ?>
                                <small style="color:#6b7280;">
                                    <?= $r['processed_at'] ? date('d.m.Y H:i', strtotime($r['processed_at'])) : '—' ?>
                                </small>
                            <?php endif; ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
            <?php endif; ?>
        </div>
    </div>

    <?php if ($totalPages > 1): ?>
    <div class="pagination">
        <?php for ($i = 1; $i <= $totalPages; $i++): ?>
            <a href="?page=<?= $i ?>&status=<?= urlencode($statusFilter) ?>&search=<?= urlencode($searchQuery) ?>"
               class="<?= $i === $page ? 'active' : '' ?>"><?= $i ?></a>
        <?php endfor; ?>
    </div>
    <?php endif; ?>
</div>

<?php include 'includes/footer.php'; ?>
