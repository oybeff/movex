<?php
/**
 * N5 · Yordam chatlari (Figma «Admin panel» 07).
 *
 * 3 ustun: suhbatlar (javob kutayotgani qizil), chat (tez javoblar),
 * kontekst (foydalanuvchi va uning faol buyurtmasi). Foydalanuvchi
 * ilovadan yozadi (Profil → Yordam). Javob — backend orqali: u ilovada
 * bildirishnoma ham yaratadi. Sahifa har 15 soniyada yangilanadi.
 */
require_once 'config.php';
require_once 'includes/orders_lib.php';
requireAdmin();
requireCsrfToken();

$db = getDbConnection();
$db->exec("SET TIME ZONE 'Asia/Tashkent'");
$adminId = (int) ($_SESSION['admin_user_id'] ?? 0);
$pageTitle = 'Operatsiyalar / Yordam chatlari';
$currentPage = 'support';
$tid = isset($_GET['t']) ? (int) $_GET['t'] : 0;
$tab = $_GET['tab'] ?? 'open';
$self = 'support.php?tab=' . urlencode($tab) . ($tid ? '&t=' . $tid : '');

if ($_SERVER['REQUEST_METHOD'] === 'POST' && $tid) {
    $a = $_POST['action'] ?? '';
    if ($a === 'reply') {
        $r = internalApiPost("/admin-orders/internal/support/$tid/reply", ['admin_id' => $adminId, 'text' => (string) ($_POST['text'] ?? '')]);
        $_SESSION['flash'] = $r['ok'] ? null : ['error', 'Yuborilmadi: ' . $r['error']];
        if (!$r['ok']) {
            $_SESSION['draft'] = (string) ($_POST['text'] ?? '');
        }
    } elseif ($a === 'close') {
        $r = internalApiPost("/admin-orders/internal/support/$tid/close", ['admin_id' => $adminId]);
        $_SESSION['flash'] = $r['ok'] ? ['success', 'Suhbat yopildi'] : ['error', $r['error']];
    } elseif ($a === 'take') {
        $db->prepare('UPDATE support_threads SET assigned_admin_id = ? WHERE id = ?')->execute([$adminId, $tid]);
    }
    header('Location: ' . $self);
    exit;
}
$flash = $_SESSION['flash'] ?? null;
$draft = $_SESSION['draft'] ?? '';
unset($_SESSION['flash'], $_SESSION['draft']);

// «Javob kutmoqda» — oxirgi xabar foydalanuvchidan
$lastSql = "(SELECT m.is_admin FROM support_messages m WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1)";
$tabs = ['open' => 'Ochiq', 'mine' => 'Menga', 'unassigned' => 'Tayinlanmagan', 'closed' => 'Yopilgan'];
if (!isset($tabs[$tab])) { $tab = 'open'; }
$where = ['open' => "t.status = 'open'", 'mine' => "t.status = 'open' AND t.assigned_admin_id = $adminId",
          'unassigned' => "t.status = 'open' AND t.assigned_admin_id IS NULL", 'closed' => "t.status = 'closed'"][$tab];
