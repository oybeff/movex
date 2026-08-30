# Уведомления

До этого в приложении не было никакого способа узнать о новом заказе: владелец
техники обновлял список руками. Теперь есть лента уведомлений, а под push
подготовлена вся серверная часть.

## Что уже работает

Лента внутри приложения — экран `/notifications`, вход через колокольчик в
шапке дашборда владельца и пункт в профиле клиента. У каждой строки иконка
типа техники, чтобы было видно, о какой машине речь, не читая текст.

| Событие | Кому уходит | Тип |
|---|---|---|
| Клиент оформил заказ | владельцу техники | `order_created` |
| Владелец подтвердил | клиенту | `order_confirmed` |
| Владелец отклонил | клиенту | `order_rejected` |
| Заказ отменён | обеим сторонам | `order_cancelled` |
| Заказ завершён | обеим сторонам | `order_completed` |

| Клиент создал заявку | владельцам подходящей техники в радиусе | `request_created` |
| Владелец прислал предложение | клиенту | `request_offer` |
| Клиент выбрал предложение | этому владельцу | `request_offer_accepted` |
| Клиент выбрал чужое предложение | остальным владельцам | `request_offer_rejected` |
| Клиент отменил заявку | владельцам, приславшим предложения | `request_cancelled` |

Зарезервированы, но пока не рассылаются: `balance_topup`, `payout_paid`,
`payout_rejected`, `system`.

Заявки рассылаются **только владельцам в радиусе** — см. `search_radius_km`
в `users`. Владелец без заданной точки получает всё: радиус это фильтр, а не
запрет, и не настроивший его не должен остаться без заявок.

## Эндпоинты

```
GET    /notifications/                 лента, только свои
GET    /notifications/unread-count     число для значка на колокольчике
POST   /notifications/{id}/read        отметить прочитанным
POST   /notifications/read-all         отметить все
DELETE /notifications/{id}             удалить своё
POST   /notifications/devices          зарегистрировать токен устройства
DELETE /notifications/devices          снять токен (при выходе)
```

Каждый эндпоинт работает только со своими уведомлениями — чужое не видно и
не удаляется.

`equipment_type` хранится прямо в уведомлении, а не берётся из заказа
каждый раз: если заказ удалят, в ленте всё равно останется правильная иконка.

Создание уведомления никогда не ломает основное действие — все ошибки внутри
`notify_order_event` проглатываются. Заказ подтверждён, но уведомление не
записалось — это не повод откатывать подтверждение.

Проверка: `venv/bin/python tests/verify_notifications.py` — 29 тестов.

## Push

Серверная часть **написана полностью** — `services/push_service.py`, Firebase
Cloud Messaging HTTP v1. Отправка подключена к `notification_service.create`,
то есть работает для всех событий из таблицы выше сразу.

Пока не заданы ключи, `push_service` молчит: пишет одну строку в лог и
возвращает 0. Ничего не ломается, уведомления видны в ленте приложения как
и раньше.

### Что нужно от вас

Проект Firebase может создать только владелец аккаунта Google — у меня нет
и не должно быть доступа к вашей учётной записи.

**1. Создать проект.** [console.firebase.google.com](https://console.firebase.google.com)
→ Add project. Имя любое, например `movex-go`. Google Analytics можно
выключить.

**2. Добавить два приложения** с идентификатором `uz.movexgo.app`:
- Android → скачать `google-services.json`
- iOS → скачать `GoogleService-Info.plist`

**3. Скачать ключ сервисного аккаунта.** Настройки проекта (шестерёнка) →
Service accounts → Generate new private key. Скачается JSON.

**Этот файл — полный доступ к отправке push от имени проекта. Не присылайте
его мне в чат и не коммитьте в git.** Положите на сервер:

```bash
scp firebase-key.json root@СЕРВЕР:/opt/movex_go/firebase-key.json
ssh root@СЕРВЕР 'chmod 600 /opt/movex_go/firebase-key.json'
```

**4. Прописать в `/opt/movex_go/.env`:**

```
FCM_PROJECT_ID=movex-go-12345
FCM_CREDENTIALS_FILE=/opt/movex_go/firebase-key.json
```

`FCM_PROJECT_ID` — поле `project_id` из того же JSON.

**5. Перезапустить сервис:**

```bash
systemctl restart movex-go
journalctl -u movex-go -n 20 | grep -i fcm
```

Если в логе нет строки «Push yuborilmaydi: FCM sozlanmagan» — ключи
подхватились.

**6. Для iOS дополнительно**: APNs-ключ (.p8) из Apple Developer загрузить в
Firebase Console → Cloud Messaging, и включить Push Notifications в Xcode.
Без этого push будет работать только на Android.

### Что останется сделать в мобилке

Когда файлы из шага 2 будут на месте:

1. Положить `google-services.json` → `mobile/android/app/`,
   `GoogleService-Info.plist` → `mobile/ios/Runner/`.
2. В `mobile/pubspec.yaml` вернуть:
   ```yaml
   firebase_core: ^3.6.0
   firebase_messaging: ^15.1.3
   ```
3. В `mobile/android/settings.gradle.kts` — плагин
   `com.google.gms.google-services`.
4. В `main()` после `Firebase.initializeApp()`:
   ```dart
   final messaging = FirebaseMessaging.instance;
   await messaging.requestPermission();
   final token = await messaging.getToken();
   if (token != null) {
     await NotificationService().registerDevice(
       token, Platform.isIOS ? 'ios' : 'android');
   }
   ```
   При выходе из аккаунта — `unregisterDevice(token)`, иначе push продолжит
   приходить прежнему владельцу телефона.

Эти шаги не сделаны заранее намеренно: `google-services.json` нужен уже во
время сборки Android, и без него сборка падает с невнятной ошибкой.

### Как устроена отправка

Токен доступа получается по стандартной схеме сервисного аккаунта: JWT,
подписанный ключом (RS256), меняется на access token, который живёт час и
кэшируется в памяти. Отдельная библиотека `google-auth` не нужна —
`python-jose` в проекте уже есть.

Два правила, заложенные в код:

- **Push никогда не ломает основное действие.** Заказ создан, а push не ушёл
  — это не повод откатывать заказ. Все ошибки проглатываются и попадают
  только в лог.
- **Мёртвые токены удаляются.** На ответ 404 `UNREGISTERED` (приложение
  удалили) или 400 `INVALID_ARGUMENT` запись из `device_tokens` стирается,
  иначе на каждое уведомление уходил бы бесполезный запрос.

Уведомления, создаваемые пачкой (заявка уходит сразу нескольким владельцам),
шлют push через `notification_service.send_pending` — уже после `commit`.
Иначе push ушёл бы о записи, которой ещё нет в базе.
