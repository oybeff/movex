<?php
/**
 * Texnika: xaritada va ro'yxatda.
 *
 * Ilgari panelda texnika sahifasi UMUMAN YO'Q edi — egalar mashina
 * qo'shardi, admin esa ularni faqat buyurtmalar ichidan ko'rardi.
 *
 * Xaritada ikki qatlam:
 *   texnika        — `equipment.latitude/longitude`, egasi ko'rsatgan joy;
 *   yetkazib berish — faol buyurtmalarning `delivery_latitude/longitude`,
 *                     ya'ni mashina QAYERGA ketishi kerak.
 *
 * MUHIM, chalkashmaslik uchun: `equipment.latitude/longitude` — bu
 * mashinaning HOZIRGI joyi EMAS. Bu egasi e'lon qo'yayotganda tanlagan
 * nuqta, va u o'zgarmaydi. Mashinani real vaqtda kuzatish uchun ilova
 * telefondan koordinatani muntazam yuborishi kerak — bunday narsa
 * loyihada hozircha yo'q. Shuning uchun sahifada nuqtaning YOSHI
 * ko'rsatiladi: "3 kun oldin yangilangan" degan yozuv bu nuqtaga
 * qanchalik ishonish mumkinligini darhol aytadi.
 *
 * Xarita — Leaflet + OpenStreetMap, sun'iy yo'ldosh qatlami Esri World
 * Imagery. Ikkalasi ham kalitsiz ishlaydi: Yandex JS API uchun alohida
 * kalit kerak bo'lardi (mobil ilovadagi kalit MapKit uchun va bu yerda
 * ishlamaydi).
 */
require_once 'config.php';
requireAdmin();
requireCsrfToken();

$pageTitle = 'Texnika';
$currentPage = 'equipment';

$db = getDbConnection();

// ---------------------------------------------------------------- filtrlar
$typeFilter = $_GET['type'] ?? 'all';
$statusFilter = $_GET['status'] ?? 'all';
$searchQuery = trim($_GET['search'] ?? '');

$where = ['e.deleted_at IS NULL'];
$params = [];

if ($typeFilter !== 'all') {
    $where[] = 'e.type = ?';
    $params[] = $typeFilter;
}

if ($statusFilter === 'available') {
    $where[] = 'e.available = true';
} elseif ($statusFilter === 'busy') {
    $where[] = 'e.available = false';
} elseif ($statusFilter === 'no_coords') {
    $where[] = '(e.latitude IS NULL OR e.longitude IS NULL)';
}

if ($searchQuery !== '') {
    $where[] = '(e.model ILIKE ? OR e.address ILIKE ? OR u.full_name ILIKE ? OR u.phone ILIKE ?)';
    for ($i = 0; $i < 4; $i++) {
        $params[] = "%$searchQuery%";
    }
}

$whereClause = 'WHERE ' . implode(' AND ', $where);

$query = "
    SELECT
        e.id, e.type, e.model, e.year, e.address,
        e.latitude, e.longitude, e.available, e.status,
        e.price_per_day, e.photo_url, e.updated_at, e.created_at,
        u.id AS owner_id, u.full_name AS owner_name, u.phone AS owner_phone,
        (SELECT COUNT(*) FROM orders o
          WHERE o.equipment_id = e.id AND o.status IN ('pending','confirmed')
        ) AS active_orders
    FROM equipment e
    JOIN users u ON u.id = e.owner_id
    $whereClause
    ORDER BY e.id DESC
";
$stmt = $db->prepare($query);
$stmt->execute($params);
$equipment = $stmt->fetchAll();

