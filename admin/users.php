<?php
require_once 'config.php';
requireAdmin();

$pageTitle = 'Foydalanuvchilar';
$currentPage = 'users';

$message = '';
$messageType = '';

// Handle user deletion
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'delete') {
    $userId = intval($_POST['user_id']);
    
    $db = getDbConnection();
    $user = $db->prepare("SELECT role FROM users WHERE id = ?");
    $user->execute([$userId]);
    $userData = $user->fetch();
    
    if ($userData && $userData['role'] !== 'admin') {
        $stmt = $db->prepare("DELETE FROM users WHERE id = ?");
        if ($stmt->execute([$userId])) {
            $message = 'Foydalanuvchi o\'chirildi!';
            $messageType = 'success';
        } else {
            $message = 'Xatolik yuz berdi!';
            $messageType = 'error';
        }
    } else {
        $message = 'Admin foydalanuvchini o\'chirish mumkin emas!';
        $messageType = 'error';
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
                            <th>Buyurtmalar</th>
                            <th>Balans</th>
                            <th>Ro'yxatdan o'tgan</th>
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
                            <td><?= number_format($user['orders_count']) ?></td>
                            <td><?= number_format($user['balance'] ?? 0, 0) ?> so'm</td>
                            <td><?= formatDate($user['created_at'], 'd.m.Y') ?></td>
                            <td>
                                <?php if ($user['role'] !== 'admin'): ?>
                                    <form method="POST" action="" style="display: inline;"
                                          onsubmit="return confirm('Bu foydalanuvchini o\'chirmoqchimisiz?');">
                                        <input type="hidden" name="action" value="delete">
                                        <input type="hidden" name="user_id" value="<?= $user['id'] ?>">
                                        <button type="submit" class="btn btn-sm btn-danger">
                                            🗑️
                                        </button>
                                    </form>
                                <?php endif; ?>
                            </td>
                        </tr>
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

