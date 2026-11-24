<?php
/**
 * Hujjatlar tekshiruvi (Figma «Admin panel» 05):
 *   V1 · navbat — eng eski ariza tepada, SLA taymeri (2 soat), qulflangan
 *        (boshqa admin ochgan) va to'liq bo'lmagan arizalar belgisi;
 *   V2 · ko'rib chiqish (?user=ID) — hujjatlar ro'yxati, ko'ruvchi (zoom,
 *        burish), tekshiruv ro'yxati, prava/texpasport muddati;
 *   V3 · rad etish — bir nechta sabab, haydovchiga ko'rinadigan matn;
 *   V4 · qulf — ikki admin bitta haydovchini bir vaqtda tekshirmaydi,
 *        10 daqiqa harakatsizlikdan so'ng qulf ochiladi (doc_review_locks);
 *   V6 · navbat bo'sh — bugungi natija.
 *
 * Rasmlar ochiq /static da EMAS (pasport ma'lumotlari): backend ichki
 * manzilidan X-Admin-Secret bilan olinadi (?file=ID). Holatni backend
 * o'zgartiradi (driver_service.review) — panel bazaga faqat qulfni yozadi.
 *
 * Pasport raqami (V5 «takroriy hujjat») bizda saqlanmaydi — faqat foto,
 * shuning uchun takror tekshiruvi telefon va davlat raqami bo'yicha.
 */
require_once 'config.php';
requireAdmin();
requirePagePerm('docs');
requireCsrfToken();
// Audit (S9): har bir o'zgartiruvchi so'rov jurnalga — maydonlar bilan.
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $auditFields = array_diff_key($_POST, ['csrf_token' => 1, 'password' => 1, 'new_password' => 1]);
    array_walk_recursive($auditFields, function (&$v) { $v = mb_substr((string) $v, 0, 200); });
    auditLog('doc_review', 'document', (int) ($_POST['doc_id'] ?? 0) ?: null, $auditFields);
}

require_once __DIR__ . '/includes/user_lib.php';

$db = getDbConnection();
$adminId = (int) ($_SESSION['admin_user_id'] ?? 0);

// Rasmni proksi qilish: <img src="drivers.php?file=12">
if (isset($_GET['file'])) {
    $res = internalApiGet('/drivers/internal/documents/' . (int) $_GET['file'] . '/file', true);
    if (!$res['ok']) {
        http_response_code(404);
        exit;
    }
    header('Content-Type: ' . ($res['type'] ?: 'image/jpeg'));
    header('Cache-Control: private, no-store');
    echo $res['data'];
    exit;
}

const KIND_NAMES = [
    'id_front' => 'ID karta — old', 'id_back' => 'ID karta — orqa',
    'license_front' => 'Prava — old', 'license_back' => 'Prava — orqa',
    'tech_front' => 'Texpasport — old', 'tech_back' => 'Texpasport — orqa',
    'car_front' => 'Mashina — old', 'car_back' => 'Mashina — orqa', 'car_left' => 'Mashina — chap', 'car_right' => "Mashina — o'ng",
    'passport' => 'Pasport (eski)', 'driver_license' => 'Prava (eski)', 'tech_passport' => 'Texpasport (eski)',
    'equipment_photo' => 'Texnika surati (eski)', 'insurance' => "Sug'urta polisi",
];
const REQUIRED_KINDS = ['id_front', 'id_back', 'license_front', 'license_back', 'tech_front', 'tech_back',
                        'car_front', 'car_back', 'car_left', 'car_right'];
const EXPIRY_KINDS = ['license_front', 'tech_front', 'driver_license', 'tech_passport'];
const REJECT_REASONS = [
    'blurry' => "Rasm xira — o'qib bo'lmaydi",
    'cropped' => "Hujjat to'liq ko'rinmaydi (cheti kesilgan)",
    'wrong' => 'Boshqa hujjat yuklangan',
    'expired' => "Hujjat muddati o'tgan",
    'mismatch' => "Ma'lumot mos emas (ism yoki raqam)",
    'plate' => "Davlat raqami ko'rinmaydi",
    'glare' => 'Yaltirash / soya ma\'lumotni yopgan',
];
const LOCK_MINUTES = 10;
const SLA_MINUTES = 120;

