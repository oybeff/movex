<?php
/**
 * Nizolar (Figma «Admin panel» → 07: N1 ro'yxat, N2 tafsilot, N3 qaror).
 *
 * Nizo — order_problems: hamma turdagi buyurtma, ochadi mijoz yoki ijrochi.
 * SLA: birinchi javob 1 soat, yechim 48 soat. Tayinlanmagan va javobsiz
 * nizo — qizil.
 *
 * Pul va bildirishnomaga tegadigan hamma narsa (xabar tomonlarga, qaror) —
 * backend'ning /admin-orders/internal/disputes/... manzillari orqali:
 * qaror pul mantig'i dispute_service'da, panelda emas.
 */
require_once 'config.php';
require_once 'includes/orders_lib.php';
requireAdmin();
requirePagePerm('disputes');
requireCsrfToken();

$db = getDbConnection();
$db->exec("SET TIME ZONE 'Asia/Tashkent'");
$adminId = (int) ($_SESSION['admin_user_id'] ?? 0);
$currentPage = 'problems';

const DISPUTE_REASONS = [
    'not_arrived' => 'Ijrochi kelmadi',
    'wrong_equipment' => 'Boshqa texnika / mashina keldi',
    'poor_quality' => 'Ish sifatsiz / to\'liq bajarilmadi',
    'price_differs' => 'Narx boshqacha',
    'damaged' => 'Yuk / tovar shikastlangan',
    'wrong_quantity' => 'Miqdor mos emas',
    'client_no_pay' => 'Mijoz to\'lamadi',
    'client_absent' => 'Mijoz joyida yo\'q',
    'other' => 'Boshqa',
];
const SLA_FIRST = 3600;        // 1 soat
const SLA_RESOLVE = 172800;    // 48 soat

function durText(int $sec): string
{
    $m = (int) floor($sec / 60);
    if ($m < 60) { return $m . ' daq'; }
    $h = (int) floor($m / 60);
    if ($h < 24) { return $h . ' s ' . ($m % 60) . ' daq'; }
    return floor($h / 24) . ' kun ' . ($h % 24) . ' s';
}

function slaInfo(array $p): array
{
    if ($p['status'] !== 'open') {
        return [$p['resolution'] ? 'Hal qilindi' : 'Yopildi', 'success'];
    }
    $age = time() - strtotime($p['created_at']);
    if (!$p['first_response_at']) {
        $left = SLA_FIRST - $age;
        return $left > 0 ? [durText($left) . ' ichida javob', 'warning']
                         : ['Javobsiz ' . durText($age), 'danger'];
    }
    $left = SLA_RESOLVE - $age;
    return $left > 0 ? [durText($left) . ' qoldi', $left < 6 * 3600 ? 'warning' : 'secondary']
                     : ['Muddat o\'tdi', 'danger'];
}

