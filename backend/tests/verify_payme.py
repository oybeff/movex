"""
Payme Merchant API protokolini tekshirish.

Payme sertifikatsiyada aynan shu holatlarni tekshiradi: noto'g'ri kalit,
summa mos kelmasligi, takroriy so'rovlar (idempotentlik), holatlar ketma-ketligi.

Test IDEMPOTENT — bazani tozalamasdan qayta ishga tushirsa bo'ladi.

Ishga tushirish (server ishlab turgan holda):
    venv/bin/python tests/verify_payme.py
"""
import base64
import re
import time

import requests

API = "http://127.0.0.1:8000"
PAYME_URL = f"{API}/payments/payme"

# .env dagi mahalliy sinov qiymatlari bilan bir xil
PAYME_KEY = "local_dev_payme_key"
ACCOUNT_FIELD = "transaction_id"

CLIENT_PHONE = "998901110002"
TOPUP = 150_000            # so'm
TOPUP_TIYIN = TOPUP * 100

ok_count = 0
fail_count = 0


def money(x):
    return f"{float(x):,.0f}".replace(",", " ")


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


def auth_header(key=PAYME_KEY):
    raw = base64.b64encode(f"Paycom:{key}".encode()).decode()
    return {"Authorization": f"Basic {raw}"}


def rpc(method, params, key=PAYME_KEY, request_id=1):
    return requests.post(
        PAYME_URL,
        json={"jsonrpc": "2.0", "id": request_id, "method": method, "params": params},
        headers=auth_header(key),
    ).json()


def token(phone):
    r = requests.post(f"{API}/auth/send-otp", json={"phone": phone})
    code = re.search(r"(\d{4})\s*$", r.json()["message"]).group(1)
    r = requests.post(f"{API}/auth/verify-otp", json={"phone": phone, "otp_code": code})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def balance_of(hdr):
    b = requests.get(f"{API}/balance/me", headers=hdr).json()
    return float(b["balance"])


def new_topup(hdr):
    """Payme orqali to'ldirish arizasi — bizning tranzaksiya id qaytadi."""
    r = requests.post(f"{API}/balance/topup", headers=hdr,
                      json={"amount": TOPUP, "payment_method": "payme"})
    return r


client = token(CLIENT_PHONE)
start_balance = balance_of(client)
print(f"стартовый баланс клиента: {money(start_balance)} сум")

head("1. ЗАЯВКА НА ПОПОЛНЕНИЕ ЧЕРЕЗ PAYME")

r = new_topup(client)
check("заявка создана", r.status_code == 200, r.text[:200])
top = r.json()
tx_id = top["transaction_id"]
check("статус pending — деньги не зачислены", top.get("status") == "pending", str(top.get("status")))
check("ссылка на checkout.paycom.uz сгенерирована",
      "paycom.uz" in (top.get("payment_url") or ""), str(top.get("payment_url"))[:80])
check("баланс не изменился", balance_of(client) == start_balance)

# havola ichidagi ma'lumot to'g'rimi
try:
    encoded = top["payment_url"].rsplit("/", 1)[-1]
    decoded = base64.b64decode(encoded).decode()
    check("в ссылке верная сумма в тийинах", f"a={TOPUP_TIYIN}" in decoded, decoded)
    check("в ссылке номер нашей транзакции", f"ac.{ACCOUNT_FIELD}={tx_id}" in decoded, decoded)
except Exception as exc:
    check("ссылка декодируется", False, str(exc))

head("2. АВТОРИЗАЦИЯ")

res = rpc("CheckPerformTransaction", {"amount": TOPUP_TIYIN, "account": {ACCOUNT_FIELD: tx_id}},
          key="wrong_key")
check("чужой ключ отклонён кодом -32504",
      res.get("error", {}).get("code") == -32504, str(res))

res = requests.post(PAYME_URL, json={"method": "CheckPerformTransaction", "params": {}, "id": 1}).json()
check("запрос без заголовка Authorization отклонён",
      res.get("error", {}).get("code") == -32504, str(res))

head("3. CheckPerformTransaction")

res = rpc("CheckPerformTransaction", {"amount": TOPUP_TIYIN, "account": {ACCOUNT_FIELD: tx_id}})
check("оплата разрешена", res.get("result", {}).get("allow") is True, str(res))

res = rpc("CheckPerformTransaction", {"amount": TOPUP_TIYIN + 100, "account": {ACCOUNT_FIELD: tx_id}})
check("несовпадение суммы -> -31001", res.get("error", {}).get("code") == -31001, str(res))

