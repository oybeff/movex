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

Зарезервированы, но пока не рассылаются: `balance_topup`, `payout_paid`,
`payout_rejected`, `system`.

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

Проверка: `venv/bin/python tests/verify_notifications.py` — 23 теста.

## Push: что осталось сделать

Серверная часть готова — токены устройств принимаются и хранятся в
`device_tokens`. Не хватает только Firebase, потому что для него нужны файлы
из вашего проекта Firebase, которых у меня нет.

Порядок подключения:

1. Создать проект в Firebase Console, добавить два приложения с идентификатором
   `uz.movexgo.app` (Android и iOS).
2. Скачать `google-services.json` → `mobile/android/app/`
   и `GoogleService-Info.plist` → `mobile/ios/Runner/`.
3. В `mobile/android/app/build.gradle.kts` добавить плагин
   `com.google.gms.google-services`, а в корневой `build.gradle.kts` —
   зависимость classpath.
4. Вернуть в `pubspec.yaml`:
   ```yaml
   firebase_core: ^3.6.0
   firebase_messaging: ^15.1.3
   ```
5. В `main()` вызвать `Firebase.initializeApp()`, запросить разрешение на
   уведомления и отправить токен:
   ```dart
   final token = await FirebaseMessaging.instance.getToken();
   if (token != null) {
     await NotificationService().registerDevice(token, Platform.isIOS ? 'ios' : 'android');
   }
   ```
   При выходе из аккаунта — `unregisterDevice(token)`, иначе push будет
   приходить прежнему владельцу телефона.
6. Для iOS дополнительно: APNs-ключ в Firebase Console и включённая
   возможность Push Notifications в Xcode.
7. На сервере: добавить отправку через FCM в `notification_service.create` —
   после сохранения в базу разослать на все `device_tokens` пользователя.
   Ключ сервера положить в `.env` как `FCM_SERVER_KEY`.

Пока шаг 7 не сделан, уведомления видны только при открытом приложении —
это рабочее состояние, просто без всплывающих сообщений.
