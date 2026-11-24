<?php
/**
 * S6 · Adminlar, S8 · Admin taklif qilish (Figma «Admin panel» 09).
 *
 * Taklif — havola (48 soat, bir marta). Email yuborish yo'q: super admin
 * havolani o'zi yuboradi (Telegram va h.k.). Havolani ochgan odam SMS kod
 * bilan raqamini tasdiqlaydi va parol qo'yadi (invite.php).
 *
 * Qoidalar: o'z rolini o'zgartirib/o'chirib bo'lmaydi; oxirgi faol super
 * adminni o'chirib yoki rolini tushirib bo'lmaydi; super adminni faqat
 * super admin tayinlaydi (bu sahifa umuman super adminniki — «admins»
 * ruxsati boshqa rolga berilmaydi, roles.php da qulflangan).
 */
require_once 'config.php';
require_once 'includes/user_lib.php';
requireAdmin();
requirePagePerm('admins');
requireCsrfToken();

$db = getDbConnection();
$db->exec("SET TIME ZONE 'Asia/Tashkent'");
$me = (int) $_SESSION['admin_user_id'];
$pageTitle = 'Sozlamalar / Adminlar';
$currentPage = 'admins';

function activeSuperAdmins(PDO $db): int {
    return (int) $db->query("SELECT COUNT(*) FROM users WHERE role = 'admin' AND admin_disabled_at IS NULL
                             AND COALESCE(admin_role, 'super_admin') = 'super_admin'")->fetchColumn();
}

function toast(string $type, string $text): void {
    $_SESSION['toast'] = [$type, $text];
}

$newInviteLink = $_SESSION['invite_link'] ?? null;
unset($_SESSION['invite_link']);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $a = $_POST['action'] ?? '';
    $uid = (int) ($_POST['user_id'] ?? 0);
    $target = null;
    if ($uid) {
        $st = $db->prepare("SELECT id, full_name, phone, admin_role, admin_disabled_at FROM users WHERE id = ? AND role = 'admin'");
        $st->execute([$uid]);
        $target = $st->fetch() ?: null;
    }
    $isLastSuper = $target && ($target['admin_role'] ?: 'super_admin') === 'super_admin'
        && !$target['admin_disabled_at'] && activeSuperAdmins($db) <= 1;

    if ($a === 'invite') {
        $name = trim((string) ($_POST['full_name'] ?? ''));
        $phone = normalizeAdminLogin((string) ($_POST['phone'] ?? ''));
        $role = (string) ($_POST['admin_role'] ?? '');
        if ($name === '' || mb_strlen($name) > 120) {
            toast('error', 'Ism-familiya majburiy');
        } elseif (!preg_match('/^998\d{9}$/', $phone)) {
            toast('error', 'Telefon raqam noto\'g\'ri: +998 XX XXX XX XX');
        } elseif (!isset(ADMIN_ROLES[$role])) {
            toast('error', 'Rolni tanlang');
        } else {
            $ex = $db->prepare('SELECT role FROM users WHERE phone = ?');
            $ex->execute([$phone]);
            $exRole = $ex->fetchColumn();
            if ($exRole !== false) {
                toast('error', $exRole === 'admin' ? 'Bu raqam allaqachon admin'
                    : 'Bu raqam ilovada ro\'yxatdan o\'tgan (mijoz/haydovchi). Admin uchun boshqa raqam kerak.');
            } else {
                $db->prepare("UPDATE admin_invites SET revoked_at = NOW() WHERE phone = ? AND accepted_at IS NULL AND revoked_at IS NULL")
                   ->execute([$phone]);
                $tok = bin2hex(random_bytes(24));
                $db->prepare("INSERT INTO admin_invites (token_hash, phone, full_name, admin_role, invited_by, expires_at)
                              VALUES (?, ?, ?, ?, ?, NOW() + INTERVAL '48 hours') RETURNING id")
                   ->execute([hash('sha256', $tok), $phone, $name, $role, $me]);
                $iid = (int) $db->lastInsertId();
                auditLog('admin_invited', 'admin', $iid, ['phone' => $phone, 'name' => $name, 'role' => $role]);
                $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https' ? 'https' : 'http';
                $dir = rtrim(dirname($_SERVER['SCRIPT_NAME']), '/\\');
                $_SESSION['invite_link'] = $scheme . '://' . $_SERVER['HTTP_HOST'] . $dir . '/invite.php?t=' . $tok;
                toast('success', 'Taklif yaratildi — havolani nusxalab yuboring');
            }
        }
    } elseif ($a === 'revoke_invite') {
        $iid = (int) ($_POST['invite_id'] ?? 0);
        $db->prepare('UPDATE admin_invites SET revoked_at = NOW() WHERE id = ? AND accepted_at IS NULL')->execute([$iid]);
        auditLog('admin_invite_revoked', 'admin', $iid);
        toast('success', 'Taklif bekor qilindi');
    } elseif (!$target) {
        toast('error', 'Admin topilmadi');
    } elseif ($uid === $me) {
        toast('error', "O'zingizning rolingizni o'zgartira yoki o'chira olmaysiz");
    } elseif ($a === 'set_role') {
        $role = (string) ($_POST['admin_role'] ?? '');
        $old = $target['admin_role'] ?: 'super_admin';
        if (!isset(ADMIN_ROLES[$role])) {
            toast('error', 'Rol noto\'g\'ri');
        } elseif ($isLastSuper && $role !== 'super_admin') {
            toast('error', 'Oxirgi super adminning rolini tushirib bo\'lmaydi');
        } elseif ($role !== $old) {
            $db->prepare('UPDATE users SET admin_role = ? WHERE id = ?')->execute([$role, $uid]);
            auditLog('admin_role_changed', 'admin', $uid, ['name' => $target['full_name'],
                     'before' => ['Rol' => ADMIN_ROLES[$old]], 'after' => ['Rol' => ADMIN_ROLES[$role]]]);
            toast('success', $target['full_name'] . ' — endi ' . ADMIN_ROLES[$role]);
        }
    } elseif ($a === 'disable') {
        if ($isLastSuper) {
            toast('error', 'Oxirgi super adminni o\'chirib bo\'lmaydi');
        } else {
            $db->prepare('UPDATE users SET admin_disabled_at = NOW() WHERE id = ?')->execute([$uid]);
            $db->prepare('DELETE FROM admin_trusted_devices WHERE user_id = ?')->execute([$uid]);
            auditLog('admin_disabled', 'admin', $uid, ['name' => $target['full_name'], 'reason' => trim((string) ($_POST['reason'] ?? ''))]);
            toast('success', $target['full_name'] . ' — panelga kira olmaydi');
        }
    } elseif ($a === 'enable') {
        $db->prepare('UPDATE users SET admin_disabled_at = NULL WHERE id = ?')->execute([$uid]);
        auditLog('admin_enabled', 'admin', $uid, ['name' => $target['full_name']]);
        toast('success', $target['full_name'] . ' — qayta faol');
    } elseif ($a === 'forget_devices') {
        $db->prepare('DELETE FROM admin_trusted_devices WHERE user_id = ?')->execute([$uid]);
        auditLog('admin_devices_reset', 'admin', $uid, ['name' => $target['full_name']]);
        toast('success', 'Eslab qolingan qurilmalar o\'chirildi — keyingi kirishda SMS so\'raladi');
    }
    header('Location: admins.php');
    exit;
}

$admins = $db->query("
    SELECT u.id, u.full_name, u.phone, COALESCE(u.admin_role, 'super_admin') AS admin_role, u.admin_disabled_at,
           u.last_login_at,
           (SELECT ip FROM admin_login_attempts a WHERE a.user_id = u.id AND a.success AND a.stage = 'sms' ORDER BY a.id DESC LIMIT 1) AS last_ip,
           (SELECT user_agent FROM admin_login_attempts a WHERE a.user_id = u.id AND a.success AND a.stage = 'sms' ORDER BY a.id DESC LIMIT 1) AS last_ua,
           (SELECT COUNT(*) FROM admin_trusted_devices d WHERE d.user_id = u.id AND d.expires_at > NOW()) AS devices,
           (SELECT COUNT(*) FROM admin_login_attempts a WHERE a.user_id = u.id AND NOT a.success
                AND a.created_at > NOW() - INTERVAL '24 hours') AS fails24
    FROM users u WHERE u.role = 'admin'
    ORDER BY u.admin_disabled_at IS NOT NULL, CASE COALESCE(u.admin_role,'super_admin') WHEN 'super_admin' THEN 0 ELSE 1 END, u.full_name
")->fetchAll();
$invites = $db->query("SELECT i.*, x.full_name AS by_name, i.expires_at < NOW() AS expired FROM admin_invites i
                       LEFT JOIN users x ON x.id = i.invited_by
                       WHERE i.accepted_at IS NULL AND i.revoked_at IS NULL AND i.created_at > NOW() - INTERVAL '14 days'
                       ORDER BY i.id DESC")->fetchAll();
$supers = activeSuperAdmins($db);
$csrf = generateCsrfToken();
$roleBadge = ['super_admin' => 'dark', 'operator' => 'info', 'finance' => 'success', 'moderator' => 'warning', 'support' => 'secondary'];

include 'includes/header.php';
?>
<div class="content">
    <div class="page-head">
        <div>
            <h2>Adminlar va rollar</h2>
            <div class="sub"><?= count(array_filter($admins, fn($a) => !$a['admin_disabled_at'])) ?> ta faol admin · <?= count(ADMIN_ROLES) ?> ta rol</div>
        </div>
        <div class="page-actions">
            <a class="btn btn-secondary" href="roles.php"><i data-lucide="table-2"></i> Rollar matritsasi</a>
            <button class="btn btn-primary" type="button" data-open="modalInvite"><i data-lucide="user-plus"></i> Admin taklif qilish</button>
        </div>
    </div>

    <?php if ($newInviteLink): ?>
        <div class="banner banner-info" style="margin-bottom:16px">
            <i data-lucide="link"></i>
            <div style="flex:1;min-width:0"><b>Taklif havolasi (48 soat, bir marta)</b>
                <div class="copy-row"><input readonly value="<?= htmlspecialchars($newInviteLink) ?>" id="invLink" onclick="this.select()">
                    <button class="btn btn-secondary btn-sm" type="button" onclick="navigator.clipboard.writeText(document.getElementById('invLink').value);toastOk('Nusxalandi')"><i data-lucide="copy"></i> Nusxa</button></div>
                <small class="text-muted">Havola boshqa ko'rsatilmaydi. Yo'qolsa — taklifni bekor qilib, yangisini yarating.</small></div>
        </div>
    <?php endif; ?>

    <div class="card">
        <div class="card-header"><div class="card-title">Adminlar</div></div>
        <div class="table-responsive"><table>
            <thead><tr><th>Admin</th><th>Rol</th><th>2FA</th><th>Oxirgi kirish</th><th>Holat</th><th style="width:220px"></th></tr></thead>
            <tbody>
            <?php foreach ($admins as $a):
                $self = (int) $a['id'] === $me;
                $lastSuper = $a['admin_role'] === 'super_admin' && !$a['admin_disabled_at'] && $supers <= 1; ?>
                <tr class="<?= $a['admin_disabled_at'] ? 'row-muted' : '' ?>">
                    <td><div class="person" style="margin:0"><div class="user-avatar"><?= htmlspecialchars(initials($a['full_name'])) ?></div>
                        <div><b><?= htmlspecialchars($a['full_name']) ?><?= $self ? ' <span class="text-muted">(siz)</span>' : '' ?></b>
                            <small class="num"><?= htmlspecialchars(fmtPhone($a['phone'])) ?></small></div></div></td>
                    <td>
                        <?php if ($self || $a['admin_disabled_at']): ?>
                            <span class="badge badge-<?= $roleBadge[$a['admin_role']] ?>"><?= ADMIN_ROLES[$a['admin_role']] ?></span>
                        <?php else: ?>
                            <form method="post" class="inline-form">
                                <input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="action" value="set_role">
                                <input type="hidden" name="user_id" value="<?= (int) $a['id'] ?>">
                                <select name="admin_role" onchange="this.form.submit()" <?= $lastSuper ? 'disabled title="Oxirgi super admin"' : '' ?>>
                                    <?php foreach (ADMIN_ROLES as $k => $v): ?><option value="<?= $k ?>" <?= $k === $a['admin_role'] ? 'selected' : '' ?>><?= $v ?></option><?php endforeach; ?>
                                </select>
                            </form>
                        <?php endif; ?>
                    </td>
                    <td><span class="badge badge-success"><i data-lucide="shield-check"></i> SMS</span>
                        <?php if ($a['devices']): ?><small class="sub"><?= (int) $a['devices'] ?> ta eslab qolingan qurilma</small><?php endif; ?></td>
                    <td><?= $a['last_login_at'] ? lastSeenText($a['last_login_at']) : '<span class="text-muted">Kirmagan</span>' ?>
                        <?php if ($a['last_ua'] || $a['last_ip']): ?><small class="sub"><?= htmlspecialchars(uaShort($a['last_ua'])) ?> · <span class="num"><?= htmlspecialchars($a['last_ip'] ?: '—') ?></span></small><?php endif; ?>
                        <?php if ((int) $a['fails24'] >= 3): ?><small class="sub text-danger"><?= (int) $a['fails24'] ?> ta xato urinish (24 soat)</small><?php endif; ?></td>
                    <td><?= $a['admin_disabled_at'] ? '<span class="badge badge-secondary">Ishdan ketgan</span>' : '<span class="badge badge-success">Faol</span>' ?></td>
                    <td class="text-right">
                        <?php if (!$self): ?>
                            <form method="post" class="inline-form">
                                <input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="user_id" value="<?= (int) $a['id'] ?>">
                                <?php if ($a['admin_disabled_at']): ?>
                                    <button class="btn btn-secondary btn-sm" name="action" value="enable">Qayta faollashtirish</button>
                                <?php else: ?>
                                    <?php if ($a['devices']): ?><button class="btn btn-ghost btn-sm" name="action" value="forget_devices" title="Keyingi kirishda SMS so'raladi">Qurilmalarni unutish</button><?php endif; ?>
                                    <button class="btn btn-ghost btn-sm text-danger" name="action" value="disable" <?= $lastSuper ? 'disabled title="Oxirgi super admin"' : '' ?>
                                            data-confirm="<?= htmlspecialchars($a['full_name']) ?> panelga kira olmaydi. Davom etilsinmi?">O'chirish</button>
                                <?php endif; ?>
                            </form>
                        <?php endif; ?>
                    </td>
                </tr>
            <?php endforeach; ?>
            <?php foreach ($invites as $i): ?>
                <tr class="row-muted">
                    <td><div class="person" style="margin:0"><div class="user-avatar"><i data-lucide="mail"></i></div>
                        <div><b><?= htmlspecialchars($i['full_name']) ?></b><small class="num"><?= htmlspecialchars(fmtPhone($i['phone'])) ?></small></div></div></td>
                    <td><span class="badge badge-<?= $roleBadge[$i['admin_role']] ?>"><?= ADMIN_ROLES[$i['admin_role']] ?></span></td>
                    <td><span class="text-muted">—</span></td>
                    <td><span class="text-muted">Taklif <?= date('d.m H:i', strtotime($i['created_at'])) ?></span><small class="sub"><?= htmlspecialchars($i['by_name'] ?? '') ?></small></td>
                    <td><?= $i['expired'] ? '<span class="badge badge-danger">Muddati o\'tgan</span>' : '<span class="badge badge-warning">Taklif kutilmoqda</span>' ?></td>
                    <td class="text-right"><form method="post" class="inline-form">
                        <input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="invite_id" value="<?= (int) $i['id'] ?>">
                        <button class="btn btn-ghost btn-sm" name="action" value="revoke_invite">Bekor qilish</button></form></td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table></div>
    </div>

    <div class="banner banner-warn" style="margin-top:16px">
        <i data-lucide="alert-triangle"></i>
        <div><b>Kamida 1 ta faol super admin bo'lishi shart<?= $supers < 2 ? ' — hozir faqat ' . $supers . ' ta, ikkinchisini tayinlash tavsiya qilinadi' : '' ?></b>
            <span>Oxirgi super adminni o'chirib yoki rolini tushirib bo'lmaydi. O'zingizning rolingizni o'zgartira olmaysiz.</span></div>
    </div>
</div>

<!-- S8 · Admin taklif qilish -->
<div class="modal" id="modalInvite" role="dialog" aria-modal="true" aria-labelledby="invTitle">
    <form class="modal-content" method="post" style="max-width:520px">
        <input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="action" value="invite">
        <div class="modal-header"><div><div class="modal-title" id="invTitle">Admin taklif qilish</div>
            <div class="text-muted" style="font-size:12.5px">Taklif havolasi 48 soat va bir marta amal qiladi. Kirishda SMS kod shu raqamga keladi.</div></div>
            <button class="modal-close" type="button" data-close aria-label="Yopish">×</button></div>
        <div class="modal-body">
            <div class="form-group"><label for="invName">Ism-familiya</label><input id="invName" name="full_name" maxlength="120" required placeholder="Sardor Qodirov"></div>
            <div class="form-group"><label for="invPhone">Telefon</label><input id="invPhone" name="phone" inputmode="tel" required placeholder="+998 90 123 45 67">
                <div class="form-hint">Ilovada ro'yxatdan o'tmagan raqam bo'lishi kerak.</div></div>
            <div class="form-section" style="margin-top:6px">Rol</div>
            <?php foreach (ADMIN_ROLES as $k => $v): ?>
                <label class="choice"><input type="radio" name="admin_role" value="<?= $k ?>" <?= $k === 'operator' ? 'checked' : '' ?>>
                    <span><b><?= $v ?></b><small><?= htmlspecialchars(ADMIN_ROLE_HINTS[$k]) ?></small></span></label>
            <?php endforeach; ?>
        </div>
        <div class="modal-footer">
            <button class="btn btn-secondary" type="button" data-close>Bekor</button>
            <button class="btn btn-primary" type="submit"><i data-lucide="send"></i> Taklif yaratish</button>
        </div>
    </form>
</div>
<?php include 'includes/footer.php'; ?>
