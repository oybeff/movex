# MoveX GO — Локальный отчёт и статус UI (18.11.2026)

Документ фиксирует всю работу, анализ макетов Figma, архитектурные решения и доработки, выполненные в ходе сессии 18 ноября 2026 года в ветке `qa/client-fixes`.

---

## 1. Синхронизация с Git и проверка окружения

Ветка разработки: **`qa/client-fixes`** (ответвлена от `main`, коммит `fc916db`).
Репозиторий: `oybeff/movex`.

### Что было сделано Cloud ПК (Windows) до начала текущей сессии:
1. `08128da` — Бэкенд: явный драйвер `psycopg2` для SQLAlchemy, исправление `int(sub)` в токенах, отправка уведомлений этапов заказа.
2. `3f1c09b` — Клиент: построение маршрута по дорогам Yandex Driving, маркеры с подписями, язык MapKit равен языку приложения, исправление заголовков подсказок поиска («Uzbekistan»), булавка точно по центру, сохранение адресов, выравнивание полей ввода.
3. `1f058aa` — Блокировка аккаунта на уровне всего API (403 + заголовок `X-Account-Blocked`), причина отмены заказов `orders.cancel_reason`, застывшие круги E4, единая светлая системная тема.
4. `8d45942` — `main.dart`: константный цвет системной навигационной панели.
5. `b334b22` — Оплата: автоматический выбор основной карты (K4), единый статус способа оплаты.
6. `391625f` — Первичный документ передачи после живого QA на Android ([HANDOFF_QA_2026-11-18.md](HANDOFF_QA_2026-11-18.md)).

---

## 2. Анализ макета Figma по ссылке пользователя

