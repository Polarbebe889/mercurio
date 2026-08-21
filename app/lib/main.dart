import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/dashboard_screen.dart';
import 'screens/registro.dart';
import 'theme/uranio_theme.dart';

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
        theme: UranioTheme.dark,
        home: app.token == null ? const RegistroScreen() : const DashboardScreen(),
      ),
    );
  }
}