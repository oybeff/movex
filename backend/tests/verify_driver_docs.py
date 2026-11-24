"""
Документы водителя (MoveX GO Driver, макет 00 R5–R9, V1–V3), 21.11.2026.

Проверяется:
- статус считается из документов: incomplete → pending → rejected/approved;
- загружать может только владелец техники; неизвестный тип — 404,
  не картинка — 400;
- фото лежит ВНЕ публичной media/ и по /static недоступно; своё фото
  водитель получает, чужое — 404;
- админские адреса без X-Admin-Secret закрыты; отказ без причины — 400,
  причина доходит до водителя; повторная загрузка снова «на проверку»;
- одобренный документ заменить нельзя (409);
- удаление аккаунта стирает фото с диска.
"""
import os
import sys
import time

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import otp_code  # noqa: E402

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BACKEND)

from sqlalchemy import text  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402
from app.services.driver_service import PRIVATE_ROOT  # noqa: E402

API = os.environ.get("API", "http://127.0.0.1:8000")
SECRET = {"X-Admin-Secret": settings.ADMIN_INTERNAL_SECRET}
ok_count = fail_count = 0
created_ids, created_phones = [], []
PNG = (b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
       b"\x00\x00\x00\rIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82")


def check(label, condition, detail=""):
    global ok_count, fail_count
    if condition:
        ok_count += 1
        print(f"  [OK]   {label}")
    else:
        fail_count += 1
        print(f"  [FAIL] {label}  {detail}")


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


def register(role):
    phone = f"9989{int(time.time() * 1000) % 100000000:08d}"[:12]
    requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": otp_code(phone)})
    r = requests.post(f"{API}/auth/register", json={"full_name": f"Sinov Hujjat {role}", "phone": phone, "role": role})
    body = r.json()
    created_ids.append(body["user_id"])
    created_phones.append(phone)
    time.sleep(0.01)
    return body["user_id"], {"Authorization": f"Bearer {body['access_token']}"}


def upload(hdr, kind, data=PNG, name="doc.png"):
    return requests.post(f"{API}/drivers/me/documents/{kind}", headers=hdr, files={"file": (name, data, "image/png")})


