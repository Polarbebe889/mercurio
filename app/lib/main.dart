import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/dashboard_premium.dart';
import 'screens/login_screen.dart';
import 'theme/uranio_premium_theme.dart';

final AppState app = AppState();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final tieneSesion = await app.cargarSesion();
  if (tieneSesion) {
    await app.iniciarSesion();
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