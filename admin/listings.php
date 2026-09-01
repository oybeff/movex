<?php
/**
 * E'lonlar — mijoz o'z so'zlari bilan yozgan buyurtmalar.
 *
 * Zayavkadan farqi: ma'lumotnoma va savdo yo'q. Egasi "olaman" bosadi, mijoz
 * uni tasdiqlaydi. Pul bu yerda umuman aylanmaydi.
 *
 * Sahifada admin bitta amal qila oladi — e'lonni yopish. U spam va haqorat
 * uchun kerak. Boshqa hech narsa: kimni tanlash mijozning ishi, admin uning
 * o'rniga ijrochi tayinlamaydi.
 *
 * TELEFON RAQAMI bu sahifada ko'rsatiladi va bu ataylab: shikoyat kelganda
 * admin ikkala tomon bilan bog'lana olishi kerak. Ilovada esa raqam faqat
 * tasdiqdan keyin ochiladi.
 */
require_once 'config.php';
requireAdmin();
requireCsrfToken();

$pageTitle = "E'lonlar";
$currentPage = 'listings';

$db = getDbConnection();
$message = '';
$messageType = '';

// CSRF requireCsrfToken() da tekshirilgan — bu yerga faqat o'z formadan
// kelgan so'rov yetib keladi.
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    $listingId = intval($_POST['listing_id'] ?? 0);
    if ($_POST['action'] === 'close' && $listingId > 0) {
        // Yakunlangan e'lonni qayta yopishning ma'nosi yo'q, tarixni
        // buzadi: "done" holati ishning bajarilganini bildiradi.
        $stmt = $db->prepare(
            "UPDATE listings SET status = 'cancelled'
             WHERE id = ? AND status NOT IN ('done', 'cancelled')"
        );
        $stmt->execute([$listingId]);
        if ($stmt->rowCount() > 0) {
            $message = "E'lon #$listingId yopildi";
            $messageType = 'success';
        } else {
            $message = "E'lon #$listingId allaqachon yopilgan";
            $messageType = 'error';
        }
    }
}

$page = isset($_GET['page']) ? max(1, intval($_GET['page'])) : 1;
$perPage = ITEMS_PER_PAGE;
$offset = ($page - 1) * $perPage;

$statusFilter = $_GET['status'] ?? '';

$whereClause = '';
$params = [];
if (!empty($statusFilter)) {
    $whereClause = 'WHERE l.status = ?';
    $params[] = $statusFilter;
}

$countStmt = $db->prepare("SELECT COUNT(*) AS total FROM listings l $whereClause");
$countStmt->execute($params);
$totalListings = $countStmt->fetch()['total'];
$totalPages = ceil($totalListings / $perPage);

// Rasmlar soni LEFT JOIN bilan: har qator uchun alohida so'rov ketsa,
// 50 ta e'lon 51 ta so'rovga aylanadi.
$query = "
    SELECT
        l.id,
        l.title,
        l.description,
        l.equipment_type,
        l.budget,
        l.address,
        l.needed_from,
        l.needed_to,
        l.status,
        l.contact_phone,
        l.views_count,
        l.created_at,
        l.expires_at,
        c.full_name AS client_name,
        c.phone AS client_phone,
        t.full_name AS taker_name,
        t.phone AS taker_phone,
        COUNT(p.id) AS photo_count
    FROM listings l
    JOIN users c ON l.client_id = c.id
    LEFT JOIN users t ON l.taken_by = t.id
    LEFT JOIN listing_photos p ON p.listing_id = l.id
    $whereClause
    GROUP BY l.id, c.full_name, c.phone, t.full_name, t.phone
    ORDER BY l.created_at DESC
    LIMIT ? OFFSET ?
";
$params[] = $perPage;
$params[] = $offset;
$stmt = $db->prepare($query);
$stmt->execute($params);
$listings = $stmt->fetchAll();

