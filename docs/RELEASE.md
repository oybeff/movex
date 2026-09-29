# Выкат MoveX GO в продакшн

**Чистый сервер настраивается не отсюда, а комплектом `deploy/`** —
`deploy/README.md`, один скрипт делает всё: пакеты, база, окружение,
systemd, nginx, админка, файрвол, дампы. Этот файл описывает выкат на
уже настроенный сервер и то, что делается руками помимо него.

Единый чеклист. В `docs/backend/` лежат семь старых документов о деплое
(`DEPLOY.md`, `SIMPLE_DEPLOY.md`, `QUICK_START.md`, `START_HERE.md`,
`README_DEPLOY.md`, `DEPLOY_SUMMARY.md`, `DEPLOY_MOVEX_004_UZ.md`) — они
пересекаются между собой и написаны до всех изменений. **Ориентируйтесь на
этот файл.**

---

## 1. Бэкенд

### Первая установка на чистом сервере

```bash
cd /opt/movex_go
python3 -m venv venv          # в Ubuntu 24.04 это 3.12; пакета python3.11 там НЕТ
venv/bin/pip install -r requirements.txt

cp .env.example .env && nano .env      # см. раздел «Переменные» ниже
venv/bin/python scripts/init_db.py     # ТОЛЬКО на пустой базе
```

`init_db.py` строит схему и отмечает Alembic как актуальный. На непустой базе
он откажется работать — это защита от порчи данных.

### Обновление уже работающего сервера

```bash
cd /opt/movex_go
git pull
venv/bin/pip install -r requirements.txt

# ОБЯЗАТЕЛЬНО: сделайте дамп перед миграцией
pg_dump movex_go > /root/movex_go_$(date +%F_%H%M).sql

venv/bin/alembic upgrade head
systemctl restart movex_go
```

#### Релиз 5 сентября 2026 — что обязательно сделать руками

Две новые миграции применяются обычным `alembic upgrade head`:

* `f3b8c21d47ae` — тип транзакции `bonus` в `check_transaction_type`;
* `a91c4e8b2d76` — `listings.agreed_price` / `listings.commission` и
  `budget_reserves.listing_id` (у `order_id` снимается NOT NULL);
* `c47f9a1e6b23` — `balances.bonus_balance`. Миграция сама проставляет его
  тем, кто бонус уже получил, чтобы задним числом его не вывели.

**Правку `.env` миграция не делает** — её нужно внести самому, иначе люди
по-прежнему будут входить заново каждый день:

```bash
# в /opt/movex/backend/.env
ACCESS_TOKEN_EXPIRE_MINUTES=0     # было 1440; 0 = токен без срока
```

Файлы админки тоже обновляются `git pull`, но проверьте после выката две
страницы: `commission.php` (там появился блок «совға за регистрацию») и
`budget.php` (в списке теперь и заказы, и объявления).

Проверить, что настройки бонуса на месте:

```bash
psql movex_go -c "SELECT key, value FROM app_settings WHERE key LIKE 'signup_bonus%';"
```
Пустой ответ — это нормально: значения по умолчанию (50 000, включено)
берутся из кода, а строки появятся после первого сохранения в админке.

Миграции прежних релизов: типы техники, заявки на вывод, уведомления,
индексы. Миграция типов техники **меняет данные** в `equipment.type` — исходный
текст сохраняется в `equipment.type_legacy`, откатить можно через
`alembic downgrade`.

### Переменные окружения

Файл `/opt/movex_go/.env`, systemd подхватывает его через `EnvironmentFile`.

```bash
DATABASE_URL=postgresql://user:pass@localhost:5432/movex_go
SECRET_KEY=                      # openssl rand -hex 32

APP_ENV=production               # включает строгие проверки, скрывает /docs
ALLOWED_HOSTS=movex.004.uz
CORS_ORIGINS=https://movex.004.uz

# SMS
ESKIZ_EMAIL=
ESKIZ_PASSWORD=
OTP_TEST_MODE=false              # true отдаёт код прямо в ответе — только для разработки

# Rahmat (Multicard) — единственный платёжный шлюз
RAHMAT_APPLICATION_ID=
RAHMAT_SECRET=
RAHMAT_STORE_ID=
RAHMAT_TEST_MODE=false           # true — песочница dev-mesh
RAHMAT_CALLBACK_BASE_URL=https://movexgo.uz   # пусто = оплата не создаётся
RAHMAT_RETURN_URL=movexgo://payment/success
RAHMAT_RETURN_ERROR_URL=movexgo://payment/failed

# Слово, которым PHP-панель вызывает API. Перевод денег на карту делает
# только backend; пусто = внутренние адреса отдают 404.
ADMIN_INTERNAL_SECRET=           # openssl rand -hex 32
INTERNAL_API_URL=http://127.0.0.1:8000
```

`SPLIT_MODE` больше нет: он читался только интеграцией Payme и после её
удаления ни на что не влиял. Деньги идут строго по escrow.

**Проверьте после старта:** при `APP_ENV=production` и `CORS_ORIGINS=*`
приложение не запустится намеренно — это защита от открытого API.

### Проверка после выката

```bash
curl https://movex.004.uz/health          # {"status":"healthy",...}
curl https://movex.004.uz/docs            # должно быть 404 — в проде документация скрыта
```

### Вход по Telegram

В проде бот работает через **вебхук**, а не опросом:

```bash
cd backend
venv/bin/python scripts/telegram_webhook.py set https://movex.004.uz
venv/bin/python scripts/telegram_webhook.py info
```

Опрос (`TELEGRAM_POLLING=true`) запускается в КАЖДОМ процессе uvicorn, а
их несколько. Два опроса одного бота Telegram встречает ответом 409, и
вход начинает работать через раз. Вебхуку число процессов безразлично.

