<?php
/**
 * Hamma turdagi buyurtmalar bitta ro'yxatda (Figma «Admin panel» O1):
 *   equipment — texnika ijarasi (orders),
 *   request   — tezkor zayavka, hali hech kim olmagan (equipment_requests, mode=quick),
 *   freight   — «Yuk tashish» (freight_orders),
 *   material  — stroymaterial (material_orders).
 *
 * st — admin uchun umumiy bosqich (tablar shu bo'yicha):
 *   searching | assigned | progress | done | cancelled
 * dispute — ochiq shikoyat bor (order_problems).
 * stuck   — 10+ daqiqa ijrochi qidirilmoqda (dashboard banneri bilan bir xil qoida).
 */

function ordersUnionSql(string $alias = 'u'): string
{
    return "(
    SELECT 'equipment'::text AS kind, o.id, o.created_at,
           o.user_id AS client_id, cu.full_name AS client_name, cu.phone AS client_phone,
           ow.id AS perf_id, ow.full_name AS perf_name, e.type AS what, e.plate_number AS plate,
           NULL::text AS addr_from, o.delivery_address AS addr_to, o.delivery_distance AS km,
           CASE WHEN o.status = 'pending' THEN 'searching'
                WHEN o.status = 'confirmed' AND o.started_at IS NULL THEN 'assigned'
                WHEN o.status = 'confirmed' THEN 'progress'
                WHEN o.status = 'completed' THEN 'done' ELSE 'cancelled' END AS st,
           o.status AS raw, COALESCE(o.payment_method, 'balance') AS payment, o.total_amount AS amount,
           o.created_at AS wait_since, o.delay_minutes AS delay,
           EXISTS (SELECT 1 FROM order_problems op WHERE op.kind = 'equipment' AND op.order_id = o.id AND op.status = 'open') AS dispute,
           false AS stuck
      FROM orders o
      JOIN users cu ON cu.id = o.user_id
      LEFT JOIN equipment e ON e.id = o.equipment_id
      LEFT JOIN users ow ON ow.id = e.owner_id
    UNION ALL
    SELECT 'request', r.id, r.created_at,
           r.client_id, cu.full_name, cu.phone,
           NULL, NULL, r.equipment_type, NULL,
           NULL, r.delivery_address, NULL,
           CASE WHEN r.status IN ('open','awaiting_payment') THEN 'searching' ELSE 'cancelled' END,
           r.status, COALESCE(r.payment_method, 'balance'), r.budget,
           r.created_at, NULL, false,
           (r.status = 'open' AND r.created_at < NOW() - INTERVAL '10 minutes')
      FROM equipment_requests r
      JOIN users cu ON cu.id = r.client_id
     WHERE r.mode = 'quick' AND r.status IN ('open','awaiting_payment','expired','cancelled')
    UNION ALL
    SELECT 'freight', f.id, f.created_at,
           f.client_id, cu.full_name, cu.phone,
           dr.id, dr.full_name, f.vehicle_code, dp.plate,
           f.from_address, f.to_address, f.distance_km,
           CASE f.status WHEN 'searching' THEN 'searching' WHEN 'accepted' THEN 'assigned'
                WHEN 'done' THEN 'done' WHEN 'cancelled' THEN 'cancelled' ELSE 'progress' END,
           f.status, f.payment_method, f.price,
           f.created_at, NULL,
           EXISTS (SELECT 1 FROM order_problems op WHERE op.kind = 'freight' AND op.order_id = f.id AND op.status = 'open'),
           (f.status = 'searching' AND f.created_at < NOW() - INTERVAL '10 minutes')
      FROM freight_orders f
      JOIN users cu ON cu.id = f.client_id
      LEFT JOIN users dr ON dr.id = f.driver_id
      LEFT JOIN delivery_driver_profiles dp ON dp.user_id = f.driver_id
    UNION ALL
    SELECT 'material', m.id, m.created_at,
           m.buyer_id, cu.full_name, cu.phone,
           COALESCE(dr.id, sl.id), COALESCE(dr.full_name, sl.full_name), p.title, dp.plate,
           p.address, m.delivery_address, m.delivery_distance_km,
           CASE WHEN m.status = 'pending' THEN 'searching'
                WHEN m.status = 'delivered' THEN 'done'
                WHEN m.status IN ('cancelled','rejected') THEN 'cancelled'
                WHEN m.dispatch = 'driver' AND m.delivery_status IN ('waiting_seller','searching') THEN 'searching'
                WHEN m.dispatch = 'driver' AND m.delivery_status = 'accepted' THEN 'assigned'
                ELSE 'progress' END,
           CASE WHEN m.status = 'confirmed' AND m.dispatch = 'driver' THEN 'd_' || COALESCE(m.delivery_status, '') ELSE m.status END,
           COALESCE(m.delivery_payment, 'balance'), m.total_amount,
           CASE WHEN m.status = 'pending' THEN m.created_at ELSE m.updated_at END, NULL,
           EXISTS (SELECT 1 FROM order_problems op WHERE op.kind = 'material' AND op.order_id = m.id AND op.status = 'open'),
           (m.status = 'confirmed' AND m.delivery_status = 'searching' AND m.updated_at < NOW() - INTERVAL '10 minutes')
      FROM material_orders m
      JOIN users cu ON cu.id = m.buyer_id
      LEFT JOIN material_products p ON p.id = m.product_id
      LEFT JOIN users sl ON sl.id = m.seller_id
      LEFT JOIN users dr ON dr.id = m.driver_id
      LEFT JOIN delivery_driver_profiles dp ON dp.user_id = m.driver_id
) " . $alias;
}

