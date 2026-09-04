"""
E'lonlar taxtasi.

Zayavkadan farqi: erkin matn, savdo yo'q, egasi oladi va mijoz tasdiqlaydi.

Ikki narsa alohida tekshiriladi:

  1. Telefon raqami begonaga ko'rinmaydi. Aks holda ro'yxatdan o'tib, hamma
     e'lonni ochib chiqish orqali raqamlar bazasini yig'ib olsa bo'lardi.
  2. Bitta e'lonni ikki ega ola olmaydi. Qator bloklanadi, ya'ni "kim
     birinchi bo'lsa — o'shaniki" haqiqatan ishlaydi.

Test IDEMPOTENT.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_listings.py
"""
import os
import sys

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _auth import token  # noqa: E402

API = "http://127.0.0.1:8000"
CLIENT_PHONE = "998901110002"
OWNER_PHONE = "998901110001"
OTHER_CLIENT_PHONE = "998901179425"

ok_count = 0
fail_count = 0


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


client = token(CLIENT_PHONE)
owner = token(OWNER_PHONE)
other = token(OTHER_CLIENT_PHONE)


def create(**over):
    body = {
        "title": "Нужен эвакуатор",
        "description": "Вытащить технику с объекта",
        "budget": 700000,
        "address": "Тошкент, объект",
        "latitude": 41.3, "longitude": 69.25,
    }
    body.update(over)
    return requests.post(f"{API}/listings/", headers=client, json=body)


head("1. ОБЪЯВЛЕНИЕ СОЗДАЁТСЯ БЕЗ СПРАВОЧНИКА")

