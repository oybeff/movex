<?php
/**
 * Shikoyatlar (mijoz ilovasi B5 «Muammo bor»).
 *
 * Panel pulni O'ZI harakatlantirmaydi: payouts.php kabi backend'ning ichki
 * manziliga murojaat qiladi (/orders/internal/problems/{id}/resolve), pul
 * mantig'i bitta joyda — order_service.
 *   complete — ish qabul qilindi, pul texnika egasiga;
 *   cancel   — buyurtma bekor, pul mijozga qaytadi;
 *   close    — servisdan tashqarida hal bo'ldi, pul qimirlamaydi.
 */
require_once 'config.php';
requireAdmin();
requireCsrfToken();

$pageTitle = 'Shikoyatlar';
$currentPage = 'problems';
$db = getDbConnection();
$message = '';
$messageType = 'success';

$reasons = [
    'not_arrived' => 'Texnika kelmadi',
    'wrong_equipment' => 'Boshqa texnika keldi',
    'poor_quality' => 'Ish sifatsiz',
    'price_differs' => 'Narx boshqacha',
    'other' => 'Boshqa',
];
$actions = [
    'complete' => 'Ish qabul qilindi — pul texnika egasiga o\'tdi',
    'cancel' => 'Buyurtma bekor qilindi — pul mijozga qaytdi',
    'close' => 'Shikoyat yopildi, pul harakatlanmadi',
];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $id = (int) ($_POST['problem_id'] ?? 0);
    $action = $_POST['action'] ?? '';
    if ($id <= 0 || !isset($actions[$action])) {
        $message = 'Noto\'g\'ri so\'rov';
        $messageType = 'error';
    } else {
        $r = internalApiPost("/orders/internal/problems/$id/resolve", ['action' => $action]);
        $message = $r['ok'] ? "#$id: " . $actions[$action] : "#$id: " . $r['error'];
        $messageType = $r['ok'] ? 'success' : 'error';
    }
}

$status = ($_GET['status'] ?? 'open') === 'resolved' ? 'resolved' : 'open';
$stmt = $db->prepare("
    SELECT p.id, p.order_id, p.reason, p.comment, p.photos, p.status, p.created_at,
           o.status AS order_status, o.total_amount, o.payment_method, o.finished_at,
           c.full_name AS client_name, c.phone AS client_phone,
           ow.full_name AS owner_name, ow.phone AS owner_phone, e.model
    FROM order_problems p
    JOIN orders o ON o.id = p.order_id
    JOIN users c ON c.id = o.user_id
    LEFT JOIN equipment e ON e.id = o.equipment_id
    LEFT JOIN users ow ON ow.id = e.owner_id
    WHERE p.status = ?
    ORDER BY p.created_at DESC
    LIMIT 200
");
$stmt->execute([$status]);
$rows = $stmt->fetchAll();
$openCount = (int) $db->query("SELECT COUNT(*) FROM order_problems WHERE status = 'open'")->fetchColumn();

$payNames = ['cash' => 'Naqd', 'card' => 'Karta', 'balance' => 'Balans'];

include 'includes/header.php';
?>

<div class="content">
    <?php if ($message): ?>
        <div class="alert alert-<?= $messageType === 'success' ? 'success' : 'error' ?>">
            <?= htmlspecialchars($message) ?>
        </div>
    <?php endif; ?>

    <div class="card mb-3">
        <div class="card-body d-flex gap-2" style="align-items:center; flex-wrap:wrap;">
            <a href="?status=open" class="btn <?= $status === 'open' ? 'btn-primary' : '' ?>">Ochiq (<?= $openCount ?>)</a>
            <a href="?status=resolved" class="btn <?= $status === 'resolved' ? 'btn-primary' : '' ?>">Ko'rib chiqilgan</a>
            <span style="color:#6b7280; font-size:13px;">
                Shikoyat bor buyurtma avtomatik tasdiqlanmaydi — pul siz qaror qilguningizcha muzlatilgan turadi.
            </span>
        </div>
    </div>

    <div class="card">
        <div class="card-body" style="overflow-x:auto;">
            <?php if (!$rows): ?>
                <p style="color:#6b7280;">Shikoyat yo'q.</p>
            <?php else: ?>
            <table>
                <thead>
                    <tr>
                        <th>#</th>
                        <th>Buyurtma</th>
                        <th>Mijoz</th>
                        <th>Texnika egasi</th>
                        <th>Sabab</th>
                        <th>Rasmlar</th>
                        <th>Sana</th>
                        <th>Amal</th>
                    </tr>
                </thead>
                <tbody>
                <?php foreach ($rows as $r):
                    $photos = json_decode($r['photos'] ?? '[]', true) ?: [];
                    $active = $r['order_status'] === 'confirmed';
                ?>
                    <tr>
                        <td><?= (int) $r['id'] ?></td>
                        <td>
                            #<?= (int) $r['order_id'] ?> · <?= htmlspecialchars($r['model'] ?? '') ?><br>
                            <b><?= number_format((float) $r['total_amount'], 0, '.', ' ') ?> so'm</b>
                            · <?= $payNames[$r['payment_method']] ?? htmlspecialchars($r['payment_method']) ?><br>
                            <small><?= htmlspecialchars($r['order_status']) ?><?= $r['finished_at'] ? ' · ish tugagan' : '' ?></small>
                        </td>
                        <td><?= htmlspecialchars($r['client_name'] ?? '') ?><br><small>+<?= htmlspecialchars($r['client_phone'] ?? '') ?></small></td>
                        <td><?= htmlspecialchars($r['owner_name'] ?? '') ?><br><small>+<?= htmlspecialchars($r['owner_phone'] ?? '') ?></small></td>
                        <td>
                            <b><?= htmlspecialchars($reasons[$r['reason']] ?? $r['reason']) ?></b>
                            <?php if ($r['comment']): ?><br><small><?= nl2br(htmlspecialchars($r['comment'])) ?></small><?php endif; ?>
                        </td>
                        <td>
                            <?php foreach ($photos as $ph): if (!is_string($ph) || strpos($ph, '/static/problems/') !== 0) continue; ?>
                                <a href="<?= htmlspecialchars($ph) ?>" target="_blank" rel="noopener">
                                    <img src="<?= htmlspecialchars($ph) ?>" alt="" style="width:48px;height:48px;object-fit:cover;border-radius:6px;">
                                </a>
                            <?php endforeach; ?>
                        </td>
                        <td><?= htmlspecialchars(formatDate($r['created_at'], 'd.m.Y H:i')) ?></td>
                        <td>
                            <?php if ($r['status'] === 'open'): ?>
                            <form method="POST" class="d-flex gap-2" style="flex-wrap:wrap;"
                                  onsubmit="return confirm('Tasdiqlaysizmi? Pul harakati qaytarilmaydi.');">
                                <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
                                <input type="hidden" name="problem_id" value="<?= (int) $r['id'] ?>">
                                <?php if ($active): ?>
                                    <button name="action" value="cancel" class="btn btn-danger">Bekor — pulni mijozga</button>
                                    <button name="action" value="complete" class="btn btn-success">Qabul — pul egasiga</button>
                                <?php endif; ?>
                                <button name="action" value="close" class="btn">Yopish</button>
                            </form>
                            <?php else: ?>
                                Ko'rib chiqilgan
                            <?php endif; ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
            <?php endif; ?>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>
