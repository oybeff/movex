<?php
/**
 * Tariflar — «taksi kabi» buyurtma (ikkinchi maket, 12.11.2026).
 *
 * Mijoz texnika turini, tarifni va soatlarni tanlaydi va narxni darhol
 * ko'radi. Narxni ADMIN qo'yadi (egasi qarori): har bir tur uchun uchta
 * tarif — Ekonom, Tezkor, Kun davomida — soatlik narx bilan, va eng kam
 * buyurtma soati.
 *
 * Narx bo'sh qoldirilsa — o'sha tarif o'chadi (ilovada ko'rinmaydi).
 * Uchalasi ham bo'sh bo'lsa, bu tur «taksi» oqimida umuman yo'q.
 *
 * Qo'shimcha jihoz (kovsh, gidromolot) — soatiga ustama. 0 — «narxga
 * kiritilgan».
 *
 * DIQQAT: hisob-kitob backend'da (tariff_service.py). Bu sahifa faqat
 * tariffs va equipment_attachments jadvallarini o'zgartiradi.
 */
require_once 'config.php';
requireAdmin();
requirePagePerm('settings');
requireCsrfToken();

$pageTitle = 'Tariflar';
$currentPage = 'tariffs';

$db = getDbConnection();

// Turlar — catalog.php dan (admin yangi tur qo'shsa, shu yerda ham chiqadi).
$types = equipmentTypeCodes();
// Paket tariflar (Sherzodbek 24.11.2026): narx — PAKET uchun, soatlar qat'iy.
// Ekonom — soatbay. Soatlik narx (uzaytirish uchun) paketdan hisoblanadi.
$packageHours = ['fast' => 6, 'day' => 12];
$tiers = [
    'econom' => 'Ekonom',
    'fast'   => 'Tezkor',
    'day'    => 'Kun davomida',
];

$message = null;
$error = null;

