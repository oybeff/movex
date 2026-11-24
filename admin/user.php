<?php
/**
 * C2 · Mijoz / haydovchi profili, C3 · bloklash modal, C4 · bloklangan
 * profil banneri, H2 · haydovchi hujjatlari (Figma «Admin panel» 03, 04).
 *
 * Bloklash, blokdan chiqarish va xabar — backend orqali
 * (/users/internal/...): faol buyurtmani bekor qilish, SMS va audit bitta
 * joyda. Sovg'a va naqd pul — /balance/internal/... (pul mantig'i
 * backend'da). Qolganlari (rol, telefon, parol, muzlatish, e'lon narxi) —
 * pulga tegmaydi, to'g'ridan-to'g'ri bazaga, lekin audit jurnaliga yoziladi.
 *
 * Qattiq o'chirish (DELETE FROM users) yo'q: CASCADE ikkinchi tomonning
 * buyurtma va pul yozuvlarini ham o'chirib yuborardi. Akkauntni mijoz o'zi
 * ilovadan o'chiradi (obezlichivanie).
 */
require_once 'config.php';
requireAdmin();
requirePerm('orders_view');
requireCsrfToken();
require_once __DIR__ . '/includes/user_lib.php';

$db = getDbConnection();
$id = (int) ($_GET['id'] ?? 0);
$adminId = (int) ($_SESSION['admin_user_id'] ?? 0);
$self = 'user.php?id=' . $id;

$u = $db->prepare('SELECT u.*, b.full_name AS blocked_by_name FROM users u LEFT JOIN users b ON b.id = u.blocked_by WHERE u.id = ?');
$u->execute([$id]);
$u = $u->fetch();
if (!$u) {
    http_response_code(404);
    $pageTitle = 'Topilmadi';
    $currentPage = 'users';
    include 'includes/header.php';
    echo '<div class="content"><div class="empty-state"><b>Foydalanuvchi topilmadi</b><div class="mt-1"><a href="users.php">Mijozlar ro\'yxatiga</a></div></div></div>';
    include 'includes/footer.php';
    exit;
}
$isOwner = $u['role'] === 'owner';
$isAdminAcc = $u['role'] === 'admin';
$deleted = isDeletedUser($u);

function auditUser(PDO $db, int $adminId, string $action, int $userId, array $payload = []): void
{
    auditLog($action, 'user', $userId, $payload, $adminId ?: null);
}

function flash(string $type, string $text): void
{
    $_SESSION['user_flash'] = [$type, $text];
}

