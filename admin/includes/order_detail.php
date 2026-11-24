<?php
/**
 * O2 · Buyurtma tafsiloti (+ O3 bekor qilish modal, O4 ijrochini
 * almashtirish drawer). orders.php?kind=..&id=.. dan chaqiriladi —
 * $db, CSRF va requireAdmin u yerda.
 *
 * Pulga tegadigan amallar (bekor qilish, almashtirish) — backend'ning
 * /admin-orders/internal/... manzillari orqali: pul mantig'i bitta joyda.
 * Ichki izoh — pulga tegmaydi, to'g'ridan-to'g'ri bazaga.
 */

$kind = $_GET['kind'] ?? 'equipment';
if (!isset(ORDER_KINDS[$kind])) {
    $kind = 'equipment';
}
$id = (int) $_GET['id'];
$adminId = (int) ($_SESSION['admin_user_id'] ?? 0);
$self = orderHref($kind, $id);

$cancelReasons = [
    'client_request' => ['Mijoz so\'rovi bilan', ''],
    'performer_late' => ['Ijrochi kechikdi / kelmadi', ''],
    'technical' => ['Texnik nosozlik (ilova / to\'lov)', ''],
    'fraud' => ['Firibgarlik shubhasi', 'Xavfsizlik bo\'limiga ham xabar bering'],
    'other' => ['Boshqa sabab', 'Izohda yozing'],
];

// ----------------------------------------------------------------- POST
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';
    $flash = ['error', 'Noma\'lum amal'];
    if ($action === 'cancel') {
        $reason = (string) ($_POST['reason'] ?? '');
        $note = trim((string) ($_POST['note'] ?? ''));
        if (!isset($cancelReasons[$reason])) {
            $flash = ['error', 'Sababni tanlang'];
        } elseif ($note === '') {
            $flash = ['error', 'Izoh majburiy — u audit jurnaliga yoziladi'];
        } else {
            $r = internalApiPost("/admin-orders/internal/$kind/$id/cancel", [
                'admin_id' => $adminId, 'reason' => $reason, 'note' => $note,
                'notify' => !empty($_POST['notify']),
            ]);
            $flash = $r['ok']
                ? ['success', 'Buyurtma bekor qilindi' . ((float) ($r['data']['released'] ?? 0) > 0
                    ? '. ' . moneyFmt($r['data']['released']) . ' so\'m mijozga qaytdi (muzlatish yechildi)' : '')]
                : ['error', 'Bekor qilib bo\'lmadi: ' . $r['error']];
        }
    } elseif ($action === 'reassign') {
        $target = $_POST['target'] ?? '';
        $payload = ['admin_id' => $adminId, 'note' => trim((string) ($_POST['note'] ?? '')) ?: null];
        if ($kind === 'equipment') {
            $payload['equipment_id'] = (int) $target;
        } elseif ($target !== 'requeue') {
            $payload['user_id'] = (int) $target;
        }
        if ($target === '') {
            $flash = ['error', 'Ijrochini tanlang'];
        } else {
            $r = internalApiPost("/admin-orders/internal/$kind/$id/reassign", $payload);
            $flash = $r['ok']
                ? ['success', $target === 'requeue' ? 'Haydovchi olindi — buyurtma qayta qidiruvda' : 'Yangi ijrochi tayinlandi']
                : ['error', 'Almashtirib bo\'lmadi: ' . $r['error']];
        }
    } elseif ($action === 'note') {
        $text = trim((string) ($_POST['text'] ?? ''));
        if ($text === '' || mb_strlen($text) > 2000) {
            $flash = ['error', 'Izoh bo\'sh yoki juda uzun'];
        } else {
            $db->prepare('INSERT INTO order_notes (kind, order_id, admin_id, text) VALUES (?, ?, ?, ?)')
               ->execute([$kind, $id, $adminId, $text]);
            $db->prepare("INSERT INTO admin_actions (admin_id, action, entity, entity_id, payload)
                          VALUES (?, 'order_note', ?, ?, ?::jsonb)")
               ->execute([$adminId, $kind, $id, json_encode(['text' => mb_substr($text, 0, 200)], JSON_UNESCAPED_UNICODE)]);
            $flash = ['success', 'Izoh saqlandi'];
        }
    }
    $_SESSION['flash'] = $flash;
    header('Location: ' . $self);
    exit;
}
$flash = $_SESSION['flash'] ?? null;
unset($_SESSION['flash']);

// ----------------------------------------------------------------- Ma'lumot
$st = $db->prepare('SELECT u.* FROM ' . ordersUnionSql() . ' WHERE u.kind = ? AND u.id = ?');
$st->execute([$kind, $id]);
$row = $st->fetch();

$pageTitle = 'Operatsiyalar / Buyurtmalar / #' . $id;
$currentPage = 'orders';