/** Bo'sh — null, aks holda musbat butun son yoki false (xato). */
function parsePrice(string $raw) {
    $raw = preg_replace('/\s+/', '', $raw);
    if ($raw === '') {
        return null;
    }
    if (!ctype_digit($raw) || (int)$raw <= 0) {
        return false;
    }
    return (int)$raw;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $form = $_POST['form'] ?? '';

    if ($form === 'tariffs') {
        $type = (string)($_POST['equipment_type'] ?? '');
        $minHours = (string)($_POST['min_hours'] ?? '1');
        if (!in_array($type, $types, true)) {
            $error = "Noma'lum texnika turi";
        } elseif (!ctype_digit($minHours) || (int)$minHours < 1 || (int)$minHours > 24) {
            $error = 'Eng kam soat 1 dan 24 gacha bo\'lsin';
        } else {
            $prices = [];
            $etas = [];
            foreach ($tiers as $tier => $label) {
                $p = parsePrice((string)($_POST['price_' . $tier] ?? ''));
                if ($p === false) {
                    $error = "$label narxi musbat butun son bo'lsin (yoki bo'sh)";
                    break;
                }
                $prices[$tier] = $p;
                // Kelish vaqti, daqiqa: «45 daqiqada keladi». Bo'sh — yozuvsiz.
                $eRaw = trim((string)($_POST['eta_' . $tier] ?? ''));
                if ($eRaw !== '' && (!ctype_digit($eRaw) || (int)$eRaw < 1 || (int)$eRaw > 1440)) {
                    $error = "$label: kelish vaqti 1–1440 daqiqa bo'lsin (yoki bo'sh)";
                    break;
                }
                $etas[$tier] = $eRaw === '' ? null : (int)$eRaw;
            }
            if ($error === null) {
                $bst = $db->prepare('SELECT tier, COALESCE(package_price, price_per_hour) AS p, min_hours, eta_minutes FROM tariffs WHERE equipment_type = ?');
                $bst->execute([$type]);
                $tBefore = [];
                foreach ($bst as $br) $tBefore[$br['tier']] = $br;
                $aBefore = $aAfter = [];
                foreach ($prices as $tier => $p) {
                    $lab = $tiers[$tier];
                    $ob = isset($tBefore[$tier]) ? (int) $tBefore[$tier]['p'] : null;
                    if ($ob !== $p) { $aBefore["$lab: narx"] = $ob; $aAfter["$lab: narx"] = $p; }
                    $oe = isset($tBefore[$tier]['eta_minutes']) ? (int) $tBefore[$tier]['eta_minutes'] : null;
                    if ($p !== null && $oe !== $etas[$tier]) { $aBefore["$lab: kelish, daq"] = $oe; $aAfter["$lab: kelish, daq"] = $etas[$tier]; }
                }
                $db->beginTransaction();
                foreach ($prices as $tier => $p) {
                    if ($p === null) {
                        $db->prepare('DELETE FROM tariffs WHERE equipment_type = ? AND tier = ?')
                           ->execute([$type, $tier]);
                        continue;
                    }
                    $ph = $packageHours[$tier] ?? null;
                    $db->prepare('
                        INSERT INTO tariffs (equipment_type, tier, price_per_hour, min_hours, eta_minutes, is_active,
                                             package_hours, package_price)
                        VALUES (?, ?, ?, ?, ?, true, ?, ?)
                        ON CONFLICT (equipment_type, tier)
                        DO UPDATE SET price_per_hour = EXCLUDED.price_per_hour,
                                      min_hours = EXCLUDED.min_hours,
                                      eta_minutes = EXCLUDED.eta_minutes,
                                      package_hours = EXCLUDED.package_hours,
                                      package_price = EXCLUDED.package_price,
                                      is_active = true,
                                      updated_at = NOW()
                    ')->execute([$type, $tier,
                                 $ph ? (int) round($p / $ph) : $p,
                                 $ph ?: (int)$minHours,
                                 $etas[$tier],
                                 $ph, $ph ? $p : null]);
                }
                $db->commit();
                if ($aAfter) auditLog('tariff_changed', 'tariff', null, ['type' => equipmentTypeName($type), 'before' => $aBefore, 'after' => $aAfter]);
                $message = equipmentTypeName($type) . ' — saqlandi. Yangi buyurtmalarga darhol qo\'llaniladi.';
            }
        }
    } elseif ($form === 'attachment_add') {
        $type = (string)($_POST['equipment_type'] ?? '');
        $nameUz = trim((string)($_POST['name_uz'] ?? ''));
        $nameRu = trim((string)($_POST['name_ru'] ?? ''));
        $priceRaw = preg_replace('/\s+/', '', (string)($_POST['price'] ?? '0'));
        if (!in_array($type, $types, true)) {
            $error = "Noma'lum texnika turi";
        } elseif ($nameUz === '' || $nameRu === '' || mb_strlen($nameUz) > 100 || mb_strlen($nameRu) > 100) {
            $error = 'Ikkala tildagi nomni yozing (100 belgigacha)';
        } elseif ($priceRaw !== '' && !ctype_digit($priceRaw)) {
            $error = "Ustama 0 yoki musbat butun son bo'lsin";
        } else {
            $sort = (int)$db->query('SELECT COALESCE(MAX(sort_order), 0) + 1 FROM equipment_attachments')->fetchColumn();
            $db->prepare('
                INSERT INTO equipment_attachments (equipment_type, name_uz, name_ru, price_per_hour, sort_order)
                VALUES (?, ?, ?, ?, ?)
            ')->execute([$type, $nameUz, $nameRu, (int)$priceRaw, $sort]);
            $message = "Jihoz qo'shildi.";
        }
    } elseif ($form === 'attachment_toggle') {
        $id = (int)($_POST['id'] ?? 0);
        $db->prepare('UPDATE equipment_attachments SET is_active = NOT is_active WHERE id = ?')->execute([$id]);
        $message = 'Saqlandi.';
    } elseif ($form === 'attachment_delete') {
        // Eski buyurtmalarda attachment_id SET NULL bo'ladi, narxi esa
        // equipment_requests.attachment_price da saqlanib qoladi.
        $id = (int)($_POST['id'] ?? 0);
        $db->prepare('DELETE FROM equipment_attachments WHERE id = ?')->execute([$id]);
        $message = "Jihoz o'chirildi.";
    }
}

