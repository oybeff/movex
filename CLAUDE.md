# MoveX GO

Платформа аренды строительной техники (Узбекистан). Клиент находит и арендует технику,
владелец сдаёт её и управляет парком. Прод: `movex.004.uz`.

## Структура

```
movex/
├── backend/   FastAPI + PostgreSQL + Alembic   — основной API
├── admin/     чистый PHP 7.4 + PDO            — админ-панель (ходит в БД напрямую)
├── mobile/    Flutter 3.8                     — приложение iOS + Android
└── docs/      выгрузка .md из исходных архивов (deploy-гайды, Click-интеграция)
```

Три части были отдельными GitHub-репозиториями (`movex_go_backend`, `movex_go_admin`,
`movex_go_mobile`), собраны в один монорепо 30 августа 2026. Git-истории не сохранилось —
первый коммит здесь и есть точка отсчёта.

## Домен и роли

Роли пользователя: **client**, **owner**, **admin** (`backend/app/core/roles.py`).

- **client** — каталог техники, аренда с выбором точки на карте, чат с владельцем,
  история заказов, баланс и платежи
- **owner** — дашборд, свой парк техники (добавить/редактировать), заказы, статистика,
  платежи, франшиза
- **admin** — только через PHP-панель, не через мобилку

## Backend

FastAPI, Python 3.11+. Точка входа `backend/app/main.py`.

Слои: `routes/` (HTTP) → `services/` (логика) → `models/` (SQLAlchemy) + `schemas/` (Pydantic).

Роуты монтируются с префиксами: `/auth`, `/users`, `/companies`, `/equipment`, `/orders`,
`/chats`, `/messages`, `/reviews`, `/payments`, `/balance`, `/settings`, `/admin`.
Плюс `/health` и `/`. Swagger на `/docs` — **автоматически отключается при `APP_ENV=production`**.

Внешние интеграции:
- **Click** — приём платежей (`services/click_service.py`, `docs/backend/CLICK_INTEGRATION.md`)
- **Eskiz** — SMS и OTP-коды (`services/eskiz_service.py`, токен кэшируется в таблице `eskiz_token`)
- **Telegram** — уведомления в группу (`services/telegram_service.py`)

Команды (из `backend/`, есть `Makefile`):

```bash
make install                  # pip install -r requirements.txt
make run                      # uvicorn app.main:app --reload --port 8000
make migrate                  # alembic upgrade head
make migrate-create           # новая миграция
```

## Admin

Чистый PHP без фреймворка, подключается к той же PostgreSQL напрямую через PDO —
**не через API бэкенда**. Схему БД меняешь в `backend/` — проверь, не сломались ли
запросы в `admin/*.php`.

Страницы: `index.php` (дашборд), `users.php`, `orders.php`, `balance.php`, `budget.php`,
`system.php`, `backup.php` (дампы БД), `login.php`/`logout.php`. Конфиг — `admin/config.php`.

## Mobile

Flutter 3.8, Dart SDK `^3.8.1`. 69 dart-файлов, 38 экранов.

Структура: `lib/core/` (сеть, модели, сервисы, тема, роутер, виджеты) +
`lib/features/{auth,client_home,owner_home,balance,settings}/presentation/pages/`.

- Навигация — **go_router**, все маршруты объявлены прямо в `lib/main.dart`
- Состояние — **provider**
- HTTP — **dio**, единственный клиент `lib/core/network/dio_client.dart`
  (интерцептор подставляет Bearer-токен из SharedPreferences, на 401 чистит сессию и кидает на `/login`)
- Карты — **yandex_mapkit**
- Локализация — **easy_localization**, переводы в `assets/translations/` (uz по умолчанию)

Сборка:

```bash
flutter pub get
flutter run                                  # dev
flutter build apk --release                  # Android
flutter build ipa --release                  # iOS
```

## Известные проблемы

Актуально на момент переноса, ещё не исправлено:

1. **API-адрес захардкожен на локалку разработчика** — `lib/core/network/dio_client.dart:9`
   содержит `http://192.168.1.101:8000`. Нужен `--dart-define` или конфиг dev/prod.
   Это единственное место в `lib/`, где зашит адрес.
2. **Bundle ID дефолтный** — `com.example.movexGo` (iOS) и `com.example.movex_go` (Android).
   С таким в App Store и Google Play не пустят.
3. **Firebase — мёртвая зависимость.** `firebase_core` и `firebase_auth` есть в `pubspec.yaml`,
   но в `lib/` не используются ни разу, `Firebase.initializeApp()` не вызывается, конфигов
   (`google-services.json`, `GoogleService-Info.plist`) в проекте нет. Приложение от этого не
   падает, но нативные SDK тянутся в сборку и могут ломать `pod install` на iOS.
   Либо выпилить, либо донастроить.
4. **Токены и тела запросов текут в логи** — `dio_client.dart` печатает кусок JWT через `print`
   и вешает `LogInterceptor` с `requestBody`/`responseBody`. В релизной сборке так нельзя.
5. **`create_all` вместе с Alembic** — `backend/app/main.py` вызывает
   `Base.metadata.create_all(bind=engine)` на старте, хотя миграции ведёт Alembic.
   Схема может разъехаться с историей миграций.
6. **Пароль от FTP лежал в репозитории** — `mobile/.vscode/sftp.json`. Файл добавлен
   в `.gitignore`, но пароль скомпрометирован и его надо сменить на сервере.
7. **`ADMIN_SECRET_KEY` захардкожен** в `admin/config.php` (`movex_go_admin_secret_2024`,
   в комментарии рядом честно написано «O'zgartiring!»). Вынести в окружение.

## Окружение этой машины

- Flutter/Dart **не установлены** — мобилку локально собрать нечем
- Python **3.9.6**, бэкенду нужен **3.11+**
- PHP 7.4.33 ✅, PostgreSQL 16.13 ✅, Xcode ✅

## Правила

- Секреты — только в `.env` и переменных окружения, никогда в код и никогда в git
- Меняешь схему БД — миграция Alembic **и** проверка PHP-запросов в `admin/`
- Языки в проекте смешаны: код и комментарии на узбекском, русском и английском.
  Не переписывай существующие комментарии ради единообразия
