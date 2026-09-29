<?php
/**
 * Pul yechish arizalari.
 *
 * Texnika egasi ilovada ariza beradi, admin shu yerda ko'rib chiqadi.
 * Pul kartaga MULTICARD orqali o'tadi (POST /payment/credit) — admin bank
 * ilovasida qo'lda o'tkazmaydi.
 *
 * MUHIM: bu sahifa pulni O'ZI HARAKATLANTIRMAYDI. Ilgari harakatlantirardi
 * va payout_service dagi mantiqni takrorlardi — ikkisi ajralib ketishi
 * mumkin edi. Endi panel backend'ning ichki manziliga murojaat qiladi
 * (internalApiPost), ya'ni pul harakati BITTA joyda: payout_service.
 *
 * Uchta amal:
 *   pay    — kartaga o'tkazish (balansdan yechish faqat shlyuz
 *            tasdiqlaganidan keyin);
 *   reject — rad etish, pul egasida qoladi;
 *   sync   — holatni shlyuzdan so'rash. Javob kelmagan holat uchun:
 *            so'rovni QAYTARISH man etilgan, aks holda bir arizaga pul
 *            ikki marta ketardi.
 */
require_once 'config.php';
requireAdmin();
requireCsrfToken();

$pageTitle = 'Pul Yechish Arizalari';
$currentPage = 'payouts';