const ORDER_TABS = [
    'all' => 'Hammasi',
    'searching' => 'Qidirilmoqda',
    'assigned' => "Tayinlandi / yo'lda",
    'progress' => 'Ish jarayonida',
    'done' => 'Yakunlangan',
    'cancelled' => 'Bekor qilingan',
    'dispute' => 'Nizoli',
];

const ORDER_KINDS = [
    'equipment' => 'Texnika',
    'request' => 'Texnika (qidiruv)',
    'freight' => 'Yuk tashish',
    'material' => 'Material',
];

/** Holat yorlig'i: [matn, badge rangi] */
function orderStatusBadge(array $r): array
{
    $raw = $r['raw'];
    $min = isset($r['wait_since']) ? max(0, (int) floor((time() - strtotime($r['wait_since'])) / 60)) : 0;
    if (!empty($r['dispute'])) {
        return ['Nizo ochilgan', 'danger'];
    }
    switch ($r['kind']) {
        case 'request':
            if ($raw === 'expired') { return ['Texnika topilmadi', 'danger']; }
            if ($raw === 'cancelled') { return ['Bekor qilindi', 'secondary']; }
            if ($raw === 'awaiting_payment') { return ["Karta tasdig'i kutilmoqda", 'warning']; }
            return ['Qidirilmoqda · ' . $min . ' daq', $min >= 10 ? 'danger' : 'warning'];
        case 'equipment':
            if ($raw === 'pending') { return ["Ega tasdig'i kutilmoqda", 'warning']; }
            if ($r['st'] === 'assigned') {
                return !empty($r['delay']) ? ['Kechikmoqda +' . (int) $r['delay'] . ' daq', 'warning'] : ['Tayinlandi', 'info'];
            }
            if ($r['st'] === 'progress') { return ['Ish jarayonida', 'info']; }
            if ($raw === 'completed') { return ['Yakunlandi', 'success']; }
            if ($raw === 'rejected') { return ['Rad etildi', 'secondary']; }
            return ['Bekor qilindi', 'secondary'];
        case 'freight':
            $m = ['searching' => ['Qidirilmoqda · ' . $min . ' daq', $min >= 10 ? 'danger' : 'warning'],
                  'accepted' => ["Yo'lda", 'info'], 'loaded' => ['Yuk ortildi', 'info'],
                  'arrived' => ['Yetib keldi', 'info'], 'done' => ['Yakunlandi', 'success'],
                  'cancelled' => ['Bekor qilindi', 'secondary']];
            return $m[$raw] ?? [$raw, 'secondary'];
        case 'material':
            $m = ['pending' => ['Sotuvchi kutilmoqda', 'warning'],
                  'd_waiting_seller' => ['Sotuvchi kutilmoqda', 'warning'],
                  'd_searching' => ['Haydovchi qidirilmoqda · ' . $min . ' daq', $min >= 10 ? 'danger' : 'warning'],
                  'd_accepted' => ["Haydovchi yo'lda", 'info'], 'd_picked_up' => ['Tovar olindi', 'info'],
                  'd_arrived' => ['Yetib keldi', 'info'], 'confirmed' => ['Sotuvchi yetkazmoqda', 'info'],
                  'delivered' => ['Yetkazildi', 'success'], 'cancelled' => ['Bekor qilindi', 'secondary'],
                  'rejected' => ['Rad etildi', 'secondary']];
            return $m[$raw] ?? [$raw, 'secondary'];
    }
    return [$raw, 'secondary'];
}

/** To'lov ustuni: [usul, holat] */
function orderPaymentLabel(array $r): array
{
    $method = ['balance' => 'Go wallet', 'card' => 'Karta', 'cash' => 'Naqd'][$r['payment']] ?? $r['payment'];
    if ($r['payment'] === 'cash') {
        return [$method, $r['st'] === 'done' ? 'Ijrochiga berildi' : ''];
    }
    if ($r['st'] === 'done') { return [$method, 'Yechildi']; }
    if ($r['st'] === 'cancelled') { return [$method, 'Qaytarildi']; }
    return [$method, 'Bloklangan'];
}

function orderWhat(array $r): string
{
    if ($r['kind'] === 'equipment' || $r['kind'] === 'request') {
        return equipmentTypeName($r['what']);
    }
    if ($r['kind'] === 'freight') {
        return deliveryVehicleName($r['what']);
    }
    return (string) $r['what'];
}

function orderHref(string $kind, int $id): string
{
    return 'orders.php?kind=' . $kind . '&id=' . $id;
}

function maskPhone(?string $p): string
{
    $p = preg_replace('/\D/', '', (string) $p);
    if (strlen($p) !== 12) {
        return $p ? '+' . $p : '';
    }
    return '+' . substr($p, 0, 3) . ' ' . substr($p, 3, 2) . ' ' . substr($p, 5, 3) . ' ' . substr($p, 8, 2) . ' ' . substr($p, 10);
}

function moneyFmt($v): string
{
    return number_format((float) $v, 0, '.', ' ');
}

function agoText(?string $ts): string
{
    if (!$ts) { return ''; }
    $t = strtotime($ts);
    $d = date('Y-m-d', $t);
    if ($d === date('Y-m-d')) { return 'Bugun, ' . date('H:i', $t); }
    if ($d === date('Y-m-d', strtotime('-1 day'))) { return 'Kecha, ' . date('H:i', $t); }
    return date('d.m.Y H:i', $t);
}
