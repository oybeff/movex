<?php
/**
 * Admin P5 (Figma «Admin panel» 00, 09): rollar, ruxsatlar, 2FA, audit.
 *
 * Rollar besh: super_admin, operator, finance, moderator, support.
 * Ruxsat darajasi: full (ko'rish + amal), view (faqat ko'rish), none.
 * Super admin hamma narsaga ega va matritsada tahrirlanmaydi. Qolgan
 * rollar matritsasi app_settings.admin_role_permissions da (roles.php),
 * bo'lmasa — Figma S7 dagi standart.
 *
 * 4 ko'z (ikkinchi tasdiq) YO'Q — egasining qarori (P4). Shuning uchun
 * «Pul qaytarish ≤ / > 5 mln» bitta ruxsat: refund.
 */

const ADMIN_ROLES = [
    'super_admin' => 'Super admin',
    'operator'    => 'Operator',
    'finance'     => 'Moliya',
    'moderator'   => 'Moderator',
    'support'     => "Qo'llab-quvv.",
];

const ADMIN_ROLE_HINTS = [
    'super_admin' => 'Hamma bo\'limlar, adminlar va rollar',
    'operator'    => 'Buyurtmalar, mijozlar, haydovchilar, chat',
    'finance'     => "To'lovlar, pul yechish, qaytarish",
    'moderator'   => 'Hujjatlar, texnika, sharhlar',
    'support'     => 'Nizolar va yordam chatlari',
];

const ADMIN_PERMS = [
    'orders_view'   => "Buyurtmalarni ko'rish",
    'orders_manage' => 'Buyurtmani bekor qilish / qayta tayinlash',
    'refund'        => 'Pul qaytarish (nizoda)',
    'payouts'       => 'Pul yechishni tasdiqlash',
    'finance'       => "To'lovlar va eksport",
    'docs'          => 'Hujjatlarni tekshirish',
    'equipment'     => 'Texnika va sharhlar moderatsiyasi',
    'users_block'   => 'Foydalanuvchini bloklash va boshqarish',
    'disputes'      => 'Nizolarni hal qilish',
    'support'       => 'Support chat',
    'push'          => 'Push yuborish',
    'settings'      => 'Tariflar, limitlar, hududlar',
    'admins'        => 'Adminlar va rollar',
    'audit'         => 'Audit jurnali',
];

/** Figma S7 dagi standart matritsa. */
function defaultRolePermissions(): array {
    $none = array_fill_keys(array_keys(ADMIN_PERMS), 'none');
    return [
        'operator' => array_merge($none, [
            'orders_view' => 'full', 'orders_manage' => 'full', 'finance' => 'view', 'docs' => 'view',
            'equipment' => 'view', 'users_block' => 'full', 'disputes' => 'full', 'support' => 'full',
            'push' => 'full', 'audit' => 'view',
        ]),
        'finance' => array_merge($none, [
            'orders_view' => 'full', 'refund' => 'full', 'payouts' => 'full', 'finance' => 'full',
            'disputes' => 'view', 'audit' => 'view',
        ]),
        'moderator' => array_merge($none, [
            'orders_view' => 'full', 'docs' => 'full', 'equipment' => 'full', 'users_block' => 'full',
            'audit' => 'view',
        ]),
        'support' => array_merge($none, [
            'orders_view' => 'full', 'disputes' => 'full', 'support' => 'full',
        ]),
    ];
}

function rolePermissions(): array {
    static $m = null;
    if ($m !== null) return $m;
    $m = defaultRolePermissions();
    try {
        $raw = appSettingRaw(getDbConnection(), 'admin_role_permissions');
        if (is_array($raw)) {
            foreach ($m as $role => $perms) {
                foreach ($perms as $p => $lvl) {
                    $v = $raw[$role][$p] ?? null;
                    if (in_array($v, ['full', 'view', 'none'], true)) $m[$role][$p] = $v;
                }
            }
        }
    } catch (Throwable $e) {
        // jadval yo'q — standart
    }
    return $m;
}

