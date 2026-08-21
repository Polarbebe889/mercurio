import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/dashboard_premium.dart';
import 'screens/login_screen.dart';
import 'services/notification_service.dart';
import 'theme/uranio_premium_theme.dart';

final AppState app = AppState.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Notificaciones (FCM + local) — no bloquea el arranque si Firebase no está configurado
  try {
    await NotificationService.instance.init();
  } catch (_) {}
  final tieneSesion = await app.cargarSesion();
  if (tieneSesion) {
    await app.iniciarSesion();
  }
  // Re-intenta registro FCM si ya hay sesión (el token se obtiene async)
  if (tieneSesion) {
    try {
      await NotificationService.instance.init();
    } catch (_) {}
  }
  runApp(ElBunkerApp(arrancandoConSesion: tieneSesion));
}

class ElBunkerApp extends StatefulWidget {
  final bool arrancandoConSesion;
  const ElBunkerApp({super.key, required this.arrancandoConSesion});

  @override
  State<ElBunkerApp> createState() => _ElBunkerAppState();
}

class _ElBunkerAppState extends State<ElBunkerApp> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => MaterialApp(
        title: 'Mercurio',
        debugShowCheckedModeBanner: false,
        theme: UranioPremiumTheme.dark,
        // Login persistente: si hay token -> Dashboard, si no -> Login minimalista
        home: app.token == null ? const LoginScreen() : const DashboardPremium(),
      ),
    );
  }
}