import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../theme.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _statusCtrl = TextEditingController();

  @override
  void dispose() {
    _statusCtrl.dispose();
    super.dispose();
  }

  void _cambiarStatus() async {
    final t = _statusCtrl.text.trim();
    if (t.isEmpty) return;
    try {
      await app.api!.setStatus(t);
      _statusCtrl.clear();
      FocusScope.of(context).unfocus();
      await app.recargarTodo();
    } catch (e) {
      if (mounted) _snack('$e');
    }
  }

  void _abrirMusica(Usuario u, bool esYo) {
    final esOtra = u.musica != null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            top: 24,
            left: 24,
            right: 24),
        child: _MusicaSheet(
            musica: u.musica, esYo: esYo, esOtra: esOtra),
      ),
    );
  }

  void _snack(String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (app.usuarios.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final yo = app.usuarios.firstWhere((u) => u.id == app.yo?.id,
            orElse: () => app.usuarios.first);
        return RefreshIndicator(
          onRefresh: app.recargarTodo,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── tarjeta propia ──
              _tarjeta(yo, esYo: true),
              const SizedBox(height: 16),
              const Text('Los demás',
                  style: TextStyle(fontSize: 12, color: Colors.white54)),
              const SizedBox(height: 8),
              for (final u in app.usuarios)
                if (u.id != yo.id) ...[
                  _tarjeta(u, esYo: false),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 24),
              // ── qué estás haciendo ──
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _statusCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Qué estás haciendo…',
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onSubmitted: (_) => _cambiarStatus(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _cambiarStatus,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tarjeta(Usuario u, {required bool esYo}) {
    final tieneHistorias = u.notasVoz.isNotEmpty;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _abrirMusica(u, esYo),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // anillo de voz si tiene historias
              Container(
                width: 56,
                height: 56,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: tieneHistorias
                      ? Border.all(color: const Color(0xFF22D3EE), width: 3)
                      : null,
                ),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: colorBunker(u.avatarColor),
                  child: Text(u.emoji, style: const TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(u.displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      if (esYo) ...[
                        const SizedBox(width: 6),
                        const Text('(tú)',
                            style: TextStyle(
                                fontSize: 12, color: Colors.white38)),
                      ],
                    ]),
                    Text(
                      u.statusText?.isNotEmpty == true
                          ? u.statusText!
                          : 'sin status',
                      style: TextStyle(
                          fontSize: 13,
                          color: u.statusText != null
                              ? Colors.white70
                              : Colors.white38,
                          fontStyle: u.statusText != null
                              ? FontStyle.normal
                              : FontStyle.italic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (esYo) ...[
                      const SizedBox(height: 2),
                      Text('Elo ${u.elo}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.amberAccent)),
                    ],
                  ],
                ),
              ),
              _musicaMini(u.musica),
              const Icon(Icons.chevron_right, color: Colors.white30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _musicaMini(Musica? m) {
    if (m == null || m.titulo == null) {
      return const Icon(Icons.music_note, color: Colors.white24, size: 18);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(m.titulo!,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Text(m.artista ?? '',
            style: TextStyle(fontSize: 11, color: Colors.white54)),
        if (!m.reproduciendo)
          const Text('pausa',
              style: TextStyle(fontSize: 10, color: Colors.white38)),
      ],
    );
  }
}

class _MusicaSheet extends StatefulWidget {
  final Musica? musica;
  final bool esYo;
  final bool esOtra;
  const _MusicaSheet({required this.musica, required this.esYo, required this.esOtra});

  @override
  State<_MusicaSheet> createState() => _MusicaSheetState();
}

class _MusicaSheetState extends State<_MusicaSheet> {
  String _provider = 'spotify';
  late final TextEditingController _titulo =
      TextEditingController(text: widget.musica?.titulo ?? '');
  late final TextEditingController _artista =
      TextEditingController(text: widget.musica?.artista ?? '');
  late final TextEditingController _album =
      TextEditingController(text: widget.musica?.album ?? '');
  bool _play = true;
  bool _guardando = false;

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await app.api!.setMusica(
          _provider, _titulo.text.trim(), _artista.text.trim(),
          _album.text.trim(), _play);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.esYo
            ? 'Tu música'
            : widget.esOtra
                ? 'Está escuchando'
                : 'Sin música'),
        const SizedBox(height: 4),
        Text(
          widget.musica?.titulo != null
              ? '${widget.musica!.titulo} — ${widget.musica!.artista}'
              : 'nada por ahora',
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        if (widget.esYo) ...[
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'spotify', label: Text('Spotify')),
              ButtonSegment(value: 'music_kit', label: Text('Apple Music')),
            ],
            selected: {_provider},
            onSelectionChanged: (s) => setState(() => _provider = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
              controller: _titulo,
              decoration: const InputDecoration(labelText: 'Canción')),
          const SizedBox(height: 8),
          TextField(
              controller: _artista,
              decoration: const InputDecoration(labelText: 'Artista')),
          const SizedBox(height: 8),
          TextField(
              controller: _album,
              decoration: const InputDecoration(labelText: 'Álbum')),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reproduciendo'),
            value: _play,
            onChanged: (v) => setState(() => _play = v),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            child: const Text('Guardar'),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}