$threads = $db->query("SELECT t.*, u.full_name, u.phone, u.role,
        $lastSql AS last_admin,
        (SELECT m.text FROM support_messages m WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1) AS last_text,
        (SELECT MIN(m.created_at) FROM support_messages m WHERE m.thread_id = t.id AND NOT m.is_admin
            AND m.created_at > COALESCE((SELECT MAX(m2.created_at) FROM support_messages m2 WHERE m2.thread_id = t.id AND m2.is_admin), 'epoch')) AS waiting_since,
        (SELECT COUNT(*) FROM support_messages m WHERE m.thread_id = t.id AND NOT m.is_admin
            AND m.created_at > COALESCE(t.admin_read_at, 'epoch')) AS unread
      FROM support_threads t JOIN users u ON u.id = t.user_id
     WHERE $where
     ORDER BY ($lastSql IS FALSE) DESC, t.last_message_at DESC LIMIT 100")->fetchAll();
$counts = $db->query("SELECT COUNT(*) FILTER (WHERE status='open') AS open,
        COUNT(*) FILTER (WHERE status='open' AND assigned_admin_id = $adminId) AS mine,
        COUNT(*) FILTER (WHERE status='open' AND assigned_admin_id IS NULL) AS unassigned,
        COUNT(*) FILTER (WHERE status='closed') AS closed FROM support_threads")->fetch();

$thread = null;
$msgs = [];
$ctx = [];
if ($tid) {
    $st = $db->prepare('SELECT t.*, u.full_name, u.phone, u.role, u.created_at AS user_since, a.full_name AS admin_name
                          FROM support_threads t JOIN users u ON u.id = t.user_id LEFT JOIN users a ON a.id = t.assigned_admin_id
                         WHERE t.id = ?');
    $st->execute([$tid]);
    $thread = $st->fetch();
    if ($thread) {
        $db->prepare('UPDATE support_threads SET admin_read_at = NOW() WHERE id = ?')->execute([$tid]);
        $st = $db->prepare('SELECT m.*, u.full_name FROM support_messages m LEFT JOIN users u ON u.id = m.author_id
                             WHERE m.thread_id = ? ORDER BY m.created_at');
        $st->execute([$tid]);
        $msgs = $st->fetchAll();
        $uid = (int) $thread['user_id'];
        $st = $db->prepare("SELECT COUNT(*) FILTER (WHERE kind <> 'request') AS n, COUNT(*) FILTER (WHERE st = 'cancelled') AS cx
                              FROM " . ordersUnionSql() . " WHERE u.client_id = ? OR u.perf_id = ?");
        $st->execute([$uid, $uid]);
        $ctx['stats'] = $st->fetch();
        $st = $db->prepare("SELECT u.* FROM " . ordersUnionSql() . " WHERE (u.client_id = ? OR u.perf_id = ?)
                              AND u.st IN ('searching','assigned','progress') ORDER BY u.created_at DESC LIMIT 3");
        $st->execute([$uid, $uid]);
        $ctx['active'] = $st->fetchAll();
        $st = $db->prepare("SELECT id, created_at, status FROM support_threads WHERE user_id = ? AND id <> ? ORDER BY id DESC LIMIT 5");
        $st->execute([$uid, $tid]);
        $ctx['prev'] = $st->fetchAll();
    }
}

$quick = [
    "Assalomu alaykum! Tekshiryapmiz, bir necha daqiqada javob beramiz.",
    "Buyurtma bo'yicha ijrochi bilan bog'landik, kuting.",
    "Pul qaytarish 1–3 ish kuni ichida kartangizga tushadi.",
    "Bekor qilish shartlari: ijrochi yo'lga chiqquncha bepul.",
    "Rahmat! Yana savol bo'lsa, shu yerga yozing.",
];

include 'includes/header.php';
?>
<div class="content" style="max-width:none">
    <?php if ($flash): ?><div class="alert alert-<?= $flash[0] === 'success' ? 'success' : 'error' ?>"><?= htmlspecialchars($flash[1]) ?></div><?php endif; ?>
    <div class="support-grid">
        <div class="support-list">
            <div class="head">
                <div class="d-flex justify-between align-center"><b style="font-size:16px">Yordam chatlari</b>
                    <span class="nav-count danger"><?= (int) $counts['open'] ?></span></div>
                <div class="seg mt-1" style="flex-wrap:wrap">
                    <?php foreach ($tabs as $k => $v): ?>
                        <a href="?tab=<?= $k ?>" class="<?= $tab === $k ? 'active' : '' ?>"><?= $v ?> · <?= (int) $counts[$k] ?></a>
                    <?php endforeach; ?>
                </div>
            </div>
            <div class="items">
                <?php if (!$threads): ?><div class="empty-state" style="padding:24px">Suhbat yo'q</div><?php endif; ?>
                <?php foreach ($threads as $t):
                    $wait = $t['waiting_since'] ? (int) floor((time() - strtotime($t['waiting_since'])) / 60) : null;
                    $isDriver = $t['app'] === 'driver';
                ?>
                    <a class="support-item <?= (int) $t['id'] === $tid ? 'active' : '' ?>" href="?tab=<?= $tab ?>&t=<?= (int) $t['id'] ?>">
                        <div class="user-avatar" style="width:32px;height:32px;font-size:11.5px"><?= htmlspecialchars(mb_strtoupper(mb_substr($t['full_name'], 0, 2))) ?></div>
                        <div style="min-width:0">
                            <b><?= htmlspecialchars($t['full_name']) ?></b>
                            <small><?= htmlspecialchars((string) $t['last_text']) ?></small>
                            <span class="badge <?= $isDriver ? 'badge-success' : 'badge-info' ?> no-dot" style="height:18px;font-size:11px;margin-top:4px"><?= $isDriver ? 'Haydovchi' : 'Mijoz' ?></span>
                        </div>
                        <div class="meta <?= $wait !== null && $wait >= 10 ? 'late' : '' ?>">
                            <?= $wait !== null ? ($wait < 60 ? $wait . ' daq' : floor($wait / 60) . ' s') : date('H:i', strtotime($t['last_message_at'])) ?>
                            <?php if ($t['unread']): ?><br><span class="nav-count danger"><?= (int) $t['unread'] ?></span><?php endif; ?>
                        </div>
                    </a>
                <?php endforeach; ?>
            </div>
        </div>

        <div class="support-chat">
            <?php if (!$thread): ?>
                <div class="empty-state" style="margin:auto"><i data-lucide="messages-square"></i><div>Chapdan suhbatni tanlang</div></div>
            <?php else: ?>
                <div class="head">
                    <div class="user-avatar" style="width:32px;height:32px;font-size:11.5px"><?= htmlspecialchars(mb_strtoupper(mb_substr($thread['full_name'], 0, 2))) ?></div>
                    <div><b><?= htmlspecialchars($thread['full_name']) ?></b>
                        <div class="text-muted" style="font-size:12px"><?= $thread['app'] === 'driver' ? 'Haydovchi ilovasi' : 'Mijoz ilovasi' ?> ·
                            <?= $thread['status'] === 'open' ? 'ochiq' : 'yopilgan' ?> · mas'ul: <?= htmlspecialchars($thread['admin_name'] ?? '—') ?></div></div>
                    <div class="page-actions" style="margin-left:auto">
                        <?php if ((int) $thread['assigned_admin_id'] !== $adminId): ?>
                            <form method="post"><input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
                                <input type="hidden" name="action" value="take"><button class="btn btn-secondary btn-sm"><i data-lucide="user-check"></i> Menga olish</button></form>
                        <?php endif; ?>
                        <?php if ($thread['status'] === 'open'): ?>
                            <form method="post"><input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
                                <input type="hidden" name="action" value="close"><button class="btn btn-secondary btn-sm"><i data-lucide="check"></i> Yopish</button></form>
                        <?php endif; ?>
                    </div>
                </div>
                <div class="chat" id="chat">
                    <?php $day = ''; foreach ($msgs as $m):
                        $d = date('Y-m-d', strtotime($m['created_at']));
                        if ($d !== $day): $day = $d; ?>
                            <div class="text-center text-muted" style="font-size:12px"><?= $d === date('Y-m-d') ? 'Bugun' : date('d.m.Y', strtotime($m['created_at'])) ?></div>
                        <?php endif; ?>
                        <div class="msg <?= $m['is_admin'] ? 'out' : 'in' ?>">
                            <div class="who"><?= $m['is_admin'] ? 'Siz · ' . htmlspecialchars($m['full_name'] ?? 'admin') : htmlspecialchars($thread['full_name']) ?> · <?= date('H:i', strtotime($m['created_at'])) ?></div>
                            <div class="bubble"><?= nl2br(htmlspecialchars((string) $m['text'])) ?>
                                <?php if ($m['photo'] && strpos($m['photo'], '/static/problems/') === 0): ?>
                                    <div class="photos"><a href="<?= htmlspecialchars($m['photo']) ?>" target="_blank" rel="noopener"><img src="<?= htmlspecialchars($m['photo']) ?>" alt="Rasm"></a></div>
                                <?php endif; ?></div>
                        </div>
                    <?php endforeach; ?>
                </div>
                <form method="post" class="composer" id="replyForm">
                    <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
                    <input type="hidden" name="action" value="reply">
                    <div class="quick-replies">
                        <?php foreach ($quick as $q): ?><button type="button" data-q="<?= htmlspecialchars($q) ?>"><?= htmlspecialchars(mb_substr($q, 0, 34)) ?>…</button><?php endforeach; ?>
                    </div>
                    <?php if ($draft !== ''): ?><div class="text-danger" style="font-size:12px;margin-bottom:6px">Oldingi xabar yuborilmadi — qayta urinib ko'ring</div><?php endif; ?>
                    <div class="d-flex gap-1">
                        <textarea name="text" id="replyText" rows="2" required maxlength="2000" placeholder="Javob yozing… (Enter — yuborish, Shift+Enter — yangi qator)"><?= htmlspecialchars($draft) ?></textarea>
                        <button class="btn btn-primary" type="submit" style="align-self:flex-end"><i data-lucide="send"></i> Yuborish</button>
                    </div>
                </form>
            <?php endif; ?>
        </div>

        <div class="support-ctx">
            <?php if ($thread): ?>
                <div class="form-section">Foydalanuvchi</div>
                <div class="pay-rows">
                    <div class="r"><span>Telefon</span><b class="num"><?= maskPhone($thread['phone']) ?></b></div>
                    <div class="r"><span>Buyurtmalar</span><b><?= (int) $ctx['stats']['n'] ?> · bekor <?= $ctx['stats']['n'] ? round($ctx['stats']['cx'] / max(1, $ctx['stats']['n']) * 100) : 0 ?>%</b></div>
                    <div class="r"><span>Ro'yxatdan</span><b><?= date('d.m.Y', strtotime($thread['user_since'])) ?></b></div>
                </div>
                <a class="btn btn-secondary btn-sm btn-block mt-1" href="users.php?search=<?= urlencode($thread['phone']) ?>"><i data-lucide="user"></i> Profil</a>
                <div class="form-section">Faol buyurtma</div>
                <?php if (!$ctx['active']): ?><div class="text-muted">Yo'q</div><?php endif; ?>
                <?php foreach ($ctx['active'] as $o): [$sT, $sTone] = orderStatusBadge($o); ?>
                    <a class="card" href="<?= orderHref($o['kind'], (int) $o['id']) ?>" style="display:block;padding:10px 12px;margin-bottom:8px;color:inherit">
                        <b>#<?= (int) $o['id'] ?> · <?= htmlspecialchars(orderWhat($o)) ?></b><br>
                        <span class="badge badge-<?= $sTone ?>" style="margin-top:4px"><?= htmlspecialchars($sT) ?></span>
                    </a>
                <?php endforeach; ?>
                <div class="form-section">Oldingi murojaatlar</div>
                <?php if (!$ctx['prev']): ?><div class="text-muted">Yo'q</div><?php endif; ?>
                <?php foreach ($ctx['prev'] as $pt): ?>
                    <div><a href="?tab=all&t=<?= (int) $pt['id'] ?>"><?= date('d.m', strtotime($pt['created_at'])) ?></a> · <?= $pt['status'] === 'open' ? 'ochiq' : 'yopilgan' ?></div>
                <?php endforeach; ?>
            <?php endif; ?>
        </div>
    </div>
</div>
<script>
(() => {
    const c = document.getElementById('chat'); if (c) c.scrollTop = c.scrollHeight;
    const ta = document.getElementById('replyText');
    document.querySelectorAll('[data-q]').forEach(b => b.addEventListener('click', () => { ta.value = b.dataset.q; ta.focus(); }));
    if (ta) ta.addEventListener('keydown', e => {
        if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); if (ta.value.trim()) document.getElementById('replyForm').submit(); }
    });
    // Yangi xabarlarni ko'rish: yozilayotgan javob bo'lmasa, 15 s da yangilash
    setInterval(() => { if (document.visibilityState === 'visible' && (!ta || !ta.value.trim())) location.reload(); }, 15000);
})();
</script>
<?php include 'includes/footer.php'; ?>
