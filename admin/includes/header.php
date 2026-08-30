<?php
$adminUser = getAdminUser();
?>
<!DOCTYPE html>
<html lang="uz">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= $pageTitle ?? 'Admin Panel' ?> - Movex GO</title>
    <link rel="stylesheet" href="assets/css/style.css">
</head>
<body>
    <div class="dashboard">
        <!-- Sidebar -->
        <aside class="sidebar" id="sidebar">
            <div class="sidebar-header">
                <h2>🚜 Movex GO</h2>
                <p>Admin Panel</p>
            </div>
            
            <nav class="sidebar-nav">
                <ul>
                    <li>
                        <a href="index.php" class="<?= ($currentPage ?? '') === 'dashboard' ? 'active' : '' ?>">
                            <span>📊</span>
                            Dashboard
                        </a>
                    </li>
                    <li>
                        <a href="users.php" class="<?= ($currentPage ?? '') === 'users' ? 'active' : '' ?>">
                            <span>👥</span>
                            Foydalanuvchilar
                        </a>
                    </li>
                    <li>
                        <a href="orders.php" class="<?= ($currentPage ?? '') === 'orders' ? 'active' : '' ?>">
                            <span>📦</span>
                            Buyurtmalar
                        </a>
                    </li>
                    <li>
                        <a href="balance.php" class="<?= ($currentPage ?? '') === 'balance' ? 'active' : '' ?>">
                            <span>💰</span>
                            Balans
                        </a>
                    </li>
                    <li>
                        <a href="budget.php" class="<?= ($currentPage ?? '') === 'budget' ? 'active' : '' ?>">
                            <span>🏦</span>
                            Budjet Jamg'armasi
                        </a>
                    </li>
                    <li>
                        <a href="backup.php" class="<?= ($currentPage ?? '') === 'backup' ? 'active' : '' ?>">
                            <span>💾</span>
                            Database Backup
                        </a>
                    </li>
                    <li>
                        <a href="system.php" class="<?= ($currentPage ?? '') === 'system' ? 'active' : '' ?>">
                            <span>⚙️</span>
                            Tizim Ma'lumotlari
                        </a>
                    </li>
                    <li>
                        <a href="logout.php" style="color: #ef4444;">
                            <span>🚪</span>
                            Chiqish
                        </a>
                    </li>
                </ul>
            </nav>
        </aside>
        
        <!-- Main Content -->
        <main class="main-content">
            <!-- Header -->
            <header class="header">
                <div class="header-left">
                    <button class="btn btn-secondary btn-sm" id="toggleSidebar" style="display: none;">
                        ☰
                    </button>
                    <h1><?= $pageTitle ?? 'Admin Panel' ?></h1>
                </div>
                
                <div class="header-right">
                    <div class="user-info">
                        <div class="user-avatar">
                            <?= strtoupper(substr($adminUser['full_name'], 0, 1)) ?>
                        </div>
                        <div class="user-details">
                            <div class="user-name"><?= htmlspecialchars($adminUser['full_name']) ?></div>
                            <div class="user-role">Administrator</div>
                        </div>
                    </div>
                </div>
            </header>

