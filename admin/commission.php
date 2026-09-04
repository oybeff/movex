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
requireCsrfToken();

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

/**
 * Ikkala shakl uchun bir xil tekshiruv: rejim tanish bo'lsin, summa
 * manfiy bo'lmasin, foiz 0..100 orasida bo'lsin.
 * Xato bo'lsa matn qaytaradi, hammasi joyida bo'lsa — null.
 */
function validateCommission(string $mode, string $fixed, string $percent): ?string {
    if (!in_array($mode, ['fixed', 'percent'], true)) {
        return "Noma'lum rejim";
    }
    if (!is_numeric($fixed) || (float)$fixed < 0) {
        return "Qat'iy summa manfiy bo'lishi mumkin emas";
    }
    if (!is_numeric($percent) || (float)$percent < 0 || (float)$percent > 100) {
        return 'Foiz 0 va 100 orasida bo\'lishi kerak';
    }
    return null;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Sahifada ikkita mustaqil shakl bor: buyurtma ulushi va pul yechish
    // ulushi. Qaysi biri yuborilganini shu maydon aytadi — aks holda
    // bittasini saqlaganda ikkinchisi ham qayta yozilib ketardi.
    $form = $_POST['form'] ?? 'order';
    $mode = $_POST['mode'] ?? 'fixed';
    $fixed = trim((string)($_POST['fixed'] ?? '5000'));
    $percent = trim((string)($_POST['percent'] ?? '10'));

    $error = validateCommission($mode, $fixed, $percent);

    if ($error === null && $form === 'payout') {
        saveSetting($db, 'payout_commission_mode', $mode);
        saveSetting($db, 'payout_commission_fixed', $fixed);
        saveSetting($db, 'payout_commission_percent', $percent);
        $message = 'Saqlandi. Yangi arizalarga darhol qo\'llaniladi.';
    } elseif ($error === null) {
        saveSetting($db, 'commission_mode', $mode);
        saveSetting($db, 'commission_fixed', $fixed);
        saveSetting($db, 'commission_percent', $percent);
        $message = 'Saqlandi. Yangi buyurtmalarga darhol qo\'llaniladi.';
    }
}

$mode = settingValue($db, 'commission_mode', 'fixed');
$fixed = settingValue($db, 'commission_fixed', '5000');
$percent = settingValue($db, 'commission_percent', '10');

// Pul yechish ulushi — alohida sozlama, buyurtma ulushiga bog'liq emas.
$payoutMode = settingValue($db, 'payout_commission_mode', 'fixed');
$payoutFixed = settingValue($db, 'payout_commission_fixed', '5000');
$payoutPercent = settingValue($db, 'payout_commission_percent', '10');

// Pul yechishdan yig'ilgan ulush — 30 kun
$payoutCollected = $db->query("
    SELECT COALESCE(SUM(commission), 0) AS total, COUNT(*) AS cnt
      FROM payout_requests
     WHERE status = 'paid'
       AND commission > 0
       AND processed_at >= NOW() - INTERVAL '30 days'
")->fetch();

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
                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                <input type="hidden" name="form" value="order">
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

    <div class="card mb-3">
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

    <!-- ============ Pul yechish ulushi — alohida sozlama ============ -->

    <h2 style="margin: 34px 0 16px; font-size: 20px;">Pul yechish ulushi</h2>

    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Joriy rejim</div>
                    <div class="stat-value" style="font-size: 22px;">
                        <?= $payoutMode === 'fixed'
                            ? number_format((float)$payoutFixed, 0, '.', ' ') . " so'm"
                            : rtrim(rtrim($payoutPercent, '0'), '.') . '%' ?>
                    </div>
                    <div class="stat-change">
                        <?= $payoutMode === 'fixed' ? "har bir arizadan qat'iy" : 'ariza summasidan' ?>
                    </div>
                </div>
                <div class="stat-icon primary">💳</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">30 kunda ushlangan</div>
                    <div class="stat-value"><?= number_format((float)$payoutCollected['total'], 0, '.', ' ') ?></div>
                    <div class="stat-change"><?= (int)$payoutCollected['cnt'] ?> ta arizadan</div>
                </div>
                <div class="stat-icon success">🏦</div>
            </div>
        </div>
    </div>

    <div class="card mb-3">
        <div class="card-body">
            <div class="alert alert-info" style="margin-bottom: 18px;">
                <strong>Ushlanmani texnika egasi to'laydi.</strong>
                Bir buyurtmadan atigi
                <?= $mode === 'fixed' ? number_format((float)$fixed, 0, '.', ' ') . " so'm" : $percent . '%' ?>
                olinadi, va bu summa pulni kartaga o'tkazish uchun to'lov tizimi
                oladigan foizni qoplamaydi. Ushlanma ariza summasining ICHIDAN
                olinadi: 100 000 so'ragan ega balansidan 100 000 yechiladi,
                kartasiga qolgani tushadi. Shuning uchun u balansini oxirgi
                so'migacha yecha oladi.
                <br><br>
                Ushlanma ariza berilgan paytdagi qiymat bo'yicha yoziladi:
                bugun o'zgartirsangiz, kechagi arizalar tegilmaydi.
            </div>

            <form method="POST" action="">
                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                <input type="hidden" name="form" value="payout">
                <div class="form-group">
                    <label>
                        <input type="radio" name="mode" value="fixed"
                               <?= $payoutMode === 'fixed' ? 'checked' : '' ?>>
                        <strong>Qat'iy summa</strong> — har bir arizadan bir xil
                    </label>
                    <input type="number" name="fixed" min="0" step="100"
                           value="<?= htmlspecialchars($payoutFixed) ?>"
                           style="max-width: 220px; margin-top: 6px;">
                    <small class="text-muted">so'm</small>
                </div>

                <div class="form-group" style="margin-top: 18px;">
                    <label>
                        <input type="radio" name="mode" value="percent"
                               <?= $payoutMode === 'percent' ? 'checked' : '' ?>>
                        <strong>Foiz</strong> — ariza summasidan
                    </label>
                    <input type="number" name="percent" min="0" max="100" step="0.5"
                           value="<?= htmlspecialchars($payoutPercent) ?>"
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
            <h3 class="card-title">Misol: 100 000 so'm yechish</h3>
        </div>
        <div class="card-body">
            <?php
            $payoutExample = 100000.0;
            $payoutTake = $payoutMode === 'fixed'
                ? (float)$payoutFixed
                : $payoutExample * (float)$payoutPercent / 100;
            $payoutTake = min($payoutTake, $payoutExample);
            ?>
            <table>
                <tr><td>Ega so'raydi</td>
                    <td><strong><?= number_format($payoutExample, 0, '.', ' ') ?></strong> so'm</td></tr>
                <tr><td>Balansidan yechiladi</td>
                    <td><strong><?= number_format($payoutExample, 0, '.', ' ') ?></strong> so'm</td></tr>
                <tr><td>Platformaga</td>
                    <td><strong><?= number_format($payoutTake, 0, '.', ' ') ?></strong> so'm</td></tr>
                <tr><td>Kartaga o'tkaziladi</td>
                    <td><strong><?= number_format($payoutExample - $payoutTake, 0, '.', ' ') ?></strong> so'm</td></tr>
            </table>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>
