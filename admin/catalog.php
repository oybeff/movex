<?php
/**
 * Katalog — texnika turlari, yetkazib berish mashinalari va «Qurilish
 * materiallari» bo'limi (23.11.2026, Sherzodbek: «ko'p nastroykalarni
 * admin panel orqali qilishni qo'shib qo'ying»).
 *
 * Texnika turlari (equipment_catalog): nomi uz/ru, guruh («Barcha
 * kategoriyalar» ekranidagi bo'lim), qisqa izoh, ikonka, yoqish/o'chirish,
 * tartib. Yangi tur shu yerda qo'shiladi va ilovada yangi versiyasiz
 * chiqadi. KOD keyin o'zgarmaydi — u buyurtmalarda saqlanadi.
 *
 * Ikonka backend orqali saqlanadi (internalApiUpload): media/ papkasiga
 * backend yozadi, fayl nomini ham u qo'yadi.
 *
 * Mashinalar (delivery_vehicles): material yetkazish. Yetkazish narxi =
 * (podacha + km × narx) × reys. Km narxi bo'sh — sotuvchi tovarga yozgan
 * km narxi olinadi (eski qoida).
 */
require_once 'config.php';
requireAdmin();
requireCsrfToken();

$pageTitle = 'Katalog';
$currentPage = 'catalog';

$db = getDbConnection();

$groups = [
    'earth'     => 'Yer ishlari',
    'lifting'   => "Ko'tarish",
    'transport' => 'Tashish',
    'concrete'  => 'Beton ishlari',
    'other'     => 'Boshqa',
];

$message = null;
$error = null;

// «Yuk tashish» (Y1–Y8): sinf va kuzov turlari
$sizeClasses = ['small' => 'Kichik', 'medium' => "O'rta", 'large' => 'Katta', 'trailer' => 'Fura va tirkama'];
$bodyTypes = [
    'tent' => 'Tentli', 'open' => 'Bortli', 'van' => 'Furgon', 'isothermal' => 'Izotermik',
    'fridge' => 'Muzlatkichli', 'tank' => 'Sisterna', 'manipulator' => 'Manipulyator',
];

function settingOn(PDO $db, string $key): bool {
    $stmt = $db->prepare('SELECT value FROM app_settings WHERE key = ?');
    $stmt->execute([$key]);
    $v = $stmt->fetchColumn();
    if ($v === false || $v === null) return true;
    $d = json_decode((string)$v, true);
    return !in_array((string)($d ?? $v), ['0', 'false'], true);
}