$rows = $db->query('SELECT equipment_type, tier, price_per_hour, min_hours, eta_minutes, package_hours, package_price, is_active FROM tariffs')->fetchAll();
$tariffs = [];
foreach ($rows as $r) {
    $tariffs[$r['equipment_type']][$r['tier']] = $r;
}

$attachments = $db->query('
    SELECT id, equipment_type, name_uz, name_ru, price_per_hour, is_active
      FROM equipment_attachments
     ORDER BY equipment_type, sort_order, id
')->fetchAll();

$cashOrders = $db->query("
    SELECT COUNT(*) AS cnt, COALESCE(SUM(owner_frozen), 0) AS frozen
      FROM orders
     WHERE payment_method = 'cash' AND status = 'confirmed'
")->fetch();

include 'includes/header.php';

function money($v) {
    return number_format((float)$v, 0, '.', ' ');
}
?>

<div class="content">
    <div class="page-head">
        <div><h2>Tariflar va narxlar</h2>
            <div class="sub">Texnika turi bo'yicha narxlar · <?= count($tariffs) ?> / <?= count($types) ?> turda tarif bor · faol naqd buyurtmalar: <?= (int)$cashOrders['cnt'] ?></div></div>
        <div class="page-actions"><a class="btn btn-secondary" href="audit.php?section=Sozlamalar&amp;period=30d"><i data-lucide="history"></i> O'zgarishlar tarixi</a></div>
    </div>
    <?php if ($message): ?><div class="alert alert-success"><?= htmlspecialchars($message) ?></div><?php endif; ?>
    <?php if ($error): ?><div class="alert alert-danger"><?= htmlspecialchars($error) ?></div><?php endif; ?>

    <div class="banner banner-info"><i data-lucide="info"></i>
        <div><b>Faol buyurtmalar eski narxda yakunlanadi</b>
            <span>O'zgarish saqlangan paytdan boshlab yangi buyurtmalarga qo'llanadi va audit jurnaliga yoziladi. Ekonom — soatbay: (narx + jihoz ustamasi) × soat; Tezkor — 6 soatlik, Kun davomida — 12 soatlik paket narxi. Narxni bo'sh qoldirsangiz, o'sha tarif o'chadi. Komissiya — <a href="commission.php">Sozlamalar</a>.</span></div></div>

    <div class="card">
        <div class="table-responsive"><table class="tariff-table">
            <thead><tr>
                <th>Texnika turi</th>
                <?php foreach ($tiers as $tier => $label): ?>
                    <th class="text-right"><?= htmlspecialchars($label) ?><small class="sub"><?= isset($packageHours[$tier]) ? $packageHours[$tier] . ' soat paketi · kelish, daq' : "so'm/soat · kelish, daq" ?></small></th>
                <?php endforeach; ?>
                <th class="text-right">Min. soat</th><th>Holat</th>
            </tr></thead>
            <tbody>
            <?php foreach ($types as $type):
                $t = $tariffs[$type] ?? [];
                $min = isset($t['econom']) ? (int)$t['econom']['min_hours'] : 1;
                $formId = 'tf_' . $type;
                $activeTiers = count(array_filter($t, function ($x) { return $x['is_active']; }));
            ?>
                <tr data-form="<?= $formId ?>" data-name="<?= htmlspecialchars(equipmentTypeName($type)) ?>">
                    <td><b><?= htmlspecialchars(equipmentTypeName($type)) ?></b>
                        <form id="<?= $formId ?>" method="POST" action="" class="tariff-form">
                            <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                            <input type="hidden" name="form" value="tariffs">
                            <input type="hidden" name="equipment_type" value="<?= htmlspecialchars($type) ?>">
                        </form></td>
                    <?php foreach ($tiers as $tier => $label):
                        $off = isset($t[$tier]) && !$t[$tier]['is_active']; ?>
                        <td class="text-right">
                            <input class="cell-input" form="<?= $formId ?>" type="text" inputmode="numeric" name="price_<?= $tier ?>"
                                   value="<?= isset($t[$tier]) && $t[$tier]['is_active'] ? (int)($t[$tier]['package_price'] ?? $t[$tier]['price_per_hour']) : '' ?>"
                                   placeholder="<?= $off ? "o'chirilgan" : '—' ?>" aria-label="<?= htmlspecialchars(equipmentTypeName($type) . ' — ' . $label) ?>">
                            <input class="cell-input cell-sub" form="<?= $formId ?>" type="text" inputmode="numeric" name="eta_<?= $tier ?>"
                                   value="<?= isset($t[$tier]['eta_minutes']) ? (int)$t[$tier]['eta_minutes'] : '' ?>"
                                   placeholder="kelish, daq" title="N daqiqada keladi. Bo'sh — yozuvsiz">
                        </td>
                    <?php endforeach; ?>
                    <td class="text-right"><input class="cell-input" form="<?= $formId ?>" type="number" min="1" max="24" name="min_hours" value="<?= $min ?>" style="width:64px"></td>
                    <td><span class="badge badge-<?= $activeTiers ? 'success' : 'secondary' ?>"><?= $activeTiers ? 'Faol' : 'Nofaol' ?></span>
                        <?php if (!$activeTiers): ?><small class="sub">ilovada ko'rinmaydi</small><?php endif; ?></td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table></div>
    </div>

    <div class="unsaved-bar" id="unsavedBar" hidden>
        <i data-lucide="alert-triangle"></i>
        <span id="unsavedText"></span>
        <button type="button" class="link-btn" id="unsavedCancel">Bekor qilish</button>
        <button type="button" class="btn btn-warning" id="unsavedSave">Saqlash</button>
    </div>
    <script>
    (function () {
        var rows = Array.prototype.slice.call(document.querySelectorAll('.tariff-table tr[data-form]'));
        var init = new Map();
        rows.forEach(function (r) { r.querySelectorAll('input.cell-input').forEach(function (i) { init.set(i, i.value); }); });
        var bar = document.getElementById('unsavedBar'), txt = document.getElementById('unsavedText');
        function changed() {
            return rows.filter(function (r) {
                return Array.prototype.some.call(r.querySelectorAll('input.cell-input'), function (i) { return i.value !== init.get(i); });
            });
        }
        function fmt(v) { return v === '' ? '—' : Number(v).toLocaleString('ru-RU').replace(/,/g, ' '); }
        function sync() {
            var c = changed();
            rows.forEach(function (r) { r.classList.toggle('row-editing', c.indexOf(r) >= 0); });
            bar.hidden = !c.length;
            if (!c.length) return;
            var first = c[0];
            var inp = Array.prototype.find.call(first.querySelectorAll('input.cell-input'), function (i) { return i.value !== init.get(i); });
            txt.textContent = c.length + ' ta qator saqlanmagan · ' + first.dataset.name + ': ' + fmt(init.get(inp)) + ' → ' + fmt(inp.value);
        }
        document.querySelector('.tariff-table').addEventListener('input', sync);
        document.getElementById('unsavedCancel').addEventListener('click', function () { init.forEach(function (v, i) { i.value = v; }); sync(); });
        window.addEventListener('beforeunload', function (e) { if (changed().length) { e.preventDefault(); e.returnValue = ''; } });
        document.getElementById('unsavedSave').addEventListener('click', async function () {
            var c = changed(), btn = this;
            btn.disabled = true;
            for (var k = 0; k < c.length; k++) {
                var r = c[k];
                var res = await fetch(location.pathname, { method: 'POST', body: new FormData(document.getElementById(r.dataset.form)) });
                var html = await res.text();
                var err = html.match(/<div class="alert alert-danger">([^<]*)<\/div>/);
                if (err) { showNotification(r.dataset.name + ': ' + err[1], 'error'); btn.disabled = false; return; }
            }
            c.forEach(function (r) { r.querySelectorAll('input.cell-input').forEach(function (i) { init.set(i, i.value); }); });
            sessionStorage.setItem('tariffSaved', String(c.length));
            location.reload();
        });
        var saved = sessionStorage.getItem('tariffSaved');
        if (saved) {
            sessionStorage.removeItem('tariffSaved');
            document.addEventListener('DOMContentLoaded', function () { showNotification(saved + " ta tur saqlandi — yangi buyurtmalarga qo'llanadi", 'success'); });
        }
    })();
    </script>

    <div class="card mb-3">
        <div class="card-header">
            <h3 class="card-title">Qo'shimcha jihozlar</h3>
        </div>
        <div class="card-body">
            <form method="POST" action="" style="display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end;margin-bottom:16px">
                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                <input type="hidden" name="form" value="attachment_add">
                <label>Texnika<br>
                    <select name="equipment_type">
                        <?php foreach ($types as $type): ?>
                            <option value="<?= htmlspecialchars($type) ?>"><?= htmlspecialchars(equipmentTypeName($type)) ?></option>
                        <?php endforeach; ?>
                    </select>
                </label>
                <label>Nomi (uz)<br><input type="text" name="name_uz" maxlength="100" placeholder="Gidromolot"></label>
                <label>Nomi (ru)<br><input type="text" name="name_ru" maxlength="100" placeholder="Гидромолот"></label>
                <label>Ustama, so'm/soat<br><input type="text" inputmode="numeric" name="price" value="0" style="width:120px"></label>
                <button type="submit" class="btn btn-primary">Qo'shish</button>
            </form>

            <?php if (!$attachments): ?>
                <p style="color:#6b7280">Hali jihoz qo'shilmagan.</p>
            <?php else: ?>
                <table>
                    <thead>
                        <tr><th>Texnika</th><th>Nomi</th><th>Ustama</th><th>Holati</th><th></th></tr>
                    </thead>
                    <tbody>
                    <?php foreach ($attachments as $a): ?>
                        <tr>
                            <td><?= htmlspecialchars(equipmentTypeName($a['equipment_type'])) ?></td>
                            <td><?= htmlspecialchars($a['name_uz']) ?> / <?= htmlspecialchars($a['name_ru']) ?></td>
                            <td><?= (float)$a['price_per_hour'] > 0 ? '+' . money($a['price_per_hour']) . " so'm/soat" : 'narxga kiritilgan' ?></td>
                            <td><?= $a['is_active'] ? 'Faol' : "O'chirilgan" ?></td>
                            <td style="display:flex;gap:6px">
                                <form method="POST" action="">
                                    <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                    <input type="hidden" name="form" value="attachment_toggle">
                                    <input type="hidden" name="id" value="<?= (int)$a['id'] ?>">
                                    <button type="submit" class="btn btn-sm"><?= $a['is_active'] ? "O'chirish" : 'Yoqish' ?></button>
                                </form>
                                <form method="POST" action="">
                                    <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                    <input type="hidden" name="form" value="attachment_delete">
                                    <input type="hidden" name="id" value="<?= (int)$a['id'] ?>">
                                    <button type="submit" class="btn btn-danger-outline btn-sm" name="do" value="1" data-confirm="Jihoz olib tashlansinmi?">Olib tashlash</button>
                                </form>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            <?php endif; ?>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>
