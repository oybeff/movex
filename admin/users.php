<?php
require_once 'config.php';
requireAdmin();

$pageTitle = 'Foydalanuvchilar';
$currentPage = 'users';

$message = '';
$messageType = '';

/**
 * Foydalanuvchini boshqarish.
 *
 * Admin hisobiga hech qanday amal qo'llanmaydi: o'zini yoki boshqa adminni
 * bloklab qo'yish paneldan chiqib ketishning eng oson yo'li.
 *
 * Parolni KO'RSATIB bo'lmaydi — u bcrypt bilan shifrlangan va shunday
 * bo'lishi kerak. Faqat yangisini o'rnatish mumkin.
 */
if ($_SERVER['REQUEST_METHOD'] === 'POST' && !empty($_POST['action'])) {
    $action = $_POST['action'];
    $userId = intval($_POST['user_id'] ?? 0);
    $db = getDbConnection();

    $target = $db->prepare("SELECT id, role, full_name FROM users WHERE id = ?");
    $target->execute([$userId]);
    $userData = $target->fetch();

    if (!$userData) {
        $message = 'Foydalanuvchi topilmadi';
        $messageType = 'error';
    } elseif ($userData['role'] === 'admin') {
        $message = 'Admin hisobiga bu amalni qo\'llab bo\'lmaydi';
        $messageType = 'error';
    } else {
        switch ($action) {
            case 'delete':
                $db->prepare("DELETE FROM users WHERE id = ?")->execute([$userId]);
                $message = 'Foydalanuvchi o\'chirildi';
                $messageType = 'success';
                break;

            case 'block':
                $reason = trim((string)($_POST['reason'] ?? ''));
                $db->prepare("UPDATE users SET is_blocked = true, blocked_reason = ? WHERE id = ?")
                   ->execute([$reason !== '' ? $reason : null, $userId]);
                $message = 'Hisob bloklandi — endi kira olmaydi';
                $messageType = 'success';
                break;

            case 'unblock':
                $db->prepare("UPDATE users SET is_blocked = false, blocked_reason = NULL WHERE id = ?")
                   ->execute([$userId]);
                $message = 'Blok olib tashlandi';
                $messageType = 'success';
                break;

            case 'freeze':
                $db->prepare("UPDATE users SET is_frozen = true WHERE id = ?")->execute([$userId]);
                $message = 'Hisob muzlatildi — ko\'radi, lekin yangi amal qila olmaydi';
                $messageType = 'success';
                break;

            case 'unfreeze':
                $db->prepare("UPDATE users SET is_frozen = false WHERE id = ?")->execute([$userId]);
                $message = 'Muzlatish olib tashlandi';
                $messageType = 'success';
                break;

            case 'set_role':
                $role = $_POST['role'] ?? '';
                if (!in_array($role, ['client', 'owner'], true)) {
                    $message = 'Rol faqat mijoz yoki ega bo\'lishi mumkin';
                    $messageType = 'error';
                } else {
                    $db->prepare("UPDATE users SET role = ? WHERE id = ?")->execute([$role, $userId]);
                    $message = 'Rol o\'zgartirildi';
                    $messageType = 'success';
                }
                break;

            case 'set_phone':
                $phone = preg_replace('/\D/', '', (string)($_POST['phone'] ?? ''));
                if (strlen($phone) !== 12 || strpos($phone, '998') !== 0) {
                    $message = 'Telefon 998 bilan boshlanib, 12 raqamdan iborat bo\'lsin';
                    $messageType = 'error';
                } else {
                    // Raqam band bo'lmasin: unique cheklov 500 xato berardi
                    $busy = $db->prepare("SELECT id FROM users WHERE phone = ? AND id <> ?");
                    $busy->execute([$phone, $userId]);
                    if ($busy->fetch()) {
                        $message = 'Bu raqam boshqa hisobda band';
                        $messageType = 'error';
                    } else {
                        $db->prepare("UPDATE users SET phone = ? WHERE id = ?")
                           ->execute([$phone, $userId]);
                        $message = 'Telefon raqam o\'zgartirildi';
                        $messageType = 'success';
                    }
                }
                break;

            case 'set_password':
                $newPassword = (string)($_POST['password'] ?? '');
                if (strlen($newPassword) < 6) {
                    $message = 'Parol kamida 6 belgidan iborat bo\'lsin';
                    $messageType = 'error';
                } else {
                    // bcrypt — backend'dagi passlib bilan bir xil format
                    $hash = password_hash($newPassword, PASSWORD_BCRYPT);
                    $db->prepare("UPDATE users SET password_hash = ? WHERE id = ?")
                       ->execute([$hash, $userId]);
                    $message = 'Parol o\'rnatildi. Uni foydalanuvchiga o\'zingiz ayting — '
                             . 'panel parolni saqlamaydi va keyin ko\'rsata olmaydi.';
                    $messageType = 'success';
                }
                break;

            default:
                $message = 'Noma\'lum amal';
                $messageType = 'error';
        }
    }
}

