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
requireCsrfToken();

$pageTitle = 'Tariflar';
$currentPage = 'tariffs';

$db = getDbConnection();

// backend/app/core/equipment_types.py dagi texnika turlari (xizmatlarsiz).
$types = [
    'excavator', 'mini_excavator', 'backhoe_loader', 'bulldozer', 'front_loader',
    'grader', 'roller', 'truck_crane', 'manipulator', 'aerial_platform',
    'dump_truck', 'concrete_mixer', 'concrete_pump', 'auger_drill', 'tow_truck',
    'compressor', 'other',
];
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
        $minHours = (string)($_POST['min_hours'] ?? '4');
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
                $db->beginTransaction();
                foreach ($prices as $tier => $p) {
                    if ($p === null) {
                        $db->prepare('DELETE FROM tariffs WHERE equipment_type = ? AND tier = ?')
                           ->execute([$type, $tier]);
                        continue;
                    }
                    $db->prepare('
                        INSERT INTO tariffs (equipment_type, tier, price_per_hour, min_hours, eta_minutes, is_active)
                        VALUES (?, ?, ?, ?, ?, true)
                        ON CONFLICT (equipment_type, tier)
                        DO UPDATE SET price_per_hour = EXCLUDED.price_per_hour,
                                      min_hours = EXCLUDED.min_hours,
                                      eta_minutes = EXCLUDED.eta_minutes,
                                      is_active = true,
                                      updated_at = NOW()
                    ')->execute([$type, $tier, $p, (int)$minHours, $etas[$tier]]);
                }
                $db->commit();
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

$rows = $db->query('SELECT equipment_type, tier, price_per_hour, min_hours, eta_minutes FROM tariffs')->fetchAll();
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
                    <div class="stat-title">Tarifli turlar</div>
                    <div class="stat-value"><?= count($tariffs) ?> / <?= count($types) ?></div>
                    <div class="stat-change">tarifi yo'q tur ilovada «taksi» oqimida ko'rinmaydi</div>
                </div>
                <div class="stat-icon primary">🚕</div>
            </div>
        </div>
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Faol naqd buyurtmalar</div>
                    <div class="stat-value"><?= (int)$cashOrders['cnt'] ?></div>
                    <div class="stat-change">egalarda muzlatilgan komissiya: <?= money($cashOrders['frozen']) ?> so'm</div>
                </div>
                <div class="stat-icon primary">💵</div>
            </div>
        </div>
    </div>

    <div class="card mb-3">
        <div class="card-header">
            <h3 class="card-title">Soatlik narxlar</h3>
        </div>
        <div class="card-body">
            <p style="margin-top:0;color:#6b7280">
                Buyurtma summasi = (tarif narxi + jihoz ustamasi) × soat. Narxni bo'sh qoldirsangiz,
                o'sha tarif o'chadi. Naqd to'lovda komissiya egasining balansidan olinadi
                (stavka — <a href="commission.php">Platforma ulushi</a>).
            </p>
            <table>
                <thead>
                    <tr>
                        <th>Texnika</th>
                        <?php foreach ($tiers as $label): ?>
                            <th><?= htmlspecialchars($label) ?>, so'm/soat</th>
                        <?php endforeach; ?>
                        <th>Kamida, soat</th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>
                <?php foreach ($types as $type):
                    $t = $tariffs[$type] ?? [];
                    $min = 4;
                    foreach ($t as $row) { $min = (int)$row['min_hours']; break; }
                    $formId = 'tf_' . $type;
                ?>
                    <tr>
                        <td><strong><?= htmlspecialchars(equipmentTypeName($type)) ?></strong></td>
                        <?php foreach ($tiers as $tier => $label): ?>
                            <td>
                                <input form="<?= $formId ?>" type="text" inputmode="numeric"
                                       name="price_<?= $tier ?>" style="width:130px"
                                       value="<?= isset($t[$tier]) ? (int)$t[$tier]['price_per_hour'] : '' ?>"
                                       placeholder="—">
                                <br>
                                <input form="<?= $formId ?>" type="text" inputmode="numeric"
                                       name="eta_<?= $tier ?>" style="width:130px;margin-top:4px"
                                       value="<?= isset($t[$tier]['eta_minutes']) ? (int)$t[$tier]['eta_minutes'] : '' ?>"
                                       placeholder="kelish, daqiqa" title="«N daqiqada keladi». Bo'sh — yozuvsiz">
                            </td>
                        <?php endforeach; ?>
                        <td>
                            <input form="<?= $formId ?>" type="number" min="1" max="24"
                                   name="min_hours" style="width:70px" value="<?= $min ?>">
                        </td>
                        <td>
                            <form id="<?= $formId ?>" method="POST" action="">
                                <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                <input type="hidden" name="form" value="tariffs">
                                <input type="hidden" name="equipment_type" value="<?= htmlspecialchars($type) ?>">
                                <button type="submit" class="btn btn-primary btn-sm">Saqlash</button>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    </div>

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
                                <form method="POST" action="" onsubmit="return confirm('Jihozni o\'chirasizmi?')">
                                    <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                                    <input type="hidden" name="form" value="attachment_delete">
                                    <input type="hidden" name="id" value="<?= (int)$a['id'] ?>">
                                    <button type="submit" class="btn btn-danger btn-sm">Olib tashlash</button>
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
