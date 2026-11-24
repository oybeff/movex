<?php
/**
 * Hududlar va narxlar (Sherzodbek, 24.11.2026): «Andijon boshqa narx,
 * Toshkent boshqa narx — kran soatiga 300 ming Andijonda, 350 ming
 * Toshkentda». Admin hududni xaritada chizadi va unga o'z narxlarini
 * qo'yadi (tur × tarif) yoki ustama foizini.
 *
 * Narxni buyurtma NUQTASI (texnika kerak bo'lgan joy) qaysi hududga
 * tushishi belgilaydi. Hududda narx yozilmagan juftlik — asosiy narx
 * (tariffs.php). Hududlar ustma-ust tushsa — tartib raqami kichigi.
 *
 * DIQQAT: hisob — backend'da (zone_service.py, tariff_service.py). Bu
 * sahifa faqat price_zones va zone_tariffs jadvallarini o'zgartiradi.
 * PHP 7.4 — 8.x sintaksisi ishlatilmaydi.
 */
require_once 'config.php';
requireAdmin();
requirePagePerm('settings');
requireCsrfToken();
// Audit (S9): har bir o'zgartiruvchi so'rov jurnalga — maydonlar bilan.
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $auditFields = array_diff_key($_POST, ['csrf_token' => 1, 'password' => 1, 'new_password' => 1]);
    array_walk_recursive($auditFields, function (&$v) { $v = mb_substr((string) $v, 0, 200); });
    auditLog('zone_changed', 'zone', (int) ($_POST['zone_id'] ?? $_POST['id'] ?? 0) ?: null, $auditFields);
}


$pageTitle = 'Tizim / Xizmat hududlari';
$currentPage = 'zones';

$db = getDbConnection();
$tiers = ['econom' => 'Ekonom', 'fast' => 'Tezkor', 'day' => 'Kun davomida'];
$message = null;
$error = null;

function zoneMoney($v) {
    return number_format((float)$v, 0, '.', ' ');
}