r = create()
check("объявление создано", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
listing = r.json()
lid = listing["id"]
check("статус open", listing["status"] == "open", listing["status"])
check("тип техники не обязателен", listing.get("equipment_type") is None)
check("деньги не тронуты — их тут нет", "frozen_amount" not in listing)

r = create(title="")
check("пустой заголовок отклонён", r.status_code == 422, f"{r.status_code}")

r = create(equipment_type="letayushchaya_tarelka")
check("несуществующий тип отклонён", r.status_code == 400, f"{r.status_code}")

r = create(budget=-5)
check("отрицательный бюджет отклонён", r.status_code == 422, f"{r.status_code}")

head("2. ТЕЛЕФОН НЕ ВИДЕН ПОСТОРОННИМ")

check("автор видит свой телефон", listing.get("contact_phone") is not None)

seen = requests.get(f"{API}/listings/{lid}", headers=other).json()
check("посторонний телефона не видит", seen.get("contact_phone") is None,
      str(seen.get("contact_phone")))

feed = requests.get(f"{API}/listings/feed", headers=owner).json()
mine_in_feed = [x for x in feed if x["id"] == lid]
check("объявление в ленте владельца", len(mine_in_feed) == 1)
check("в ленте телефона тоже нет",
      mine_in_feed and mine_in_feed[0].get("contact_phone") is None)

own_feed = requests.get(f"{API}/listings/feed", headers=client).json()
check("своё объявление в свою ленту не попадает",
      not any(x["id"] == lid for x in own_feed))

head("3. КТО ПЕРВЫЙ ВЗЯЛ — ТОГО И ЗАКАЗ")

r = requests.post(f"{API}/listings/{lid}/take", headers=client)
check("свой заказ взять нельзя", r.status_code in (400, 403), f"{r.status_code}")

r = requests.post(f"{API}/listings/{lid}/take", headers=owner)
check("владелец взял", r.status_code == 200, f"{r.status_code} {r.text[:120]}")
check("статус taken", r.json()["status"] == "taken")
check("видно, кто взял", r.json().get("taker_name") is not None)

r = requests.post(f"{API}/listings/{lid}/take", headers=owner)
check("повторно взять нельзя", r.status_code == 400, f"{r.status_code}")

head("4. ПОДТВЕРЖДЕНИЕ ОТКРЫВАЕТ ТЕЛЕФОН")

before = requests.get(f"{API}/listings/{lid}", headers=owner).json()
check("до подтверждения исполнитель телефона не видит",
      before.get("contact_phone") is None, str(before.get("contact_phone")))

r = requests.post(f"{API}/listings/{lid}/confirm", headers=other)
check("посторонний подтвердить не может", r.status_code == 403, f"{r.status_code}")

r = requests.post(f"{API}/listings/{lid}/confirm", headers=client)
check("клиент подтвердил", r.status_code == 200, f"{r.status_code}")
check("статус confirmed", r.json()["status"] == "confirmed")

after = requests.get(f"{API}/listings/{lid}", headers=owner).json()
check("после подтверждения телефон открыт",
      after.get("contact_phone") is not None)
check("посторонний по-прежнему не видит",
      requests.get(f"{API}/listings/{lid}", headers=other).json().get("contact_phone") is None)

head("5. ЗАВЕРШЕНИЕ")

r = requests.post(f"{API}/listings/{lid}/finish", headers=other)
check("посторонний завершить не может", r.status_code == 403, f"{r.status_code}")

r = requests.post(f"{API}/listings/{lid}/finish", headers=owner)
check("исполнитель завершил", r.status_code == 200, f"{r.status_code}")
check("статус done", r.json()["status"] == "done")

# Завершённое из ленты уходит. Иначе доска исполнителя со временем
# забивается сделанной работой — в браузере верх экрана оказался целиком
# из карточек «Завершено», а новые объявления ушли под них.
feed = requests.get(f"{API}/listings/feed", headers=owner).json()
check("завершённое из ленты исполнителя пропало",
      not any(x["id"] == lid for x in feed))
check("но у клиента в своих осталось",
      any(x["id"] == lid for x in requests.get(f"{API}/listings/mine", headers=client).json()))

head("6. ОТКАЗ ОТ ИСПОЛНИТЕЛЯ ВОЗВРАЩАЕТ В ЛЕНТУ")

lid2 = create(title="Нужны грузчики, 3 человека").json()["id"]
requests.post(f"{API}/listings/{lid2}/take", headers=owner)
r = requests.post(f"{API}/listings/{lid2}/reject", headers=client)
check("клиент отказал исполнителю", r.status_code == 200, f"{r.status_code}")
check("объявление снова открыто", r.json()["status"] == "open")
check("исполнитель снят", r.json().get("taken_by") is None)

feed = requests.get(f"{API}/listings/feed", headers=owner).json()
check("вернулось в ленту", any(x["id"] == lid2 for x in feed))

head("7. ОТМЕНА")

r = requests.post(f"{API}/listings/{lid2}/cancel", headers=other)
check("чужое отменить нельзя", r.status_code == 403, f"{r.status_code}")

r = requests.post(f"{API}/listings/{lid2}/cancel", headers=client)
check("своё отменяется", r.status_code == 200, f"{r.status_code}")
check("статус cancelled", r.json()["status"] == "cancelled")

feed = requests.get(f"{API}/listings/feed", headers=owner).json()
check("отменённое из ленты пропало", not any(x["id"] == lid2 for x in feed))

head("8. ОБЪЯВЛЕНИЕ ДВУСТОРОННЕЕ: ВЛАДЕЛЕЦ ТОЖЕ РАЗМЕЩАЕТ")

# Раньше размещать мог кто угодно, а откликаться — только владелец. То есть
# объявление владельца («завтра свободен экскаватор») висело мёртвым: взять
# его не мог никто, потому что своё взять нельзя, а других владельцев в
# радиусе может не быть вовсе.
r = requests.post(f"{API}/listings/", headers=owner, json={
    "title": "Завтра свободен экскаватор, недорого",
    "description": "Простаивает, готов выехать по городу",
    "equipment_type": "excavator",
    "budget": 900000,
})
check("владелец разместил объявление", r.status_code == 200,
      f"{r.status_code} {r.text[:120]}")
owner_lid = r.json()["id"] if r.status_code == 200 else None

check("оно у владельца в своих",
      any(x["id"] == owner_lid
          for x in requests.get(f"{API}/listings/mine", headers=owner).json()))
check("в свою ленту не попало",
      not any(x["id"] == owner_lid
              for x in requests.get(f"{API}/listings/feed", headers=owner).json()))

check("клиент видит его на доске",
      any(x["id"] == owner_lid
          for x in requests.get(f"{API}/listings/feed", headers=client).json()))

r = requests.post(f"{API}/listings/{owner_lid}/take", headers=client)
check("КЛИЕНТ может откликнуться", r.status_code == 200,
      f"{r.status_code} {r.text[:120]}")
check("статус taken", r.status_code == 200 and r.json()["status"] == "taken")

before = requests.get(f"{API}/listings/{owner_lid}", headers=client).json()
check("до подтверждения телефон владельца закрыт",
      before.get("contact_phone") is None, str(before.get("contact_phone")))

r = requests.post(f"{API}/listings/{owner_lid}/confirm", headers=client)
check("откликнувшийся сам себя не подтверждает", r.status_code == 403,
      f"{r.status_code}")

r = requests.post(f"{API}/listings/{owner_lid}/confirm", headers=owner)
check("автор (владелец) подтверждает", r.status_code == 200, f"{r.status_code}")

after = requests.get(f"{API}/listings/{owner_lid}", headers=client).json()
check("после подтверждения телефон открыт исполнителю-клиенту",
      after.get("contact_phone") is not None)
check("постороннему по-прежнему закрыт",
      requests.get(f"{API}/listings/{owner_lid}", headers=other)
      .json().get("contact_phone") is None)

requests.post(f"{API}/listings/{owner_lid}/cancel", headers=owner)

head("9. СЧЁТЧИК ПРОСМОТРОВ")

lid3 = create(title="Нужен автокран на день").json()["id"]
requests.get(f"{API}/listings/{lid3}", headers=owner)
requests.get(f"{API}/listings/{lid3}", headers=other)
views = requests.get(f"{API}/listings/{lid3}", headers=client).json()["views_count"]
check("чужие просмотры считаются", views >= 2, f"{views}")

before_own = views
requests.get(f"{API}/listings/{lid3}", headers=client)
after_own = requests.get(f"{API}/listings/{lid3}", headers=client).json()["views_count"]
check("свои просмотры не считаются", after_own == before_own,
      f"{before_own} -> {after_own}")

requests.post(f"{API}/listings/{lid3}/cancel", headers=client)

head("10. ПРЕДЛОЖЕНИЯ С ЦЕНОЙ")

lid4 = create(title="Нужны три грузчика", budget=800_000).json()["id"]

r = requests.post(f"{API}/listings/{lid4}/offers", headers=client, json={"price": 100})
check("на своё объявление предложить нельзя", r.status_code == 400, f"{r.status_code}")

r = requests.post(f"{API}/listings/{lid4}/offers", headers=owner,
                  json={"price": 950_000, "comment": "вчетвером за 3 часа"})
check("исполнитель предложил цену", r.status_code == 200, f"{r.status_code} {r.text[:120]}")
offer_id = r.json().get("id")
check("телефон предложившего автору ПОКА не отдаётся",
      r.json().get("user_phone") is None, str(r.json().get("user_phone")))

r = requests.post(f"{API}/listings/{lid4}/offers", headers=owner, json={"price": 900_000})
check("повторное предложение обновляет старое, а не плодит новое",
      r.status_code == 200 and r.json().get("id") == offer_id,
      f"{r.status_code} {r.json().get('id')} vs {offer_id}")

r = requests.post(f"{API}/listings/{lid4}/offers", headers=other, json={"price": 870_000})
check("второй исполнитель тоже может предложить", r.status_code == 200, f"{r.status_code}")
other_offer_id = r.json().get("id")

seen = requests.get(f"{API}/listings/{lid4}/offers", headers=client).json()
check("автор видит оба предложения", len(seen) == 2, str(len(seen)))
check("предложения отсортированы от дешёвых",
      [float(o["price"]) for o in seen] == sorted(float(o["price"]) for o in seen),
      str([float(o["price"]) for o in seen]))

mine_view = requests.get(f"{API}/listings/{lid4}/offers", headers=owner).json()
check("исполнитель видит ТОЛЬКО своё предложение, не конкурентов",
      len(mine_view) == 1 and mine_view[0]["id"] == offer_id, str(len(mine_view)))

row = next(x for x in requests.get(f"{API}/listings/mine", headers=client).json()
           if x["id"] == lid4)
check("счётчик предложений виден автору", row["offers_count"] == 2, str(row["offers_count"]))

r = requests.post(f"{API}/listings/{lid4}/offers/{offer_id}/accept", headers=owner)
check("чужой не может принять предложение за автора", r.status_code == 403, f"{r.status_code}")

r = requests.post(f"{API}/listings/{lid4}/offers/{offer_id}/accept", headers=client)
check("автор принял предложение", r.status_code == 200, f"{r.status_code} {r.text[:150]}")
check("объявление сразу подтверждено", r.json().get("status") == "confirmed",
      str(r.json().get("status")))
check("исполнителем стал автор предложения", r.json().get("taken_by_me") is False)

after = requests.get(f"{API}/listings/{lid4}", headers=owner).json()
check("принятому исполнителю телефон открыт", after.get("contact_phone") is not None)
check("постороннему телефон закрыт",
      requests.get(f"{API}/listings/{lid4}", headers=other).json().get("contact_phone") is None)

seen = requests.get(f"{API}/listings/{lid4}/offers", headers=client).json()
accepted = next(o for o in seen if o["id"] == offer_id)
declined = next(o for o in seen if o["id"] == other_offer_id)
check("принятое предложение отмечено accepted", accepted["status"] == "accepted",
      accepted["status"])
check("остальные предложения отклонены автоматически", declined["status"] == "declined",
      declined["status"])
check("телефон принятого исполнителя автору открылся",
      accepted.get("user_phone") is not None, str(accepted.get("user_phone")))

r = requests.post(f"{API}/listings/{lid4}/offers", headers=other, json={"price": 500_000})
check("в закрытое объявление предложить уже нельзя", r.status_code == 400, f"{r.status_code}")

requests.post(f"{API}/listings/{lid4}/cancel", headers=client)

head("11. ЛАЙКИ И СОХРАНЕНИЯ")

lid5 = create(title="Нужен самосвал на неделю").json()["id"]

before_views = requests.get(f"{API}/listings/{lid5}", headers=client).json()["views_count"]

r = requests.post(f"{API}/listings/{lid5}/like", headers=owner)
check("лайк поставлен", r.status_code == 200 and r.json()["likes_count"] == 1,
      f"{r.status_code} {r.json().get('likes_count')}")
check("свой лайк отмечен", r.json()["liked_by_me"] is True)
check("ЛАЙК НЕ НАКРУЧИВАЕТ ПРОСМОТРЫ", r.json()["views_count"] == before_views,
      f"было {before_views}, стало {r.json()['views_count']}")

r = requests.post(f"{API}/listings/{lid5}/like", headers=owner)
check("повторный лайк не удваивает счётчик", r.json()["likes_count"] == 1,
      str(r.json()["likes_count"]))

r = requests.post(f"{API}/listings/{lid5}/like", headers=other)
check("второй лайк от другого человека считается", r.json()["likes_count"] == 2,
      str(r.json()["likes_count"]))

r = requests.delete(f"{API}/listings/{lid5}/like", headers=other)
check("лайк снят", r.json()["likes_count"] == 1, str(r.json()["likes_count"]))

r = requests.post(f"{API}/listings/{lid5}/save", headers=owner)
check("закладка поставлена", r.json()["saves_count"] == 1 and r.json()["saved_by_me"],
      str(r.json().get("saves_count")))

saved = requests.get(f"{API}/listings/saved", headers=owner).json()
check("объявление попало в «Сохранённое»", any(x["id"] == lid5 for x in saved),
      str([x["id"] for x in saved]))
check("«Сохранённое» не путается с параметрическим путём — вернулся список",
      isinstance(saved, list))

requests.delete(f"{API}/listings/{lid5}/save", headers=owner)
saved = requests.get(f"{API}/listings/saved", headers=owner).json()
check("после снятия закладки объявление ушло из списка",
      not any(x["id"] == lid5 for x in saved), str([x["id"] for x in saved]))

requests.post(f"{API}/listings/{lid5}/cancel", headers=client)

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