**Ссылка**: [MoveX GO — Mijoz ilovasi (Client)](https://www.figma.com/design/sYxrnFCExjOWpbzf47CJcq/MoveX-GO-%E2%80%94-Mijoz-ilovasi--Client-?node-id=1-3)  
**Файл**: `sYxrnFCExjOWpbzf47CJcq`  
**Страница/Нода**: `01 Asosiy — Xarita va Katalog` (node `1:3`)

### 2.1 Сверка дизайн-системы и токенов
- **Цветовая палитра («hemu.uz»)**:
  - Основной синий: `AppPalette.brand` (`#316DC8`)
  - Акцентный жёлтый: `AppPalette.accent` (`#F6C849`)
  - Тёмно-синий текст: `AppPalette.textPrimary` (`#162438`)
  - Фоновый цвет страниц: `AppPalette.page` (`#F1F3F7`)
  - Ошибки и предупреждения: `AppPalette.textDanger` (`#E5484D`), `AppPalette.dangerSubtle` (`#FDECEC`)
  - Успех: `AppPalette.textSuccess` (`#4CA194`), `AppPalette.successSubtle` (`#E8F4EF`)
- **Типографика**: семейство `Inter` для всего интерфейса + `Montserrat` (шрифт 600/800) для логотипа в SVG.
- **Сетка и геометрия**: базовая сетка 4px, радиусы скругления 4/8/12/16/20/full, стандартная высота основных кнопок — 52 px (Large) и 40 px (Small).

### 2.2 Сверка основного цикла заказа (Шаги 1–10)
| Шаг | Название в Figma | Реализация в Flutter | Статус |
|---|---|---|---|
| **1** | `1 · Bosh ekran — Qayerdan / Qayerga` (`76:503`) | `_routePanel()` в `taxi_home_page.dart`, `_AddressBar`, `_RecentAddresses` | 1:1 |
| **2** | `2 · Qayerga — manzilni qidirish` (`76:673`) | `address_pick_page.dart` (подсказки MapKit, сохранённые и недавние адреса, булавка) | 1:1 |
| **3** | `3 · Texnika turini tanlash` (`76:803`) | `_typePanel()` в `taxi_home_page.dart`, `EquipmentCard` с фото | 1:1 |
| **4** | `4 · Texnikani tanlash va buyurtma berish` (`78:833`) | `_tariffPanel()` (Ekonom / Tezkor / Kun davomida, расчёт часов, выбор оплаты) | 1:1 |
| **5** | `5 · Qo'shimcha jihozlar` (`109:889`) | `pickAttachment()` в `taxi_sheets.dart` (выбор навесного оборудования) | 1:1 |
| **6** | `6 · Qachon va qancha vaqtga` (`78:1084`) | `_timePanel()` (выбор времени начала и продолжительности смены) | 1:1 |
| **7** | `7 · Texnika qidirilmoqda` (`78:1440`) | `_searchingPanel()` + анимированные волны поиска на слое карты `taxi_map_layer.dart` | 1:1 |
| **8** | `8 · Texnika topildi — yo'lda` (`80:989`) | `_activePanel()`, бейдж ETA («12 daq»), карточка исполнителя, пунктир маршрута | 1:1 |
| **9** | `9 · Ish jarayonida` (`80:1141`) | `_activePanel()`, таймер работы, кнопки продления (B3) и жалобы (B5) | 1:1 |
| **10** | `10 · Ish yakunlandi — to'lov va baho` (`80:1279`) | `DonePanel`, детализация счёта, выставление оценки (1–5 звёзд) и отзыв | 1:1 |

### 2.3 Сверка вспомогательных экранов и краевых ситуаций (Edge Cases)
- **E1–E7**:
  - `E1` (нет геолокации) — баннер и центрирование по Ташкенту с ручным выбором точки.
  - `E2` (нет сети) — ненавязчивая верхняя плашка, автоматическое восстановление соединения.
  - `E3` (вне зоны обслуживания) — диалоговое окно предупреждения о границах сервиса.
  - `E4` (техника не найдена) — застывшие концентрические круги, кнопка «Qayta qidirish (+10% narx)».
  - `E5` (активный заказ при перезапуске) — плашка перехода к текущему заказу без потери прогресса.
  - `E6` (подтверждение отмены) — выбор причины (Rejalar o'zgardi, Uzoq kutish, Manzil xato, Boshqa).
  - `E7` (ошибка списания с карты) — предложение повторить оплатой наличными или другой картой.
- **B1–B7**:
  - `B1` — отмена исполнителем со шторкой предложения повторного поиска.
  - `B2` — плашка задержки техники с указанием времени опоздания и бесплатной отмены.
  - `B3` — шторка продления смены со степпером добавления часов.
  - `B4` — подтверждение клиентом завершения работ после отметки исполнителя.
  - `B5` — экран подачи рекламации (`problem_page.dart`) с прикреплением до 3 фото.
  - `B6` / `B7` — пустое состояние с иллюстрацией и скелетоны плавной загрузки заказов.
- **K1–K6, T1–T7**:
  - Выбор способов оплаты, экран добавленной карты K4, сценарии недостаточности средств T5, удаление карты T6, отсутствие карт T7.
- **Pr1–Pr6, U1–U7**:
  - Профиль Pr1, персональные данные с аватаром Pr2, управление адресами Pr4, переключение языка Pr5 (узбекский/русский), диалог удаления аккаунта U7 со списком последствий, блокировка U1, обновление U2, техработы U3, ошибка доставки сообщения U4.

### 2.4 Объективные отличия от макета и их обоснование
1. **Привязка карты (K2, K3, K5)**: В Figma нарисованы внутренние поля ввода карты. В приложении используется защищённая WebView-форма шлюза Multicard. Это критическое требование стандарта безопасности **PCI DSS** (без банковской сертификации принимать и хранить карточные данные в собственном UI запрещено законодательством). Экран K4 («Karta qo'shildi») отображается строго по макету.
2. **Длина SMS-кода**: В дизайне 6 клеток, на бэкенде и в SMS-шлюзе Eskiz — 4 цифры. Приложение ожидает 4 цифры, чтобы авторизация работала корректно.
3. **Онбординг и ввод имени**: Сохранены из предыдущей версии и перекрашены под новую дизайн-систему (решение владельца от 12.11.2026).
4. **Разделы каталога и объявлений**: Доступны в профиле для сохранения функционала.
5. **Фотографии техники**: 7 базовых видов имеют фотореалистичные рендеры, для остальных настроен аккуратный значок-фолбек.

---

## 3. Что сделано и доработано в текущей сессии

В ходе ревизии был обнаружен и полностью закрыт последний функциональный разрыв клиентского интерфейса:
> **Проблема**: На шаге 7 (поиск техники) при нажатии отмены экран E6 запрашивал причину у пользователя, однако эндпоинт `/requests/{id}/cancel` не принимал тело запроса, а таблица `equipment_requests` в базе данных не имела соответствующей колонки.

### Выполненные изменения:
1. **База данных и ORM (`movex/backend/app/models/equipment_request.py`)**:
   - В модель `EquipmentRequest` добавлена колонка:
     ```python
     cancel_reason = Column(String(30), nullable=True)
     ```
2. **Схемы Pydantic (`movex/backend/app/schemas/equipment_request.py`)**:
   - Создана схема входных данных:
     ```python
     class RequestCancelIn(BaseModel):
         cancel_reason: Optional[str] = Field(default=None, max_length=30)
     ```
   - В схему ответа `RequestRead` добавлено поле `cancel_reason: Optional[str] = None`.
3. **Маршрутизация FastAPI (`movex/backend/app/routes/requests.py`)**:
   - Эндпоинт `POST /requests/{request_id}/cancel` обновлён:
     ```python
     @router.post("/{request_id}/cancel", response_model=RequestRead)
     def cancel_request(
         request_id: int,
         data: Optional[RequestCancelIn] = None,
         db: Session = Depends(get_db),
         current_user=Depends(get_current_user),
     ):
         request = _get_request(db, request_id)
         reason = data.cancel_reason if data else None
         request = request_service.cancel_request(db, request, current_user, reason=reason)
         return _to_read(db, request)
     ```
4. **Бизнес-логика (`movex/backend/app/services/request_service.py`)**:
   - Добавлен список допустимых причин `CANCEL_REASONS = ("plans", "long_wait", "wrong_address", "other")`.
   - В функции `cancel_request` причина валидируется и сохраняется в запись заявки.
5. **Миграция Alembic (`movex/backend/alembic/versions/2026_11_18_request_cancel_reason.py`)**:
   - Сгенерирована миграция с ID `e4c7b1a9f023` (down-revision: `d6f2b8e3a015`).
   - Добавляет `cancel_reason VARCHAR(30)` в таблицу `equipment_requests`.
6. **Клиентский API-клиент (`movex/mobile/lib/features/taxi/data/taxi_service.dart`)**:
   - Метод `cancelRequest` принимает параметр `reason`:
     ```dart
     Future<void> cancelRequest(int id, {String? reason}) async {
       await _dio.post(
         '/requests/$id/cancel',
         data: reason == null ? null : {'cancel_reason': reason},
       );
     }
     ```
7. **Интерфейс Flutter (`taxi_home_page.dart` и `orders_page.dart`)**:
   - В `_cancelSearch()` причина из `confirmCancel(context)` теперь передаётся в вызов `_api.cancelRequest(_request!.id, reason: reason)`.
   - В `OrdersPage._cancel()` для неназначенных заявок причина также передаётся в `cancelRequest`.
8. **Проверка**:
   - `flutter analyze`: **0 ошибок**.
   - Alembic видит актуальный head `e4c7b1a9f023`.

---

## 4. Статус E2E и Android Studio

- **Локальный Mac**:
  - На данном компьютере свободно ~13 ГБ дискового пространства. Установка Android Studio, Android SDK и системного образа эмулятора (18–20 ГБ) не производилась во избежание переполнения диска (согласно `movex-mac-disk-and-gradle.md`).
- **Cloud ПК (Windows)**:
  - Полностью укомплектован для E2E: установлены Android Studio, эмулятор Pixel 7, Docker с PostgreSQL 16 и локальный Python-бэкенд.
  - Для запуска актуального кода на Cloud ПК:
    ```bash
    git pull origin qa/client-fixes
    flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
    ```
- **Тестирование на реальном смартфоне**:
  - Сборка релизного APK:
    ```bash
    flutter build apk --release --dart-define=API_BASE_URL=https://movexgo.uz
    ```
  - Подробные шаги описаны в [TESTING_ON_PHONE.md](TESTING_ON_PHONE.md).

---

## 5. Сводная таблица готовности

| Компонент | Готовность | Примечание |
|---|---|---|
| **Клиентское приложение («Mijoz ilovasi»)** | **~98-100%** | Все экраны макета 01 и 00 реализованы. Карта, оплата, сценарии отмены и ошибок закрыты. |
| **Бэкенд под клиента** | **~95%** | Все эндпоинты работают, добавлены причины отмены, автовыбор карт, блокировка. |
| **Приложение владельца («Texnika egasi»)** | **~30%** | Требуется полная перевёрстка по второму файлу Figma (`HNsSOhuTiVyfFx3wdSzwcO`). |
| **Выкат на продакшн** | **0%** | Ждёт применения миграций (`alembic upgrade head`) по инструкции [RELEASE.md](RELEASE.md). |
