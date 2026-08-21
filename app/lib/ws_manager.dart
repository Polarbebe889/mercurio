/// WebSocket en vivo con reconexión automática (exponencial + tope).
///
/// La reconexión es importante en celular (el sistema mata la app de fondo).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config.dart';

class WsManager {
  final String token;
  final void Function(Map<String, dynamic> evento) onEvent;
  final void Function(bool conectado) onEstado;

  WsManager(this.token, {required this.onEvent, required this.onEstado});

  WebSocket? _ws;
  bool _cerrando = false;
  Timer? _reconT;
  int _intentos = 0;

  bool get conectado => _ws != null;

  void conectar() {
    _cerrando = false;
    _abrir();
  }

  Future<void> _abrir() async {
    try {
      final ws = await WebSocket.connect('${AppConfig.wsUrl}?token=$token');
      if (_cerrando) {
        ws.close();
        return;
      }
      _ws = ws;
      _intentos = 0;
      onEstado(true);
      ws.listen(
        (data) {
          try {
            onEvent(jsonDecode(data as String) as Map<String, dynamic>);
          } catch (_) {}
        },
        onDone: () => _perdida(),
        onError: (_) => _perdida(),
      );
    } catch (_) {
      _perdida();
    }
  }

  void _perdida() {
    _ws = null;
    onEstado(false);
    if (_cerrando) return;
    _intentos++;
    final espera = const [1, 2, 4, 8, 15].elementAt(
        _intentos > 4 ? 4 : _intentos);
    _reconT?.cancel();
    _reconT = Timer(Duration(seconds: espera), _abrir);
  }

  Future<void> cerrar() async {
    _cerrando = true;
    _reconT?.cancel();
    final ws = _ws;
    _ws = null;
    if (ws != null) await ws.close();
  }
}