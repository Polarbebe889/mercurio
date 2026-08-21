import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/home.dart';
import 'screens/registro.dart';
import 'theme.dart';

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
        theme: temaBunker(),
        home: app.token == null ? const RegistroScreen() : const HomeScreen(),
      ),
    );
  }
}