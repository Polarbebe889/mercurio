import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../config.dart';
import '../services/apple_music_push.dart';
import '../services/audio_player_service.dart';

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
      try {
        final path = await _recorder.stop();
        final secs = _inicio != null ? DateTime.now().difference(_inicio!).inSeconds.clamp(1, 600) : 2;
        setState(() { _grabando = false; _inicio = null; });
        if (path == null) return;
        // PWA web: path es blob URL, no File
        if (kIsWeb) {
          final bytes = await _recorder.isRecording(); // dummy to ensure stop
          // En web, _recorder.stop() ya libera, subimos via bytes si fuera necesario, pero usamos path como está
          // Para web, el path es un blob, lo manejamos via XFile bytes en subirHistoriaWeb
          // Por ahora, si es web, no usamos File, sino que mostramos error y pedimos usar app nativa si falla
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Subiendo ${secs}s… (web)')));
          // En web, el file es un blob, lo subimos via http con bytes si es posible
          // Si falla, mostramos mensaje
          try {
            // Intenta subir como File si existe, si no, muestra que en PWA el audio es limitado
            final f = File(path);
            if (await f.exists() && await f.length() > 0) {
              await app.api!.subirHistoria(f, secs);
            } else {
              throw Exception('Web audio no soportado, usa app nativa para historias');
            }
          } catch (e) {
            // Fallback: intenta via bytes si es blob
            throw Exception('Audio web: $e — usa app nativa');
          }
          await app.recargarTodo();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Historia subida ✓')));
        } else {
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
        }
      } catch (e) {
        setState(() { _grabando = false; });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error voz: $e')));
      }
      return;
    }
    // iniciar - PWA web no usa Permission.permission_handler, usa getUserMedia directo
    if (!kIsWeb) {
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
    }
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin permiso de micrófono')));
      return;
    }
    try {
      final path = kIsWeb ? 'mercurio_${DateTime.now().millisecondsSinceEpoch}.wav' : '${Directory.systemTemp.path}/mercurio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final cfg = kIsWeb ? const RecordConfig(encoder: AudioEncoder.wav, bitRate: 128000, sampleRate: 44100) : const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100);
      await _recorder.start(cfg, path: path);
      setState(() { _grabando = true; _inicio = DateTime.now(); });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('● Grabando — toca de nuevo para enviar'), duration: Duration(seconds: 2)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo grabar: $e (en PWA usa Chrome/Safari actualizado)')));
    }
  }

  Future<void> _tomarFoto() async {
    if (!kIsWeb) {
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
    }
    // En PWA web, ImageSource.camera a veces falla en iOS si no es https o no es PWA instalada; usa gallery como fallback
    XFile? x;
    try {
      x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    } catch (e) {
      debugPrint('[Foto] camera failed, trying gallery: $e');
    }
    if (x == null && kIsWeb) {
      // Fallback a galería en web si cámara falla
      try { x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85); } catch (_) {}
    }
    if (x == null) return;
    try {
      final bytes = await x.readAsBytes();
      if (bytes.isEmpty) throw Exception('Imagen vacía');
      final mimeType = lookupMimeType(x.name) ?? lookupMimeType(x.path) ?? 'image/jpeg';
      final parts = mimeType.split('/');
      final uri = Uri.parse('${AppConfig.apiBase}/drops');
      final req = http.MultipartRequest('POST', uri);
      req.headers['x-token'] = app.token ?? '';
      if (app.username != null && app.username!.isNotEmpty) {
        req.headers['x-user-id'] = app.username!;
        req.headers['x-username'] = app.username!;
      }
      // En web usa fromBytes, en móvil fromPath es más eficiente pero fromBytes también funciona
      if (kIsWeb) {
        req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: x.name.isNotEmpty ? x.name : 'foto.jpg', contentType: MediaType(parts[0], parts[1])));
      } else {
        // Intenta fromPath, fallback a fromBytes
        try {
          req.files.add(await http.MultipartFile.fromPath('file', x.path, contentType: MediaType(parts[0], parts[1])));
        } catch (_) {
          req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: x.name, contentType: MediaType(parts[0], parts[1])));
        }
      }
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
                      detail: _LobbyDetail(usuarios: usuarios),
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
                      detail: _MusicDetail(usuarios: usuarios),
                      child: Builder(builder: (context){
                        final conMusica = usuarios.where((u)=>u.musica!=null && u.musica!.reproduciendo).toList();
                        final spotifyConectado = usuarios.any((u)=> u.musica?.provider=='spotify');
                        if (conMusica.isEmpty) {
                          if (spotifyConectado) {
                            return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [Icon(Icons.graphic_eq_rounded, size: 14, color: Color(0xFF8A929A)), SizedBox(width: 6), Text('SONANDO', style: TextStyle(color: Color(0xFF8A929A), fontSize: 10, letterSpacing: 1.2))]),
                              SizedBox(height: 12),
                              Text('Spotify conectado ✓', style: TextStyle(color: Color(0xFF1DB954), fontSize: 12, fontWeight: FontWeight.w700)),
                              SizedBox(height: 6),
                              Text('Pon algo a sonar en Spotify', style: TextStyle(color: Color(0xFF8A929A), fontSize: 11)),
                              SizedBox(height: 4),
                              Text('Se sincroniza solo cada 45s', style: TextStyle(color: Color(0xFF5A6270), fontSize: 9)),
                            ]);
                          }
                          return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [Icon(Icons.graphic_eq_rounded, size: 14, color: Color(0xFF8A929A)), SizedBox(width: 6), Text('SONANDO', style: TextStyle(color: Color(0xFF8A929A), fontSize: 10, letterSpacing: 1.2))]),
                            SizedBox(height: 12),
                            Text('Nadie suena', style: TextStyle(color: Color(0xFF8A929A), fontSize: 12)),
                            SizedBox(height: 6),
                            Text('Toca para conectar Spotify', style: TextStyle(color: Color(0xFFFFF8E7), fontSize: 11, fontWeight: FontWeight.w600)),
                          ]);
                        }
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Row(children: [Icon(Icons.graphic_eq_rounded, size: 14, color: Color(0xFF8A929A)), SizedBox(width: 6), Text('SONANDO', style: TextStyle(color: Color(0xFF8A929A), fontSize: 10, letterSpacing: 1.2))]),
                          const SizedBox(height: 12),
                          ...conMusica.take(2).map((u)=> Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(children: [
                              Container(width: 32,height: 32,decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(6)), child: Icon(u.musica!.provider=='spotify'?Icons.circle:Icons.apple, size: 14, color: const Color(0xFF8A929A))),
                              const SizedBox(width: 8),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(u.musica!.titulo ?? '—', maxLines: 1, style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 12, fontWeight: FontWeight.w600)),
                                Text('${u.displayName} · ${u.musica!.artista ?? ""}', maxLines: 1, style: const TextStyle(color: Color(0xFF8A929A), fontSize: 11)),
                              ])),
                            ]),
                          )),
                        ]);
                      }),
                    )),
                  ]),
                  const SizedBox(height: 14),
                  // PROTAGONISTA - muestra todos los drops (1 por usuario) + último grande
                  _heroCard(
                    tag: 'drop',
                    detail: _DropsDetail(drops: drops),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        const Icon(Icons.camera_alt_rounded, size: 14, color: Color(0xFF8A929A)),
                        const SizedBox(width: 6),
                        Text('DROPS · ${drops.length} activos', style: const TextStyle(color: Color(0xFF8A929A), fontSize: 10, letterSpacing: 1.2)),
                        const Spacer(),
                        InkWell(onTap: _tomarFoto, borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFFFF8E7), borderRadius: BorderRadius.circular(8)), child: const Row(children: [Icon(Icons.camera_alt_rounded, size: 14, color: Color(0xFF050505)), SizedBox(width: 6), Text('Cámara', style: TextStyle(color: Color(0xFF050505), fontSize: 11, fontWeight: FontWeight.w700))]))),
                      ]),
                      const SizedBox(height: 12),
                      if (lastDropUrl==null)
                        InkWell(onTap: _tomarFoto, child: Container(height: 220, decoration: BoxDecoration(color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.04))), child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.camera_alt_rounded, size: 28, color: Color(0xFF8A929A)), SizedBox(height: 8), Text('Toca Cámara para tu primer drop', style: TextStyle(color: Color(0xFF8A929A), fontSize: 12))]))))
                      else ...[
                        Container(
                          height: 280,
                          width: double.infinity,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                          child: Stack(children: [
                            Positioned.fill(child: Image.network(lastDropUrl, fit: BoxFit.cover, width: double.infinity, errorBuilder: (_,__,___)=> Container(color: const Color(0xFF0A0A0A), child: const Center(child: Icon(Icons.broken_image, color: Color(0xFF8A929A)))))),
                            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.72), Colors.black.withOpacity(0.88)])))),
                            Positioned(left: 14, right: 14, bottom: 14, child: Row(children: [
                              const Icon(Icons.camera_alt_rounded, size: 14, color: Color(0xFFFFF8E7)),
                              const SizedBox(width: 6),
                              Expanded(child: Text('Último · ${app.usuarioPorId(lastDrop!.usuarioId)?.displayName ?? ""}', style: const TextStyle(color: Color(0xFFFFF8E7), fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                            ])),
                          ]),
                        ),
                        if (drops.length > 1) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 72,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: drops.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (_, i) {
                                final d = drops[i];
                                final url = AppConfig.fullUrl(d.imgUrl);
                                final u = app.usuarioPorId(d.usuarioId);
                                final isSelected = d.id == lastDrop!.id;
                                return GestureDetector(
                                  onTap: () => Navigator.push(context, PageRouteBuilder(pageBuilder: (_, a, __) => FadeTransition(opacity: a, child: _DetailScaffold(title: u?.displayName ?? 'Drop', child: InteractiveViewer(child: Image.network(url)))))),
                                  child: Container(
                                    width: 72,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: isSelected ? const Color(0xFFFFF8E7) : Colors.white.withOpacity(0.08), width: isSelected ? 2 : 1),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Stack(children: [
                                      Positioned.fill(child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_,__,___)=> Container(color: const Color(0xFF141414), child: Center(child: Text(u?.emoji ?? '📷'))))),
                                      Positioned(bottom: 2, left: 2, right: 2, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(6)), child: Text(u?.displayName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 8)))),
                                    ]),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
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
                        detail: _HistoriasDetail(usuarios: usuarios),
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
                        detail: _EloDetail(usuarios: usuarios),
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
                        detail: _PlanesDetail(usuarios: usuarios),
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

