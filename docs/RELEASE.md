# Выкат MoveX GO в продакшн

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
python3.11 -m venv venv
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

Миграции этого релиза: типы техники, Payme, заявки на вывод, уведомления,
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

# Click
CLICK_MERCHANT_ID=
CLICK_SERVICE_ID=
CLICK_SECRET_KEY=
CLICK_MERCHANT_USER_ID=

# Payme
PAYME_MERCHANT_ID=
PAYME_KEY=
PAYME_ACCOUNT_FIELD=transaction_id

SPLIT_MODE=escrow                # см. docs/backend/PAYMENTS.md
```

**Проверьте после старта:** при `APP_ENV=production` и `CORS_ORIGINS=*`
приложение не запустится намеренно — это защита от открытого API.

### Проверка после выката

```bash
curl https://movex.004.uz/health          # {"status":"healthy",...}
curl https://movex.004.uz/docs            # должно быть 404 — в проде документация скрыта
```

---

## 2. Платёжные системы

1. Получить мерчант-аккаунты в Click и Payme, вписать ключи в `.env`.
2. В кабинете **Payme** указать адрес вебхука:
   `https://movex.004.uz/payments/payme`
   и имя поля счёта — оно должно совпадать с `PAYME_ACCOUNT_FIELD`.
3. В кабинете **Click** указать `prepare` и `complete`:
   `https://movex.004.uz/balance/click/prepare`
   `https://movex.004.uz/balance/click/complete`
4. Пройти сертификацию Payme. Сценарии, которые там проверяют, покрыты
   тестом `backend/tests/verify_payme.py`.

Подробности и режимы сплита — `docs/backend/PAYMENTS.md`.

---

## 3. Админка

```bash
APP_ENV=production               # иначе ошибки будут видны посетителям
POSTGRES_HOST=localhost
POSTGRES_DB=movex_go
POSTGRES_USER=
POSTGRES_PASSWORD=
```

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

187 проверок: деньги, возвраты, Payme, выплаты, права доступа, уведомления,
защита OTP. Все должны быть зелёными.

Отдельно руками:

- [ ] Реальное пополнение через Click и через Payme на небольшую сумму
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
