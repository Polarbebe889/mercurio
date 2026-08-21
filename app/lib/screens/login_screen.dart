import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../main.dart';

/// Login ultra minimalista: solo Username + PIN 4 dígitos.
///
/// - Guarda `username` y `token` en shared_preferences vía AppState.guardarSesion.
/// - Si ya hay sesión, main.dart lo manda directo a DashboardPremium.
/// - Si reinstala y mete mismo username+PIN, recupera token (no crea fantasma).
/// - Usa join_code fijo BUNKER-6 para auto-registro.
/// - Añade validación elegante: username min 2 chars, PIN exactamente 4 dígitos.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _pin = TextEditingController();
  bool _cargando = false;
  bool _verPin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Precarga username guardado (si reinstaló pero prefs aún tiene? en reinstalación se borra, pero si hizo logout parcial)
    _username.text = app.username ?? '';
  }

  Future<void> _entrar() async {
    final u = _username.text.trim().toLowerCase();
    final p = _pin.text.trim();
    if (u.length < 2) {
      setState(() => _error = 'Username mínimo 2 caracteres');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(p)) {
      setState(() => _error = 'PIN debe ser 4 dígitos');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // Intenta login directo. Si no existe (404), auto-registra con BUNKER-6 y reintenta.
      final loginOk = await _tryLogin(u, p);
      if (!loginOk) {
        await _tryRegistro(u, p);
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').replaceFirst('ApiError: ', '');
        _cargando = false;
      });
    }
  }

  Future<bool> _tryLogin(String u, String p) async {
    final r = await http.post(
      Uri.parse('${AppConfig.apiBase}/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'username': u, 'pin': p}),
    );
    if (r.statusCode == 200) {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final token = j['token'] as String;
      await app.guardarSesion(token, u);
      if (mounted) setState(() => _cargando = false);
      return true;
    }
    if (r.statusCode == 404) return false; // no existe -> probar registro
    if (r.statusCode >= 400) {
      String msg = 'Error ${r.statusCode}';
      try {
        final j = jsonDecode(r.body);
        if (j is Map && j['detail'] is String) msg = j['detail'] as String;
      } catch (_) {}
      // Si es 401 PIN incorrecto, no intentes registro, lanza
      if (r.statusCode == 401) throw Exception(msg);
      // Para otros errores, si es "usuario no existe", permite registro
      if (msg.contains('no existe')) return false;
      throw Exception(msg);
    }
    return false;
  }

  Future<void> _tryRegistro(String u, String p) async {
    final r = await http.post(
      Uri.parse('${AppConfig.apiBase}/auth/registro'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'username': u,
        'display_name': u,
        'join_code': AppConfig.joinCode,
        'emoji': '🫡',
        'avatar_color': '#FFD60A',
        'pin': p,
      }),
    );
    if (r.statusCode == 200 || r.statusCode == 201) {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final token = j['token'] as String;
      await app.guardarSesion(token, u);
      if (mounted) setState(() => _cargando = false);
      return;
    }
    String msg = 'Error ${r.statusCode}';
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['detail'] is String) msg = j['detail'] as String;
    } catch (_) {}
    throw Exception(msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('MERCURIO',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFFFFF8E7),
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6)),
                  const SizedBox(height: 6),
                  const Text('entra con tu nombre y PIN',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF8A929A), fontSize: 13, letterSpacing: 1.2)),
                  const SizedBox(height: 36),
                  // Username
                  TextField(
                    controller: _username,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Username',
                      hintText: 'ej: ova',
                      hintStyle: const TextStyle(color: Color(0xFF8A929A)),
                      labelStyle: const TextStyle(color: Color(0xFF8A929A)),
                      filled: true,
                      fillColor: const Color(0xFF141414),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF8A929A)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // PIN 4 dígitos
                  TextField(
                    controller: _pin,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    obscureText: !_verPin,
                    style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 18, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: 'PIN 4 dígitos',
                      hintText: '••••',
                      hintStyle: const TextStyle(color: Color(0xFF8A929A), letterSpacing: 8),
                      labelStyle: const TextStyle(color: Color(0xFF8A929A)),
                      filled: true,
                      fillColor: const Color(0xFF141414),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF8A929A)),
                      suffixIcon: IconButton(
                        icon: Icon(_verPin ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF8A929A)),
                        onPressed: () => setState(() => _verPin = !_verPin),
                      ),
                    ),
                    onSubmitted: (_) => _entrar(),
                  ),
                  const SizedBox(height: 8),
                  const Text('Si ya tienes cuenta, usa tu mismo PIN para recuperar sesión.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF5A6270), fontSize: 11)),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _cargando ? null : _entrar,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFF8E7),
                      foregroundColor: const Color(0xFF050505),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _cargando
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF050505)))
                        : const Text('Entrar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFF1A0A0A), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3))),
                      child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                    ),
                  ],
                  const SizedBox(height: 28),
                  const Text('El mismo usuario + PIN en otro móvil recupera tu sesión.\nNo se crean cuentas fantasmas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF3A414D), fontSize: 10, height: 1.4)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
