<?php
/**
 * 00 · Kirish (Figma «Admin panel» L1–L7).
 *
 * Ikki bosqich: telefon + parol → SMS kod (Eskiz, ilova kirish kodi bilan
 * bir xil tasdiqlangan shablon). «Qurilmani 30 kun eslab qolish» — shu
 * brauzerda SMS bosqichi o'tkazib yuboriladi (cookie + admin_trusted_devices).
 *
 * 5 xato (parol yoki kod) / 15 daqiqa — blok, IP va brauzer jurnalga
 * yoziladi. Kod: 6 xona, 5 daqiqa, 3 urinish, kuniga 5 SMS.
 * Parolni tiklash — telefon orqali SMS (email yo'q). Javob akkaunt bor-
 * yo'qligini oshkor qilmaydi.
 * Ro'yxatdan o'tish yo'q — faqat taklif (invite.php).
 */
require_once 'config.php';

startAdminSession();

if (isAdminLoggedIn()) {
    header('Location: index.php');
    exit;
}

$view = 'password';
$error = '';
$errorSub = '';
$info = '';
$fieldError = '';
$lock = null;
$pending = $_SESSION['login_pending'] ?? null;
$loginVal = '';

if (isset($_GET['expired'])) $info = '30 daqiqa faolsizlik sababli tizimdan chiqdingiz. Davom etish uchun qayta kiring.';
if (isset($_GET['invited'])) $info = 'Akkaunt yaratildi. Endi telefon va parol bilan kiring — SMS kod keladi.';
if (isset($_GET['disabled'])) $error = 'Akkauntingiz o\'chirilgan. Super adminga murojaat qiling.';
if (isset($_GET['forgot'])) { $view = 'forgot'; unset($_SESSION['login_pending']); $pending = null; }
if (isset($_GET['restart'])) { unset($_SESSION['login_pending']); $pending = null; }
if ($pending && !isset($_GET['forgot']) && !isset($_GET['restart'])) {
    $view = $pending['purpose'] === 'reset' ? 'reset_code' : 'code';
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $step = $_POST['step'] ?? 'password';
    if (!verifyCsrfToken($_POST['csrf_token'] ?? '')) {
        $error = 'Sahifa eskirgan, qaytadan kiriting';
        $view = 'password';
        unset($_SESSION['login_pending']);
        $pending = null;
    } elseif ($step === 'password') {
        $login = normalizeAdminLogin((string) ($_POST['phone'] ?? ''));
        $loginVal = $login;
        $password = (string) ($_POST['password'] ?? '');
        $lock = $login !== '' ? loginLockState($login) : null;
        if ($login === '' || $password === '') {
            $error = 'Telefon raqam va parol kiritilishi shart';
        } elseif ($lock['locked']) {
            $view = 'locked';
        } else {
            $u = findAdmin($login);
            $ok = $u && !$u['admin_disabled_at'] && password_verify($password, (string) $u['password_hash']);
            recordLoginAttempt($login, $u['id'] ?? null, 'password', (bool) $ok);
            if (!$ok) {
                $lock = loginLockState($login);
                if ($lock['locked']) {
                    $view = 'locked';
                    auditLog('login_locked', 'admin', $u['id'] ?? null, ['login' => $login], $u['id'] ?? null);
                } else {
                    $left = LOGIN_MAX_FAILS - $lock['fails'];
                    $error = "Login yoki parol noto'g'ri";
                    $errorSub = "Yana $left marta xato kiritilsa, akkaunt " . LOGIN_LOCK_MINUTES . ' daqiqaga bloklanadi.';
                    $fieldError = "$left ta urinish qoldi";
                }
            } elseif (trustedDeviceValid((int) $u['id']) || ADMIN_SMS_2FA_OFF) {
                // ADMIN_SMS_2FA=false (backend/.env) — favqulodda: Eskiz ishlamasa
                // adminlar panelsiz qolmasin. Kirish jurnalda belgilanadi.
                recordLoginAttempt($login, (int) $u['id'], 'sms', true);
                completeAdminLogin($u, true);
                header('Location: index.php');
                exit;
            } else {
                $s = sendAdminOtp($u, 'login');
                if (!$s['ok']) {
                    $error = $s['error'];
                } else {
                    $_SESSION['login_pending'] = ['user_id' => (int) $u['id'], 'login' => $login, 'purpose' => 'login',
                                                  'remember' => !empty($_POST['remember']), 'test_code' => $s['test_code'] ?? null];
                    header('Location: login.php');
                    exit;
                }
            }
        }
    } elseif ($step === 'code' && $pending && $pending['purpose'] === 'login') {
        $lock = loginLockState($pending['login']);
        if ($lock['locked']) {
            $view = 'locked';
            unset($_SESSION['login_pending']);
        } else {
            $r = verifyAdminOtp($pending['user_id'], 'login', (string) ($_POST['code'] ?? ''));
            recordLoginAttempt($pending['login'], $pending['user_id'], 'sms', $r['ok']);
            if ($r['ok']) {
                $u = findAdmin($pending['login']);
                if (!$u || $u['admin_disabled_at']) {
                    unset($_SESSION['login_pending']);
                    $error = 'Akkaunt topilmadi yoki o\'chirilgan';
                    $view = 'password';
                } else {
                    if (!empty($pending['remember'])) rememberDevice((int) $u['id']);
                    completeAdminLogin($u, false);
                    header('Location: index.php');
                    exit;
                }
            } else {
                $lock = loginLockState($pending['login']);
                if ($lock['locked']) {
                    $view = 'locked';
                    unset($_SESSION['login_pending']);
                    auditLog('login_locked', 'admin', $pending['user_id'], ['login' => $pending['login'], 'stage' => 'sms'], $pending['user_id']);
                } else {
                    $view = 'code';
                    $error = $r['left'] > 0
                        ? "Kod noto'g'ri yoki muddati tugagan (" . OTP_TTL_MINUTES . " daqiqa). {$r['left']} ta urinish qoldi."
                        : "Kod noto'g'ri yoki muddati tugagan. Yangi kod so'rang.";
                }
            }
        }
    } elseif ($step === 'resend' && $pending) {
        $view = $pending['purpose'] === 'reset' ? 'reset_code' : 'code';
        $last = lastOtpAt($pending['user_id'], $pending['purpose']);
        if ($last !== null && time() - $last < OTP_RESEND_SECONDS) {
            $error = 'Yangi kodni ' . (OTP_RESEND_SECONDS - (time() - $last)) . ' soniyadan keyin so\'rash mumkin';
        } else {
            $u = findAdmin($pending['login']);
            $s = $u ? sendAdminOtp($u, $pending['purpose']) : ['ok' => true];
            if ($s['ok']) {
                $_SESSION['login_pending']['test_code'] = $s['test_code'] ?? null;
                $info = 'Yangi kod yuborildi';
            } else {
                $error = $s['error'];
            }
        }
    } elseif ($step === 'forgot') {
        $login = normalizeAdminLogin((string) ($_POST['phone'] ?? ''));
        $u = $login !== '' ? findAdmin($login) : null;
        $test = null;
        if ($u && !$u['admin_disabled_at']) {
            $s = sendAdminOtp($u, 'reset');
            $test = $s['test_code'] ?? null;
            recordLoginAttempt($login, (int) $u['id'], 'reset', $s['ok']);
        }
        // Javob har doim bir xil — raqam ro'yxatda bormi, bilinmaydi.
        $_SESSION['login_pending'] = ['user_id' => (int) ($u['id'] ?? 0), 'login' => $login, 'purpose' => 'reset',
                                      'remember' => false, 'test_code' => $test];
        header('Location: login.php?sent=1');
        exit;
    } elseif ($step === 'reset' && $pending && $pending['purpose'] === 'reset') {
        $view = 'reset_code';
        $p1 = (string) ($_POST['new_password'] ?? '');
        $p2 = (string) ($_POST['new_password2'] ?? '');
        $u = $pending['user_id'] ? findAdmin($pending['login']) : null;
        if (!passwordOk($p1, $u['password_hash'] ?? null)) {
            $error = 'Parol talablarga javob bermaydi';
        } elseif ($p1 !== $p2) {
            $error = 'Takroriy parol mos kelmadi';
            $fieldError = 'Parollar mos emas';
        } else {
            $r = $u ? verifyAdminOtp((int) $u['id'], 'reset', (string) ($_POST['code'] ?? '')) : ['ok' => false, 'left' => 0];
            if (!$r['ok']) {
                $error = $r['left'] > 0 ? "Kod noto'g'ri. {$r['left']} ta urinish qoldi." : "Kod noto'g'ri yoki muddati tugagan. Yangi kod so'rang.";
                if ($u) recordLoginAttempt($pending['login'], (int) $u['id'], 'reset', false);
            } else {
                getDbConnection()->prepare('UPDATE users SET password_hash = ?, updated_at = NOW() WHERE id = ?')
                    ->execute([password_hash($p1, PASSWORD_BCRYPT), $u['id']]);
                // Parol almashdi — eski «eslab qolingan» qurilmalar ham bekor.
                getDbConnection()->prepare('DELETE FROM admin_trusted_devices WHERE user_id = ?')->execute([$u['id']]);
                auditLog('admin_password_reset', 'admin', $u['id'], [], (int) $u['id']);
                unset($_SESSION['login_pending']);
                $view = 'password';
                $info = 'Parol yangilandi. Yangi parol bilan kiring.';
                $loginVal = $pending['login'];
            }
        }
    }
    $pending = $_SESSION['login_pending'] ?? null;
}

