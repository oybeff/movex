<?php
require_once 'config.php';
requireAdmin();

$pageTitle = 'Tizim Ma\'lumotlari';
$currentPage = 'system';

$db = getDbConnection();

// Database info
$dbVersion = $db->query("SELECT version()")->fetch()['version'];
$dbSize = $db->query("
    SELECT pg_size_pretty(pg_database_size(current_database())) as size
")->fetch()['size'];

// Table sizes
$tableSizes = $db->query("
    SELECT 
        schemaname,
        tablename,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
        pg_total_relation_size(schemaname||'.'||tablename) AS size_bytes
    FROM pg_tables
    WHERE schemaname = 'public'
    ORDER BY size_bytes DESC
")->fetchAll();

// Connection info
$connections = $db->query("
    SELECT 
        COUNT(*) as total,
        COUNT(CASE WHEN state = 'active' THEN 1 END) as active,
        COUNT(CASE WHEN state = 'idle' THEN 1 END) as idle
    FROM pg_stat_activity
    WHERE datname = current_database()
")->fetch();

// System info
$systemInfo = [
    'PHP Version' => phpversion(),
    'Server Software' => $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown',
    'Server OS' => PHP_OS,
    'Memory Limit' => ini_get('memory_limit'),
    'Max Execution Time' => ini_get('max_execution_time') . 's',
    'Upload Max Filesize' => ini_get('upload_max_filesize'),
    'Post Max Size' => ini_get('post_max_size'),
];

// Backup directory info
$backupInfo = [
    'path' => BACKUP_DIR,
    'exists' => is_dir(BACKUP_DIR),
    'writable' => is_writable(BACKUP_DIR),
    'size' => 0,
    'files' => 0
];

if ($backupInfo['exists']) {
    $files = glob(BACKUP_DIR . '/*');
    $backupInfo['files'] = count($files);
    foreach ($files as $file) {
        if (is_file($file)) {
            $backupInfo['size'] += filesize($file);
        }
    }
}

include 'includes/header.php';
?>

<div class="content">
    <!-- Database Info -->
    <div class="card">
        <div class="card-header">
            <h3 class="card-title">🗄️ Database Ma'lumotlari</h3>
        </div>
        <div class="card-body">
            <table>
                <tbody>
                    <tr>
                        <td><strong>Database Version</strong></td>
                        <td><?= htmlspecialchars($dbVersion) ?></td>
                    </tr>
                    <tr>
                        <td><strong>Database Size</strong></td>
                        <td><?= htmlspecialchars($dbSize) ?></td>
                    </tr>
                    <tr>
                        <td><strong>Database Name</strong></td>
                        <td><?= DB_NAME ?></td>
                    </tr>
                    <tr>
                        <td><strong>Database Host</strong></td>
                        <td><?= DB_HOST ?>:<?= DB_PORT ?></td>
                    </tr>
                    <tr>
                        <td><strong>Total Connections</strong></td>
                        <td>
                            <?= $connections['total'] ?> 
                            (Active: <?= $connections['active'] ?>, Idle: <?= $connections['idle'] ?>)
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>
    
    <!-- Table Sizes -->
    <div class="card">
        <div class="card-header">
            <h3 class="card-title">📊 Jadvallar Hajmi</h3>
        </div>
        <div class="card-body">
            <div class="table-responsive">
                <table>
                    <thead>
                        <tr>
                            <th>Jadval Nomi</th>
                            <th>Hajmi</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($tableSizes as $table): ?>
                        <tr>
                            <td><code><?= htmlspecialchars($table['tablename']) ?></code></td>
                            <td><?= htmlspecialchars($table['size']) ?></td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
    </div>
    
    <!-- System Info -->
    <div class="card">
        <div class="card-header">
            <h3 class="card-title">⚙️ Server Ma'lumotlari</h3>
        </div>
        <div class="card-body">
            <table>
                <tbody>
                    <?php foreach ($systemInfo as $key => $value): ?>
                    <tr>
                        <td><strong><?= htmlspecialchars($key) ?></strong></td>
                        <td><?= htmlspecialchars($value) ?></td>
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    </div>
    
    <!-- Backup Info -->
    <div class="card">
        <div class="card-header">
            <h3 class="card-title">💾 Backup Ma'lumotlari</h3>
        </div>
        <div class="card-body">
            <table>
                <tbody>
                    <tr>
                        <td><strong>Backup Directory</strong></td>
                        <td><code><?= htmlspecialchars($backupInfo['path']) ?></code></td>
                    </tr>
                    <tr>
                        <td><strong>Directory Exists</strong></td>
                        <td>
                            <?php if ($backupInfo['exists']): ?>
                                <span class="badge badge-success">✓ Mavjud</span>
                            <?php else: ?>
                                <span class="badge badge-danger">✗ Mavjud emas</span>
                            <?php endif; ?>
                        </td>
                    </tr>
                    <tr>
                        <td><strong>Writable</strong></td>
                        <td>
                            <?php if ($backupInfo['writable']): ?>
                                <span class="badge badge-success">✓ Yozish mumkin</span>
                            <?php else: ?>
                                <span class="badge badge-danger">✗ Yozish mumkin emas</span>
                            <?php endif; ?>
                        </td>
                    </tr>
                    <tr>
                        <td><strong>Total Backups</strong></td>
                        <td><?= $backupInfo['files'] ?> ta fayl</td>
                    </tr>
                    <tr>
                        <td><strong>Total Size</strong></td>
                        <td><?= formatBytes($backupInfo['size']) ?></td>
                    </tr>
                    <tr>
                        <td><strong>Retention Days</strong></td>
                        <td><?= BACKUP_RETENTION_DAYS ?> kun</td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>

