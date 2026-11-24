<?php
/** E1 · 404 — mavjud bo'lmagan ID / eskirgan havola. $notFoundTitle, $notFoundText, $backHref */
http_response_code(404);
$pageTitle = $pageTitle ?? 'Topilmadi';
require_once __DIR__ . '/../includes/header.php';
?>
<div class="content">
    <div class="card"><div class="card-body">
        <div class="state-page">
            <div class="state-icon"><i data-lucide="search"></i></div>
            <h2><?= htmlspecialchars($notFoundTitle ?? 'Sahifa topilmadi') ?></h2>
            <p><?= htmlspecialchars($notFoundText ?? "Havola eskirgan yoki yozuv o'chirilgan. Havolani tekshiring.") ?></p>
            <div class="state-actions">
                <a class="btn btn-primary" href="<?= htmlspecialchars($backHref ?? 'index.php') ?>">Ro'yxatga qaytish</a>
                <a class="btn btn-secondary" href="index.php">Dashboard</a>
            </div>
        </div>
    </div></div>
</div>
<?php require_once __DIR__ . '/../includes/footer.php'; ?>
