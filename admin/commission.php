<?php
/**
 * Platforma ulushi: qat'iy summa yoki foiz.
 *
 * Ulushni TEXNIKA EGASI to'laydi. Mijoz faqat ijara va yetkazib berish
 * narxini to'laydi, ulush esa buyurtma yakunlanganda egasining pulidan
 * ushlab qolinadi.
 *
 * Ilgari ulush mijozning summasiga ustiga qo'shilardi va har doim 10% edi.
 * Yangi ilova uchun bu ko'p, shuning uchun hozircha qat'iy 5 000 so'm
 * olinadi — bu sahifadan istalgan payt foizga qaytarish mumkin, kodni
 * tahrirlamasdan.
 *
 * DIQQAT: hisob-kitobning o'zi backend'da, pricing_service.py da. Bu sahifa
 * faqat app_settings jadvalidagi qiymatlarni o'zgartiradi.
 */
require_once 'config.php';
requireAdmin();

$pageTitle = 'Platforma ulushi';
$currentPage = 'commission';

$db = getDbConnection();

/**
 * app_settings.value — bu JSON ustuni, oddiy matn emas.
 *
 * PostgreSQL uni qo'shtirnoq bilan qaytaradi ("fixed"), shuning uchun
 * json_decode kerak. Aks holda $mode === 'fixed' solishtiruvi hech qachon
 * to'g'ri bo'lmasdi va sahifa har doim noto'g'ri rejimni ko'rsatardi.
 */
function settingValue(PDO $db, string $key, string $fallback): string {
    $stmt = $db->prepare("SELECT value FROM app_settings WHERE key = ?");
    $stmt->execute([$key]);
    $row = $stmt->fetch();
    if (!$row || $row['value'] === null) {
        return $fallback;
    }
    $decoded = json_decode((string)$row['value'], true);
    if ($decoded === null && json_last_error() !== JSON_ERROR_NONE) {
        return (string)$row['value'];   // ustun matn bo'lib qolgan holat
    }
    return is_scalar($decoded) ? (string)$decoded : $fallback;
}

function saveSetting(PDO $db, string $key, string $value): void {
    $stmt = $db->prepare("SELECT id FROM app_settings WHERE key = ?");
    $stmt->execute([$key]);
    // to_jsonb(?::text) — qiymatni JSON ga aylantiradi. Oddiy satr bilan
    // yozib bo'lmaydi: ustun turi json, va "fixed" xato beradi.
    if ($stmt->fetch()) {
        $db->prepare("UPDATE app_settings SET value = to_jsonb(?::text), updated_at = NOW() WHERE key = ?")
           ->execute([$value, $key]);
    } else {
        $db->prepare("INSERT INTO app_settings (key, value) VALUES (?, to_jsonb(?::text))")
           ->execute([$key, $value]);
    }
}

$message = null;
$error = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $mode = $_POST['mode'] ?? 'fixed';
    $fixed = trim((string)($_POST['fixed'] ?? '5000'));
    $percent = trim((string)($_POST['percent'] ?? '10'));

    if (!in_array($mode, ['fixed', 'percent'], true)) {
        $error = "Noma'lum rejim";
    } elseif (!is_numeric($fixed) || (float)$fixed < 0) {
        $error = "Qat'iy summa manfiy bo'lishi mumkin emas";
    } elseif (!is_numeric($percent) || (float)$percent < 0 || (float)$percent > 100) {
        $error = 'Foiz 0 va 100 orasida bo\'lishi kerak';
    } else {
        saveSetting($db, 'commission_mode', $mode);
        saveSetting($db, 'commission_fixed', $fixed);
        saveSetting($db, 'commission_percent', $percent);
        $message = 'Saqlandi. Yangi buyurtmalarga darhol qo\'llaniladi.';
    }
}

$mode = settingValue($db, 'commission_mode', 'fixed');
$fixed = settingValue($db, 'commission_fixed', '5000');
$percent = settingValue($db, 'commission_percent', '10');

