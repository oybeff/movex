<?php
/**
 * 08 · Push xabarlar (Figma «Admin panel» P1–P4).
 *
 * Yuborish backendda (push_campaign_service): har qabul qiluvchiga ilova
 * ichidagi bildirishnoma + FCM push (Firebase hali ulanmagan — unda faqat
 * ilova ichida). «Yetkazildi» — yozilgan bildirishnomalar, «Ochildi» —
 * ulardan o'qilganlari; ikkalasi ham haqiqiy hisob.
 * Jim soatlar 22:00–08:00: shu oraliqdagi yuborish 08:00 ga suriladi.
 */
require_once 'config.php';
requireAdmin();
requirePagePerm('push');
requireCsrfToken();

$db = getDbConnection();
$db->exec("SET TIME ZONE 'Asia/Tashkent'");
$adminId = (int) $_SESSION['admin_user_id'];
$pageTitle = 'Push xabarlar';
$currentPage = 'push';

$zones = $db->query("SELECT id, name FROM price_zones WHERE is_enabled ORDER BY sort_order, name")->fetchAll();

function audienceFromPost(array $p): array {
    return [
        'role' => in_array($p['role'] ?? '', ['all', 'client', 'driver'], true) ? $p['role'] : 'client',
        'langs' => array_values(array_intersect((array) ($p['langs'] ?? []), ['uz', 'ru'])),
        'active_days' => (int) ($p['active_days'] ?? 0) ?: null,
        'zone_id' => (int) ($p['zone_id'] ?? 0) ?: null,
    ];
}

// Auditoriya hisobi (forma o'zgarganda fetch)
if (isset($_GET['audience'])) {
    header('Content-Type: application/json; charset=utf-8');
    $r = internalApiPost('/admin-p5/internal/push/audience', ['audience' => audienceFromPost($_GET)]);
    echo json_encode($r['ok'] ? $r['data'] : ['error' => $r['error']], JSON_UNESCAPED_UNICODE);
    exit;
}

$form = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $a = $_POST['action'] ?? '';
    $payload = [
        'admin_id' => $adminId,
        'title_uz' => trim((string) ($_POST['title_uz'] ?? '')), 'body_uz' => trim((string) ($_POST['body_uz'] ?? '')),
        'title_ru' => trim((string) ($_POST['title_ru'] ?? '')) ?: null, 'body_ru' => trim((string) ($_POST['body_ru'] ?? '')) ?: null,
        'audience' => audienceFromPost($_POST),
    ];
    if ($a === 'cancel') {
        $r = internalApiPost('/admin-p5/internal/push/' . (int) $_POST['id'] . '/cancel', ['admin_id' => $adminId]);
        $_SESSION['toast'] = $r['ok'] ? ['success', 'Xabar bekor qilindi'] : ['error', $r['error']];
        header('Location: push.php');
        exit;
    }
    if ($a === 'test') {
        $payload['phone'] = (string) ($_POST['test_phone'] ?? '');
        $r = internalApiPost('/admin-p5/internal/push/test', $payload);
        $_SESSION['toast'] = $r['ok'] ? ['success', 'Sinov xabari yuborildi — ilovadagi «Bildirishnomalar»da ko\'rinadi'] : ['error', $r['error']];
        $form = $_POST;
    } elseif (in_array($a, ['draft', 'send'], true)) {
        $mode = $a === 'draft' ? 'draft' : (($_POST['when'] ?? 'now') === 'schedule' ? 'schedule' : 'now');
        $payload['mode'] = $mode;
        $payload['scheduled_at'] = $mode === 'schedule' ? (string) ($_POST['scheduled_at'] ?? '') : null;
        $r = internalApiPost('/admin-p5/internal/push/campaigns', $payload);
        if ($r['ok']) {
            $fromDraft = (int) ($_POST['draft_id'] ?? 0);
            if ($fromDraft) $db->prepare("DELETE FROM push_campaigns WHERE id = ? AND status = 'draft'")->execute([$fromDraft]);
            $d = $r['data'];
            $msg = $mode === 'draft' ? 'Qoralama saqlandi'
                : ($d['status'] === 'sent' ? number_format($d['recipients'], 0, '', ' ') . ' ta qabul qiluvchiga yuborildi'
                : 'Rejalashtirildi: ' . date('d.m H:i', strtotime($d['scheduled_at'])));
            $_SESSION['toast'] = ['success', $msg];
            header('Location: push.php');
            exit;
        }
        $_SESSION['toast'] = ['error', $r['error']];
        $form = $_POST;
    }
}

