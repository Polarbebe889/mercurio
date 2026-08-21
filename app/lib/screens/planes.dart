import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';

class PlanesScreen extends StatefulWidget {
  const PlanesScreen({super.key});

  @override
  State<PlanesScreen> createState() => _PlanesScreenState();
}

class _PlanesScreenState extends State<PlanesScreen> {
  final _titulo = TextEditingController();
  final _lugar = TextEditingController();
  DateTime _cuando = DateTime.now().add(const Duration(hours: 2));
  bool _creando = false;

  @override
  void dispose() {
    _titulo.dispose();
    _lugar.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    if (_titulo.text.trim().isEmpty) return;
    setState(() => _creando = true);
    try {
      await app.api!.crearPlan(
          _titulo.text.trim(), _lugar.text.trim(), _cuando);
      _titulo.clear();
      _lugar.clear();
      await app.recargarTodo();
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _creando = false);
    }
  }

  Future<void> _estado(Plan p, String estado) async {
    try {
      await app.api!.setPlanEstado(p.id, estado);
      await app.recargarTodo();
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _cuando,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (fecha == null) return;
    final hora = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_cuando));
    if (hora == null) return;
    setState(() {
      _cuando = DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute);
    });
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Nuevo plan',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _titulo,
                      decoration: const InputDecoration(
                          labelText: '¿Qué hacemos?',
                          hintText: 'ej: Furros en casa de Ferxxo')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: _lugar,
                      decoration: const InputDecoration(
                          labelText: 'Dónde', hintText: 'ej: Casa Oscar')),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_fmt(_cuando)),
                    onPressed: _elegirFecha,
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: _creando ? null : _crear,
                    child: _creando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Armar plan'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => app.recargarTodo(),
              child: app.planes.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text('Sin planes todavía',
                              style: TextStyle(color: Colors.white38)),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: app.planes.length,
                      itemBuilder: (context, i) => _PlanCard(
                        plan: app.planes[i],
                        onEstado: _estado,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    final meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${meses[d.month - 1]} · $hh:$mm';
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final void Function(Plan, String) onEstado;
  const _PlanCard({required this.plan, required this.onEstado});

  static const _estados = [
    ('alistandome', 'Me alisto'),
    ('en_camino', 'En camino'),
    ('llegue', 'Llegué'),
  ];

  @override
  Widget build(BuildContext context) {
    final mio = plan.estadoDe(app.yo?.id ?? -1);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.flag, size: 16, color: Color(0xFF22D3EE)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(plan.titulo,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Text(_hace(plan.startsAt),
                  style: TextStyle(fontSize: 11, color: Colors.white38)),
            ]),
            if (plan.lugar?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text('📍 ${plan.lugar}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final (valor, etiqueta) in _estados)
                  ChoiceChip(
                    label: Text(etiqueta),
                    selected: mio == valor,
                    onSelected: (_) => onEstado(plan, valor),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: [
                for (final u in app.usuarios)
                  _estadoDeUsuario(u, plan.estadoDe(u.id)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _estadoDeUsuario(Usuario u, String e) {
    const iconos = {
      'alistandome': Icons.radio_button_unchecked,
      'en_camino': Icons.directions_walk,
      'llegue': Icons.check_circle,
    };
    final c = switch (e) {
      'alistandome' => Colors.white38,
      'en_camino' => const Color(0xFFFACC15),
      'llegue' => const Color(0xFF4ADE80),
      _ => Colors.white24,
    };
    return Tooltip(
      message: '${u.displayName}: $e',
      child: Column(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: c.withValues(alpha: .15),
          child: Icon(iconos[e] ?? Icons.help_outline, size: 16, color: c),
        ),
        const SizedBox(height: 2),
        Text(u.emoji, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }

  String _hace(DateTime t) {
    final d = t.difference(DateTime.now());
    if (d.isNegative) return 'ya inició';
    if (d.inMinutes < 60) return 'en ${d.inMinutes}m';
    if (d.inHours < 24) return 'en ${d.inHours}h';
    return 'en ${d.inDays}d';
  }
}