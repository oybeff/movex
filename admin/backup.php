<?php
require_once 'config.php';
requireAdmin();

$pageTitle = 'Database Backup';
$currentPage = 'backup';

$message = '';
$messageType = '';

// Handle backup creation
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    $action = $_POST['action'];
    
    if ($action === 'create_backup') {
        $backupType = $_POST['backup_type'] ?? 'full';
        
        // Yo'l monorepo tuzilishiga ko'ra. Ilgari bu yerda
        // 'movex_go_backend/scripts/backup.sh' turardi — repozitoriylar
        // birlashtirilgandan keyin bunday katalog yo'q va zaxira nusxa
        // tugmasi ishlamay qolgan edi.
        $scriptPath = dirname(__DIR__) . '/backend/scripts/backup.sh';
        $command = escapeshellcmd($scriptPath) . ' --' . escapeshellarg($backupType);
        
        exec($command . ' 2>&1', $output, $returnCode);
        
        if ($returnCode === 0) {
            $message = 'Backup muvaffaqiyatli yaratildi!';
            $messageType = 'success';
        } else {
            $message = 'Backup yaratishda xatolik: ' . implode("\n", $output);
            $messageType = 'error';
        }
    }
    
    if ($action === 'restore_backup') {
        $filename = $_POST['filename'] ?? '';
        
        if (!empty($filename)) {
            $backupFile = BACKUP_DIR . '/' . basename($filename);
            
            if (file_exists($backupFile)) {
                $scriptPath = dirname(__DIR__) . '/backend/scripts/restore.sh';
                $command = escapeshellcmd($scriptPath) . ' ' . escapeshellarg($backupFile);
                
                // Auto-confirm with 'yes'
                $descriptorspec = [
                    0 => ["pipe", "r"],
                    1 => ["pipe", "w"],
                    2 => ["pipe", "w"]
                ];
                
                $process = proc_open($command, $descriptorspec, $pipes);
                
                if (is_resource($process)) {
                    fwrite($pipes[0], "yes\n");
                    fclose($pipes[0]);
                    
                    $output = stream_get_contents($pipes[1]);
                    $error = stream_get_contents($pipes[2]);
                    fclose($pipes[1]);
                    fclose($pipes[2]);
                    
                    $returnCode = proc_close($process);
                    
                    if ($returnCode === 0) {
                        $message = 'Database muvaffaqiyatli restore qilindi!';
                        $messageType = 'success';
                    } else {
                        $message = 'Restore qilishda xatolik: ' . $error;
                        $messageType = 'error';
                    }
                }
            } else {
                $message = 'Backup fayl topilmadi!';
                $messageType = 'error';
            }
        }
    }
    
    if ($action === 'delete_backup') {
        $filename = $_POST['filename'] ?? '';
        
        if (!empty($filename)) {
            $backupFile = BACKUP_DIR . '/' . basename($filename);
            
            if (file_exists($backupFile)) {
                unlink($backupFile);
                
                // Delete metadata file if exists
                $metaFile = $backupFile . '.meta';
                if (file_exists($metaFile)) {
                    unlink($metaFile);
                }
                
                $message = 'Backup o\'chirildi!';
                $messageType = 'success';
            } else {
                $message = 'Backup fayl topilmadi!';
                $messageType = 'error';
            }
        }
    }
}

// Get list of backups
$backups = [];
if (is_dir(BACKUP_DIR)) {
    $files = scandir(BACKUP_DIR, SCANDIR_SORT_DESCENDING);
    
    foreach ($files as $file) {
        if (preg_match('/^backup_.*\.(sql|sql\.gz)$/', $file)) {
            $filepath = BACKUP_DIR . '/' . $file;
            $stat = stat($filepath);
            
            // Read metadata if exists
            $metadata = [];
            $metaFile = $filepath . '.meta';
            if (file_exists($metaFile)) {
                $metadata = json_decode(file_get_contents($metaFile), true);
            }
            
            $backups[] = [
                'filename' => $file,
                'size' => $stat['size'],
                'created_at' => $stat['mtime'],
                'metadata' => $metadata
            ];
        }
    }
}

include 'includes/header.php';
?>

