<?php
/**
 * Admin Panel Configuration
 * Movex GO Admin Panel - Database va API sozlamalari
 */

// Muhit: APP_ENV=development bo'lgandagina xatolar ekranga chiqadi.
// Ilgari display_errors doim yoqilgan edi — bu prodda tashqi odamga
// stek va baza haqidagi ma'lumotni ko'rsatib qo'yardi.
define('IS_DEV', getenv('APP_ENV') === 'development');

error_reporting(E_ALL);
ini_set('display_errors', IS_DEV ? '1' : '0');
ini_set('log_errors', '1');

// Session sozlamalari
ini_set('session.cookie_httponly', 1);
ini_set('session.use_only_cookies', 1);
// HTTPS aniqlansa — cookie faqat shifrlangan ulanish orqali yuboriladi.
// Ilgari bu doim 0 edi, ya'ni prod HTTPS da ham sessiya ochiq HTTP orqali
// ketishi va o'g'irlanishi mumkin edi.
$isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
    || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https')
    || (($_SERVER['SERVER_PORT'] ?? '') == 443);
ini_set('session.cookie_secure', $isHttps ? '1' : '0');
ini_set('session.cookie_samesite', 'Strict');

// Timezone
date_default_timezone_set('Asia/Tashkent');

// Database Configuration
//
// Ulanish sozlamalari backend'ning .env faylidagi DATABASE_URL dan olinadi —
// ilova aynan shundan foydalanadi, ya'ni ikkinchi manba bo'lmaydi.
//
// Ilgari bu yerda faqat POSTGRES_* o'zgaruvchilari o'qilardi. Ular .env da
// yo'q, shuning uchun adminka standart qiymatlarga tushardi — foydalanuvchi
// "shohruxbek", boshqa mashinadan qolgan — va butun panel
// "role does not exist" bilan yiqilardi.
$movexDb = ['host' => 'localhost', 'port' => '5432',
            'name' => 'movex_go', 'user' => get_current_user(), 'pass' => ''];