def main():
    owner_id, owner = register("owner")
    other_id, other = register("owner")
    client_id, client = register("client")

    r = requests.get(f"{API}/drivers/me", headers=owner)
    check("новый водитель — incomplete", r.status_code == 200 and r.json()["status"] == "incomplete", r.text)

    check("клиент загружать не может — 403", upload(client, "id_front").status_code == 403)
    check("неизвестный тип — 404", upload(owner, "selfie").status_code == 404)
    check("не картинка — 400", upload(owner, "id_front", b"%PDF", "doc.pdf").status_code == 400)

    NEW = ("id_front", "id_back", "license_front", "license_back", "tech_front", "tech_back", "car_front", "car_back", "car_left", "car_right")
    for kind in NEW[:-1]:
        upload(owner, kind)
    check("не все обязательные — всё ещё incomplete",
          requests.get(f"{API}/drivers/me", headers=owner).json()["status"] == "incomplete")
    r = upload(owner, NEW[-1])
    check("все десять загружены — pending", r.status_code == 200 and r.json()["status"] == "pending", r.text)

    name = sql("SELECT file_name FROM driver_documents WHERE user_id=:u AND kind='id_front'", u=owner_id)[0][0]
    check("файл лежит в private_media", os.path.isfile(os.path.join(PRIVATE_ROOT, name)))
    check("по /static его нет", requests.get(f"{API}/static/driver_docs/{name}").status_code == 404)
    r = requests.get(f"{API}/drivers/me/documents/id_front/file", headers=owner)
    check("своё фото водитель получает", r.status_code == 200 and r.content == PNG, r.status_code)
    r = requests.get(f"{API}/drivers/me/documents/id_front/file", headers=other)
    check("чужого фото у другого водителя нет — 404", r.status_code == 404, r.status_code)

    check("очередь без секрета закрыта", requests.get(f"{API}/drivers/internal/queue").status_code in (403, 404))
    q = requests.get(f"{API}/drivers/internal/queue", headers=SECRET).json()
    me = next((i for i in q if i["user_id"] == owner_id), None)
    check("водитель в очереди со статусом pending", me is not None and me["status"] == "pending", me)
    ids = {d["kind"]: d["id"] for d in me["documents"]}
    r = requests.get(f"{API}/drivers/internal/documents/{ids['id_front']}/file", headers=SECRET)
    check("админка получает фото", r.status_code == 200 and r.content == PNG, r.status_code)

    r = requests.post(f"{API}/drivers/internal/documents/{ids['tech_front']}/review", headers=SECRET,
                      json={"approve": False})
    check("отказ без причины — 400", r.status_code == 400, r.text)
    requests.post(f"{API}/drivers/internal/documents/{ids['tech_front']}/review", headers=SECRET,
                  json={"approve": False, "reason": "Rasm xira"})
    s = requests.get(f"{API}/drivers/me", headers=owner).json()
    tech = next(d for d in s["documents"] if d["kind"] == "tech_front")
    n = sql("SELECT title, body FROM notifications WHERE user_id=:u AND type='driver_document_rejected'", u=owner_id)
    check("водителю ушло уведомление об отказе с причиной", n and "Rasm xira" in n[0][1], n)
    check("отклонён — статус rejected, причина видна водителю",
          s["status"] == "rejected" and tech["reject_reason"] == "Rasm xira", s)
    upload(owner, "tech_front")
    s = requests.get(f"{API}/drivers/me", headers=owner).json()
    check("перезагрузил — снова pending", s["status"] == "pending", s)

    q = requests.get(f"{API}/drivers/internal/queue", headers=SECRET).json()
    ids = {d["kind"]: d["id"] for d in next(i for i in q if i["user_id"] == owner_id)["documents"]}
    for kind in NEW:
        requests.post(f"{API}/drivers/internal/documents/{ids[kind]}/review", headers=SECRET, json={"approve": True})
    check("все одобрены — approved", requests.get(f"{API}/drivers/me", headers=owner).json()["status"] == "approved")
    n = sql("SELECT count(*) FROM notifications WHERE user_id=:u AND type='driver_approved'", u=owner_id)
    check("уведомление «одобрено» — ровно одно", n[0][0] == 1, n)
    check("одобренный заменить нельзя — 409", upload(owner, "id_front").status_code == 409)
    # Старый водитель: одобрены прежние четыре документа — остаётся approved
    old_id, old = register("owner")
    for kind in ("passport", "driver_license", "tech_passport", "equipment_photo"):
        upload(old, kind)
    qq = requests.get(f"{API}/drivers/internal/queue", headers=SECRET).json()
    oids = {d["kind"]: d["id"] for d in next(i for i in qq if i["user_id"] == old_id)["documents"]}
    for k, i in oids.items():
        requests.post(f"{API}/drivers/internal/documents/{i}/review", headers=SECRET, json={"approve": True})
    check("старые четыре одобрены — approved без новых фото",
          requests.get(f"{API}/drivers/me", headers=old).json()["status"] == "approved")
    r = upload(owner, "insurance")
    check("страховка по желанию не сбивает approved", r.json()["status"] == "approved", r.text)

    files = [r[0] for r in sql("SELECT file_name FROM driver_documents WHERE user_id=:u", u=owner_id)]
    r = requests.delete(f"{API}/users/me", headers=owner)
    check("аккаунт удалён", r.status_code in (200, 204), r.text)
    check("фото документов стёрты с диска",
          not any(os.path.isfile(os.path.join(PRIVATE_ROOT, f)) for f in files), files)


def cleanup():
    db = SessionLocal()
    try:
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