// =================================================================== tafsilot
if (isset($_GET['id'])) {
    $id = (int) $_GET['id'];
    $self = 'problems.php?id=' . $id;

    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $a = $_POST['action'] ?? '';
        $flash = ['error', 'Noma\'lum amal'];
        if ($a === 'message') {
            $r = internalApiPost("/admin-orders/internal/disputes/$id/message", [
                'admin_id' => $adminId, 'text' => (string) ($_POST['text'] ?? ''),
                'visibility' => (string) ($_POST['visibility'] ?? 'all'),
            ]);
            $flash = $r['ok'] ? ['success', 'Xabar yuborildi'] : ['error', $r['error']];
        } elseif ($a === 'take') {
            $r = internalApiPost("/admin-orders/internal/disputes/$id/assign", ['admin_id' => $adminId, 'to_admin_id' => $adminId]);
            $flash = $r['ok'] ? ['success', 'Nizo sizga biriktirildi'] : ['error', $r['error']];
        } elseif ($a === 'resolve') {
            $payload = ['admin_id' => $adminId, 'decision' => (string) ($_POST['decision'] ?? ''),
                        'note' => trim((string) ($_POST['note'] ?? '')) ?: null];
            if (($_POST['decision'] ?? '') === 'partial') {
                $payload['refund_amount'] = (float) preg_replace('/[^\d.]/', '', (string) ($_POST['refund_amount'] ?? '0'));
            }
            $r = internalApiPost("/admin-orders/internal/disputes/$id/resolve", $payload);
            $flash = $r['ok'] ? ['success', 'Qaror chiqarildi. Tomonlarga bildirishnoma yuborildi'] : ['error', 'Qaror chiqmadi: ' . $r['error']];
        }
        $_SESSION['flash'] = $flash;
        header('Location: ' . $self);
        exit;
    }
    $flash = $_SESSION['flash'] ?? null;
    unset($_SESSION['flash']);

    $st = $db->prepare('SELECT p.*, u.full_name AS opener, u.phone AS opener_phone, a.full_name AS admin_name
                          FROM order_problems p JOIN users u ON u.id = p.user_id
                          LEFT JOIN users a ON a.id = p.assigned_admin_id WHERE p.id = ?');
    $st->execute([$id]);
    $p = $st->fetch();
    $pageTitle = 'Operatsiyalar / Nizolar / #D-' . $id;
    if (!$p) {
        include 'includes/header.php';
        echo '<div class="content"><div class="card"><div class="empty-state"><b>Nizo topilmadi</b><br><a class="btn btn-secondary btn-sm mt-2" href="problems.php">Ro\'yxatga</a></div></div></div>';
        include 'includes/footer.php';
        exit;
    }
    $st = $db->prepare('SELECT u.* FROM ' . ordersUnionSql() . ' WHERE u.kind = ? AND u.id = ?');
    $st->execute([$p['kind'], $p['order_id']]);
    $ord = $st->fetch() ?: [];
    $msgs = $db->prepare('SELECT m.*, u.full_name FROM dispute_messages m LEFT JOIN users u ON u.id = m.author_id
                           WHERE m.problem_id = ? ORDER BY m.created_at');
    $msgs->execute([$id]);
    $msgs = $msgs->fetchAll();
    $opts = null;
    if ($p['status'] === 'open') {
        $r = internalApiGet("/admin-orders/internal/disputes/$id/options");
        $opts = $r['ok'] ? $r['data'] : ['error' => $r['error']];
    }
    // Ijrochining tarixi — dalil sifatida
    $perfHist = [];
    if (!empty($ord['perf_id'])) {
        $s = $db->prepare("SELECT COUNT(*) AS n, COUNT(*) FILTER (WHERE st = 'done') AS ok FROM " . ordersUnionSql() . " WHERE u.perf_id = ?");
        $s->execute([$ord['perf_id']]);
        $perfHist = $s->fetch();
        $s = $db->prepare("SELECT COUNT(*) FROM order_problems p2 WHERE p2.id <> ? AND EXISTS (
                              SELECT 1 FROM " . ordersUnionSql() . " WHERE u.kind = p2.kind AND u.id = p2.order_id AND u.perf_id = ?)");
        $s->execute([$id, $ord['perf_id']]);
        $perfHist['disputes'] = (int) $s->fetchColumn();
    }
    [$slaText, $slaTone] = slaInfo($p);
    $roleTxt = $p['opened_role'] === 'client' ? 'Mijoz → ijrochi' : 'Ijrochi → mijoz';
    $visLabel = ['all' => 'Ikkala tomonga', 'client' => 'Faqat mijozga', 'performer' => 'Faqat ijrochiga', 'internal' => 'Ichki izoh'];
    $photos = json_decode((string) $p['photos'], true) ?: [];

    include 'includes/header.php';
    ?>
    <div class="content">
        <?php if ($flash): ?><div class="alert alert-<?= $flash[0] === 'success' ? 'success' : 'error' ?>"><?= htmlspecialchars($flash[1]) ?></div><?php endif; ?>
        <div class="od-head">
            <a class="icon-btn" href="problems.php" aria-label="Orqaga" style="border:1px solid var(--border)"><i data-lucide="chevron-left"></i></a>
            <div>
                <h2>#D-<?= $id ?> · <?= htmlspecialchars(DISPUTE_REASONS[$p['reason']] ?? $p['reason']) ?>
                    <span class="badge badge-<?= $p['status'] === 'open' ? 'warning' : 'success' ?>"><?= $p['status'] === 'open' ? 'Ochiq' : 'Hal qilingan' ?></span>
                    <span class="badge badge-<?= $slaTone ?>">SLA · <?= htmlspecialchars($slaText) ?></span>
                </h2>
                <div class="sub">#<?= (int) $p['order_id'] ?> · <?= ORDER_KINDS[$p['kind']] ?><?= $ord ? ' · ' . htmlspecialchars(orderWhat($ord)) : '' ?> ·
                    ochilgan <?= agoText($p['created_at']) ?> · <?= $roleTxt ?> · Mas'ul: <?= htmlspecialchars($p['admin_name'] ?? 'tayinlanmagan') ?></div>
            </div>
            <div class="page-actions">
                <a class="btn btn-secondary btn-sm" href="<?= orderHref($p['kind'], (int) $p['order_id']) ?>"><i data-lucide="clipboard-list"></i> Buyurtma</a>
                <?php if ($p['status'] === 'open' && (int) $p['assigned_admin_id'] !== $adminId): ?>
                    <form method="post"><input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
                        <input type="hidden" name="action" value="take">
                        <button class="btn btn-secondary btn-sm" type="submit"><i data-lucide="user-check"></i> Menga olish</button></form>
                <?php endif; ?>
            </div>
        </div>

        <div class="od-grid">
            <div class="card">
                <div class="card-header"><div class="card-title">Muloqot</div><span class="text-muted" style="font-size:12.5px">Ikkala tomon + ichki izohlar</span></div>
                <div class="card-body chat">
                    <div class="msg in">
                        <div class="who"><?= htmlspecialchars($p['opener']) ?> · <?= $p['opened_role'] === 'client' ? 'mijoz' : 'ijrochi' ?> · <?= date('H:i', strtotime($p['created_at'])) ?></div>
                        <div class="bubble"><b><?= htmlspecialchars(DISPUTE_REASONS[$p['reason']] ?? $p['reason']) ?>.</b> <?= nl2br(htmlspecialchars((string) $p['comment'])) ?>
                            <?php if ($photos): ?><div class="photos">
                                <?php foreach ($photos as $ph): if (!is_string($ph) || strpos($ph, '/static/problems/') !== 0) { continue; } ?>
                                    <a href="<?= htmlspecialchars($ph) ?>" target="_blank" rel="noopener"><img src="<?= htmlspecialchars($ph) ?>" alt="Rasm"></a>
                                <?php endforeach; ?></div><?php endif; ?>
                        </div>
                    </div>
                    <?php foreach ($msgs as $m):
                        $mine = $m['author_role'] === 'admin';
                        $cls = $m['visibility'] === 'internal' ? 'note-msg' : ($mine ? 'out' : 'in');
                        $roleName = ['client' => 'mijoz', 'performer' => 'ijrochi', 'admin' => $visLabel[$m['visibility']]][$m['author_role']];
                    ?>
                        <div class="msg <?= $cls ?>">
                            <div class="who"><?= htmlspecialchars($m['full_name'] ?? '—') ?> · <?= $roleName ?> · <?= date('H:i', strtotime($m['created_at'])) ?></div>
                            <div class="bubble"><?= nl2br(htmlspecialchars((string) $m['text'])) ?>
                                <?php $mp = json_decode((string) $m['photos'], true) ?: []; if ($mp): ?><div class="photos">
                                    <?php foreach ($mp as $ph): if (!is_string($ph) || strpos($ph, '/static/problems/') !== 0) { continue; } ?>
                                        <a href="<?= htmlspecialchars($ph) ?>" target="_blank" rel="noopener"><img src="<?= htmlspecialchars($ph) ?>" alt="Rasm"></a>
                                    <?php endforeach; ?></div><?php endif; ?>
                            </div>
                        </div>
                    <?php endforeach; ?>
                </div>
                <?php if ($p['status'] === 'open'): ?>
                <form method="post" class="composer">
                    <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
                    <input type="hidden" name="action" value="message">
                    <div class="seg" role="radiogroup" aria-label="Kimga">
                        <?php foreach ($visLabel as $k => $v): ?>
                            <label><input type="radio" name="visibility" value="<?= $k ?>" <?= $k === 'all' ? 'checked' : '' ?> hidden><span><?= $v ?></span></label>
                        <?php endforeach; ?>
                    </div>
                    <div class="d-flex gap-1 mt-1">
                        <textarea name="text" rows="2" required maxlength="2000" placeholder="Xabar yozing…"></textarea>
                        <button class="btn btn-primary" type="submit" style="align-self:flex-end"><i data-lucide="send"></i> Yuborish</button>
                    </div>
                </form>
                <?php endif; ?>
            </div>

            <div>
                <div class="card"><div class="card-body pay-rows">
                    <b>Dalillar (avtomatik)</b>
                    <?php if ($ord): ?>
                        <div class="r"><span>Buyurtma</span><b><?= htmlspecialchars(orderStatusBadge($ord)[0]) ?></b></div>
                        <div class="r"><span>Summa</span><b><?= moneyFmt($ord['amount']) ?> so'm</b></div>
                        <div class="r"><span>To'lov</span><b><?= htmlspecialchars(orderPaymentLabel($ord)[0]) ?></b></div>
                        <div class="r"><span>Mijoz</span><b><?= htmlspecialchars($ord['client_name']) ?></b></div>
                        <div class="r"><span>Ijrochi</span><b><?= htmlspecialchars($ord['perf_name'] ?? '—') ?></b></div>
                        <?php if ($perfHist): ?>
                            <div class="r"><span>Ijrochi tarixi</span><b><?= (int) $perfHist['n'] ?> buyurtma · <?= (int) $perfHist['disputes'] ?> nizo</b></div>
                        <?php endif; ?>
                    <?php endif; ?>
                    <div class="form-hint mt-1">Qadamlar vaqtlari — buyurtma sahifasidagi «Holatlar tarixi»da.</div>
                </div></div>

                <?php if ($p['status'] === 'open'): ?>
                <div class="card"><div class="card-body">
                    <b>Qaror</b>
                    <?php if (!empty($opts['error'])): ?>
                        <div class="alert alert-error mt-1"><?= htmlspecialchars($opts['error']) ?></div>
                    <?php else:
                        $amount = (float) ($opts['amount'] ?? 0);
                        $choices = [
                            'client' => ['Mijoz foydasiga — to\'liq qaytarish', 'Buyurtma bekor, muzlatish yechiladi'],
                            'partial' => ['Qisman qaytarish', 'Mijozga qism, qolgani ijrochiga (komissiya bilan)'],
                            'performer' => ['Ijrochi foydasiga', 'Buyurtma yakunlanadi, pul ijrochiga'],
                            'close' => ['Nizoni yopish', 'Pul qimirlamaydi'],
                        ];
                    ?>
                    <form method="post" id="resolveForm" class="mt-1">
                        <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
                        <input type="hidden" name="action" value="resolve">
                        <?php foreach ($choices as $k => [$t, $s]): $why = $opts['options'][$k] ?? null; ?>
                            <label class="choice <?= $why ? 'disabled' : '' ?>">
                                <input type="radio" name="decision" value="<?= $k ?>" <?= $why ? 'disabled' : '' ?> required>
                                <span><b><?= $t ?></b><small><?= $s ?></small><?php if ($why): ?><small class="why"><?= htmlspecialchars($why) ?></small><?php endif; ?></span>
                            </label>
                        <?php endforeach; ?>
                        <div class="form-group hidden" id="refundBox">
                            <label for="refund">Mijozga qaytariladi, so'm (buyurtma <?= moneyFmt($amount) ?>)</label>
                            <input type="number" id="refund" name="refund_amount" min="1" max="<?= max(0, (int) $amount - 1) ?>" step="1">
                        </div>
                        <div class="form-group"><label for="rnote">Izoh (audit jurnaliga)</label>
                            <textarea id="rnote" name="note" rows="2" placeholder="Qaror sababi"></textarea></div>
                        <button class="btn btn-primary btn-block" type="button" data-open="modalConfirm"><i data-lucide="check"></i> Qarorni chiqarish</button>
                    </form>
                    <?php endif; ?>
                </div></div>
                <?php else: ?>
                <div class="card"><div class="card-body pay-rows">
                    <b>Qaror</b>
                    <div class="r"><span>Natija</span><b><?= ['client' => 'Mijoz foydasiga', 'partial' => 'Qisman', 'performer' => 'Ijrochi foydasiga', 'close' => 'Yopildi'][$p['resolution']] ?? '—' ?></b></div>
                    <?php if ($p['refund_amount'] !== null): ?><div class="r"><span>Mijozga qaytdi</span><b><?= moneyFmt($p['refund_amount']) ?> so'm</b></div><?php endif; ?>
                    <div class="r"><span>Vaqt</span><b><?= agoText($p['resolved_at']) ?></b></div>
                </div></div>
                <?php endif; ?>
            </div>
        </div>
    </div>

    <?php if ($p['status'] === 'open' && empty($opts['error'])): ?>
    <!-- N3 · Qarorni tasdiqlash -->
    <div class="modal" id="modalConfirm" role="dialog" aria-modal="true" aria-labelledby="cTitle">
        <div class="modal-content" style="max-width:460px">
            <div class="modal-header"><div class="modal-title" id="cTitle">Qarorni tasdiqlash</div>
                <button class="modal-close" type="button" data-close aria-label="Yopish">×</button></div>
            <div class="modal-body">
                <div class="pay-rows" id="confirmRows"></div>
                <div class="alert alert-warning mt-2" style="margin-bottom:0"><i data-lucide="triangle-alert"></i>
                    <div>Pul harakatini ortga qaytarib bo'lmaydi. Tomonlarga bildirishnoma boradi.</div></div>
            </div>
            <div class="modal-footer">
                <button class="btn btn-secondary" type="button" data-close>Ortga</button>
                <button class="btn btn-primary" type="button" id="confirmGo">Tasdiqlash</button>
            </div>
        </div>
    </div>
    <script>
    (() => {
        const f = document.getElementById('resolveForm');
        const box = document.getElementById('refundBox');
        const amount = <?= json_encode($amount) ?>;
        const fmt = n => Math.round(n).toLocaleString('ru-RU').replace(/,/g, ' ');
        f.querySelectorAll('input[name=decision]').forEach(r => r.addEventListener('change', () => {
            box.classList.toggle('hidden', r.value !== 'partial' || !r.checked);
            document.getElementById('refund').required = r.value === 'partial' && r.checked;
        }));
        document.querySelector('[data-open=modalConfirm]').addEventListener('click', e => {
            const d = f.querySelector('input[name=decision]:checked');
            if (!d) { e.stopImmediatePropagation(); notify.warning('Qarorni tanlang'); return; }
            const R = +document.getElementById('refund').value || 0;
            if (d.value === 'partial' && (R <= 0 || R >= amount)) { e.stopImmediatePropagation(); notify.warning("Summani to'g'ri kiriting"); return; }
            const rows = {
                client: [['Buyurtma', 'bekor qilinadi'], ['Mijozga qaytadi', fmt(amount) + " so'm"]],
                partial: [['Mijozga qaytadi', fmt(R) + " so'm"], ['Ijrochiga o\'tadi (komissiyadan oldin)', fmt(amount - R) + " so'm"]],
                performer: [['Buyurtma', 'yakunlanadi'], ['Ijrochiga (komissiyadan oldin)', fmt(amount) + " so'm"]],
                close: [['Pul', 'qimirlamaydi']],
            }[d.value];
            document.getElementById('confirmRows').innerHTML = rows.map(r => `<div class="r"><span>${r[0]}</span><b>${r[1]}</b></div>`).join('');
        }, true);
        document.getElementById('confirmGo').addEventListener('click', () => f.submit());
    })();
    </script>
    <?php endif; ?>
    <script>
    document.querySelectorAll('[data-open]').forEach(b => b.addEventListener('click', () => {
        const el = document.getElementById(b.dataset.open); if (el) el.classList.add('active');
    }));
    document.querySelectorAll('.modal').forEach(m => m.addEventListener('click', e => {
        if (e.target === m || e.target.closest('[data-close]')) m.classList.remove('active');
    }));
    document.querySelectorAll('.composer .seg label').forEach(l => l.addEventListener('click', () => {
        document.querySelectorAll('.composer .seg label').forEach(x => x.classList.remove('active'));
        l.classList.add('active');
    }));
    const first = document.querySelector('.composer .seg label'); if (first) first.classList.add('active');
    const chat = document.querySelector('.chat'); if (chat) chat.scrollTop = chat.scrollHeight;
    </script>
    <?php
    include 'includes/footer.php';
    exit;
}

// =================================================================== N1 · ro'yxat
$pageTitle = 'Operatsiyalar / Nizolar';
$tab = $_GET['tab'] ?? 'open';
$tabs = ['open' => 'Ochiq', 'waiting' => 'Javob berilgan', 'resolved' => 'Hal qilingan', 'all' => 'Hammasi'];
if (!isset($tabs[$tab])) { $tab = 'open'; }
$whereTab = ['open' => "p.status = 'open' AND p.first_response_at IS NULL",
             'waiting' => "p.status = 'open' AND p.first_response_at IS NOT NULL",
             'resolved' => "p.status = 'resolved'", 'all' => 'true'][$tab];
$counts = $db->query("SELECT
    COUNT(*) FILTER (WHERE status = 'open' AND first_response_at IS NULL) AS open,
    COUNT(*) FILTER (WHERE status = 'open' AND first_response_at IS NOT NULL) AS waiting,
    COUNT(*) FILTER (WHERE status = 'resolved') AS resolved, COUNT(*) AS all_n FROM order_problems")->fetch();
$counts['all'] = $counts['all_n'];

$rows = $db->query("SELECT p.*, u.full_name AS opener, a.full_name AS admin_name, x.amount, x.perf_name, x.client_name,
                           (SELECT COUNT(*) FROM dispute_messages m WHERE m.problem_id = p.id) AS msgs
                      FROM order_problems p
                      JOIN users u ON u.id = p.user_id
                      LEFT JOIN users a ON a.id = p.assigned_admin_id
                      LEFT JOIN LATERAL (SELECT uu.amount, uu.perf_name, uu.client_name FROM " . ordersUnionSql('uu')
                           . " WHERE uu.kind = p.kind AND uu.id = p.order_id) x ON true
                     WHERE $whereTab
                     ORDER BY (p.status = 'open' AND p.first_response_at IS NULL AND p.created_at < NOW() - INTERVAL '1 hour') DESC,
                              p.created_at DESC LIMIT 200")->fetchAll();

if (($_GET['export'] ?? '') === 'csv') {
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="nizolar-' . date('Y-m-d') . '.csv"');
    $out = fopen('php://output', 'w');
    fwrite($out, "\xEF\xBB\xBF");
    fputcsv($out, ['Nizo', 'Turi', 'Buyurtma', 'Ochgan', 'Sabab', 'Summa', 'Holat', 'Qaror', 'Qaytarildi', 'Ochilgan', 'Hal qilingan']);
    foreach ($rows as $r) {
        fputcsv($out, ['D-' . $r['id'], ORDER_KINDS[$r['kind']], $r['order_id'], $r['opener'], DISPUTE_REASONS[$r['reason']] ?? $r['reason'],
            (float) $r['amount'], $r['status'], $r['resolution'], $r['refund_amount'], $r['created_at'], $r['resolved_at']]);
    }
    exit;
}

include 'includes/header.php';
?>
<div class="content">
    <div class="page-head">
        <div><h2>Nizolar va shikoyatlar</h2>
            <div class="sub">Mijoz va ijrochilar ilovadan ochadi. SLA: birinchi javob 1 soat, yechim 48 soat</div></div>
        <div class="page-actions"><a class="btn btn-secondary btn-sm" href="?tab=<?= $tab ?>&export=csv"><i data-lucide="download"></i> Eksport</a></div>
    </div>
    <div class="tabs">
        <?php foreach ($tabs as $k => $v): ?>
            <a href="?tab=<?= $k ?>" class="<?= $tab === $k ? 'active' : '' ?>"><?= $v ?>
                <span class="nav-count <?= $k === 'open' && $counts['open'] ? 'danger' : '' ?>"><?= (int) $counts[$k] ?></span></a>
        <?php endforeach; ?>
    </div>
    <div class="card">
        <?php if (!$rows): ?>
            <div class="empty-state"><i data-lucide="shield-check"></i><div>Bu bo'limda nizo yo'q</div></div>
        <?php else: ?>
        <div class="table-responsive"><table>
            <thead><tr><th>Nizo</th><th>Buyurtma</th><th>Tashabbuskor</th><th>Sabab</th><th class="text-right">Nizodagi summa</th><th>SLA</th><th>Mas'ul</th><th></th></tr></thead>
            <tbody>
            <?php foreach ($rows as $r):
                [$slaText, $slaTone] = slaInfo($r);
                $red = $r['status'] === 'open' && !$r['first_response_at'] && strtotime($r['created_at']) < time() - SLA_FIRST;
            ?>
                <tr class="<?= $red ? 'row-alert' : '' ?>" data-href="problems.php?id=<?= (int) $r['id'] ?>">
                    <td><a href="problems.php?id=<?= (int) $r['id'] ?>"><b>#D-<?= (int) $r['id'] ?></b></a><span class="sub"><?= agoText($r['created_at']) ?></span></td>
                    <td><a href="<?= orderHref($r['kind'], (int) $r['order_id']) ?>">#<?= (int) $r['order_id'] ?></a><span class="sub"><?= ORDER_KINDS[$r['kind']] ?></span></td>
                    <td><?= htmlspecialchars($r['opener']) ?><span class="sub"><?= $r['opened_role'] === 'client' ? 'Mijoz → ijrochi' : 'Ijrochi → mijoz' ?></span></td>
                    <td><?= htmlspecialchars(DISPUTE_REASONS[$r['reason']] ?? $r['reason']) ?><?php if ($r['msgs']): ?><span class="sub"><?= (int) $r['msgs'] ?> xabar</span><?php endif; ?></td>
                    <td class="text-right num"><?= $r['amount'] !== null ? moneyFmt($r['amount']) : '—' ?></td>
                    <td><span class="badge badge-<?= $slaTone ?>"><?= htmlspecialchars($slaText) ?></span></td>
                    <td><?= $r['admin_name'] ? htmlspecialchars($r['admin_name']) : '<span class="text-danger">Tayinlanmagan</span>' ?></td>
                    <td><a class="icon-btn" href="problems.php?id=<?= (int) $r['id'] ?>" aria-label="Ochish"><i data-lucide="chevron-right"></i></a></td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table></div>
        <?php endif; ?>
    </div>
</div>
<script>
document.querySelectorAll('tr[data-href]').forEach(tr => tr.addEventListener('click', e => {
    if (!e.target.closest('a,button,input')) location.href = tr.dataset.href;
}));
</script>
<?php include 'includes/footer.php'; ?>