// Oxirgi 30 kunda yig'ilgan ulush — o'zgarish ta'sirini ko'rish uchun
$collected = $db->query("
    SELECT COALESCE(SUM(amount), 0) AS total, COUNT(*) AS cnt
      FROM budget_reserves
     WHERE created_at >= NOW() - INTERVAL '30 days'
")->fetch();

include 'includes/header.php';
?>

<div class="content">
    <?php if ($message): ?>
        <div class="alert alert-success"><?= htmlspecialchars($message) ?></div>
    <?php endif; ?>
    <?php if ($error): ?>
        <div class="alert alert-danger"><?= htmlspecialchars($error) ?></div>
    <?php endif; ?>

    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Joriy rejim</div>
                    <div class="stat-value" style="font-size: 22px;">
                        <?= $mode === 'fixed'
                            ? number_format((float)$fixed, 0, '.', ' ') . " so'm"
                            : rtrim(rtrim($percent, '0'), '.') . '%' ?>
                    </div>
                    <div class="stat-change">
                        <?= $mode === 'fixed' ? "har bir buyurtmadan qat'iy" : 'ijara summasidan' ?>
                    </div>
                </div>
                <div class="stat-icon primary">💰</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">30 kunda yig'ilgan</div>
                    <div class="stat-value"><?= number_format((float)$collected['total'], 0, '.', ' ') ?></div>
                    <div class="stat-change"><?= (int)$collected['cnt'] ?> ta buyurtmadan</div>
                </div>
                <div class="stat-icon success">🏦</div>
            </div>
        </div>
    </div>

    <div class="card mb-3">
        <div class="card-body">
            <div class="alert alert-info" style="margin-bottom: 18px;">
                <strong>Ulushni texnika egasi to'laydi.</strong>
                Mijoz faqat ijara va yetkazib berishni to'laydi; ulush buyurtma
                yakunlanganda egasining puliga tushmasdan platformada qoladi.
                Ulush hech qachon buyurtma summasidan oshmaydi — arzon
                buyurtmada egasi minusga ketmasligi uchun.
            </div>

            <form method="POST" action="">
                <div class="form-group">
                    <label>
                        <input type="radio" name="mode" value="fixed"
                               <?= $mode === 'fixed' ? 'checked' : '' ?>>
                        <strong>Qat'iy summa</strong> — har bir buyurtmadan bir xil
                    </label>
                    <input type="number" name="fixed" min="0" step="100"
                           value="<?= htmlspecialchars($fixed) ?>"
                           style="max-width: 220px; margin-top: 6px;">
                    <small class="text-muted">so'm</small>
                </div>

                <div class="form-group" style="margin-top: 18px;">
                    <label>
                        <input type="radio" name="mode" value="percent"
                               <?= $mode === 'percent' ? 'checked' : '' ?>>
                        <strong>Foiz</strong> — ijara summasidan
                    </label>
                    <input type="number" name="percent" min="0" max="100" step="0.5"
                           value="<?= htmlspecialchars($percent) ?>"
                           style="max-width: 220px; margin-top: 6px;">
                    <small class="text-muted">%</small>
                </div>

                <button type="submit" class="btn btn-primary" style="margin-top: 20px;">
                    💾 Saqlash
                </button>
            </form>
        </div>
    </div>

    <div class="card">
        <div class="card-header">
            <h3 class="card-title">Misol: 3 000 000 so'mlik buyurtma</h3>
        </div>
        <div class="card-body">
            <?php
            $example = 3000000.0;
            $take = $mode === 'fixed' ? (float)$fixed : $example * (float)$percent / 100;
            $take = min($take, $example);
            ?>
            <table>
                <tr><td>Mijoz to'laydi</td>
                    <td><strong><?= number_format($example, 0, '.', ' ') ?></strong> so'm</td></tr>
                <tr><td>Platformaga</td>
                    <td><strong><?= number_format($take, 0, '.', ' ') ?></strong> so'm</td></tr>
                <tr><td>Texnika egasiga</td>
                    <td><strong><?= number_format($example - $take, 0, '.', ' ') ?></strong> so'm</td></tr>
            </table>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>