<div class="content">
    <?php if ($message): ?>
        <div class="alert alert-<?= $messageType ?>">
            <?= htmlspecialchars($message) ?>
        </div>
    <?php endif; ?>
    
    <!-- Create Backup Card -->
    <div class="card">
        <div class="card-header">
            <h3 class="card-title">Yangi Backup Yaratish</h3>
        </div>
        <div class="card-body">
            <form method="POST" action="">
                <input type="hidden" name="action" value="create_backup">
                
                <div class="form-group">
                    <label for="backup_type">Backup Turi</label>
                    <select name="backup_type" id="backup_type" required>
                        <option value="full">Full Backup (Schema + Data)</option>
                        <option value="schema">Schema Only</option>
                        <option value="data">Data Only</option>
                    </select>
                </div>
                
                <button type="submit" class="btn btn-primary">
                    💾 Backup Yaratish
                </button>
            </form>
        </div>
    </div>

    <!-- Backups List -->
    <div class="card">
        <div class="card-header">
            <h3 class="card-title">Mavjud Backuplar</h3>
            <span class="badge badge-info"><?= count($backups) ?> ta backup</span>
        </div>
        <div class="card-body">
            <?php if (empty($backups)): ?>
                <p class="text-center text-muted">Hozircha backuplar yo'q</p>
            <?php else: ?>
                <div class="table-responsive">
                    <table>
                        <thead>
                            <tr>
                                <th>Fayl Nomi</th>
                                <th>Turi</th>
                                <th>Hajmi</th>
                                <th>Yaratilgan</th>
                                <th>Amallar</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($backups as $backup): ?>
                            <tr>
                                <td>
                                    <strong><?= htmlspecialchars($backup['filename']) ?></strong>
                                </td>
                                <td>
                                    <?php
                                    $type = $backup['metadata']['backup_type'] ?? 'full';
                                    $typeLabels = [
                                        'full' => 'Full',
                                        'schema' => 'Schema',
                                        'data' => 'Data'
                                    ];
                                    ?>
                                    <span class="badge badge-info">
                                        <?= $typeLabels[$type] ?? 'Full' ?>
                                    </span>
                                </td>
                                <td><?= formatBytes($backup['size']) ?></td>
                                <td><?= formatDate(date('Y-m-d H:i:s', $backup['created_at'])) ?></td>
                                <td>
                                    <div class="d-flex gap-1">
                                        <!-- Restore Button -->
                                        <form method="POST" action="" style="display: inline;"
                                              onsubmit="return confirm('⚠️ DIQQAT! Bu amal hozirgi ma\'lumotlarni o\'chiradi va backup\'dan tiklaydi. Davom etasizmi?');">
                                            <input type="hidden" name="action" value="restore_backup">
                                            <input type="hidden" name="filename" value="<?= htmlspecialchars($backup['filename']) ?>">
                                            <button type="submit" class="btn btn-sm btn-success" title="Restore">
                                                ♻️ Restore
                                            </button>
                                        </form>

                                        <!-- Delete Button -->
                                        <form method="POST" action="" style="display: inline;"
                                              onsubmit="return confirm('Bu backup\'ni o\'chirmoqchimisiz?');">
                                            <input type="hidden" name="action" value="delete_backup">
                                            <input type="hidden" name="filename" value="<?= htmlspecialchars($backup['filename']) ?>">
                                            <button type="submit" class="btn btn-sm btn-danger" title="O'chirish">
                                                🗑️ O'chirish
                                            </button>
                                        </form>
                                    </div>
                                </td>
                            </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            <?php endif; ?>
        </div>
    </div>

    <!-- Backup Information -->
    <div class="card">
        <div class="card-header">
            <h3 class="card-title">ℹ️ Backup Haqida Ma'lumot</h3>
        </div>
        <div class="card-body">
            <div style="line-height: 1.8;">
                <p><strong>Backup Papkasi:</strong> <code><?= BACKUP_DIR ?></code></p>
                <p><strong>Saqlash Muddati:</strong> <?= BACKUP_RETENTION_DAYS ?> kun</p>
                <p><strong>Umumiy Hajm:</strong> <?= formatBytes(array_sum(array_column($backups, 'size'))) ?></p>

                <hr style="margin: 20px 0; border: none; border-top: 1px solid var(--gray-200);">

                <h4 style="margin-bottom: 12px;">📝 Backup Turlari:</h4>
                <ul style="margin-left: 20px;">
                    <li><strong>Full Backup:</strong> Database schema va barcha ma'lumotlar</li>
                    <li><strong>Schema Only:</strong> Faqat database strukturasi (jadvallar, indekslar)</li>
                    <li><strong>Data Only:</strong> Faqat ma'lumotlar (schema'siz)</li>
                </ul>

                <hr style="margin: 20px 0; border: none; border-top: 1px solid var(--gray-200);">

                <h4 style="margin-bottom: 12px;">⚠️ Muhim Eslatmalar:</h4>
                <ul style="margin-left: 20px;">
                    <li>Restore qilishdan oldin albatta yangi backup yarating</li>
                    <li>Restore jarayoni hozirgi ma'lumotlarni to'liq o'chiradi</li>
                    <li>Katta backuplar uchun restore vaqti uzoqroq bo'lishi mumkin</li>
                    <li>Production muhitda restore qilishdan oldin test muhitda sinab ko'ring</li>
                </ul>
            </div>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>

