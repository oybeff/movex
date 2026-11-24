<?php
/**
 * S7 · Rollar matritsasi (Figma «Admin panel» 09).
 *
 * 4 rol × 14 ruxsat: to'liq / faqat ko'rish / yo'q. Super admin ustuni
 * qulflangan (hamma narsa). «Adminlar va rollar» ruxsati faqat super
 * adminda qoladi: aks holda operator o'zini super admin qilib olardi.
 * Saqlanadi: app_settings.admin_role_permissions; o'zgarish audit
 * jurnaliga eski/yangi qiymat bilan yoziladi (S10 da farq ko'rinadi).
 */
require_once 'config.php';
requireAdmin();
requirePagePerm('admins');
requireCsrfToken();

$db = getDbConnection();
$pageTitle = 'Sozlamalar / Rollar';
$currentPage = 'admins';
const LOCKED_PERMS = ['admins'];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $before = rolePermissions();
    $new = [];
    $changes = [];
    foreach (defaultRolePermissions() as $role => $perms) {
        foreach ($perms as $p => $def) {
            $v = $_POST['perm'][$role][$p] ?? $before[$role][$p];
            if (!in_array($v, ['full', 'view', 'none'], true) || in_array($p, LOCKED_PERMS, true)) $v = 'none';
            $new[$role][$p] = $v;
            if ($v !== $before[$role][$p]) {
                $changes[] = [ADMIN_ROLES[$role] . ': ' . ADMIN_PERMS[$p], $before[$role][$p], $v];
            }
        }
    }
    if ($changes) {
        $json = json_encode($new);
        $up = $db->prepare("UPDATE app_settings SET value = ?::json, updated_at = NOW() WHERE key = 'admin_role_permissions'");
        $up->execute([$json]);
        if ($up->rowCount() === 0) {
            $db->prepare("INSERT INTO app_settings (key, value, description) VALUES ('admin_role_permissions', ?::json, 'Admin panel rollari ruxsatlari (roles.php)')")
               ->execute([$json]);
        }
        $lbl = ['full' => "To'liq", 'view' => "Ko'rish", 'none' => "Yo'q"];
        auditLog('roles_changed', 'settings', null, [
            'before' => array_combine(array_column($changes, 0), array_map(fn($c) => $lbl[$c[1]], $changes)),
            'after' => array_combine(array_column($changes, 0), array_map(fn($c) => $lbl[$c[2]], $changes)),
        ]);
        $_SESSION['toast'] = ['success', count($changes) . " ta ruxsat o'zgardi. Adminlarda keyingi bosishdan kuchga kiradi."];
    } else {
        $_SESSION['toast'] = ['info', "O'zgarish yo'q"];
    }
    header('Location: roles.php');
    exit;
}

$m = rolePermissions();
$roles = array_keys(ADMIN_ROLES);
$counts = [];
foreach ($db->query("SELECT COALESCE(admin_role,'super_admin') r, COUNT(*) c FROM users WHERE role='admin' AND admin_disabled_at IS NULL GROUP BY 1") as $r) {
    $counts[$r['r']] = (int) $r['c'];
}
include 'includes/header.php';
?>
<div class="content">
    <form method="post" id="rolesForm" data-dirty-guard>
    <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
    <div class="page-head">
        <div style="display:flex;gap:16px;align-items:center">
            <a class="icon-btn back" href="admins.php" aria-label="Orqaga" style="border:1px solid var(--border)"><i data-lucide="chevron-left"></i></a>
            <div><h2>Rollar va ruxsatlar</h2><div class="sub">Har bir rol nimani ko'ra va qila oladi</div></div>
        </div>
        <div class="page-actions"><button class="btn btn-primary" type="submit" id="saveRoles" disabled>Saqlash</button></div>
    </div>

    <div class="card">
        <div class="table-responsive"><table class="perm-matrix">
            <thead><tr><th>Ruxsat</th>
                <?php foreach ($roles as $r): ?><th><?= strtoupper(ADMIN_ROLES[$r]) ?><small class="sub" style="font-weight:400;text-transform:none"><?= $counts[$r] ?? 0 ?> ta admin</small></th><?php endforeach; ?></tr></thead>
            <tbody>
            <?php foreach (ADMIN_PERMS as $p => $label): ?>
                <tr><td><?= htmlspecialchars($label) ?></td>
                    <?php foreach ($roles as $r):
                        $lvl = $r === 'super_admin' ? 'full' : $m[$r][$p]; ?>
                        <td>
                        <?php if ($r === 'super_admin' || in_array($p, LOCKED_PERMS, true)): ?>
                            <span class="perm-fixed <?= $lvl ?>" title="<?= $r === 'super_admin' ? 'Super admin ruxsatlari tahrirlanmaydi' : 'Faqat super admin' ?>">
                                <?= $lvl === 'view' ? "Ko'rish" : '<i data-lucide="' . ($lvl === 'full' ? 'check-circle-2' : 'x') . '"></i>' ?></span>
                        <?php else: ?>
                            <span class="perm-cell" role="radiogroup" aria-label="<?= htmlspecialchars(ADMIN_ROLES[$r] . ' — ' . $label) ?>">
                                <?php foreach (['full' => ['check', "To'liq"], 'view' => ['eye', "Faqat ko'rish"], 'none' => ['x', "Yo'q"]] as $v => [$ic, $t]): ?>
                                    <label title="<?= $t ?>"><input type="radio" name="perm[<?= $r ?>][<?= $p ?>]" value="<?= $v ?>" <?= $lvl === $v ? 'checked' : '' ?>><span class="<?= $v ?>"><i data-lucide="<?= $ic ?>"></i></span></label>
                                <?php endforeach; ?>
                            </span>
                        <?php endif; ?>
                        </td>
                    <?php endforeach; ?>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table></div>
    </div>
    </form>
    <div class="banner banner-info" style="margin-top:16px">
        <i data-lucide="info"></i>
        <div><b>Ikkinchi tasdiq (4 ko'z) yoqilmagan</b>
            <span>Katta qaytarish va pul yechishni bitta admin tasdiqlaydi — egasining qarori. Katta summalar ro'yxatlarda qizil bilan ajratiladi. Har bir harakat audit jurnalida.</span></div>
    </div>
</div>
<script>
document.getElementById('rolesForm').addEventListener('change', () => document.getElementById('saveRoles').disabled = false);
</script>
<?php include 'includes/footer.php'; ?>
