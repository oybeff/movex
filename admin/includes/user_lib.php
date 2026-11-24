<?php
/**
 * Mijozlar va haydovchilar (Figma «Admin panel» 03, 04) uchun umumiy narsalar:
 * statistika, holat yorlig'i, bloklash sabablari.
 *
 * Statistika barcha buyurtma turlaridan (orders_lib: texnika, tezkor
 * qidiruv, yuk tashish, material) — mijoz sifatida (client_id) va
 * ijrochi sifatida (perf_id) alohida.
 */
require_once __DIR__ . '/orders_lib.php';

const BLOCK_REASONS = [
    'fraud' => ["To'lov firibgarligi", 'Chargeback, soxta to\'lov'],
    'abuse' => ['Haqoratli xatti-harakat', 'Shikoyat yoki nizo asosida'],
    'cancels' => ["Ko'p bekor qilish", "30 kunda 30% dan ko'p"],
    'fake_docs' => ['Soxta hujjat', 'Haydovchi hujjatlari tekshiruvida aniqlangan'],
    'other' => ['Boshqa sabab', 'Izohda yozing'],
];
const BLOCK_DURATIONS = ['24h' => '24 soat', '7d' => '7 kun', '30d' => '30 kun', 'forever' => 'Doimiy'];

/** Mijoz sifatidagi statistika: n — jami, done, cx — bekor, paid — yakunlanganlar summasi. */
function clientStatsSql(): string
{
    return "SELECT u.client_id AS uid, COUNT(*) AS n,
                   COUNT(*) FILTER (WHERE u.st = 'done') AS done,
                   COUNT(*) FILTER (WHERE u.st = 'cancelled') AS cx,
                   COALESCE(SUM(u.amount) FILTER (WHERE u.st = 'done'), 0) AS paid
              FROM " . ordersUnionSql('u') . " GROUP BY u.client_id";
}

function perfStatsSql(): string
{
    return "SELECT u.perf_id AS uid, COUNT(*) AS n,
                   COUNT(*) FILTER (WHERE u.st = 'done') AS done,
                   COUNT(*) FILTER (WHERE u.st = 'cancelled') AS cx,
                   COALESCE(SUM(u.amount) FILTER (WHERE u.st = 'done'), 0) AS earned
              FROM " . ordersUnionSql('u') . " WHERE u.perf_id IS NOT NULL GROUP BY u.perf_id";
}

/** Bekor %: 3 tadan kam buyurtmada — null (bitta bekor = 100% noto'g'ri tuyuladi). */
function cancelPct($n, $cx): ?int
{
    $n = (int) $n;
    return $n >= 3 ? (int) round((int) $cx / $n * 100) : null;
}

function isDeletedUser(array $u): bool
{
    return strpos((string) $u['phone'], 'deleted-') === 0;
}

/** [matn, rang] — ro'yxat va profil uchun bitta qoida. */
function userStatusBadge(array $u, ?int $pct = null): array
{
    if (isDeletedUser($u)) {
        return ["O'chirilgan", 'secondary'];
    }
    if (!empty($u['is_blocked'])) {
        if (!empty($u['blocked_until'])) {
            $days = max(1, (int) ceil((strtotime($u['blocked_until']) - time()) / 86400));
            return ['Bloklangan · ' . $days . ' kun', 'danger'];
        }
        return ['Bloklangan', 'danger'];
    }
    if (!empty($u['is_frozen'])) {
        return ['Muzlatilgan', 'warning'];
    }
    if ($pct !== null && $pct > 30) {
        return ["Ko'p bekor qiladi", 'warning'];
    }
    if (!empty($u['created_at']) && strtotime($u['created_at']) > time() - 7 * 86400) {
        return ['Yangi', 'info'];
    }
    return ['Faol', 'success'];
}

function lastSeenText(?string $ts): string
{
    if (!$ts) {
        return '—';
    }
    $m = (int) floor((time() - strtotime($ts)) / 60);
    if ($m < 5) return 'Hozir';
    if ($m < 60) return $m . ' daq oldin';
    if ($m < 1440) return floor($m / 60) . ' soat oldin';
    if ($m < 2880) return 'Kecha';
    return date('d.m.Y', strtotime($ts));
}

function blockUntilText(?string $until): string
{
    return $until ? date('d.m.Y H:i', strtotime($until)) . ' gacha' : 'muddatsiz';
}

function initials(string $name): string
{
    $out = '';
    foreach (preg_split('/\s+/', trim($name)) as $w) {
        if ($w !== '' && mb_strlen($out) < 2) {
            $out .= mb_strtoupper(mb_substr($w, 0, 1));
        }
    }
    return $out !== '' ? $out : '—';
}

/** Tashqi ko'rinish uchun telefon: +998 90 123 45 67 */
function fmtPhone(?string $p): string
{
    $d = preg_replace('/\D/', '', (string) $p);
    if (strlen($d) === 12) {
        return '+' . substr($d, 0, 3) . ' ' . substr($d, 3, 2) . ' ' . substr($d, 5, 3) . ' ' . substr($d, 8, 2) . ' ' . substr($d, 10, 2);
    }
    return (string) $p;
}
