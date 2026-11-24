<?php
/**
 * D4 · Jonli xarita — haydovchilar, D5 · texnika topilmayotgan buyurtmalar
 * (Figma «Admin panel» 01).
 *
 * Manba — driver_locations: MoveX GO Driver onlayn ekan har 10 s yuboradi
 * (POST /drivers/heartbeat). Holat:
 *   bo'sh       — onlayn, faol ishi yo'q
 *   band        — faol buyurtma / yuk / yetkazish bor
 *   GPS yo'q    — onlayn, lekin oxirgi nuqta 4 daqiqadan eski (qizil)
 *   oflayn      — o'zi o'chgan yoki 2 daqiqadan beri signal yo'q
 * Oflayn — faqat so'nggi 24 soatda nuqtasi bo'lganlar.
 * Eski ilova (1.0.11 gacha) heartbeat yubormaydi — u xaritada ko'rinmaydi.
 * Batareya ko'rsatilmaydi: ilova uni yubormaydi, taxminiy raqam qo'ymaymiz.
 *
 * Qidirilayotgan buyurtmalar: tezkor zayavka (open), yuk (searching),
 * material yetkazish (searching). Qo'lda tayinlash — buyurtma kartasida.
 */
require_once 'config.php';
require_once 'includes/user_lib.php';
requireAdmin();
requirePerm('orders_view');

$db = getDbConnection();
$db->exec("SET TIME ZONE 'Asia/Tashkent'");