// ------------------------------------------------------------- tahrir / yangi
$compose = isset($_GET['new']) || $form !== null;
if (isset($_GET['from'])) {
    $st = $db->prepare('SELECT * FROM push_campaigns WHERE id = ?');
    $st->execute([(int) $_GET['from']]);
    if ($c = $st->fetch()) {
        $aud = json_decode($c['audience'], true) ?: [];
        $form = ['title_uz' => $c['title_uz'], 'body_uz' => $c['body_uz'], 'title_ru' => $c['title_ru'], 'body_ru' => $c['body_ru'],
                 'role' => $aud['role'] ?? 'client', 'langs' => $aud['langs'] ?? ['uz', 'ru'], 'active_days' => $aud['active_days'] ?? '',
                 'zone_id' => $aud['zone_id'] ?? '', 'draft_id' => $c['status'] === 'draft' ? $c['id'] : ''];
        $compose = true;
    }
}
$f = array_merge(['title_uz' => '', 'body_uz' => '', 'title_ru' => '', 'body_ru' => '', 'role' => 'client', 'langs' => ['uz', 'ru'],
                  'active_days' => '30', 'zone_id' => '', 'when' => 'now', 'scheduled_at' => '', 'draft_id' => '', 'test_phone' => ''], $form ?? []);