$csrf = generateCsrfToken();
$testCode = $pending['test_code'] ?? null;
$resendIn = 0;
if ($pending && $pending['user_id']) {
    $last = lastOtpAt($pending['user_id'], $pending['purpose']);
    if ($last !== null) $resendIn = max(0, OTP_RESEND_SECONDS - (time() - $last));
}
$smsLeft = $pending && $pending['user_id'] ? max(0, OTP_DAILY_LIMIT - otpSentToday($pending['user_id'])) : null;
$maskedPhone = $pending ? maskAdminPhone($pending['login']) : '';
?>
<!DOCTYPE html>
<html lang="uz">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kirish · MoveX GO Admin</title>
    <link rel="icon" type="image/png" href="assets/favicon.png">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap">
    <link rel="stylesheet" href="assets/css/style.css?v=<?= @filemtime(__DIR__ . '/assets/css/style.css') ?>">
</head>
<body class="auth-page">
<div class="auth">
    <aside class="auth-brand">
        <div class="auth-logo">
            <span class="auth-logo-mark"><i data-lucide="navigation"></i></span>
            <b>MoveX GO</b><span class="auth-tag">Admin</span>
        </div>
        <div class="auth-pitch">
            <h1>Buyurtmalar, haydovchilar va to'lovlar — bitta panelda</h1>
            <p>Faqat taklif qilingan xodimlar uchun. Har bir harakat audit jurnaliga yoziladi.</p>
            <small>v1.0 · © <?= date('Y') ?> MoveX GO</small>
        </div>
    </aside>
    <main class="auth-main">
        <div class="auth-card">
        <?php if ($view === 'locked' && $lock): ?>
            <div class="auth-icon danger"><i data-lucide="lock"></i></div>
            <h2>Akkaunt vaqtincha bloklandi</h2>
            <p class="auth-sub"><?= LOGIN_MAX_FAILS ?> marta noto'g'ri urinish. <?= $lock['until']->format('H:i') ?> dan keyin qayta urinib ko'ring.</p>
            <div class="auth-timer"><b class="num" data-until="<?= $lock['until']->getTimestamp() ?>" id="lockLeft">—</b><span>Qolgan vaqt</span></div>
            <div class="auth-banner info">
                <i data-lucide="info"></i>
                <div><b>Bu siz emasmisiz?</b>
                    <span>Hodisa audit jurnaliga yozildi (IP <?= htmlspecialchars($lock['ip'] ?: '—') ?>, <?= htmlspecialchars(uaShort($lock['ua'])) ?>). Parolni almashtirishni tavsiya qilamiz.</span></div>
            </div>
            <a class="btn btn-secondary btn-block btn-lg" href="login.php?forgot=1">Parolni tiklash</a>
        <?php elseif ($view === 'code'): ?>
            <h2>SMS kodni kiriting</h2>
            <p class="auth-sub"><?= htmlspecialchars($maskedPhone) ?> raqamiga 6 xonali kod yubordik</p>
            <?php if ($error): ?><div class="auth-error-line"><?= htmlspecialchars($error) ?></div><?php endif; ?>
            <?php if ($info): ?><div class="auth-banner ok"><i data-lucide="check-circle"></i><div><b><?= htmlspecialchars($info) ?></b></div></div><?php endif; ?>
            <?php if ($testCode): ?><div class="auth-banner warn"><i data-lucide="flask-conical"></i><div><b>Sinov rejimi</b><span>SMS yuborilmadi. Kod: <b class="num"><?= htmlspecialchars($testCode) ?></b></span></div></div><?php endif; ?>
            <form method="post" class="auth-form" id="codeForm">
                <input type="hidden" name="csrf_token" value="<?= $csrf ?>">
                <input type="hidden" name="step" value="code">
                <input type="hidden" name="code" id="codeValue">
                <div class="otp<?= $error ? ' error' : '' ?>" id="otp">
                    <?php for ($i = 0; $i < 6; $i++): ?><input inputmode="numeric" autocomplete="<?= $i === 0 ? 'one-time-code' : 'off' ?>" aria-label="Kod <?= $i + 1 ?>-raqami"><?php endfor; ?>
                </div>
                <div class="auth-meta"><i data-lucide="clock"></i><span id="resendLabel" data-left="<?= $resendIn ?>">Qayta yuborish: 0:<?= str_pad((string) $resendIn, 2, '0', STR_PAD_LEFT) ?></span></div>
                <button class="btn btn-primary btn-block btn-lg" type="submit">Tasdiqlash</button>
            </form>
            <form method="post" id="resendForm" class="auth-resend">
                <input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="step" value="resend">
                <button type="submit" class="link-btn" id="resendBtn" <?= $resendIn ? 'disabled' : '' ?>>Kodni qayta yuborish</button>
                · <a href="login.php?restart=1">Boshqa akkaunt</a>
            </form>
            <p class="auth-note"><i data-lucide="info"></i><span><?= $smsLeft !== null ? "Kunlik SMS limiti: " . OTP_DAILY_LIMIT . " ta. Qolgan: $smsLeft ta. " : '' ?>Raqam o'zgarganmi? Super adminga murojaat qiling — raqamni faqat u almashtira oladi.</span></p>
        <?php elseif ($view === 'forgot'): ?>
            <a class="auth-back" href="login.php?restart=1">← Kirishga qaytish</a>
            <h2>Parolni tiklash</h2>
            <p class="auth-sub">Admin telefon raqamingizni kiriting — SMS kod keladi</p>
            <form method="post" class="auth-form">
                <input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="step" value="forgot">
                <label class="fl"><span>Telefon</span><input name="phone" inputmode="tel" placeholder="+998 90 123 45 67" required autofocus></label>
                <button class="btn btn-primary btn-block btn-lg" type="submit">Kod yuborish</button>
            </form>
            <p class="auth-note"><i data-lucide="info"></i><span>Akkaunt borligi oshkor qilinmaydi — javob har doim bir xil.</span></p>
        <?php elseif ($view === 'reset_code'): ?>
            <a class="auth-back" href="login.php?restart=1">← Kirishga qaytish</a>
            <h2>Yangi parol o'rnating</h2>
            <?php if (isset($_GET['sent'])): ?>
                <div class="auth-banner ok"><i data-lucide="check-circle"></i><div><b>Kod yuborildi</b><span>Agar bu raqam ro'yxatda bo'lsa, SMS kod keladi. Kod <?= OTP_TTL_MINUTES ?> daqiqa va bir marta amal qiladi.</span></div></div>
            <?php endif; ?>
            <?php if ($testCode): ?><div class="auth-banner warn"><i data-lucide="flask-conical"></i><div><b>Sinov rejimi</b><span>SMS yuborilmadi. Kod: <b class="num"><?= htmlspecialchars($testCode) ?></b></span></div></div><?php endif; ?>
            <?php if ($error): ?><div class="auth-banner danger"><i data-lucide="alert-triangle"></i><div><b><?= htmlspecialchars($error) ?></b></div></div><?php endif; ?>
            <?php if ($info): ?><div class="auth-banner ok"><i data-lucide="check-circle"></i><div><b><?= htmlspecialchars($info) ?></b></div></div><?php endif; ?>
            <form method="post" class="auth-form" id="resetForm">
                <input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="step" value="reset">
                <label class="fl"><span>SMS kod</span><input name="code" inputmode="numeric" maxlength="6" autocomplete="one-time-code" required></label>
                <label class="fl"><span>Yangi parol</span><input type="password" name="new_password" id="np1" autocomplete="new-password" required></label>
                <ul class="pw-rules" id="pwRules">
                    <?php foreach (passwordRules('') as [$t]): ?><li><i data-lucide="circle"></i><?= htmlspecialchars($t) ?></li><?php endforeach; ?>
                </ul>
                <label class="fl<?= $fieldError ? ' error' : '' ?>"><span>Parolni takrorlang</span><input type="password" name="new_password2" id="np2" autocomplete="new-password" required>
                    <?php if ($fieldError): ?><em><?= htmlspecialchars($fieldError) ?></em><?php endif; ?></label>
                <button class="btn btn-primary btn-block btn-lg" type="submit">Parolni saqlash</button>
            </form>
            <form method="post" class="auth-resend"><input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="step" value="resend">
                <button type="submit" class="link-btn" <?= $resendIn ? 'disabled' : '' ?>>Kodni qayta yuborish</button></form>
        <?php else: ?>
            <h2>Admin panelga kirish</h2>
            <p class="auth-sub">Telefon raqam va parolingizni kiriting</p>
            <?php if ($error): ?>
                <div class="auth-banner danger"><i data-lucide="alert-triangle"></i><div><b><?= htmlspecialchars($error) ?></b><?php if ($errorSub): ?><span><?= htmlspecialchars($errorSub) ?></span><?php endif; ?></div></div>
            <?php endif; ?>
            <?php if ($info): ?><div class="auth-banner info"><i data-lucide="info"></i><div><b><?= htmlspecialchars($info) ?></b></div></div><?php endif; ?>
            <form method="post" class="auth-form">
                <input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="step" value="password">
                <label class="fl"><span>Telefon</span><input name="phone" inputmode="tel" placeholder="+998 90 123 45 67" value="<?= htmlspecialchars($loginVal) ?>" required <?= $loginVal ? '' : 'autofocus' ?>></label>
                <label class="fl<?= $fieldError ? ' error' : '' ?>"><span>Parol</span><input type="password" name="password" id="pw" autocomplete="current-password" required <?= $loginVal ? 'autofocus' : '' ?>>
                    <em id="pwHint"><?= htmlspecialchars($fieldError) ?></em></label>
                <div class="auth-row">
                    <?php if (!ADMIN_SMS_2FA_OFF): ?><label class="check"><input type="checkbox" name="remember" value="1"> Qurilmani <?= TRUST_DAYS ?> kun eslab qolish</label><?php else: ?><span></span><?php endif; ?>
                    <a href="login.php?forgot=1">Parolni unutdingizmi?</a>
                </div>
                <button class="btn btn-primary btn-block btn-lg" type="submit">Kirish</button>
            </form>
            <p class="auth-note"><i data-lucide="shield"></i><span><?= ADMIN_SMS_2FA_OFF ? '' : 'Kirish 2 bosqichli: parol + SMS kod. ' ?>Ro'yxatdan o'tish yo'q — faqat taklif orqali. 5 ta xato urinish — 15 daqiqa blok.</span></p>
        <?php endif; ?>
        </div>
    </main>