/** Qulf: o'zimiz olsak — null, boshqa admin ushlab turgan bo'lsa — uning ismi. */
function takeLock(PDO $db, int $userId, int $adminId): ?array
{
    $st = $db->prepare("INSERT INTO doc_review_locks (user_id, admin_id, locked_until)
                        VALUES (?, ?, NOW() + INTERVAL '" . LOCK_MINUTES . " minutes')
                        ON CONFLICT (user_id) DO UPDATE SET admin_id = EXCLUDED.admin_id, locked_until = EXCLUDED.locked_until
                         WHERE doc_review_locks.locked_until < NOW() OR doc_review_locks.admin_id = EXCLUDED.admin_id
                        RETURNING admin_id");
    $st->execute([$userId, $adminId]);
    if ($st->fetch()) {
        return null;
    }
    $who = $db->prepare('SELECT u.full_name, l.locked_until FROM doc_review_locks l JOIN users u ON u.id = l.admin_id WHERE l.user_id = ?');
    $who->execute([$userId]);
    return $who->fetch() ?: ['full_name' => 'Boshqa admin', 'locked_until' => null];
}

$userId = (int) ($_GET['user'] ?? 0);
$flash = $_SESSION['doc_flash'] ?? null;
unset($_SESSION['doc_flash']);

// ----------------------------------------------------------------- POST (V2/V3)
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $userId) {
    $lockedBy = takeLock($db, $userId, $adminId);
    if ($lockedBy) {
        $_SESSION['doc_flash'] = ['error', $lockedBy['full_name'] . " hozir ko'rib chiqmoqda — qaror qabul qilinmadi"];
    } else {
        $docId = (int) ($_POST['doc_id'] ?? 0);
        $approve = ($_POST['action'] ?? '') === 'approve';
        $reasons = array_values(array_intersect_key(REJECT_REASONS, array_flip((array) ($_POST['reasons'] ?? []))));
        $extra = trim((string) ($_POST['reason'] ?? ''));
        $reasonText = trim(implode('. ', $reasons) . ($extra !== '' ? ($reasons ? '. ' : '') . $extra : ''));
        $exp = trim((string) ($_POST['expires_on'] ?? ''));
        if (!$approve && $reasonText === '') {
            $_SESSION['doc_flash'] = ['error', "Rad etish sababini tanlang yoki yozing — haydovchi uni ilovada ko'radi"];
        } else {
            $res = internalApiPost('/drivers/internal/documents/' . $docId . '/review', [
                'approve' => $approve,
                'reason' => $approve ? null : $reasonText,
                'expires_on' => $approve && $exp !== '' ? $exp : null,
                'admin_id' => $adminId,
            ]);
            $_SESSION['doc_flash'] = $res['ok']
                ? ['success', $approve ? 'Hujjat tasdiqlandi' : 'Hujjat rad etildi — haydovchiga sabab bilan xabar ketdi']
                : ['error', 'Xato: ' . $res['error']];
        }
    }
    $next = (int) ($_POST['next_doc'] ?? 0);
    header('Location: drivers.php?user=' . $userId . ($next ? '&doc=' . $next : ''));
    exit;
}