/** app_settings dagi JSON qiymat, dekodlangan holda (massiv bo'lishi mumkin). */
function appSettingRaw(PDO $db, string $key) {
    $st = $db->prepare('SELECT value FROM app_settings WHERE key = ?');
    $st->execute([$key]);
    $v = $st->fetchColumn();
    if ($v === false || $v === null) return null;
    $d = json_decode((string) $v, true);
    return is_string($d) ? (json_decode($d, true) ?? $d) : $d;
}

function currentAdminRole(): string {
    $r = $_SESSION['admin_perm_role'] ?? 'super_admin';
    return isset(ADMIN_ROLES[$r]) ? $r : 'support';
}

function adminLevel(string $perm, ?string $role = null): string {
    $role = $role ?? currentAdminRole();
    if ($role === 'super_admin') return 'full';
    return rolePermissions()[$role][$perm] ?? 'none';
}

function adminCan(string $perm, string $need = 'view'): bool {
    $lvl = adminLevel($perm);
    return $need === 'view' ? $lvl !== 'none' : $lvl === 'full';
}

/** Ruxsat yo'q — E2 sahifasi (403). */
function requirePerm(string $perm, string $need = 'view'): void {
    if (adminCan($perm, $need)) return;
    http_response_code(403);
    $GLOBALS['deniedPerm'] = $perm;
    $GLOBALS['deniedNeed'] = $need;
    require __DIR__ . '/../errors/403.php';
    exit;
}

/** Sahifa ruxsati: GET — ko'rish, POST — to'liq. */
function requirePagePerm(string $perm): void {
    requirePerm($perm, $_SERVER['REQUEST_METHOD'] === 'POST' ? 'full' : 'view');
}

function rolesWith(string $perm, string $need = 'full'): array {
    $out = [];
    foreach (ADMIN_ROLES as $r => $label) {
        $lvl = adminLevel($perm, $r);
        if ($need === 'view' ? $lvl !== 'none' : $lvl === 'full') $out[] = $label;
    }
    return $out;
}

// ------------------------------------------------------------------ audit

function clientIp(): string {
    // nginx real IP ni X-Forwarded-For / X-Real-IP da beradi; birinchisi —
    // brauzer. Bu faqat jurnal uchun, ruxsat uchun emas.
    $xff = $_SERVER['HTTP_X_REAL_IP'] ?? ($_SERVER['HTTP_X_FORWARDED_FOR'] ?? '');
    if ($xff !== '') {
        $ip = trim(explode(',', $xff)[0]);
        if (filter_var($ip, FILTER_VALIDATE_IP)) return $ip;
    }
    return (string) ($_SERVER['REMOTE_ADDR'] ?? '');
}

