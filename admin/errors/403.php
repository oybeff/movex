<?php
/** E2 · 403 — rolga ruxsat berilmagan bo'lim (requirePerm). */
$perm = $GLOBALS['deniedPerm'] ?? '';
$need = $GLOBALS['deniedNeed'] ?? 'view';
$pageTitle = $pageTitle ?? 'Ruxsat yo\'q';
$who = rolesWith($perm, $need);
require_once __DIR__ . '/../includes/header.php';
?>
<div class="content">
    <div class="card"><div class="card-body">
        <div class="state-page">
            <div class="state-icon warn"><i data-lucide="lock"></i></div>
            <h2><?= $need === 'full' ? 'Bu amalga ruxsatingiz yo\'q' : 'Bu bo\'limga ruxsatingiz yo\'q' ?></h2>
            <p>«<?= htmlspecialchars(ADMIN_PERMS[$perm] ?? $perm) ?>» faqat
                <?= htmlspecialchars(implode(', ', array_map(fn($r) => "«{$r}»", $who))) ?> rollariga ochiq.
                Sizning rolingiz: <b><?= htmlspecialchars(ADMIN_ROLES[currentAdminRole()]) ?></b>.</p>
            <div class="state-actions">
                <a class="btn btn-primary" href="index.php"><i data-lucide="layout-dashboard"></i> Dashboardga</a>
                <a class="btn btn-secondary" href="javascript:history.back()">Orqaga</a>
            </div>
            <p class="state-hint">Ruxsat kerak bo'lsa — super adminga murojaat qiling.</p>
        </div>
    </div></div>
</div>
<?php require_once __DIR__ . '/../includes/footer.php'; ?>
