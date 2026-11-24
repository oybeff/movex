<?php
/**
 * Haydovchilar hujjatlari — MoveX GO Driver ilovasidan yuklangan pasport,
 * guvohnoma, texpasport va texnika surati. Har birini tasdiqlash yoki
 * sababi bilan rad etish.
 *
 * Rasmlar ochiq /static da EMAS (pasport ma'lumotlari): ular backend
 * ichki manzilidan X-Admin-Secret bilan olinadi va shu sahifa orqali
 * ko'rsatiladi (?file=ID). Panel bazaga yozmaydi — holatni backend
 * o'zgartiradi (driver_service.review).
 */
require_once 'config.php';
requireAdmin();
requireCsrfToken();

// Rasmni proksi qilish: <img src="drivers.php?file=12">
if (isset($_GET['file'])) {
    $id = (int) $_GET['file'];
    $res = internalApiGet('/drivers/internal/documents/' . $id . '/file', true);
    if (!$res['ok']) {
        http_response_code(404);
        exit;
    }
    header('Content-Type: ' . ($res['type'] ?: 'image/jpeg'));
    header('Cache-Control: private, no-store');
    echo $res['data'];
    exit;
}

$message = '';
$messageType = 'success';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $docId = (int) ($_POST['doc_id'] ?? 0);
    $approve = ($_POST['action'] ?? '') === 'approve';
    $reason = trim((string) ($_POST['reason'] ?? ''));
    if (!$approve && $reason === '') {
        $message = "Rad etish sababini yozing — haydovchi uni ilovada ko'radi";
        $messageType = 'error';
    } else {
        $res = internalApiPost('/drivers/internal/documents/' . $docId . '/review', [
            'approve' => $approve,
            'reason' => $approve ? null : $reason,
        ]);
        if ($res['ok']) {
            $message = $approve ? 'Hujjat tasdiqlandi' : 'Hujjat rad etildi';
        } else {
            $message = 'Xato: ' . $res['error'];
            $messageType = 'error';
        }
    }
}

$queue = internalApiGet('/drivers/internal/queue');
$drivers = $queue['ok'] && is_array($queue['data']) ? $queue['data'] : [];

$kindNames = [
    'id_front' => 'ID karta — old',
    'id_back' => 'ID karta — orqa',
    'license_front' => 'Haydovchilik guvohnomasi — old',
    'license_back' => 'Haydovchilik guvohnomasi — orqa',
    'tech_front' => 'Texpasport — old',
    'tech_back' => 'Texpasport — orqa',
    'car_front' => 'Mashina — old',
    'car_back' => 'Mashina — orqa',
    'car_left' => 'Mashina — chap',
    'car_right' => "Mashina — o'ng",
    'passport' => 'Pasport (ID karta)',
    'driver_license' => 'Haydovchilik guvohnomasi',
    'tech_passport' => 'Texnika texpasporti',
    'equipment_photo' => 'Texnika surati',
    'insurance' => "Sug'urta polisi",
];
$statusBadge = [
    'pending' => ['warning', 'Tekshirilmoqda'],
    'approved' => ['success', 'Tasdiqlangan'],
    'rejected' => ['danger', 'Rad etilgan'],
    'incomplete' => ['secondary', "To'liq emas"],
];

$pageTitle = 'Haydovchilar hujjatlari';
$currentPage = 'drivers';
include 'includes/header.php';
?>

<div class="content">
    <?php if ($message): ?>
        <div class="alert alert-<?= $messageType === 'success' ? 'success' : 'error' ?>"><?= htmlspecialchars($message) ?></div>
    <?php endif; ?>
    <?php if (!$queue['ok']): ?>
        <div class="alert alert-error">Ro'yxat olinmadi: <?= htmlspecialchars($queue['error']) ?></div>
    <?php endif; ?>

    <div class="alert alert-info">
        Haydovchi ilovada <strong>ishga chiqishi</strong> uchun 4 ta majburiy hujjat tasdiqlangan bo'lishi kerak:
        pasport, guvohnoma, texpasport va texnika surati. Sug'urta — ixtiyoriy.
        Rad etsangiz, sababini yozing: haydovchi uni ko'rib, hujjatni qayta yuklaydi.
    </div>

    <?php if (!$drivers): ?>
        <div class="card"><div class="card-body">Hali hujjat yuklagan haydovchi yo'q.</div></div>
    <?php endif; ?>

    <?php foreach ($drivers as $d): ?>
        <?php [$cls, $label] = $statusBadge[$d['status']] ?? ['secondary', $d['status']]; ?>
        <div class="card mb-3">
            <div class="card-header" style="display:flex;justify-content:space-between;align-items:center;">
                <h3 class="card-title">
                    <?= htmlspecialchars($d['full_name'] ?? '') ?>
                    <small class="text-muted">· <?= htmlspecialchars($d['phone'] ?? '') ?> · #<?= (int) $d['user_id'] ?></small>
                </h3>
                <span class="badge badge-<?= $cls ?>"><?= $label ?></span>
            </div>
            <div class="card-body" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:16px;">
                <?php foreach ($d['documents'] as $doc): ?>
                    <?php [$dcls, $dlabel] = $statusBadge[$doc['status']] ?? ['secondary', $doc['status']]; ?>
                    <div style="border:1px solid #e5e9ee;border-radius:12px;padding:12px;">
                        <div style="display:flex;justify-content:space-between;margin-bottom:8px;">
                            <strong><?= htmlspecialchars($kindNames[$doc['kind']] ?? $doc['kind']) ?></strong>
                            <span class="badge badge-<?= $dcls ?>"><?= $dlabel ?></span>
                        </div>
                        <a href="drivers.php?file=<?= (int) $doc['id'] ?>" target="_blank" rel="noopener">
                            <img src="drivers.php?file=<?= (int) $doc['id'] ?>" alt=""
                                 style="width:100%;height:150px;object-fit:cover;border-radius:8px;background:#f1f3f7;">
                        </a>
                        <?php if ($doc['status'] === 'rejected' && $doc['reject_reason']): ?>
                            <div class="text-muted" style="margin-top:6px;">Sabab: <?= htmlspecialchars($doc['reject_reason']) ?></div>
                        <?php endif; ?>
                        <?php if ($doc['status'] === 'pending'): ?>
                            <form method="POST" style="margin-top:8px;">
                                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                <input type="hidden" name="doc_id" value="<?= (int) $doc['id'] ?>">
                                <button type="submit" name="action" value="approve" class="btn btn-success btn-sm">✅ Tasdiqlash</button>
                            </form>
                            <form method="POST" style="margin-top:6px;display:flex;gap:6px;">
                                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                <input type="hidden" name="doc_id" value="<?= (int) $doc['id'] ?>">
                                <input type="text" name="reason" placeholder="Rad etish sababi" class="form-control" style="flex:1;" required>
                                <button type="submit" name="action" value="reject" class="btn btn-danger btn-sm">Rad etish</button>
                            </form>
                        <?php endif; ?>
                    </div>
                <?php endforeach; ?>
            </div>
        </div>
    <?php endforeach; ?>
</div>

<?php include 'includes/footer.php'; ?>
