"""
Admin P5 (25.11.2026): jonli xarita GPS, ilova versiyasi, push xabarlar, admin SMS.

Tekshiriladi:
- /drivers/heartbeat - faqat haydovchi (mijoz 403); nuqta, aniqlik,
  tezlik (m/s -> km/s) yoziladi; online=false - nuqta qoladi, holat oflayn;
  nuqtasiz heartbeat - eski nuqta qoladi (admin "GPS yo'q" ko'radi);
- X-App-Version/Platform/Flavor - users ga yoziladi, noto'g'risi e'tiborsiz;
- /admin-p5/internal/* - sirsiz rad;
- sms-code: sinov rejimida kod javobda, SMS ketmaydi;
- push: auditoriya hisobi rol/til/faollik bo'yicha; bo'sh matn - 400;
  0 qabul qiluvchi - 400; hozir (jim soatdan tashqari) - darhol, har
  qabul qiluvchiga bitta bildirishnoma, rus tilidagiga ruscha matn;
  bloklangan qabul qilmaydi; qoralama - hech kimga bormaydi; bekor qilish;
  yuborilganni bekor qilib bo'lmaydi; rejalashtirilgan - run_due yuboradi
  va ikkinchi marta yubormaydi; jim soatlar 22–08 -> 08:00;
- sinov push - bitta telefonga, kampaniyasiz.
"""
import os
import sys
import time
from datetime import datetime, timedelta, timezone

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import otp_code  # noqa: E402

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND)

from sqlalchemy import text  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402
from app.services import push_campaign_service as pcs  # noqa: E402

API = os.environ.get("API", "http://127.0.0.1:8000")
SECRET = {"X-Admin-Secret": settings.ADMIN_INTERNAL_SECRET}
TK = timezone(timedelta(hours=5))
ok_count = fail_count = 0
created_ids, created_phones, campaigns, zones = [], [], [], []


def check(label, condition, detail=""):
    global ok_count, fail_count
    if condition:
        ok_count += 1
        print(f"  [OK]   {label}")
    else:
        fail_count += 1
        print(f"  [FAIL] {label}  {detail}")


def head(t):
    print(f"\n{'=' * 66}\n{t}\n{'=' * 66}")


def sql(q, **p):
    db = SessionLocal()
    try:
        r = db.execute(text(q), p)
        db.commit()
        try:
            return r.fetchall()
        except Exception:
            return None
    finally:
        db.close()


def register(role, lang="uz"):
    phone = f"9989{int(time.time() * 1000) % 100000000:08d}"[:12]
    requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": otp_code(phone)})
    r = requests.post(f"{API}/auth/register", json={"full_name": f"Sinov P5 {role}", "phone": phone, "role": role})
    body = r.json()
    created_ids.append(body["user_id"])
    created_phones.append(phone)
    sql("UPDATE users SET language=:l WHERE id=:u", l=lang, u=body["user_id"])
    time.sleep(0.01)
    return body["user_id"], {"Authorization": f"Bearer {body['access_token']}"}, phone


def admin_id():
    return sql("SELECT id FROM users WHERE role='admin' ORDER BY id LIMIT 1")[0][0]


def post(path, body, headers=SECRET):
    return requests.post(f"{API}{path}", headers=headers, json=body)