function clientUa(): string {
    return mb_substr((string) ($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 300);
}

/** «Chrome · Windows» — UA dan qisqa nom. */
function uaShort(?string $ua): string {
    $ua = (string) $ua;
    if ($ua === '') return '—';
    $b = 'Brauzer';
    foreach (['Edg/' => 'Edge', 'OPR/' => 'Opera', 'YaBrowser' => 'Yandex', 'Firefox/' => 'Firefox',
              'Chrome/' => 'Chrome', 'Safari/' => 'Safari', 'curl/' => 'curl'] as $k => $v) {
        if (strpos($ua, $k) !== false) { $b = $v; break; }
    }
    $os = '';
    foreach (['Windows' => 'Windows', 'Android' => 'Android', 'iPhone' => 'iOS', 'iPad' => 'iOS',
              'Mac OS' => 'macOS', 'Linux' => 'Linux'] as $k => $v) {
        if (strpos($ua, $k) !== false) { $os = $v; break; }
    }
    return $os ? "$b · $os" : $b;
}

/**
 * Admin harakatini jurnalga yozish (S9). Jurnal faqat qo'shiladi:
 * panelda tahrirlash yoki o'chirish yo'q.
 *
 * $payload ichida 'before' va 'after' bo'lsa — S10 da farq ko'rinadi.
 */
function auditLog(string $action, string $entity, $entityId = null, array $payload = [], ?int $adminId = null): void {
    try {
        $adminId = $adminId ?? (int) ($_SESSION['admin_user_id'] ?? 0);
        getDbConnection()->prepare(
            'INSERT INTO admin_actions (admin_id, action, entity, entity_id, payload, ip, user_agent)
             VALUES (?, ?, ?, ?, ?::jsonb, ?, ?)'
        )->execute([$adminId ?: null, mb_substr($action, 0, 40), mb_substr($entity, 0, 20),
                    $entityId === null ? null : (int) $entityId,
                    json_encode($payload ?: new stdClass(), JSON_UNESCAPED_UNICODE), clientIp() ?: null, clientUa() ?: null]);
    } catch (Throwable $e) {
        error_log('auditLog: ' . $e->getMessage());
    }
}

/**
 * Backend ichki manzili admin_actions ga yozadi, lekin IP ni bilmaydi.
 * Chaqiruvdan keyin shu adminning so'nggi soniyalardagi IP siz yozuvlariga
 * IP va brauzer qo'yiladi (internalApiPost o'zi chaqiradi).
 */
function auditStampIp(int $adminId): void {
    if ($adminId <= 0) return;
    try {
        getDbConnection()->prepare(
            "UPDATE admin_actions SET ip = ?, user_agent = ?
             WHERE admin_id = ? AND ip IS NULL AND created_at > NOW() - INTERVAL '30 seconds'"
        )->execute([clientIp() ?: null, clientUa() ?: null, $adminId]);
    } catch (Throwable $e) {
        // jurnal ustunlari hali yo'q
    }
}

// ------------------------------------------------------------------ kirish

const LOGIN_MAX_FAILS = 5;
const LOGIN_LOCK_MINUTES = 15;
const OTP_TTL_MINUTES = 5;
const OTP_MAX_ATTEMPTS = 3;
const OTP_DAILY_LIMIT = 5;
const OTP_RESEND_SECONDS = 60;
const TRUST_COOKIE = 'movex_admin_trust';
const TRUST_DAYS = 30;
const IDLE_MINUTES = 30;
// SMS-kod bilan kirish egasining qarori bilan O'CHIRILGAN (25.11.2026): kirish —
// telefon + parol. Yoqish kerak bo'lsa: backend/.env da ADMIN_SMS_2FA=true.
define('ADMIN_SMS_2FA_OFF', strtolower((string) ($GLOBALS['movexEnv']['ADMIN_SMS_2FA'] ?? 'false')) !== 'true');

function normalizeAdminLogin(string $login): string {
    $login = trim($login);
    if (preg_match('/^[\d\s()+\-]+$/', $login)) {
        $login = preg_replace('/\D/', '', $login);
        if (strlen($login) === 9) $login = '998' . $login;
    }
    return mb_substr($login, 0, 50);
}

function findAdmin(string $login): ?array {
    $st = getDbConnection()->prepare(
        "SELECT id, full_name, phone, password_hash, role, admin_role, admin_disabled_at
         FROM users WHERE phone = ? AND role = 'admin'");
    $st->execute([$login]);
    $u = $st->fetch();
    return $u ?: null;
}

function recordLoginAttempt(string $login, ?int $userId, string $stage, bool $ok): void {
    getDbConnection()->prepare(
        'INSERT INTO admin_login_attempts (login, user_id, stage, success, ip, user_agent) VALUES (?, ?, ?, ?, ?, ?)'
    )->execute([$login, $userId, $stage, $ok ? 'true' : 'false', clientIp() ?: null, clientUa() ?: null]);
}

/**
 * Blok holati: oxirgi 15 daqiqada 5 xato (parol yoki SMS kod) —
 * oxirgi muvaffaqiyatli kirishdan keyingilari hisoblanadi.
 * Qaytaradi: ['locked' => bool, 'fails' => int, 'until' => DateTime|null, 'ip' => ?, 'ua' => ?]
 */
function loginLockState(string $login): array {
    $db = getDbConnection();
    $st = $db->prepare(
        "SELECT created_at, ip, user_agent FROM admin_login_attempts
         WHERE login = ? AND success = false AND stage IN ('password','sms')
           AND created_at > NOW() - make_interval(mins => ?)
           AND created_at > COALESCE((SELECT MAX(created_at) FROM admin_login_attempts
                                      WHERE login = ? AND success = true AND stage = 'sms'), 'epoch')
         ORDER BY created_at DESC");
    $st->execute([$login, LOGIN_LOCK_MINUTES, $login]);
    $rows = $st->fetchAll();
    $fails = count($rows);
    if ($fails < LOGIN_MAX_FAILS) {
        return ['locked' => false, 'fails' => $fails, 'until' => null, 'ip' => null, 'ua' => null];
    }
    $until = (new DateTime($rows[0]['created_at']))->modify('+' . LOGIN_LOCK_MINUTES . ' minutes');
    return ['locked' => $until > new DateTime(), 'fails' => $fails, 'until' => $until,
            'ip' => $rows[0]['ip'], 'ua' => $rows[0]['user_agent']];
}

function otpSentToday(int $userId): int {
    $st = getDbConnection()->prepare(
        "SELECT COUNT(*) FROM admin_otp WHERE user_id = ?
         AND (created_at AT TIME ZONE 'Asia/Tashkent')::date = (NOW() AT TIME ZONE 'Asia/Tashkent')::date");
    $st->execute([$userId]);
    return (int) $st->fetchColumn();
}

/**
 * Kod yaratib SMS yuboradi. Qaytaradi: ['ok' => bool, 'error' => string,
 * 'test_code' => ?string] — test_code faqat backend sinov rejimida
 * (OTP_TEST_MODE, production emas) keladi.
 */
function sendAdminOtp(array $user, string $purpose): array {
    $db = getDbConnection();
    if (otpSentToday((int) $user['id']) >= OTP_DAILY_LIMIT) {
        return ['ok' => false, 'error' => 'Kunlik SMS limiti (' . OTP_DAILY_LIMIT . ' ta) tugadi. Ertaga urinib ko\'ring yoki super adminga murojaat qiling.'];
    }
    $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
    $db->prepare("UPDATE admin_otp SET used_at = NOW() WHERE user_id = ? AND purpose = ? AND used_at IS NULL")
       ->execute([$user['id'], $purpose]);
    $db->prepare("INSERT INTO admin_otp (user_id, purpose, code_hash, expires_at)
                  VALUES (?, ?, ?, NOW() + make_interval(mins => ?))")
       ->execute([$user['id'], $purpose, password_hash($code, PASSWORD_DEFAULT), OTP_TTL_MINUTES]);
    $r = internalApiPost('/admin-p5/internal/sms-code', ['phone' => $user['phone'], 'code' => $code]);
    if (!$r['ok']) {
        return ['ok' => false, 'error' => 'SMS yuborilmadi: ' . $r['error']];
    }
    return ['ok' => true, 'error' => '', 'test_code' => $r['data']['test_code'] ?? null];
}

/** Kodni tekshiradi. Qaytaradi: ['ok' => bool, 'left' => int] */
function verifyAdminOtp(int $userId, string $purpose, string $code): array {
    $db = getDbConnection();
    $st = $db->prepare("SELECT id, code_hash, attempts, expires_at > NOW() AS alive FROM admin_otp
                        WHERE user_id = ? AND purpose = ? AND used_at IS NULL ORDER BY id DESC LIMIT 1");
    $st->execute([$userId, $purpose]);
    $o = $st->fetch();
    if (!$o) return ['ok' => false, 'left' => 0];
    $code = preg_replace('/\D/', '', $code);
    if ($o['alive'] && (int) $o['attempts'] < OTP_MAX_ATTEMPTS && password_verify($code, $o['code_hash'])) {
        $db->prepare('UPDATE admin_otp SET used_at = NOW() WHERE id = ?')->execute([$o['id']]);
        return ['ok' => true, 'left' => 0];
    }
    $attempts = (int) $o['attempts'] + 1;
    $dead = $attempts >= OTP_MAX_ATTEMPTS || !$o['alive'];
    $db->prepare('UPDATE admin_otp SET attempts = ?' . ($dead ? ', used_at = NOW()' : '') . ' WHERE id = ?')
       ->execute([$attempts, $o['id']]);
    return ['ok' => false, 'left' => $o['alive'] ? max(0, OTP_MAX_ATTEMPTS - $attempts) : 0];
}

function lastOtpAt(int $userId, string $purpose): ?int {
    $st = getDbConnection()->prepare("SELECT EXTRACT(EPOCH FROM created_at)::bigint FROM admin_otp
                                      WHERE user_id = ? AND purpose = ? ORDER BY id DESC LIMIT 1");
    $st->execute([$userId, $purpose]);
    $v = $st->fetchColumn();
    return $v === false ? null : (int) $v;
}

/** Ishonchli qurilma cookie si shu admin uchunmi. */
function trustedDeviceValid(int $userId): bool {
    $tok = $_COOKIE[TRUST_COOKIE] ?? '';
    if (!is_string($tok) || strlen($tok) < 40) return false;
    $st = getDbConnection()->prepare('SELECT 1 FROM admin_trusted_devices WHERE user_id = ? AND token_hash = ? AND expires_at > NOW()');
    $st->execute([$userId, hash('sha256', $tok)]);
    return (bool) $st->fetchColumn();
}

function rememberDevice(int $userId): void {
    $tok = bin2hex(random_bytes(32));
    getDbConnection()->prepare(
        'INSERT INTO admin_trusted_devices (user_id, token_hash, user_agent, ip, expires_at)
         VALUES (?, ?, ?, ?, NOW() + make_interval(days => ?))'
    )->execute([$userId, hash('sha256', $tok), clientUa() ?: null, clientIp() ?: null, TRUST_DAYS]);
    $https = ini_get('session.cookie_secure') === '1';
    setcookie(TRUST_COOKIE, $tok, ['expires' => time() + TRUST_DAYS * 86400, 'path' => '/',
                                   'secure' => $https, 'httponly' => true, 'samesite' => 'Strict']);
}

/** Ikki bosqich o'tdi — sessiya ochiladi. */
function completeAdminLogin(array $user, bool $viaTrusted): void {
    startAdminSession();
    session_regenerate_id(true);
    $_SESSION['admin_user_id'] = (int) $user['id'];
    $_SESSION['admin_role'] = 'admin';
    $_SESSION['admin_perm_role'] = $user['admin_role'] ?: 'super_admin';
    $_SESSION['admin_name'] = $user['full_name'];
    $_SESSION['admin_login_time'] = time();
    $_SESSION['admin_last_activity'] = time();
    unset($_SESSION['login_pending']);
    getDbConnection()->prepare('UPDATE users SET last_login_at = NOW() WHERE id = ?')->execute([$user['id']]);
    auditLog('admin_login', 'admin', $user['id'], ['trusted_device' => $viaTrusted, 'sms_2fa_off' => ADMIN_SMS_2FA_OFF], (int) $user['id']);
}

/** L7: talablar ro'yxati → [matn, bajarildimi] */
function passwordRules(string $p, ?string $currentHash = null): array {
    return [
        ['Kamida 12 belgi', mb_strlen($p) >= 12],
        ['Katta va kichik harf', (bool) (preg_match('/\p{Lu}/u', $p) && preg_match('/\p{Ll}/u', $p))],
        ['Raqam yoki maxsus belgi', (bool) preg_match('/[\d\W_]/u', $p)],
        ['Joriy paroldan farq qiladi', $currentHash === null || $p === '' || !password_verify($p, $currentHash)],
    ];
}

function passwordOk(string $p, ?string $currentHash = null): bool {
    foreach (passwordRules($p, $currentHash) as [, $ok]) if (!$ok) return false;
    return true;
}

/** «+998 90 *** ** 47» */
function maskAdminPhone(string $phone): string {
    $d = preg_replace('/\D/', '', $phone);
    if (strlen($d) !== 12) return $phone;
    return '+998 ' . substr($d, 3, 2) . ' *** ** ' . substr($d, 10, 2);
}