// Pagination
$page = isset($_GET['page']) ? max(1, intval($_GET['page'])) : 1;
$perPage = ITEMS_PER_PAGE;
$offset = ($page - 1) * $perPage;

// Filters
$roleFilter = $_GET['role'] ?? '';
$searchQuery = $_GET['search'] ?? '';

// Build query
$db = getDbConnection();
$whereConditions = [];
$params = [];

if (!empty($roleFilter)) {
    $whereConditions[] = "role = ?";
    $params[] = $roleFilter;
}

if (!empty($searchQuery)) {
    $whereConditions[] = "(full_name ILIKE ? OR phone ILIKE ? OR email ILIKE ?)";
    $searchParam = "%$searchQuery%";
    $params[] = $searchParam;
    $params[] = $searchParam;
    $params[] = $searchParam;
}

$whereClause = !empty($whereConditions) ? 'WHERE ' . implode(' AND ', $whereConditions) : '';

// Get total count
$countQuery = "SELECT COUNT(*) as total FROM users $whereClause";
$countStmt = $db->prepare($countQuery);
$countStmt->execute($params);
$totalUsers = $countStmt->fetch()['total'];
$totalPages = ceil($totalUsers / $perPage);

// Get users
$query = "
    SELECT 
        id, 
        full_name, 
        email, 
        phone, 
        role, 
        created_at,
        is_blocked,
        is_frozen,
        blocked_reason,
        last_login_at,
        (SELECT COUNT(*) FROM orders WHERE user_id = users.id) as orders_count,
        (SELECT balance FROM balances WHERE user_id = users.id) as balance
    FROM users 
    $whereClause
    ORDER BY created_at DESC
    LIMIT ? OFFSET ?
";

$params[] = $perPage;
$params[] = $offset;

$stmt = $db->prepare($query);
$stmt->execute($params);
$users = $stmt->fetchAll();

include 'includes/header.php';
?>