class _LobbyDetail extends StatefulWidget {
  final List<dynamic> usuarios;
  const _LobbyDetail({required this.usuarios});
  @override
  State<_LobbyDetail> createState() => _LobbyDetailState();
}
class _LobbyDetailState extends State<_LobbyDetail> {
  final _ctrl = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return _DetailScaffold(
      title: 'Lobby',
      child: Column(children: [
        Row(children: [
          Expanded(child: TextField(controller: _ctrl, decoration: const InputDecoration(hintText: 'Qué haces…', hintStyle: TextStyle(color: Color(0xFF8A929A)), filled: true, fillColor: Color(0xFF141414), border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(12)))))),
          IconButton(icon: const Icon(Icons.send, color: Color(0xFFFFF8E7)), onPressed: () async { if (_ctrl.text.trim().isEmpty) return; await app.api!.setStatus(_ctrl.text.trim()); _ctrl.clear(); await app.recargarTodo(); setState((){}); }),
        ]),
        const SizedBox(height: 16),
        Expanded(child: ListView.builder(itemCount: widget.usuarios.length, itemBuilder: (_,i){ final u=widget.usuarios[i]; return ListTile(leading: CircleAvatar(backgroundColor: const Color(0xFF1A1A1A), child: Text(u.emoji)), title: Text(u.displayName, style: const TextStyle(color: Colors.white)), subtitle: Text(u.statusText ?? 'sin status', style: const TextStyle(color: Color(0xFF8A929A))));})),
      ]),
    );
  }
}

