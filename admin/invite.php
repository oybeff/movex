<?php
/**
 * Taklifni qabul qilish (S8 → L7). Havola: invite.php?t=<token>, 48 soat,
 * bir marta. Avval SMS kod (raqam haqiqatan shu odamniki), keyin parol.
 * Akkaunt shu yerda yaratiladi — ro'yxatdan o'tish sahifasi yo'q.
 */
require_once 'config.php';
startAdminSession();

$db = getDbConnection();
$tok = (string) ($_GET['t'] ?? ($_POST['t'] ?? ''));
$inv = null;
if (preg_match('/^[a-f0-9]{48}$/', $tok)) {
    $st = $db->prepare("SELECT * FROM admin_invites WHERE token_hash = ? AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > NOW()");
    $st->execute([hash('sha256', $tok)]);
    $inv = $st->fetch() ?: null;
}

$error = '';
$testCode = null;
$step = 'start';
$sessKey = 'invite_' . substr(hash('sha256', $tok), 0, 16);
$state = $_SESSION[$sessKey] ?? null;

// Raqam tasdiqlanmaguncha akkaunt yaratilmaydi, shuning uchun kod admin_otp
// da emas (u users ga bog'langan), sessiyada xeshlangan holda turadi.
if ($inv && $_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!verifyCsrfToken($_POST['csrf_token'] ?? '')) {
        $error = 'Sahifa eskirgan, qaytadan urinib ko\'ring';
    } elseif (($_POST['step'] ?? '') === 'send') {
        if ($state && time() - $state['sent'] < OTP_RESEND_SECONDS) {
            $error = 'Yangi kodni ' . (OTP_RESEND_SECONDS - (time() - $state['sent'])) . ' soniyadan keyin so\'rash mumkin';
        } elseif ($state && $state['count'] >= OTP_DAILY_LIMIT) {
            $error = 'SMS limiti tugadi. Taklif qilgan admindan yangi havola so\'rang.';
        } else {
            $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
            $r = internalApiPost('/admin-p5/internal/sms-code', ['phone' => $inv['phone'], 'code' => $code]);
            if (!$r['ok']) {
                $error = 'SMS yuborilmadi: ' . $r['error'];
            } else {
                $_SESSION[$sessKey] = ['hash' => password_hash($code, PASSWORD_DEFAULT), 'sent' => time(), 'tries' => 0,
                                       'count' => ($state['count'] ?? 0) + 1, 'ok' => false, 'test' => $r['data']['test_code'] ?? null];
            }
        }
    } elseif (($_POST['step'] ?? '') === 'code' && $state) {
        $c = preg_replace('/\D/', '', (string) ($_POST['code'] ?? ''));
        if (time() - $state['sent'] > OTP_TTL_MINUTES * 60 || $state['tries'] >= OTP_MAX_ATTEMPTS) {
            $error = 'Kod muddati tugagan. Yangi kod so\'rang.';
        } elseif (!password_verify($c, $state['hash'])) {
            $_SESSION[$sessKey]['tries']++;
            $error = "Kod noto'g'ri. " . max(0, OTP_MAX_ATTEMPTS - $_SESSION[$sessKey]['tries']) . ' ta urinish qoldi.';
        } else {
            $_SESSION[$sessKey]['ok'] = true;
        }
    } elseif (($_POST['step'] ?? '') === 'password' && !empty($state['ok'])) {
        $p1 = (string) ($_POST['new_password'] ?? '');
        $p2 = (string) ($_POST['new_password2'] ?? '');
        if (!passwordOk($p1)) {
            $error = 'Parol talablarga javob bermaydi';
        } elseif ($p1 !== $p2) {
            $error = 'Takroriy parol mos kelmadi';
        } else {
            $ex = $db->prepare('SELECT 1 FROM users WHERE phone = ?');
            $ex->execute([$inv['phone']]);
            if ($ex->fetchColumn()) {
                $error = 'Bu raqam allaqachon ro\'yxatda. Taklif qilgan adminga murojaat qiling.';
            } else {
                $db->beginTransaction();
                $ins = $db->prepare("INSERT INTO users (full_name, phone, password_hash, role, admin_role, language,
                                     search_radius_km, is_blocked, is_frozen, created_at, updated_at)
                                     VALUES (?, ?, ?, 'admin', ?, 'uz', 50, false, false, NOW(), NOW()) RETURNING id");
                $ins->execute([$inv['full_name'], $inv['phone'], password_hash($p1, PASSWORD_BCRYPT), $inv['admin_role']]);
                $uid = (int) $ins->fetchColumn();
                $db->prepare('UPDATE admin_invites SET accepted_at = NOW() WHERE id = ?')->execute([$inv['id']]);
                $db->commit();
                auditLog('admin_invite_accepted', 'admin', $uid, ['name' => $inv['full_name'], 'role' => $inv['admin_role']], $uid);
                unset($_SESSION[$sessKey]);
                header('Location: login.php?invited=1');
                exit;
            }
        }
    }
    $state = $_SESSION[$sessKey] ?? null;
}
if ($state) {
    $step = !empty($state['ok']) ? 'password' : 'code';
    $testCode = $state['test'] ?? null;
}
$csrf = generateCsrfToken();
?>
<!DOCTYPE html>
<html lang="uz">
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Taklif · MoveX GO Admin</title>
    <link rel="icon" type="image/png" href="assets/favicon.png">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap">
    <link rel="stylesheet" href="assets/css/style.css?v=<?= @filemtime(__DIR__ . '/assets/css/style.css') ?>">
