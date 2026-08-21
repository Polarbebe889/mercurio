import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../main.dart';
import '../config.dart';
import '../theme/uranio_premium_theme.dart';


/// ── Modelos dummy para música (listos para backend real) ──
enum MusicProvider { spotify, appleMusic }
class DummyMusic { final String user; final String track; final String artist; final MusicProvider provider; DummyMusic(this.user,this.track,this.artist,this.provider); }

/// Dashboard premium single-page — sin BottomNav, BeReal + high-end
class DashboardPremium extends StatefulWidget {
  const DashboardPremium({super.key});
  @override
  State<DashboardPremium> createState() => _DashboardPremiumState();
}

class _DashboardPremiumState extends State<DashboardPremium> {
  final _recorder = AudioRecorder();

  // ── FIX AUDIO: permission_handler + try/catch ──
  Future<void> _grabarVoz() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Micrófono denegado')));
      return;
    }
    if (!await _recorder.hasPermission()) return;
    try {
      final dir = Directory.systemTemp;
      final path = '${dir.path}/mercurio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100), path: path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grabando… toca de nuevo para parar')));
      await Future.delayed(const Duration(seconds: 3));
      final out = await _recorder.stop();
      if (out != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Audio: $out')));
        // TODO: subir con app.api!.subirHistoria(File(out), segundos)
      }
    } catch (e) {
      debugPrint('Audio error: $e');
    }
  }

  // ── FIX FOTOS: mime + MediaType explícito ──
  // ignore: unused_element
  Future<void> _subirDrop(File file) async {
    final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';
    final parts = mimeType.split('/');
    final uri = Uri.parse('${AppConfig.apiBase}/drops');
    final req = http.MultipartRequest('POST', uri);
    req.headers['x-token'] = app.token ?? '';
    req.files.add(await http.MultipartFile.fromPath('file', file.path, contentType: MediaType(parts[0], parts[1])));
    req.fields['caption'] = 'drop';
    final resp = await req.send();
    debugPrint('Drop status: ${resp.statusCode}');
  }

  Widget _heroCard({required String tag, required Widget child, required Widget detail}) {
    return Hero(
      tag: tag,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(context, PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 320),
            pageBuilder: (_,a,__) => FadeTransition(opacity: a, child: detail),
          )),
          child: Container(
            decoration: UranioPremiumTheme.cardDecoration(),
            padding: const EdgeInsets.all(16),
            child: child,
          ),
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

        // dummy música
        final dummyMusic = [
          DummyMusic('Tú', 'Die For You', 'The Weeknd', MusicProvider.spotify),
          DummyMusic('Javier', 'DTMF', 'Bad Bunny', MusicProvider.appleMusic),
        ];

        return Scaffold(
          backgroundColor: PremiumColors.background,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: PremiumColors.background,
                title: const Text('M E R C U R I O'),
                centerTitle: true,
                actions: [IconButton(icon: const Icon(Icons.logout, size: 16, color: PremiumColors.textSecondary), onPressed: () => app.cerrarSesion())],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList.list(children: [
                  // Fila Lobby + Música
                  Row(children: [
                    Expanded(child: _heroCard(
                      tag: 'lobby',
                      detail: _DetailScaffold(title: 'Lobby', child: Text('${usuarios.length} en el bunker', style: const TextStyle(color: Colors.white))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Row(children: [Icon(Icons.podcasts_rounded, size: 14, color: PremiumColors.textSecondary), SizedBox(width: 6), Text('LOBBY', style: TextStyle(color: PremiumColors.textSecondary, fontSize: 10, letterSpacing: 1.2))]),
                        const SizedBox(height: 12),
                        SizedBox(height: 36, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: usuarios.take(6).length, separatorBuilder: (_,__)=>const SizedBox(width: 8), itemBuilder: (_,i){ final u=usuarios[i]; return CircleAvatar(radius: 18, backgroundColor: const Color(0xFF1A1A1A), child: Text(u.emoji, style: const TextStyle(fontSize: 16)));})),
                        const SizedBox(height: 8),
                        Text('${usuarios.length} conectados', style: const TextStyle(color: PremiumColors.textSecondary, fontSize: 11)),
                      ]),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _heroCard(
                      tag: 'musica',
                      detail: const _DetailScaffold(title: 'Sonando ahora', child: Text('Música', style: TextStyle(color: Colors.white))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Row(children: [Icon(Icons.graphic_eq_rounded, size: 14, color: PremiumColors.textSecondary), SizedBox(width: 6), Text('SONANDO', style: TextStyle(color: PremiumColors.textSecondary, fontSize: 10, letterSpacing: 1.2))]),
                        const SizedBox(height: 12),
                        ...dummyMusic.map((m)=> Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Container(width: 32,height: 32,decoration: BoxDecoration(color: PremiumColors.surfaceElevated, borderRadius: BorderRadius.circular(6)), child: Icon(m.provider==MusicProvider.spotify?Icons.circle:Icons.apple, size: 14, color: PremiumColors.textSecondary)),
                            const SizedBox(width: 8),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(m.track, maxLines: 1, style: const TextStyle(color: PremiumColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                              Text('${m.user} · ${m.artist}', maxLines: 1, style: const TextStyle(color: PremiumColors.textSecondary, fontSize: 11)),
                            ])),
                          ]),
                        )),
                      ]),
                    )),
                  ]),
                  const SizedBox(height: 14),
                  // ÚLTIMO DROP PROTAGONISTA
                  _heroCard(
                    tag: 'drop',
                    detail: _DetailScaffold(title: 'Drop', child: lastDropUrl!=null?Image.network(lastDropUrl):const Text('Sin drop', style: TextStyle(color: Colors.white))),
                    child: lastDropUrl==null
                        ? const SizedBox(height: 180, child: Center(child: Text('Sin drops aún', style: TextStyle(color: PremiumColors.textSecondary, fontSize: 12))))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(children: [
                              AspectRatio(aspectRatio: 16/10, child: Image.network(lastDropUrl, fit: BoxFit.cover, width: double.infinity)),
                              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.65)])))),
                              Positioned(left: 12, right: 12, bottom: 12, child: Row(children: [
                                const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white70),
                                const SizedBox(width: 6),
                                Text('Último Drop · ${app.usuarioPorId(lastDrop!.usuarioId)?.displayName ?? ""}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                              ])),
                            ]),
                          ),
                  ),
                  const SizedBox(height: 14),
                  // GRID 2x2
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
                          const Row(children: [Icon(Icons.mic_rounded, size: 14, color: PremiumColors.textSecondary), SizedBox(width: 6), Text('HISTORIAS', style: TextStyle(color: PremiumColors.textSecondary, fontSize: 10, letterSpacing: 1.2))]),
                          const SizedBox(height: 12),
                          InkWell(onTap: _grabarVoz, child: Container(width: 44,height: 44,decoration: const BoxDecoration(color: PremiumColors.surfaceElevated, shape: BoxShape.circle), child: const Icon(Icons.mic_rounded, size: 18, color: PremiumColors.textPrimary))),
                          const SizedBox(height: 8),
                          Text('${app.historias.length} activas · ${app.pines.length} pines', style: const TextStyle(color: PremiumColors.textSecondary, fontSize: 11)),
                        ]),
                      ),
                      _heroCard(
                        tag: 'elo',
                        detail: const _DetailScaffold(title: 'Top Elo', child: Text('Ranking', style: TextStyle(color: Colors.white))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Row(children: [Icon(Icons.emoji_events_rounded, size: 14, color: PremiumColors.textSecondary), SizedBox(width: 6), Text('TOP ELO', style: TextStyle(color: PremiumColors.textSecondary, fontSize: 10, letterSpacing: 1.2))]),
                          const SizedBox(height: 12),
                          ...app.ranking.take(3).map((r)=> Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(children: [
                              Text('#${r.posicion}', style: const TextStyle(color: PremiumColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
                              const SizedBox(width: 6),
                              Expanded(child: Text(r.displayName, maxLines: 1, style: const TextStyle(color: PremiumColors.textPrimary, fontSize: 12))),
                              Text('${r.elo}', style: const TextStyle(color: PremiumColors.textSecondary, fontSize: 11)),
                            ]),
                          )),
                          if (app.ranking.isEmpty) const Text('Sin ranking', style: TextStyle(color: PremiumColors.textSecondary, fontSize: 11)),
                        ]),
                      ),
                      _heroCard(
                        tag: 'planes',
                        detail: const _DetailScaffold(title: 'Planes', child: Text('Planes', style: TextStyle(color: Colors.white))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Row(children: [Icon(Icons.event_rounded, size: 14, color: PremiumColors.textSecondary), SizedBox(width: 6), Text('PLANES', style: TextStyle(color: PremiumColors.textSecondary, fontSize: 10, letterSpacing: 1.2))]),
                          const SizedBox(height: 12),
                          ...app.planes.take(2).map((p)=> Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(p.titulo, maxLines: 1, style: const TextStyle(color: PremiumColors.textPrimary, fontSize: 12)),
                          )),
                          if (app.planes.isEmpty) const Text('Sin planes', style: TextStyle(color: PremiumColors.textSecondary, fontSize: 11)),
                        ]),
                      ),
                      _heroCard(
                        tag: 'analisis',
                        detail: const _DetailScaffold(title: 'Análisis', child: Text('Análisis', style: TextStyle(color: Colors.white))),
                        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Icon(Icons.insights_rounded, size: 14, color: PremiumColors.textSecondary), SizedBox(width: 6), Text('ANÁLISIS', style: TextStyle(color: PremiumColors.textSecondary, fontSize: 10, letterSpacing: 1.2))]),
                          SizedBox(height: 12),
                          Text('Mercurio está vivo', style: TextStyle(color: PremiumColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                          SizedBox(height: 4),
                          Text('Backend on · WS conectado', style: TextStyle(color: PremiumColors.textSecondary, fontSize: 11)),
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
      backgroundColor: PremiumColors.background,
      appBar: AppBar(backgroundColor: PremiumColors.background, title: Text(title, style: const TextStyle(letterSpacing: 2))),
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}
