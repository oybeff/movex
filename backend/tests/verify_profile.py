"""
Профиль клиента (макет Pr2, Pr4): фото и сохранённые адреса.

Сторожит: чужой адрес не читается и не меняется (404, как несуществующий),
тип адреса только из справочника, удаление аккаунта стирает адреса и фото.
"""
import os
import sys
import time

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import otp_code  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sqlalchemy import text  # noqa: E402

from app.db.session import SessionLocal  # noqa: E402

API = os.environ.get("API", "http://127.0.0.1:8000")
ok = fail = 0
ids, phones = [], []


def check(label, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1
        print(f"  [OK]   {label}")
    else:
        fail += 1
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


def register():
    phone = f"9989{int(time.time() * 1000) % 100000000:08d}"[:12]
    requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": otp_code(phone)})
    b = requests.post(f"{API}/auth/register",
                      json={"full_name": "Sinov Profil", "phone": phone, "role": "client"}).json()
    ids.append(b["user_id"])
    phones.append(phone)
    time.sleep(0.01)
    return b["user_id"], {"Authorization": f"Bearer {b['access_token']}"}


def main():
    uid, me = register()
    _, other = register()
    home = {"kind": "home", "title": "Uy", "address": "Chilonzor 9-kv", "latitude": 41.28, "longitude": 69.2}

    r = requests.post(f"{API}/users/me/addresses", headers=me, json=home)
    check("адрес сохранён", r.status_code == 200 and r.json()["title"] == "Uy", r.text)
    aid = r.json().get("id")
    r = requests.post(f"{API}/users/me/addresses", headers=me, json={**home, "kind": "dacha"})
    check("неизвестный тип адреса — 400", r.status_code == 400, r.text)
    check("в списке ровно мой адрес",
          [a["id"] for a in requests.get(f"{API}/users/me/addresses", headers=me).json()] == [aid])
    check("чужой список пуст", requests.get(f"{API}/users/me/addresses", headers=other).json() == [])
    r = requests.put(f"{API}/users/me/addresses/{aid}", headers=other, json=home)
    check("чужой адрес не изменить — 404", r.status_code == 404, r.text)
    r = requests.delete(f"{API}/users/me/addresses/{aid}", headers=other)
    check("чужой адрес не удалить — 404", r.status_code == 404, r.text)
    r = requests.put(f"{API}/users/me/addresses/{aid}", headers=me, json={**home, "title": "Uyim"})
    check("свой адрес изменён", r.status_code == 200 and r.json()["title"] == "Uyim", r.text)

    r = requests.post(f"{API}/users/me/avatar", headers=me,
                      files={"file": ("a.png", b"\x89PNG fake", "image/png")})
    url = r.json().get("avatar_url") if r.status_code == 200 else None
    check("фото профиля загружено", url and url.startswith("/static/avatars/"), r.text)
    r = requests.post(f"{API}/users/me/avatar", headers=me,
                      files={"file": ("a.exe", b"MZ", "application/octet-stream")})
    check("не картинка — 400", r.status_code == 400, r.text)

    r = requests.delete(f"{API}/users/me", headers=me)
    check("аккаунт удалён", r.status_code == 200, r.text)
    left = sql("SELECT count(*) FROM user_addresses WHERE user_id=:u", u=uid)[0][0]
    av = sql("SELECT avatar_url FROM users WHERE id=:u", u=uid)[0][0]
    check("удаление стёрло адреса и фото", left == 0 and av is None, (left, av))


def cleanup():
    sql("DELETE FROM users WHERE id = ANY(:i)", i=ids)
    sql("DELETE FROM otp_verifications WHERE phone = ANY(:p)", p=phones)


if __name__ == "__main__":
    try:
        main()
    finally:
        cleanup()
    print(f"\nITOG: {ok} o'tdi, {fail} yiqildi")
    sys.exit(1 if fail else 0)