if (isset($_GET['data'])) {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    $drivers = $db->query("
        WITH busy AS (
            SELECT e.owner_id AS uid, 'equipment' AS kind, o.id,
                   CASE WHEN o.started_at IS NOT NULL THEN 'Ishda' WHEN o.arrived_at IS NOT NULL THEN 'Yetib keldi'
                        WHEN o.departed_at IS NOT NULL THEN 'Yo''lda' ELSE 'Tasdiqlangan' END AS step,
                   NULLIF(o.delivery_latitude, '')::numeric AS dlat, NULLIF(o.delivery_longitude, '')::numeric AS dlon
              FROM orders o JOIN equipment e ON e.id = o.equipment_id
             WHERE o.status = 'confirmed' AND o.finished_at IS NULL
            UNION ALL
            SELECT f.driver_id, 'freight', f.id,
                   CASE f.status WHEN 'accepted' THEN 'Yukka ketmoqda' WHEN 'loaded' THEN 'Yuk ortildi' ELSE 'Yetib keldi' END,
                   f.to_latitude, f.to_longitude
              FROM freight_orders f WHERE f.status IN ('accepted','loaded','arrived') AND f.driver_id IS NOT NULL
            UNION ALL
            SELECT m.driver_id, 'material', m.id,
                   CASE m.delivery_status WHEN 'accepted' THEN 'Omborga' WHEN 'picked_up' THEN 'Yo''lda' ELSE 'Yetib keldi' END,
                   m.delivery_latitude, m.delivery_longitude
              FROM material_orders m WHERE m.delivery_status IN ('accepted','picked_up','arrived') AND m.driver_id IS NOT NULL
        )
        SELECT u.id, u.full_name, u.phone, u.app_version,
               dl.online AND dl.updated_at > NOW() - INTERVAL '2 minutes' AS live,
               dl.latitude::float AS lat, dl.longitude::float AS lon, dl.speed_kmh::float AS speed,
               dl.accuracy_m::float AS acc,
               EXTRACT(EPOCH FROM (NOW() - dl.location_at))::int AS gps_age,
               EXTRACT(EPOCH FROM (NOW() - dl.updated_at))::int AS seen_age,
               (SELECT string_agg(DISTINCT eq.type, ',') FROM equipment eq WHERE eq.owner_id = u.id AND eq.deleted_at IS NULL) AS eq_types,
               (SELECT eq.plate_number FROM equipment eq WHERE eq.owner_id = u.id AND eq.deleted_at IS NULL AND eq.plate_number IS NOT NULL LIMIT 1) AS eq_plate,
               dp.vehicle_code, dp.plate AS truck_plate,
               (SELECT ROUND(AVG(rv.rating)::numeric, 1) FROM reviews rv JOIN equipment eq ON eq.id = rv.equipment_id WHERE eq.owner_id = u.id) AS rating,
               b.kind AS job_kind, b.id AS job_id, b.step AS job_step, b.dlat::float AS job_lat, b.dlon::float AS job_lon
          FROM driver_locations dl
          JOIN users u ON u.id = dl.user_id
          LEFT JOIN delivery_driver_profiles dp ON dp.user_id = u.id
          LEFT JOIN LATERAL (SELECT * FROM busy WHERE busy.uid = u.id LIMIT 1) b ON true
         WHERE dl.latitude IS NOT NULL AND COALESCE(u.is_blocked, false) = false
           AND dl.location_at > NOW() - INTERVAL '24 hours'
    ")->fetchAll();
    $out = [];
    foreach ($drivers as $d) {
        $status = !$d['live'] ? 'offline' : ((int) $d['gps_age'] > 240 ? 'nogps' : ($d['job_id'] ? 'busy' : 'free'));
        $what = [];
        if ($d['vehicle_code']) $what[] = deliveryVehicleName($d['vehicle_code']);
        $types = array_values(array_filter(explode(',', (string) $d['eq_types'])));
        foreach (array_slice($types, 0, 2) as $t) $what[] = equipmentTypeName($t);
        if (count($types) > 2) $what[] = '+' . (count($types) - 2);
        $dist = null;
        if ($d['job_lat'] !== null && $d['lat'] !== null) {
            $r = 6371; $p1 = deg2rad($d['lat']); $p2 = deg2rad($d['job_lat']);
            $dp = $p2 - $p1; $dl = deg2rad($d['job_lon'] - $d['lon']);
            $h = sin($dp / 2) ** 2 + cos($p1) * cos($p2) * sin($dl / 2) ** 2;
            $dist = round(2 * $r * asin(min(1, sqrt($h))), 1);
        }
        $out[] = [
            'id' => (int) $d['id'], 'name' => $d['full_name'], 'phone' => fmtPhone($d['phone']),
            'lat' => (float) $d['lat'], 'lon' => (float) $d['lon'], 'status' => $status,
            'speed' => $d['speed'], 'acc' => $d['acc'], 'gps_age' => (int) $d['gps_age'], 'seen_age' => (int) $d['seen_age'],
            'what' => implode(', ', $what) ?: 'Texnika qo\'shilmagan', 'plate' => $d['truck_plate'] ?: $d['eq_plate'],
            'rating' => $d['rating'], 'version' => $d['app_version'],
            'job' => $d['job_id'] ? ['kind' => $d['job_kind'], 'id' => (int) $d['job_id'], 'step' => $d['job_step'], 'km' => $dist,
                                    'lat' => $d['job_lat'], 'lon' => $d['job_lon']] : null,
        ];
    }

    $orders = $db->query("
        SELECT 'request' AS kind, r.id, r.equipment_type AS what, r.delivery_address AS addr,
               NULLIF(r.delivery_latitude, '')::float AS lat, NULLIF(r.delivery_longitude, '')::float AS lon, r.budget AS price,
               EXTRACT(EPOCH FROM (NOW() - r.created_at))::int AS age,
               (SELECT COUNT(*) FROM quick_request_declines d WHERE d.request_id = r.id) AS declines
          FROM equipment_requests r WHERE r.mode = 'quick' AND r.status = 'open' AND NULLIF(r.delivery_latitude, '') IS NOT NULL
        UNION ALL
        SELECT 'freight', f.id, f.vehicle_code, f.from_address, f.from_latitude::float, f.from_longitude::float, f.price,
               EXTRACT(EPOCH FROM (NOW() - f.created_at))::int, NULL
          FROM freight_orders f WHERE f.status = 'searching'
        UNION ALL
        SELECT 'material', m.id, m.vehicle_code, m.delivery_address, m.delivery_latitude::float, m.delivery_longitude::float,
               m.delivery_fee, EXTRACT(EPOCH FROM (NOW() - m.created_at))::int, NULL
          FROM material_orders m WHERE m.delivery_status = 'searching' AND m.delivery_latitude IS NOT NULL
        ORDER BY age DESC
    ")->fetchAll();
    foreach ($orders as &$o) {
        $o['what'] = $o['kind'] === 'request' ? equipmentTypeName($o['what']) : deliveryVehicleName($o['what']);
        $o['id'] = (int) $o['id'];
        $o['age'] = (int) $o['age'];
        $o['lat'] = (float) $o['lat'];
        $o['lon'] = (float) $o['lon'];
        $o['price'] = $o['price'] !== null ? (float) $o['price'] : null;
    }
    unset($o);
    $zones = $db->query("SELECT name, polygon::text AS polygon FROM price_zones WHERE is_enabled ORDER BY sort_order")->fetchAll();
    echo json_encode(['drivers' => $out, 'orders' => $orders,
                      'zones' => array_map(fn($z) => ['name' => $z['name'], 'polygon' => json_decode($z['polygon'], true)], $zones),
                      'at' => date('H:i:s')], JSON_UNESCAPED_UNICODE);
    exit;
}

$pageTitle = 'Jonli xarita';
$currentPage = 'livemap';
include 'includes/header.php';
?>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
      integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin="">
<div class="content live-wrap">
    <div class="live-grid">
        <aside class="card live-side">
            <div class="live-tabs" role="tablist">
                <button class="active" data-tab="drivers" role="tab">Haydovchilar</button>
                <button data-tab="orders" role="tab">Qidirilmoqda <span class="nav-count danger" id="cntOrders">0</span></button>
            </div>
            <div id="paneDrivers">
                <div class="filter-search" style="margin:10px 12px"><i data-lucide="search"></i>
                    <input type="search" id="liveQ" placeholder="Ism, telefon, davlat raqami"></div>
                <div class="live-chips" id="liveChips">
                    <button class="chip active" data-f="all">Hammasi <b id="cAll">0</b></button>
                    <button class="chip" data-f="free"><i class="dot free"></i>Bo'sh <b id="cFree">0</b></button>
                    <button class="chip" data-f="busy"><i class="dot busy"></i>Band <b id="cBusy">0</b></button>
                    <button class="chip" data-f="nogps"><i class="dot nogps"></i>GPS yo'q <b id="cNogps">0</b></button>
                    <button class="chip" data-f="offline"><i class="dot offline"></i>Oflayn <b id="cOff">0</b></button>
                </div>
                <ul class="live-list" id="driverList"></ul>
            </div>
            <div id="paneOrders" hidden>
                <ul class="live-list" id="orderList"></ul>
            </div>
            <div class="live-foot"><span id="liveAt">Yuklanmoqda…</span> · har 10 soniyada</div>
        </aside>
        <div class="card live-map-card">
            <div id="liveMap"></div>
            <div class="live-legend">
                <span><i class="dot free"></i>Bo'sh</span><span><i class="dot busy"></i>Band</span>
                <span><i class="dot search"></i>Qidirilmoqda</span><span><i class="dot nogps"></i>GPS yo'q (4+ daq)</span>
                <span><i class="dot offline"></i>Oflayn</span>
            </div>
            <div class="live-empty" id="liveEmpty" hidden>
                <i data-lucide="map-pin-off"></i>
                <b>Xaritada hali haydovchi yo'q</b>
                <span>Nuqtani MoveX GO Driver 1.0.12+ onlayn rejimda har 10 soniyada yuboradi. Eski versiyadagilar ko'rinmaydi.</span>
            </div>
        </div>
    </div>
</div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"
        integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin=""></script>
<script>
(() => {
    const map = L.map('liveMap', { zoomControl: true }).setView([41.3111, 69.2797], 11);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '© OpenStreetMap' }).addTo(map);
    const layer = L.layerGroup().addTo(map), zoneLayer = L.layerGroup().addTo(map), jobLayer = L.layerGroup().addTo(map);
    const colors = { free: '#4CA194', busy: '#316DC8', nogps: '#E5484D', offline: '#8E97A2', search: '#E9B52E' };
    const st = { free: "Bo'sh", busy: 'Band', nogps: "GPS yo'q", offline: 'Oflayn' };
    const kinds = { equipment: 'Texnika', request: 'Texnika (qidiruv)', freight: 'Yuk', material: 'Material' };
    let data = { drivers: [], orders: [] }, filter = 'all', q = '', fitted = false, zonesDrawn = false, markers = {};
    const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
    const ago = s => s < 60 ? s + ' soniya oldin' : s < 3600 ? Math.round(s / 60) + ' daqiqa oldin' : Math.round(s / 3600) + ' soat oldin';
    const money = v => v == null ? '' : Math.round(v).toLocaleString('ru-RU').replace(/,/g, ' ') + " so'm";
    const pin = (color, ring) => L.divIcon({ className: '', iconSize: [22, 22], iconAnchor: [11, 11],
        html: `<span class="live-pin${ring ? ' ring' : ''}" style="--c:${color}"></span>` });
    const orderHref = o => `orders.php?kind=${o.kind}&id=${o.id}`;

    function popup(d) {
        const job = d.job ? `<div class="lp-job"><a href="${orderHref(d.job)}">#${d.job.id} · ${esc(kinds[d.job.kind])}</a> · ${esc(d.job.step)}${d.job.km != null ? ' · ' + d.job.km + ' km' : ''}</div>` : '';
        return `<div class="lp"><b>${esc(d.name)}</b><div class="lp-sub">${d.rating ? d.rating + ' ★ · ' : ''}${esc(d.what)}${d.plate ? ' · ' + esc(d.plate) : ''}</div>
            <span class="badge" style="background:${colors[d.status]}22;color:${colors[d.status]}">${st[d.status]}</span>${job}
            <div class="lp-meta">GPS: ${ago(d.gps_age)}${d.speed != null ? ' · ' + Math.round(d.speed) + ' km/s' : ''}${d.acc != null ? ' · ±' + Math.round(d.acc) + ' m' : ''}</div>
            <div class="lp-meta">${esc(d.phone)}${d.version ? ' · ilova ' + esc(d.version) : ''}</div>
            <a class="btn btn-secondary btn-sm" href="user.php?id=${d.id}" style="margin-top:8px">Profil</a></div>`;
    }

    function render() {
        layer.clearLayers(); jobLayer.clearLayers(); markers = {};
        const counts = { all: 0, free: 0, busy: 0, nogps: 0, offline: 0 };
        const qq = q.toLowerCase();
        const shown = data.drivers.filter(d => {
            counts.all++; counts[d.status]++;
            return (filter === 'all' || d.status === filter)
                && (!qq || [d.name, d.phone, d.plate].some(v => String(v || '').toLowerCase().replace(/\s/g, '').includes(qq.replace(/\s/g, ''))));
        });
        cAll.textContent = counts.all; cFree.textContent = counts.free; cBusy.textContent = counts.busy;
        cNogps.textContent = counts.nogps; cOff.textContent = counts.offline;
        const bounds = [];
        shown.forEach(d => {
            const m = L.marker([d.lat, d.lon], { icon: pin(colors[d.status], d.status === 'nogps'), zIndexOffset: d.status === 'offline' ? -100 : 0 })
                .bindPopup(popup(d), { maxWidth: 280 }).addTo(layer);
            markers['d' + d.id] = m;
            bounds.push([d.lat, d.lon]);
            if (d.status === 'busy' && d.job && d.job.lat != null) L.polyline([[d.lat, d.lon], [d.job.lat, d.job.lon]], { color: colors.busy, weight: 2, dashArray: '4 6', opacity: .7 }).addTo(jobLayer);
        });
        data.orders.forEach(o => {
            const m = L.marker([o.lat, o.lon], { icon: pin(colors.search, o.age > 600) })
                .bindPopup(`<div class="lp"><b>#${o.id} · ${esc(o.what)}</b><div class="lp-sub">${esc(kinds[o.kind])}${o.price ? ' · ' + money(o.price) : ''}</div>
                    <div class="lp-meta">${esc(o.addr || '')}</div><div class="lp-meta">Qidirilmoqda ${Math.max(1, Math.round(o.age / 60))} daq${o.declines ? ' · ' + o.declines + ' ta rad etdi' : ''}</div>
                    <a class="btn btn-secondary btn-sm" href="${orderHref(o)}" style="margin-top:8px">Buyurtma kartasi</a></div>`).addTo(layer);
            markers['o' + o.kind + o.id] = m;
            bounds.push([o.lat, o.lon]);
        });
        if (!fitted && bounds.length) { map.fitBounds(bounds, { padding: [40, 40], maxZoom: 13 }); fitted = true; }
        liveEmpty.hidden = data.drivers.length > 0 || data.orders.length > 0;

        driverList.innerHTML = shown.length ? shown.map(d => `<li data-k="d${d.id}"><i class="dot ${d.status}"></i><div><b>${esc(d.name)}</b>
            <small>${esc(d.what)}${d.job ? ' · #' + d.job.id + ' ' + esc(d.job.step) : ''}${d.status === 'nogps' ? ' · GPS signali yo\'q · ' + Math.round(d.gps_age / 60) + ' daqiqa' : ''}${d.status === 'offline' ? ' · oxirgi faollik ' + ago(d.seen_age) : ''}</small></div></li>`).join('')
            : '<li class="empty">Mos haydovchi yo\'q</li>';
        cntOrders.textContent = data.orders.length;
        orderList.innerHTML = data.orders.length ? data.orders.map(o => `<li data-k="o${o.kind}${o.id}" class="${o.age > 600 ? 'late' : ''}"><i class="dot search"></i><div><b>#${o.id} · ${esc(o.what)}</b>
            <small>${esc(kinds[o.kind])} · ${esc(o.addr || '')} · ${Math.max(1, Math.round(o.age / 60))} daq${o.declines ? ' · ' + o.declines + ' rad' : ''}</small></div></li>`).join('')
            : '<li class="empty">Hozir texnika qidirilayotgan buyurtma yo\'q</li>';
    }

    async function load() {
        try {
            const r = await fetch('live_map.php?data=1', { cache: 'no-store' });
            if (r.redirected || !r.ok) { liveAt.textContent = 'Yangilanmadi (' + r.status + ')'; return; }
            data = await r.json();
            if (!zonesDrawn) {
                data.zones.forEach(z => L.polygon(z.polygon, { color: '#316DC8', weight: 1.5, dashArray: '6 6', fillOpacity: .03 }).bindTooltip(z.name).addTo(zoneLayer));
                zonesDrawn = true;
            }
            liveAt.textContent = 'Yangilandi ' + data.at;
            render();
        } catch (e) { liveAt.textContent = "Aloqa yo'q — oxirgi ma'lumot ko'rsatilmoqda"; }
    }
    document.querySelectorAll('#liveChips .chip').forEach(c => c.addEventListener('click', () => {
        document.querySelectorAll('#liveChips .chip').forEach(x => x.classList.toggle('active', x === c));
        filter = c.dataset.f; render();
    }));
    liveQ.addEventListener('input', () => { q = liveQ.value.trim(); render(); });
    document.querySelectorAll('.live-tabs button').forEach(b => b.addEventListener('click', () => {
        document.querySelectorAll('.live-tabs button').forEach(x => x.classList.toggle('active', x === b));
        paneDrivers.hidden = b.dataset.tab !== 'drivers'; paneOrders.hidden = b.dataset.tab !== 'orders';
    }));
    document.querySelector('.live-side').addEventListener('click', e => {
        const li = e.target.closest('li[data-k]');
        const m = li && markers[li.dataset.k];
        if (m) { map.setView(m.getLatLng(), Math.max(map.getZoom(), 14)); m.openPopup(); }
    });
    load();
    setInterval(() => { if (!document.hidden) load(); }, 10000);
})();
</script>
<?php include 'includes/footer.php'; ?>