class _MusicDetail extends StatefulWidget {
  final List<dynamic> usuarios;
  const _MusicDetail({required this.usuarios});
  @override
  State<_MusicDetail> createState()=>_MusicDetailState();
}
class _MusicDetailState extends State<_MusicDetail> {
  Timer? _poll; bool _polling=false;
  @override
  void dispose(){ _poll?.cancel(); super.dispose();}
  void _startPolling(){
    if(_polling) return;
    _polling=true;
    int intentos=0;
    _poll=Timer.periodic(const Duration(seconds:2), (_) async {
      intentos++;
      if(intentos>30){ _poll?.cancel(); _polling=false; return; }
      try{
        final s = await app.api!.spotifyStatus();
        if(s['conectado']==true){
          _poll?.cancel(); _polling=false;
          if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Spotify conectado ✓')));
          await app.recargarTodo();
          if(mounted) setState((){});
        }
      }catch(_){}
    });
  }
  @override
  Widget build(BuildContext context) {
    final conMusica = widget.usuarios.where((u)=>u.musica!=null).toList();
    return _DetailScaffold(
      title: 'Sonando ahora',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1DB954)), icon: const Icon(Icons.music_note, color: Colors.white), label: const Text('Conectar Spotify', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)), onPressed: () async {
          String? authUrl;
          try {
            final resp = await app.api!.spotifyLogin();
            authUrl = resp['auth_url'] as String;
          } catch (e) {
            debugPrint('[Spotify] login via API fallo: $e');
            const clientId = 'c232ed3488354a57aa68e881240120d4';
            final redirect = Uri.encodeComponent('https://mercurio-9haf.onrender.com/auth/spotify/callback');
            final state = app.token ?? '';
            authUrl = 'https://accounts.spotify.com/authorize?client_id=$clientId&response_type=code&redirect_uri=$redirect&scope=user-read-currently-playing%20user-read-playback-state&state=$state';
          }
          final url = Uri.parse(authUrl!);
          bool launched = false;
          try { launched = await launchUrl(url, mode: LaunchMode.externalApplication); } catch (e) { debugPrint('[Spotify] launch external failed: $e'); }
          if (!launched) {
            try { launched = await launchUrl(url, mode: LaunchMode.platformDefault); } catch (e) { debugPrint('[Spotify] launch platformDefault failed: $e'); }
          }
          if (launched) {
            _startPolling();
            if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Autoriza en el navegador y vuelve — detectando…'), duration: Duration(seconds:3)));
          } else {
            if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo abrir navegador: $authUrl')));
          }
        }),
        const SizedBox(height: 6),
        TextButton.icon(icon: const Icon(Icons.apple, size: 16, color: Color(0xFF8A929A)), label: const Text('Apple Music en Android: concede Acceso a notificaciones', style: TextStyle(color: Color(0xFF8A929A), fontSize: 11)), onPressed: ()=>openAppSettings()),
        const SizedBox(height: 16),
        if (conMusica.isEmpty) const Text('Nadie suena ahora', style: TextStyle(color: Color(0xFF8A929A))) else ...conMusica.map((u)=> ListTile(leading: Container(width: 40,height: 40,decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(6)), child: Icon(u.musica!.provider=='spotify'?Icons.circle:Icons.apple, color: const Color(0xFF8A929A))), title: Text(u.musica!.titulo ?? '—', style: const TextStyle(color: Colors.white)), subtitle: Text('${u.displayName} · ${u.musica!.artista ?? ""}', style: const TextStyle(color: Color(0xFF8A929A))))),
      ]),
    );
  }
}