$movexEnvFile = dirname(__DIR__) . '/backend/.env';
if (is_readable($movexEnvFile)) {
    foreach (file($movexEnvFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (strpos(ltrim($line), 'DATABASE_URL=') !== 0) {
            continue;
        }
        $url = trim(substr(ltrim($line), strlen('DATABASE_URL=')), " \t\"'");
        $parts = parse_url($url);
        if ($parts !== false) {
            if (!empty($parts['host'])) $movexDb['host'] = $parts['host'];
            if (!empty($parts['port'])) $movexDb['port'] = (string)$parts['port'];
            if (!empty($parts['user'])) $movexDb['user'] = urldecode($parts['user']);
            if (isset($parts['pass'])) $movexDb['pass'] = urldecode($parts['pass']);
            if (!empty($parts['path'])) $movexDb['name'] = ltrim($parts['path'], '/');
        }
        break;
    }
}

define('DB_HOST', getenv('POSTGRES_HOST') ?: $movexDb['host']);
define('DB_PORT', getenv('POSTGRES_PORT') ?: $movexDb['port']);
define('DB_NAME', getenv('POSTGRES_DB') ?: $movexDb['name']);
define('DB_USER', getenv('POSTGRES_USER') ?: $movexDb['user']);
define('DB_PASSWORD', getenv('POSTGRES_PASSWORD') ?: $movexDb['pass']);

// API Configuration
define('API_BASE_URL', 'http://localhost:8000');
define('API_TIMEOUT', 30);

// Admin Panel Configuration
define('ADMIN_SESSION_NAME', 'movex_admin_session');
define('ADMIN_SESSION_LIFETIME', 3600 * 8); // 8 soat
define('ITEMS_PER_PAGE', 20);

// Backup Configuration
// Zaxira nusxalar backend/scripts/backup.sh yozadigan joyda yotadi.
define('BACKUP_DIR', dirname(__DIR__) . '/backend/database/backups');
define('BACKUP_RETENTION_DAYS', 30);

// ADMIN_SECRET_KEY olib tashlandi: u shu yerda ochiq yozilgan edi, lekin
// kodning birorta joyida ishlatilmasdi. Kirish parol bilan tekshiriladi
// (adminLogin), sessiya esa PHP ning o'z mexanizmi bilan himoyalangan.

/**
 * Database Connection
 */
function getDbConnection() {
    static $conn = null;
    
    if ($conn === null) {
        try {
            $dsn = sprintf(
                "pgsql:host=%s;port=%s;dbname=%s",
                DB_HOST,
                DB_PORT,
                DB_NAME
            );
            
            $conn = new PDO($dsn, DB_USER, DB_PASSWORD, [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]);
        } catch (PDOException $e) {
            die("Database connection failed: " . $e->getMessage());
        }
    }
    
    return $conn;
}

/**
 * Session Management
 */
function startAdminSession() {
    if (session_status() === PHP_SESSION_NONE) {
        session_name(ADMIN_SESSION_NAME);
        session_start();
    }
}

function isAdminLoggedIn() {
    startAdminSession();
    return isset($_SESSION['admin_user_id']) && isset($_SESSION['admin_role']);
}

function requireAdmin() {
    if (!isAdminLoggedIn()) {
        header('Location: login.php');
        exit;
    }
    
    if ($_SESSION['admin_role'] !== 'admin') {
        die('Access denied. Admin role required.');
    }
}

/**
 * Zaprosning haqiqatan shu paneldan kelganini tekshirish (CSRF).
 *
 * Nega kerak. Panel faqat cookie bilan ishlaydi. Cookie esa brauzer
 * tomonidan HAR QANDAY saytdan yuborilgan so'rovga ham qo'shiladi. Ya'ni
 * admin panelga kirgan holda begona sahifani ochsa, o'sha sahifadagi
 * yashirin forma o'zi jo'nab, admin nomidan amal bajarardi: foydalanuvchini
 * o'chirish, parolini almashtirish, pul yechishni tasdiqlash.
 *
 * Tekshiruv yo'q edi — hech bir sahifada. Endi POST qabul qiladigan har
 * bir forma token bilan yuboriladi va u sessiyadagisi bilan solishtiriladi:
 * begona sayt sessiyadagi tokenni o'qiy olmaydi.
 *
 * Solishtirish hash_equals bilan — oddiy === javob vaqti bo'yicha tokenni
 * belgima-belgi topishga imkon beradi.
 */
function generateCsrfToken() {
    startAdminSession();
    if (empty($_SESSION['csrf_token'])) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf_token'];
}

function verifyCsrfToken($token) {
    startAdminSession();
    if (empty($_SESSION['csrf_token']) || !is_string($token) || $token === '') {
        return false;
    }
    return hash_equals($_SESSION['csrf_token'], $token);
}

/**
 * Tekshiruvdan o'tmagan POST ni to'xtatadi.
 *
 * Sahifa o'zi hal qilmasin: unutilgan bitta forma butun himoyani bekor
 * qiladi. Shuning uchun bitta chaqiruv — va amal bajarilmaydi.
 */
function requireCsrfToken() {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        return;
    }
    if (!verifyCsrfToken($_POST['csrf_token'] ?? '')) {
        http_response_code(403);
        die('Sessiya eskirgan yoki so\'rov boshqa saytdan kelgan. '
            . 'Sahifani yangilab, amalni qaytaring.');
    }
}

function getAdminUser() {
    if (!isAdminLoggedIn()) {
        return null;
    }
    
    $db = getDbConnection();
    $stmt = $db->prepare("SELECT id, full_name, email, phone, role FROM users WHERE id = ? AND role = 'admin'");
    $stmt->execute([$_SESSION['admin_user_id']]);
    return $stmt->fetch();
}

function adminLogin($phone, $password) {
    $db = getDbConnection();
    
    // Find admin user by phone
    $stmt = $db->prepare("SELECT id, full_name, phone, password_hash, role FROM users WHERE phone = ? AND role = 'admin'");
    $stmt->execute([$phone]);
    $user = $stmt->fetch();
    
    if (!$user) {
        return false;
    }
    
    // Verify password (bcrypt)
    if (!password_verify($password, $user['password_hash'])) {
        return false;
    }
    
    // Set session
    startAdminSession();
    $_SESSION['admin_user_id'] = $user['id'];
    $_SESSION['admin_role'] = $user['role'];
    $_SESSION['admin_name'] = $user['full_name'];
    $_SESSION['admin_login_time'] = time();
    
    return true;
}

function adminLogout() {
    startAdminSession();
    session_destroy();
    header('Location: login.php');
    exit;
}

