import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';

class PartidasScreen extends StatefulWidget {
  const PartidasScreen({super.key});

  @override
  State<PartidasScreen> createState() => _PartidasScreenState();
}

class _PartidasScreenState extends State<PartidasScreen> {
  int? _contrincanteId;
  final _m1 = TextEditingController(text: '0');
  final _m2 = TextEditingController(text: '0');
  final _juego = TextEditingController(text: '1v1');
  bool _enviando = false;

  @override
  void dispose() {
    _m1.dispose();
    _m2.dispose();
    _juego.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    final c = _contrincanteId;
    if (c == null) {
      _snack('Elige rival');
      return;
    }
    setState(() => _enviando = true);
    try {
      final p = await app.api!.registrarPartida(
          c, int.tryParse(_m1.text) ?? 0, int.tryParse(_m2.text) ?? 0,
          _juego.text.trim());
      _snack('Registrada: ${p['juego']} ${p['marcador1']}-${p['marcador2']}');
      await app.recargarTodo();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final otros = app.usuarios.where((u) => u.id != app.yo?.id).toList();
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [Tab(text: 'Retas'), Tab(text: 'Ranking')],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    RefreshIndicator(
                      onRefresh: () async => app.recargarTodo(),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text('Registra tu reta',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<int>(
                                    initialValue: _contrincanteId,
                                    hint: const Text('¿Contra quién?'),
                                    items: [
                                      for (final u in otros)
                                        DropdownMenuItem(
                                            value: u.id,
                                            child: Text(
                                                '${u.emoji} ${u.displayName} (Elo ${u.elo})')),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _contrincanteId = v),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Expanded(
                                        child: TextField(
                                            controller: _m1,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                                labelText: 'Tú'))),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 12),
                                      child: Text('—'),
                                    ),
                                    Expanded(
                                        child: TextField(
                                            controller: _m2,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                                labelText: 'Rival'))),
                                  ]),
                                  const SizedBox(height: 12),
                                  TextField(
                                      controller: _juego,
                                      decoration: const InputDecoration(
                                          labelText: 'Juego')),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed: _enviando ? null : _registrar,
                                    child: _enviando
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Text('Guardar reta'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (app.partidas.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 60),
                              child: Center(
                                child: Text('Aún no hay retas',
                                    style: TextStyle(color: Colors.white38)),
                              ),
                            ),
                          for (final p in app.partidas) _PartidaCard(p),
                        ],
                      ),
                    ),
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Card(
                          child: Column(
                            children: [
                              for (var i = 0; i < app.ranking.length; i++)
                                _RankingRowCard(app.ranking[i], i),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PartidaCard extends StatelessWidget {
  final Partida p;
  const _PartidaCard(this.p);

  @override
  Widget build(BuildContext context) {
    final ganoYo1 = p.j1.id == app.yo?.id;
    final miElo = ganoYo1 ? p.j1.eloFinal : p.j2.eloFinal;
    final cambio = miElo - (ganoYo1 ? p.j1.elo : p.j2.elo);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(
          cambio > 0
              ? Icons.trending_up
              : cambio < 0
                  ? Icons.trending_down
                  : Icons.trending_flat,
          color: cambio > 0
              ? const Color(0xFF4ADE80)
              : cambio < 0
                  ? const Color(0xFFF87171)
                  : Colors.white38,
        ),
        title: Text('${p.j1.displayName} ${p.marcador1} — ${p.marcador2} ${p.j2.displayName}'),
        subtitle: Text(
            '${p.juego} · ${p.j1.elo} → ${p.j1.eloFinal} · ${p.j2.elo} → ${p.j2.eloFinal}',
            style: const TextStyle(fontSize: 12)),
        trailing: p.reactionAudio != null
            ? const Icon(Icons.volume_up, size: 18)
            : null,
      ),
    );
  }
}

class _RankingRowCard extends StatelessWidget {
  final RankingRow f;
  final int i;
  const _RankingRowCard(this.f, this.i);

  @override
  Widget build(BuildContext context) {
    final soy = f.id == app.yo?.id;
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 28,
        child: Text('${i + 1}º',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: i == 0 ? Colors.amberAccent : Colors.white70)),
      ),
      title: Text('${f.emoji} ${f.displayName}${soy ? ' (tú)' : ''}',
          style: TextStyle(fontWeight: soy ? FontWeight.w700 : FontWeight.w400)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${f.victorias}V/${f.empates}E/${f.derrotas}D',
              style: TextStyle(fontSize: 11, color: Colors.white38)),
          const SizedBox(width: 10),
          Text('${f.elo}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.amberAccent)),
        ],
      ),
    );
  }
}