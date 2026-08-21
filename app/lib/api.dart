/// Cliente HTTP del API de El Bunker (multipart para subidas).

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'config.dart';

class ApiError implements Exception {
  final int status;
  final String message;
  ApiError(this.status, this.message);
  @override
  String toString() => message;
}

class Api {
  final String _token;
  Api(this._token);

  Map<String, String> get _h => {'x-token': _token};

  Future<Map<String, dynamic>> _send(
      Future<http.Response> Function() fn) async {
    final r = await fn();
    if (r.statusCode >= 400) {
      String msg = 'Error ${r.statusCode}';
      try {
        final j = jsonDecode(r.body);
        if (j is Map && j['detail'] is String) msg = j['detail'] as String;
      } catch (_) {}
      throw ApiError(r.statusCode, msg);
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  // ── auth / lobby ────────────────────────────────────────────────
  Future<Map<String, dynamic>> me() =>
      _send(() => http.get(Uri.parse('${AppConfig.apiBase}/auth/me'), headers: _h));

  Future<List<dynamic>> lobby() => _send(
      () => http.get(Uri.parse('${AppConfig.apiBase}/lobby'), headers: _h))
          .then((j) => j['usuarios'] as List);

  Future<void> setStatus(String texto) => _send(() => http.put(
      Uri.parse('${AppConfig.apiBase}/lobby/me/estado'),
      headers: {..._h, 'content-type': 'application/json'},
      body: jsonEncode({'status_text': texto})));

  // ── música ──────────────────────────────────────────────────────
  Future<void> setMusica(String provider, String titulo, String artista,
          String album, bool reproduciendo) =>
      _send(() => http.put(
          Uri.parse('${AppConfig.apiBase}/musica/me'),
          headers: {..._h, 'content-type': 'application/json'},
          body: jsonEncode({
            'provider': provider,
            'titulo': titulo,
            'artista': artista,
            'album': album,
            'reproduciendo': reproduciendo,
          })));

  Future<void> detenerMusica() => _send(
      () => http.delete(Uri.parse('${AppConfig.apiBase}/musica/me'), headers: _h));

  // ── drops ───────────────────────────────────────────────────────
  Future<List<dynamic>> drops() => _send(
      () => http.get(Uri.parse('${AppConfig.apiBase}/drops'), headers: _h))
          .then((j) => j as List);

  Future<Map<String, dynamic>> subirDrop(File foto, String caption) {
    final req = http.MultipartRequest(
        'POST', Uri.parse('${AppConfig.apiBase}/drops'))
      ..headers.addAll(_h)
      ..files.add(http.MultipartFile.fromBytes(
          'file', foto.readAsBytesSync(),
          filename: 'foto.jpg'))
      ..fields['caption'] = caption;
    return _send(() => req.send().then(http.Response.fromStream));
  }

  Future<void> borrarDrop(int id) =>
      _send(() => http.delete(Uri.parse('${AppConfig.apiBase}/drops/$id'), headers: _h));

  // ── voz ─────────────────────────────────────────────────────────
  Future<List<dynamic>> historias() => _send(
      () => http.get(Uri.parse('${AppConfig.apiBase}/voz/historias'), headers: _h))
          .then((j) => j as List);

  Future<List<dynamic>> pines() => _send(
      () => http.get(Uri.parse('${AppConfig.apiBase}/voz/pines'), headers: _h))
          .then((j) => j as List);

  Future<Map<String, dynamic>> subirHistoria(File audio, int durationS) {
    final req = http.MultipartRequest(
        'POST', Uri.parse('${AppConfig.apiBase}/voz/historias'))
      ..headers.addAll(_h)
      ..files.add(http.MultipartFile.fromBytes(
          'file', audio.readAsBytesSync(),
          filename: 'voz.m4a', contentType: MediaType('audio', 'mp4')))
      ..fields['duration_s'] = '$durationS';
    return _send(() => req.send().then(http.Response.fromStream));
  }

  Future<Map<String, dynamic>> subirPin(File audio, String caption, int durationS) {
    final req = http.MultipartRequest(
        'POST', Uri.parse('${AppConfig.apiBase}/voz/pines'))
      ..headers.addAll(_h)
      ..files.add(http.MultipartFile.fromBytes(
          'file', audio.readAsBytesSync(),
          filename: 'pin.m4a', contentType: MediaType('audio', 'mp4')))
      ..fields['caption'] = caption
      ..fields['duration_s'] = '$durationS';
    return _send(() => req.send().then(http.Response.fromStream));
  }

  Future<void> borrarHistoria(int id) =>
      _send(() => http.delete(
          Uri.parse('${AppConfig.apiBase}/voz/historias/$id'),
          headers: _h));

  Future<void> borrarPin(int id) =>
      _send(() => http.delete(
          Uri.parse('${AppConfig.apiBase}/voz/pines/$id'), headers: _h));

  // ── partidas ────────────────────────────────────────────────────
  Future<Map<String, dynamic>> registrarPartida(
          int contrincanteId, int m1, int m2, String juego) =>
      _send(() => http.post(
          Uri.parse('${AppConfig.apiBase}/partidas'),
          headers: {..._h, 'content-type': 'application/json'},
          body: jsonEncode({
            'contrincante_id': contrincanteId,
            'marcador1': m1,
            'marcador2': m2,
            'juego': juego,
          })));

  Future<List<dynamic>> partidas() => _send(
      () => http.get(Uri.parse('${AppConfig.apiBase}/partidas'), headers: _h))
          .then((j) => j as List);

  Future<List<dynamic>> ranking() => _send(
      () => http.get(Uri.parse('${AppConfig.apiBase}/partidas/ranking'), headers: _h))
          .then((j) => j as List);

  // ── planes ──────────────────────────────────────────────────────
  Future<List<dynamic>> planes() => _send(
      () => http.get(Uri.parse('${AppConfig.apiBase}/planes'), headers: _h))
          .then((j) => j as List);

  Future<Map<String, dynamic>> crearPlan(String titulo, String lugar, DateTime cuando) =>
      _send(() => http.post(
          Uri.parse('${AppConfig.apiBase}/planes'),
          headers: {..._h, 'content-type': 'application/json'},
          body: jsonEncode({
            'titulo': titulo,
            'descripcion': '',
            'lugar': lugar,
            'starts_at': cuando.toIso8601String(),
          })));

  Future<void> setPlanEstado(int planId, String estado) =>
      _send(() => http.put(
          Uri.parse('${AppConfig.apiBase}/planes/$planId/estado'),
          headers: {..._h, 'content-type': 'application/json'},
          body: jsonEncode({'estado': estado})));
}