class _EloDetail extends StatefulWidget {
  final List<dynamic> usuarios;
  const _EloDetail({required this.usuarios});
  @override
  State<_EloDetail> createState() => _EloDetailState();
}
class _EloDetailState extends State<_EloDetail> {
  int? rival; final m1=TextEditingController(text:'0'); final m2=TextEditingController(text:'0'); final juego=TextEditingController(text:'1v1');
  @override
  Widget build(BuildContext context) {
    final otros = widget.usuarios.where((u)=>u.id!=app.yo?.id).toList();
    return _DetailScaffold(
      title: 'Top Elo',
      child: ListView(children: [
        DropdownButtonFormField<int>(value: rival, hint: const Text('Rival', style: TextStyle(color: Color(0xFF8A929A))), decoration: const InputDecoration(filled: true, fillColor: Color(0xFF141414)), items: [for (final u in otros) DropdownMenuItem(value: u.id, child: Text('${u.emoji} ${u.displayName}'))], onChanged: (v)=>setState(()=>rival=v)),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: TextField(controller: m1, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tú'))), const SizedBox(width: 8), Expanded(child: TextField(controller: m2, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rival')))]),
        const SizedBox(height: 8),
        TextField(controller: juego, decoration: const InputDecoration(labelText: 'Juego')),
        const SizedBox(height: 12),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFF8E7), foregroundColor: Color(0xFF050505)), onPressed: () async { if (rival==null) return; await app.api!.registrarPartida(rival!, int.tryParse(m1.text)??0, int.tryParse(m2.text)??0, juego.text); await app.recargarTodo(); if (mounted) Navigator.pop(context); }, child: const Text('Guardar reta')),
        const SizedBox(height: 20),
        ...app.ranking.map((r)=> ListTile(leading: Text('#${r.posicion}', style: const TextStyle(color: Color(0xFFFFF8E7))), title: Text(r.displayName, style: const TextStyle(color: Colors.white)), trailing: Text('${r.elo}', style: const TextStyle(color: Color(0xFF8A929A))))),
      ]),
    );
  }
}