// Faol buyurtmalarning yetkazib berish nuqtalari — xaritaning ikkinchi
// qatlami. Faqat koordinatasi borlari: qolganlarini chizib bo'lmaydi.
// DIQQAT: buyurtmadagi mijoz ustuni `user_id` deb ataladi, `client_id`
// emas — kodda esa hamma joyda "client" deyiladi. Shu nomlar farqi
// bu sahifani birinchi ochganda 500 xato bergan edi.
$deliveries = $db->query("
    SELECT o.id, o.delivery_latitude AS lat, o.delivery_longitude AS lng,
           o.delivery_address, o.start_date, o.end_date, o.status,
           e.type AS eq_type, e.model AS eq_model, e.id AS equipment_id,
           c.full_name AS client_name, c.phone AS client_phone
      FROM orders o
      JOIN equipment e ON e.id = o.equipment_id
      JOIN users c ON c.id = o.user_id
     WHERE o.status IN ('pending','confirmed')
       AND o.delivery_latitude IS NOT NULL
       AND o.delivery_longitude IS NOT NULL
     ORDER BY o.id DESC
")->fetchAll();

// Ro'yxatdagi barcha turlar — filtr uchun. Kod bazada, ekranda esa nom.
$types = $db->query("
    SELECT DISTINCT type FROM equipment WHERE deleted_at IS NULL ORDER BY type
")->fetchAll(PDO::FETCH_COLUMN);

/**
 * Nuqta qachon yangilangani — o'qiladigan ko'rinishda.
 *
 * Hisob PHP tomonda: PostgreSQL vaqtni "+05" ko'rinishidagi siljish
 * bilan qaytaradi (daqiqasiz), va JavaScript uni tushunmaydi — xaritada
 * har bir nuqtada "sana noma'lum" chiqardi.
 */
function pointAge(?string $value): string {
    if (empty($value)) {
        return "sana noma'lum";
    }
    try {
        $then = new DateTime($value);
    } catch (Throwable $e) {
        return "sana noma'lum";
    }
    $days = (int) (new DateTime('now'))->diff($then)->days;
    if ($days <= 0) {
        return 'bugun yangilangan';
    }
    if ($days === 1) {
        return 'kecha yangilangan';
    }
    return $days . ' kun oldin yangilangan';
}

$stats = [
    'total' => count($equipment),
    'mapped' => 0,
    'no_coords' => 0,
    'available' => 0,
    'busy' => 0,
];

// Xaritaga beriladigan ma'lumot. PHP tomonda yig'iladi va JSON bo'lib
// uzatiladi: ikkinchi so'rov qilishdan ko'ra arzon, sahifa kichik.
$markers = [];
foreach ($equipment as $item) {
    if ($item['available']) {
        $stats['available']++;
    } else {
        $stats['busy']++;
    }

    if ($item['latitude'] === null || $item['longitude'] === null) {
        $stats['no_coords']++;
        continue;
    }
    $stats['mapped']++;

    $markers[] = [
        'id' => (int) $item['id'],
        'lat' => (float) $item['latitude'],
        'lng' => (float) $item['longitude'],
        'type' => equipmentTypeName($item['type']),
        // Kod ham kerak: xaritadagi belgiga turga mos IKONKA qo'yiladi
        // (assets/equipment_types/{kod}.svg). Ekranda esa nom ko'rsatiladi.
        'typeCode' => $item['type'],
        'model' => $item['model'],
        'year' => $item['year'],
        'address' => $item['address'],
        'available' => (bool) $item['available'],
        'price' => $item['price_per_day'] !== null ? (float) $item['price_per_day'] : null,
        'owner' => $item['owner_name'],
        'phone' => $item['owner_phone'],
        'ownerId' => (int) $item['owner_id'],
        'activeOrders' => (int) $item['active_orders'],
        // Nuqta qachon yangilangani. Koordinata eskirgani darhol
        // ko'rinishi kerak: u mashinaning hozirgi joyi emas.
        'updated' => pointAge($item['updated_at'] ?: $item['created_at']),
    ];
}

$deliveryMarkers = [];
foreach ($deliveries as $row) {
    $deliveryMarkers[] = [
        'id' => (int) $row['id'],
        'lat' => (float) $row['lat'],
        'lng' => (float) $row['lng'],
        'equipmentId' => (int) $row['equipment_id'],
        'equipment' => equipmentTypeName($row['eq_type']) . ' ' . $row['eq_model'],
        'client' => $row['client_name'],
        'phone' => $row['client_phone'],
        'status' => $row['status'],
        'address' => $row['delivery_address'],
        'start' => $row['start_date'],
        'end' => $row['end_date'],
    ];
}

include 'includes/header.php';
?>

<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
      integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin="">

<div class="content">

    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Jami texnika</div>
                    <div class="stat-value"><?= number_format($stats['total']) ?></div>
                    <div class="stat-change"><?= number_format($stats['mapped']) ?> ta xaritada</div>
                </div>
                <div class="stat-icon primary">🚜</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Bo'sh</div>
                    <div class="stat-value"><?= number_format($stats['available']) ?></div>
                    <div class="stat-change"><?= number_format($stats['busy']) ?> ta band</div>
                </div>
                <div class="stat-icon success">✅</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Faol yetkazib berish</div>
                    <div class="stat-value"><?= number_format(count($deliveryMarkers)) ?></div>
                    <div class="stat-change">buyurtma nuqtasi xaritada</div>
                </div>
                <div class="stat-icon primary">📍</div>
            </div>
        </div>

        <div class="stat-card">
            <div class="stat-header">
                <div>
                    <div class="stat-title">Koordinatasiz</div>
                    <div class="stat-value"><?= number_format($stats['no_coords']) ?></div>
                    <div class="stat-change">
                        <?php if ($stats['no_coords'] > 0): ?>
                            <a href="?status=no_coords">xaritada ko'rinmaydi</a>
                        <?php else: ?>
                            hammasi joyida
                        <?php endif; ?>
                    </div>
                </div>
                <div class="stat-icon <?= $stats['no_coords'] > 0 ? 'warning' : 'success' ?>">🧭</div>
            </div>
        </div>
    </div>

    <div class="card mb-3">
        <div class="card-header" style="display:flex; align-items:center; gap:16px; flex-wrap:wrap;">
            <h3 class="card-title" style="margin:0;">Xarita</h3>
            <!-- Tab: texnikani va buyurtmalarni ALOHIDA ko'rsatish uchun.
                 Ilgari bu yerda ikkita "checkbox" turardi — ular bir-biriga
                 xalaqit berardi. Tab bilan bittasini tanlash aniqroq. -->
            <div class="map-tabs" style="display:inline-flex; border:1px solid #d1d5db; border-radius:8px; overflow:hidden;">
                <button type="button" class="map-tab active" data-mode="all"
                        style="padding:6px 14px; font-size:13px; border:none; background:#16a34a; color:#fff; cursor:pointer;">
                    Hammasi
                </button>
                <button type="button" class="map-tab" data-mode="equipment"
                        style="padding:6px 14px; font-size:13px; border:none; border-left:1px solid #d1d5db; background:#fff; color:#111; cursor:pointer;">
                    🚜 Texnika
                </button>
                <button type="button" class="map-tab" data-mode="delivery"
                        style="padding:6px 14px; font-size:13px; border:none; border-left:1px solid #d1d5db; background:#fff; color:#111; cursor:pointer;">
                    📍 Buyurtmalar
                </button>
            </div>
            <button type="button" id="fit-all" class="btn" style="padding:6px 12px; font-size:13px; margin-left:auto;">
                Hammasini ko'rsatish
            </button>
        </div>
        <div class="card-body" style="padding:0;">
            <div id="map" style="height:520px; width:100%; border-radius:0 0 8px 8px;"></div>
        </div>
    </div>

    <div class="alert alert-info" style="margin-bottom:18px;">
        <strong>Nuqta — mashinaning hozirgi joyi emas.</strong>
        Bu egasi texnikani qo'shayotganda tanlagan manzil, va u o'zgarmaydi.
        Har bir nuqtada oxirgi yangilangan sana ko'rsatilgan. Mashinani real
        vaqtda kuzatish uchun ilova telefondan koordinatani yuborib turishi
        kerak — bunday imkoniyat hozircha yo'q.
    </div>

    <div class="card mb-3">
        <div class="card-body">
            <form method="GET" action="" class="d-flex gap-2" style="align-items: flex-end; flex-wrap: wrap;">
                <div class="form-group" style="margin-bottom: 0;">
                    <label for="type">Turi</label>
                    <select id="type" name="type">
                        <option value="all" <?= $typeFilter === 'all' ? 'selected' : '' ?>>Hammasi</option>
                        <?php foreach ($types as $code): ?>
                            <option value="<?= htmlspecialchars($code) ?>"
                                <?= $typeFilter === $code ? 'selected' : '' ?>>
                                <?= htmlspecialchars(equipmentTypeName($code)) ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>

                <div class="form-group" style="margin-bottom: 0;">
                    <label for="status">Holat</label>
                    <select id="status" name="status">
                        <?php foreach ([
                            'all' => 'Hammasi',
                            'available' => "Bo'sh",
                            'busy' => 'Band',
                            'no_coords' => 'Koordinatasiz',
                        ] as $value => $label): ?>
                            <option value="<?= $value ?>" <?= $statusFilter === $value ? 'selected' : '' ?>>
                                <?= $label ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                </div>

                <div class="form-group" style="margin-bottom: 0;">
                    <label for="search">Qidirish</label>
                    <input type="text" id="search" name="search"
                           placeholder="Model, manzil, ega..."
                           value="<?= htmlspecialchars($searchQuery) ?>">
                </div>

                <button type="submit" class="btn btn-primary">Filtrlash</button>
                <a href="equipment.php" class="btn">Tozalash</a>
            </form>
        </div>
    </div>

    <div class="card">
        <div class="card-body" style="overflow-x: auto;">
            <?php if (empty($equipment)): ?>
                <p style="padding: 24px; text-align: center; color: #6b7280;">
                    Texnika topilmadi
                </p>
            <?php else: ?>
            <table>
                <thead>
                    <tr>
                        <th>#</th>
                        <th>Texnika</th>
                        <th>Egasi</th>
                        <th>Manzil</th>
                        <th>Kunlik narx</th>
                        <th>Holat</th>
                        <th>Xaritada</th>
                    </tr>
                </thead>
                <tbody>
                <?php foreach ($equipment as $item): ?>
                    <tr>
                        <td><?= (int) $item['id'] ?></td>
                        <td>
                            <?php
                            // Bazada KOD turadi (excavator), ekranda esa nom.
                            // Kod bir necha marta foydalanuvchiga chiqib
                            // ketgan, shuning uchun bu yerda faqat
                            // equipmentTypeName(). Yonida — turga mos ikonka.
                            $iconFile = __DIR__ . '/assets/equipment_types/' . $item['type'] . '.svg';
                            $iconCode = is_file($iconFile) ? $item['type'] : 'other';
                            ?>
                            <div style="display:flex; align-items:center; gap:10px;">
                                <img src="assets/equipment_types/<?= htmlspecialchars($iconCode) ?>.svg"
                                     width="30" height="30" alt=""
                                     style="flex:none; background:#f3f4f6; border-radius:6px; padding:3px;">
                                <div>
                                    <strong><?= htmlspecialchars(equipmentTypeName($item['type'])) ?></strong><br>
                                    <small style="color:#6b7280;">
                                        <?= htmlspecialchars($item['model'] ?? '—') ?>
                                        <?= $item['year'] ? ', ' . (int) $item['year'] : '' ?>
                                    </small>
                                </div>
                            </div>
                        </td>
                        <td>
                            <?= htmlspecialchars($item['owner_name']) ?><br>
                            <small style="color:#6b7280;"><?= htmlspecialchars($item['owner_phone']) ?></small>
                        </td>
                        <td style="max-width:260px;">
                            <small><?= htmlspecialchars($item['address'] ?? '—') ?></small>
                        </td>
                        <td>
                            <?= $item['price_per_day'] !== null
                                ? number_format($item['price_per_day'], 0, '.', ' ') . " so'm"
                                : '—' ?>
                        </td>
                        <td>
                            <?php if ($item['available']): ?>
                                <span class="badge badge-success">Bo'sh</span>
                            <?php else: ?>
                                <span class="badge badge-warning">Band</span>
                            <?php endif; ?>
                            <?php if ((int) $item['active_orders'] > 0): ?>
                                <br><small style="color:#6b7280;">
                                    <?= (int) $item['active_orders'] ?> ta faol buyurtma
                                </small>
                            <?php endif; ?>
                        </td>
                        <td>
                            <?php if ($item['latitude'] !== null && $item['longitude'] !== null): ?>
                                <button type="button" class="btn show-on-map"
                                        data-id="<?= (int) $item['id'] ?>"
                                        style="padding:4px 10px; font-size:13px;">
                                    Ko'rsatish
                                </button>
                            <?php else: ?>
                                <small style="color:#dc2626;">koordinata yo'q</small>
                            <?php endif; ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
            <?php endif; ?>
        </div>
    </div>
</div>

<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
        integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>
<script>
(function () {
    var equipment = <?= json_encode($markers, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
    var deliveries = <?= json_encode($deliveryMarkers, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;

    // Toshkent markazi — xaritada hech narsa bo'lmasa ham bo'sh ko'k
    // ekran chiqmasligi uchun.
    var FALLBACK = [41.2995, 69.2401];

    var map = L.map('map', { center: FALLBACK, zoom: 11 });

    var streets = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution: '&copy; OpenStreetMap'
    });

    // Sun'iy yo'ldosh. Esri World Imagery kalitsiz ishlaydi — Yandex JS
    // API uchun alohida kalit kerak bo'lardi, mobil ilovadagi kalit unga
    // to'g'ri kelmaydi.
    var satellite = L.tileLayer(
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        { maxZoom: 19, attribution: 'Esri, Maxar, Earthstar Geographics' }
    );

    // Sun'iy yo'ldosh ustiga ko'cha nomlari: toza sun'iy yo'ldoshda
    // manzilni topib bo'lmaydi.
    var labels = L.tileLayer(
        'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
        { maxZoom: 19 }
    );
    var satelliteWithLabels = L.layerGroup([satellite, labels]);

    satelliteWithLabels.addTo(map);
    L.control.layers(
        { "Sun'iy yo'ldosh": satelliteWithLabels, 'Xarita': streets },
        null,
        { collapsed: false }
    ).addTo(map);

    // Texnika belgisi — turga mos IKONKA oq doira ichida, rani holatga
    // qarab (yashil — bo'sh, sariq — band). Ikonkalar mobil ilovadagilar
    // bilan bir xil (assets/equipment_types/{kod}.svg), shuning uchun
    // xaritada ekskavator ekskavatorga o'xshaydi, oddiy nuqta emas.
    var ICON_BASE = 'assets/equipment_types/';
    // Ma'lum turlar ro'yxati: notanish kodga "other" ishlatiladi, aks
    // holda buzilgan rasm chiqardi.
    var KNOWN_ICONS = <?= json_encode(array_map(function ($f) {
        return basename($f, '.svg');
    }, glob(__DIR__ . '/assets/equipment_types/*.svg')), JSON_HEX_TAG) ?>;

    function equipmentIcon(typeCode, available) {
        var code = KNOWN_ICONS.indexOf(typeCode) !== -1 ? typeCode : 'other';
        var ring = available ? '#16a34a' : '#f59e0b';
        return L.divIcon({
            className: '',
            html:
                '<div style="width:34px;height:34px;border-radius:50%;background:#fff;' +
                'border:2.5px solid ' + ring + ';box-shadow:0 1px 4px rgba(0,0,0,.4);' +
                'display:flex;align-items:center;justify-content:center;">' +
                '<img src="' + ICON_BASE + code + '.svg" width="22" height="22" ' +
                'style="display:block" alt="">' +
                '</div>',
            iconSize: [34, 34],
            iconAnchor: [17, 17],
            popupAnchor: [0, -17]
        });
    }

    // Yetkazib berish nuqtasi — ko'k tomchi belgi (texnikadan farqlansin).
    function dropIcon() {
        return L.divIcon({
            className: '',
            html:
                '<div style="width:20px;height:20px;border-radius:50% 50% 50% 0;' +
                'transform:rotate(-45deg);background:#2563eb;border:2px solid #fff;' +
                'box-shadow:0 1px 4px rgba(0,0,0,.4);"></div>',
            iconSize: [20, 20],
            iconAnchor: [10, 18],
            popupAnchor: [0, -18]
        });
    }
    var iconDrop = dropIcon();

    function escapeHtml(value) {
        return String(value === null || value === undefined ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function money(value) {
        if (value === null || value === undefined) { return '—'; }
        return Math.round(value).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + " so'm";
    }

    var equipmentLayer = L.layerGroup();
    var deliveryLayer = L.layerGroup();
    var byId = {};

    equipment.forEach(function (item) {
        var marker = L.marker([item.lat, item.lng], {
            icon: equipmentIcon(item.typeCode, item.available)
        });
        marker.bindPopup(
            '<div style="min-width:220px">' +
            '<strong>' + escapeHtml(item.type) + ' ' + escapeHtml(item.model || '') + '</strong>' +
            (item.year ? ' <span style="color:#6b7280">' + item.year + '</span>' : '') +
            '<br><span style="color:#6b7280;font-size:12px">' + escapeHtml(item.address || '') + '</span>' +
            '<hr style="margin:8px 0;border:none;border-top:1px solid #e5e7eb">' +
            'Egasi: <strong>' + escapeHtml(item.owner) + '</strong><br>' +
            'Tel: ' + escapeHtml(item.phone) + '<br>' +
            'Kunlik: ' + money(item.price) + '<br>' +
            'Holat: ' + (item.available ? "bo'sh" : 'band') +
            (item.activeOrders ? ' · ' + item.activeOrders + ' ta faol buyurtma' : '') +
            // Nuqtaning yoshi — unga qanchalik ishonish mumkinligi.
            '<br><span style="color:#6b7280;font-size:12px">' + escapeHtml(item.updated) + '</span>' +
            '</div>'
        );
        marker.addTo(equipmentLayer);
        byId[item.id] = marker;
    });

    deliveries.forEach(function (row) {
        var marker = L.marker([row.lat, row.lng], { icon: iconDrop });
        marker.bindPopup(
            '<div style="min-width:220px">' +
            '<strong>Buyurtma #' + row.id + '</strong> · ' + escapeHtml(row.status) +
            '<br>' + escapeHtml(row.equipment) +
            (row.address ? '<br><span style="color:#6b7280;font-size:12px">' +
                           escapeHtml(row.address) + '</span>' : '') +
            '<hr style="margin:8px 0;border:none;border-top:1px solid #e5e7eb">' +
            'Mijoz: <strong>' + escapeHtml(row.client) + '</strong><br>' +
            'Tel: ' + escapeHtml(row.phone) + '<br>' +
            'Muddat: ' + escapeHtml(row.start) + ' — ' + escapeHtml(row.end) +
            '</div>'
        );
        marker.addTo(deliveryLayer);

        // Texnikani yetkazib berish nuqtasi bilan bog'lovchi chiziq:
        // mashina qayerdan qayerga ketishi kerakligi ko'rinadi.
        var source = equipment.filter(function (e) { return e.id === row.equipmentId; })[0];
        if (source) {
            L.polyline([[source.lat, source.lng], [row.lat, row.lng]], {
                color: '#2563eb', weight: 1, opacity: 0.35, dashArray: '4 4'
            }).addTo(deliveryLayer);
        }
    });

    equipmentLayer.addTo(map);
    deliveryLayer.addTo(map);

    function fitAll() {
        var points = [];
        if (map.hasLayer(equipmentLayer)) {
            equipment.forEach(function (e) { points.push([e.lat, e.lng]); });
        }
        if (map.hasLayer(deliveryLayer)) {
            deliveries.forEach(function (d) { points.push([d.lat, d.lng]); });
        }
        if (points.length) {
            map.fitBounds(L.latLngBounds(points), { padding: [40, 40], maxZoom: 15 });
        } else {
            map.setView(FALLBACK, 11);
        }
    }
    fitAll();

    // Tab: qaysi qatlam ko'rinishini tanlaydi.
    var tabs = document.querySelectorAll('.map-tab');

    function setMode(mode) {
        if (mode === 'equipment') {
            map.addLayer(equipmentLayer);
            map.removeLayer(deliveryLayer);
        } else if (mode === 'delivery') {
            map.removeLayer(equipmentLayer);
            map.addLayer(deliveryLayer);
        } else {
            map.addLayer(equipmentLayer);
            map.addLayer(deliveryLayer);
        }
        Array.prototype.forEach.call(tabs, function (tab) {
            var on = tab.dataset.mode === mode;
            tab.classList.toggle('active', on);
            tab.style.background = on ? '#16a34a' : '#fff';
            tab.style.color = on ? '#fff' : '#111';
        });
        fitAll();
    }

    Array.prototype.forEach.call(tabs, function (tab) {
        tab.addEventListener('click', function () { setMode(this.dataset.mode); });
    });

    document.getElementById('fit-all').addEventListener('click', fitAll);

    // Jadvaldagi "Ko'rsatish" tugmasi — texnika tabiga o'tib, o'sha
    // nuqtaga uchadi.
    Array.prototype.forEach.call(document.querySelectorAll('.show-on-map'), function (button) {
        button.addEventListener('click', function () {
            var marker = byId[parseInt(this.dataset.id, 10)];
            if (!marker) { return; }
            if (!map.hasLayer(equipmentLayer)) { setMode('all'); }
            map.setView(marker.getLatLng(), 16);
            marker.openPopup();
            document.getElementById('map').scrollIntoView({ behavior: 'smooth', block: 'center' });
        });
    });
}());
</script>

<?php include 'includes/footer.php'; ?>