// ------------------------------------------------------------- ro'yxat (P1)
$tab = $_GET['tab'] ?? 'all';
$tabs = ['all' => 'Hammasi', 'scheduled' => 'Rejalashtirilgan', 'draft' => 'Qoralama', 'failed' => 'Xato'];
if (!isset($tabs[$tab])) $tab = 'all';
$q = trim((string) ($_GET['q'] ?? ''));
$where = ['TRUE'];
$params = [];
if ($tab !== 'all') { $where[] = 'c.status = ?'; $params[] = $tab; }
if ($q !== '') { $where[] = '(c.title_uz ILIKE ? OR c.title_ru ILIKE ?)'; $params[] = "%$q%"; $params[] = "%$q%"; }
$perPage = 15;
$page = max(1, (int) ($_GET['page'] ?? 1));
$cnt = $db->prepare('SELECT COUNT(*) FROM push_campaigns c WHERE ' . implode(' AND ', $where));
$cnt->execute($params);
$total = (int) $cnt->fetchColumn();
$pages = max(1, (int) ceil($total / $perPage));
$st = $db->prepare('SELECT c.*, u.full_name AS author,
                           (SELECT COUNT(*) FROM notifications n WHERE n.campaign_id = c.id AND n.is_read) AS opened
                      FROM push_campaigns c LEFT JOIN users u ON u.id = c.created_by
                     WHERE ' . implode(' AND ', $where) . ' ORDER BY COALESCE(c.sent_at, c.scheduled_at, c.created_at) DESC
                     LIMIT ' . $perPage . ' OFFSET ' . (($page - 1) * $perPage));
$st->execute($params);
$rows = $st->fetchAll();
$tabCounts = [];
foreach ($db->query("SELECT status, COUNT(*) c FROM push_campaigns GROUP BY status") as $r) $tabCounts[$r['status']] = (int) $r['c'];
$zoneNames = array_column($zones, 'name', 'id');

function audienceText(array $a, array $zoneNames): string {
    $role = ['all' => 'Barcha', 'client' => 'Mijozlar', 'driver' => 'Haydovchilar'][$a['role'] ?? 'all'] ?? 'Barcha';
    $parts = [$role];
    if (!empty($a['zone_id'])) $parts[] = $zoneNames[$a['zone_id']] ?? ('Hudud #' . $a['zone_id']);
    if (!empty($a['active_days'])) $parts[] = $a['active_days'] . ' kun faol';
    $parts[] = strtoupper(implode('/', $a['langs'] ?? ['uz', 'ru']));
    return implode(' · ', $parts);
}
$statusBadge = ['draft' => ['Qoralama', 'secondary'], 'scheduled' => ['Rejalashtirilgan', 'warning'], 'sending' => ['Yuborilmoqda', 'info'],
                'sent' => ['Yuborildi', 'success'], 'failed' => ['Xato', 'danger'], 'cancelled' => ['Bekor qilingan', 'secondary']];
$pushReady = (bool) (($movexEnv['FCM_PROJECT_ID'] ?? '') && ($movexEnv['FCM_CREDENTIALS_FILE'] ?? ''));
$csrf = generateCsrfToken();
include 'includes/header.php';
?>
<div class="content">
<?php if (!$compose): ?>
    <div class="page-head">
        <div><h2>Push xabarlar</h2><div class="sub">Yuborilgan, rejalashtirilgan va qoralamalar</div></div>
        <div class="page-actions"><a class="btn btn-primary" href="push.php?new=1"><i data-lucide="plus"></i> Yangi xabar</a></div>
    </div>
    <?php if (!$pushReady): ?>
        <div class="banner banner-info"><i data-lucide="info"></i>
            <div><b>Hozircha faqat ilova ichida</b><span>Firebase (FCM) ulanmagan: xabar «Bildirishnomalar» bo'limiga tushadi, telefon ekraniga chiqmaydi. Ulanganda push o'zi qo'shiladi.</span></div></div>
    <?php endif; ?>
    <div class="tabs">
        <?php foreach ($tabs as $k => $v): ?>
            <a href="push.php?tab=<?= $k ?>" class="<?= $tab === $k ? 'active' : '' ?>"><?= $v ?>
                <?php if ($k !== 'all' && !empty($tabCounts[$k])): ?><span class="nav-count <?= $k === 'failed' ? 'danger' : '' ?>"><?= $tabCounts[$k] ?></span><?php endif; ?></a>
        <?php endforeach; ?>
    </div>
    <form class="filters" method="get"><input type="hidden" name="tab" value="<?= htmlspecialchars($tab) ?>">
        <div class="filter-search"><i data-lucide="search"></i><input type="search" name="q" value="<?= htmlspecialchars($q) ?>" placeholder="Sarlavha bo'yicha qidirish"></div>
    </form>
    <div class="card">
        <?php if (!$rows): ?>
            <div class="empty-state"><i data-lucide="bell-ring"></i><div><b><?= $q !== '' || $tab !== 'all' ? 'Mos xabar topilmadi' : 'Hali xabar yuborilmagan' ?></b></div>
                <div><a class="btn btn-primary btn-sm mt-1" href="push.php?new=1">Birinchi xabarni yaratish</a></div></div>
        <?php else: ?>
        <div class="table-responsive"><table>
            <thead><tr><th>Xabar</th><th>Auditoriya</th><th>Holat</th><th class="text-right">Yetkazildi</th><th class="text-right">Ochildi</th><th>Vaqt</th><th style="width:120px"></th></tr></thead>
            <tbody>
            <?php foreach ($rows as $r):
                $aud = json_decode($r['audience'], true) ?: [];
                [$bt, $bc] = $statusBadge[$r['status']];
                $when = $r['sent_at'] ?: ($r['scheduled_at'] ?: $r['created_at']);
                $pct = $r['recipients'] ? round($r['opened'] * 100 / $r['recipients'], 1) : null; ?>
                <tr>
                    <td><b><?= htmlspecialchars($r['title_uz']) ?></b><small class="sub"><?= htmlspecialchars(mb_strimwidth($r['body_uz'], 0, 70, '…')) ?></small></td>
                    <td><?= htmlspecialchars(audienceText($aud, $zoneNames)) ?></td>
                    <td><span class="badge badge-<?= $bc ?>"><?= $bt ?></span><?php if ($r['error']): ?><small class="sub text-danger"><?= htmlspecialchars(mb_strimwidth($r['error'], 0, 60, '…')) ?></small><?php endif; ?></td>
                    <td class="text-right num"><?= $r['status'] === 'sent' ? number_format($r['recipients'], 0, '', ' ') : '—' ?></td>
                    <td class="text-right num"><?= $pct !== null ? number_format($r['opened'], 0, '', ' ') . '<small class="sub">' . str_replace('.', ',', $pct) . '%</small>' : '—' ?></td>
                    <td><?= date('d.m H:i', strtotime($when)) ?><small class="sub"><?= htmlspecialchars($r['author'] ?? 'Avto') ?></small></td>
                    <td class="text-right">
                        <?php if (in_array($r['status'], ['draft', 'failed', 'sent', 'cancelled'], true)): ?>
                            <a class="btn btn-ghost btn-sm" href="push.php?from=<?= (int) $r['id'] ?>"><?= $r['status'] === 'draft' ? 'Tahrirlash' : 'Nusxa' ?></a><?php endif; ?>
                        <?php if (in_array($r['status'], ['draft', 'scheduled'], true)): ?>
                            <form method="post" class="inline-form"><input type="hidden" name="csrf_token" value="<?= $csrf ?>">
                                <input type="hidden" name="id" value="<?= (int) $r['id'] ?>">
                                <button class="btn btn-ghost btn-sm text-danger" name="action" value="cancel" data-confirm="«<?= htmlspecialchars($r['title_uz']) ?>» bekor qilinsinmi?">Bekor</button></form>
                        <?php endif; ?>
                    </td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table></div>
        <div class="table-foot"><span class="text-muted"><?= ($page - 1) * $perPage + 1 ?>–<?= ($page - 1) * $perPage + count($rows) ?> / <?= $total ?> ta</span>
            <div class="pagination" style="padding:0"><?php for ($i = max(1, $page - 2); $i <= min($pages, $page + 2); $i++): ?>
                <?= $i === $page ? '<span class="active">' . $i . '</span>' : '<a href="push.php?' . htmlspecialchars(http_build_query(['tab' => $tab, 'q' => $q, 'page' => $i])) . '">' . $i . '</a>' ?><?php endfor; ?></div></div>
        <?php endif; ?>
    </div>
<?php else: ?>
    <!-- P2 · Yangi xabar -->
    <form method="post" id="pushForm" data-dirty-guard>
    <input type="hidden" name="csrf_token" value="<?= $csrf ?>">
    <input type="hidden" name="draft_id" value="<?= htmlspecialchars((string) $f['draft_id']) ?>">
    <div class="page-head">
        <div style="display:flex;gap:16px;align-items:center">
            <a class="icon-btn back" href="push.php" aria-label="Orqaga" style="border:1px solid var(--border)"><i data-lucide="chevron-left"></i></a>
            <div><h2>Yangi push xabar</h2><div class="sub">Mijoz va haydovchi ilovalariga bildirishnoma</div></div>
        </div>
        <div class="page-actions">
            <button class="btn btn-secondary" name="action" value="draft" formnovalidate>Qoralama saqlash</button>
            <button class="btn btn-primary" type="button" id="toConfirm" disabled>Davom etish</button>
        </div>
    </div>
    <div class="push-grid">
        <div class="push-main">
            <div class="card"><div class="card-body">
                <div class="push-step">1. Auditoriya</div>
                <div class="seg-cards">
                    <?php foreach (['client' => 'Mijozlar', 'driver' => 'Haydovchilar', 'all' => 'Hammasi'] as $k => $v): ?>
                        <label class="choice"><input type="radio" name="role" value="<?= $k ?>" <?= $f['role'] === $k ? 'checked' : '' ?>>
                            <span><b><?= $v ?></b><small data-total="<?= $k ?>">…</small></span></label>
                    <?php endforeach; ?>
                </div>
                <div class="push-filters">
                    <label>Hudud<select name="zone_id"><option value="">Barcha hududlar</option>
                        <?php foreach ($zones as $z): ?><option value="<?= (int) $z['id'] ?>" <?= (string) $f['zone_id'] === (string) $z['id'] ? 'selected' : '' ?>><?= htmlspecialchars($z['name']) ?></option><?php endforeach; ?></select></label>
                    <label>Oxirgi faollik<select name="active_days">
                        <?php foreach (['' => 'Hammasi', '7' => '7 kun', '30' => '30 kun', '90' => '90 kun'] as $k => $v): ?><option value="<?= $k ?>" <?= (string) $f['active_days'] === (string) $k ? 'selected' : '' ?>><?= $v ?></option><?php endforeach; ?></select></label>
                    <fieldset><legend>Til</legend>
                        <label class="check"><input type="checkbox" name="langs[]" value="uz" <?= in_array('uz', (array) $f['langs'], true) ? 'checked' : '' ?>> O'zbek</label>
                        <label class="check"><input type="checkbox" name="langs[]" value="ru" <?= in_array('ru', (array) $f['langs'], true) ? 'checked' : '' ?>> Rus</label></fieldset>
                </div>
                <div class="push-count" id="audBox"><i data-lucide="users"></i><div><b id="audTotal">Hisoblanmoqda…</b><span id="audSub"></span></div></div>
                <p class="form-hint">Hudud — haydovchining oxirgi GPS nuqtasi yoki mijozning qidiruv nuqtasi bo'yicha; nuqtasi yo'qlar hudud filtriga tushmaydi. Faollik — ilovani oxirgi ochgan vaqti (1.0.12 dan).</p>
            </div></div>

            <div class="card"><div class="card-body">
                <div class="push-step">2. Kontent</div>
                <div class="tabs push-lang"><a href="#" class="active" data-lang="uz">O'zbekcha</a><a href="#" data-lang="ru">Русский</a></div>
                <?php foreach (['uz', 'ru'] as $l): ?>
                <div class="push-lang-pane" data-pane="<?= $l ?>" <?= $l === 'ru' ? 'hidden' : '' ?>>
                    <div class="form-group"><label>Sarlavha <span class="counter" data-for="title_<?= $l ?>"></span></label>
                        <input type="text" name="title_<?= $l ?>" maxlength="65" value="<?= htmlspecialchars((string) $f['title_' . $l]) ?>" <?= $l === 'uz' ? 'required' : '' ?> placeholder="<?= $l === 'uz' ? 'Hafta oxiri: barcha texnikaga -15%' : 'Выходные: −15% на всю технику' ?>"></div>
                    <div class="form-group"><label>Matn <span class="counter" data-for="body_<?= $l ?>"></span></label>
                        <textarea name="body_<?= $l ?>" maxlength="240" rows="4" <?= $l === 'uz' ? 'required' : '' ?>><?= htmlspecialchars((string) $f['body_' . $l]) ?></textarea></div>
                </div>
                <?php endforeach; ?>
                <p class="form-hint">Ruscha matn bo'sh bo'lsa, rus tilidagi foydalanuvchilarga o'zbekcha yuboriladi. Uzun sarlavha telefonda qirqiladi.</p>
            </div></div>

            <div class="card"><div class="card-body">
                <div class="push-step">3. Yuborish vaqti</div>
                <div class="seg-cards two">
                    <label class="choice"><input type="radio" name="when" value="now" <?= $f['when'] !== 'schedule' ? 'checked' : '' ?>><span><b>Hozir</b><small>Darhol yuboriladi</small></span></label>
                    <label class="choice"><input type="radio" name="when" value="schedule" <?= $f['when'] === 'schedule' ? 'checked' : '' ?>><span><b>Rejalashtirish</b>
                        <input type="datetime-local" name="scheduled_at" value="<?= htmlspecialchars((string) $f['scheduled_at']) ?>" min="<?= date('Y-m-d\TH:i') ?>" class="push-dt"><small>Toshkent vaqti</small></span></label>
                </div>
                <div class="push-quiet" id="quietNote"><i data-lucide="moon"></i><div><b>Jim soatlar: 22:00–08:00</b><span>Bu oraliqqa tushgan xabar ertalab 08:00 da yuboriladi.</span></div></div>
                <div class="push-test">
                    <input type="text" name="test_phone" inputmode="tel" placeholder="Sinov uchun telefon: +998 90 …" value="<?= htmlspecialchars((string) $f['test_phone']) ?>">
                    <button class="btn btn-secondary btn-sm" name="action" value="test" formnovalidate><i data-lucide="smartphone"></i> Sinov yuborish</button>
                </div>
            </div></div>
        </div>
        <aside class="push-preview">
            <div class="form-section" style="margin-top:0">Ko'rinishi (telefon)</div>
            <div class="phone"><div class="phone-time" id="pvClock"></div><div class="phone-date" id="pvDate"></div>
                <div class="phone-note"><div class="phone-app"><span class="phone-icon">M</span>MoveX GO<span>hozir</span></div>
                    <b id="pvTitle">Sarlavha</b><p id="pvBody">Matn</p></div></div>
        </aside>
    </div>

    <!-- P3 · Tasdiqlash -->
    <div class="modal" id="modalConfirm" role="dialog" aria-modal="true" aria-labelledby="pcTitle">
        <div class="modal-content" style="max-width:500px">
            <div class="modal-header"><div class="modal-title" id="pcTitle">—</div><button class="modal-close" type="button" data-close aria-label="Yopish">×</button></div>
            <div class="modal-body">
                <p class="text-muted" style="margin-bottom:14px">Rejalashtirilgan vaqtgacha bekor qilish mumkin. Yuborilgandan keyin qaytarib bo'lmaydi.</p>
                <div class="mini-stats" style="grid-template-columns:repeat(3,1fr)">
                    <div><b class="num" id="pcTotal">—</b><span>Qabul qiluvchi</span></div>
                    <div><b class="num" id="pcLang">—</b><span>Til bo'yicha</span></div>
                    <div><b class="num" id="pcWhen">—</b><span>Yuborish vaqti</span></div>
                </div>
                <div class="banner" id="pcLimit" hidden style="margin:14px 0 0"><i data-lucide="alert-triangle"></i><div><b id="pcLimitT"></b><span>Kunlik limit — 2 ta xabar. Ortiqcha push ilovani o'chirishga olib keladi.</span></div></div>
                <label class="check" style="margin-top:14px"><input type="checkbox" id="pcTested"> Sinov xabari o'z telefonimda tekshirildi</label>
            </div>
            <div class="modal-footer"><button class="btn btn-secondary" type="button" data-close>Orqaga</button>
                <button class="btn btn-primary" name="action" value="send" id="pcSend" disabled>Yuborish</button></div>
        </div>
    </div>
    </form>
<?php endif; ?>
</div>
<?php if ($compose): ?>
<script>
(() => {
    const form = document.getElementById('pushForm');
    const fmt = n => Number(n).toLocaleString('ru-RU').replace(/,/g, ' ');
    let stats = null, timer = null;
    const qs = () => new URLSearchParams([...new FormData(form)].filter(([k]) => ['role', 'zone_id', 'active_days', 'langs[]'].includes(k)).map(([k, v]) => [k.replace('[]', '[]'), v])).toString();
    async function count() {
        audTotal.textContent = 'Hisoblanmoqda…'; audSub.textContent = '';
        try {
            const r = await fetch('push.php?audience=1&' + qs(), { cache: 'no-store' });
            stats = await r.json();
            if (stats.error) throw new Error(stats.error);
            document.querySelector('[data-total=client]').textContent = fmt(stats.clients_total) + ' ta';
            document.querySelector('[data-total=driver]').textContent = fmt(stats.drivers_total) + ' ta';
            document.querySelector('[data-total=all]').textContent = fmt(stats.clients_total + stats.drivers_total) + ' ta';
            const zero = stats.total === 0;
            audBox.classList.toggle('zero', zero);
            audTotal.textContent = zero ? "Tanlangan filtrga mos foydalanuvchi yo'q (0)" : 'Taxminiy qabul qiluvchilar: ' + fmt(stats.total);
            audSub.textContent = zero ? "Filtrlarni kengaytiring. 0 ta qabul qiluvchiga xabar yuborib bo'lmaydi."
                : `UZ ${fmt(stats.by_lang.uz)} · RU ${fmt(stats.by_lang.ru)} · telefonida push ruxsati bor: ${fmt(stats.with_device)}`;
        } catch (e) { stats = null; audTotal.textContent = 'Hisoblab bo\'lmadi'; audSub.textContent = e.message; }
        validate();
    }
    const validate = () => {
        const ok = stats && stats.total > 0 && form.title_uz.value.trim() && form.body_uz.value.trim()
            && (form.when.value !== 'schedule' || form.scheduled_at.value);
        toConfirm.disabled = !ok;
    };
    form.addEventListener('change', e => { if (['role', 'zone_id', 'active_days', 'langs[]'].includes(e.target.name)) { clearTimeout(timer); timer = setTimeout(count, 150); } validate(); quiet(); });
    form.addEventListener('input', () => { preview(); validate(); });
    // Belgilar hisoblagichi
    document.querySelectorAll('.counter').forEach(c => {
        const el = form.elements[c.dataset.for];
        const upd = () => c.textContent = el.value.length + '/' + el.maxLength;
        el.addEventListener('input', upd); upd();
    });
    // Til tablari
    document.querySelectorAll('.push-lang a').forEach(a => a.addEventListener('click', e => {
        e.preventDefault();
        document.querySelectorAll('.push-lang a').forEach(x => x.classList.toggle('active', x === a));
        document.querySelectorAll('.push-lang-pane').forEach(p => p.hidden = p.dataset.pane !== a.dataset.lang);
        preview(a.dataset.lang);
    }));
    let pvLang = 'uz';
    function preview(l) {
        if (l) pvLang = l;
        const t = form['title_' + pvLang].value.trim() || form.title_uz.value.trim(), b = form['body_' + pvLang].value.trim() || form.body_uz.value.trim();
        pvTitle.textContent = t || 'Sarlavha';
        pvBody.textContent = b ? (b.length > 110 ? b.slice(0, 110) + '…' : b) : 'Matn';
        pvTitle.classList.toggle('clip', t.length > 40);
    }
    const now = new Date();
    pvClock.textContent = now.toTimeString().slice(0, 5);
    const wd = ['Yakshanba', 'Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba'];
    const mo = ['yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun', 'iyul', 'avgust', 'sentabr', 'oktabr', 'noyabr', 'dekabr'];
    pvDate.textContent = wd[now.getDay()] + ', ' + now.getDate() + '-' + mo[now.getMonth()];
    function sendAt() {
        let d = form.when.value === 'schedule' && form.scheduled_at.value ? new Date(form.scheduled_at.value) : new Date();
        const h = d.getHours();
        let shifted = false;
        if (h >= 22) { d.setDate(d.getDate() + 1); d.setHours(8, 0, 0, 0); shifted = true; }
        else if (h < 8) { d.setHours(8, 0, 0, 0); shifted = true; }
        return { d, shifted };
    }
    function quiet() { quietNote.classList.toggle('active', sendAt().shifted); }
    toConfirm.addEventListener('click', () => {
        if (!stats) return;
        const { d, shifted } = sendAt();
        const who = { client: 'mijozga', driver: 'haydovchiga', all: 'foydalanuvchiga' }[form.role.value];
        pcTitle.textContent = fmt(stats.total) + ' ta ' + who + ' yuborilsinmi?';
        pcTotal.textContent = fmt(stats.total);
        pcLang.textContent = 'UZ ' + fmt(stats.by_lang.uz) + ' · RU ' + fmt(stats.by_lang.ru);
        pcWhen.textContent = (form.when.value === 'now' && !shifted ? 'Hozir' : d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }));
        pcLimit.hidden = stats.sent_today < 1;
        pcLimitT.textContent = 'Bu auditoriyaga bugun ' + stats.sent_today + ' ta xabar yuborilgan';
        pcTested.checked = false; pcSend.disabled = true;
        modalConfirm.classList.add('active');
    });
    pcTested.addEventListener('change', () => pcSend.disabled = !pcTested.checked);
    preview(); quiet(); count();
})();
</script>
<?php endif; ?>
<?php include 'includes/footer.php'; ?>