$db = getDbConnection();
$message = '';
$messageType = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'], $_POST['request_id'])) {
    $requestId = intval($_POST['request_id']);
    $action = $_POST['action'];
    $adminComment = sanitizeInput($_POST['admin_comment'] ?? '');

    $endpoints = [
        'paid'     => ['/payouts/internal/' . $requestId . '/pay',
                       'Pul kartaga o\'tkazildi, balansdan yechildi'],
        'rejected' => ['/payouts/internal/' . $requestId . '/reject',
                       'Ariza rad etildi, pul egasida qoldi'],
        'sync'     => ['/payouts/internal/' . $requestId . '/sync',
                       'Holat shlyuzdan yangilandi'],
    ];

    if (!isset($endpoints[$action])) {
        $message = 'Noma\'lum amal';
        $messageType = 'error';
    } else {
        [$path, $successMessage] = $endpoints[$action];
        $result = internalApiPost($path, [
            'admin_comment' => $adminComment ?: null,
            'admin_id' => $_SESSION['admin_user_id'] ?? null,
        ]);

        if ($result['ok']) {
            $status = $result['data']['status'] ?? '';
            $gateway = $result['data']['rahmat_status'] ?? '';
            $message = $successMessage;
            if ($action === 'sync' || ($status === 'pending' && $gateway !== '')) {
                // Pul yo'lda (draft/progress). Bu xato emas, lekin admin
                // "to'landi" deb o'ylab qolmasligi kerak.
                $message .= ' — holat: ' . ($gateway ?: $status);
            }
            $messageType = 'success';
        } else {
            $message = $result['error'];
            $messageType = 'error';
        }
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
        pr.id, pr.amount, pr.commission, pr.payout_amount,
        pr.status, pr.card_number, pr.card_holder,
        pr.rahmat_uuid, pr.rahmat_status, pr.rahmat_receipt_url, pr.rahmat_error,
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
        COALESCE(SUM(CASE WHEN status = 'pending' THEN payout_amount END), 0) as pending_amount,
        COALESCE(SUM(CASE WHEN status = 'paid' THEN payout_amount END), 0) as paid_amount,
        COALESCE(SUM(CASE WHEN status = 'paid' AND processed_at >= NOW() - INTERVAL '30 days'
                          THEN payout_amount END), 0) as paid_month,
        COALESCE(SUM(CASE WHEN status = 'paid' THEN commission END), 0) as commission_total
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
                    <div class="stat-change">
                        <?= number_format($stats['pending_amount'], 0) ?> so'm kartaga
                    </div>
                </div>
                <div class="stat-icon warning">⏳</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Oxirgi 30 kun</div>
                    <div class="stat-value"><?= number_format($stats['paid_month'], 0) ?></div>
                    <div class="stat-change">so'm kartalarga o'tkazilgan</div>
                </div>
                <div class="stat-icon primary">📅</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Jami o'tkazilgan</div>
                    <div class="stat-value"><?= number_format($stats['paid_amount'], 0) ?></div>
                    <div class="stat-change">so'm</div>
                </div>
                <div class="stat-icon success">✅</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Ushlangan ulush</div>
                    <div class="stat-value"><?= number_format($stats['commission_total'], 0) ?></div>
                    <div class="stat-change">so'm — <a href="commission.php">sozlash</a></div>
                </div>
                <div class="stat-icon primary">💳</div>
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
                        <th>Balansidan</th>
                        <th>Kartaga o'tkaziladi</th>
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
                        <td>
                            <?= number_format($r['amount'], 0) ?> so'm
                            <?php if ((float)$r['commission'] > 0): ?>
                                <br><small style="color:#6b7280;">
                                    ulush: <?= number_format($r['commission'], 0) ?> so'm
                                </small>
                            <?php endif; ?>
                        </td>
                        <td>
                            <!-- Kartaga aynan shu summa o'tkaziladi. Ulush ariza
                                 summasining ichidan ushlanadi, shuning uchun bu
                                 raqam yuqoridagidan kichik bo'lishi normal. -->
                            <strong style="font-size:15px;">
                                <?= number_format($r['payout_amount'], 0) ?>
                            </strong> so'm
                        </td>
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
                            <?php if (!empty($r['rahmat_status'])): ?>
                                <!-- Shlyuzning o'z holati. Bizning holatdan
                                     alohida ko'rsatiladi: 'progress' — pul
                                     yo'lda, 'draft' — hali yo'lga chiqmagan,
                                     bizda esa ikkalasi 'pending'. -->
                                <br><small style="color:#6b7280;">
                                    shlyuz: <?= htmlspecialchars($r['rahmat_status']) ?>
                                </small>
                            <?php endif; ?>
                            <?php if (!empty($r['rahmat_receipt_url'])): ?>
                                <br><small>
                                    <a href="<?= htmlspecialchars($r['rahmat_receipt_url']) ?>"
                                       target="_blank" rel="noopener">chek</a>
                                </small>
                            <?php endif; ?>
                            <?php if (!empty($r['rahmat_error'])): ?>
                                <br><small style="color:var(--error-color,#dc2626);">
                                    <?= htmlspecialchars($r['rahmat_error']) ?>
                                </small>
                            <?php endif; ?>
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
                                    <!-- Tugma pulni HOZIR jo'natadi. Ilgari u
                                         "men qo'lda o'tkazdim" degani edi,
                                         shuning uchun matni ham o'zgardi. -->
                                    <button type="submit" name="action" value="paid"
                                            class="btn btn-primary" style="padding:4px 10px; font-size:13px;"
                                            onclick="return confirm('Kartaga <?= number_format($r['payout_amount'], 0, '.', ' ') ?> so\'m HOZIR o\'tkaziladi. Egasining balansidan <?= number_format($r['amount'], 0, '.', ' ') ?> so\'m yechiladi. Davom etasizmi?')">
                                        Kartaga o'tkazish
                                    </button>
                                    <button type="submit" name="action" value="rejected"
                                            class="btn" style="padding:4px 10px; font-size:13px;"
                                            onclick="return confirm('Arizani rad etasizmi?')">
                                        Rad etish
                                    </button>
                                    <?php if (!empty($r['rahmat_uuid']) || !empty($r['rahmat_error'])): ?>
                                        <!-- O'tkazma boshlangan, lekin natija
                                             aniq emas. Qayta jo'natish MAN
                                             ETILGAN — holatni so'raymiz. -->
                                        <button type="submit" name="action" value="sync"
                                                class="btn" style="padding:4px 10px; font-size:13px;">
                                            Holatni tekshirish
                                        </button>
                                    <?php endif; ?>
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
