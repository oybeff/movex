<?php
$adminUser = getAdminUser();
?>
<!DOCTYPE html>
<html lang="uz">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= $pageTitle ?? 'Admin Panel' ?> - Movex GO</title>
    <link rel="icon" type="image/png" href="assets/favicon.png">
    <link rel="stylesheet" href="assets/css/style.css">
    <style>
        /* Foydalanuvchini boshqarish paneli — bosilganda ochiladi */
        tr.hidden { display: none; }
    </style>
</head>
<body>
    <div class="dashboard">
        <!-- Sidebar -->
        <aside class="sidebar" id="sidebar">
            <div class="sidebar-header">
                <h2 style="display:flex; align-items:center; gap:9px;">
                    <img src="assets/logo.png" alt="MovexGo" width="30" height="30"
                         style="border-radius:7px; background:#fff;">
                    Movex GO
                </h2>
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
                        <a href="requests.php" class="<?= ($currentPage ?? '') === 'requests' ? 'active' : '' ?>">
                            <span>📣</span>
                            Zayavkalar
                            <?php
                            // Javob kelmagan ochiq zayavkalar soni. Ular
                            // ko'p bo'lsa — yo egalar yetishmaydi, yo
                            // radius juda tor: buni darhol ko'rish kerak.
                            try {
                                $openNoOffers = getDbConnection()->query("
                                    SELECT COUNT(*) FROM equipment_requests r
                                     WHERE r.status = 'open'
                                       AND NOT EXISTS (SELECT 1 FROM request_offers o
                                                        WHERE o.request_id = r.id
                                                          AND o.status = 'pending')
                                ")->fetchColumn();
                            } catch (Throwable $e) {
                                $openNoOffers = 0;
                            }
                            if ($openNoOffers > 0):
                            ?>
                                <span class="badge badge-warning" style="margin-left:auto;"><?= $openNoOffers ?></span>
                            <?php endif; ?>
                        </a>
                    </li>
                    <li>
                        <a href="listings.php" class="<?= ($currentPage ?? '') === 'listings' ? 'active' : '' ?>">
                            <span>📢</span>
                            E'lonlar
                            <?php
                            // Ega olgan, lekin mijoz hali tasdiqlamagan e'lonlar.
                            // Bu holatda ijrochi javob kutib turadi va telefon
                            // hali ochilmagan — uzoq turishi kerak emas.
                            try {
                                $waitingConfirm = getDbConnection()->query("
                                    SELECT COUNT(*) FROM listings WHERE status = 'taken'
                                ")->fetchColumn();
                            } catch (Throwable $e) {
                                $waitingConfirm = 0;
                            }
                            if ($waitingConfirm > 0):
                            ?>
                                <span class="badge badge-info" style="margin-left:auto;"><?= $waitingConfirm ?></span>
                            <?php endif; ?>
                        </a>
                    </li>
                    <li>
                        <a href="materials.php" class="<?= ($currentPage ?? '') === 'materials' ? 'active' : '' ?>">
                            <span>🧱</span>
                            Materiallar
                            <?php
                            // Moderatsiyada turgan tovarlar. Ular katalogda
                            // KO'RINMAYDI, ya'ni sotuvchi kutib turadi va
                            // xaridor tovarni umuman ko'rmaydi — bu raqam
                            // uzoq nolda turmasligi kerak.
                            try {
                                $pendingProducts = getDbConnection()->query("
                                    SELECT COUNT(*) FROM material_products
                                     WHERE status = 'pending'
                                ")->fetchColumn();
                            } catch (Throwable $e) {
                                $pendingProducts = 0;
                            }
                            if ($pendingProducts > 0):
                            ?>
                                <span class="badge badge-warning" style="margin-left:auto;"><?= $pendingProducts ?></span>
                            <?php endif; ?>
                        </a>
                    </li>
                    <li>
                        <a href="balance.php" class="<?= ($currentPage ?? '') === 'balance' ? 'active' : '' ?>">
                            <span>💰</span>
                            Balans
                        </a>
                    </li>
                    <li>
                        <a href="commission.php" class="<?= ($currentPage ?? '') === 'commission' ? 'active' : '' ?>">
                            <span>💰</span>
                            Platforma ulushi
                        </a>
                    </li>
                    <li>
                        <a href="budget.php" class="<?= ($currentPage ?? '') === 'budget' ? 'active' : '' ?>">
                            <span>🏦</span>
                            Budjet Jamg'armasi
                        </a>
                    </li>
                    <li>
                        <a href="payouts.php" class="<?= ($currentPage ?? '') === 'payouts' ? 'active' : '' ?>">
                            <span>💸</span>
                            Pul Yechish
                            <?php
                            // Kutayotgan arizalar soni — ular ko'rib chiqilmasa,
                            // texnika egasi pulini ololmaydi
                            try {
                                $pendingPayouts = getDbConnection()
                                    ->query("SELECT COUNT(*) FROM payout_requests WHERE status = 'pending'")
                                    ->fetchColumn();
                            } catch (Throwable $e) {
                                $pendingPayouts = 0;
                            }
                            if ($pendingPayouts > 0): ?>
                                <span class="badge badge-warning" style="margin-left:auto;"><?= (int) $pendingPayouts ?></span>
                            <?php endif; ?>
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