/**
 * app_settings dan qiymat olish.
 *
 * Ustun JSON, PostgreSQL uni qo'shtirnoq bilan qaytaradi ("fixed") — shuning
 * uchun json_decode kerak.
 *
 * commission.php da xuddi shunday settingValue() bor. Uni bu yerga
 * ko'chirmadim ataylab: o'sha sahifa ulushni almashtiradi, ya'ni pulga
 * tegadi, va uni tegmasdan qoldirish xavfsizroq. Ikkalasi bir xil ishlaydi.
 */
function appSettingValue(PDO $db, string $key, string $fallback): string {
    $stmt = $db->prepare("SELECT value FROM app_settings WHERE key = ?");
    $stmt->execute([$key]);
    $row = $stmt->fetch();
    if (!$row || $row['value'] === null) {
        return $fallback;
    }
    $decoded = json_decode((string)$row['value'], true);
    if ($decoded === null && json_last_error() !== JSON_ERROR_NONE) {
        return (string)$row['value'];
    }
    return is_scalar($decoded) ? (string)$decoded : $fallback;
}

/**
 * Texnika turining o'qiladigan nomi.
 *
 * Bazada tur KOD bo'lib yotadi ('excavator'). Adminkada u to'g'ridan-to'g'ri
 * chiqarilardi va admin "excavator - Komatsu PC200" ko'rardi. Ro'yxat
 * backend'dagi app/core/equipment_types.py bilan bir xil bo'lishi kerak.
 */
function equipmentTypeName($code) {
    static $names = [
        'excavator'       => 'Ekskavator',
        'mini_excavator'  => 'Mini ekskavator',
        'backhoe_loader'  => 'Ekskavator-yuklagich',
        'bulldozer'       => 'Buldozer',
        'front_loader'    => 'Frontal yuklagich',
        'grader'          => 'Greyder',
        'roller'          => 'Katok',
        'truck_crane'     => 'Avtokran',
        'manipulator'     => 'Manipulyator',
        'aerial_platform' => 'Avtovishka',
        'dump_truck'      => 'Samosval',
        'concrete_mixer'  => 'Beton aralashtirgich',
        'concrete_pump'   => 'Betonnasos',
        'auger_drill'     => 'Yamobur',
        'tow_truck'       => 'Tral / Evakuator',
        'compressor'      => 'Kompressor',
        'other'           => 'Boshqa texnika',
    ];
    if ($code === null || $code === '') return '—';
    return $names[$code] ?? $code;
}

/**
 * Material turi: bazada KOD, ekranda esa nomi.
 *
 * Xuddi texnika turlaridagi kabi. Kod foydalanuvchiga chiqib ketmasligi
 * kerak — bu loyihada allaqachon to'rt marta bo'lgan xato.
 * Ro'yxat backend/app/core/material_types.py bilan bir xil.
 */
function materialTypeName($code) {
    static $names = [
        'brick'     => "G'isht",
        'gas_block' => 'Gazoblok',
        'cement'    => 'Sement',
        'sand'      => 'Qum',
        'gravel'    => "Shag'al",
        'stone'     => 'Tosh',
        'rebar'     => 'Armatura',
        'concrete'  => 'Beton',
        'lumber'    => "Yog'och",
        'other'     => 'Boshqa material',
    ];
    if ($code === null || $code === '') return '—';
    return $names[$code] ?? $code;
}

/** O'lchov birligi: piece → dona. */
function materialUnitName($unit) {
    static $units = [
        'piece' => 'dona',
        'bag'   => 'qop',
        'tonne' => 'tonna',
        'm3'    => 'm³',
    ];
    return $units[$unit] ?? ($unit ?? '');
}

/** Yetkazadigan mashina: kod → nomi va sig'imi. */
function deliveryVehicleName($code) {
    static $vehicles = [
        'labo'  => 'Labo (0.7 t)',
        'isuzu' => 'Isuzu (5 t)',
        'kamaz' => 'KamAZ (15 t)',
        'howo'  => 'Howo (25 t)',
    ];
    return $vehicles[$code] ?? ($code ?? '—');
}

/**
 * Utility Functions
 */
function formatBytes($bytes, $precision = 2) {
    $units = ['B', 'KB', 'MB', 'GB', 'TB'];
    
    for ($i = 0; $bytes > 1024 && $i < count($units) - 1; $i++) {
        $bytes /= 1024;
    }
    
    return round($bytes, $precision) . ' ' . $units[$i];
}

function formatDate($date, $format = 'Y-m-d H:i:s') {
    if (empty($date)) return '-';
    return date($format, strtotime($date));
}

function sanitizeInput($data) {
    return htmlspecialchars(strip_tags(trim($data)));
}

