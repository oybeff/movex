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

    // Sovg'a va Rahmat shakllarida rejim va foiz maydonlari yo'q —
    // ularni tekshirish shart emas.
    $error = in_array($form, ['bonus', 'rahmat'], true)
        ? null
        : validateCommission($mode, $fixed, $percent);

    if ($form === 'rahmat') {
        $ofdVatInput = trim((string)($_POST['ofd_vat'] ?? '0'));
        $ofdMxikInput = preg_replace('/\D/', '', (string)($_POST['ofd_mxik'] ?? ''));
        $ofdPackageInput = preg_replace('/\D/', '', (string)($_POST['ofd_package_code'] ?? ''));

        if (!is_numeric($ofdVatInput) || (float)$ofdVatInput < 0 || (float)$ofdVatInput > 100) {
            $error = 'QQS 0 va 100 orasida bo\'lishi kerak';
        } elseif ($ofdMxikInput === '' || $ofdPackageInput === '') {
            // Bo'sh kod bilan chek shakllanmaydi, va invoys yaratishda
            // xato beradi — bu yerda to'xtatish arzonroq.
            $error = 'ИКПУ va qadoq kodi to\'ldirilishi shart';
        } else {
            saveSetting($db, 'payout_auto_enabled', isset($_POST['auto_payout']) ? '1' : '0');
            saveSetting($db, 'rahmat_ofd_mxik', $ofdMxikInput);
            saveSetting($db, 'rahmat_ofd_package_code', $ofdPackageInput);
            saveSetting($db, 'rahmat_ofd_vat', $ofdVatInput);
            $message = 'Saqlandi. Yangi to\'lovlar va arizalarga qo\'llaniladi.';
        }
    } elseif ($form === 'bonus') {
        // Sovg'a — alohida shakl, ulush tekshiruviga bog'liq emas.
        $bonusAmount = trim((string)($_POST['bonus_amount'] ?? '50000'));
        if (!is_numeric($bonusAmount) || (float)$bonusAmount < 0) {
            $error = "Sovg'a summasi manfiy bo'lishi mumkin emas";
        } else {
            saveSetting($db, 'signup_bonus_enabled', isset($_POST['bonus_enabled']) ? '1' : '0');
            saveSetting($db, 'signup_bonus_amount', $bonusAmount);
            $message = "Saqlandi. Yangi ro'yxatdan o'tganlarga qo'llaniladi.";
        }
    } elseif ($error === null && $form === 'payout') {
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

// Ro'yxatdan o'tganlik uchun sovg'a — faqat texnika egalari uchun.
$bonusEnabled = settingValue($db, 'signup_bonus_enabled', '1') === '1';
$bonusAmount = settingValue($db, 'signup_bonus_amount', '50000');

// Rahmat: avtomatik o'tkazma va fiskal chek kodlari.
// Standart qiymatlar rahmat_service.py dagilar bilan bir xil bo'lishi
// kerak — u yerda ular DEFAULT_OFD_* deb yozilgan.
$autoPayout = settingValue($db, 'payout_auto_enabled', '0') === '1';
$ofdMxik = settingValue($db, 'rahmat_ofd_mxik', '10204001001000000');
$ofdPackageCode = settingValue($db, 'rahmat_ofd_package_code', '1500169');
$ofdVat = settingValue($db, 'rahmat_ofd_vat', '0');

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

    <div class="card mb-3" style="margin-top: 24px;">
        <div class="card-header">
            <h3 class="card-title">Ro'yxatdan o'tganlik uchun sovg'a</h3>
        </div>
        <div class="card-body">
            <div class="alert alert-info" style="margin-bottom: 18px;">
                Sovg'a faqat <strong>texnika egasi</strong> ro'yxatdan o'tganda
                va bir marta beriladi. Ilgari ro'yxatdan o'tganlarga berilmaydi.
            </div>

            <form method="POST" action="">
                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                <input type="hidden" name="form" value="bonus">
                <div class="form-group">
                    <label>
                        <input type="checkbox" name="bonus_enabled" value="1"
                               <?= $bonusEnabled ? 'checked' : '' ?>>
                        <strong>Sovg'a berilsin</strong>
                    </label>
                </div>
                <div class="form-group" style="margin-top: 14px;">
                    <label>Summa</label><br>
                    <input type="number" name="bonus_amount" min="0" step="1000"
                           value="<?= htmlspecialchars($bonusAmount) ?>"
                           style="max-width: 220px; margin-top: 6px;">
                    <small class="text-muted">so'm</small>
                </div>
                <button type="submit" class="btn btn-primary" style="margin-top: 20px;">
                    💾 Saqlash
                </button>
            </form>
        </div>
    </div>

    <div class="card mb-3" style="margin-top: 24px;">
        <div class="card-header">
            <h3 class="card-title">Rahmat (Multicard)</h3>
        </div>
        <div class="card-body">
            <div class="alert alert-info" style="margin-bottom: 18px;">
                Pul kartaga <strong>shlyuz orqali</strong> o'tkaziladi. Savol faqat
                shunda: o'tkazishni kim boshlaydi. O'chirilgan bo'lsa — siz,
                arizani ko'rib chiqib; yoqilgan bo'lsa — tizim, ariza berilishi
                bilanoq. <strong>O'tkazma qaytarilmaydi</strong>, shuning uchun
                standart holda o'chirilgan.
            </div>

            <form method="POST" action="">
                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                <input type="hidden" name="form" value="rahmat">
                <div class="form-group">
                    <label>
                        <input type="checkbox" name="auto_payout" value="1"
                               <?= $autoPayout ? 'checked' : '' ?>>
                        <strong>Arizalar avtomatik o'tkazilsin</strong>
                    </label>
                </div>

                <hr style="margin: 20px 0; border: none; border-top: 1px solid #e5e7eb;">

                <!-- Fiskal chek. Kodlar tasnif.soliq.uz dan olinadi va SHU
                     YERDA turadi: ma'lumotnomadagi kod o'zgarsa, yangi
                     versiya chiqarish kerak bo'lmasin. -->
                <p class="text-muted" style="margin-bottom: 14px;">
                    Fiskal chek uchun kodlar — <code>tasnif.soliq.uz</code> ma'lumotnomasidan.
                </p>
                <div class="form-group">
                    <label>ИКПУ (MXIK)</label><br>
                    <input type="text" name="ofd_mxik"
                           value="<?= htmlspecialchars($ofdMxik) ?>"
                           style="max-width: 280px; margin-top: 6px;">
                </div>
                <div class="form-group" style="margin-top: 14px;">
                    <label>Qadoq kodi (package_code)</label><br>
                    <input type="text" name="ofd_package_code"
                           value="<?= htmlspecialchars($ofdPackageCode) ?>"
                           style="max-width: 280px; margin-top: 6px;">
                </div>
                <div class="form-group" style="margin-top: 14px;">
                    <label>QQS (%)</label><br>
                    <input type="number" name="ofd_vat" min="0" max="100" step="1"
                           value="<?= htmlspecialchars($ofdVat) ?>"
                           style="max-width: 120px; margin-top: 6px;">
                </div>

                <button type="submit" class="btn btn-primary" style="margin-top: 20px;">
                    💾 Saqlash
                </button>
            </form>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>
