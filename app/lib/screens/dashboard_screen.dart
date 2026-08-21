import 'package:flutter/material.dart';
import '../main.dart';
import '../config.dart';
import '../theme/uranio_theme.dart';
import '../widgets/lobby_card.dart';
import '../widgets/music_card.dart';
import '../widgets/mercurio_cards.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => app.recargarTodo());
  }

  String _avatarUrl(String name) =>
      'https://ui-avatars.com/api/?name=${Uri.encodeComponent(name)}&background=171B1E&color=22D3EE&bold=true';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        // --- mapear AppState real a los modelos del dashboard ---
        final lobbyMembers = app.usuarios.map((u) => LobbyMember(
          id: u.id.toString(),
          name: u.displayName,
          avatarUrl: _avatarUrl(u.displayName),
          isInLobby: u.statusText != null && u.statusText!.isNotEmpty,
          isSpeaking: u.notasVoz.isNotEmpty,
        )).toList();

        final musicStatuses = app.usuarios.map((u) {
          final m = u.musica;
          return MusicStatus(
            userId: u.id.toString(),
            userName: u.displayName,
            avatarUrl: _avatarUrl(u.displayName),
            provider: m?.provider == 'spotify' ? MusicProvider.spotify
                : m?.provider == 'music_kit' ? MusicProvider.appleMusic
                : MusicProvider.none,
            isPlaying: m?.reproduciendo ?? false,
            trackName: m?.titulo,
            artistName: m?.artista,
            albumArtUrl: m?.artworkUrl,
          );
        }).toList();

        final lastDrop = app.drops.isNotEmpty ? app.drops.first : null;
        final lastDropUrl = lastDrop != null ? AppConfig.fullUrl(lastDrop.imgUrl) : null;
        final lastDropAuthor = lastDrop != null
            ? app.usuarioPorId(lastDrop.usuarioId)?.displayName
            : null;

        final stories = app.historias.map((n) {
          final aut = app.usuarioPorId(n.usuarioId);
          return VoiceStoryPreview(
            userId: n.usuarioId.toString(),
            userName: aut?.displayName ?? 'alguien',
            avatarUrl: _avatarUrl(aut?.displayName ?? '??'),
            hasActiveStory: true,
          );
        }).toList();

        final pins = app.pines.map((p) {
          final aut = app.usuarioPorId(p.usuarioId);
          return VoiceStoryPreview(
            userId: p.usuarioId.toString(),
            userName: aut?.displayName ?? 'alguien',
            avatarUrl: _avatarUrl(aut?.displayName ?? '??'),
            isPinned: true,
          );
        }).toList();

        final elo = app.ranking.map((r) => EloEntry(userName: r.displayName, elo: r.elo, rank: r.posicion)).toList();

        final plans = app.planes.map((p) => QuickPlan(title: p.titulo, when: p.startsAt, confirmedCount: p.estados.length)).toList();

        return Scaffold(
          backgroundColor: UranioColors.background,
          appBar: AppBar(
            backgroundColor: UranioColors.background,
            title: const Text('M E R C U R I O', style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w900)),
            centerTitle: true,
            actions: [
              IconButton(icon: const Icon(Icons.logout, size: 18), onPressed: () => app.cerrarSesion()),
            ],
          ),
          body: RefreshIndicator(
            color: UranioColors.accent,
            backgroundColor: UranioColors.surface,
            onRefresh: () => app.recargarTodo(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                LobbyCard(members: lobbyMembers),
                const SizedBox(height: 14),
                MusicCard(statuses: musicStatuses),
                const SizedBox(height: 14),
                PhotoDropCard(imageUrl: lastDropUrl, authorName: lastDropAuthor),
                const SizedBox(height: 14),
                VoiceStoriesCard(stories: stories, pins: pins),
                const SizedBox(height: 14),
                EloCard(ranking: elo),
                const SizedBox(height: 14),
                PlansCard(plans: plans),
                if (app.eventos.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: UranioTheme.cardDecoration(),
                    child: Text('WS: ${app.eventos.first['type']}', style: const TextStyle(color: UranioColors.textSecondary, fontSize: 11)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
