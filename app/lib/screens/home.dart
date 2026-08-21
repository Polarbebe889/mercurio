import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import 'drops.dart';
import 'lobby.dart';
import 'partidas.dart';
import 'planes.dart';
import 'voz.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  Timer? _bannerT;
  String? _banner;

  @override
  void dispose() {
    _bannerT?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        // Banner del último evento en vivo relevante.
        final evento = app.eventos.isEmpty ? null : app.eventos.first;
        final banner = evento == null ? null : app.bannerDe(evento);
        if (banner != null && _banner != banner) {
          _banner = banner;
          _bannerT?.cancel();
          _bannerT = Timer(const Duration(seconds: 4), () {
            if (mounted && _banner == banner) {
              setState(() => _banner = null);
            }
          });
        }
        final pantallas = const [
          LobbyScreen(),
          DropsScreen(),
          VozScreen(),
          PartidasScreen(),
          PlanesScreen(),
        ];
        return Scaffold(
          appBar: AppBar(
            title: Row(children: [
              const Text('EL BUNKER',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(width: 10),
              if (app.conectado)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: Color(0xFF4ADE80), shape: BoxShape.circle),
                ),
              const Spacer(),
              if (app.yo != null)
                Text('${app.yo!.elo} pts',
                    style: TextStyle(color: Colors.amberAccent.shade200)),
              IconButton(
                tooltip: 'Cerrar sesión',
                icon: const Icon(Icons.logout, size: 20),
                onPressed: () => app.cerrarSesion(),
              ),
            ]),
            bottom: _banner != null
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(48),
                    child: Material(
                      color: const Color(0xFF22D3EE).withValues(alpha: .12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(children: [
                          const Icon(Icons.bolt, size: 18,
                              color: Color(0xFF22D3EE)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_banner!,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ]),
                      ),
                    ),
                  )
                : null,
          ),
          body: pantallas[_tab],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.groups), label: 'Lobby'),
              NavigationDestination(
                  icon: Icon(Icons.photo_camera), label: 'Drops'),
              NavigationDestination(
                  icon: Icon(Icons.mic), label: 'Voz'),
              NavigationDestination(
                  icon: Icon(Icons.emoji_events), label: 'Retas'),
              NavigationDestination(
                  icon: Icon(Icons.map), label: 'Planes'),
            ],
          ),
        );
      },
    );
  }
}