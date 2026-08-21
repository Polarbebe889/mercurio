import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../main.dart';
import '../config.dart';
import '../services/apple_music_push.dart';

enum MusicProvider { spotify, appleMusic }
class DummyMusic { final String user; final String track; final String artist; final MusicProvider provider; DummyMusic(this.user,this.track,this.artist,this.provider); }

class DashboardPremium extends StatefulWidget {
  const DashboardPremium({super.key});
  @override
  State<DashboardPremium> createState() => _DashboardPremiumState();
}

class _DashboardPremiumState extends State<DashboardPremium> {
  final _recorder = AudioRecorder();
  final _picker = ImagePicker();
  bool _grabando = false;
  DateTime? _inicio;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      app.recargarTodo();
      AppleMusicPush.iniciar();
    });
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleVoz() async {
    if (_grabando) {
      // parar y subir
      try {
        final path = await _recorder.stop();
        final secs = _inicio != null ? DateTime.now().difference(_inicio!).inSeconds.clamp(1, 600) : 2;
        setState(() { _grabando = false; _inicio = null; });
        if (path == null) return;
        final f = File(path);
        if (!await f.exists() || await f.length() == 0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Audio vacío')));
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Subiendo ${secs}s…')));
        await app.api!.subirHistoria(f, secs);
        await app.recargarTodo();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Historia subida ✓')));
      } catch (e) {
        setState(() { _grabando = false; });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error voz: $e')));
      }
      return;
    }
    // iniciar
    var status = await Permission.microphone.status;
    if (!status.isGranted) status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status.isPermanentlyDenied ? 'Micrófono bloqueado — abre Ajustes' : 'Micrófono denegado'),
        action: status.isPermanentlyDenied ? SnackBarAction(label: 'Ajustes', onPressed: () => openAppSettings()) : null,
      ));
      return;
    }
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin permiso de micrófono')));
      return;
    }
    try {
      final dir = Directory.systemTemp;
      final path = '${dir.path}/mercurio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100), path: path);
      setState(() { _grabando = true; _inicio = DateTime.now(); });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('● Grabando — toca de nuevo para enviar'), duration: Duration(seconds: 2)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo grabar: $e')));
    }
  }

  Future<void> _tomarFoto() async {
    var cam = await Permission.camera.status;
    if (!cam.isGranted) cam = await Permission.camera.request();
    if (!cam.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(cam.isPermanentlyDenied ? 'Cámara bloqueada — abre Ajustes' : 'Cámara denegada'),
        action: cam.isPermanentlyDenied ? SnackBarAction(label: 'Ajustes', onPressed: () => openAppSettings()) : null,
      ));
      return;
    }
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 92);
    if (x == null) return;
    final file = File(x.path);
    try {
      final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';
      final parts = mimeType.split('/');
      final uri = Uri.parse('${AppConfig.apiBase}/drops');
      final req = http.MultipartRequest('POST', uri);
      req.headers['x-token'] = app.token ?? '';
      req.files.add(await http.MultipartFile.fromPath('file', file.path, contentType: MediaType(parts[0], parts[1])));
      req.fields['caption'] = '';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subiendo foto…')));
      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        await app.recargarTodo();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Drop subido ✓')));
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error ${resp.statusCode}: ${resp.body}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error foto: $e')));
    }
  }

  BoxDecoration _cardDeco() => BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
      );

  Widget _heroCard({required String tag, required Widget child, required Widget detail}) {
    return Hero(
      tag: tag,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(context, PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 320),
            pageBuilder: (_,a,__) => FadeTransition(opacity: a, child: detail),
          )),
          child: Container(decoration: _cardDeco(), padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final usuarios = app.usuarios;
        final drops = app.drops;
        final lastDrop = drops.isNotEmpty ? drops.first : null;
        final lastDropUrl = lastDrop != null ? AppConfig.fullUrl(lastDrop.imgUrl) : null;

        final dummyMusic = [
          DummyMusic('Tú', 'Die For You', 'The Weeknd', MusicProvider.spotify),
          DummyMusic('Javier', 'DTMF', 'Bad Bunny', MusicProvider.appleMusic),
        ];

        return Scaffold(
          backgroundColor: const Color(0xFF050505),
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: const Color(0xFF050505),
                centerTitle: true,
                title: const Text('M E R C U R I O', style: TextStyle(color: Color(0xFFFFF8E7), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 8, fontFamily: 'Inter')),
                actions: [IconButton(icon: const Icon(Icons.logout, size: 16, color: Color(0xFF8A929A)), onPressed: () => app.cerrarSesion())],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList.list(children: [
                  Row(children: [
                    Expanded(child: _heroCard(
                      tag: 'lobby',
                      detail: _DetailScaffold(title: 'Lobby', child: Text('${usuarios.length} en el bunker', style: const TextStyle(color: Colors.white))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Row(children: [Icon(Icons.podcasts_rounded, size: 14, color: Color(0xFF8A929A)), SizedBox(width: 6), Text('LOBBY', style: TextStyle(color: Color(0xFF8A929A), fontSize: 10, letterSpacing: 1.2))]),
                        const SizedBox(height: 12),
                        SizedBox(height: 36, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: usuarios.length, separatorBuilder: (_,__)=>const SizedBox(width: 8), itemBuilder: (_,i){ final u=usuarios[i]; final hasVoz = app.historias.any((h)=>h.usuarioId==u.id); return Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: hasVoz?const Color(0xFFFFF8E7):Colors.transparent, width: 1.5)), child: CircleAvatar(radius: 18, backgroundColor: const Color(0xFF1A1A1A), child: Text(u.emoji, style: const TextStyle(fontSize: 16))));})),
                        const SizedBox(height: 8),
                        Text('${usuarios.length} conectados', style: const TextStyle(color: Color(0xFF8A929A), fontSize: 11)),
                      ]),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _heroCard(
                      tag: 'musica',
                      detail: const _DetailScaffold(title: 'Sonando ahora', child: Text('Música', style: TextStyle(color: Colors.white))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Row(children: [Icon(Icons.graphic_eq_rounded, size: 14, color: Color(0xFF8A929A)), SizedBox(width: 6), Text('SONANDO', style: TextStyle(color: Color(0xFF8A929A), fontSize: 10, letterSpacing: 1.2))]),
                        const SizedBox(height: 12),
                        ...dummyMusic.map((m)=> Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Container(width: 32,height: 32,decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(6)), child: Icon(m.provider==MusicProvider.spotify?Icons.circle:Icons.apple, size: 14, color: const Color(0xFF8A929A))),
                            const SizedBox(width: 8),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(m.track, maxLines: 1, style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12, fontWeight: FontWeight.w600)),
                              Text('${m.user} · ${m.artist}', maxLines: 1, style: const TextStyle(color: Color(0xFF8A929A), fontSize: 11)),
                            ])),
                          ]),
                        )),
                      ]),
                    )),
                  ]),
                  const SizedBox(height: 14),
                  // PROTAGONISTA
                  _heroCard(
                    tag: 'drop',
                    detail: _DetailScaffold(title: 'Drop', child: lastDropUrl!=null?InteractiveViewer(child: Image.network(lastDropUrl)):const Text('Sin drop', style: TextStyle(color: Colors.white))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        const Icon(Icons.camera_alt_rounded, size: 14, color: Color(0xFF8A929A)),
                        const SizedBox(width: 6),
                        const Text('ÚLTIMO DROP', style: TextStyle(color: Color(0xFF8A929A), fontSize: 10, letterSpacing: 1.2)),
                        const Spacer(),
                        InkWell(onTap: _tomarFoto, borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFFFF8E7), borderRadius: BorderRadius.circular(8)), child: const Row(children: [Icon(Icons.camera_alt_rounded, size: 14, color: Color(0xFF050505)), SizedBox(width: 6), Text('Cámara', style: TextStyle(color: Color(0xFF050505), fontSize: 11, fontWeight: FontWeight.w700))]))),
                      ]),
                      const SizedBox(height: 12),
                      lastDropUrl==null
                          ? InkWell(onTap: _tomarFoto, child: Container(height: 320, decoration: BoxDecoration(color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.04))), child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.camera_alt_rounded, size: 28, color: Color(0xFF8A929A)), SizedBox(height: 8), Text('Toca Cámara para tu primer drop', style: TextStyle(color: Color(0xFF8A929A), fontSize: 12))]))))
                          : Container(
                              height: 320,
                              width: double.infinity,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                              child: Stack(children: [
                                Positioned.fill(child: Image.network(lastDropUrl, fit: BoxFit.cover, width: double.infinity)),
                                Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.72), Colors.black.withOpacity(0.88)])))),
                                Positioned(left: 14, right: 14, bottom: 14, child: Row(children: [
                                  const Icon(Icons.camera_alt_rounded, size: 14, color: Color(0xFFFFF8E7)),
                                  const SizedBox(width: 6),
                                  Text('Último Drop · ${app.usuarioPorId(lastDrop!.usuarioId)?.displayName ?? ""}', style: const TextStyle(color: Color(0xFFFFF8E7), fontSize: 12, fontWeight: FontWeight.w600)),
                                ])),
                              ]),
                            ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.25,
                    children: [
                      _heroCard(
                        tag: 'historias',
                        detail: const _DetailScaffold(title: 'Historias', child: Text('Historias 24h', style: TextStyle(color: Colors.white))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Row(children: [Icon(Icons.mic_rounded, size: 14, color: Color(0xFF8A929A)), SizedBox(width: 6), Text('HISTORIAS', style: TextStyle(color: Color(0xFF8A929A), fontSize: 10, letterSpacing: 1.2))]),
                          const SizedBox(height: 12),
                          InkWell(onTap: _toggleVoz, borderRadius: BorderRadius.circular(22), child: Container(width: 44,height: 44,decoration: BoxDecoration(color: _grabando?const Color(0xFFEF4444):const Color(0xFF1A1A1A), shape: BoxShape.circle), child: Icon(_grabando?Icons.stop_rounded:Icons.mic_rounded, size: 18, color: Colors.white))),
                          const SizedBox(height: 8),
                          Text(_grabando?'● Grabando… toca para enviar':'Toca para grabar', style: TextStyle(color: _grabando?const Color(0xFFEF4444):const Color(0xFF8A929A), fontSize: 11, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('${app.historias.length} activas · ${app.pines.length} pines', style: const TextStyle(color: Color(0xFF8A929A), fontSize: 11)),
                        ]),
                      ),
                      _heroCard(
                        tag: 'elo',
                        detail: const _DetailScaffold(title: 'Top Elo', child: Text('Ranking', style: TextStyle(color: Colors.white))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Row(children: [Icon(Icons.emoji_events_rounded, size: 14, color: Color(0xFF8A929A)), SizedBox(width: 6), Text('TOP ELO', style: TextStyle(color: Color(0xFF8A929A), fontSize: 10, letterSpacing: 1.2))]),
                          const SizedBox(height: 12),
                          ...app.ranking.take(3).map((r)=> Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(children: [
                              Text('#${r.posicion}', style: const TextStyle(color: Color(0xFFFFF8E7), fontSize: 11, fontWeight: FontWeight.w700)),
                              const SizedBox(width: 6),
                              Expanded(child: Text(r.displayName, maxLines: 1, style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12))),
                              Text('${r.elo}', style: const TextStyle(color: Color(0xFF8A929A), fontSize: 11)),
                            ]),
                          )),
                          if (app.ranking.isEmpty) const Text('Sin ranking', style: TextStyle(color: Color(0xFF8A929A), fontSize: 11)),
                        ]),
                      ),
                      _heroCard(
                        tag: 'planes',
                        detail: const _DetailScaffold(title: 'Planes', child: Text('Planes', style: TextStyle(color: Colors.white))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Row(children: [Icon(Icons.event_rounded, size: 14, color: Color(0xFF8A929A)), SizedBox(width: 6), Text('PLANES', style: TextStyle(color: Color(0xFF8A929A), fontSize: 10, letterSpacing: 1.2))]),
                          const SizedBox(height: 12),
                          ...app.planes.take(2).map((p)=> Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(p.titulo, maxLines: 1, style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12)),
                          )),
                          if (app.planes.isEmpty) const Text('Sin planes', style: TextStyle(color: Color(0xFF8A929A), fontSize: 11)),
                        ]),
                      ),
                      _heroCard(
                        tag: 'analisis',
                        detail: const _DetailScaffold(title: 'Análisis', child: Text('Análisis', style: TextStyle(color: Colors.white))),
                        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Icon(Icons.insights_rounded, size: 14, color: Color(0xFF8A929A)), SizedBox(width: 6), Text('ANÁLISIS', style: TextStyle(color: Color(0xFF8A929A), fontSize: 10, letterSpacing: 1.2))]),
                          SizedBox(height: 12),
                          Text('Mercurio está vivo', style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 12, fontWeight: FontWeight.w600)),
                          SizedBox(height: 4),
                          Text('Backend on · WS conectado', style: TextStyle(color: Color(0xFF8A929A), fontSize: 11)),
                        ]),
                      ),
                    ],
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  final String title; final Widget child;
  const _DetailScaffold({required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(backgroundColor: const Color(0xFF050505), title: Text(title, style: const TextStyle(color: Color(0xFFFFF8E7), letterSpacing: 4, fontSize: 13, fontWeight: FontWeight.w700))),
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}
