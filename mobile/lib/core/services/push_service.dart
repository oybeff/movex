import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_flavor.dart';
import 'notification_service.dart';

/// Push через Firebase Cloud Messaging (только Android и iOS, в вебе молчит).
///
/// Сервер шлёт push на каждое уведомление из ленты (`notification_service`
/// на бэкенде), поэтому здесь только три вещи:
///   1. отдать токен устройства серверу, когда человек вошёл
///      (`syncToken`, зовут главные экраны), и забрать при выходе
///      (`unregister` — ДО удаления токена входа, иначе запрос уйдёт
///      без авторизации и push продолжит приходить прежнему владельцу);
///   2. показать уведомление, когда приложение открыто: в этом случае
///      Android сам его не рисует;
///   3. по нажатию открыть нужный экран (`onOpen`).
///
/// Ошибки глотаются: без push приложение работает как раньше (опрос раз
/// в 10–15 с на экранах заказов).
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  /// Канал Android. Имя совпадает с `channel_id` в push_service.py.
  static const _channel = AndroidNotificationChannel(
    'movex_orders',
    'Buyurtmalar',
    description: 'Yangi buyurtmalar va buyurtma holati',
    importance: Importance.high,
  );

  static const _prefsKey = 'push_token_sent';

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Куда вести по нажатию. Задаёт main.dart: data из push → маршрут.
  void Function(Map<String, dynamic> data)? onOpen;

  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> init() async {
    if (!_supported || _ready) return;
    try {
      await Firebase.initializeApp();
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null) onOpen?.call(_decode(p));
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpen?.call(m.data));
      FirebaseMessaging.instance.onTokenRefresh.listen((t) => _send(t, force: true));
      _ready = true;

      // Приложение было закрыто и открыто нажатием на push.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        // Роутер ещё строится — даём ему кадр.
        Future.delayed(const Duration(milliseconds: 800), () => onOpen?.call(initial.data));
      }
    } catch (e) {
      debugPrint('Push init: $e');
    }
  }

  /// Зовут главные экраны после входа: спросить разрешение и отдать токен.
  Future<void> syncToken() async {
    if (!_supported) return;
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _send(token);
    } catch (e) {
      debugPrint('Push token: $e');
    }
  }

  Future<void> _send(String token, {bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('token') == null) return; // не вошёл
    final key = '$token|${prefs.get('user_id') ?? ''}';
    if (!force && prefs.getString(_prefsKey) == key) return;
    await NotificationService().registerDevice(token, Platform.isIOS ? 'ios' : 'android');
    await prefs.setString(_prefsKey, key);
  }

  /// Выход из аккаунта. Звать ДО удаления токена входа.
  Future<void> unregister() async {
    if (!_supported || !_ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await NotificationService()
            .unregisterDevice(token)
            .timeout(const Duration(seconds: 5));
      }
    } catch (e) {
      debugPrint('Push unregister: $e');
    }
  }

  void _showForeground(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    // Водитель: экран входящего заказа и так откроется опросом —
    // всё равно показываем, звук важнее.
    _local.show(
      m.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          color: const Color(0xFF316DC8),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: _encode(m.data),
    );
  }

  static String _encode(Map<String, dynamic> d) =>
      d.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}').join('&');

  static Map<String, dynamic> _decode(String s) => Uri.splitQueryString(s);

  /// Маршрут по типу уведомления. Водительские события — на главную
  /// водителя (там список и входящий заказ), остальное — в ленту.
  static String routeFor(Map<String, dynamic> data) =>
      AppFlavor.isDriver ? '/driverHome' : '/notifications';
}
