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
define('DB_HOST', getenv('POSTGRES_HOST') ?: 'localhost');
define('DB_PORT', getenv('POSTGRES_PORT') ?: '5432');
define('DB_NAME', getenv('POSTGRES_DB') ?: 'movex_go');
define('DB_USER', getenv('POSTGRES_USER') ?: 'shohruxbek');
define('DB_PASSWORD', getenv('POSTGRES_PASSWORD') ?: '');

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

