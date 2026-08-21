import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../main.dart';
import '../models.dart';

class DropsScreen extends StatefulWidget {
  const DropsScreen({super.key});

  @override
  State<DropsScreen> createState() => _DropsScreenState();
}

class _DropsScreenState extends State<DropsScreen> {
  final _picker = ImagePicker();

  Future<void> _subir() async {
    final foto = await _picker.pickImage(source: ImageSource.gallery);
    if (foto == null || !mounted) return;
    final caption = await _pedirCaption();
    if (caption == null) return;
    try {
      await app.api!.subirDrop(File(foto.path), caption);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<String?> _pedirCaption() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Caption del drop'),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
                hintText: 'ej: la vista de hoy')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Solo foto')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Soltar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        return Scaffold(
          body: Stack(
            children: [
              RefreshIndicator(
                onRefresh: () async => app.recargarTodo(),
                child: app.drops.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 200),
                          Center(
                            child: Text('Aún no hay drops\nsuéltate al primero',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white38)),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: app.drops.length,
                        itemBuilder: (context, i) => _DropCard(app.drops[i]),
                      ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.extended(
                  heroTag: 'drop_btn',
                  onPressed: _subir,
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Drop'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DropCard extends StatelessWidget {
  final Drop drop;
  const _DropCard(this.drop);

  @override
  Widget build(BuildContext context) {
    final autor = app.usuarioPorId(drop.usuarioId);
    final soy = autor?.id == app.yo?.id;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.network(
            AppConfig.fullUrl(drop.imgUrl),
            height: 260,
            fit: BoxFit.cover,
            width: double.infinity,
            loadingBuilder: (c, child, p) => p == null
                ? child
                : Container(
                    height: 260,
                    color: const Color(0xFF1C2125),
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2))),
            errorBuilder: (_, __, ___) => Container(
              height: 260,
              color: const Color(0xFF1C2125),
              child: const Center(child: Icon(Icons.broken_image, color: Colors.white24)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Text('${autor?.emoji ?? '🫡'} ${autor?.displayName ?? 'alguien'}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(_hace(drop.created),
                  style: TextStyle(fontSize: 11, color: Colors.white38)),
              if (soy) ...[
                const SizedBox(width: 8),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  onPressed: () => app.api!.borrarDrop(drop.id),
                ),
              ],
            ]),
          ),
          if (drop.caption?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(drop.caption!,
                  style: const TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }

  String _hace(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'ahora';
    if (d.inHours < 1) return 'hace ${d.inMinutes}m';
    if (d.inDays < 1) return 'hace ${d.inHours}h';
    return 'hace ${d.inDays}d';
  }
}