// ----------------------------------------------------------------- POST
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';
    requirePerm(in_array($action, ['grant_bonus', 'cash_topup', 'set_listing_fee'], true) ? 'finance' : 'users_block', 'full');
    if ($isAdminAcc) {
        flash('error', "Admin hisobiga bu amalni qo'llab bo'lmaydi");
    } else {
        switch ($action) {
            case 'block':
                $res = internalApiPost('/users/internal/' . $id . '/block', [
                    'admin_id' => $adminId,
                    'reason' => (string) ($_POST['reason'] ?? ''),
                    'duration' => (string) ($_POST['duration'] ?? ''),
                    'note' => trim((string) ($_POST['note'] ?? '')),
                    'send_sms' => !empty($_POST['send_sms']),
                    'cancel_active' => !empty($_POST['cancel_active']),
                ]);
                if ($res['ok']) {
                    $msg = 'Bloklandi.';
                    if (!empty($res['data']['cancelled'])) {
                        $msg .= ' Bekor qilindi: ' . implode(', ', $res['data']['cancelled']) . '.';
                    }
                    if (isset($res['data']['sms'])) {
                        $msg .= $res['data']['sms']['sent'] ? ' SMS yuborildi.'
                            : ' SMS yuborilmadi (Eskiz: matn shablon sifatida tasdiqlanmagan bo\'lishi mumkin).';
                    }
                    flash('success', $msg);
                } else {
                    flash('error', 'Bloklanmadi: ' . $res['error']);
                }
                break;
            case 'unblock':
                $res = internalApiPost('/users/internal/' . $id . '/unblock', ['admin_id' => $adminId, 'send_sms' => !empty($_POST['send_sms'])]);
                $sms = $res['data']['sms'] ?? null;
                flash($res['ok'] ? 'success' : 'error', $res['ok'] ? 'Blokdan chiqarildi.' . ($sms === null ? '' : ($sms['sent'] ? ' SMS yuborildi.' : " SMS yuborilmadi (Eskiz shabloni hali tasdiqlanmagan bo'lishi mumkin).")) : 'Xato: ' . $res['error']);
                break;
            case 'message':
                $res = internalApiPost('/users/internal/' . $id . '/message', [
                    'admin_id' => $adminId, 'text' => trim((string) ($_POST['text'] ?? '')), 'sms' => !empty($_POST['sms']),
                ]);
                if ($res['ok']) {
                    $sms = $res['data']['sms'] ?? null;
                    flash('success', 'Xabar ilovaga yuborildi.' . ($sms === null ? '' : ($sms['sent'] ? ' SMS ham ketdi.' : ' SMS yuborilmadi (Eskiz shablon talab qiladi).')));
                } else {
                    flash('error', 'Yuborilmadi: ' . $res['error']);
                }
                break;
            case 'freeze':
            case 'unfreeze':
                $db->prepare('UPDATE users SET is_frozen = ? WHERE id = ?')->execute([$action === 'freeze' ? 'true' : 'false', $id]);
                auditUser($db, $adminId, 'user_' . $action, $id);
                flash('success', $action === 'freeze' ? "Muzlatildi — ko'radi, lekin buyurtma bera olmaydi" : 'Muzlatish olib tashlandi');
                break;
            case 'set_role':
                $role = $_POST['role'] ?? '';
                if (!in_array($role, ['client', 'owner'], true)) {
                    flash('error', "Rol faqat mijoz yoki ega bo'lishi mumkin");
                } else {
                    $db->prepare('UPDATE users SET role = ? WHERE id = ?')->execute([$role, $id]);
                    auditUser($db, $adminId, 'user_role', $id, ['role' => $role]);
                    flash('success', "Rol o'zgartirildi");
                }
                break;
            case 'set_phone':
                $phone = preg_replace('/\D/', '', (string) ($_POST['phone'] ?? ''));
                if (strlen($phone) !== 12 || strpos($phone, '998') !== 0) {
                    flash('error', "Telefon 998 bilan boshlanib, 12 raqamdan iborat bo'lsin");
                } else {
                    $busy = $db->prepare('SELECT id FROM users WHERE phone = ? AND id <> ?');
                    $busy->execute([$phone, $id]);
                    if ($busy->fetch()) {
                        flash('error', 'Bu raqam boshqa hisobda band');
                    } else {
                        $db->prepare('UPDATE users SET phone = ? WHERE id = ?')->execute([$phone, $id]);
                        auditUser($db, $adminId, 'user_phone', $id, ['phone' => $phone]);
                        flash('success', "Telefon raqam o'zgartirildi");
                    }
                }
                break;
            case 'set_password':
                $pw = (string) ($_POST['password'] ?? '');
                if (strlen($pw) < 6) {
                    flash('error', "Parol kamida 6 belgidan iborat bo'lsin");
                } else {
                    $db->prepare('UPDATE users SET password_hash = ? WHERE id = ?')->execute([password_hash($pw, PASSWORD_BCRYPT), $id]);
                    auditUser($db, $adminId, 'user_password', $id);
                    flash('success', "Parol o'rnatildi. Uni foydalanuvchiga o'zingiz ayting — panel saqlamaydi.");
                }
                break;
            case 'grant_bonus':
            case 'cash_topup':
                $amount = (int) preg_replace('/\D/', '', (string) ($_POST['amount'] ?? ''));
                if ($amount <= 0) {
                    flash('error', 'Summani kiriting');
                    break;
                }
                $res = internalApiPost($action === 'grant_bonus' ? '/balance/internal/bonus' : '/balance/internal/cash_topup', [
                    'user_id' => $id, 'amount' => $amount, 'comment' => trim((string) ($_POST['comment'] ?? '')),
                ]);
                if ($res['ok']) {
                    auditUser($db, $adminId, 'user_' . $action, $id, ['amount' => $amount]);
                    flash('success', moneyFmt($amount) . ($action === 'grant_bonus'
                        ? " so'm sovg'a berildi — kartaga yechib bo'lmaydi."
                        : " so'm naqd qabul qilindi va balansga yozildi."));
                } else {
                    flash('error', 'Bajarilmadi: ' . $res['error']);
                }
                break;
            case 'set_listing_fee':
                $raw = trim((string) ($_POST['listing_fee'] ?? ''));
                if ($raw !== '' && !ctype_digit($raw)) {
                    flash('error', "E'lon narxi butun son bo'lsin (yoki bo'sh qoldiring)");
                } else {
                    $db->prepare('UPDATE users SET listing_fee_override = ? WHERE id = ?')->execute([$raw === '' ? null : (int) $raw, $id]);
                    auditUser($db, $adminId, 'user_listing_fee', $id, ['fee' => $raw]);
                    flash('success', "E'lon narxi saqlandi");
                }
                break;
            default:
                flash('error', "Noma'lum amal");
        }
    }
    header('Location: ' . $self . (isset($_GET['t']) ? '&t=' . urlencode($_GET['t']) : ''));
    exit;
}

$flashMsg = $_SESSION['user_flash'] ?? null;
unset($_SESSION['user_flash']);

// ----------------------------------------------------------------- ma'lumotlar
function q1(PDO $db, string $sql, array $p = [])
{
    $st = $db->prepare($sql);
    $st->execute($p);
    return $st->fetch();
}
function qa(PDO $db, string $sql, array $p = []): array
{
    $st = $db->prepare($sql);
    $st->execute($p);
    return $st->fetchAll();
}