Адрес `/auth/telegram/webhook` закрыт словом `TELEGRAM_WEBHOOK_SECRET`.
Пока оно пустое, адреса нет вовсе (404) — иначе любой, кто знает домен,
слал бы поддельные `contact` и заходил под чужим номером: ни пароля, ни
кода на этом пути не спрашивают. Сторожит `tests/verify_telegram_webhook.py`.

### Администратор

На чистой базе администратора нет — в панель войти нечем:

```bash
cd backend && venv/bin/python scripts/create_admin.py
```

Логин в панели — номер ровно как в базе, без плюса: `998901234567`.

---

## 2. Платёжные системы

Система одна — **Rahmat (Multicard)**. Click и Payme со своими
интеграциями убраны: на странице оплаты Multicard они уже есть как способы
оплаты, вместе с Uzum, Anorbank, Oson, Alif, Xazna, Beepul, Trastpay,
Paynet и картой.

1. Получить боевые `application_id`, `secret` и `store_id`, вписать в `.env`
   и поставить `RAHMAT_TEST_MODE=false`.
2. `RAHMAT_CALLBACK_BASE_URL` — **публичный адрес этого сервера**
   (`https://movexgo.uz`). Адрес callback шлюзу передаётся в каждом
   инвойсе, отдельно в кабинете его прописывать не нужно.
3. В кабинете Multicard включить вебхуки на смену статуса, если нужны
   `revert` и `error` — иначе о возврате никто не сообщит и деньги
   останутся на балансе.
4. Проверить боевой оплатой на маленькую сумму и сверить:
   транзакция `completed`, баланс вырос ровно на сумму.

Выплаты на карту идут из депозита (кошелька) приложения в Multicard —
его нужно пополнить, иначе `POST /payment/credit` вернёт ошибку.

Подробности — `docs/backend/PAYMENTS.md`.

---

## 3. Админка

Отдельных настроек у админки нет: `admin/config.php` берёт доступ к базе
из `backend/.env`, из `DATABASE_URL`. Поэтому `admin/` и `backend/` должны
лежать РЯДОМ, а `.env` — быть доступен на чтение пользователю php-fpm
(`bootstrap_ubuntu24.sh` кладёт файл в группу `movex` и добавляет туда
`www-data`).

Раньше здесь стояли `POSTGRES_*` — таких переменных в проекте нет, панель
падала с «role does not exist».

Панель живёт на отдельном поддомене `admin.<домен>`, а не на `/admin`
основного: этот путь у API занят собственным роутером.

Cookie сессии сама получает флаг `Secure`, когда сайт открыт по HTTPS —
руками ничего править не нужно.

Новая страница — **Pul Yechish** (`payouts.php`). Без неё владельцы техники
не смогут получить свои деньги: заявки будут копиться необработанными.

---

## 4. Мобильное приложение

### Перед первой публикацией

- [ ] **Идентификатор приложения.** Сейчас `uz.movexgo.app` на обеих
      платформах. Поменять можно только ДО первой публикации — потом он
      закрепляется навсегда.
- [ ] **Firebase**, если нужны push. Порядок — `docs/backend/NOTIFICATIONS.md`.
- [ ] **Ключ Яндекс-карт** для боевого бандла: `MainActivity.kt` (Android)
      и `AppDelegate.swift` / `Info.plist` (iOS).
- [ ] **Ключ геокодера** — в `geocoding_service.dart:7` до сих пор заглушка,
      определение адреса по координатам работать не будет.

### Сборка

Адрес сервера задаётся при сборке. Без него возьмётся прод — это сделано
намеренно, чтобы случайная сборка не стучалась в чью-то локальную сеть.

```bash
flutter build apk --release  --dart-define=API_BASE_URL=https://movex.004.uz
flutter build ipa --release  --dart-define=API_BASE_URL=https://movex.004.uz
```

Для отладки на устройстве:

```bash
flutter run --dart-define=API_BASE_URL=http://<ваш-ip>:8000
```

### Что нужно на машине сборки

- **Android**: Android Studio или Android SDK (~6 ГБ)
- **iOS**: полный Xcode (~17 ГБ), одних Command Line Tools недостаточно

---

## 5. Что проверить перед тем, как открывать людям

```bash
# на сервере, при запущенном API
bash backend/tests/run_all.sh
```

Деньги, возвраты, Rahmat, выплаты, права доступа, уведомления, объявления,
материалы, защита OTP, вебхук Telegram и смоук по всем GET-эндпоинтам.
Скрипт заканчивается строкой `BARCHA TEKSHIRUVLAR MUVAFFAQIYATLI` — любая
другая означает провал.

Отдельно руками:

- [ ] Бонус владельцам, зарегистрированным до 05.09.2026, если решено
      доначислить: `venv/bin/python scripts/grant_bonus_to_existing_owners.py`
      (сначала без флагов — покажет список и сумму, затем `--apply`)
- [ ] Реальное пополнение через Rahmat на небольшую сумму
- [ ] Вывод на карту: заявка → «Картаga o'tkazish» в панели → деньги пришли
- [ ] Заказ целиком: создать → подтвердить → завершить, сверить балансы
- [ ] Отмена заказа — деньги вернулись клиенту
- [ ] Заявка на вывод и её обработка в админке
- [ ] Вход по СМС на настоящий номер (`OTP_TEST_MODE=false`)
- [ ] Карта открывается и на Android, и на iPhone

---

## 6. Не забыть

**Сменить пароль от FTP** (`159.69.38.202`, пользователь `ftp_movex_004_uz`).
Он лежал открытым текстом в архиве мобильного приложения и, судя по всему,
был в истории репозитория. В новый git не попадает, но считать его
действующим нельзя.