<div class="content">
    <?php if ($message): ?>
        <div class="alert alert-<?= $messageType ?>">
            <?= htmlspecialchars($message) ?>
        </div>
    <?php endif; ?>
    
    <!-- Filters -->
    <div class="card mb-3">
        <div class="card-body">
            <form method="GET" action="" class="d-flex gap-2" style="align-items: flex-end;">
                <div class="form-group" style="flex: 1; margin-bottom: 0;">
                    <label for="search">Qidirish</label>
                    <input 
                        type="text" 
                        id="search" 
                        name="search" 
                        placeholder="Ism, telefon yoki email..."
                        value="<?= htmlspecialchars($searchQuery) ?>"
                    >
                </div>
                
                <div class="form-group" style="margin-bottom: 0;">
                    <label for="role">Rol</label>
                    <select name="role" id="role">
                        <option value="">Barchasi</option>
                        <option value="client" <?= $roleFilter === 'client' ? 'selected' : '' ?>>Client</option>
                        <option value="owner" <?= $roleFilter === 'owner' ? 'selected' : '' ?>>Owner</option>
                        <option value="admin" <?= $roleFilter === 'admin' ? 'selected' : '' ?>>Admin</option>
                    </select>
                </div>
                
                <button type="submit" class="btn btn-primary">
                    🔍 Qidirish
                </button>
                
                <?php if (!empty($searchQuery) || !empty($roleFilter)): ?>
                    <a href="users.php" class="btn btn-secondary">
                        ✖️ Tozalash
                    </a>
                <?php endif; ?>
            </form>
        </div>
    </div>
    
    <!-- Users Table -->
    <div class="card">
        <div class="card-header">
            <h3 class="card-title">Foydalanuvchilar Ro'yxati</h3>
            <span class="badge badge-info"><?= number_format($totalUsers) ?> ta foydalanuvchi</span>
        </div>
        <div class="card-body">
            <div class="table-responsive">
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Ism</th>
                            <th>Telefon</th>
                            <th>Email</th>
                            <th>Rol</th>
                            <th>Holat</th>
                            <th>Buyurtmalar</th>
                            <th>Balans</th>
                            <th>Oxirgi kirish</th>
                            <th>Amallar</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($users as $user): ?>
                        <tr>
                            <td>#<?= $user['id'] ?></td>
                            <td><strong><?= htmlspecialchars($user['full_name']) ?></strong></td>
                            <td><?= htmlspecialchars($user['phone']) ?></td>
                            <td><?= htmlspecialchars($user['email'] ?? '-') ?></td>
                            <td>
                                <?php
                                $roleClass = [
                                    'client' => 'info',
                                    'owner' => 'warning',
                                    'admin' => 'danger'
                                ][$user['role']] ?? 'secondary';

                                $roleLabel = [
                                    'client' => 'Mijoz',
                                    'owner' => 'Egasi',
                                    'admin' => 'Admin'
                                ][$user['role']] ?? ucfirst($user['role'] ?? '');
                                ?>
                                <span class="badge badge-<?= $roleClass ?>">
                                    <?= $roleLabel ?>
                                </span>
                            </td>
                            <td>
                                <?php if ($user['is_blocked']): ?>
                                    <span class="badge badge-danger">Bloklangan</span>
                                    <?php if (!empty($user['blocked_reason'])): ?>
                                        <br><small class="text-muted"><?= htmlspecialchars($user['blocked_reason']) ?></small>
                                    <?php endif; ?>
                                <?php elseif ($user['is_frozen']): ?>
                                    <span class="badge badge-warning">Muzlatilgan</span>
                                    <br><small class="text-muted">faqat ko'radi</small>
                                <?php else: ?>
                                    <span class="badge badge-success">Faol</span>
                                <?php endif; ?>
                            </td>
                            <td><?= number_format($user['orders_count']) ?></td>
                            <td><?= number_format($user['balance'] ?? 0, 0) ?> so'm</td>
                            <td>
                                <?php if (!empty($user['last_login_at'])): ?>
                                    <?= formatDate($user['last_login_at'], 'd.m.Y H:i') ?>
                                <?php else: ?>
                                    <small class="text-muted">hech qachon</small>
                                <?php endif; ?>
                                <br><small class="text-muted">ro'yxat: <?= formatDate($user['created_at'], 'd.m.Y') ?></small>
                            </td>
                            <td style="white-space: nowrap;">
                                <?php if ($user['role'] !== 'admin'): ?>
                                    <button type="button" class="btn btn-sm btn-secondary"
                                            onclick="document.getElementById('u<?= $user['id'] ?>').classList.toggle('hidden')">
                                        ⚙️ Boshqarish
                                    </button>
                                    <form method="POST" action="" style="display: inline;"
                                          onsubmit="return confirm('Bu foydalanuvchini butunlay o\'chirmoqchimisiz? Qaytarib bo\'lmaydi.');">
                                        <input type="hidden" name="action" value="delete">
                                        <input type="hidden" name="user_id" value="<?= $user['id'] ?>">
                                        <button type="submit" class="btn btn-sm btn-danger">🗑️</button>
                                    </form>
                                <?php else: ?>
                                    <small class="text-muted">admin</small>
                                <?php endif; ?>
                            </td>
                        </tr>
                        <?php if ($user['role'] !== 'admin'): ?>
                        <tr id="u<?= $user['id'] ?>" class="hidden">
                            <td colspan="10" style="background: #fafafa;">
                                <div style="display: flex; flex-wrap: wrap; gap: 22px; padding: 14px 6px;">

                                    <form method="POST" style="display: flex; gap: 6px; align-items: flex-end;">
                                        <input type="hidden" name="user_id" value="<?= $user['id'] ?>">
                                        <?php if ($user['is_blocked']): ?>
                                            <input type="hidden" name="action" value="unblock">
                                            <button class="btn btn-sm btn-success">🔓 Blokni ochish</button>
                                        <?php else: ?>
                                            <input type="hidden" name="action" value="block">
                                            <div>
                                                <label style="font-size:12px;">Blok sababi</label>
                                                <input type="text" name="reason" placeholder="ixtiyoriy"
                                                       style="max-width:190px;">
                                            </div>
                                            <button class="btn btn-sm btn-danger">🚫 Bloklash</button>
                                        <?php endif; ?>
                                    </form>

                                    <form method="POST" style="display: flex; gap: 6px; align-items: flex-end;">
                                        <input type="hidden" name="user_id" value="<?= $user['id'] ?>">
                                        <?php if ($user['is_frozen']): ?>
                                            <input type="hidden" name="action" value="unfreeze">
                                            <button class="btn btn-sm btn-success">▶️ Muzlatishni olish</button>
                                        <?php else: ?>
                                            <input type="hidden" name="action" value="freeze">
                                            <button class="btn btn-sm btn-warning">❄️ Muzlatish</button>
                                        <?php endif; ?>
                                    </form>

                                    <form method="POST" style="display: flex; gap: 6px; align-items: flex-end;">
                                        <input type="hidden" name="user_id" value="<?= $user['id'] ?>">
                                        <input type="hidden" name="action" value="set_role">
                                        <div>
                                            <label style="font-size:12px;">Rol</label>
                                            <select name="role">
                                                <option value="client" <?= $user['role']==='client'?'selected':'' ?>>Mijoz</option>
                                                <option value="owner" <?= $user['role']==='owner'?'selected':'' ?>>Egasi</option>
                                            </select>
                                        </div>
                                        <button class="btn btn-sm btn-primary">Saqlash</button>
                                    </form>

                                    <form method="POST" style="display: flex; gap: 6px; align-items: flex-end;">
                                        <input type="hidden" name="user_id" value="<?= $user['id'] ?>">
                                        <input type="hidden" name="action" value="set_phone">
                                        <div>
                                            <label style="font-size:12px;">Telefon</label>
                                            <input type="text" name="phone" value="<?= htmlspecialchars($user['phone']) ?>"
                                                   style="max-width:160px;">
                                        </div>
                                        <button class="btn btn-sm btn-primary">Saqlash</button>
                                    </form>

                                    <form method="POST" style="display: flex; gap: 6px; align-items: flex-end;">
                                        <input type="hidden" name="user_id" value="<?= $user['id'] ?>">
                                        <input type="hidden" name="action" value="set_password">
                                        <div>
                                            <label style="font-size:12px;">Yangi parol</label>
                                            <input type="text" name="password" placeholder="kamida 6 belgi"
                                                   style="max-width:170px;">
                                        </div>
                                        <button class="btn btn-sm btn-primary">O'rnatish</button>
                                    </form>

                                </div>
                                <div style="padding: 0 6px 12px; font-size: 12px; color: #777;">
                                    Parolni ko'rsatib bo'lmaydi — u shifrlangan holda saqlanadi.
                                    Yangisini o'rnating va foydalanuvchiga o'zingiz ayting.
                                </div>
                            </td>
                        </tr>
                        <?php endif; ?>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>

            <!-- Pagination -->
            <?php if ($totalPages > 1): ?>
                <div class="pagination">
                    <?php if ($page > 1): ?>
                        <a href="?page=<?= $page - 1 ?><?= $roleFilter ? '&role=' . $roleFilter : '' ?><?= $searchQuery ? '&search=' . urlencode($searchQuery) : '' ?>">
                            ← Oldingi
                        </a>
                    <?php endif; ?>

                    <?php for ($i = max(1, $page - 2); $i <= min($totalPages, $page + 2); $i++): ?>
                        <?php if ($i === $page): ?>
                            <span class="active"><?= $i ?></span>
                        <?php else: ?>
                            <a href="?page=<?= $i ?><?= $roleFilter ? '&role=' . $roleFilter : '' ?><?= $searchQuery ? '&search=' . urlencode($searchQuery) : '' ?>">
                                <?= $i ?>
                            </a>
                        <?php endif; ?>
                    <?php endfor; ?>

                    <?php if ($page < $totalPages): ?>
                        <a href="?page=<?= $page + 1 ?><?= $roleFilter ? '&role=' . $roleFilter : '' ?><?= $searchQuery ? '&search=' . urlencode($searchQuery) : '' ?>">
                            Keyingi →
                        </a>
                    <?php endif; ?>
                </div>
            <?php endif; ?>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>

