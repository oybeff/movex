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

/**
 * Saralash. Foydalanuvchi bergan matn SO'ROVGA QO'SHILMAYDI — faqat shu
 * ro'yxatdagi kalit ishlatiladi, aks holda ORDER BY orqali SQL yozib
 * yuborish mumkin bo'lardi.
 */
$sortOptions = [
    'created' => ['l.created_at DESC', 'Yangi e\'lonlar'],
    'views'   => ['l.views_count DESC, l.created_at DESC', "Ko'p ko'rilgan"],
    'likes'   => ['likes_count DESC, l.created_at DESC', "Ko'p yoqtirilgan"],
    'saves'   => ['saves_count DESC, l.created_at DESC', "Ko'p saqlangan"],
    'offers'  => ['offers_count DESC, l.created_at DESC', "Ko'p taklif"],
    'quiet'   => ['(l.views_count + 0) ASC, l.created_at DESC', "Eng sust"],
];
$sort = $_GET['sort'] ?? 'created';
if (!isset($sortOptions[$sort])) {
    $sort = 'created';
}
$orderBy = $sortOptions[$sort][0];

// Rasmlar soni LEFT JOIN bilan: har qator uchun alohida so'rov ketsa,
// 50 ta e'lon 51 ta so'rovga aylanadi.
//
// Yoqtirish/saqlash/takliflar esa skalyar so'rovchalar bilan: ularni ham
// JOIN qilsak, qatorlar bir-biriga ko'payib, rasm sanog'i yolg'on
// ko'rsatardi.
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
        COUNT(p.id) AS photo_count,
        (SELECT COUNT(*) FROM listing_reactions r
          WHERE r.listing_id = l.id AND r.kind = 'like')  AS likes_count,
        (SELECT COUNT(*) FROM listing_reactions r
          WHERE r.listing_id = l.id AND r.kind = 'save')  AS saves_count,
        (SELECT COUNT(*) FROM listing_offers o
          WHERE o.listing_id = l.id
            AND o.status IN ('pending','accepted'))       AS offers_count,
        (SELECT MIN(o.price) FROM listing_offers o
          WHERE o.listing_id = l.id AND o.status = 'pending') AS best_offer
    FROM listings l
    JOIN users c ON l.client_id = c.id
    LEFT JOIN users t ON l.taken_by = t.id
    LEFT JOIN listing_photos p ON p.listing_id = l.id
    $whereClause
    GROUP BY l.id, c.full_name, c.phone, t.full_name, t.phone
    ORDER BY $orderBy
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

