import 'package:flutter/material.dart';
import '../theme/uranio_theme.dart';
import 'section_card.dart';

enum MusicProvider { spotify, appleMusic, none }

class MusicStatus {
  final String userId;
  final String userName;
  final String avatarUrl;
  final MusicProvider provider;
  final bool isPlaying;
  final String? trackName;
  final String? artistName;
  final String? albumArtUrl;

  MusicStatus({
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    required this.provider,
    this.isPlaying = false,
    this.trackName,
    this.artistName,
    this.albumArtUrl,
  });

  factory MusicStatus.fromJson(Map<String, dynamic> json) {
    return MusicStatus(
      userId: json['user_id'],
      userName: json['user_name'],
      avatarUrl: json['avatar_url'] ?? '',
      provider: switch (json['provider']) {
        'spotify' => MusicProvider.spotify,
        'apple_music' => MusicProvider.appleMusic,
        _ => MusicProvider.none,
      },
      isPlaying: json['is_playing'] ?? false,
      trackName: json['track_name'],
      artistName: json['artist_name'],
      albumArtUrl: json['album_art_url'],
    );
  }
}

class MusicCard extends StatelessWidget {
  final List<MusicStatus> statuses;
  const MusicCard({super.key, required this.statuses});

  @override
  Widget build(BuildContext context) {
    final listening = statuses.where((s) => s.isPlaying && s.trackName != null).toList();

    return SectionCard(
      heroTag: 'music-card',
      fullViewBuilder: (_) => _MusicFullView(statuses: statuses),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.graphic_eq_rounded, color: UranioColors.accent, size: 18),
              SizedBox(width: 8),
              Text('Sonando ahora',
                  style: TextStyle(color: UranioColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          if (listening.isEmpty)
            const Text('Nadie está escuchando música ahora mismo',
                style: TextStyle(color: UranioColors.textSecondary, fontSize: 13))
          else
            ...listening.take(2).map((s) => _MusicRow(status: s)),
          if (listening.length > 2)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('+${listening.length - 2} más',
                  style: const TextStyle(color: UranioColors.accent, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _MusicRow extends StatelessWidget {
  final MusicStatus status;
  const _MusicRow({required this.status});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: status.albumArtUrl != null
                ? Image.network(status.albumArtUrl!, width: 40, height: 40, fit: BoxFit.cover)
                : Container(width: 40, height: 40, color: UranioColors.surfaceElevated),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${status.userName} · ${status.trackName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: UranioColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  status.artistName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: UranioColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(
            status.provider == MusicProvider.spotify ? Icons.circle : Icons.apple_rounded,
            size: 14,
            color: UranioColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _MusicFullView extends StatelessWidget {
  final List<MusicStatus> statuses;
  const _MusicFullView({required this.statuses});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Música')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: statuses.length,
        itemBuilder: (context, i) {
          final s = statuses[i];
          return ListTile(
            leading: CircleAvatar(backgroundImage: NetworkImage(s.avatarUrl)),
            title: Text(s.userName, style: const TextStyle(color: UranioColors.textPrimary)),
            subtitle: Text(
              s.isPlaying ? '${s.trackName} — ${s.artistName}' : 'Sin reproducción activa',
              style: const TextStyle(color: UranioColors.textSecondary),
            ),
          );
        },
      ),
    );
  }
}
