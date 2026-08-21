import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../main.dart';

/// Push para Apple Music — Android MediaSession + iOS MPMusicPlayerController.
/// Solo se activa en el dispositivo que usa Apple Music (1 de los 6).
/// Los 5 de Spotify no tocan nada (polling en servidor).
class AppleMusicPush {
  static const _ch = MethodChannel('mercurio/music');
  static bool _iniciado = false;

  static Future<void> iniciar() async {
    if (_iniciado) return;
    _iniciado = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onTrackChanged') {
        final m = Map<String, dynamic>.from(call.arguments as Map);
        await _push(m);
      }
    });
    try {
      await _ch.invokeMethod('startListening');
    } catch (_) {
      // en iOS/Android sin código nativo aún, es no-op; no crashea
    }
    // fallback polling ligero solo para Apple Music (cada 8s) si no hay nativo
    if (Platform.isAndroid) {
      Timer.periodic(const Duration(seconds: 8), (_) async {
        try {
          final r = await _ch.invokeMethod<Map>('getCurrentTrack');
          if (r != null) await _push(Map<String, dynamic>.from(r));
        } catch (_) {}
      });
    }
  }

  static Future<void> _push(Map<String, dynamic> m) async {
    final api = app.api;
    if (api == null) return;
    try {
      await api.setMusica('music_kit', (m['titulo'] ?? m['track'] ?? '').toString(),
          (m['artista'] ?? m['artist'] ?? '').toString(), (m['album'] ?? '').toString(), true);
    } catch (_) {}
  }

  /// Llamado desde DashboardPremium al tocar la tarjeta de música en iOS
  static Future<void> pushManual(String titulo, String artista) async {
    final api = app.api;
    if (api == null) return;
    await api.setMusica('music_kit', titulo, artista, '', true);
  }
}