$cs = q1($db, 'SELECT * FROM (' . clientStatsSql() . ') s WHERE s.uid = ?', [$id]) ?: ['n' => 0, 'done' => 0, 'cx' => 0, 'paid' => 0];
$ps = $isOwner ? (q1($db, 'SELECT * FROM (' . perfStatsSql() . ') s WHERE s.uid = ?', [$id]) ?: ['n' => 0, 'done' => 0, 'cx' => 0, 'earned' => 0]) : null;
$bal = q1($db, 'SELECT balance, frozen_balance, bonus_balance FROM balances WHERE user_id = ?', [$id]) ?: ['balance' => 0, 'frozen_balance' => 0, 'bonus_balance' => 0];
$clientRating = q1($db, 'SELECT ROUND(AVG(rating)::numeric, 1) AS r, COUNT(*) AS n FROM client_ratings WHERE client_id = ?', [$id]);
$ownerRating = $isOwner ? q1($db, 'SELECT ROUND(AVG(r.rating)::numeric, 1) AS r, COUNT(*) AS n FROM reviews r JOIN equipment e ON e.id = r.equipment_id
                                    WHERE e.owner_id = ? AND NOT r.hidden', [$id]) : null;
$pct = cancelPct($cs['n'], $cs['cx']);
[$stText, $stTone] = userStatusBadge($u, $pct);

$cards = qa($db, 'SELECT pan, ps, is_default, status, created_at FROM user_cards WHERE user_id = ? ORDER BY is_default DESC, created_at DESC', [$id]);
$addresses = qa($db, 'SELECT kind, title, address, created_at FROM user_addresses WHERE user_id = ? ORDER BY created_at DESC', [$id]);
$problemCount = (int) q1($db, 'SELECT COUNT(*) AS c FROM order_problems WHERE user_id = ?', [$id])['c'];
$docs = $isOwner ? qa($db, 'SELECT d.*, a.full_name AS reviewer FROM driver_documents d LEFT JOIN users a ON a.id = d.reviewed_by
                            WHERE d.user_id = ? ORDER BY d.id', [$id]) : [];
$equipment = $isOwner ? qa($db, 'SELECT id, type, model, plate_number, status, deleted_at, created_at FROM equipment WHERE owner_id = ? ORDER BY created_at DESC', [$id]) : [];
$truck = $isOwner ? q1($db, 'SELECT p.*, v.name AS vehicle_name FROM delivery_driver_profiles p LEFT JOIN delivery_vehicles v ON v.code = p.vehicle_code WHERE p.user_id = ?', [$id]) : null;

$tabs = ['orders' => 'Buyurtmalar', 'payments' => "To'lovlar", 'cards' => 'Kartalar', 'addresses' => 'Manzillar',
         'problems' => 'Shikoyatlar', 'audit' => 'Audit'];
if ($isOwner) {
    $tabs = ['docs' => 'Hujjatlar', 'equipment' => 'Texnika'] + $tabs;
}
$t = $_GET['t'] ?? ($isOwner ? 'docs' : 'orders');
if (!isset($tabs[$t])) {
    $t = 'orders';
}

$orders = [];
if ($t === 'orders') {
    $orders = qa($db, 'SELECT u.* FROM ' . ordersUnionSql('u') . ' WHERE u.client_id = ? OR u.perf_id = ? ORDER BY u.created_at DESC LIMIT 50', [$id, $id]);
}
$txs = $t === 'payments' ? qa($db, 'SELECT * FROM balance_transactions WHERE user_id = ? ORDER BY created_at DESC LIMIT 100', [$id]) : [];
$problems = $t === 'problems' ? qa($db, 'SELECT * FROM order_problems WHERE user_id = ? ORDER BY created_at DESC LIMIT 50', [$id]) : [];
$audit = $t === 'audit' ? qa($db, "SELECT a.*, x.full_name FROM admin_actions a LEFT JOIN users x ON x.id = a.admin_id
                                    WHERE a.entity = 'user' AND a.entity_id = ? ORDER BY a.created_at DESC LIMIT 100", [$id]) : [];
$active = [];
if (!$isAdminAcc && !$deleted && !$u['is_blocked']) {
    $r = internalApiGet('/users/internal/' . $id . '/active-orders');
    $active = $r['ok'] && is_array($r['data']) ? $r['data'] : [];
}

$txNames = ['topup' => "To'ldirish", 'payment' => "To'lov", 'income' => 'Daromad', 'refund' => 'Qaytarish',
            'withdrawal' => 'Pul yechish', 'bonus' => "Sovg'a", 'listing_fee' => "E'lon narxi"];
$auditNames = ['user_block' => 'Blokladi', 'user_unblock' => 'Blokdan chiqardi', 'user_message' => 'Xabar yubordi',
               'user_sms' => 'SMS yubordi', 'user_freeze' => 'Muzlatdi', 'user_unfreeze' => 'Muzlatishni oldi',
               'user_role' => "Rolni o'zgartirdi", 'user_phone' => "Telefonni o'zgartirdi", 'user_password' => "Parol o'rnatdi",
               'user_grant_bonus' => "Sovg'a berdi", 'user_cash_topup' => 'Naqd pul qabul qildi', 'user_listing_fee' => "E'lon narxini o'zgartirdi"];
$docNames = ['id_front' => 'ID karta — old', 'id_back' => 'ID karta — orqa', 'license_front' => 'Prava — old', 'license_back' => 'Prava — orqa',
             'tech_front' => 'Texpasport — old', 'tech_back' => 'Texpasport — orqa', 'car_front' => 'Mashina — old', 'car_back' => 'Mashina — orqa',
             'car_left' => 'Mashina — chap', 'car_right' => "Mashina — o'ng", 'passport' => 'Pasport (eski)', 'driver_license' => 'Prava (eski)',
             'tech_passport' => 'Texpasport (eski)', 'equipment_photo' => 'Texnika fotosi (eski)', 'insurance' => "Sug'urta"];

$pageTitle = $u['full_name'] ?: 'Profil';
$currentPage = $isOwner ? 'haydovchilar' : 'users';
include 'includes/header.php';
?>
<div class="content">
    <?php if ($flashMsg): ?>
        <div class="alert alert-<?= $flashMsg[0] === 'success' ? 'success' : 'error' ?>"><?= htmlspecialchars($flashMsg[1]) ?></div>
    <?php endif; ?>

    <div class="od-head">
        <a class="icon-btn back" href="<?= $isOwner ? 'haydovchilar.php' : 'users.php' ?>" aria-label="Orqaga" style="border:1px solid var(--border)"><i data-lucide="chevron-left"></i></a>
        <div>
            <h2><?= htmlspecialchars($u['full_name'] ?: 'Ism kiritilmagan') ?>
                <span class="badge badge-<?= $stTone ?>"><?= htmlspecialchars($stText) ?></span>
                <span class="badge badge-secondary no-dot"><?= $isOwner ? 'Haydovchi / ega' : ($isAdminAcc ? 'Admin' : 'Mijoz') ?></span>
            </h2>
            <div class="sub num"><?= $deleted ? 'telefon o\'chirilgan' : htmlspecialchars(fmtPhone($u['phone'])) ?> · ID <?= $id ?> · ro'yxatdan <?= date('d.m.Y', strtotime($u['created_at'])) ?></div>
        </div>
        <?php if (!$isAdminAcc && !$deleted): ?>
            <div class="page-actions">
                <button class="btn btn-secondary btn-sm" type="button" data-open="modalMessage"><i data-lucide="send"></i> Xabar yuborish</button>
                <?php if ($u['is_blocked']): ?>
                    <form method="post" style="display:inline">
                        <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
                        <input type="hidden" name="action" value="unblock">
                        <label class="check" style="font-size:12.5px;margin-right:6px" title="MoveX GO: hisobingiz blokdan chiqarildi. Ilovadan yana foydalanishingiz mumkin."><input type="checkbox" name="send_sms" value="1" checked> SMS</label>
                        <button class="btn btn-primary btn-sm" type="submit"><i data-lucide="lock-open"></i> Blokdan chiqarish</button>
                    </form>
                <?php else: ?>
                    <button class="btn btn-danger btn-sm" type="button" data-open="modalBlock"><i data-lucide="ban"></i> Bloklash</button>
                <?php endif; ?>
            </div>
        <?php endif; ?>
    </div>

    <?php if ($u['is_blocked'] && !$deleted): ?>
        <div class="banner danger">
            <i data-lucide="triangle-alert"></i>
            <div>
                <b>Bloklangan · <?= htmlspecialchars(blockUntilText($u['blocked_until'])) ?><?= $u['block_reason_code'] ? ' · sabab: ' . htmlspecialchars(BLOCK_REASONS[$u['block_reason_code']][0] ?? $u['block_reason_code']) : '' ?></b>
                <div class="sub"><?= htmlspecialchars(($u['blocked_by_name'] ?? 'Admin') . ($u['blocked_at'] ? ', ' . date('d.m.Y H:i', strtotime($u['blocked_at'])) : '')) ?>.
                    <?= $u['block_note'] ? 'Izoh: «' . htmlspecialchars($u['block_note']) . '». ' : '' ?>
                    Ilovada mijoz ko'radi: «<?= htmlspecialchars((string) $u['blocked_reason']) ?>»</div>
            </div>
            <a class="btn btn-secondary btn-sm" href="<?= $self ?>&t=audit"><i data-lucide="history"></i> Audit</a>
        </div>
    <?php elseif ($deleted): ?>
        <div class="banner"><i data-lucide="user-x"></i><div><b>Akkaunt o'chirilgan</b>
            <div class="sub">Foydalanuvchi o'zi ilovadan o'chirgan. Ism va telefon o'chirilgan, buyurtma va to'lovlar ikkinchi tomon uchun saqlangan.</div></div></div>
    <?php endif; ?>

    <div class="stats-grid" style="grid-template-columns:repeat(5,minmax(0,1fr))">
        <div class="stat-card"><div class="stat-value"><?= (int) $cs['n'] ?></div><div class="stat-title">buyurtma (mijoz sifatida)</div></div>
        <div class="stat-card"><div class="stat-value"><?= moneyFmt($cs['paid']) ?></div><div class="stat-title">jami to'lagan, so'm</div></div>
        <div class="stat-card"><div class="stat-value <?= $pct !== null && $pct > 30 ? 'text-danger' : '' ?>"><?= $pct === null ? '—' : $pct . '%' ?></div><div class="stat-title">bekor qilingan</div></div>
        <?php if ($isOwner): ?>
            <div class="stat-card"><div class="stat-value"><?= (int) $ps['done'] ?> / <?= moneyFmt($ps['earned']) ?></div><div class="stat-title">bajargan / topgan, so'm</div></div>
            <div class="stat-card"><div class="stat-value"><?= $ownerRating['n'] ? $ownerRating['r'] . ' ★' : '—' ?></div><div class="stat-title">mijozlar bahosi (<?= (int) $ownerRating['n'] ?>)</div></div>
        <?php else: ?>
            <div class="stat-card"><div class="stat-value"><?= $clientRating['n'] ? $clientRating['r'] . ' ★' : '—' ?></div><div class="stat-title">haydovchilar bahosi (<?= (int) $clientRating['n'] ?>)</div></div>
            <div class="stat-card"><div class="stat-value"><?= moneyFmt($bal['bonus_balance']) ?></div><div class="stat-title">sovg'a balansi, so'm</div></div>
        <?php endif; ?>
    </div>

    <div class="od-grid">
        <div>
            <div class="tabs">
                <?php foreach ($tabs as $k => $label):
                    $n = ['cards' => count($cards), 'addresses' => count($addresses), 'problems' => $problemCount, 'docs' => count($docs), 'equipment' => count($equipment)][$k] ?? null; ?>
                    <a href="<?= $self ?>&t=<?= $k ?>" class="<?= $t === $k ? 'active' : '' ?>"><?= $label ?><?php if ($n !== null): ?> <span class="nav-count"><?= $n ?></span><?php endif; ?></a>
                <?php endforeach; ?>
            </div>

            <div class="card">
            <?php if ($t === 'orders'): ?>
                <?php if (!$orders): ?><div class="empty-state">Buyurtma yo'q</div><?php else: ?>
                <div class="table-responsive"><table>
                    <thead><tr><th>ID</th><th>Sana</th><th>Xizmat</th><th>Roli</th><th>Holat</th><th class="text-right">Summa</th></tr></thead>
                    <tbody>
                    <?php foreach ($orders as $o): [$ot, $oc] = orderStatusBadge($o); ?>
                        <tr data-href="<?= orderHref($o['kind'], (int) $o['id']) ?>">
                            <td><a class="num" href="<?= orderHref($o['kind'], (int) $o['id']) ?>"><b>#<?= (int) $o['id'] ?></b></a></td>
                            <td class="num"><?= date('d.m H:i', strtotime($o['created_at'])) ?></td>
                            <td><?= htmlspecialchars(ORDER_KINDS[$o['kind']] . ' · ' . orderWhat($o)) ?></td>
                            <td class="text-muted"><?= (int) $o['client_id'] === $id ? 'mijoz' : 'ijrochi' ?></td>
                            <td><span class="badge badge-<?= $oc ?>"><?= htmlspecialchars($ot) ?></span></td>
                            <td class="text-right num"><?= $o['st'] === 'cancelled' ? '—' : moneyFmt($o['amount']) ?></td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table></div>
                <?php endif; ?>

            <?php elseif ($t === 'payments'): ?>
                <?php if (!$txs): ?><div class="empty-state">To'lov yo'q</div><?php else: ?>
                <div class="table-responsive"><table>
                    <thead><tr><th>Sana</th><th>Turi</th><th>Izoh</th><th>Holat</th><th class="text-right">Summa</th></tr></thead>
                    <tbody>
                    <?php foreach ($txs as $x): $plus = in_array($x['type'], ['topup', 'income', 'refund', 'bonus'], true); ?>
                        <tr>
                            <td class="num"><?= date('d.m.Y H:i', strtotime($x['created_at'])) ?></td>
                            <td><?= $txNames[$x['type']] ?? htmlspecialchars($x['type']) ?><?= $x['payment_method'] ? '<span class="sub">' . htmlspecialchars($x['payment_method']) . '</span>' : '' ?></td>
                            <td class="text-muted" style="font-size:12.5px"><?= htmlspecialchars((string) $x['description']) ?></td>
                            <td><span class="badge badge-<?= $x['status'] === 'completed' ? 'success' : ($x['status'] === 'failed' ? 'danger' : 'warning') ?>"><?= htmlspecialchars($x['status']) ?></span></td>
                            <td class="text-right num <?= $plus ? 'text-success' : '' ?>"><?= ($plus ? '+' : '−') . moneyFmt($x['amount']) ?></td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table></div>
                <?php endif; ?>

            <?php elseif ($t === 'cards'): ?>
                <div class="card-body">
                    <?php if (!$cards): ?><div class="text-muted">Bog'langan karta yo'q</div><?php endif; ?>
                    <?php foreach ($cards as $c): ?>
                        <div class="note" style="background:var(--gray-50)"><b><?= htmlspecialchars(strtoupper((string) $c['ps'])) ?> •••• <?= htmlspecialchars(substr((string) $c['pan'], -4)) ?></b>
                            <small><?= $c['is_default'] ? 'Asosiy · ' : '' ?><?= htmlspecialchars($c['status']) ?> · qo'shilgan <?= date('d.m.Y', strtotime($c['created_at'])) ?></small></div>
                    <?php endforeach; ?>
                    <div class="form-hint">Karta raqami to'liq ko'rinmaydi (PCI DSS) — faqat oxirgi 4 raqam. Karta Multicard sahifasida bog'lanadi.</div>
                </div>

            <?php elseif ($t === 'addresses'): ?>
                <div class="card-body">
                    <?php if (!$addresses): ?><div class="text-muted">Saqlangan manzil yo'q</div><?php endif; ?>
                    <?php foreach ($addresses as $a): ?>
                        <div class="note" style="background:var(--gray-50)"><b><?= htmlspecialchars($a['title'] ?: $a['kind']) ?></b><small><?= htmlspecialchars((string) $a['address']) ?></small></div>
                    <?php endforeach; ?>
                </div>

            <?php elseif ($t === 'problems'): ?>
                <?php if (!$problems): ?><div class="empty-state">Shikoyat yo'q</div><?php else: ?>
                <div class="table-responsive"><table>
                    <thead><tr><th>Nizo</th><th>Buyurtma</th><th>Sabab</th><th>Holat</th><th>Sana</th></tr></thead>
                    <tbody>
                    <?php foreach ($problems as $p): ?>
                        <tr data-href="problems.php?id=<?= (int) $p['id'] ?>">
                            <td><a href="problems.php?id=<?= (int) $p['id'] ?>"><b>#<?= (int) $p['id'] ?></b></a></td>
                            <td><a href="<?= orderHref($p['kind'], (int) $p['order_id']) ?>">#<?= (int) $p['order_id'] ?></a></td>
                            <td><?= htmlspecialchars($p['reason']) ?></td>
                            <td><span class="badge badge-<?= $p['status'] === 'open' ? 'danger' : 'secondary' ?>"><?= htmlspecialchars($p['status']) ?></span></td>
                            <td class="num"><?= date('d.m.Y', strtotime($p['created_at'])) ?></td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table></div>
                <?php endif; ?>

            <?php elseif ($t === 'audit'): ?>
                <?php if (!$audit): ?><div class="empty-state">Bu foydalanuvchida admin amali bo'lmagan</div><?php else: ?>
                <div class="table-responsive"><table>
                    <thead><tr><th>Vaqt</th><th>Admin</th><th>Amal</th><th>Tafsilot</th></tr></thead>
                    <tbody>
                    <?php foreach ($audit as $a): $pl = json_decode((string) $a['payload'], true) ?: []; ?>
                        <tr>
                            <td class="num text-muted"><?= date('d.m.Y H:i', strtotime($a['created_at'])) ?></td>
                            <td><?= htmlspecialchars($a['full_name'] ?? '—') ?></td>
                            <td><?= $auditNames[$a['action']] ?? htmlspecialchars($a['action']) ?></td>
                            <td class="text-muted" style="font-size:12.5px"><?php
                                $bits = [];
                                if (!empty($pl['reason'])) $bits[] = BLOCK_REASONS[$pl['reason']][0] ?? $pl['reason'];
                                if (!empty($pl['duration'])) $bits[] = BLOCK_DURATIONS[$pl['duration']] ?? $pl['duration'];
                                if (!empty($pl['amount'])) $bits[] = moneyFmt($pl['amount']) . " so'm";
                                if (!empty($pl['role'])) $bits[] = $pl['role'];
                                if (!empty($pl['note'])) $bits[] = '«' . $pl['note'] . '»';
                                if (!empty($pl['text'])) $bits[] = '«' . $pl['text'] . '»';
                                if (!empty($pl['cancelled'])) $bits[] = 'bekor: ' . implode(', ', $pl['cancelled']);
                                echo htmlspecialchars(implode(' · ', $bits));
                            ?></td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table></div>
                <?php endif; ?>

            <?php elseif ($t === 'docs'): ?>
                <?php if (!$docs): ?><div class="empty-state">Hujjat topshirilmagan<div class="mt-1 text-muted">Mijoz ilovasidan kelgan ega bo'lishi mumkin — hujjatsiz ham buyurtma oladi.</div></div><?php else: ?>
                <div class="table-responsive"><table>
                    <thead><tr><th>Hujjat</th><th>Holat</th><th>Muddati</th><th>Kim tekshirdi</th><th></th></tr></thead>
                    <tbody>
                    <?php foreach ($docs as $d):
                        $days = $d['expires_on'] ? (int) floor((strtotime($d['expires_on']) - strtotime('today')) / 86400) : null;
                        $expCls = $days === null ? '' : ($days < 0 ? 'text-danger' : ($days < 30 ? 'text-warning' : ''));
                    ?>
                        <tr class="<?= $days !== null && $days < 0 ? 'row-alert' : '' ?>">
                            <td><?= htmlspecialchars($docNames[$d['kind']] ?? $d['kind']) ?></td>
                            <td><span class="badge badge-<?= ['approved' => 'success', 'rejected' => 'danger', 'pending' => 'warning'][$d['status']] ?? 'secondary' ?>"><?= ['approved' => 'Tasdiqlangan', 'rejected' => 'Rad etilgan', 'pending' => 'Tekshiruvda'][$d['status']] ?? $d['status'] ?></span>
                                <?php if ($d['reject_reason']): ?><span class="sub"><?= htmlspecialchars($d['reject_reason']) ?></span><?php endif; ?></td>
                            <td class="num <?= $expCls ?>"><?= $d['expires_on'] ? date('d.m.Y', strtotime($d['expires_on'])) . ($days < 0 ? ' · o\'tgan' : ($days < 30 ? ' · ' . $days . ' kun qoldi' : '')) : '—' ?></td>
                            <td class="text-muted"><?= htmlspecialchars($d['reviewer'] ?? '—') ?><?= $d['reviewed_at'] ? '<span class="sub">' . date('d.m.Y H:i', strtotime($d['reviewed_at'])) . '</span>' : '' ?></td>
                            <td></td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table></div>
                <div class="card-body" style="padding-top:0"><a class="btn btn-secondary btn-sm" href="drivers.php?user=<?= $id ?>"><i data-lucide="file-check-2"></i> Hujjatlarni tekshirish</a>
                    <span class="form-hint">Muddati o'tgan hujjat avtomatik «rad etilgan» bo'ladi — haydovchi yangisini yuklamaguncha buyurtma ololmaydi.</span></div>
                <?php endif; ?>

            <?php elseif ($t === 'equipment'): ?>
                <?php if (!$equipment && !$truck): ?><div class="empty-state">Texnika qo'shilmagan</div><?php else: ?>
                <div class="table-responsive"><table>
                    <thead><tr><th>Texnika</th><th>Davlat raqami</th><th>Holat</th><th>Qo'shilgan</th></tr></thead>
                    <tbody>
                    <?php if ($truck): ?>
                        <tr><td><b><?= htmlspecialchars($truck['vehicle_name'] ?? $truck['vehicle_code']) ?></b><span class="sub">Yuk mashinasi<?= $truck['body_type'] ? ' · ' . htmlspecialchars($truck['body_type']) : '' ?></span></td>
                            <td class="num"><?= htmlspecialchars((string) $truck['plate']) ?></td>
                            <td><span class="badge badge-<?= $truck['is_online'] ? 'success' : 'secondary' ?>"><?= $truck['is_online'] ? 'Onlayn' : 'Oflayn' ?></span></td>
                            <td class="num"><?= date('d.m.Y', strtotime($truck['created_at'])) ?></td></tr>
                    <?php endif; ?>
                    <?php foreach ($equipment as $e): ?>
                        <tr><td><b><?= htmlspecialchars(equipmentTypeName($e['type'])) ?></b><span class="sub"><?= htmlspecialchars((string) $e['model']) ?></span></td>
                            <td class="num"><?= htmlspecialchars((string) $e['plate_number']) ?></td>
                            <td><span class="badge badge-<?= $e['deleted_at'] ? 'secondary' : ($e['status'] === 'available' ? 'success' : 'warning') ?>"><?= $e['deleted_at'] ? "O'chirilgan" : htmlspecialchars($e['status']) ?></span></td>
                            <td class="num"><?= date('d.m.Y', strtotime($e['created_at'])) ?></td></tr>
                    <?php endforeach; ?>
                    </tbody>
                </table></div>
                <?php endif; ?>
            <?php endif; ?>
            </div>
        </div>

        <div>
            <div class="card"><div class="card-body">
                <b>Ma'lumotlar</b>
                <div class="pay-rows mt-1">
                    <div class="r"><span>Til</span><b><?= $u['language'] === 'ru' ? 'Ruscha' : "O'zbekcha" ?></b></div>
                    <div class="r"><span>Oxirgi kirish</span><b><?= lastSeenText($u['last_login_at']) ?></b></div>
                    <div class="r"><span>Balans</span><b><?= moneyFmt($bal['balance']) ?> so'm</b></div>
                    <div class="r"><span>Muzlatilgan</span><b><?= moneyFmt($bal['frozen_balance']) ?> so'm</b></div>
                    <div class="r"><span>Sovg'a (yechilmaydi)</span><b><?= moneyFmt($bal['bonus_balance']) ?> so'm</b></div>
                    <div class="r"><span>E'lon narxi</span><b><?= $u['listing_fee_override'] === null ? 'umumiy' : moneyFmt($u['listing_fee_override']) . " so'm" ?></b></div>
                </div>
            </div></div>

            <?php if ($active): ?>
            <div class="card"><div class="card-body">
                <b>Faol buyurtmalar</b>
                <?php foreach ($active as $a): ?>
                    <div class="note" style="background:var(--gray-50)"><a href="<?= orderHref($a['kind'], (int) $a['id']) ?>"><b><?= ORDER_KINDS[$a['kind']] ?? $a['kind'] ?> #<?= (int) $a['id'] ?></b></a>
                        <small><?= $a['role'] === 'client' ? 'mijoz' : 'ijrochi' ?> · <?= htmlspecialchars($a['status']) ?> · <?= moneyFmt($a['amount']) ?> so'm</small></div>
                <?php endforeach; ?>
            </div></div>
            <?php endif; ?>

            <?php if (!$isAdminAcc && !$deleted): ?>
            <div class="card"><div class="card-body">
                <b>Boshqaruv</b>
                <?php $csrf = htmlspecialchars(generateCsrfToken()); ?>
                <form method="post" class="mt-1 d-flex gap-1">
                    <input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="action" value="<?= $u['is_frozen'] ? 'unfreeze' : 'freeze' ?>">
                    <button class="btn btn-secondary btn-sm btn-block" type="submit"><i data-lucide="snowflake"></i> <?= $u['is_frozen'] ? 'Muzlatishni olib tashlash' : 'Muzlatish (ko\'radi, buyurtma bermaydi)' ?></button>
                </form>
                <details class="mt-1"><summary>Sovg'a berish (yechib bo'lmaydi)</summary>
                    <form method="post" class="mt-1"><input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="action" value="grant_bonus">
                        <input name="amount" placeholder="Summa, so'm" required inputmode="numeric"><input name="comment" placeholder="Izoh" class="mt-1">
                        <button class="btn btn-secondary btn-sm mt-1" type="submit">Berish</button></form></details>
                <details class="mt-1"><summary>Naqd pul qabul qilish (haqiqiy balans)</summary>
                    <form method="post" class="mt-1"><input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="action" value="cash_topup">
                        <input name="amount" placeholder="Summa, so'm" required inputmode="numeric"><input name="comment" placeholder="Izoh" class="mt-1">
                        <button class="btn btn-secondary btn-sm mt-1" type="submit">Balansga yozish</button></form></details>
                <details class="mt-1"><summary>Telefon raqam</summary>
                    <form method="post" class="mt-1"><input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="action" value="set_phone">
                        <input name="phone" value="<?= htmlspecialchars($u['phone']) ?>" required><button class="btn btn-secondary btn-sm mt-1" type="submit">Saqlash</button></form></details>
                <details class="mt-1"><summary>Rol</summary>
                    <form method="post" class="mt-1"><input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="action" value="set_role">
                        <select name="role"><option value="client" <?= $u['role'] === 'client' ? 'selected' : '' ?>>Mijoz</option><option value="owner" <?= $isOwner ? 'selected' : '' ?>>Ega / haydovchi</option></select>
                        <button class="btn btn-secondary btn-sm mt-1" type="submit">Saqlash</button></form></details>
                <details class="mt-1"><summary>E'lon narxi</summary>
                    <form method="post" class="mt-1"><input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="action" value="set_listing_fee">
                        <input name="listing_fee" value="<?= $u['listing_fee_override'] === null ? '' : (int) $u['listing_fee_override'] ?>" placeholder="bo'sh — umumiy, 0 — bepul">
                        <button class="btn btn-secondary btn-sm mt-1" type="submit">Saqlash</button></form></details>
                <details class="mt-1"><summary>Parol o'rnatish</summary>
                    <form method="post" class="mt-1"><input type="hidden" name="csrf_token" value="<?= $csrf ?>"><input type="hidden" name="action" value="set_password">
                        <input type="password" name="password" minlength="6" required autocomplete="new-password"><button class="btn btn-secondary btn-sm mt-1" type="submit">O'rnatish</button></form></details>
            </div></div>
            <?php endif; ?>
        </div>
    </div>
</div>

<?php if (!$isAdminAcc && !$deleted): ?>
<!-- C3 · Bloklash -->
<div class="modal" id="modalBlock" role="dialog" aria-modal="true" aria-labelledby="blockTitle">
    <form class="modal-content" method="post" style="max-width:520px">
        <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
        <input type="hidden" name="action" value="block">
        <div class="modal-header">
            <div class="d-flex gap-1 align-center">
                <span class="stat-icon danger"><i data-lucide="ban"></i></span>
                <div><div class="modal-title" id="blockTitle"><?= htmlspecialchars($u['full_name']) ?>ni bloklash</div>
                    <div class="text-muted" style="font-size:12.5px">Bloklangan foydalanuvchi ilovaga kira olmaydi. Tarixi saqlanadi.</div></div>
            </div>
            <button class="modal-close" type="button" data-close aria-label="Yopish">×</button>
        </div>
        <div class="modal-body">
            <?php $clientActive = array_filter($active, function ($a) { return $a['role'] === 'client'; });
                  $perfActive = array_filter($active, function ($a) { return $a['role'] !== 'client'; }); ?>
            <?php if ($active): ?>
                <div class="alert alert-warning" style="margin-bottom:10px"><i data-lucide="triangle-alert"></i>
                    <div><b>Faol buyurtma bor:</b>
                        <?php foreach ($active as $a): ?><a href="<?= orderHref($a['kind'], (int) $a['id']) ?>">#<?= (int) $a['id'] ?></a> (<?= $a['role'] === 'client' ? 'mijoz' : 'ijrochi' ?>) <?php endforeach; ?>
                        <?php if ($perfActive): ?><div class="mt-1">Ijrochi bo'lgan buyurtmalarda — avval buyurtma sahifasida <b>ijrochini almashtiring</b>, aks holda mijoz kutib qoladi.</div><?php endif; ?>
                    </div></div>
                <?php if ($clientActive): ?>
                    <label class="d-flex gap-1 align-center mb-1" style="font-size:13px"><input type="checkbox" name="cancel_active" value="1">
                        Mijoz buyurtmalarini hozir bekor qilish (muzlatilgan pul qaytadi, jarima yo'q)</label>
                <?php endif; ?>
            <?php endif; ?>
            <div class="form-section" style="margin-top:0">Sabab (majburiy)</div>
            <?php foreach (BLOCK_REASONS as $k => [$tt, $ss]): ?>
                <label class="choice"><input type="radio" name="reason" value="<?= $k ?>" required>
                    <span><b><?= htmlspecialchars($tt) ?></b><small><?= htmlspecialchars($ss) ?></small></span></label>
            <?php endforeach; ?>
            <div class="form-section">Muddat</div>
            <div class="seg" id="durSeg">
                <?php foreach (BLOCK_DURATIONS as $k => $v): ?>
                    <label style="margin:0"><input type="radio" name="duration" value="<?= $k ?>" <?= $k === '7d' ? 'checked' : '' ?> style="display:none"><span class="seg-btn"><?= $v ?></span></label>
                <?php endforeach; ?>
            </div>
            <div class="form-group mt-2">
                <label for="blockNote">Izoh (foydalanuvchiga ko'rinmaydi)</label>
                <textarea id="blockNote" name="note" rows="2" placeholder="Masalan: haydovchiga qo'pollik qilgan, audio yozuv bor"></textarea>
            </div>
            <label class="d-flex gap-1 align-center" style="font-size:13px"><input type="checkbox" name="send_sms" value="1" id="smsOn"> Foydalanuvchiga SMS yuborish</label>
            <div class="note mt-1" id="smsText" aria-live="polite"></div>
            <div class="form-hint">Matn Eskizda tasdiqlangan shablon bo'yicha avtomatik tuziladi (sabab va muddatdan) — o'zgartirib bo'lmaydi, aks holda Eskiz rad etadi.</div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-secondary" type="button" data-close>Bekor</button>
            <button class="btn btn-danger" type="submit">Bloklash</button>
        </div>
    </form>
</div>

<!-- Xabar yuborish -->
<div class="modal" id="modalMessage" role="dialog" aria-modal="true" aria-labelledby="msgTitle">
    <form class="modal-content" method="post" style="max-width:480px">
        <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
        <input type="hidden" name="action" value="message">
        <div class="modal-header"><div class="modal-title" id="msgTitle">Xabar yuborish</div>
            <button class="modal-close" type="button" data-close aria-label="Yopish">×</button></div>
        <div class="modal-body">
            <textarea name="text" rows="4" maxlength="1000" required placeholder="Ilovada «Bildirishnomalar» da ko'rinadi"></textarea>
            <label class="d-flex gap-1 align-center mt-1" style="font-size:13px"><input type="checkbox" name="sms" value="1"> SMS ham yuborish (Eskiz shablon talab qiladi)</label>
        </div>
        <div class="modal-footer">
            <button class="btn btn-secondary" type="button" data-close>Bekor</button>
            <button class="btn btn-primary" type="submit"><i data-lucide="send"></i> Yuborish</button>
        </div>
    </form>
</div>
<?php endif; ?>

<style>
    #durSeg .seg-btn { display: inline-block; padding: 6px 14px; border-radius: 7px; font: 500 12.5px var(--font-family); color: var(--gray-600); cursor: pointer; }
    #durSeg input:checked + .seg-btn { background: #fff; color: var(--navy-900); box-shadow: var(--shadow-sm); }
    .text-warning { color: var(--yellow-700); }
    details summary { cursor: pointer; font-size: 13px; padding: 6px 0; color: var(--navy-900); }
</style>
<script>
document.querySelectorAll('tr[data-href]').forEach(tr => tr.addEventListener('click', e => {
    if (e.target.closest('input,a,button')) return;
    location.href = tr.dataset.href;
}));
document.querySelectorAll('[data-open]').forEach(b => b.addEventListener('click', () => {
    const el = document.getElementById(b.dataset.open); if (el) el.classList.add('active');
}));
document.querySelectorAll('.modal').forEach(m => m.addEventListener('click', e => {
    if (e.target === m || e.target.closest('[data-close]')) m.classList.remove('active');
}));
document.addEventListener('keydown', e => { if (e.key === 'Escape') document.querySelectorAll('.modal.active').forEach(m => m.classList.remove('active')); });
(() => {
    const on = document.getElementById('smsOn'), txt = document.getElementById('smsText');
    if (!on) return;
    // backend/app/services/user_admin_service.block_sms bilan BIR XIL bo'lishi shart
    const why = {fraud: "to'lov firibgarligi", abuse: "haqoratli xatti-harakat", cancels: "ko'p bekor qilish",
                 fake_docs: "soxta hujjat", other: "qoidalarni buzish"};
    const hrs = {'24h': 24, '7d': 168, '30d': 720};
    const pad = n => String(n).padStart(2, '0');
    const form = on.form;
    const sync = () => {
        txt.style.display = on.checked ? '' : 'none';
        const r = (form.querySelector('[name=reason]:checked') || {}).value || 'other';
        const d = (form.querySelector('[name=duration]:checked') || {}).value || '7d';
        const tail = ' Sabab: ' + (why[r] || why.other) + '. Savollar uchun Telegram: @movex_support';
        if (!hrs[d]) { txt.textContent = 'MoveX GO: hisobingiz bloklandi.' + tail; return; }
        const t = new Date(Date.now() + hrs[d] * 3600e3);
        txt.textContent = 'MoveX GO: hisobingiz ' + pad(t.getDate()) + '.' + pad(t.getMonth() + 1) + '.' + t.getFullYear()
            + ' ' + pad(t.getHours()) + ':' + pad(t.getMinutes()) + ' gacha bloklandi.' + tail;
    };
    form.addEventListener('change', sync); sync();
})();
</script>
<?php include 'includes/footer.php'; ?>