function cleanInt(string $raw) {
    $raw = preg_replace('/\s+/', '', $raw);
    if ($raw === '') return null;
    if (!ctype_digit($raw)) return false;
    return (int)$raw;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $form = $_POST['form'] ?? '';

    if ($form === 'loader_fee') {
        $fee = cleanInt((string)($_POST['fee'] ?? ''));
        if ($fee === false || $fee === null) {
            $error = "Yuklovchi narxi — 0 yoki musbat butun son";
        } else {
            $db->prepare("
                INSERT INTO app_settings (key, value) VALUES ('freight_loader_fee', to_jsonb(?::text))
                ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()
            ")->execute([(string)$fee]);
            $message = 'Yuklovchi narxi saqlandi: ' . number_format($fee, 0, '.', ' ') . " so'm.";
        }
    } elseif ($form === 'materials_toggle') {
        $on = isset($_POST['enabled']) ? '1' : '0';
        $db->prepare("
            INSERT INTO app_settings (key, value) VALUES ('materials_enabled', to_jsonb(?::text))
            ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()
        ")->execute([$on]);
        $message = $on === '1'
            ? "«Qurilish materiallari» yoqildi — ilovada ko'rinadi."
            : "«Qurilish materiallari» o'chirildi — ilovada ko'rinmaydi, buyurtma berib bo'lmaydi.";

    } elseif ($form === 'type_save' || $form === 'type_add') {
        $code = strtolower(trim((string)($_POST['code'] ?? '')));
        $nameUz = trim((string)($_POST['name_uz'] ?? ''));
        $nameRu = trim((string)($_POST['name_ru'] ?? ''));
        $group = (string)($_POST['group_code'] ?? 'other');
        $subUz = trim((string)($_POST['subtitle_uz'] ?? ''));
        $subRu = trim((string)($_POST['subtitle_ru'] ?? ''));
        $sort = cleanInt((string)($_POST['sort_order'] ?? '0'));

        if (!preg_match('/^[a-z][a-z0-9_]{1,38}$/', $code)) {
            $error = "Kod — lotin kichik harflar, raqam va _ (masalan, vacuum_truck)";
        } elseif ($nameUz === '' || $nameRu === '' || mb_strlen($nameUz) > 100 || mb_strlen($nameRu) > 100) {
            $error = 'Ikkala tildagi nomni yozing (100 belgigacha)';
        } elseif (!isset($groups[$group])) {
            $error = "Noma'lum guruh";
        } elseif (mb_strlen($subUz) > 150 || mb_strlen($subRu) > 150) {
            $error = 'Izoh 150 belgigacha';
        } elseif ($sort === false) {
            $error = 'Tartib — butun son';
        } elseif ($form === 'type_add') {
            $exists = $db->prepare('SELECT 1 FROM equipment_catalog WHERE code = ?');
            $exists->execute([$code]);
            if ($exists->fetchColumn()) {
                $error = 'Bu kod band';
            } else {
                $db->prepare('
                    INSERT INTO equipment_catalog (code, name_uz, name_ru, group_code, subtitle_uz, subtitle_ru, sort_order)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                ')->execute([$code, $nameUz, $nameRu, $group, $subUz ?: null, $subRu ?: null, (int)$sort]);
                $message = "«$nameUz» qo'shildi. Ilovada ko'rinishi uchun ikonka yuklang va Tariflar sahifasida narx qo'ying.";
            }
        } else {
            $db->prepare('
                UPDATE equipment_catalog
                   SET name_uz = ?, name_ru = ?, group_code = ?, subtitle_uz = ?, subtitle_ru = ?,
                       sort_order = ?, updated_at = NOW()
                 WHERE code = ?
            ')->execute([$nameUz, $nameRu, $group, $subUz ?: null, $subRu ?: null, (int)$sort, $code]);
            $message = "«$nameUz» saqlandi.";
        }

    } elseif ($form === 'type_toggle') {
        $db->prepare('UPDATE equipment_catalog SET is_enabled = NOT is_enabled, updated_at = NOW() WHERE code = ?')
           ->execute([(string)($_POST['code'] ?? '')]);
        $message = "Saqlandi. Ilovada yarim daqiqada yangilanadi.";

    } elseif ($form === 'type_icon') {
        $code = (string)($_POST['code'] ?? '');
        $f = $_FILES['icon'] ?? null;
        if (!$f || ($f['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
            $error = 'Rasm tanlanmagan';
        } else {
            $res = internalApiUpload(
                '/equipment/internal/catalog/' . rawurlencode($code) . '/icon',
                $f['tmp_name'], (string)$f['name'], (string)($f['type'] ?: 'image/png')
            );
            if ($res['ok']) {
                $message = 'Ikonka yuklandi.';
            } else {
                $error = 'Ikonka yuklanmadi: ' . $res['error'];
            }
        }

    } elseif ($form === 'vehicle_save' || $form === 'vehicle_add') {
        $code = strtolower(trim((string)($_POST['code'] ?? '')));
        $name = trim((string)($_POST['name'] ?? ''));
        $kg = cleanInt((string)($_POST['capacity_kg'] ?? ''));
        $volRaw = str_replace(',', '.', trim((string)($_POST['volume_m3'] ?? '')));
        $base = cleanInt((string)($_POST['base_fee'] ?? '0'));
        $km = cleanInt((string)($_POST['price_per_km'] ?? ''));
        $sort = cleanInt((string)($_POST['sort_order'] ?? '0'));
        // «Yuk tashish»: как считать перевозку и есть ли выбор кузова
        $mode = ($_POST['price_mode'] ?? 'km') === 'hour' ? 'hour' : 'km';
        $perHour = cleanInt((string)($_POST['price_per_hour'] ?? ''));
        $minHours = cleanInt((string)($_POST['min_hours'] ?? '1'));
        $brand = trim((string)($_POST['brand'] ?? ''));
        $sizeClass = (string)($_POST['size_class'] ?? 'medium');
        $dims = [];
        foreach (['body_length_m', 'body_width_m', 'body_height_m'] as $dk) {
            $raw = str_replace(',', '.', trim((string)($_POST[$dk] ?? '')));
            $dims[$dk] = ($raw === '' || !is_numeric($raw) || (float)$raw <= 0) ? null : $raw;
        }
        $bodies = array_values(array_intersect(array_keys($bodyTypes), (array)($_POST['body_types'] ?? [])));
        $bodiesCsv = implode(',', $bodies);
        // Tanlov — kuzov turi bittadan ko'p bo'lsa
        $bodyChoice = count($bodies) > 1 ? 'true' : 'false';

        if (!preg_match('/^[a-z][a-z0-9_]{1,19}$/', $code)) {
            $error = 'Kod — lotin kichik harflar, raqam va _ (20 belgigacha)';
        } elseif ($name === '' || mb_strlen($name) > 60) {
            $error = 'Mashina nomini yozing (60 belgigacha)';
        } elseif (!$kg) {
            $error = "Sig'im, kg — musbat butun son";
        } elseif ($volRaw !== '' && (!is_numeric($volRaw) || (float)$volRaw <= 0)) {
            $error = 'Kuzov hajmi, m³ — musbat son yoki bo\'sh';
        } elseif ($base === false || $km === false || $sort === false || $perHour === false) {
            $error = 'Narxlar va tartib — butun son';
        } elseif (!isset($sizeClasses[$sizeClass])) {
            $error = "Noma'lum sinf";
        } elseif (mb_strlen($brand) > 40) {
            $error = 'Marka 40 belgigacha';
        } elseif (!$minHours || $minHours > 48) {
            $error = 'Eng kam soat 1 dan 48 gacha';
        } elseif ($mode === 'hour' && !$perHour) {
            $error = "«Soatbay» rejimida soat narxini yozing";
        } elseif ($form === 'vehicle_add') {
            $exists = $db->prepare('SELECT 1 FROM delivery_vehicles WHERE code = ?');
            $exists->execute([$code]);
            if ($exists->fetchColumn()) {
                $error = 'Bu kod band';
            } else {
                $db->prepare('
                    INSERT INTO delivery_vehicles (code, name, capacity_kg, volume_m3, base_fee, price_per_km, sort_order,
                                                   price_mode, price_per_hour, min_hours, has_body_choice,
                                                   brand, size_class, body_length_m, body_width_m, body_height_m, body_types)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ' . $bodyChoice . ', ?, ?, ?, ?, ?, ?)
                ')->execute([$code, $name, $kg, $volRaw === '' ? null : $volRaw, (int)$base, $km, (int)$sort,
                             $mode, $perHour, (int)$minHours, $brand ?: null, $sizeClass,
                             $dims['body_length_m'], $dims['body_width_m'], $dims['body_height_m'], $bodiesCsv]);
                $message = "«$name» qo'shildi.";
            }
        } else {
            $db->prepare('
                UPDATE delivery_vehicles
                   SET name = ?, capacity_kg = ?, volume_m3 = ?, base_fee = ?, price_per_km = ?, sort_order = ?,
                       price_mode = ?, price_per_hour = ?, min_hours = ?, has_body_choice = ' . $bodyChoice . ',
                       brand = ?, size_class = ?, body_length_m = ?, body_width_m = ?, body_height_m = ?, body_types = ?
                 WHERE code = ?
            ')->execute([$name, $kg, $volRaw === '' ? null : $volRaw, (int)$base, $km, (int)$sort,
                         $mode, $perHour, (int)$minHours, $brand ?: null, $sizeClass,
                         $dims['body_length_m'], $dims['body_width_m'], $dims['body_height_m'], $bodiesCsv, $code]);
            $message = "«$name» saqlandi.";
        }

    } elseif ($form === 'vehicle_toggle') {
        $db->prepare('UPDATE delivery_vehicles SET is_enabled = NOT is_enabled WHERE code = ?')
           ->execute([(string)($_POST['code'] ?? '')]);
        $message = 'Saqlandi.';
    }
}

$materialsOn = settingOn($db, 'materials_enabled');
$loaderStmt = $db->query("SELECT value FROM app_settings WHERE key = 'freight_loader_fee'");
$loaderRaw = $loaderStmt ? $loaderStmt->fetchColumn() : false;
$loaderFee = $loaderRaw === false ? 0 : (int)json_decode((string)$loaderRaw, true);
$types = $db->query('
    SELECT c.*, EXISTS (SELECT 1 FROM tariffs t WHERE t.equipment_type = c.code AND t.is_active) AS has_tariff
      FROM equipment_catalog c
     ORDER BY c.sort_order, c.code
')->fetchAll();
$vehicles = $db->query('SELECT * FROM delivery_vehicles ORDER BY capacity_kg, sort_order')->fetchAll();

include 'includes/header.php';

function money($v) {
    return number_format((float)$v, 0, '.', ' ');
}
?>

<div class="content">
    <?php if ($message): ?>
        <div class="alert alert-success"><?= htmlspecialchars($message) ?></div>
    <?php endif; ?>
    <?php if ($error): ?>
        <div class="alert alert-danger"><?= htmlspecialchars($error) ?></div>
    <?php endif; ?>

    <div class="card mb-3">
        <div class="card-header"><h3 class="card-title">Qurilish materiallari bo'limi</h3></div>
        <div class="card-body">
            <form method="POST" action="" style="display:flex;gap:12px;align-items:center">
                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                <input type="hidden" name="form" value="materials_toggle">
                <label style="display:flex;gap:8px;align-items:center">
                    <input type="checkbox" name="enabled" value="1" <?= $materialsOn ? 'checked' : '' ?>>
                    Ilovada ko'rinsin (bosh ekrandagi tugma va E'lonlardagi tugma)
                </label>
                <button type="submit" class="btn btn-primary btn-sm">Saqlash</button>
            </form>
            <p style="margin:8px 0 0;color:#6b7280">
                Hozir: <strong><?= $materialsOn ? 'yoqilgan' : "o'chirilgan" ?></strong>.
                O'chirilganda yangi material buyurtmasi qabul qilinmaydi, eski buyurtmalar o'z yo'lida davom etadi.
            </p>
        </div>
    </div>

    <div class="card mb-3">
        <div class="card-header"><h3 class="card-title">Yuk tashish — yuklovchi</h3></div>
        <div class="card-body">
            <form method="POST" action="" style="display:flex;gap:12px;align-items:center">
                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                <input type="hidden" name="form" value="loader_fee">
                <label>Mijoz «Yuklovchi kerak» ni tanlasa narxga qo'shiladi, so'm
                    <input name="fee" value="<?= $loaderFee ?>" style="width:120px">
                </label>
                <button type="submit" class="btn btn-primary btn-sm">Saqlash</button>
            </form>
        </div>
    </div>

    <div class="card mb-3">
        <div class="card-header"><h3 class="card-title">Texnika turlari</h3></div>
        <div class="card-body">
            <p style="margin-top:0;color:#6b7280">
                «Boshqalar» ekranida shu ro'yxat chiqadi. Tarifi yo'q tur ilovada kulrang ko'rinadi —
                narxni <a href="tariffs.php">Tariflar</a> sahifasida qo'ying. Ikonka: PNG, shaffof fon, 300×300.
            </p>
            <table>
                <thead>
                    <tr><th>Ikonka</th><th>Kod</th><th>Nomi uz / ru</th><th>Guruh</th><th>Izoh uz / ru</th><th>Tartib</th><th>Holati</th><th></th></tr>
                </thead>
                <tbody>
                <?php foreach ($types as $t): $fid = 'ty_' . $t['code']; ?>
                    <tr style="<?= $t['is_enabled'] ? '' : 'opacity:.55' ?>">
                        <td>
                            <?php if ($t['icon_url']): ?>
                                <img src="<?= htmlspecialchars($t['icon_url']) ?>" alt="" style="width:48px;height:48px;object-fit:contain;background:#EAF2FB;border-radius:8px">
                            <?php else: ?>
                                <span style="color:#9ca3af;font-size:12px">ilovadagi</span>
                            <?php endif; ?>
                            <form method="POST" action="" enctype="multipart/form-data" style="margin-top:4px">
                                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                <input type="hidden" name="form" value="type_icon">
                                <input type="hidden" name="code" value="<?= htmlspecialchars($t['code']) ?>">
                                <input type="file" name="icon" accept="image/png,image/jpeg,image/webp" style="width:150px" onchange="this.form.submit()">
                            </form>
                        </td>
                        <td><code><?= htmlspecialchars($t['code']) ?></code><?= $t['has_tariff'] ? '' : '<br><span style="color:#b45309;font-size:12px">tarif yo\'q</span>' ?></td>
                        <td>
                            <input form="<?= $fid ?>" name="name_uz" value="<?= htmlspecialchars($t['name_uz']) ?>" style="width:150px"><br>
                            <input form="<?= $fid ?>" name="name_ru" value="<?= htmlspecialchars($t['name_ru']) ?>" style="width:150px;margin-top:4px">
                        </td>
                        <td>
                            <select form="<?= $fid ?>" name="group_code">
                                <?php foreach ($groups as $g => $gl): ?>
                                    <option value="<?= $g ?>" <?= $t['group_code'] === $g ? 'selected' : '' ?>><?= htmlspecialchars($gl) ?></option>
                                <?php endforeach; ?>
                            </select>
                        </td>
                        <td>
                            <input form="<?= $fid ?>" name="subtitle_uz" value="<?= htmlspecialchars((string)$t['subtitle_uz']) ?>" placeholder="16–300 t" style="width:150px"><br>
                            <input form="<?= $fid ?>" name="subtitle_ru" value="<?= htmlspecialchars((string)$t['subtitle_ru']) ?>" placeholder="16–300 т" style="width:150px;margin-top:4px">
                        </td>
                        <td><input form="<?= $fid ?>" name="sort_order" value="<?= (int)$t['sort_order'] ?>" style="width:60px"></td>
                        <td><?= $t['is_enabled'] ? 'Faol' : "O'chirilgan" ?></td>
                        <td style="display:flex;gap:6px">
                            <form id="<?= $fid ?>" method="POST" action="">
                                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                <input type="hidden" name="form" value="type_save">
                                <input type="hidden" name="code" value="<?= htmlspecialchars($t['code']) ?>">
                                <button type="submit" class="btn btn-primary btn-sm">Saqlash</button>
                            </form>
                            <form method="POST" action="">
                                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                <input type="hidden" name="form" value="type_toggle">
                                <input type="hidden" name="code" value="<?= htmlspecialchars($t['code']) ?>">
                                <button type="submit" class="btn btn-sm"><?= $t['is_enabled'] ? "O'chirish" : 'Yoqish' ?></button>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>

            <h4 style="margin:20px 0 8px">Yangi tur</h4>
            <form method="POST" action="" style="display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end">
                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                <input type="hidden" name="form" value="type_add">
                <label>Kod<br><input name="code" placeholder="vacuum_truck" style="width:140px"></label>
                <label>Nomi (uz)<br><input name="name_uz" placeholder="Assenizator"></label>
                <label>Nomi (ru)<br><input name="name_ru" placeholder="Ассенизатор"></label>
                <label>Guruh<br>
                    <select name="group_code">
                        <?php foreach ($groups as $g => $gl): ?>
                            <option value="<?= $g ?>"><?= htmlspecialchars($gl) ?></option>
                        <?php endforeach; ?>
                    </select>
                </label>
                <label>Izoh (uz)<br><input name="subtitle_uz" placeholder="3–10 m³"></label>
                <label>Izoh (ru)<br><input name="subtitle_ru" placeholder="3–10 м³"></label>
                <label>Tartib<br><input name="sort_order" value="500" style="width:70px"></label>
                <button type="submit" class="btn btn-primary">Qo'shish</button>
            </form>
        </div>
    </div>

    <div class="card mb-3">
        <div class="card-header"><h3 class="card-title">Yetkazib berish mashinalari</h3></div>
        <div class="card-body">
            <p style="margin-top:0;color:#6b7280">
                Material buyurtmasida tizim yuk og'irligiga qarab bir reysga sig'adigan eng kichik mashinani tanlaydi.
                Yetkazish = (podacha + km × narx) × reys. Km narxi bo'sh — sotuvchi tovarga yozgan km narxi olinadi.
                <br>«Yuk tashish» (mijozning yuki A→B): <b>Km</b> rejimi — podacha + km × narx;
                <b>Soatbay</b> — soat × soat narxi (eng kam soatdan kam emas). Kuzov turlari bittadan ko'p bo'lsa, mijoz kuzovni tanlaydi (Y3). Kuzov o'lchami — «sig'maydi» tekshiruvi uchun (Y7).
            </p>
            <table>
                <thead>
                    <tr><th>Kod</th><th>Nomi</th><th>Sig'im, kg</th><th>Kuzov, m³</th><th>Podacha, so'm</th><th>1 km, so'm</th><th>Rejim</th><th>1 soat / kamida</th><th>Marka / sinf / kuzov (U×E×B, m) / kuzov turlari</th><th>Tartib</th><th>Holati</th><th></th></tr>
                </thead>
                <tbody>
                <?php foreach ($vehicles as $v): $fid = 've_' . $v['code']; ?>
                    <tr style="<?= $v['is_enabled'] ? '' : 'opacity:.55' ?>">
                        <td><code><?= htmlspecialchars($v['code']) ?></code></td>
                        <td><input form="<?= $fid ?>" name="name" value="<?= htmlspecialchars($v['name']) ?>" style="width:140px"></td>
                        <td><input form="<?= $fid ?>" name="capacity_kg" value="<?= (int)$v['capacity_kg'] ?>" style="width:90px"></td>
                        <td><input form="<?= $fid ?>" name="volume_m3" value="<?= $v['volume_m3'] !== null ? rtrim(rtrim((string)$v['volume_m3'], '0'), '.') : '' ?>" style="width:70px"></td>
                        <td><input form="<?= $fid ?>" name="base_fee" value="<?= (int)$v['base_fee'] ?>" style="width:100px"></td>
                        <td><input form="<?= $fid ?>" name="price_per_km" value="<?= $v['price_per_km'] !== null ? (int)$v['price_per_km'] : '' ?>" placeholder="sotuvchi" style="width:90px"></td>
                        <td>
                            <select form="<?= $fid ?>" name="price_mode">
                                <option value="km" <?= $v['price_mode'] === 'km' ? 'selected' : '' ?>>Km</option>
                                <option value="hour" <?= $v['price_mode'] === 'hour' ? 'selected' : '' ?>>Soatbay</option>
                            </select>
                        </td>
                        <td>
                            <input form="<?= $fid ?>" name="price_per_hour" value="<?= $v['price_per_hour'] !== null ? (int)$v['price_per_hour'] : '' ?>" placeholder="—" style="width:90px">
                            <input form="<?= $fid ?>" name="min_hours" value="<?= (int)$v['min_hours'] ?>" style="width:44px" title="eng kam soat">
                        </td>
                        <td style="min-width:260px">
                            <input form="<?= $fid ?>" name="brand" value="<?= htmlspecialchars((string)$v['brand']) ?>" placeholder="Hyundai" style="width:90px">
                            <select form="<?= $fid ?>" name="size_class">
                                <?php foreach ($sizeClasses as $sc => $scl): ?>
                                    <option value="<?= $sc ?>" <?= $v['size_class'] === $sc ? 'selected' : '' ?>><?= htmlspecialchars($scl) ?></option>
                                <?php endforeach; ?>
                            </select><br>
                            <?php foreach (['body_length_m', 'body_width_m', 'body_height_m'] as $dk): ?>
                                <input form="<?= $fid ?>" name="<?= $dk ?>" value="<?= $v[$dk] !== null ? rtrim(rtrim((string)$v[$dk], '0'), '.') : '' ?>" style="width:46px;margin-top:4px">
                            <?php endforeach; ?><br>
                            <?php $vb = array_filter(explode(',', (string)$v['body_types'])); foreach ($bodyTypes as $bt => $btl): ?>
                                <label style="font-size:12px;white-space:nowrap"><input form="<?= $fid ?>" type="checkbox" name="body_types[]" value="<?= $bt ?>" <?= in_array($bt, $vb, true) ? 'checked' : '' ?>> <?= htmlspecialchars($btl) ?></label>
                            <?php endforeach; ?>
                        </td>
                        <td><input form="<?= $fid ?>" name="sort_order" value="<?= (int)$v['sort_order'] ?>" style="width:60px"></td>
                        <td><?= $v['is_enabled'] ? 'Faol' : "O'chirilgan" ?></td>
                        <td style="display:flex;gap:6px">
                            <form id="<?= $fid ?>" method="POST" action="">
                                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                <input type="hidden" name="form" value="vehicle_save">
                                <input type="hidden" name="code" value="<?= htmlspecialchars($v['code']) ?>">
                                <button type="submit" class="btn btn-primary btn-sm">Saqlash</button>
                            </form>
                            <form method="POST" action="">
                                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                <input type="hidden" name="form" value="vehicle_toggle">
                                <input type="hidden" name="code" value="<?= htmlspecialchars($v['code']) ?>">
                                <button type="submit" class="btn btn-sm"><?= $v['is_enabled'] ? "O'chirish" : 'Yoqish' ?></button>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>

            <h4 style="margin:20px 0 8px">Yangi mashina</h4>
            <form method="POST" action="" style="display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end">
                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                <input type="hidden" name="form" value="vehicle_add">
                <label>Kod<br><input name="code" placeholder="isuzu_4" style="width:110px"></label>
                <label>Nomi<br><input name="name" placeholder="Isuzu ELF"></label>
                <label>Sig'im, kg<br><input name="capacity_kg" placeholder="4000" style="width:90px"></label>
                <label>Kuzov, m³<br><input name="volume_m3" style="width:70px"></label>
                <label>Podacha<br><input name="base_fee" value="0" style="width:100px"></label>
                <label>1 km<br><input name="price_per_km" placeholder="sotuvchi" style="width:90px"></label>
                <label>Rejim<br><select name="price_mode"><option value="km">Km</option><option value="hour">Soatbay</option></select></label>
                <label>1 soat<br><input name="price_per_hour" style="width:90px"></label>
                <label>Kamida soat<br><input name="min_hours" value="1" style="width:60px"></label>
                <label>Marka<br><input name="brand" style="width:100px"></label>
                <label>Sinf<br><select name="size_class"><?php foreach ($sizeClasses as $sc => $scl): ?><option value="<?= $sc ?>"><?= htmlspecialchars($scl) ?></option><?php endforeach; ?></select></label>
                <label>Kuzov U×E×B, m<br><input name="body_length_m" style="width:46px"><input name="body_width_m" style="width:46px"><input name="body_height_m" style="width:46px"></label>
                <label>Kuzov turlari<br><?php foreach ($bodyTypes as $bt => $btl): ?><label style="font-size:12px"><input type="checkbox" name="body_types[]" value="<?= $bt ?>"> <?= htmlspecialchars($btl) ?></label> <?php endforeach; ?></label>
                <label>Tartib<br><input name="sort_order" value="0" style="width:60px"></label>
                <button type="submit" class="btn btn-primary">Qo'shish</button>
            </form>
        </div>
    </div>
</div>

<?php include 'includes/footer.php'; ?>
