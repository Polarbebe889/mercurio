import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import '../config.dart';
import '../main.dart';

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

class _RegistroScreenState extends State<RegistroScreen> {
  final _username = TextEditingController();
  final _nombre = TextEditingController();
  final _codigo = TextEditingController(text: AppConfig.joinCode);
  bool _cargando = false;
  String? _error;
  String _emoji = '😎';
  String _color = '#22D3EE';

  static const _emojis = ['😎', '🔥', '🧊', '🤖', '👑', '🍕', '🎧', '💣'];
  static const _colores = ['#22D3EE', '#F87171', '#4ADE80', '#FACC15', '#C084FC', '#FB923C'];

  Future<void> _registrar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await http.post(
        Uri.parse('${AppConfig.apiBase}/auth/registro'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'username': _username.text.trim(),
          'display_name': _nombre.text.trim(),
          'join_code': _codigo.text.trim(),
          'emoji': _emoji,
          'avatar_color': _color,
        }),
      );
      if (r.statusCode >= 400) {
        String msg = 'Error ${r.statusCode}';
        try {
          final j = jsonDecode(r.body);
          if (j is Map && j['detail'] is String) msg = j['detail'] as String;
        } catch (_) {}
        throw ApiError(r.statusCode, msg);
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      await app.guardarToken(j['token'] as String);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('EL BUNKER',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4)),
                  const SizedBox(height: 4),
                  Text('entra al círculo',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _username,
                    decoration: const InputDecoration(
                        labelText: 'Username', hintText: 'ej: perro_rey'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nombre,
                    decoration: const InputDecoration(
                        labelText: 'Nombre de guerra',
                        hintText: 'ej: Ferxxo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _codigo,
                    decoration: const InputDecoration(
                        labelText: 'Código de invitación'),
                  ),
                  const SizedBox(height: 20),
                  Text('Avatar', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in _emojis)
                        ChoiceChip(
                          label: Text(e, style: const TextStyle(fontSize: 20)),
                          selected: _emoji == e,
                          onSelected: (_) => setState(() => _emoji = e),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final c in _colores)
                        InkWell(
                          onTap: () => setState(() => _color = c),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color.fromARGB(
                                  255,
                                  0xFF & (int.parse(c.substring(1, 3), radix: 16)),
                                  0xFF & (int.parse(c.substring(3, 5), radix: 16)),
                                  0xFF & (int.parse(c.substring(5, 7), radix: 16))),
                              shape: BoxShape.circle,
                              border: _color == c
                                  ? Border.all(color: Colors.white, width: 3)
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _cargando ? null : _registrar,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _cargando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Entrar al bunker',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.redAccent)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}