if (!$row) {
    include __DIR__ . '/header.php';
    echo '<div class="content"><div class="card"><div class="empty-state"><i data-lucide="search-x"></i>'
       . '<div><b>Buyurtma topilmadi</b></div><a class="btn btn-secondary btn-sm mt-2" href="orders.php">Ro\'yxatga qaytish</a></div></div></div>';
    include __DIR__ . '/footer.php';
    exit;
}

function one(PDO $db, string $sql, array $p)
{
    $s = $db->prepare($sql);
    $s->execute($p);
    return $s->fetch() ?: [];
}

$o = [];
$steps = [];      // [title, sub, time|null, state: done|now|todo|bad]
$pay = [];        // [label, value, total?]
$payNote = '';
$performerRole = 'Ijrochi';
$performerExtra = '';
$closed = in_array($row['st'], ['done', 'cancelled'], true);

$T = function ($ts) { return $ts ? date('H:i', strtotime($ts)) . (date('Y-m-d', strtotime($ts)) !== date('Y-m-d') ? ' · ' . date('d.m', strtotime($ts)) : '') : null; };

if ($kind === 'equipment') {
    $o = one($db, 'SELECT o.*, e.type, e.model, e.plate_number, e.owner_id FROM orders o LEFT JOIN equipment e ON e.id = o.equipment_id WHERE o.id = ?', [$id]);
    $req = one($db, 'SELECT * FROM equipment_requests WHERE order_id = ? LIMIT 1', [$id]);
    $performerRole = 'Texnika egasi';
    $performerExtra = trim(equipmentTypeName($o['type']) . ' ' . ($o['model'] ?? '') . ($o['plate_number'] ? ' · ' . $o['plate_number'] : ''));
    $what = equipmentTypeName($o['type']) . ($o['hours'] ? ' · ' . (int) $o['hours'] . ' soat' : '');
    $steps[] = ['Buyurtma yaratildi', $what . ' · ' . orderPaymentLabel($row)[0], $T($req['created_at'] ?? $o['created_at']), 'done'];
    if ($req) {
        $steps[] = ['Ega qabul qildi', 'Tezkor buyurtma — birinchi olgan ega', $T($o['created_at']), 'done'];
    } else {
        $steps[] = [$o['status'] === 'pending' ? 'Ega tasdig\'i kutilmoqda' : 'Ega tasdiqladi', 'Katalogdan buyurtma',
                    null, $o['status'] === 'pending' ? 'now' : ($o['status'] === 'rejected' ? 'bad' : 'done')];
    }
    $flow = [['departed_at', 'Yo\'lga chiqdi'], ['arrived_at', 'Yetib keldi'], ['started_at', 'Ish boshlandi'], ['finished_at', 'Ish tugadi']];
    $nowSet = false;
    foreach ($flow as [$col, $title]) {
        if (!empty($o[$col])) {
            $steps[] = [$title, '', $T($o[$col]), 'done'];
        } elseif (!$closed && !$nowSet && $o['status'] === 'confirmed') {
            $sub = ($col === 'departed_at' || $col === 'arrived_at') && $o['delay_minutes']
                ? 'Kechikmoqda +' . (int) $o['delay_minutes'] . ' daq' . ($o['delay_reason'] ? ' — ' . $o['delay_reason'] : '') : '';
            $steps[] = [$title, $sub, null, 'now'];
            $nowSet = true;
        } else {
            $steps[] = [$title, '', null, 'todo'];
        }
    }
    $total = (float) $o['total_amount'];
    $com = (float) $o['commission'];
    if ($o['tariff']) {
        $pay[] = ['Tarif: ' . (int) $o['hours'] . ' soat', moneyFmt($total - (float) $o['delivery_fee'])];
    }
    if ((float) $o['delivery_fee'] > 0) {
        $pay[] = ['Yetkazib berish' . ($o['delivery_distance'] ? ' (' . (float) $o['delivery_distance'] . ' km)' : ''), moneyFmt($o['delivery_fee'])];
    }
    $pay[] = ['Jami mijozdan', moneyFmt($total), true];
    $pay[] = ['MoveX komissiyasi', '− ' . moneyFmt($com)];
    $pay[] = ['Texnika egasiga', moneyFmt($total - $com)];
    if ((float) $o['compensation'] > 0) {
        $pay[] = ['Kompensatsiya (E1/E7)', moneyFmt($o['compensation'])];
    }
    $payNote = $o['payment_method'] === 'cash'
        ? 'Naqd: mijoz egaga qo\'lda to\'laydi. Egada komissiya muzlatilgan: ' . moneyFmt($o['owner_frozen']) . ' so\'m'
        : ($o['payment_method'] === 'card' ? 'Karta: summa kartada bloklangan (hold), yakunda yechiladi'
            : 'Go wallet: mijoz balansida muzlatilgan: ' . moneyFmt($o['frozen_amount']) . ' so\'m');
    $cancelInfo = [$o['cancelled_by'] ?? null, $o['cancel_reason'] ?? null, $o['updated_at']];
} elseif ($kind === 'request') {
    $o = one($db, 'SELECT * FROM equipment_requests WHERE id = ?', [$id]);
    $min = (int) floor((time() - strtotime($o['created_at'])) / 60);
    $steps[] = ['Buyurtma yaratildi', equipmentTypeName($o['equipment_type']) . ($o['hours'] ? ' · ' . (int) $o['hours'] . ' soat' : ''), $T($o['created_at']), 'done'];
    if (in_array($o['status'], ['open', 'awaiting_payment'], true)) {
        $steps[] = ['Egalarga taklif yuborildi', $min . ' daqiqadan beri hech kim olmadi', null, 'now'];
    } elseif ($o['status'] === 'expired') {
        $steps[] = ['Texnika topilmadi', 'Muddati o\'tdi, muzlatish yechildi', $T($o['expires_at'] ?? $o['updated_at']), 'bad'];
    }
    $pay[] = ['Narx (tarif bo\'yicha)', moneyFmt($o['budget']), true];
    $payNote = $o['payment_method'] === 'cash' ? 'Naqd: mijozda garov muzlatilgan: ' . moneyFmt($o['frozen_amount']) . ' so\'m'
        : 'Muzlatilgan: ' . moneyFmt($o['frozen_amount']) . ' so\'m';
    $cancelInfo = [null, $o['cancel_reason'] ?? null, $o['updated_at']];
} elseif ($kind === 'freight') {
    $o = one($db, 'SELECT * FROM freight_orders WHERE id = ?', [$id]);
    $performerRole = 'Haydovchi';
    $performerExtra = deliveryVehicleName($o['vehicle_code']) . ($row['plate'] ? ' · ' . $row['plate'] : '');
    $min = (int) floor((time() - strtotime($o['created_at'])) / 60);
    $steps[] = ['Buyurtma yaratildi', deliveryVehicleName($o['vehicle_code']) . ($o['cargo_tonnes'] ? ' · ' . (float) $o['cargo_tonnes'] . ' t' : '')
        . ($o['scheduled_at'] ? ' · ' . date('d.m H:i', strtotime($o['scheduled_at'])) . ' ga' : ''), $T($o['created_at']), 'done'];
    $flow = [['accepted_at', 'Haydovchi qabul qildi'], ['loaded_at', 'Yuk ortildi'], ['arrived_at', 'Yetib keldi'], ['finished_at', 'Yakunlandi']];
    $nowSet = false;
    foreach ($flow as [$col, $title]) {
        if (!empty($o[$col])) {
            $steps[] = [$title, '', $T($o[$col]), 'done'];
        } elseif (!$closed && !$nowSet) {
            $steps[] = [$col === 'accepted_at' ? 'Haydovchi qidirilmoqda' : $title, $col === 'accepted_at' ? $min . ' daqiqadan beri' : '', null, 'now'];
            $nowSet = true;
        } else {
            $steps[] = [$title, '', null, 'todo'];
        }
    }
    $price = (float) $o['price'];
    $com = (float) ($o['driver_commission'] ?? 0);
    $pay[] = [($o['price_mode'] === 'hour' ? (int) $o['hours'] . ' soat' : 'Yo\'l ' . (float) $o['distance_km'] . ' km'), moneyFmt($price - (float) $o['loader_fee'])];
    if ((float) $o['loader_fee'] > 0) { $pay[] = ['Yuk ortuvchi', moneyFmt($o['loader_fee'])]; }
    $pay[] = ['Jami mijozdan', moneyFmt($price), true];
    if ($o['driver_id']) {
        $pay[] = ['MoveX komissiyasi', '− ' . moneyFmt($com)];
        $pay[] = ['Haydovchiga', moneyFmt($price - $com)];
    }
    $payNote = $o['payment_method'] === 'cash'
        ? 'Naqd haydovchiga. Haydovchida komissiya muzlatilgan: ' . moneyFmt($o['driver_frozen']) . ' so\'m'
        : 'Go wallet: mijoz balansida muzlatilgan: ' . moneyFmt($o['frozen_amount']) . ' so\'m';
    $cancelInfo = [$o['cancelled_by'] ?? null, $o['cancel_reason'] ?? null, $o['updated_at']];
} else { // material
    $o = one($db, 'SELECT m.*, p.title, p.material_type, p.address AS pickup FROM material_orders m LEFT JOIN material_products p ON p.id = m.product_id WHERE m.id = ?', [$id]);
    $seller = one($db, 'SELECT full_name, phone FROM users WHERE id = ?', [$o['seller_id']]);
    $performerRole = $o['driver_id'] ? 'Haydovchi' : 'Sotuvchi';
    $performerExtra = $o['driver_id'] ? deliveryVehicleName($o['vehicle_code']) . ($row['plate'] ? ' · ' . $row['plate'] : '') : ($o['title'] ?? '');
    $steps[] = ['Buyurtma yaratildi', ($o['title'] ?? '') . ' · ' . (float) $o['quantity'] . ' ' . materialUnitName($o['unit']), $T($o['created_at']), 'done'];
    $steps[] = [$o['status'] === 'pending' ? 'Sotuvchi tasdig\'i kutilmoqda' : 'Sotuvchi tasdiqladi', $seller['full_name'] ?? '', null,
                $o['status'] === 'pending' ? 'now' : ($o['status'] === 'rejected' ? 'bad' : 'done')];
    if ($o['dispatch'] === 'driver') {
        $flow = [['accepted_at', 'Haydovchi qabul qildi'], ['picked_up_at', 'Tovar olindi'], ['arrived_at', 'Yetib keldi']];
        $nowSet = $o['status'] === 'pending';
        foreach ($flow as [$col, $title]) {
            if (!empty($o[$col])) {
                $steps[] = [$title, '', $T($o[$col]), 'done'];
            } elseif (!$closed && !$nowSet) {
                $steps[] = [$col === 'accepted_at' ? 'Haydovchi qidirilmoqda' : $title, '', null, 'now'];
                $nowSet = true;
            } else {
                $steps[] = [$title, '', null, 'todo'];
            }
        }
    }
    $steps[] = ['Yetkazildi', 'Xaridor tasdiqlaydi', $o['status'] === 'delivered' ? $T($o['updated_at']) : null, $o['status'] === 'delivered' ? 'done' : 'todo'];
    $pay[] = ['Tovar: ' . (float) $o['quantity'] . ' × ' . moneyFmt($o['price_per_unit']), moneyFmt($o['goods_amount'])];
    $pay[] = ['Yetkazib berish' . ($o['delivery_distance_km'] ? ' (' . (float) $o['delivery_distance_km'] . ' km)' : ''), moneyFmt($o['delivery_fee'])];
    $pay[] = ['Jami xaridordan', moneyFmt((float) $o['goods_amount'] + (float) $o['delivery_fee']), true];
    $pay[] = ['Komissiya (sotuvchidan)', '− ' . moneyFmt($o['commission'])];
    if ($o['driver_id']) {
        $pay[] = ['Komissiya (haydovchidan)', '− ' . moneyFmt($o['driver_commission'])];
    }
    $payNote = 'Tovar — Go wallet (muzlatilgan: ' . moneyFmt($o['frozen_amount']) . ' so\'m). Yetkazish — '
        . ($o['delivery_payment'] === 'cash' ? 'naqd haydovchiga' : 'Go wallet');
    $cancelInfo = [$o['cancelled_by'] ?? null, $o['cancel_reason'] ?? null, $o['updated_at']];
}

