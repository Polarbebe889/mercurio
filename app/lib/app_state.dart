/// Estado global de la app (ChangeNotifier) + manejo de eventos WS.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'ws_manager.dart';

class AppState extends ChangeNotifier {
  String? token;
  Usuario? yo;
  bool conectado = false;
  String? fallo; // mensaje de error para la UI (registro, etc.)

  List<Usuario> usuarios = [];
  List<Drop> drops = [];
  List<NotaVoz> historias = [];
  List<PinAudio> pines = [];
  List<Partida> partidas = [];
  List<RankingRow> ranking = [];
  List<Plan> planes = [];

  List<Map<String, dynamic>> eventos = []; // evento WS más recientes para banners
  WsManager? ws;

  Api? get api => token == null ? null : Api(token!);

  /// Devuelve `true` si ya hay sesión guardada.
  Future<bool> cargarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
    return token != null;
  }

  Future<void> guardarToken(String t) async {
    token = t;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', t);
    _conectarWs();
    await recargarTodo();
    notifyListeners();
  }

  Future<void> cerrarSesion() async {
    ws?.cerrar();
    ws = null;
    token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    usuarios = [];
    notifyListeners();
  }

  void _conectarWs() {
    ws?.cerrar();
    ws = WsManager(
      token!,
      onEvent: _onEvento,
      onEstado: (c) {
        conectado = c;
        notifyListeners();
      },
    )..conectar();
  }

  /// Conecta WS + carga inicial (tras arranque con sesión guardada).
  Future<void> iniciarSesion() async {
    if (token == null) return;
    _conectarWs();
    try {
      await recargarTodo();
    } catch (e) {
      fallo = e.toString();
    }
    notifyListeners();
  }

  Future<void> recargarTodo() async {
    final a = api!;
    final yoJson = await a.me();
    yo = Usuario.fromJson(yoJson);
    await Future.wait([
      _cargarLobby(a),
      _cargarDrops(a),
      _cargarVoz(a),
      _cargarPartidas(a),
      _cargarPlanes(a),
    ]);
  }

  Future<void> _cargarLobby(Api a) async {
    final lista = await a.lobby();
    usuarios = lista.map((e) => Usuario.fromJson(e as Map<String, dynamic>)).toList();
    usuarios.sort((x, y) => x.displayName.compareTo(y.displayName));
  }

  Future<void> _cargarDrops(Api a) async {
    drops = (await a.drops())
        .map((e) => Drop.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _cargarVoz(Api a) async {
    historias = (await a.historias())
        .map((e) => NotaVoz.fromJson(e as Map<String, dynamic>))
        .toList();
    pines = (await a.pines())
        .map((e) => PinAudio.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _cargarPartidas(Api a) async {
    partidas = (await a.partidas())
        .map((e) => Partida.fromJson(e as Map<String, dynamic>))
        .toList();
    ranking = (await a.ranking())
        .map((e) => RankingRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _cargarPlanes(Api a) async {
    planes = (await a.planes())
        .map((e) => Plan.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── eventos en vivo ─────────────────────────────────────────────
  void _onEvento(Map<String, dynamic> ev) {
    eventos.insert(0, ev);
    if (eventos.length > 5) eventos.removeLast();
    switch (ev['type']) {
      case 'status.actualizado':
        _patchUsuario(ev['usuario'] as Map<String, dynamic>);
      case 'musica.actualizada':
        for (var i = 0; i < usuarios.length; i++) {
          if (usuarios[i].id == ev['usuario_id']) {
            usuarios[i] = _usuarioConMusica(usuarios[i], ev['musica']);
          }
        }
      case 'musica.detenida':
        for (var i = 0; i < usuarios.length; i++) {
          if (usuarios[i].id == ev['usuario_id']) {
            usuarios[i] = _usuarioSinMusica(usuarios[i]);
          }
        }
      case 'drop.nuevo':
        drops.insert(0, Drop.fromJson(ev['drop'] as Map<String, dynamic>));
      case 'drop.borrado':
        drops.removeWhere((d) => d.id == ev['drop_id']);
      case 'voz.nueva':
        historias.insert(0, NotaVoz.fromJson(ev['nota'] as Map<String, dynamic>));
      case 'voz.borrada':
        historias.removeWhere((n) => n.id == ev['nota_id']);
      case 'voz.expiradas':
        final ids = (ev['nota_ids'] as List? ?? []).toSet();
        historias.removeWhere((n) => ids.contains(n.id));
      case 'pin.audio.nuevo':
        pines.insert(0, PinAudio.fromJson(ev['pin'] as Map<String, dynamic>));
      case 'pin.audio.borrado':
        pines.removeWhere((p) => p.id == ev['pin_id']);
      case 'partida.nueva':
        partidas.insert(0, Partida.fromJson(ev['partida'] as Map<String, dynamic>));
      case 'partida.reaccion':
        final p = Partida.fromJson(ev['partida'] as Map<String, dynamic>);
        final i = partidas.indexWhere((x) => x.id == p.id);
        if (i >= 0) partidas[i] = p;
      case 'plan.nuevo':
        planes.insert(0, Plan.fromJson(ev['plan'] as Map<String, dynamic>));
      case 'plan.estado':
        _patchPlanEstado(ev);
      case 'plan.impulso_push':
        // Alguien está en camino → banner en la UI.
        break;
    }
    notifyListeners();
  }

  void _patchUsuario(Map<String, dynamic> j) {
    final u = Usuario.fromJson(j);
    final i = usuarios.indexWhere((x) => x.id == u.id);
    if (i >= 0) {
      final viejo = usuarios[i];
      usuarios[i] = Usuario(u.id, u.username, u.displayName, u.emoji,
          u.avatarColor, u.elo, u.statusText, viejo.musica, viejo.notasVoz);
      if (yo != null && yo!.id == u.id) {
        yo = Usuario(u.id, u.username, u.displayName, u.emoji, u.avatarColor,
            u.elo, u.statusText, viejo.musica, viejo.notasVoz);
      }
    } else {
      usuarios.add(u);
    }
  }

  Usuario _usuarioConMusica(Usuario u, Map<String, dynamic>? m) => Usuario(
      u.id, u.username, u.displayName, u.emoji, u.avatarColor, u.elo,
      u.statusText, m == null ? null : Musica.fromJson(m), u.notasVoz);

  Usuario _usuarioSinMusica(Usuario u) => Usuario(
      u.id, u.username, u.displayName, u.emoji, u.avatarColor, u.elo,
      u.statusText, null, u.notasVoz);

  void _patchPlanEstado(Map<String, dynamic> ev) {
    final planId = ev['plan_id'] as int;
    final u = ev['usuario'] as Map<String, dynamic>;
    for (var i = 0; i < planes.length; i++) {
      if (planes[i].id == planId) {
        final p = planes[i];
        final estados = [...p.estados];
        estados.removeWhere((e) => e.usuarioId == u['id']);
        estados.add(PlanEstado(u['id'] as int, u['estado'] as String));
        planes[i] = Plan(p.id, p.creadorId, p.titulo, p.descripcion, p.lugar,
            p.startsAt, estados);
      }
    }
  }

  Usuario? usuarioPorId(int id) {
    for (var u in usuarios) {
      if (u.id == id) return u;
    }
    return null;
  }

  /// Banner humano para el evento WS (para la UI).
  String? bannerDe(Map<String, dynamic> ev) {
    final tipo = ev['type'] as String? ?? '';
    final nombre = switch (tipo) {
      'drop.nuevo' => _nombreDe(ev, 'drop', 'autor'),
      'voz.nueva' => _nombreDe(ev, 'nota', 'autor'),
      'pin.audio.nuevo' => _nombreDe(ev, 'pin', 'autor'),
      'musica.actualizada' => _nombreDe(ev, null, null),
      'plan.estado' => _nombreDe(ev, null, 'usuario'),
      'plan.impulso_push' => _nombreDe(ev, null, 'usuario'),
      _ => null,
    };
    if (nombre == null) {
      return switch (tipo) {
        'drop.nuevo' => 'Nuevo drop en el muro',
        'voz.nueva' => 'Nueva historia de voz',
        'pin.audio.nuevo' => 'Nuevo pin de audio',
        'musica.actualizada' => 'Alguien cambió la música',
        'plan.estado' => 'Alguien tocó un botón del plan',
        'plan.impulso_push' => '¡Alguien va en camino!',
        _ => null,
      };
    }
    return switch (tipo) {
      'drop.nuevo' => '$nombre soltó un drop',
      'voz.nueva' => '$nombre grabó una historia',
      'pin.audio.nuevo' => '$nombre fijó un audio',
      'plan.estado' => '$nombre: ${ev['usuario']?['estado'] ?? ''}',
      'plan.impulso_push' => '$nombre va en camino',
      _ => null,
    };
  }

  String? _nombreDe(Map<String, dynamic> ev, String? clave, String? autorClave) {
    Map<String, dynamic>? obj;
    if (clave != null && ev[clave] is Map) {
      obj = ev[clave] as Map<String, dynamic>;
    }
    final autor = autorClave != null ? ev[autorClave] : null;
    final n = (autor is Map ? autor['display_name'] : null) ??
        (obj?['display_name']);
    return n is String ? n : null;
  }
}