/** [[lat,lon],...] ni tekshiradi; yaroqsiz — null. */
function parsePolygon($raw) {
    $pts = json_decode((string)$raw, true);
    if (!is_array($pts) || count($pts) < 3 || count($pts) > 500) return null;
    $out = [];
    foreach ($pts as $p) {
        if (!is_array($p) || count($p) !== 2 || !is_numeric($p[0]) || !is_numeric($p[1])) return null;
        $lat = round((float)$p[0], 6);
        $lon = round((float)$p[1], 6);
        if ($lat < -90 || $lat > 90 || $lon < -180 || $lon > 180) return null;
        $out[] = [$lat, $lon];
    }
    return $out;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $form = $_POST['form'] ?? '';
    $id = (int)($_POST['id'] ?? 0);

    if ($form === 'zone') {
        $name = trim((string)($_POST['name'] ?? ''));
        $poly = parsePolygon($_POST['polygon'] ?? '');
        $sur = str_replace(',', '.', trim((string)($_POST['surcharge'] ?? '0')));
        $sort = (int)($_POST['sort_order'] ?? 0);
        $on = isset($_POST['is_enabled']) ? 'true' : 'false';
        if ($name === '' || mb_strlen($name) > 100) {
            $error = 'Hudud nomini yozing (100 belgigacha).';
        } elseif ($poly === null) {
            $error = "Xaritada hududni chizing — kamida 3 nuqta.";
        } elseif ($sur === '' || !is_numeric($sur) || (float)$sur < -50 || (float)$sur > 200) {
            $error = 'Ustama — −50 dan 200 gacha foiz.';
        } else {
            $json = json_encode($poly);
            if ($id > 0) {
                $db->prepare("UPDATE price_zones SET name = ?, polygon = ?::json, surcharge_percent = ?, sort_order = ?,
                              is_enabled = $on, updated_at = NOW() WHERE id = ?")
                   ->execute([$name, $json, $sur, $sort, $id]);
                $message = "«{$name}» saqlandi.";
            } else {
                $st = $db->prepare("INSERT INTO price_zones (name, polygon, surcharge_percent, sort_order, is_enabled)
                                    VALUES (?, ?::json, ?, ?, $on) RETURNING id");
                $st->execute([$name, $json, $sur, $sort]);
                $id = (int)$st->fetchColumn();
                header('Location: zones.php?id=' . $id . '&saved=1');
                exit;
            }
        }
    } elseif ($form === 'prices' && $id > 0) {
        $prices = $_POST['price'] ?? [];
        $bad = 0;
        $db->beginTransaction();
        $db->prepare('DELETE FROM zone_tariffs WHERE zone_id = ?')->execute([$id]);
        $ins = $db->prepare('INSERT INTO zone_tariffs (zone_id, equipment_type, tier, price) VALUES (?, ?, ?, ?)');
        foreach ($prices as $type => $byTier) {
            if (!is_array($byTier) || !preg_match('/^[a-z0-9_]{1,50}$/', (string)$type)) continue;
            foreach ($byTier as $tier => $raw) {
                if (!isset($tiers[$tier])) continue;
                $raw = preg_replace('/\s+/', '', (string)$raw);
                if ($raw === '') continue;
                if (!ctype_digit($raw) || (int)$raw <= 0) { $bad++; continue; }
                $ins->execute([$id, $type, $tier, (int)$raw]);
            }
        }
        $db->commit();
        $message = 'Hudud narxlari saqlandi.' . ($bad ? " {$bad} ta noto'g'ri qiymat o'tkazib yuborildi." : '');
    } elseif ($form === 'delete' && $id > 0) {
        $db->prepare('DELETE FROM price_zones WHERE id = ?')->execute([$id]);
        header('Location: zones.php?deleted=1');
        exit;
    }
}
if (isset($_GET['saved'])) $message = 'Hudud yaratildi — endi narxlarini qo\'ying.';
if (isset($_GET['deleted'])) $message = "Hudud o'chirildi.";

$zones = $db->query('SELECT z.*, (SELECT COUNT(*) FROM zone_tariffs t WHERE t.zone_id = z.id) AS prices
                     FROM price_zones z ORDER BY z.sort_order, z.id')->fetchAll(PDO::FETCH_ASSOC);
$editId = (int)($_GET['id'] ?? ($_POST['id'] ?? 0));
$isNew = isset($_GET['new']);
$zone = null;
foreach ($zones as $z) {
    if ((int)$z['id'] === $editId) $zone = $z;
}

// Asosiy tariflar: hududda shu juftliklarga narx qo'yiladi.
$base = $db->query('SELECT equipment_type, tier, price_per_hour, package_hours, package_price
                    FROM tariffs WHERE is_active ORDER BY equipment_type')->fetchAll(PDO::FETCH_ASSOC);
$baseBy = [];
foreach ($base as $b) $baseBy[$b['equipment_type']][$b['tier']] = $b;
$zonePrices = [];
if ($zone) {
    $st = $db->prepare('SELECT equipment_type, tier, price FROM zone_tariffs WHERE zone_id = ?');
    $st->execute([$zone['id']]);
    foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $r) $zonePrices[$r['equipment_type']][$r['tier']] = $r['price'];
}

$mapZones = [];
foreach ($zones as $z) {
    $mapZones[] = ['id' => (int)$z['id'], 'name' => $z['name'], 'polygon' => json_decode($z['polygon'], true),
                   'enabled' => (bool)$z['is_enabled'], 'current' => $zone && (int)$z['id'] === (int)$zone['id']];
}

include 'includes/header.php';
?>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
      integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin="">
<style>
    .zones-layout { display: grid; grid-template-columns: 300px 1fr; gap: 16px; align-items: start; }
    .zone-list a { display: flex; justify-content: space-between; gap: 8px; padding: 10px 12px; border-radius: 8px;
                   color: inherit; text-decoration: none; border: 1px solid transparent; }
    .zone-list a:hover { background: #f3f4f6; }
    .zone-list a.active { border-color: #dc2626; background: #fef2f2; }
    .zone-list .muted { color: #6b7280; font-size: 12px; }
    #zoneMap { height: 460px; border-radius: 10px; }
    .draw-bar { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin-bottom: 8px; }
    .zone-prices input { width: 120px; }
    .zone-prices td, .zone-prices th { white-space: nowrap; }
    @media (max-width: 1000px) { .zones-layout { grid-template-columns: 1fr; } }
</style>

<div class="content">
    <div class="page-head"><div><h2>Xizmat hududlari</h2><div class="sub">Hudud chegarasi, ustama va hududiy narxlar. Hududdan tashqarida tarifli buyurtma berib bo&#39;lmaydi</div></div></div>

    <?php if ($message): ?><div class="alert alert-success"><?= htmlspecialchars($message) ?></div><?php endif; ?>
    <?php if ($error): ?><div class="alert alert-danger"><?= htmlspecialchars($error) ?></div><?php endif; ?>

    <div class="zones-layout">
        <div class="card">
            <div class="card-header" style="display:flex;justify-content:space-between;align-items:center">
                <h3 class="card-title">Hududlar</h3>
                <a class="btn btn-primary btn-sm" href="zones.php?new=1">+ Yangi hudud</a>
            </div>
            <div class="card-body zone-list">
                <?php if (!$zones): ?>
                    <p class="muted" style="margin:0">Hali hudud yo'q. Hamma joyda asosiy narx (Tariflar) ishlaydi,
                        xizmat hududi — Toshkent shahri va viloyati.</p>
                <?php endif; ?>
                <?php foreach ($zones as $z): ?>
                    <a href="zones.php?id=<?= (int)$z['id'] ?>" class="<?= $zone && (int)$z['id'] === (int)$zone['id'] ? 'active' : '' ?>">
                        <span>
                            <strong><?= htmlspecialchars($z['name']) ?></strong><br>
                            <span class="muted"><?= (int)$z['prices'] ?> ta narx<?php
                                if ((float)$z['surcharge_percent'] != 0) echo ' · ustama ' . (float)$z['surcharge_percent'] . '%'; ?></span>
                        </span>
                        <span class="muted"><?= $z['is_enabled'] ? '' : "o'chiq" ?></span>
                    </a>
                <?php endforeach; ?>
            </div>
        </div>

        <div>
            <div class="card mb-3">
                <div class="card-body">
                    <?php if ($zone || $isNew): ?>
                        <form method="POST" action="zones.php<?= $zone ? '?id=' . (int)$zone['id'] : '?new=1' ?>" id="zoneForm">
                            <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                            <input type="hidden" name="form" value="zone">
                            <input type="hidden" name="id" value="<?= $zone ? (int)$zone['id'] : 0 ?>">
                            <input type="hidden" name="polygon" id="polygonField"
                                   value="<?= htmlspecialchars($zone ? $zone['polygon'] : ($_POST['polygon'] ?? '')) ?>">
                            <div class="draw-bar">
                                <label>Nomi <input name="name" required maxlength="100" style="width:200px"
                                       value="<?= htmlspecialchars($zone['name'] ?? ($_POST['name'] ?? '')) ?>" placeholder="Andijon viloyati"></label>
                                <label>Ustama, % <input name="surcharge" style="width:70px"
                                       value="<?= htmlspecialchars((string)(float)($zone['surcharge_percent'] ?? 0)) ?>"></label>
                                <label>Tartib <input name="sort_order" style="width:60px" value="<?= (int)($zone['sort_order'] ?? 0) ?>"></label>
                                <label><input type="checkbox" name="is_enabled" <?= !$zone || $zone['is_enabled'] ? 'checked' : '' ?>> Yoqilgan</label>
                            </div>
                            <div class="draw-bar">
                                <button type="button" class="btn btn-secondary btn-sm" id="btnDraw"><i data-lucide="pencil"></i> Qaytadan chizish</button>
                                <button type="button" class="btn btn-secondary btn-sm" id="btnUndo">↶ Oxirgi nuqtani olib tashlash</button>
                                <span class="muted" id="drawHint" style="color:#6b7280">Xaritaga bosib hudud chegarasini nuqtalab chizing.</span>
                                <button type="submit" class="btn btn-primary btn-sm" style="margin-left:auto">Saqlash</button>
                            </div>
                        </form>
                    <?php else: ?>
                        <p style="margin:0 0 8px;color:#6b7280">Hududni tanlang yoki «+ Yangi hudud» bosing. Xaritada barcha hududlar.</p>
                    <?php endif; ?>
                    <div id="zoneMap"></div>
                </div>
            </div>

            <?php if ($zone): ?>
                <div class="card mb-3">
                    <div class="card-header"><h3 class="card-title">«<?= htmlspecialchars($zone['name']) ?>» narxlari</h3></div>
                    <div class="card-body">
                        <p style="margin-top:0;color:#6b7280">
                            Bo'sh katak — asosiy narx (kulrang). Ekonom — soatiga, Tezkor va Kun davomida — paket narxi
                            (6 va 12 soat). Ustama foizi bularning ustiga qo'shiladi.
                        </p>
                        <?php if (!$baseBy): ?>
                            <p>Asosiy tariflar yo'q — avval <a href="tariffs.php">Tariflar</a> sahifasida narx qo'ying.</p>
                        <?php else: ?>
                        <form method="POST" action="zones.php?id=<?= (int)$zone['id'] ?>">
                            <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                            <input type="hidden" name="form" value="prices">
                            <input type="hidden" name="id" value="<?= (int)$zone['id'] ?>">
                            <div class="table-responsive">
                            <table class="table zone-prices">
                                <thead><tr><th>Texnika</th><?php foreach ($tiers as $label): ?><th><?= $label ?></th><?php endforeach; ?></tr></thead>
                                <tbody>
                                <?php foreach ($baseBy as $type => $byTier): ?>
                                    <tr>
                                        <td><?= htmlspecialchars(equipmentTypeName($type)) ?></td>
                                        <?php foreach ($tiers as $tier => $label): ?>
                                            <td>
                                                <?php if (isset($byTier[$tier])):
                                                    $b = $byTier[$tier];
                                                    $basePrice = $b['package_hours'] ? $b['package_price'] : $b['price_per_hour'];
                                                    $cur = $zonePrices[$type][$tier] ?? ''; ?>
                                                    <input name="price[<?= htmlspecialchars($type) ?>][<?= $tier ?>]"
                                                           value="<?= $cur === '' ? '' : (int)$cur ?>"
                                                           placeholder="<?= zoneMoney($basePrice) ?>">
                                                    <div class="muted" style="font-size:11px;color:#9ca3af">
                                                        <?= $b['package_hours'] ? (int)$b['package_hours'] . ' soat paket' : 'soatiga' ?>
                                                    </div>
                                                <?php else: ?>
                                                    <span style="color:#9ca3af">—</span>
                                                <?php endif; ?>
                                            </td>
                                        <?php endforeach; ?>
                                    </tr>
                                <?php endforeach; ?>
                                </tbody>
                            </table>
                            </div>
                            <button type="submit" class="btn btn-primary btn-sm">Narxlarni saqlash</button>
                        </form>
                        <?php endif; ?>
                    </div>
                </div>
                <form method="POST" action="zones.php" onsubmit="return confirm('Hudud o\'chirilsinmi? Narxlari ham o\'chadi.')">
                    <input type="hidden" name="csrf_token" value="<?= generateCsrfToken() ?>">
                    <input type="hidden" name="form" value="delete">
                    <input type="hidden" name="id" value="<?= (int)$zone['id'] ?>">
                    <button type="submit" class="btn btn-danger btn-sm">Hududni o'chirish</button>
                </form>
            <?php endif; ?>
        </div>
    </div>
</div>

<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
        integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>
<script>
(function () {
    var zones = <?= json_encode($mapZones, JSON_UNESCAPED_UNICODE) ?>;
    var editing = <?= ($zone || $isNew) ? 'true' : 'false' ?>;
    var map = L.map('zoneMap').setView([41.3, 69.25], 7);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 18, attribution: '&copy; OpenStreetMap'
    }).addTo(map);

    var bounds = [];
    zones.forEach(function (z) {
        if (!z.polygon || z.current) return;
        var p = L.polygon(z.polygon, {color: z.enabled ? '#2563eb' : '#9ca3af', weight: 2, fillOpacity: 0.08})
            .addTo(map).bindTooltip(z.name);
        p.on('click', function () { if (!editing) location.href = 'zones.php?id=' + z.id; });
        bounds.push.apply(bounds, z.polygon);
    });

    if (!editing) {
        if (bounds.length) map.fitBounds(bounds, {padding: [20, 20]});
        return;
    }

    var field = document.getElementById('polygonField');
    var pts = [];
    try { pts = JSON.parse(field.value || '[]') || []; } catch (e) { pts = []; }
    var shape = L.polygon([], {color: '#dc2626', weight: 3, fillOpacity: 0.15}).addTo(map);
    var markers = L.layerGroup().addTo(map);

    function redraw() {
        shape.setLatLngs(pts);
        markers.clearLayers();
        pts.forEach(function (p) {
            L.circleMarker(p, {radius: 4, color: '#dc2626', fillOpacity: 1}).addTo(markers);
        });
        field.value = pts.length >= 3 ? JSON.stringify(pts) : '';
        document.getElementById('drawHint').textContent = pts.length < 3
            ? 'Xaritaga bosib nuqta qo\'ying: ' + pts.length + ' / kamida 3'
            : pts.length + ' nuqta — hudud tayyor. Saqlashni bosing.';
    }
    map.on('click', function (e) {
        pts.push([+e.latlng.lat.toFixed(6), +e.latlng.lng.toFixed(6)]);
        redraw();
    });
    document.getElementById('btnDraw').onclick = function () { pts = []; redraw(); };
    document.getElementById('btnUndo').onclick = function () { pts.pop(); redraw(); };
    document.getElementById('zoneForm').addEventListener('submit', function (e) {
        if (pts.length < 3) { e.preventDefault(); alert('Hududni chizing — kamida 3 nuqta.'); }
    });
    redraw();
    if (pts.length) map.fitBounds(pts, {padding: [30, 30]});
    else if (bounds.length) map.fitBounds(bounds, {padding: [20, 20]});
})();
</script>

<?php include 'includes/footer.php'; ?>