// Qiziqish ko'rsatkichlari. Ular alohida turadi, chunki savol boshqacha:
// e'lonlar ko'rilyaptimi va ularga javob berilyaptimi.
$engagement = $db->query("
    SELECT
        COALESCE(SUM(views_count), 0) AS views,
        (SELECT COUNT(*) FROM listing_reactions WHERE kind = 'like') AS likes,
        (SELECT COUNT(*) FROM listing_reactions WHERE kind = 'save') AS saves,
        (SELECT COUNT(*) FROM listing_offers
          WHERE status IN ('pending','accepted')) AS offers,
        COUNT(*) FILTER (WHERE views_count = 0 AND status = 'open') AS unseen
    FROM listings
")->fetch();

// Nechta e'lon umuman javob olgan — konversiya. Ko'rish ko'p, javob yo'q
// bo'lsa, e'lonlar odamlarga mos kelmayapti degani.
$answered = $db->query("
    SELECT COUNT(DISTINCT l.id) AS n
    FROM listings l
    WHERE EXISTS (SELECT 1 FROM listing_offers o WHERE o.listing_id = l.id)
       OR l.taken_by IS NOT NULL
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

    <!-- ==================== Qiziqish ====================
         Savol boshqacha: e'lonlar ko'rilyaptimi va ularga javob
         berilyaptimi. Shuning uchun alohida qator. -->

    <h2 style="margin: 30px 0 14px; font-size: 19px;">Qiziqish</h2>

    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Ko'rishlar</div>
                    <div class="stat-value"><?= number_format($engagement['views']) ?></div>
                    <div class="stat-change">
                        <a href="?sort=views<?= $statusFilter ? '&status=' . urlencode($statusFilter) : '' ?>">
                            ko'p ko'rilganlar →
                        </a>
                    </div>
                </div>
                <div class="stat-icon primary">👁</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Yoqtirishlar</div>
                    <div class="stat-value"><?= number_format($engagement['likes']) ?></div>
                    <div class="stat-change">
                        <a href="?sort=likes<?= $statusFilter ? '&status=' . urlencode($statusFilter) : '' ?>">
                            reyting →
                        </a>
                    </div>
                </div>
                <div class="stat-icon danger">❤️</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Saqlanganlar</div>
                    <div class="stat-value"><?= number_format($engagement['saves']) ?></div>
                    <div class="stat-change">
                        <a href="?sort=saves<?= $statusFilter ? '&status=' . urlencode($statusFilter) : '' ?>">
                            xatcho'plar →
                        </a>
                    </div>
                </div>
                <div class="stat-icon info">🔖</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Takliflar</div>
                    <div class="stat-value"><?= number_format($engagement['offers']) ?></div>
                    <div class="stat-change">
                        <?= number_format($answered) ?> ta e'lon javob olgan
                    </div>
                </div>
                <div class="stat-icon success">💬</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Hech kim ochmagan</div>
                    <div class="stat-value"><?= number_format($engagement['unseen']) ?></div>
                    <div class="stat-change">ochiq, lekin 0 ko'rish</div>
                </div>
                <div class="stat-icon <?= $engagement['unseen'] > 0 ? 'warning' : 'success' ?>">🕳</div>
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

                <div class="form-group" style="margin-bottom: 0;">
                    <label for="sort">Saralash</label>
                    <select name="sort" id="sort">
                        <?php foreach ($sortOptions as $key => [$_expr, $label]): ?>
                            <option value="<?= $key ?>" <?= $sort === $key ? 'selected' : '' ?>>
                                <?= htmlspecialchars($label) ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>

                <button type="submit" class="btn btn-primary">🔍 Filtrlash</button>

                <?php if (!empty($statusFilter) || $sort !== 'created'): ?>
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
                            <th>Qiziqish</th>
                            <th>Yaratilgan</th>
                            <th>Amal</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php if (empty($listings)): ?>
                        <tr>
                            <td colspan="10" class="text-muted" style="text-align: center; padding: 24px;">
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
                            </td>
                            <td style="white-space: nowrap;">
                                <?php
                                // Ko'rish sanog'i ilgari status ostida mayda
                                // kulrang yozuv edi va uni hech kim topmasdi.
                                // Endi alohida ustun: raqamlar bir qatorda,
                                // nolga tegmagani ko'zga tashlanmaydi.
                                $views  = intval($l['views_count']);
                                $likes  = intval($l['likes_count']);
                                $saves  = intval($l['saves_count']);
                                $offers = intval($l['offers_count']);
                                $dim = 'color:#c0c4cc;';   // nol — bo'sh joydek
                                ?>
                                <span title="ko'rishlar" style="<?= $views ? '' : $dim ?>">
                                    👁 <strong><?= $views ?></strong>
                                </span>
                                &nbsp;
                                <span title="yoqtirishlar" style="<?= $likes ? '' : $dim ?>">
                                    ❤️ <strong><?= $likes ?></strong>
                                </span>
                                <br>
                                <span title="saqlanganlar" style="<?= $saves ? '' : $dim ?>">
                                    🔖 <strong><?= $saves ?></strong>
                                </span>
                                &nbsp;
                                <span title="takliflar" style="<?= $offers ? '' : $dim ?>">
                                    💬 <strong><?= $offers ?></strong>
                                </span>
                                <?php if ($l['best_offer'] !== null): ?>
                                    <br><small class="text-muted">
                                        eng arzon: <?= number_format($l['best_offer'], 0, '.', ' ') ?>
                                    </small>
                                <?php endif; ?>
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
                    <?php
                    // Saralash ham havolada qolishi kerak: aks holda ikkinchi
                    // sahifaga o'tganda ro'yxat yana sanaga qaytib ketardi.
                    $q = ($statusFilter ? '&status=' . urlencode($statusFilter) : '')
                       . ($sort !== 'created' ? '&sort=' . urlencode($sort) : '');
                    ?>
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
