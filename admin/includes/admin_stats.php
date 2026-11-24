<?php
/**
 * Menyu, qo'ng'iroqcha va dashboard'dagi "Diqqat talab qiladi" uchun
 * hisoblagichlar. Bir joyda — aks holda menyudagi raqam bilan dashboard
 * dagi raqam ajralib ketadi.
 *
 * Har bir so'rov alohida try/catch'da: bitta jadval yo'q yoki migratsiya
 * qo'llanmagan bo'lsa, butun panel yiqilmasin — faqat o'sha raqam 0.
 */

function adminCount(PDO $db, string $sql): int
{
    try {
        return (int) $db->query($sql)->fetchColumn();
    } catch (Throwable $e) {
        return 0;
    }
}

/** Menyu uchun hamma hisoblagichlar — bitta sahifa yuklanishida bir marta. */
function adminNavCounts(PDO $db): array
{
    static $cache = null;
    if ($cache !== null) {
        return $cache;
    }
    $cache = [
        // Faol buyurtmalar: texnika + yuk tashish + material yetkazish
        'orders_active' => adminCount($db, "
            SELECT (SELECT COUNT(*) FROM orders WHERE status IN ('pending','confirmed'))
                 + (SELECT COUNT(*) FROM freight_orders WHERE status NOT IN ('done','cancelled'))
                 + (SELECT COUNT(*) FROM material_orders WHERE status IN ('pending','confirmed'))"),
        // Javob kelmagan ochiq zayavkalar — egalar yetishmaydi yoki radius tor
        'requests_no_offers' => adminCount($db, "
            SELECT COUNT(*) FROM equipment_requests r
             WHERE r.status = 'open'
               AND NOT EXISTS (SELECT 1 FROM request_offers o
                                WHERE o.request_id = r.id AND o.status = 'pending')"),
        // Ijrochi olgan, muallif hali tasdiqlamagan e'lonlar
        'listings_taken' => adminCount($db, "SELECT COUNT(*) FROM listings WHERE status = 'taken'"),
        // Moderatsiyadagi tovarlar — katalogda ko'rinmaydi
        'materials_pending' => adminCount($db, "SELECT COUNT(*) FROM material_products WHERE status = 'pending'"),
        'problems_open' => adminCount($db, "SELECT COUNT(*) FROM order_problems WHERE status = 'open'"),
        // Javob kutayotgan yordam chatlari: oxirgi xabar foydalanuvchidan
        'support_waiting' => adminCount($db, "
            SELECT COUNT(*) FROM support_threads t
             WHERE t.status = 'open'
               AND (SELECT m.is_admin FROM support_messages m WHERE m.thread_id = t.id ORDER BY m.id DESC LIMIT 1) IS FALSE"),
        // Avto-belgili, hali ko'rilmagan sharhlar (reviews.php bilan bir xil qoida emas — taxminiy, tez)
        'reviews_flagged' => adminCount($db, "
            SELECT COUNT(*) FROM reviews r LEFT JOIN equipment e ON e.id = r.equipment_id
             WHERE NOT r.hidden AND r.moderated_at IS NULL
               AND (r.user_id = e.owner_id
                    OR r.comment ~* '(https?://|www\.|t\.me|telegram|instagram|@[a-z0-9_]{3,}|\+?998[ -]?[0-9]{2})')"),
        'problems_late' => adminCount($db, "SELECT COUNT(*) FROM order_problems
                                             WHERE status = 'open' AND created_at < NOW() - INTERVAL '24 hours'"),
        // Tekshirilmagan hujjatlar — haydovchi ishga chiqolmaydi
        'docs_pending' => adminCount($db, "SELECT COUNT(*) FROM driver_documents WHERE status = 'pending'"),
        'docs_late' => adminCount($db, "SELECT COUNT(*) FROM driver_documents
                                         WHERE status = 'pending' AND created_at < NOW() - INTERVAL '2 hours'"),
        // Koordinatasiz texnika — xaritada ham, qidiruvda ham yo'q
        'equipment_no_coords' => adminCount($db, "SELECT COUNT(*) FROM equipment
                                                   WHERE deleted_at IS NULL
                                                     AND (latitude IS NULL OR longitude IS NULL)"),
        'payouts_pending' => adminCount($db, "SELECT COUNT(*) FROM payout_requests WHERE status = 'pending'"),
        'payouts_late' => adminCount($db, "SELECT COUNT(*) FROM payout_requests
                                            WHERE status = 'pending' AND created_at < NOW() - INTERVAL '24 hours'"),
        // Haydovchi topilmayotgan yuk/material buyurtmalari (10 daqiqadan ko'p)
        'searching_stuck' => adminCount($db, "
            SELECT (SELECT COUNT(*) FROM freight_orders
                     WHERE status = 'searching' AND created_at < NOW() - INTERVAL '10 minutes')
                 + (SELECT COUNT(*) FROM material_orders
                     WHERE delivery_status = 'searching' AND updated_at < NOW() - INTERVAL '10 minutes')
                 + (SELECT COUNT(*) FROM equipment_requests
                     WHERE mode = 'quick' AND status = 'open' AND created_at < NOW() - INTERVAL '10 minutes')"),
    ];
    return $cache;
}

/** Qo'ng'iroqchadagi raqam: admin javob berishi kerak bo'lgan hamma narsa. */
function adminAttentionTotal(array $c): int
{
    return $c['problems_open'] + $c['docs_pending'] + $c['payouts_pending'] + $c['support_waiting']
         + $c['materials_pending'] + $c['searching_stuck'];
}