def main():
    adm = admin_id()
    did, driver, _ = register("owner")
    cid, client, cphone = register("client")
    cid_ru, client_ru, _ = register("client", "ru")
    cid_bl, client_bl, _ = register("client")

    head("1. Jonli xarita: /drivers/heartbeat")
    r = requests.post(f"{API}/drivers/heartbeat", headers=client, json={"online": True, "latitude": 41.3, "longitude": 69.2})
    check("mijoz - 403", r.status_code == 403, r.status_code)
    r = requests.post(f"{API}/drivers/heartbeat", headers=driver, json={
        "online": True, "latitude": 41.311, "longitude": 69.279, "accuracy": 12.5, "speed": 10, "heading": 90})
    check("haydovchi - 200", r.status_code == 200, r.text[:200])
    row = sql("SELECT online, latitude::float, longitude::float, accuracy_m::float, speed_kmh::float, location_at IS NOT NULL "
              "FROM driver_locations WHERE user_id=:u", u=did)
    check("nuqta yozildi", row and row[0][0] is True and abs(row[0][1] - 41.311) < 1e-6, row)
    check("tezlik m/s -> km/s (10 -> 36)", row and row[0][4] == 36.0, row)
    sql("UPDATE driver_locations SET location_at = NOW() - INTERVAL '10 minutes' WHERE user_id=:u", u=did)
    requests.post(f"{API}/drivers/heartbeat", headers=driver, json={"online": True})
    row = sql("SELECT latitude::float, EXTRACT(EPOCH FROM NOW()-location_at)::int, EXTRACT(EPOCH FROM NOW()-updated_at)::int "
              "FROM driver_locations WHERE user_id=:u", u=did)[0]
    check("nuqtasiz heartbeat - eski nuqta qoladi, GPS yo'q bilinadi", row[0] == 41.311 and row[1] > 500 and row[2] < 30, row)
    requests.post(f"{API}/drivers/heartbeat", headers=driver, json={"online": False})
    check("online=false - oflayn", sql("SELECT online FROM driver_locations WHERE user_id=:u", u=did)[0][0] is False)
    r = requests.post(f"{API}/drivers/heartbeat", headers=driver, json={"online": True, "latitude": 95, "longitude": 69})
    check("noto'g'ri koordinata - 422", r.status_code == 422, r.status_code)

    head("2. Ilova versiyasi (X-App-*)")
    h = dict(client, **{"X-App-Version": "1.0.12", "X-App-Platform": "android", "X-App-Flavor": "client"})
    requests.get(f"{API}/users/me", headers=h)
    row = sql("SELECT app_version, app_platform, app_flavor, last_seen_at IS NOT NULL FROM users WHERE id=:u", u=cid)[0]
    check("versiya, platforma, ilova va faollik yozildi", tuple(row) == ("1.0.12", "android", "client", True), row)
    requests.get(f"{API}/users/me", headers=dict(client, **{"X-App-Version": "<script>", "X-App-Platform": "nokia"}))
    row = sql("SELECT app_version, app_platform FROM users WHERE id=:u", u=cid)[0]
    check("noto'g'ri sarlavha e'tiborsiz", tuple(row) == ("1.0.12", "android"), row)

    head("3. Ichki manzillar va SMS kod")
    r = post("/admin-p5/internal/sms-code", {"phone": "998900000777", "code": "123456"}, headers={})
    check("sirsiz - rad", r.status_code in (401, 403, 404), r.status_code)
    r = post("/admin-p5/internal/push/audience", {"audience": {}}, headers={})
    check("push sirsiz - rad", r.status_code in (401, 403, 404), r.status_code)
    if settings.OTP_TEST_MODE and settings.APP_ENV != "production":
        r = post("/admin-p5/internal/sms-code", {"phone": "998900000777", "code": "123456"})
        check("sinov rejimi: kod javobda, SMS ketmadi", r.json() == {"sent": False, "test_code": "123456"}, r.text)
    r = post("/admin-p5/internal/sms-code", {"phone": "99890", "code": "12"})
    check("noto'g'ri raqam/kod - 422", r.status_code == 422, r.status_code)

    head("4. Push: auditoriya")
    # Faqat shu testning odamlari: o'chirilgan (narxga ta'sir qilmaydigan)
    # sinov hududi okeanda, mijozlarning qidiruv nuqtasi - uning ichida.
    zid = sql("INSERT INTO price_zones (name, polygon, surcharge_percent, is_enabled, sort_order) "
              "VALUES ('P5 sinov', CAST(:p AS json), 0, false, 999) RETURNING id",
              p='[[1.0, 1.0], [1.0, 1.2], [1.2, 1.2], [1.2, 1.0]]')[0][0]
    zones.append(zid)
    sql("UPDATE users SET last_seen_at = NOW(), search_latitude = 1.1, search_longitude = 1.1 WHERE id = ANY(:ids)",
        ids=[cid, cid_ru, cid_bl])
    sql("UPDATE users SET is_blocked = true WHERE id=:u", u=cid_bl)
    aud = {"role": "client", "langs": ["uz", "ru"], "active_days": 1, "zone_id": zid}
    r = post("/admin-p5/internal/push/audience", {"audience": aud})
    st = r.json()
    check("faol mijozlar: 2 (bloklangan kirmaydi)", st.get("total") == 2, st)
    check("til bo'yicha: uz 1, ru 1", st.get("by_lang") == {"uz": 1, "ru": 1}, st.get("by_lang"))
    st = post("/admin-p5/internal/push/audience", {"audience": dict(aud, langs=["ru"])}).json()
    check("faqat rus tili - 1", st.get("total") == 1, st)
    st = post("/admin-p5/internal/push/audience", {"audience": dict(aud, role="driver")}).json()
    check("hududda haydovchi yo'q - 0", st.get("total") == 0, st)
    st = post("/admin-p5/internal/push/audience", {"audience": dict(aud, active_days=None, zone_id=None)}).json()
    check("hududsiz - ko'proq (umumiy baza)", st.get("total", 0) >= 2, st)
    r = post("/admin-p5/internal/push/audience", {"audience": dict(aud, langs=[])})
    check("til tanlanmagan - 400", r.status_code == 400, r.status_code)

    head("5. Push: yaratish va yuborish")
    base = {"admin_id": adm, "title_uz": "Sinov P5", "body_uz": "Matn uz", "title_ru": "Тест P5", "body_ru": "Текст ru",
            "audience": aud}
    r = post("/admin-p5/internal/push/campaigns", dict(base, title_uz=""))
    check("bo'sh sarlavha - 400", r.status_code == 400, r.status_code)
    r = post("/admin-p5/internal/push/campaigns", dict(base, title_ru="Faqat sarlavha", body_ru=None))
    check("ruscha yarim to'ldirilgan - 400", r.status_code == 400, r.status_code)
    r = post("/admin-p5/internal/push/campaigns", dict(base, mode="now", audience=dict(aud, role="driver")))
    check("0 qabul qiluvchi - 400", r.status_code == 400, r.text[:150])

    r = post("/admin-p5/internal/push/campaigns", dict(base, mode="draft"))
    draft = r.json()
    campaigns.append(draft["id"])
    check("qoralama saqlandi, hech kimga bormadi", draft["status"] == "draft"
          and sql("SELECT COUNT(*) FROM notifications WHERE campaign_id=:c", c=draft["id"])[0][0] == 0, draft)
    r = post(f"/admin-p5/internal/push/{draft['id']}/cancel", {"admin_id": adm})
    check("qoralama bekor qilindi", r.json().get("status") == "cancelled", r.text[:150])

    now_local = datetime.now(TK)
    quiet = now_local.hour >= 22 or now_local.hour < 8
    r = post("/admin-p5/internal/push/campaigns", dict(base, mode="now"))
    c = r.json()
    campaigns.append(c["id"])
    if quiet:
        check("jim soat: hozir -> 08:00 ga surildi", c["status"] == "scheduled"
              and datetime.fromisoformat(c["scheduled_at"]).astimezone(TK).hour == 8, c)
        sql("UPDATE push_campaigns SET scheduled_at = NOW() - INTERVAL '1 minute' WHERE id=:c", c=c["id"])
        db = SessionLocal()
        try:
            pcs.run_due(db)
        finally:
            db.close()
        c = {"id": c["id"], "status": sql("SELECT status FROM push_campaigns WHERE id=:c", c=c["id"])[0][0],
             "recipients": sql("SELECT recipients FROM push_campaigns WHERE id=:c", c=c["id"])[0][0]}
    check("yuborildi, 2 qabul qiluvchi", c["status"] == "sent" and c["recipients"] == 2, c)
    rows = dict(sql("SELECT user_id, title FROM notifications WHERE campaign_id=:c", c=c["id"]))
    check("har qabul qiluvchiga bitta", len(rows) == 2 and set(rows) == {cid, cid_ru}, rows)
    check("rus tilidagiga ruscha, o'zbekka o'zbekcha", rows.get(cid_ru) == "Тест P5" and rows.get(cid) == "Sinov P5", rows)
    check("bloklanganga bormadi", cid_bl not in rows)
    n = requests.get(f"{API}/notifications/", headers=client).json()
    items = n if isinstance(n, list) else n.get("items", n.get("notifications", []))
    check("ilovada ko'rinadi (type=system)", any(i.get("title") == "Sinov P5" and i.get("type") == "system" for i in items),
          str(items)[:200])
    r = post(f"/admin-p5/internal/push/{c['id']}/cancel", {"admin_id": adm})
    check("yuborilganni bekor qilib bo'lmaydi - 409", r.status_code == 409, r.status_code)

    head("6. Rejalashtirilgan va jim soatlar")
    when = (datetime.now(TK) + timedelta(days=1)).replace(hour=23, minute=30, second=0, microsecond=0)
    r = post("/admin-p5/internal/push/campaigns", dict(base, mode="schedule", scheduled_at=when.strftime("%Y-%m-%dT%H:%M")))
    s = r.json()
    campaigns.append(s["id"])
    sched = datetime.fromisoformat(s["scheduled_at"]).astimezone(TK)
    check("23:30 -> ertasi 08:00", s["status"] == "scheduled" and sched.hour == 8 and sched.date() == (when + timedelta(days=1)).date(), s)
    r = post("/admin-p5/internal/push/campaigns", dict(base, mode="schedule", scheduled_at="2020-01-01T10:00"))
    check("o'tgan vaqt - 400", r.status_code == 400, r.status_code)
    sql("UPDATE push_campaigns SET scheduled_at = NOW() - INTERVAL '1 minute' WHERE id=:c", c=s["id"])
    db = SessionLocal()
    try:
        first = pcs.run_due(db)
        second = pcs.run_due(db)
    finally:
        db.close()
    sent = sql("SELECT status, recipients FROM push_campaigns WHERE id=:c", c=s["id"])[0]
    check("vaqti keldi - fon yubordi", sent[0] == "sent" and sent[1] == 2 and first >= 1, (sent, first))
    check("ikkinchi aylanish qayta yubormaydi", second == 0
          and sql("SELECT COUNT(*) FROM notifications WHERE campaign_id=:c", c=s["id"])[0][0] == 2, second)
    check("jim soat funksiyasi: 07:59 -> 08:00, 12:00 o'zgarmaydi",
          pcs.shift_quiet(datetime(2026, 1, 1, 7, 59, tzinfo=TK)).astimezone(TK).hour == 8
          and pcs.shift_quiet(datetime(2026, 1, 1, 12, 0, tzinfo=TK)).astimezone(TK).hour == 12)

    head("7. Sinov push va jurnal")
    before = sql("SELECT COUNT(*) FROM notifications WHERE user_id=:u", u=cid)[0][0]
    r = post("/admin-p5/internal/push/test", dict(base, phone=cphone[3:]))
    check("sinov: 9 xonali raqam ham topiladi", r.status_code == 200 and r.json().get("user_id") == cid, r.text[:150])
    after = sql("SELECT COUNT(*), bool_and(campaign_id IS NULL) FROM notifications WHERE user_id=:u AND title LIKE '[TEST]%'", u=cid)[0]
    check("[TEST] bildirishnoma, kampaniyasiz", after[0] == 1 and after[1] is True
          and sql("SELECT COUNT(*) FROM notifications WHERE user_id=:u", u=cid)[0][0] == before + 1, after)
    r = post("/admin-p5/internal/push/test", dict(base, phone="998000000001"))
    check("noma'lum raqam - 404", r.status_code == 404, r.status_code)
    logs = sql("SELECT action FROM admin_actions WHERE entity='push' AND entity_id = ANY(:ids)", ids=campaigns)
    acts = {x[0] for x in logs}
    check("jurnal: qoralama, rejalashtirish, bekor, yuborildi", {"push_draft", "push_scheduled", "push_cancelled", "push_sent"} <= acts, acts)


def cleanup():
    db = SessionLocal()
    try:
        db.execute(text("DELETE FROM price_zones WHERE id = ANY(:z)"), {"z": zones})
        db.execute(text("DELETE FROM notifications WHERE campaign_id = ANY(:c) OR user_id = ANY(:ids)"),
                   {"c": campaigns, "ids": created_ids})
        db.execute(text("DELETE FROM admin_actions WHERE entity='push' AND (entity_id = ANY(:c) OR entity_id = 0)"),
                   {"c": campaigns})
        db.execute(text("DELETE FROM push_campaigns WHERE id = ANY(:c)"), {"c": campaigns})
        db.execute(text("DELETE FROM users WHERE id = ANY(:ids)"), {"ids": created_ids})
        db.execute(text("DELETE FROM otp_verifications WHERE phone = ANY(:ps)"), {"ps": created_phones})
        db.commit()
    finally:
        db.close()


if __name__ == "__main__":
    try:
        main()
    finally:
        cleanup()
    print(f"\nITOG: {ok_count} o'tdi, {fail_count} yiqildi")
    sys.exit(1 if fail_count else 0)