$stats = $db->query("
    SELECT
        COUNT(*) AS total,
        COUNT(*) FILTER (WHERE status = 'open') AS open,
        COUNT(*) FILTER (WHERE status = 'taken') AS taken,
        COUNT(*) FILTER (WHERE status = 'confirmed') AS confirmed,
        COUNT(*) FILTER (WHERE status = 'done') AS done
    FROM listings
")->fetch();

// Uzoq javobsiz turgan e'lonlar: ko'p bo'lsa, demak egalar bu bo'limga
// kirmayapti yoki e'lonlar ular uchun mos emas.
$stale = $db->query("
    SELECT COUNT(*) AS n
    FROM listings
    WHERE status = 'open' AND created_at < NOW() - INTERVAL '3 days'
")->fetch()['n'];

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
                    <div class="stat-title">Jami e'lonlar</div>
                    <div class="stat-value"><?= number_format($stats['total']) ?></div>
                </div>
                <div class="stat-icon primary">📢</div>
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
                    <div class="stat-title">Tasdiq kutmoqda</div>
                    <div class="stat-value"><?= number_format($stats['taken']) ?></div>
                    <div class="stat-change">ega oldi, mijoz javob bermadi</div>
                </div>
                <div class="stat-icon info">✋</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">3 kundan beri javobsiz</div>
                    <div class="stat-value"><?= number_format($stale) ?></div>
                </div>
                <div class="stat-icon <?= $stale > 0 ? 'danger' : 'success' ?>">🔇</div>
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
                        <option value="taken" <?= $statusFilter === 'taken' ? 'selected' : '' ?>>Tasdiq kutmoqda</option>
                        <option value="confirmed" <?= $statusFilter === 'confirmed' ? 'selected' : '' ?>>Ishda</option>
                        <option value="done" <?= $statusFilter === 'done' ? 'selected' : '' ?>>Yakunlangan</option>
                        <option value="cancelled" <?= $statusFilter === 'cancelled' ? 'selected' : '' ?>>Bekor qilingan</option>
                        <option value="expired" <?= $statusFilter === 'expired' ? 'selected' : '' ?>>Muddati o'tgan</option>
                    </select>
                </div>

                <button type="submit" class="btn btn-primary">🔍 Filtrlash</button>

                <?php if (!empty($statusFilter)): ?>
                    <a href="listings.php" class="btn btn-secondary">✖️ Tozalash</a>
                <?php endif; ?>
            </form>
        </div>
    </div>

    <div class="card">
        <div class="card-header">
            <h3 class="card-title">E'lonlar ro'yxati</h3>
            <span class="badge badge-info"><?= number_format($totalListings) ?> ta e'lon</span>
        </div>
        <div class="card-body">
            <div class="table-responsive">
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Mijoz</th>
                            <th>Nima kerak</th>
                            <th>Muddat</th>
                            <th>Byudjet</th>
                            <th>Ijrochi</th>
                            <th>Status</th>
                            <th>Yaratilgan</th>
                            <th>Amal</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php if (empty($listings)): ?>
                        <tr>
                            <td colspan="9" class="text-muted" style="text-align: center; padding: 24px;">
                                E'lonlar yo'q
                            </td>
                        </tr>
                        <?php endif; ?>
                        <?php foreach ($listings as $l): ?>
                        <tr>
                            <td><strong>#<?= $l['id'] ?></strong></td>
                            <td>
                                <?= htmlspecialchars($l['client_name']) ?><br>
                                <small class="text-muted"><?= htmlspecialchars($l['client_phone']) ?></small>
                            </td>
                            <td style="max-width: 320px;">
                                <strong><?= htmlspecialchars($l['title']) ?></strong>
                                <?php if (!empty($l['description'])): ?>
                                    <br><small class="text-muted">
                                        <?= htmlspecialchars(mb_substr($l['description'], 0, 90)) ?><?= mb_strlen($l['description']) > 90 ? '…' : '' ?>
                                    </small>
                                <?php endif; ?>
                                <?php if (!empty($l['equipment_type'])): ?>
                                    <br><span class="badge badge-secondary"><?= htmlspecialchars(equipmentTypeName($l['equipment_type'])) ?></span>
                                <?php endif; ?>
                                <?php if ($l['photo_count'] > 0): ?>
                                    <span class="badge badge-info">📷 <?= $l['photo_count'] ?></span>
                                <?php endif; ?>
                                <?php if (!empty($l['address'])): ?>
                                    <br><small class="text-muted">📍 <?= htmlspecialchars($l['address']) ?></small>
                                <?php endif; ?>
                            </td>
                            <td>
                                <?php if (!empty($l['needed_from'])): ?>
                                    <?= formatDate($l['needed_from'], 'd.m.Y') ?>
                                    <?php if (!empty($l['needed_to'])): ?>
                                        <br><small class="text-muted">→ <?= formatDate($l['needed_to'], 'd.m.Y') ?></small>
                                    <?php endif; ?>
                                <?php else: ?>
                                    <small class="text-muted">—</small>
                                <?php endif; ?>
                            </td>
                            <td>
                                <?php if ($l['budget'] !== null): ?>
                                    <?= number_format($l['budget'], 0) ?> so'm
                                <?php else: ?>
                                    <small class="text-muted">ko'rsatilmagan</small>
                                <?php endif; ?>
                            </td>
                            <td>
                                <?php if (!empty($l['taker_name'])): ?>
                                    <?= htmlspecialchars($l['taker_name']) ?><br>
                                    <small class="text-muted"><?= htmlspecialchars($l['taker_phone']) ?></small>
                                <?php else: ?>
                                    <small class="text-muted">—</small>
                                <?php endif; ?>
                            </td>
                            <td>
                                <?php
                                $statusClass = [
                                    'open' => 'warning',
                                    'taken' => 'info',
                                    'confirmed' => 'primary',
                                    'done' => 'success',
                                    'cancelled' => 'danger',
                                    'expired' => 'secondary',
                                ][$l['status']] ?? 'secondary';

                                $statusText = [
                                    'open' => 'Ochiq',
                                    'taken' => 'Tasdiq kutmoqda',
                                    'confirmed' => 'Ishda',
                                    'done' => 'Yakunlangan',
                                    'cancelled' => 'Bekor qilingan',
                                    'expired' => "Muddati o'tgan",
                                ][$l['status']] ?? ($l['status'] ?? '');
                                ?>
                                <span class="badge badge-<?= $statusClass ?>"><?= $statusText ?></span>
                                <br><small class="text-muted">👁 <?= intval($l['views_count']) ?></small>
                            </td>
                            <td><?= formatDate($l['created_at'], 'd.m.Y H:i') ?></td>
                            <td>
                                <?php if (!in_array($l['status'], ['done', 'cancelled'], true)): ?>
                                    <form method="POST" action="" style="display: inline;"
                                          onsubmit="return confirm('E\'lon #<?= $l['id'] ?> yopilsinmi?');">
                                        <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                        <input type="hidden" name="action" value="close">
                                        <input type="hidden" name="listing_id" value="<?= $l['id'] ?>">
                                        <button type="submit" class="btn btn-sm btn-danger">Yopish</button>
                                    </form>
                                <?php else: ?>
                                    <small class="text-muted">—</small>
                                <?php endif; ?>
                            </td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>

            <?php if ($totalPages > 1): ?>
                <div class="pagination">
                    <?php $q = $statusFilter ? '&status=' . urlencode($statusFilter) : ''; ?>
                    <?php if ($page > 1): ?>
                        <a href="?page=<?= $page - 1 ?><?= $q ?>">← Oldingi</a>
                    <?php endif; ?>

                    <?php for ($i = max(1, $page - 2); $i <= min($totalPages, $page + 2); $i++): ?>
                        <?php if ($i === $page): ?>
                            <span class="active"><?= $i ?></span>
                        <?php else: ?>
                            <a href="?page=<?= $i ?><?= $q ?>"><?= $i ?></a>
                        <?php endif; ?>
                    <?php endfor; ?>

                    <?php if ($page < $totalPages): ?>
                        <a href="?page=<?= $page + 1 ?><?= $q ?>">Keyingi →</a>
                    <?php endif; ?>
                </div>
            <?php endif; ?>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>