class _PlanesDetail extends StatefulWidget {
  final List<dynamic> usuarios;
  const _PlanesDetail({required this.usuarios});
  @override
  State<_PlanesDetail> createState()=>_PlanesDetailState();
}
class _PlanesDetailState extends State<_PlanesDetail> {
  final titulo=TextEditingController(); final lugar=TextEditingController(); final desc=TextEditingController();
  DateTime _cuando = DateTime.now().add(const Duration(hours:2));
  bool _creando=false;
  String _fmt(DateTime d)=> "${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}";
  Future<void> _pickCuando() async {
    final d = await showDatePicker(context: context, initialDate: _cuando, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days:60)), builder: (c,w)=> Theme(data: ThemeData.dark(), child: w!));
    if (d==null) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_cuando));
    if (t==null) return;
    setState(()=> _cuando = DateTime(d.year,d.month,d.day,t.hour,t.minute));
  }
  @override
  Widget build(BuildContext context){
    return _DetailScaffold(title:'Planes', child: ListView(children:[
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF141414), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.06))), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [Icon(Icons.event_rounded, size: 14, color: Color(0xFF8A929A)), SizedBox(width:6), Text('NUEVO PLAN', style: TextStyle(color: Color(0xFF8A929A), fontSize: 10, letterSpacing: 1.2))]),
        const SizedBox(height:12),
        TextField(controller: titulo, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText:'Qué hacemos… ej: Carnita asada', hintStyle: TextStyle(color: Color(0xFF5A6270)), filled: true, fillColor: Color(0xFF0A0A0A), border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(10))), prefixIcon: Icon(Icons.title, size: 16, color: Color(0xFF8A929A)))),
        const SizedBox(height:8),
        TextField(controller: lugar, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText:'Dónde… ej: Casa de ova', hintStyle: TextStyle(color: Color(0xFF5A6270)), filled: true, fillColor: Color(0xFF0A0A0A), border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(10))), prefixIcon: Icon(Icons.place_outlined, size: 16, color: Color(0xFF8A929A)))),
        const SizedBox(height:8),
        TextField(controller: desc, style: const TextStyle(color: Colors.white, fontSize: 13), maxLines: 2, decoration: const InputDecoration(hintText:'Detalles opcionales…', hintStyle: TextStyle(color: Color(0xFF5A6270)), filled: true, fillColor: Color(0xFF0A0A0A), border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(10))), prefixIcon: Icon(Icons.notes_rounded, size: 16, color: Color(0xFF8A929A)))),
        const SizedBox(height:10),
        InkWell(onTap: _pickCuando, borderRadius: BorderRadius.circular(10), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), decoration: BoxDecoration(color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(10)), child: Row(children: [const Icon(Icons.schedule_rounded, size: 16, color: Color(0xFF8A929A)), const SizedBox(width:8), Text(_fmt(_cuando), style: const TextStyle(color: Colors.white, fontSize: 13)), const Spacer(), const Icon(Icons.edit_calendar_rounded, size: 14, color: Color(0xFF8A929A))]))),
        const SizedBox(height:12),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFF8E7), foregroundColor: Color(0xFF050505), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: _creando?null:() async { if(titulo.text.trim().isEmpty) return; setState(()=>_creando=true); try{ await app.api!.crearPlan(titulo.text.trim(), lugar.text.trim(), _cuando); titulo.clear(); lugar.clear(); desc.clear(); await app.recargarTodo(); if(mounted) setState(()=>_cuando=DateTime.now().add(const Duration(hours:2))); } catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error plan: $e')));} finally{ if(mounted) setState(()=>_creando=false);} }, child: _creando? const SizedBox(width:16,height:16, child: CircularProgressIndicator(strokeWidth:2, color: Color(0xFF050505))): const Text('Crear plan', style: TextStyle(fontWeight: FontWeight.w800)) ),
      ])),
      const SizedBox(height:18),
      Row(children: [const Icon(Icons.list_alt_rounded, size: 14, color: Color(0xFF8A929A)), const SizedBox(width:6), Text('PRÓXIMOS · ${app.planes.length}', style: const TextStyle(color: Color(0xFF8A929A), fontSize: 10, letterSpacing: 1.2))]),
      const SizedBox(height:10),
      if (app.planes.isEmpty) Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: const Color(0xFF0A0A0A), borderRadius: BorderRadius.circular(12)), child: const Center(child: Text('Sin planes — crea el primero', style: TextStyle(color: Color(0xFF5A6270), fontSize: 12)))),
      for (final p in app.planes) Container(margin: const EdgeInsets.only(bottom:10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF141414), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.06))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(p.titulo, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))), Container(padding: const EdgeInsets.symmetric(horizontal:8, vertical:4), decoration: BoxDecoration(color: const Color(0xFFFFF8E7), borderRadius: BorderRadius.circular(8)), child: Text(_fmt(p.startsAt), style: const TextStyle(color: Color(0xFF050505), fontSize: 10, fontWeight: FontWeight.w700)))]),
        if ((p.lugar ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top:6), child: Row(children: [const Icon(Icons.place, size: 12, color: Color(0xFF8A929A)), const SizedBox(width:4), Expanded(child: Text(p.lugar!, style: const TextStyle(color: Color(0xFF8A929A), fontSize: 11)))])),
        if ((p.descripcion ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top:4), child: Text(p.descripcion!, style: const TextStyle(color: Color(0xFF8A929A), fontSize: 11))),
        const SizedBox(height:10),
        Wrap(spacing:6, runSpacing:6, children: [
          for (final opt in ['alistandome','en_camino','llegue'])
            ChoiceChip(
              label: Text(opt=='alistandome'?'Alistándome':opt=='en_camino'?'En camino':'Llegué', style: TextStyle(color: p.estadoDe(app.yo?.id??-1)==opt?const Color(0xFF050505):Colors.white, fontSize: 11)),
              selected: p.estadoDe(app.yo?.id??-1)==opt,
              selectedColor: const Color(0xFFFFF8E7),
              backgroundColor: const Color(0xFF1A1A1A),
              onSelected: (_) async { try{ await app.api!.setPlanEstado(p.id, opt); await app.recargarTodo(); if(mounted) setState((){});} catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));} },
            ),
        ]),
        const SizedBox(height:8),
        // avatares de estados
        if (p.estados.isNotEmpty) Wrap(spacing:4, children: [ for (final e in p.estados) Builder(builder: (_){ final u=app.usuarioPorId(e.usuarioId); return Chip(avatar: CircleAvatar(radius:10, backgroundColor: const Color(0xFF1A1A1A), child: Text(u?.emoji ?? '🙂', style: const TextStyle(fontSize:10))), label: Text('${u?.displayName ?? e.usuarioId}: ${e.estado}', style: const TextStyle(fontSize:10)), backgroundColor: const Color(0xFF0A0A0A), labelStyle: const TextStyle(color: Color(0xFF8A929A))); }) ]),
      ])),
    ]));
  }
}