</div>
<script src="assets/js/lucide.min.js"></script>
<script>
lucide.createIcons();
// Caps Lock ogohlantirishi (L2)
const pw = document.getElementById('pw'), hint = document.getElementById('pwHint');
if (pw && hint) {
    const base = hint.textContent;
    pw.addEventListener('keyup', e => {
        const caps = e.getModifierState && e.getModifierState('CapsLock');
        hint.textContent = [base, caps ? 'Caps Lock yoqilgan' : ''].filter(Boolean).join(' · ');
        pw.parentElement.classList.toggle('warn', !!caps && !base);
    });
}
// 6 xonali kod: avtofokus, keyingisiga o'tish, joylashtirish (L3)
const otp = document.getElementById('otp');
if (otp) {
    const cells = [...otp.querySelectorAll('input')], val = document.getElementById('codeValue');
    const sync = () => { val.value = cells.map(c => c.value).join(''); if (val.value.length === 6) document.getElementById('codeForm').submit(); };
    cells.forEach((c, i) => {
        c.addEventListener('input', () => {
            const d = c.value.replace(/\D/g, '');
            if (d.length > 1) { d.split('').slice(0, 6 - i).forEach((x, k) => cells[i + k].value = x); cells[Math.min(5, i + d.length)].focus(); }
            else { c.value = d; if (d && i < 5) cells[i + 1].focus(); }
            sync();
        });
        c.addEventListener('keydown', e => { if (e.key === 'Backspace' && !c.value && i > 0) cells[i - 1].focus(); });
    });
    cells[0].focus();
}
// Qayta yuborish taymeri
const rl = document.getElementById('resendLabel'), rb = document.getElementById('resendBtn');
if (rl) {
    let left = +rl.dataset.left;
    const tick = () => {
        rl.textContent = left > 0 ? 'Qayta yuborish: 0:' + String(left).padStart(2, '0') : 'Kodni qayta yuborish mumkin';
        if (rb) rb.disabled = left > 0;
        if (left-- > 0) setTimeout(tick, 1000);
    };
    tick();
}
// Blok taymeri (L5)
const ll = document.getElementById('lockLeft');
if (ll) {
    const until = +ll.dataset.until * 1000;
    const tick = () => {
        const s = Math.max(0, Math.round((until - Date.now()) / 1000));
        ll.textContent = Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0');
        if (s > 0) setTimeout(tick, 1000); else location.href = 'login.php';
    };
    tick();
}
// Parol talablari (L7)
const np1 = document.getElementById('np1');
if (np1) {
    const rules = [...document.querySelectorAll('#pwRules li')];
    const checks = [v => v.length >= 12, v => /\p{Lu}/u.test(v) && /\p{Ll}/u.test(v), v => /[\d\W_]/u.test(v), () => true];
    np1.addEventListener('input', () => rules.forEach((li, i) => li.classList.toggle('ok', np1.value !== '' && checks[i](np1.value))));
}
</script>
</body>
</html>
