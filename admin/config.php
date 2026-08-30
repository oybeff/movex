<?php
/**
 * Admin Panel Configuration
 * Movex GO Admin Panel - Database va API sozlamalari
 */

// Error reporting (production'da o'chirish kerak)
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Session sozlamalari
ini_set('session.cookie_httponly', 1);
ini_set('session.use_only_cookies', 1);
ini_set('session.cookie_secure', 0); // HTTPS bo'lsa 1 qiling

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
define('BACKUP_DIR', dirname(__DIR__) . '/movex_go_backend/database/backups');
define('BACKUP_RETENTION_DAYS', 30);

// Security
define('ADMIN_SECRET_KEY', 'movex_go_admin_secret_2024'); // O'zgartiring!

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