res = rpc("CheckPerformTransaction", {"amount": TOPUP_TIYIN, "account": {ACCOUNT_FIELD: 999999999}})
check("несуществующий счёт -> -31050", res.get("error", {}).get("code") == -31050, str(res))

res = rpc("CheckPerformTransaction", {"amount": TOPUP_TIYIN, "account": {}})
check("пустой account -> -31050", res.get("error", {}).get("code") == -31050, str(res))

head("4. CreateTransaction")

payme_id = f"pm{int(time.time() * 1000)}"
res = rpc("CreateTransaction",
          {"id": payme_id, "time": int(time.time() * 1000),
           "amount": TOPUP_TIYIN, "account": {ACCOUNT_FIELD: tx_id}})
result = res.get("result", {})
check("транзакция создана, состояние 1", result.get("state") == 1, str(res))
check("возвращён наш номер транзакции", result.get("transaction") == str(tx_id), str(res))
create_time = result.get("create_time")
check("create_time заполнен", bool(create_time), str(res))

res2 = rpc("CreateTransaction",
           {"id": payme_id, "time": int(time.time() * 1000),
            "amount": TOPUP_TIYIN, "account": {ACCOUNT_FIELD: tx_id}})
check("повтор того же запроса даёт тот же ответ (идемпотентность)",
      res2.get("result", {}).get("create_time") == create_time, str(res2))

res3 = rpc("CreateTransaction",
           {"id": payme_id + "x", "time": int(time.time() * 1000),
            "amount": TOPUP_TIYIN, "account": {ACCOUNT_FIELD: tx_id}})
check("вторая транзакция по тому же счёту отклонена -> -31008",
      res3.get("error", {}).get("code") == -31008, str(res3))

check("баланс всё ещё не пополнен", balance_of(client) == start_balance)

head("5. PerformTransaction — ЗАЧИСЛЕНИЕ")

res = rpc("PerformTransaction", {"id": payme_id})
result = res.get("result", {})
check("состояние стало 2", result.get("state") == 2, str(res))
perform_time = result.get("perform_time")
check("perform_time заполнен", bool(perform_time), str(res))
check("баланс пополнен ровно на сумму платежа",
      balance_of(client) == start_balance + TOPUP,
      f"ожидалось {money(start_balance + TOPUP)}, получено {money(balance_of(client))}")

res = rpc("PerformTransaction", {"id": payme_id})
check("повторное проведение не задваивает зачисление",
      res.get("result", {}).get("perform_time") == perform_time and
      balance_of(client) == start_balance + TOPUP, str(res))

res = rpc("PerformTransaction", {"id": "нет-такой"})
check("неизвестная транзакция -> -31003", res.get("error", {}).get("code") == -31003, str(res))

head("6. CheckTransaction")

res = rpc("CheckTransaction", {"id": payme_id}).get("result", {})
check("состояние 2", res.get("state") == 2, str(res))
check("время создания совпадает", res.get("create_time") == create_time, str(res))
check("время проведения совпадает", res.get("perform_time") == perform_time, str(res))

head("7. CancelTransaction — ВОЗВРАТ ПОСЛЕ ПРОВЕДЕНИЯ")

before_cancel = balance_of(client)
res = rpc("CancelTransaction", {"id": payme_id, "reason": 5})
result = res.get("result", {})
check("состояние стало -2 (отмена после проведения)", result.get("state") == -2, str(res))
check("деньги списаны обратно", balance_of(client) == before_cancel - TOPUP,
      f"ожидалось {money(before_cancel - TOPUP)}, получено {money(balance_of(client))}")

res = rpc("CancelTransaction", {"id": payme_id, "reason": 5})
check("повторная отмена не списывает второй раз",
      res.get("result", {}).get("state") == -2 and balance_of(client) == before_cancel - TOPUP,
      str(res))

head("8. GetStatement И НЕИЗВЕСТНЫЙ МЕТОД")

now_ms = int(time.time() * 1000)
res = rpc("GetStatement", {"from": now_ms - 3600_000, "to": now_ms + 3600_000})
txs = res.get("result", {}).get("transactions")
check("выписка возвращает список", isinstance(txs, list), str(res)[:200])
check("наша транзакция есть в выписке",
      any(t.get("id") == payme_id for t in (txs or [])), f"найдено {len(txs or [])}")

res = rpc("НесуществующийМетод", {})
check("неизвестный метод -> -32601", res.get("error", {}).get("code") == -32601, str(res))

res = requests.post(PAYME_URL, data="это не json", headers=auth_header()).json()
check("битый JSON -> -32700", res.get("error", {}).get("code") == -32700, str(res))

head(f"ИТОГ: {ok_count} пройдено, {fail_count} провалено")
raise SystemExit(1 if fail_count else 0)