if ($row['st'] === 'cancelled') {
    $by = ['admin' => 'admin', 'client' => 'mijoz', 'owner' => 'ijrochi', 'system' => 'tizim'][$cancelInfo[0] ?? ''] ?? null;
    $why = $cancelInfo[1] ? ($cancelReasons[$cancelInfo[1]][0] ?? $cancelInfo[1]) : '';
    $steps[] = [orderStatusBadge($row)[0], trim(($by ? 'Kim: ' . $by : '') . ($why ? ' · ' . $why : ''), ' ·'), $T($cancelInfo[2]), 'bad'];
}
$stepsDone = count(array_filter($steps, function ($s) { return $s[3] === 'done'; }));

// Mijoz va ijrochi statistikasi
$cStats = one($db, "SELECT COUNT(*) FILTER (WHERE kind <> 'request') AS n, COUNT(*) FILTER (WHERE st = 'cancelled') AS cx
                     FROM " . ordersUnionSql() . " WHERE u.client_id = ?", [$row['client_id']]);
$perf = $row['perf_id'] ? one($db, 'SELECT id, full_name, phone, is_blocked, is_frozen FROM users WHERE id = ?', [$row['perf_id']]) : [];
$pStats = $perf ? one($db, "SELECT COUNT(*) AS n, COUNT(*) FILTER (WHERE st = 'done') AS ok
                             FROM " . ordersUnionSql() . " WHERE u.perf_id = ?", [$perf['id']]) : [];
$rating = $perf ? one($db, 'SELECT ROUND(AVG(r.rating)::numeric, 1) AS r, COUNT(*) AS n FROM reviews r JOIN equipment e ON e.id = r.equipment_id WHERE e.owner_id = ? AND NOT r.hidden', [$perf['id']]) : [];

// Ijrochilar (O4) — faqat ijrochisi bor turlar
$cand = null;
if ($kind !== 'request' && !$closed) {
    $r = internalApiGet("/admin-orders/internal/$kind/$id/candidates");
    $cand = $r['ok'] ? $r['data'] : ['error' => $r['error']];
}

$notes = $db->prepare('SELECT n.*, u.full_name FROM order_notes n LEFT JOIN users u ON u.id = n.admin_id
                        WHERE n.kind = ? AND n.order_id = ? ORDER BY n.created_at DESC');
$notes->execute([$kind, $id]);
$notes = $notes->fetchAll();
$audit = $db->prepare("SELECT a.*, u.full_name FROM admin_actions a LEFT JOIN users u ON u.id = a.admin_id
                        WHERE a.entity = ? AND a.entity_id = ? ORDER BY a.created_at DESC LIMIT 30");
$audit->execute([$kind, $id]);
$audit = $audit->fetchAll();
$auditNames = ['order_cancel' => 'Bekor qildi', 'order_reassign' => 'Ijrochini almashtirdi',
               'order_requeue' => 'Qayta qidiruvga qaytardi', 'order_note' => 'Izoh qo\'shdi'];

[$stText, $stTone] = orderStatusBadge($row);
$late = !empty($row['stuck']);

include __DIR__ . '/header.php';
?>
<div class="content">
    <?php if ($flash): ?>
        <div class="alert alert-<?= $flash[0] === 'success' ? 'success' : 'error' ?>"><?= htmlspecialchars($flash[1]) ?></div>
    <?php endif; ?>

    <div class="od-head">
        <a class="icon-btn back" href="orders.php" aria-label="Orqaga" style="border:1px solid var(--border)"><i data-lucide="chevron-left"></i></a>
        <div>
            <h2>#<?= $id ?>
                <span class="badge badge-<?= $stTone ?>"><?= htmlspecialchars($stText) ?></span>
                <span class="badge badge-secondary no-dot"><?= ORDER_KINDS[$kind] ?></span>
            </h2>
            <div class="sub">Yaratildi <?= agoText($row['created_at']) ?> · <?= htmlspecialchars(orderWhat($row)) ?></div>
        </div>
        <div class="page-actions">
            <a class="btn btn-secondary btn-sm" href="#audit"><i data-lucide="history"></i> Audit</a>
        </div>
    </div>

    <?php if ($kind === 'equipment' && $row['st'] === 'assigned' && !empty($o['delay_minutes'])): ?>
        <div class="banner">
            <i data-lucide="triangle-alert"></i>
            <div><b>Ijrochi kechikmoqda: +<?= (int) $o['delay_minutes'] ?> daqiqa</b>
                <div class="sub"><?= htmlspecialchars($o['delay_reason'] ?: 'Sabab ko\'rsatilmagan') ?>. Mijoz ilovasida «Texnika kechikmoqda» ko'rinadi.</div></div>
            <?php if ($cand && !empty($cand['can_reassign'])): ?><button class="btn btn-secondary btn-sm" type="button" data-open="drawerReassign"><i data-lucide="repeat"></i> Almashtirish</button><?php endif; ?>
        </div>
    <?php elseif ($late): ?>
        <div class="banner danger">
            <i data-lucide="triangle-alert"></i>
            <div><b><?= (int) floor((time() - strtotime($row['wait_since'])) / 60) ?> daqiqadan beri ijrochi topilmayapti</b>
                <div class="sub">Mos haydovchi/ega yo'q, oflayn yoki radius tor. Qo'lda tayinlash yoki bekor qilish mumkin.</div></div>
            <?php if ($cand && !empty($cand['can_reassign'])): ?><button class="btn btn-secondary btn-sm" type="button" data-open="drawerReassign">Qo'lda tayinlash</button><?php endif; ?>
        </div>
    <?php endif; ?>

    <div class="od-grid">
        <div>
            <div class="card">
                <div class="card-header"><div class="card-title">Holatlar tarixi</div><span class="text-muted num" style="font-size:12.5px"><?= $stepsDone ?> / <?= count($steps) ?></span></div>
                <div class="card-body">
                    <ul class="timeline">
                        <?php foreach ($steps as [$t, $s, $time, $state]): ?>
                            <li class="<?= $state ?>">
                                <span class="dot"><?php if ($state === 'done'): ?><i data-lucide="check"></i><?php endif; ?></span>
                                <div><div class="t"><?= htmlspecialchars($t) ?></div><?php if ($s): ?><div class="s"><?= htmlspecialchars($s) ?></div><?php endif; ?></div>
                                <span class="time"><?= $time ?: ($state === 'now' ? 'hozir' : '—') ?></span>
                            </li>
                        <?php endforeach; ?>
                    </ul>
                </div>
            </div>

            <div class="card">
                <div class="card-header"><div class="card-title">To'lov tafsiloti</div>
                    <?php [$pm, $ps] = orderPaymentLabel($row); ?>
                    <span class="badge badge-<?= $ps === 'Bloklangan' ? 'warning' : ($ps === 'Yechildi' ? 'success' : 'secondary') ?>"><?= $pm . ($ps ? ' · ' . $ps : '') ?></span></div>
                <div class="card-body pay-rows">
                    <?php foreach ($pay as $p): ?>
                        <div class="r <?= !empty($p[2]) ? 'total' : '' ?>"><span><?= htmlspecialchars($p[0]) ?></span><b><?= $p[1] ?> so'm</b></div>
                    <?php endforeach; ?>
                    <div class="form-hint mt-1"><?= htmlspecialchars($payNote) ?></div>
                </div>
            </div>

            <div class="card" id="audit">
                <div class="card-header"><div class="card-title">Audit — admin amallari</div></div>
                <?php if (!$audit): ?>
                    <div class="empty-state" style="padding:20px">Bu buyurtmada admin amali bo'lmagan</div>
                <?php else: ?>
                    <div class="table-responsive"><table>
                        <thead><tr><th>Vaqt</th><th>Admin</th><th>Amal</th><th>Tafsilot</th></tr></thead>
                        <tbody>
                        <?php foreach ($audit as $a): $pl = json_decode((string) $a['payload'], true) ?: []; ?>
                            <tr>
                                <td class="num text-muted"><?= agoText($a['created_at']) ?></td>
                                <td><?= htmlspecialchars($a['full_name'] ?? '—') ?></td>
                                <td><?= $auditNames[$a['action']] ?? htmlspecialchars($a['action']) ?></td>
                                <td class="text-muted" style="font-size:12.5px">
                                    <?php
                                    $bits = [];
                                    if (!empty($pl['reason'])) { $bits[] = $cancelReasons[$pl['reason']][0] ?? $pl['reason']; }
                                    if (!empty($pl['released']) && (float) $pl['released'] > 0) { $bits[] = 'qaytdi ' . moneyFmt($pl['released']); }
                                    if (!empty($pl['to_user'])) { $bits[] = 'yangi ijrochi #' . (int) $pl['to_user']; }
                                    if (!empty($pl['note'])) { $bits[] = '«' . $pl['note'] . '»'; }
                                    if (!empty($pl['text'])) { $bits[] = '«' . $pl['text'] . '»'; }
                                    echo htmlspecialchars(implode(' · ', $bits));
                                    ?>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                        </tbody>
                    </table></div>
                <?php endif; ?>
            </div>
        </div>

        <div>
            <div class="card"><div class="card-body">
                <div class="d-flex justify-between align-center mb-1"><b>Mijoz</b>
                    <a class="card-link" href="users.php?search=<?= urlencode($row['client_phone']) ?>">Profil →</a></div>
                <div class="person">
                    <div class="user-avatar"><?= htmlspecialchars(mb_strtoupper(mb_substr($row['client_name'], 0, 2))) ?></div>
                    <div><b><?= htmlspecialchars($row['client_name']) ?></b><small class="num"><?= maskPhone($row['client_phone']) ?></small></div>
                </div>
                <div class="mini-stats">
                    <div><b><?= (int) ($cStats['n'] ?? 0) ?></b><small>buyurtma</small></div>
                    <div><b><?= (int) ($cStats['cx'] ?? 0) ?></b><small>bekor</small></div>
                    <div><b><?= htmlspecialchars(orderPaymentLabel($row)[0]) ?></b><small>to'lov</small></div>
                </div>
                <a class="btn btn-secondary btn-sm btn-block" href="tel:+<?= htmlspecialchars($row['client_phone']) ?>"><i data-lucide="phone"></i> Qo'ng'iroq</a>
            </div></div>

            <div class="card"><div class="card-body">
                <div class="d-flex justify-between align-center mb-1"><b><?= $performerRole ?></b>
                    <?php if ($perf): ?><a class="card-link" href="users.php?search=<?= urlencode($perf['phone']) ?>">Profil →</a><?php endif; ?></div>
                <?php if (!$perf): ?>
                    <div class="text-muted" style="font-size:13px">Hali tayinlanmagan</div>
                <?php else: ?>
                    <div class="person">
                        <div class="user-avatar"><?= htmlspecialchars(mb_strtoupper(mb_substr($perf['full_name'], 0, 2))) ?></div>
                        <div><b><?= htmlspecialchars($perf['full_name']) ?></b><small><?= htmlspecialchars($performerExtra) ?></small></div>
                    </div>
                    <div class="mini-stats">
                        <div><b><?= !empty($rating['r']) ? $rating['r'] . ' ★' : '—' ?></b><small>reyting</small></div>
                        <div><b><?= (int) ($pStats['n'] ?? 0) ?></b><small>buyurtma</small></div>
                        <div><b><?= ($pStats['n'] ?? 0) ? round($pStats['ok'] / $pStats['n'] * 100) . '%' : '—' ?></b><small>yakunlangan</small></div>
                    </div>
                    <a class="btn btn-secondary btn-sm btn-block" href="tel:+<?= htmlspecialchars($perf['phone']) ?>"><i data-lucide="phone"></i> Qo'ng'iroq · <span class="num"><?= maskPhone($perf['phone']) ?></span></a>
                <?php endif; ?>
            </div></div>

            <div class="card"><div class="card-body">
                <b>Admin amallari</b>
                <ul class="action-list mt-1">
                    <?php if ($kind !== 'request'): ?>
                        <li>
                            <?php $canR = $cand && !empty($cand['can_reassign']); ?>
                            <button type="button" data-open="drawerReassign" <?= $canR ? '' : 'disabled' ?>>
                                <i data-lucide="repeat"></i>
                                <span><?= $kind === 'equipment' ? 'Texnikani almashtirish' : 'Haydovchini almashtirish' ?>
                                    <?php if (!$canR): ?><span class="why"><?= htmlspecialchars($closed ? 'Buyurtma yopilgan' : ($cand['note'] ?? $cand['error'] ?? '')) ?></span><?php endif; ?></span>
                                <i data-lucide="chevron-right" class="chev"></i>
                            </button>
                        </li>
                    <?php endif; ?>
                    <li>
                        <button type="button" class="danger" data-open="modalCancel" <?= $closed ? 'disabled' : '' ?>>
                            <i data-lucide="circle-x"></i>
                            <span>Buyurtmani bekor qilish<?php if ($closed): ?><span class="why">Buyurtma yopilgan</span><?php endif; ?></span>
                            <i data-lucide="chevron-right" class="chev"></i>
                        </button>
                    </li>
                </ul>
            </div></div>

            <div class="card"><div class="card-body">
                <div class="d-flex justify-between align-center mb-1"><b>Ichki izoh</b><span class="text-muted" style="font-size:11.5px">faqat adminlar ko'radi</span></div>
                <?php foreach ($notes as $n): ?>
                    <div class="note"><?= htmlspecialchars($n['text']) ?><small><?= htmlspecialchars($n['full_name'] ?? 'admin') ?> · <?= agoText($n['created_at']) ?></small></div>
                <?php endforeach; ?>
                <form method="post" class="mt-1">
                    <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
                    <input type="hidden" name="action" value="note">
                    <textarea name="text" rows="2" placeholder="Masalan: mijoz qo'ng'iroq qildi, 10:30 gacha kutadi" required maxlength="2000"></textarea>
                    <button class="btn btn-secondary btn-sm mt-1" type="submit"><i data-lucide="plus"></i> Qo'shish</button>
                </form>
            </div></div>
        </div>
    </div>
</div>

<?php if (!$closed): ?>
<!-- O3 · Bekor qilish -->
<div class="modal" id="modalCancel" role="dialog" aria-modal="true" aria-labelledby="cancelTitle">
    <form class="modal-content" method="post" style="max-width:480px">
        <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
        <input type="hidden" name="action" value="cancel">
        <div class="modal-header">
            <div class="d-flex gap-1 align-center">
                <span class="stat-icon danger"><i data-lucide="circle-x"></i></span>
                <div><div class="modal-title" id="cancelTitle">Buyurtmani bekor qilish</div>
                    <div class="text-muted" style="font-size:12.5px">#<?= $id ?> · bu amalni ortga qaytarib bo'lmaydi</div></div>
            </div>
            <button class="modal-close" type="button" data-close aria-label="Yopish">×</button>
        </div>
        <div class="modal-body">
            <div class="form-section" style="margin-top:0">Sabab (majburiy)</div>
            <?php foreach ($cancelReasons as $k => [$t, $s]): ?>
                <label class="choice"><input type="radio" name="reason" value="<?= $k ?>" required>
                    <span><b><?= htmlspecialchars($t) ?></b><?php if ($s): ?><small><?= htmlspecialchars($s) ?></small><?php endif; ?></span></label>
            <?php endforeach; ?>
            <div class="alert alert-info mt-1" style="margin-bottom:0">
                <i data-lucide="info"></i>
                <div>Jarima yo'q — mijozdan pul olinmaydi.
                    <?php if ($kind === 'equipment' && ($o['payment_method'] ?? '') === 'card'): ?>Karta holdi yechiladi (bank 1–3 ish kunida qaytaradi).
                    <?php elseif (in_array($row['payment'], ['cash'], true)): ?>Naqd buyurtma: ijrochi va mijozdagi muzlatishlar yechiladi.
                    <?php else: ?>Muzlatilgan summa mijoz balansiga qaytadi.<?php endif; ?></div>
            </div>
            <div class="form-group mt-2">
                <label for="cancelNote">Izoh (audit jurnaliga yoziladi)</label>
                <textarea id="cancelNote" name="note" rows="3" required placeholder="Nima bo'ldi va nega bekor qilinyapti"></textarea>
            </div>
            <label class="d-flex gap-1 align-center" style="font-size:13px"><input type="checkbox" name="notify" value="1" checked> Mijoz va ijrochiga bildirishnoma yuborish</label>
        </div>
        <div class="modal-footer">
            <button class="btn btn-secondary" type="button" data-close>Ortga</button>
            <button class="btn btn-danger" type="submit">Bekor qilish</button>
        </div>
    </form>
</div>
<?php endif; ?>

<?php if ($cand && !empty($cand['can_reassign'])): ?>
<!-- O4 · Ijrochini almashtirish -->
<div class="drawer" id="drawerReassign" role="dialog" aria-modal="true" aria-labelledby="reTitle">
    <form class="drawer-panel" method="post">
        <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
        <input type="hidden" name="action" value="reassign">
        <div class="drawer-head">
            <div><div class="modal-title" id="reTitle"><?= $kind === 'equipment' ? 'Texnikani almashtirish' : 'Haydovchini almashtirish' ?></div>
                <div class="text-muted" style="font-size:12.5px">#<?= $id ?> · <?= htmlspecialchars(orderWhat($row)) ?></div></div>
            <button class="modal-close" type="button" data-close aria-label="Yopish">×</button>
        </div>
        <div class="drawer-body">
            <?php if ($perf): ?>
                <div class="alert alert-warning"><i data-lucide="triangle-alert"></i>
                    <div>Joriy ijrochi: <b><?= htmlspecialchars($perf['full_name']) ?></b>. Almashtirilsa, unga bildirishnoma boradi
                        <?= $row['payment'] === 'cash' ? 'va uning muzlatilgan komissiyasi yechiladi' : '' ?>.</div></div>
            <?php endif; ?>
            <div class="form-section">Mos ijrochilar — yaqinroqlari tepada</div>
            <?php $firstOk = true; $shown = 0;
            foreach ($cand['candidates'] as $c):
                if (!empty($c['current'])) { continue; }
                $val = $kind === 'equipment' ? ($c['equipment_id'] ?? '') : $c['user_id'];
                $dis = $c['reason'] !== null; $shown++;
            ?>
                <label class="choice <?= $dis ? 'disabled' : '' ?>">
                    <input type="radio" name="target" value="<?= (int) $val ?>" <?= $dis ? 'disabled' : '' ?> <?= !$dis && $firstOk ? 'checked' : '' ?> required>
                    <span>
                        <b><?= htmlspecialchars($c['name']) ?></b>
                        <small><?= $c['distance_km'] !== null ? $c['distance_km'] . ' km' : 'joylashuv yo\'q' ?>
                            <?= $c['online'] === true ? ' · onlayn' : ($c['online'] === false ? ' · oflayn' : '') ?>
                            <?= !empty($c['model']) ? ' · ' . htmlspecialchars($c['model']) : '' ?>
                            <?= $c['plate'] ? ' · ' . htmlspecialchars($c['plate']) : '' ?></small>
                        <?php if ($dis): ?><small class="why"><?= htmlspecialchars($c['reason']) ?></small><?php endif; ?>
                    </span>
                    <?php if (!$dis && $firstOk): $firstOk = false; ?><span class="tag">Eng yaqin</span><?php endif; ?>
                </label>
            <?php endforeach; ?>
            <?php if ($shown === 0): ?>
                <div class="empty-state" style="padding:16px">Bu turdagi boshqa ijrochi ro'yxatdan o'tmagan</div>
            <?php endif; ?>
            <?php if ($kind !== 'equipment'): ?>
                <label class="choice"><input type="radio" name="target" value="requeue" <?= $firstOk ? 'checked' : '' ?>>
                    <span><b>Haydovchini olib, qayta qidiruvga qaytarish</b><small>Buyurtma yana mos haydovchilarga ko'rinadi</small></span></label>
            <?php endif; ?>
            <div class="form-group mt-2">
                <label for="reNote">Izoh (audit jurnaliga)</label>
                <textarea id="reNote" name="note" rows="2" placeholder="Masalan: haydovchi 20 daqiqa kechikdi"></textarea>
            </div>
        </div>
        <div class="drawer-foot">
            <button class="btn btn-secondary" type="button" data-close>Bekor</button>
            <button class="btn btn-primary" type="submit">Tayinlash</button>
        </div>
    </form>
</div>
<?php endif; ?>

<script>
document.querySelectorAll('[data-open]').forEach(b => b.addEventListener('click', () => {
    const el = document.getElementById(b.dataset.open);
    if (el) el.classList.add('active');
}));
document.querySelectorAll('.modal, .drawer').forEach(m => {
    m.addEventListener('click', e => { if (e.target === m || e.target.closest('[data-close]')) m.classList.remove('active'); });
});
document.addEventListener('keydown', e => {
    if (e.key === 'Escape') document.querySelectorAll('.modal.active, .drawer.active').forEach(m => m.classList.remove('active'));
});
</script>
<?php include __DIR__ . '/footer.php'; ?>