</head>
<body class="auth-page">
<div class="auth">
    <aside class="auth-brand">
        <div class="auth-logo"><span class="auth-logo-mark"><i data-lucide="navigation"></i></span><b>MoveX GO</b><span class="auth-tag">Admin</span></div>
        <div class="auth-pitch"><h1>Jamoaga xush kelibsiz</h1>
            <p>Raqamingizni tasdiqlang va parol o'rnating. Keyin har kirishda parol + SMS kod so'raladi.</p>
            <small>v1.0 · © <?= date('Y') ?> MoveX GO</small></div>
    </aside>
    <main class="auth-main"><div class="auth-card">
    <?php if (!$inv): ?>
        <div class="auth-icon danger"><i data-lucide="link-2-off"></i></div>
        <h2>Havola yaroqsiz</h2>
        <p class="auth-sub">Taklif muddati (48 soat) tugagan, bekor qilingan yoki allaqachon ishlatilgan. Taklif qilgan admindan yangi havola so'rang.</p>
        <a class="btn btn-secondary btn-block btn-lg" href="login.php">Kirish sahifasi</a>
    <?php else: ?>
        <h2><?= $step === 'password' ? "Parol o'rnating" : 'Taklifni qabul qilish' ?></h2>
        <p class="auth-sub"><?= htmlspecialchars($inv['full_name']) ?> · <b><?= ADMIN_ROLES[$inv['admin_role']] ?></b> · <?= htmlspecialchars(maskAdminPhone($inv['phone'])) ?></p>
        <?php if ($error): ?><div class="auth-banner danger"><i data-lucide="alert-triangle"></i><div><b><?= htmlspecialchars($error) ?></b></div></div><?php endif; ?>
        <?php if ($testCode && $step === 'code'): ?><div class="auth-banner warn"><i data-lucide="flask-conical"></i><div><b>Sinov rejimi</b><span>SMS yuborilmadi. Kod: <b class="num"><?= htmlspecialchars($testCode) ?></b></span></div></div><?php endif; ?>
        <?php if ($step === 'start'): ?>
            <form method="post" class="auth-form"><input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="t" value="<?= htmlspecialchars($tok) ?>">
                <input type="hidden" name="step" value="send">
                <button class="btn btn-primary btn-block btn-lg">SMS kod olish</button></form>
        <?php elseif ($step === 'code'): ?>
            <form method="post" class="auth-form"><input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="t" value="<?= htmlspecialchars($tok) ?>">
                <input type="hidden" name="step" value="code">
                <label class="fl"><span>SMS kod (6 xona)</span><input name="code" inputmode="numeric" maxlength="6" autocomplete="one-time-code" required autofocus></label>
                <button class="btn btn-primary btn-block btn-lg">Tasdiqlash</button></form>
            <form method="post" class="auth-resend"><input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="t" value="<?= htmlspecialchars($tok) ?>">
                <input type="hidden" name="step" value="send"><button class="link-btn">Kodni qayta yuborish</button></form>
        <?php else: ?>
            <form method="post" class="auth-form"><input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="t" value="<?= htmlspecialchars($tok) ?>">
                <input type="hidden" name="step" value="password">
                <label class="fl"><span>Yangi parol</span><input type="password" name="new_password" id="np1" autocomplete="new-password" required autofocus></label>
                <ul class="pw-rules" id="pwRules"><?php foreach (array_slice(passwordRules(''), 0, 3) as [$t]): ?><li><i data-lucide="circle"></i><?= htmlspecialchars($t) ?></li><?php endforeach; ?></ul>
                <label class="fl"><span>Parolni takrorlang</span><input type="password" name="new_password2" autocomplete="new-password" required></label>
                <button class="btn btn-primary btn-block btn-lg">Saqlash va kirish</button></form>
        <?php endif; ?>
    <?php endif; ?>
    </div></main>
</div>
<script src="assets/js/lucide.min.js"></script>
<script>
lucide.createIcons();
const np1 = document.getElementById('np1');
if (np1) {
    const rules = [...document.querySelectorAll('#pwRules li')];
    const checks = [v => v.length >= 12, v => /\p{Lu}/u.test(v) && /\p{Ll}/u.test(v), v => /[\d\W_]/u.test(v)];
    np1.addEventListener('input', () => rules.forEach((li, i) => li.classList.toggle('ok', checks[i](np1.value))));
}
</script>
</body>
</html>
