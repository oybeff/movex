<?php
require_once 'config.php';

startAdminSession();

// Agar allaqachon login bo'lsa, dashboard'ga yo'naltirish
if (isAdminLoggedIn()) {
    header('Location: index.php');
    exit;
}

$error = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $phone = sanitizeInput($_POST['phone'] ?? '');
    $password = $_POST['password'] ?? '';

    // Kirish formasi ham tekshiriladi, lekin sahifani yopib qo'ymaydi:
    // token eskirgan bo'lsa (forma uzoq ochiq turgan) odam shunchaki qayta
    // urinadi. Bu yerda die() qilish — o'z panelidan quvib chiqarish.
    if (!verifyCsrfToken($_POST['csrf_token'] ?? '')) {
        $error = 'Sahifa eskirgan, qaytadan kiriting';
    } elseif (empty($phone) || empty($password)) {
        $error = 'Telefon raqam va parol kiritilishi shart';
    } else {
        if (adminLogin($phone, $password)) {
            header('Location: index.php');
            exit;
        } else {
            $error = 'Telefon raqam yoki parol noto\'g\'ri';
        }
    }
}
?>
<!DOCTYPE html>
<html lang="uz">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin Login - Movex GO</title>
    <link rel="stylesheet" href="assets/css/style.css">
</head>
<body class="login-page">
    <div class="login-container">
        <div class="login-box">
            <div class="login-header">
                <h1>🚜 Movex GO</h1>
                <p>Admin Panel</p>
            </div>
            
            <?php if ($error): ?>
                <div class="alert alert-error">
                    <?= htmlspecialchars($error) ?>
                </div>
            <?php endif; ?>
            
            <form method="POST" action="" class="login-form">
                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                <div class="form-group">
                    <label for="phone">Telefon Raqam</label>
                    <input 
                        type="text" 
                        id="phone" 
                        name="phone" 
                        placeholder="+998901234567"
                        value="<?= htmlspecialchars($_POST['phone'] ?? '') ?>"
                        required
                        autofocus
                    >
                </div>
                
                <div class="form-group">
                    <label for="password">Parol</label>
                    <input 
                        type="password" 
                        id="password" 
                        name="password" 
                        placeholder="••••••••"
                        required
                    >
                </div>
                
                <button type="submit" class="btn btn-primary btn-block">
                    Kirish
                </button>
            </form>
            
            <div class="login-footer">
                <p>&copy; <?= date('Y') ?> Movex GO. Barcha huquqlar himoyalangan.</p>
            </div>
        </div>
    </div>
</body>
</html>

