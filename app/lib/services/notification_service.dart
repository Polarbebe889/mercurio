// notification_service.dart — push reales vía FCM + fallback local.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api.dart';
import '../app_state.dart';

@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  // No toques AppState aquí (isolate). Solo log.
  debugPrint('[FCM] background ${message.notification?.title}');
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    // Local notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false);
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (r) => debugPrint('[Local] tap ${r.payload}'),
    );
    // Permiso Android 13+ / iOS
    if (Platform.isAndroid) {
      final st = await Permission.notification.status;
      if (!st.isGranted) await Permission.notification.request();
    } else if (Platform.isIOS) {
      await _local.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
    }
    // Firebase (opcional — si no hay google-services.json, hace no-op)
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
      // Foreground: muestra local también
      FirebaseMessaging.onMessage.listen((msg) async {
        final n = msg.notification;
        await showLocal(n?.title ?? 'Mercurio', n?.body ?? '', payload: msg.data['type'] ?? '');
      });
      // Token → backend
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _enviarToken(token);
        // refresh
        FirebaseMessaging.instance.onTokenRefresh.listen(_enviarToken);
      }
      // Permiso iOS FCM
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      _ready = true;
      debugPrint('[FCM] listo token ${token?.substring(0, 12)}...');
    } catch (e) {
      debugPrint('[FCM] no configurado (falta google-services.json): $e — solo WS/local');
    }
  }

  Future<void> _enviarToken(String token) async {
    try {
      final api = AppState.instance.api;
      if (api == null) return;
      final plat = Platform.isIOS ? 'ios' : Platform.isAndroid ? 'android' : 'web';
      // usa Api._h interno vía endpoint directo
      await api.registrarFcmToken(token, plat);
      debugPrint('[FCM] token registrado $plat');
    } catch (e) {
      debugPrint('[FCM] registro fallo: $e');
    }
  }

  Future<void> showLocal(String titulo, String cuerpo, {String? payload}) async {
    if (!_ready) {
      // intenta inicializar si no se hizo
      try { await init(); } catch (_) {}
    }
    const androidDetails = AndroidNotificationDetails(
      'mercurio_general',
      'Mercurio',
      channelDescription: 'Notificaciones de Mercurio: drops, voz, planes, música',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    const iosDetails = DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true);
    await _local.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      titulo,
      cuerpo,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  // Llamado desde AppState._onEvento para cada WS
  Future<void> onWsEvent(Map<String, dynamic> ev) async {
    final t = ev['type'] as String? ?? '';
    final banner = AppState.instance.bannerDe(ev);
    if (banner == null) return;
    String titulo = 'Mercurio';
    String cuerpo = banner;
    // personaliza por tipo
    switch (t) {
      case 'drop.nuevo': titulo = '📸 Drop nuevo'; break;
      case 'voz.nueva': titulo = '🎙️ Historia nueva'; break;
      case 'pin.audio.nuevo': titulo = '📌 Pin de audio'; break;
      case 'plan.nuevo': titulo = '📅 Plan nuevo'; break;
      case 'plan.impulso_push': titulo = '🚗 En camino'; break;
      case 'musica.actualizada': titulo = '🎵 Sonando'; break;
      case 'partida.nueva': titulo = '🏆 Reta'; break;
      case 'status.actualizado': titulo = '💬 Estado'; break;
    }
    await showLocal(titulo, cuerpo, payload: t);
  }
}
