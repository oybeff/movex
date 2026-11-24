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
requirePagePerm('settings');
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
    // Audit (S9/S10): faqat haqiqatan o'zgargan kalitlar, eski → yangi.
    $old = settingValue($db, $key, '');
    if ($old !== $value) {
        $GLOBALS['settingChanges']['before'][$key] = $old;
        $GLOBALS['settingChanges']['after'][$key] = $value;
    }
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
    $error = in_array($form, ['bonus', 'rahmat', 'listing_fee', 'app_status', 'cash_deposit', 'compensation'], true)
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
    } elseif ($form === 'app_status') {
        // Ilova holati: majburiy yangilanish (U2) va texnik ishlar (U3).
        // Server bularni /settings/app-status orqali beradi.
        $minVersion = trim((string)($_POST['min_app_version'] ?? ''));
        $until = trim((string)($_POST['maintenance_until'] ?? ''));
        if ($minVersion !== '' && !preg_match('/^\d+\.\d+\.\d+$/', $minVersion)) {
            $error = "Versiya 1.2.0 ko'rinishida bo'lsin";
        } elseif (mb_strlen($until) > 40) {
            $error = "Muddat matni juda uzun";
        } elseif (isset($_POST['maintenance']) && settingValue($db, 'maintenance_enabled', '0') !== '1'
                  && mb_strtoupper(trim((string) ($_POST['confirm_text'] ?? ''))) !== 'YOQISH') {
            // S5: xavfli harakat — «YOQISH» deb yozib tasdiqlanadi.
            $error = "Texnik ishlarni yoqish uchun tasdiqlash oynasida «YOQISH» deb yozing";
        } else {
            saveSetting($db, 'min_app_version', $minVersion === '' ? '0.0.0' : $minVersion);
            saveSetting($db, 'maintenance_enabled', isset($_POST['maintenance']) ? '1' : '0');
            saveSetting($db, 'maintenance_until', $until);
            $message = isset($_POST['maintenance'])
                ? "Saqlandi. Ilova hozir «Texnik ishlar» ekranini ko'rsatadi."
                : "Saqlandi.";
            $mChange = $GLOBALS['settingChanges']['after']['maintenance_enabled'] ?? null;
            if ($mChange !== null) {
                auditLog($mChange === '1' ? 'maintenance_on' : 'maintenance_off', 'settings', null,
                         ['until' => $until, 'push' => !empty($_POST['notify_all'])]);
                if ($mChange === '1' && !empty($_POST['notify_all'])) {
                    $msg = trim((string) ($_POST['maintenance_message'] ?? '')) ?: ('Ilovada texnik ishlar olib borilmoqda'
                        . ($until !== '' ? ". Taxminan $until da qayta ishlaydi" : '') . '. Faol buyurtmangiz bekor qilinmaydi.');
                    $r = internalApiPost('/admin-p5/internal/push/campaigns', [
                        'admin_id' => (int) $_SESSION['admin_user_id'], 'title_uz' => 'Texnik ishlar', 'body_uz' => mb_substr($msg, 0, 240),
                        'audience' => ['role' => 'all', 'langs' => ['uz', 'ru']], 'mode' => 'now']);
                    $message .= $r['ok'] ? ' Barcha foydalanuvchilarga xabar yuborildi.' : ' Xabar yuborilmadi: ' . $r['error'];
                }
                unset($GLOBALS['settingChanges']['before']['maintenance_enabled'], $GLOBALS['settingChanges']['after']['maintenance_enabled']);
            }
        }
    } elseif ($form === 'compensation') {
        // Haydovchi ilovasi E1/E7: mijoz texnika yo'lga chiqqandan keyin bekor
        // qilsa yoki kelmasa, egaga shuncha kompensatsiya — mijozning muzlatilgan
        // pulidan (garov yoki eskrou). 0 — o'chirilgan.
        $comp = trim((string)($_POST['compensation'] ?? '0'));
        if ($comp === '') {
            $comp = '0';
        }
        if (!is_numeric($comp) || (float)$comp < 0) {
            $error = "Kompensatsiya manfiy bo'lishi mumkin emas";
        } else {
            saveSetting($db, 'cancel_compensation_amount', (string)(int)round((float)$comp));
            $message = (float)$comp > 0
                ? "Saqlandi. Keyingi bekor qilishlarga qo'llaniladi."
                : "Saqlandi. Kompensatsiya o'chirilgan.";
        }
    } elseif ($form === 'cash_deposit') {
        // Naqd buyurtma garovi: mijoz balansida muzlatiladi, buyurtma
        // tugaganda yoki bekor bo'lganda qaytadi. 0 — garovsiz.
        $cashDeposit = trim((string)($_POST['cash_deposit'] ?? '0'));
        if ($cashDeposit === '') {
            $cashDeposit = '0';
        }
        if (!is_numeric($cashDeposit) || (float)$cashDeposit < 0) {
            $error = "Garov manfiy bo'lishi mumkin emas";
        } else {
            saveSetting($db, 'cash_deposit_amount', (string)(int)round((float)$cashDeposit));
            $message = (float)$cashDeposit > 0
                ? "Saqlandi. Yangi naqd buyurtmalarga qo'llaniladi."
                : "Saqlandi. Naqd buyurtma garovsiz.";
        }
    } elseif ($form === 'listing_fee') {
        // E'lon joylash narxi. 0 — bepul. Shaxsiy narx users.php da.
        $listingFee = trim((string)($_POST['listing_fee'] ?? '0'));
        if ($listingFee === '') {
            $listingFee = '0';
        }
        if (!is_numeric($listingFee) || (float)$listingFee < 0) {
            $error = "E'lon narxi manfiy bo'lishi mumkin emas";
        } else {
            saveSetting($db, 'listing_fee_amount', (string)(int)round((float)$listingFee));
            $message = (float)$listingFee > 0
                ? "Saqlandi. Yangi e'lonlar endi pullik."
                : "Saqlandi. E'lon joylash bepul.";
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

if (!empty($GLOBALS['settingChanges']['after'])) {
    auditLog('settings_changed', 'settings', null, $GLOBALS['settingChanges']);
}

$mode = settingValue($db, 'commission_mode', 'fixed');
$fixed = settingValue($db, 'commission_fixed', '5000');
$percent = settingValue($db, 'commission_percent', '10');

// Ro'yxatdan o'tganlik uchun sovg'a — faqat texnika egalari uchun.
$bonusEnabled = settingValue($db, 'signup_bonus_enabled', '1') === '1';
$bonusAmount = settingValue($db, 'signup_bonus_amount', '50000');

// E'lon joylash narxi ("E'lonlar" bo'limi). 0 — bepul.
$listingFee = settingValue($db, 'listing_fee_amount', '0');
// Standart 50 000 — request_service.CASH_DEPOSIT_DEFAULT bilan bir xil.
$cashDepositAmount = settingValue($db, 'cash_deposit_amount', '50000');
// Standart 0 — compensation_service.amount_setting bilan bir xil (o'chirilgan).
$compensationAmount = settingValue($db, 'cancel_compensation_amount', '0');
$minAppVersion = settingValue($db, 'min_app_version', '0.0.0');
$maintenanceOn = settingValue($db, 'maintenance_enabled', '0') === '1';
$maintenanceUntil = settingValue($db, 'maintenance_until', '');

// S4: versiyalar — ilova har so'rovda X-App-Version yuboradi (1.0.12 dan).
// «Eski versiyada» = minimal versiyadan pastlar: majburiy yangilanish
// ularni to'xtatadi. Faqat 30 kunda faol bo'lganlar sanaladi.
$versionRows = [];
foreach ($db->query("SELECT COALESCE(app_flavor, CASE role WHEN 'owner' THEN 'driver' ELSE 'client' END) AS flavor,
                            COALESCE(app_platform, 'android') AS platform, app_version AS v, COUNT(*) AS n
                       FROM users WHERE role IN ('client','owner') AND app_version IS NOT NULL
                        AND last_seen_at > NOW() - INTERVAL '30 days' AND COALESCE(is_blocked,false) = false
                      GROUP BY 1, 2, 3") as $r) {
    $versionRows[$r['flavor'] . '|' . $r['platform']][$r['v']] = (int) $r['n'];
}
$versionTable = [];
foreach (['client|ios' => 'Mijoz · iOS', 'client|android' => 'Mijoz · Android',
          'driver|ios' => 'Haydovchi · iOS', 'driver|android' => 'Haydovchi · Android'] as $k => $label) {
    $vs = $versionRows[$k] ?? [];
    $total = array_sum($vs);
    $old = 0;
    $latest = null;
    foreach ($vs as $v => $n) {
        if ($latest === null || version_compare($v, $latest, '>')) $latest = $v;
        if (version_compare($v, $minAppVersion, '<')) $old += $n;
    }
    $versionTable[] = ['label' => $label, 'latest' => $latest, 'total' => $total, 'old' => $old, 'vs' => $vs,
                       'pct' => $total ? round($old * 100 / $total, 1) : 0, 'driver' => strpos($k, 'driver') === 0];
}
$noVersion = (int) $db->query("SELECT COUNT(*) FROM users WHERE role IN ('client','owner') AND app_version IS NULL
                                AND COALESCE(is_blocked,false) = false AND phone NOT LIKE 'deleted-%'")->fetchColumn();
// S5: faol buyurtmalar va jarayondagi pul yechishlar
$activeOrdersNow = (int) $db->query("SELECT
      (SELECT COUNT(*) FROM orders WHERE status = 'confirmed' AND finished_at IS NULL)
    + (SELECT COUNT(*) FROM freight_orders WHERE status IN ('searching','accepted','loaded','arrived'))
    + (SELECT COUNT(*) FROM material_orders WHERE delivery_status IN ('searching','accepted','picked_up','arrived'))
    + (SELECT COUNT(*) FROM equipment_requests WHERE mode = 'quick' AND status = 'open')")->fetchColumn();
$payoutsNow = (int) $db->query("SELECT COUNT(*) FROM payout_requests WHERE status IN ('pending','processing')")->fetchColumn();

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

    <div class="card mb-3" style="margin-top: 24px;" id="app-status">
        <div class="card-header">
            <h3 class="card-title">Ilova versiyalari va texnik ishlar</h3>
        </div>
        <div class="card-body">
            <p class="text-muted" style="margin-bottom:14px">Majburiy yangilanish va texnik ishlar rejimi (ilovalardagi U2, U3 holatlari). Server va panel texnik ishlarda ham ishlaydi.</p>
            <div class="table-responsive" style="margin-bottom:16px"><table>
                <thead><tr><th>Ilova</th><th>Joriy (eng yangi)</th><th>Minimal (majburiy)</th><th class="text-right">Eski versiyada</th></tr></thead>
                <tbody>
                <?php foreach ($versionTable as $v): ?>
                    <tr class="<?= $v['old'] && $v['pct'] >= 10 ? 'row-alert' : '' ?>">
                        <td><b><?= $v['label'] ?></b></td>
                        <td class="num"><?= $v['latest'] ? htmlspecialchars($v['latest']) : '<span class="text-muted">—</span>' ?></td>
                        <td class="num"><?= htmlspecialchars($minAppVersion) ?></td>
                        <td class="text-right num"><?php if (!$v['total']): ?><span class="text-muted">ma'lumot yo'q</span>
                            <?php else: ?><?= str_replace('.', ',', (string) $v['pct']) ?>%<small class="sub"><?= $v['old'] ?> / <?= $v['total'] ?> <?= $v['driver'] ? 'haydovchi' : 'foydalanuvchi' ?></small><?php endif; ?></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table></div>
            <p class="form-hint" style="margin:-8px 0 16px">Faqat oxirgi 30 kunda ilovani ochganlar. Versiyani ilova 1.0.12 dan yuboradi — <?= $noVersion ?> ta foydalanuvchi hali eski ilovada yoki ilovani ochmagan.</p>
            <form method="POST" action="" id="appStatusForm" data-dirty-guard>
                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                <input type="hidden" name="form" value="app_status">
                <input type="hidden" name="confirm_text" id="confirmText">
                <input type="hidden" name="notify_all" id="notifyAll">
                <div style="display:flex;gap:16px;flex-wrap:wrap;align-items:flex-end">
                    <div class="form-group" style="margin:0"><label for="minVer">Minimal versiya (ikkala ilova)</label>
                        <input type="text" id="minVer" name="min_app_version" placeholder="1.0.0" value="<?= htmlspecialchars($minAppVersion) ?>" style="max-width:160px"></div>
                    <div class="form-group" style="margin:0"><label for="mUntil">Texnik ishlar qachongacha</label>
                        <input type="text" id="mUntil" name="maintenance_until" maxlength="40" placeholder="04:00" value="<?= htmlspecialchars($maintenanceUntil) ?>" style="max-width:160px"></div>
                    <label class="check" style="height:36px"><input type="checkbox" name="maintenance" id="mOn" <?= $maintenanceOn ? 'checked' : '' ?>> Texnik ishlar rejimi</label>
                    <button type="submit" class="btn btn-primary">Saqlash</button>
                </div>
                <div class="banner" id="minVerImpact" hidden style="margin:14px 0 0"><i data-lucide="alert-triangle"></i><div><b></b><span>Yangilamaganlar ilovani ocha olmaydi — avval ularga xabar bering.</span></div></div>
            </form>
        </div>
    </div>

    <!-- S5 · Texnik ishlarni yoqish (tasdiq) -->
    <div class="modal" id="modalMaint" role="dialog" aria-modal="true" aria-labelledby="mtTitle">
        <div class="modal-content" style="max-width:480px">
            <div class="modal-header"><div class="modal-title" id="mtTitle">Texnik ishlar rejimi yoqilsinmi?</div><button class="modal-close" type="button" data-close aria-label="Yopish">×</button></div>
            <div class="modal-body">
                <p>Ikkala ilovada ham yangi buyurtma, to'lov va pul yechish to'xtaydi.</p>
                <div class="banner danger" style="margin:14px 0"><i data-lucide="alert-octagon"></i><div><b>Hozir <?= $activeOrdersNow ?> ta faol buyurtma va <?= $payoutsNow ?> ta pul yechish jarayonda</b>
                    <span>Ilova ularni ham ochmaydi — ish tugagach yoqish yaxshiroq.</span></div></div>
                <label class="check" style="margin-bottom:8px"><input type="checkbox" id="mtPush" checked> Barcha foydalanuvchilarga ilova ichida xabar yuborish</label>
                <div class="form-group"><label for="mtMsg">Xabar matni (UZ)</label>
                    <textarea id="mtMsg" name="maintenance_message" form="appStatusForm" rows="3" maxlength="240">Ilovada texnik ishlar olib borilmoqda. Faol buyurtmangiz bekor qilinmaydi.</textarea></div>
                <div class="form-group"><label for="mtType">Tasdiqlash uchun <b>YOQISH</b> deb yozing</label>
                    <input id="mtType" autocomplete="off"></div>
            </div>
            <div class="modal-footer"><button class="btn btn-secondary" type="button" data-close>Bekor</button>
                <button class="btn btn-danger" type="button" id="mtGo" disabled>Rejimni yoqish</button></div>
        </div>
    </div>
    <script>
    (() => {
        const f = document.getElementById('appStatusForm'), on = document.getElementById('mOn');
        const wasOn = <?= $maintenanceOn ? 'true' : 'false' ?>;
        const vt = <?= json_encode(array_map(fn($v) => (object) $v['vs'], $versionTable)) ?>;
        const cmp = (a, b) => { const x = a.split('.').map(Number), y = b.split('.').map(Number);
            for (let i = 0; i < 3; i++) { if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) - (y[i] || 0); } return 0; };
        const minVer = document.getElementById('minVer'), imp = document.getElementById('minVerImpact');
        minVer.addEventListener('input', () => {
            const m = minVer.value.trim();
            if (!/^\d+\.\d+\.\d+$/.test(m)) { imp.hidden = true; return; }
            let n = 0, t = 0;
            vt.forEach(vs => Object.entries(vs).forEach(([v, c]) => { t += c; if (cmp(v, m) < 0) n += c; }));
            imp.hidden = n === 0;
            imp.querySelector('b').textContent = n + ' ta foydalanuvchi (' + (t ? Math.round(n * 1000 / t) / 10 : 0) + '%) yangilamaguncha ilovadan foydalana olmaydi';
        });
        f.addEventListener('submit', e => {
            if (on.checked && !wasOn && !document.getElementById('confirmText').value) {
                e.preventDefault();
                document.getElementById('modalMaint').classList.add('active');
                document.getElementById('mtType').focus();
            }
        });
        const t = document.getElementById('mtType'), go = document.getElementById('mtGo');
        t.addEventListener('input', () => go.disabled = t.value.trim().toUpperCase() !== 'YOQISH');
        go.addEventListener('click', () => {
            document.getElementById('confirmText').value = t.value.trim();
            document.getElementById('notifyAll').value = document.getElementById('mtPush').checked ? '1' : '';
            f.requestSubmit();
        });
    })();
    </script>

    <div class="card mb-3" style="margin-top: 24px;">
        <div class="card-header">
            <h3 class="card-title">E'lon joylash narxi</h3>
        </div>
        <div class="card-body">
            <div class="alert alert-info" style="margin-bottom: 18px;">
                Faqat <strong>«E'lonlar»</strong> bo'limi uchun. Pul e'lon joylanganda
                balansdan yechiladi (sovg'a ham ishlatiladi). <strong>0 — bepul.</strong>
                Alohida odamga boshqa narx yoki bepul joylashni
                «Foydalanuvchilar» → «Boshqarish» da qo'yish mumkin.
            </div>
            <form method="POST" action="">
                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                <input type="hidden" name="form" value="listing_fee">
                <div class="form-group">
                    <label>Bitta e'lon narxi</label><br>
                    <input type="number" name="listing_fee" min="0" step="1000"
                           value="<?= htmlspecialchars($listingFee) ?>"
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
            <h3 class="card-title">Naqd buyurtma garovi</h3>
        </div>
        <div class="card-body">
            <div class="alert alert-info" style="margin-bottom: 18px;">
                Mijoz <strong>naqd pul</strong> bilan texnika chaqirsa, shuncha summa uning
                balansida <strong>muzlatiladi</strong>. Ega buyurtmani yakunlaganda yoki
                buyurtma bekor bo'lganda garov qaytadi. Balansda yetmasa — naqd buyurtma
                berib bo'lmaydi. <strong>0 — garovsiz.</strong> Yangi buyurtmalarga qo'llaniladi.
            </div>
            <form method="POST" action="">
                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                <input type="hidden" name="form" value="cash_deposit">
                <div class="form-group">
                    <label>Garov summasi</label><br>
                    <input type="number" name="cash_deposit" min="0" step="1000"
                           value="<?= htmlspecialchars($cashDepositAmount) ?>"
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
            <h3 class="card-title">Bekor qilish uchun kompensatsiya</h3>
        </div>
        <div class="card-body">
            <div class="alert alert-info" style="margin-bottom: 18px;">
                Texnika egasi <strong>yo'lga chiqqandan keyin</strong> mijoz buyurtmani bekor
                qilsa, yoki ega joyida <strong>15 daqiqa</strong> kutib mijoz kelmasa — egaga
                shuncha summa o'tadi. Pul mijozning shu buyurtma uchun
                <strong>muzlatilgan</strong> summasidan olinadi (naqd buyurtmada — garovdan,
                balans bilan to'langanda — eskroudan), undan ortiq emas. Karta bilan
                to'langan buyurtmada kompensatsiya yo'q. <strong>0 — o'chirilgan.</strong>
            </div>
            <form method="POST" action="">
                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                <input type="hidden" name="form" value="compensation">
                <div class="form-group">
                    <label>Kompensatsiya summasi</label><br>
                    <input type="number" name="compensation" min="0" step="1000"
                           value="<?= htmlspecialchars($compensationAmount) ?>"
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