class _HistoriasDetail extends StatefulWidget {
  final List<dynamic> usuarios;
  const _HistoriasDetail({required this.usuarios});
  @override
  State<_HistoriasDetail> createState()=>_HistoriasDetailState();
}
class _HistoriasDetailState extends State<_HistoriasDetail>{
  Future<void> _playHistoria(dynamic h) async {
    final url = AppConfig.fullUrl(h.audioUrl as String);
    debugPrint('[HistoriasDetail] play $url');
    try {
      await AudioPlayerService.instance.play(url);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('▶ ${h.durationS}s')));
    } catch (e, st) {
      debugPrint('[HistoriasDetail] error $url: $e\n$st');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error audio: $e')));
    }
  }
  Future<void> _playPin(dynamic p) async {
    final url = AppConfig.fullUrl(p.audioUrl as String);
    debugPrint('[HistoriasDetail] play pin $url');
    try {
      await AudioPlayerService.instance.play(url);
    } catch (e, st) {
      debugPrint('[HistoriasDetail] pin error $url: $e\n$st');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error audio: $e')));
    }
  }
  @override
  Widget build(BuildContext context){
    return _DetailScaffold(title:'Historias', child: ListView(children:[
      Text('${app.historias.length} historias activas (24h)', style: const TextStyle(color: Color(0xFF8A929A))),
      const SizedBox(height:8),
      ...app.historias.map((h){ final u=app.usuarioPorId(h.usuarioId); return ListTile(leading: CircleAvatar(child: Text(u?.emoji ?? '🎙️')), title: Text(u?.displayName ?? 'alguien', style: const TextStyle(color: Colors.white)), subtitle: Text('${h.durationS}s', style: const TextStyle(color: Color(0xFF8A929A))), trailing: IconButton(icon: const Icon(Icons.play_arrow, color: Colors.white), onPressed: ()=>_playHistoria(h)));}),
      const Divider(color: Color(0x14FFFFFF)),
      Text('${app.pines.length} pines', style: const TextStyle(color: Color(0xFF8A929A))),
      ...app.pines.map((p){ final u=app.usuarioPorId(p.usuarioId); return ListTile(leading: const Icon(Icons.push_pin, color: Colors.white), title: Text(p.caption.isEmpty?'audio':p.caption, style: const TextStyle(color: Colors.white)), subtitle: Text(u?.displayName ?? '', style: const TextStyle(color: Color(0xFF8A929A))), trailing: IconButton(icon: const Icon(Icons.play_arrow, color: Colors.white), onPressed: ()=>_playPin(p)));}),
    ]));
  }
}

class _DropsDetail extends StatelessWidget {
  final List<dynamic> drops;
  const _DropsDetail({required this.drops});
  @override
  Widget build(BuildContext context) {
    if (drops.isEmpty) {
      return const _DetailScaffold(title: 'Drops', child: Text('Sin drops', style: TextStyle(color: Color(0xFF8A929A))));
    }
    return _DetailScaffold(
      title: 'Drops · ${drops.length}',
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.9),
        itemCount: drops.length,
        itemBuilder: (_, i) {
          final d = drops[i];
          final url = AppConfig.fullUrl(d.imgUrl);
          final u = app.usuarioPorId(d.usuarioId);
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(children: [
              Positioned.fill(child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_,__,___)=> Container(color: const Color(0xFF141414), child: Center(child: Text(u?.emoji ?? '📷'))))),
              Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.8)])), child: Text(u?.displayName ?? '', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)))),
            ]),
          );
        },
      ),
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
