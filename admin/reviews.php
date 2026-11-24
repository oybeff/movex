<?php
/**
 * N4 · Sharhlar moderatsiyasi (Figma «Admin panel» 07).
 *
 * Avto-belgilar (bu yerda, sharhni o'qiyotganda hisoblanadi): telefon
 * raqam, tashqi reklama (havola, @, Telegram), haqoratli so'z, o'z-o'ziga
 * baho (sharh muallifi — texnika egasining o'zi). Yashirish backend orqali:
 * muallifga bildirishnoma boradi; yashirilgan sharh reytingga kirmaydi va
 * ilovada ko'rinmaydi.
 */
require_once 'config.php';
require_once 'includes/orders_lib.php';
requireAdmin();
requirePagePerm('equipment');
requireCsrfToken();

$db = getDbConnection();
$db->exec("SET TIME ZONE 'Asia/Tashkent'");
$adminId = (int) ($_SESSION['admin_user_id'] ?? 0);
$pageTitle = 'Foydalanuvchilar / Sharhlar';
$currentPage = 'reviews';

const REVIEW_HIDE_REASONS = ['abuse' => "Haqoratli so'z", 'phone' => 'Telefon raqam', 'ads' => 'Tashqi reklama',
                             'self' => "O'z-o'ziga baho", 'other' => 'Qoidaga zid'];

/** Avto-belgilar: [kod, matn, qizil?] */
function reviewFlags(array $r): array
{
    $t = mb_strtolower((string) $r['comment']);
    $f = [];
    if (preg_match('/(\+?998[\s\-]?\d{2}|\b\d{2}[\s\-]?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}\b)/u', $t)) {
        $f[] = ['phone', 'Telefon raqam (avto)', false];
    }
    if (preg_match('/(https?:\/\/|www\.|t\.me|telegram|@[a-z0-9_]{3,}|instagram)/u', $t)) {
        $f[] = ['ads', 'Tashqi reklama (avto)', true];
    }
    $bad = ['ahmoq', 'iflos', 'harom', "jalab", 'qanjiq', 'tupoy', 'дурак', 'идиот', 'урод', 'сука', 'бля', 'хуй', 'пизд', 'мудак'];
    foreach ($bad as $w) {
        if (mb_strpos($t, $w) !== false) {
            $f[] = ['abuse', "Haqoratli so'z (avto)", true];
            break;
        }
    }
    if (!empty($r['self_review'])) {
        $f[] = ['self', "O'z-o'ziga baho (avto)", true];
    }
    return $f;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $rid = (int) ($_POST['review_id'] ?? 0);
    $hide = ($_POST['action'] ?? '') === 'hide';
    $reason = (string) ($_POST['reason'] ?? 'other');
    $r = internalApiPost("/admin-orders/internal/reviews/$rid/moderate", [
        'admin_id' => $adminId, 'hide' => $hide, 'reason' => isset(REVIEW_HIDE_REASONS[$reason]) ? $reason : 'other',
    ]);
    $_SESSION['flash'] = $r['ok'] ? ['success', $hide ? 'Sharh yashirildi, muallifga xabar yuborildi' : 'Sharh qoldirildi']
                                   : ['error', $r['error']];
    header('Location: reviews.php?tab=' . urlencode($_GET['tab'] ?? 'flagged'));
    exit;
}
$flash = $_SESSION['flash'] ?? null;
unset($_SESSION['flash']);

$tab = $_GET['tab'] ?? 'flagged';
$tabs = ['flagged' => 'Avto-belgi', 'low' => 'Past baho (1–2)', 'all' => 'Hammasi', 'hidden' => 'Yashirilgan'];
if (!isset($tabs[$tab])) { $tab = 'flagged'; }