// ----------------------------------------------------------------- V2 · ko'rib chiqish
if ($userId) {
    $u = $db->prepare("SELECT id, full_name, phone, created_at, is_blocked FROM users WHERE id = ?");
    $u->execute([$userId]);
    $u = $u->fetch();
    if (!$u) {
        header('Location: drivers.php');
        exit;
    }
    $lockedBy = takeLock($db, $userId, $adminId);
    $docs = $db->prepare('SELECT d.*, a.full_name AS reviewer FROM driver_documents d LEFT JOIN users a ON a.id = d.reviewed_by
                          WHERE d.user_id = ? ORDER BY d.id');
    $docs->execute([$userId]);
    $docs = $docs->fetchAll();
    $byKind = [];
    foreach ($docs as $d) {
        $byKind[$d['kind']] = $d;
    }
    // Yangi ro'yxatgacha (24.11.2026) eski 4 ta hujjat bilan tasdiqlanganlar
    // qayta topshirmaydi — ularga «to'liq emas» deyilmaydi.
    $legacyOk = true;
    foreach (['passport', 'driver_license', 'tech_passport', 'equipment_photo'] as $lk) {
        if (($byKind[$lk]['status'] ?? '') !== 'approved') {
            $legacyOk = false;
        }
    }
    $order = $legacyOk ? array_keys($byKind) : array_values(array_unique(array_merge(REQUIRED_KINDS, array_keys($byKind))));
    $current = null;
    $docParam = (int) ($_GET['doc'] ?? 0);
    foreach ($docs as $d) {
        if ($docParam ? (int) $d['id'] === $docParam : $d['status'] === 'pending') {
            $current = $d;
            break;
        }
    }
    if (!$current && $docs) {
        $current = $docs[0];
    }
    // Keyingi tekshiriladigan hujjat (V2 «Tasdiqlash va keyingisi»)
    $nextPending = 0;
    if ($current) {
        foreach ($docs as $d) {
            if ($d['status'] === 'pending' && (int) $d['id'] !== (int) $current['id']) {
                $nextPending = (int) $d['id'];
                break;
            }
        }
    }
    $missing = $legacyOk ? [] : array_values(array_diff(REQUIRED_KINDS, array_keys($byKind)));
    // Takroriy belgilar: shu davlat raqami boshqa haydovchida; bloklangan akkauntda
    $dups = $db->prepare("SELECT DISTINCT u2.id, u2.full_name, u2.is_blocked, x.plate FROM (
                              SELECT plate FROM delivery_driver_profiles WHERE user_id = :u AND plate IS NOT NULL AND plate <> ''
                              UNION SELECT plate_number FROM equipment WHERE owner_id = :u AND plate_number IS NOT NULL AND plate_number <> '' AND deleted_at IS NULL
                          ) x
                          JOIN (SELECT user_id AS uid, plate FROM delivery_driver_profiles
                                UNION SELECT owner_id, plate_number FROM equipment WHERE deleted_at IS NULL) y
                            ON upper(replace(y.plate, ' ', '')) = upper(replace(x.plate, ' ', '')) AND y.uid <> :u
                          JOIN users u2 ON u2.id = y.uid");
    $dups->execute(['u' => $userId]);
    $dups = $dups->fetchAll();
    $truck = $db->prepare('SELECT p.plate, v.name FROM delivery_driver_profiles p LEFT JOIN delivery_vehicles v ON v.code = p.vehicle_code WHERE p.user_id = ?');
    $truck->execute([$userId]);
    $truck = $truck->fetch();

    $pageTitle = 'Hujjat tekshiruvi — ' . $u['full_name'];
    $currentPage = 'drivers';
    include 'includes/header.php';
    ?>
<div class="content">
    <?php if ($flash): ?><div class="alert alert-<?= $flash[0] === 'success' ? 'success' : 'error' ?>"><?= htmlspecialchars($flash[1]) ?></div><?php endif; ?>

    <div class="od-head">
        <a class="icon-btn back" href="drivers.php" aria-label="Navbatga" style="border:1px solid var(--border)"><i data-lucide="chevron-left"></i></a>
        <div>
            <h2><?= htmlspecialchars($u['full_name']) ?> <span class="badge badge-secondary no-dot">Haydovchi #<?= $userId ?></span></h2>
            <div class="sub num"><?= htmlspecialchars(fmtPhone($u['phone'])) ?> · ro'yxatdan <?= date('d.m.Y', strtotime($u['created_at'])) ?>
                <?= $truck ? ' · ' . htmlspecialchars(($truck['name'] ?? '') . ' ' . ($truck['plate'] ?? '')) : '' ?></div>
        </div>
        <div class="page-actions"><a class="btn btn-secondary btn-sm" href="user.php?id=<?= $userId ?>"><i data-lucide="user"></i> Profil</a></div>
    </div>

    <?php if ($lockedBy): ?>
        <div class="banner"><i data-lucide="lock"></i><div><b><?= htmlspecialchars($lockedBy['full_name']) ?> hozir ko'rib chiqmoqda</b>
            <div class="sub">Ikki admin bir vaqtda qaror qila olmaydi. Qulf <?= $lockedBy['locked_until'] ? date('H:i', strtotime($lockedBy['locked_until'])) . ' da' : '' ?> ochiladi (10 daqiqa harakatsizlikdan so'ng). Hozircha faqat ko'rish mumkin.</div></div>
            <a class="btn btn-secondary btn-sm" href="drivers.php">Navbatga</a></div>
    <?php endif; ?>
    <?php if ($dups): ?>
        <div class="banner danger"><i data-lucide="copy"></i><div><b>Takroriy davlat raqami</b>
            <div class="sub"><?php foreach ($dups as $d): ?><a href="user.php?id=<?= (int) $d['id'] ?>"><?= htmlspecialchars($d['full_name']) ?></a> (<?= htmlspecialchars($d['plate']) ?><?= $d['is_blocked'] ? ', BLOKLANGAN' : '' ?>) <?php endforeach; ?>
                — tasdiqlashdan oldin tekshiring.</div></div></div>
    <?php endif; ?>
    <?php if ($missing): ?>
        <div class="banner"><i data-lucide="file-warning"></i><div><b>Ariza to'liq emas — <?= count($missing) ?> ta hujjat yo'q</b>
            <div class="sub"><?= htmlspecialchars(implode(', ', array_map(function ($k) { return KIND_NAMES[$k] ?? $k; }, $missing))) ?></div></div></div>
    <?php endif; ?>

    <div class="doc-review">
        <div class="card doc-list">
            <?php foreach ($order as $k):
                $d = $byKind[$k] ?? null;
                $cls = !$d ? 'missing' : $d['status'];
                $active = $d && $current && (int) $d['id'] === (int) $current['id'];
            ?>
                <a class="<?= $cls ?> <?= $active ? 'active' : '' ?>" href="<?= $d ? 'drivers.php?user=' . $userId . '&doc=' . (int) $d['id'] : '#' ?>">
                    <span class="dot"></span><span><?= htmlspecialchars(KIND_NAMES[$k] ?? $k) ?>
                    <small><?= !$d ? 'yuklanmagan' : (['pending' => 'tekshiruvda', 'approved' => 'tasdiqlangan', 'rejected' => 'rad etilgan'][$d['status']] ?? $d['status'])
                        . ($d && $d['expires_on'] ? ' · ' . date('d.m.Y', strtotime($d['expires_on'])) . ' gacha' : '') ?></small></span>
                </a>
            <?php endforeach; ?>
        </div>

        <div class="card doc-viewer">
            <?php if ($current): ?>
                <div class="viewer-bar">
                    <b><?= htmlspecialchars(KIND_NAMES[$current['kind']] ?? $current['kind']) ?></b>
                    <span class="text-muted" style="font-size:12px">yuklangan <?= date('d.m.Y H:i', strtotime($current['updated_at'])) ?></span>
                    <span style="margin-left:auto;display:flex;gap:4px">
                        <button class="icon-btn" type="button" data-z="-1" title="Kichraytirish"><i data-lucide="zoom-out"></i></button>
                        <button class="icon-btn" type="button" data-z="1" title="Kattalashtirish"><i data-lucide="zoom-in"></i></button>
                        <button class="icon-btn" type="button" data-r="1" title="Burish"><i data-lucide="rotate-cw"></i></button>
                        <a class="icon-btn" href="drivers.php?file=<?= (int) $current['id'] ?>" target="_blank" rel="noopener" title="Asl o'lcham"><i data-lucide="external-link"></i></a>
                    </span>
                </div>
                <div class="viewer-stage"><img id="docImg" src="drivers.php?file=<?= (int) $current['id'] ?>" alt="<?= htmlspecialchars(KIND_NAMES[$current['kind']] ?? '') ?>"></div>
            <?php else: ?>
                <div class="empty-state">Hujjat yuklanmagan</div>
            <?php endif; ?>
        </div>

        <div class="card doc-decide"><div class="card-body">
            <?php if ($current): ?>
                <?php if ($current['status'] !== 'pending'): ?>
                    <div class="alert alert-<?= $current['status'] === 'approved' ? 'success' : 'warning' ?>" style="margin-bottom:12px">
                        <div><b><?= $current['status'] === 'approved' ? 'Tasdiqlangan' : 'Rad etilgan' ?></b>
                            <?= $current['reviewer'] ? ' · ' . htmlspecialchars($current['reviewer']) : '' ?>
                            <?= $current['reviewed_at'] ? ' · ' . date('d.m.Y H:i', strtotime($current['reviewed_at'])) : '' ?>
                            <?php if ($current['reject_reason']): ?><div class="mt-1">«<?= htmlspecialchars($current['reject_reason']) ?>»</div><?php endif; ?>
                            <div class="mt-1 text-muted" style="font-size:12px">Qarorni o'zgartirish mumkin — haydovchiga yana xabar ketadi.</div></div>
                    </div>
                <?php endif; ?>
                <b>Tekshiruv ro'yxati</b>
                <ul class="checklist mt-1">
                    <li><label><input type="checkbox" class="chk"> Rasm aniq, matn o'qiladi</label></li>
                    <li><label><input type="checkbox" class="chk"> Hujjat to'liq, cheti kesilmagan</label></li>
                    <li><label><input type="checkbox" class="chk"> Ism profil bilan mos (<?= htmlspecialchars($u['full_name']) ?>)</label></li>
                    <?php if (in_array($current['kind'], ['tech_front', 'tech_back', 'car_front', 'car_back', 'tech_passport'], true)): ?>
                        <li><label><input type="checkbox" class="chk"> Davlat raqami ko'rinadi<?= $truck && $truck['plate'] ? ' (' . htmlspecialchars($truck['plate']) . ')' : '' ?></label></li>
                    <?php endif; ?>
                </ul>
                <?php if (!$lockedBy): ?>
                <form method="post" class="mt-2">
                    <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
                    <input type="hidden" name="doc_id" value="<?= (int) $current['id'] ?>">
                    <input type="hidden" name="next_doc" value="<?= $nextPending ?>">
                    <input type="hidden" name="action" value="approve">
                    <?php if (in_array($current['kind'], EXPIRY_KINDS, true)): ?>
                        <div class="form-group"><label for="exp">Amal qilish muddati (hujjatdagi sana)</label>
                            <input type="date" id="exp" name="expires_on" required min="<?= date('Y-m-d') ?>" value="<?= htmlspecialchars((string) $current['expires_on']) ?>">
                            <div class="form-hint">30 kun qolganda — sariq, o'tganda haydovchi buyurtma ololmaydi.</div></div>
                    <?php endif; ?>
                    <button class="btn btn-success btn-block" type="submit" id="btnApprove"><i data-lucide="check"></i> Tasdiqlash<?= $nextPending ? ' va keyingisi' : '' ?></button>
                </form>
                <button class="btn btn-danger btn-block mt-1" type="button" data-open="modalReject"><i data-lucide="x"></i> Rad etish</button>
                <?php endif; ?>
            <?php endif; ?>
        </div></div>
    </div>
</div>

<?php if ($current && !$lockedBy): ?>
<!-- V3 · Rad etish -->
<div class="modal" id="modalReject" role="dialog" aria-modal="true" aria-labelledby="rejTitle">
    <form class="modal-content" method="post" style="max-width:500px">
        <input type="hidden" name="csrf_token" value="<?= htmlspecialchars(generateCsrfToken()) ?>">
        <input type="hidden" name="doc_id" value="<?= (int) $current['id'] ?>">
        <input type="hidden" name="next_doc" value="<?= $nextPending ?>">
        <input type="hidden" name="action" value="reject">
        <div class="modal-header"><div><div class="modal-title" id="rejTitle">Rad etish — <?= htmlspecialchars(KIND_NAMES[$current['kind']] ?? '') ?></div>
            <div class="text-muted" style="font-size:12.5px">Faqat shu hujjat qayta so'raladi. Qolganlari o'z holicha qoladi.</div></div>
            <button class="modal-close" type="button" data-close aria-label="Yopish">×</button></div>
        <div class="modal-body">
            <div class="form-section" style="margin-top:0">Sabab (bir nechtasini tanlash mumkin)</div>
            <?php foreach (REJECT_REASONS as $k => $v): ?>
                <label class="choice"><input type="checkbox" name="reasons[]" value="<?= $k ?>" class="rr" data-t="<?= htmlspecialchars($v) ?>"><span><b><?= htmlspecialchars($v) ?></b></span></label>
            <?php endforeach; ?>
            <div class="form-group mt-1"><label for="rrText">Qo'shimcha izoh</label>
                <textarea id="rrText" name="reason" rows="2" maxlength="300" placeholder="Masalan: orqa tomonini yorug'da qayta suratga oling"></textarea></div>
            <div class="form-section">Haydovchi ilovada ko'radi</div>
            <div class="note" id="rrPreview" style="background:var(--red-50)">—</div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-secondary" type="button" data-close>Bekor</button>
            <button class="btn btn-danger" type="submit">Rad etish</button>
        </div>
    </form>
</div>
<?php endif; ?>

<style>
    .doc-review { display: grid; grid-template-columns: 240px minmax(0, 1fr) 300px; gap: 16px; align-items: start; }
    .doc-list { padding: 8px; }
    .doc-list a { display: flex; gap: 10px; align-items: flex-start; padding: 8px 10px; border-radius: 8px; color: var(--navy-900); font-size: 13px; }
    .doc-list a small { display: block; color: var(--muted); font-size: 11.5px; }
    .doc-list a.active { background: var(--blue-50); }
    .doc-list .dot { width: 9px; height: 9px; border-radius: 50%; margin-top: 5px; flex-shrink: 0; background: var(--gray-300); }
    .doc-list .pending .dot { background: var(--yellow-500); }
    .doc-list .approved .dot { background: var(--green-500); }
    .doc-list .rejected .dot { background: var(--red-500); }
    .doc-list .missing { color: var(--gray-400); pointer-events: none; }
    .viewer-bar { display: flex; align-items: center; gap: 10px; padding: 10px 14px; border-bottom: 1px solid var(--border); }
    .viewer-stage { height: 560px; overflow: auto; display: grid; place-items: center; background: var(--gray-100); }
    .viewer-stage img { max-width: 100%; max-height: 540px; transition: transform .15s; }
    .checklist { list-style: none; font-size: 13px; }
    .checklist li { padding: 4px 0; }
    @media (max-width: 1200px) { .doc-review { grid-template-columns: 1fr; } .viewer-stage { height: 420px; } }
</style>
<script>
(() => {
    let z = 1, r = 0;
    const img = document.getElementById('docImg');
    const apply = () => { if (img) img.style.transform = `scale(${z}) rotate(${r}deg)`; };
    document.querySelectorAll('[data-z]').forEach(b => b.addEventListener('click', () => { z = Math.min(4, Math.max(.5, z + (+b.dataset.z) * .25)); apply(); }));
    document.querySelectorAll('[data-r]').forEach(b => b.addEventListener('click', () => { r = (r + 90) % 360; apply(); }));
    document.addEventListener('keydown', e => {
        if (e.target.closest('input,textarea')) return;
        if (e.key === '+') { z = Math.min(4, z + .25); apply(); }
        if (e.key === '-') { z = Math.max(.5, z - .25); apply(); }
        if (e.key === 'r') { r = (r + 90) % 360; apply(); }
    });
    document.querySelectorAll('[data-open]').forEach(b => b.addEventListener('click', () => document.getElementById(b.dataset.open)?.classList.add('active')));
    document.querySelectorAll('.modal').forEach(m => m.addEventListener('click', e => { if (e.target === m || e.target.closest('[data-close]')) m.classList.remove('active'); }));
    const prev = document.getElementById('rrPreview'), txt = document.getElementById('rrText');
    const sync = () => {
        if (!prev) return;
        const parts = [...document.querySelectorAll('.rr:checked')].map(c => c.dataset.t);
        if (txt.value.trim()) parts.push(txt.value.trim());
        prev.textContent = parts.length ? parts.join('. ') : '—';
    };
    document.querySelectorAll('.rr').forEach(c => c.addEventListener('change', sync));
    if (txt) txt.addEventListener('input', sync);
})();
</script>
<?php
    include 'includes/footer.php';
    exit;
}

// ----------------------------------------------------------------- V1 · navbat
$tab = ($_GET['tab'] ?? 'queue') === 'all' ? 'all' : 'queue';
$rows = $db->query("
    SELECT u.id, u.full_name, u.phone, u.is_blocked,
           COUNT(d.*) AS docs,
           COUNT(*) FILTER (WHERE d.status = 'pending') AS pend,
           COUNT(*) FILTER (WHERE d.status = 'rejected') AS rej,
           COUNT(*) FILTER (WHERE d.status = 'approved') AS appr,
           MIN(d.updated_at) FILTER (WHERE d.status = 'pending') AS waiting_since,
           MAX(d.updated_at) AS last_upload,
           l.locked_until, la.full_name AS locked_by, l.admin_id AS locked_admin
      FROM driver_documents d
      JOIN users u ON u.id = d.user_id
      LEFT JOIN doc_review_locks l ON l.user_id = u.id AND l.locked_until > NOW()
      LEFT JOIN users la ON la.id = l.admin_id
     GROUP BY u.id, l.locked_until, la.full_name, l.admin_id
     " . ($tab === 'queue' ? "HAVING COUNT(*) FILTER (WHERE d.status = 'pending') > 0" : '') . "
     ORDER BY MIN(d.updated_at) FILTER (WHERE d.status = 'pending') ASC NULLS LAST, MAX(d.updated_at) DESC
     LIMIT 200")->fetchAll();
$req = count(REQUIRED_KINDS);
$today = $db->query("SELECT COUNT(*) FILTER (WHERE status = 'approved') AS a, COUNT(*) FILTER (WHERE status = 'rejected') AS r
                       FROM driver_documents WHERE reviewed_at >= CURRENT_DATE")->fetch();
$queueCount = (int) $db->query("SELECT COUNT(DISTINCT user_id) FROM driver_documents WHERE status = 'pending'")->fetchColumn();
$overSla = (int) $db->query("SELECT COUNT(*) FROM (SELECT user_id FROM driver_documents WHERE status = 'pending'
                              GROUP BY user_id HAVING MIN(updated_at) < NOW() - INTERVAL '" . SLA_MINUTES . " minutes') x")->fetchColumn();

$pageTitle = 'Hujjatlar tekshiruvi';
$currentPage = 'drivers';
include 'includes/header.php';
?>
<div class="content">
    <?php if ($flash): ?><div class="alert alert-<?= $flash[0] === 'success' ? 'success' : 'error' ?>"><?= htmlspecialchars($flash[1]) ?></div><?php endif; ?>
    <div class="page-head">
        <div><h2>Hujjatlar tekshiruvi</h2>
            <div class="sub">Eng eski ariza tepada · javob berish muddati (SLA) — 2 soat · <?= $req ?> ta majburiy hujjat (har biri ikki tomondan, mashina 4 tomondan)</div></div>
    </div>

    <div class="stats-grid" style="grid-template-columns:repeat(4,minmax(0,1fr))">
        <div class="stat-card"><div class="stat-value"><?= $queueCount ?></div><div class="stat-title">navbatda</div></div>
        <div class="stat-card"><div class="stat-value <?= $overSla ? 'text-danger' : '' ?>"><?= $overSla ?></div><div class="stat-title">2 soatdan ko'p kutyapti</div></div>
        <div class="stat-card"><div class="stat-value"><?= (int) $today['a'] ?></div><div class="stat-title">bugun tasdiqlandi</div></div>
        <div class="stat-card"><div class="stat-value"><?= (int) $today['r'] ?></div><div class="stat-title">bugun rad etildi</div></div>
    </div>

    <div class="tabs">
        <a href="drivers.php" class="<?= $tab === 'queue' ? 'active' : '' ?>">Navbat <span class="nav-count <?= $overSla ? 'danger' : '' ?>"><?= $queueCount ?></span></a>
        <a href="drivers.php?tab=all" class="<?= $tab === 'all' ? 'active' : '' ?>">Hamma arizalar</a>
    </div>

    <div class="card">
        <?php if (!$rows): ?>
            <!-- V6 · navbat bo'sh -->
            <div class="empty-state">
                <i data-lucide="circle-check-big"></i>
                <div><b>Navbat bo'sh</b></div>
                <div class="mt-1">Bugun <?= (int) $today['a'] ?> ta hujjat tasdiqlandi, <?= (int) $today['r'] ?> tasi rad etildi.</div>
                <a class="btn btn-secondary btn-sm mt-2" href="haydovchilar.php?tab=expiring"><i data-lucide="calendar-clock"></i> Muddati tugayotgan hujjatlar</a>
            </div>
        <?php else: ?>
            <div class="table-responsive"><table>
                <thead><tr><th>Haydovchi</th><th>Hujjatlar</th><th>Kutyapti</th><th>Holat</th><th style="width:140px"></th></tr></thead>
                <tbody>
                <?php foreach ($rows as $r):
                    $mins = $r['waiting_since'] ? (int) floor((time() - strtotime($r['waiting_since'])) / 60) : null;
                    $late = $mins !== null && $mins > SLA_MINUTES;
                    $lockedOther = $r['locked_until'] && (int) $r['locked_admin'] !== $adminId;
                    $incomplete = (int) $r['docs'] < $req && (int) $r['appr'] < 4;
                ?>
                    <tr class="<?= $late ? 'row-alert' : '' ?>" data-href="drivers.php?user=<?= (int) $r['id'] ?>">
                        <td><div class="person" style="margin:0"><div class="user-avatar"><?= htmlspecialchars(initials($r['full_name'])) ?></div>
                            <div><b><?= htmlspecialchars($r['full_name']) ?></b><small class="num" style="white-space:nowrap"><?= htmlspecialchars(fmtPhone($r['phone'])) ?></small></div></div></td>
                        <td><?= (int) $r['docs'] ?> / <?= $req ?>
                            <span class="sub"><?= (int) $r['pend'] ?> tekshiruvda · <?= (int) $r['appr'] ?> tasdiqlangan<?= (int) $r['rej'] ? ' · ' . (int) $r['rej'] . ' rad' : '' ?></span></td>
                        <td class="num <?= $late ? 'text-danger' : '' ?>"><?= $mins === null ? '—' : ($mins < 60 ? $mins . ' daq' : floor($mins / 60) . ' soat ' . ($mins % 60) . ' daq') ?>
                            <?php if ($late): ?><span class="sub text-danger">SLA o'tdi</span><?php endif; ?></td>
                        <td>
                            <?php if ($lockedOther): ?><span class="badge badge-secondary"><i data-lucide="lock" style="width:12px;height:12px"></i> <?= htmlspecialchars($r['locked_by']) ?> ko'rmoqda</span><?php endif; ?>
                            <?php if ($incomplete): ?><span class="badge badge-warning">To'liq emas</span><?php endif; ?>
                            <?php if ($r['is_blocked']): ?><span class="badge badge-danger">Bloklangan</span><?php endif; ?>
                            <?php if (!$lockedOther && !$incomplete && !$r['is_blocked']): ?><span class="badge badge-<?= (int) $r['pend'] ? 'warning' : 'success' ?>"><?= (int) $r['pend'] ? 'Tekshiruvda' : 'Ko\'rib chiqilgan' ?></span><?php endif; ?>
                        </td>
                        <td><a class="btn btn-<?= (int) $r['pend'] ? 'primary' : 'secondary' ?> btn-sm" href="drivers.php?user=<?= (int) $r['id'] ?>"><?= (int) $r['pend'] ? 'Ko\'rib chiqish' : 'Ochish' ?></a></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table></div>
        <?php endif; ?>
    </div>
</div>
<script>
document.querySelectorAll('tr[data-href]').forEach(tr => tr.addEventListener('click', e => {
    if (e.target.closest('a,button')) return;
    location.href = tr.dataset.href;
}));
</script>
<?php include 'includes/footer.php'; ?>