$rows = $db->query("SELECT r.*, a.full_name AS author, e.type, e.model, o.full_name AS owner_name, o.id AS owner_id,
                           (r.user_id = e.owner_id) AS self_review
                      FROM reviews r
                      JOIN users a ON a.id = r.user_id
                      LEFT JOIN equipment e ON e.id = r.equipment_id
                      LEFT JOIN users o ON o.id = e.owner_id
                     ORDER BY r.created_at DESC LIMIT 1000")->fetchAll();
$counts = ['flagged' => 0, 'low' => 0, 'all' => 0, 'hidden' => 0];
$list = [];
foreach ($rows as $r) {
    $r['flags'] = $r['comment'] !== null || $r['self_review'] ? reviewFlags($r) : [];
    $hidden = (bool) $r['hidden'];
    $isFlag = !$hidden && $r['flags'] && $r['moderated_at'] === null;
    $isLow = !$hidden && (int) $r['rating'] <= 2;
    $counts['all'] += $hidden ? 0 : 1;
    $counts['hidden'] += $hidden ? 1 : 0;
    $counts['flagged'] += $isFlag ? 1 : 0;
    $counts['low'] += $isLow ? 1 : 0;
    if (($tab === 'flagged' && $isFlag) || ($tab === 'low' && $isLow) || ($tab === 'all' && !$hidden) || ($tab === 'hidden' && $hidden)) {
        $list[] = $r;
    }
}
$list = array_slice($list, 0, 200);

include 'includes/header.php';
?>
<div class="content">
    <?php if ($flash): ?><div class="alert alert-<?= $flash[0] === 'success' ? 'success' : 'error' ?>"><?= htmlspecialchars($flash[1]) ?></div><?php endif; ?>
    <div class="page-head"><div><h2>Sharhlar</h2>
        <div class="sub">Buyurtma yakunida mijozlar qoldirgan baholar (texnika egasiga)</div></div></div>
    <div class="tabs">
        <?php foreach ($tabs as $k => $v): ?>
            <a href="?tab=<?= $k ?>" class="<?= $tab === $k ? 'active' : '' ?>"><?= $v ?>
                <span class="nav-count <?= $k === 'flagged' && $counts[$k] ? 'danger' : '' ?>"><?= $counts[$k] ?></span></a>
        <?php endforeach; ?>
    </div>
    <div class="card">
        <?php if (!$list): ?>
            <div class="empty-state"><i data-lucide="star"></i><div>Bu bo'limda sharh yo'q</div></div>
        <?php endif; ?>
        <?php foreach ($list as $r): ?>
            <div class="review-card">
                <div style="min-width:0">
                    <div class="text-muted" style="font-size:12.5px">
                        <span class="stars"><?= str_repeat('★', (int) $r['rating']) . str_repeat('☆', 5 - (int) $r['rating']) ?></span>
                        <?= htmlspecialchars($r['author']) ?> → <?= htmlspecialchars($r['owner_name'] ?? '—') ?>
                        · <?= htmlspecialchars(equipmentTypeName($r['type']) . ' ' . ($r['model'] ?? '')) ?> · <?= agoText($r['created_at']) ?>
                    </div>
                    <div class="text"><?= $r['comment'] !== null && $r['comment'] !== '' ? nl2br(htmlspecialchars($r['comment'])) : '<span class="text-muted">Izohsiz</span>' ?></div>
                    <?php foreach ($r['flags'] as [$code, $label, $red]): ?><span class="flag <?= $red ? '' : 'warn' ?>"><?= $label ?></span><?php endforeach; ?>
                    <?php if ($r['hidden']): ?><span class="flag">Yashirilgan: <?= htmlspecialchars(REVIEW_HIDE_REASONS[$r['hidden_reason']] ?? '—') ?></span><?php endif; ?>
                    <?php if ($r['moderated_at'] && !$r['hidden']): ?><span class="badge badge-success" style="height:20px">Tekshirilgan</span><?php endif; ?>
                </div>
                <div class="acts">
                    <?php if (!$r['hidden']): ?>
                        <form method="post" class="d-flex gap-1">
                            <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
                            <input type="hidden" name="review_id" value="<?= (int) $r['id'] ?>">
                            <input type="hidden" name="action" value="hide">
                            <select name="reason" style="width:auto;min-height:30px;padding:2px 8px;font-size:12.5px" aria-label="Sabab">
                                <?php $def = $r['flags'][0][0] ?? 'other'; foreach (REVIEW_HIDE_REASONS as $k => $v): ?>
                                    <option value="<?= $k ?>" <?= $k === $def ? 'selected' : '' ?>><?= $v ?></option>
                                <?php endforeach; ?>
                            </select>
                            <button class="btn btn-sm btn-secondary" style="color:var(--red-500)"><i data-lucide="eye-off"></i> Yashirish</button>
                        </form>
                        <?php if (!$r['moderated_at']): ?>
                        <form method="post">
                            <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
                            <input type="hidden" name="review_id" value="<?= (int) $r['id'] ?>">
                            <input type="hidden" name="action" value="keep">
                            <button class="btn btn-sm btn-secondary"><i data-lucide="check"></i> Qoldirish</button>
                        </form>
                        <?php endif; ?>
                    <?php else: ?>
                        <form method="post">
                            <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
                            <input type="hidden" name="review_id" value="<?= (int) $r['id'] ?>">
                            <input type="hidden" name="action" value="keep">
                            <button class="btn btn-sm btn-secondary"><i data-lucide="eye"></i> Qaytarish</button>
                        </form>
                    <?php endif; ?>
                </div>
            </div>
        <?php endforeach; ?>
    </div>
    <div class="alert alert-info"><i data-lucide="info"></i><div><b>Yashirilgan sharh reytingga ta'sir qilmaydi.</b>
        Muallifga «Sharhingiz qoidalarga mos kelmadi» xabari boradi. «Qoldirish» — sharh tekshirilgan deb belgilanadi va avto-belgilar ro'yxatidan chiqadi.</div></div>
</div>
<?php include 'includes/footer.php'; ?>
