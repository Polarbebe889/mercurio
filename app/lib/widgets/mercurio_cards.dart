import 'package:flutter/material.dart';
import '../theme/uranio_theme.dart';
import 'section_card.dart';

/// ---------------------------------------------------------------------
/// DROP DE FOTO
/// ---------------------------------------------------------------------
class PhotoDropCard extends StatelessWidget {
  final String? imageUrl;
  final String? authorName;
  const PhotoDropCard({super.key, this.imageUrl, this.authorName});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      heroTag: 'photo-drop-card',
      fullViewBuilder: (_) => _PhotoDropFullView(imageUrl: imageUrl, authorName: authorName),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.camera_alt_rounded, color: UranioColors.accent, size: 18),
              SizedBox(width: 8),
              Text('Último Drop',
                  style: TextStyle(color: UranioColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          if (imageUrl == null)
            const Text('Aún no hay drops hoy', style: TextStyle(color: UranioColors.textSecondary, fontSize: 13))
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(aspectRatio: 16 / 9, child: Image.network(imageUrl!, fit: BoxFit.cover)),
            ),
          if (authorName != null) ...[
            const SizedBox(height: 8),
            Text('por $authorName', style: const TextStyle(color: UranioColors.textSecondary, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _PhotoDropFullView extends StatelessWidget {
  final String? imageUrl;
  final String? authorName;
  const _PhotoDropFullView({this.imageUrl, this.authorName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Drops')),
      body: Center(
        child: imageUrl == null
            ? const Text('Sin drops todavía', style: TextStyle(color: UranioColors.textSecondary))
            : InteractiveViewer(child: Image.network(imageUrl!)),
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// HISTORIAS DE VOZ (24h) + PINES
/// ---------------------------------------------------------------------
class VoiceStoryPreview {
  final String userId;
  final String userName;
  final String avatarUrl;
  final bool hasActiveStory;
  final bool isPinned;

  VoiceStoryPreview({
    required this.userId,
    required this.userName,
    required this.avatarUrl,
    this.hasActiveStory = false,
    this.isPinned = false,
  });
}

class VoiceStoriesCard extends StatelessWidget {
  final List<VoiceStoryPreview> stories;
  final List<VoiceStoryPreview> pins;
  const VoiceStoriesCard({super.key, required this.stories, this.pins = const []});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      heroTag: 'voice-stories-card',
      fullViewBuilder: (_) => _VoiceStoriesFullView(stories: stories, pins: pins),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.mic_rounded, color: UranioColors.accent, size: 18),
              SizedBox(width: 8),
              Text('Historias de voz',
                  style: TextStyle(color: UranioColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 58,
            child: stories.isEmpty
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Sin historias activas', style: TextStyle(color: UranioColors.textSecondary, fontSize: 13)),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: stories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final s = stories[i];
                      return Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: s.hasActiveStory ? UranioColors.accent : Colors.transparent, width: 2),
                        ),
                        child: CircleAvatar(radius: 20, backgroundImage: NetworkImage(s.avatarUrl)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _VoiceStoriesFullView extends StatelessWidget {
  final List<VoiceStoryPreview> stories;
  final List<VoiceStoryPreview> pins;
  const _VoiceStoriesFullView({required this.stories, required this.pins});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historias y pines')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Activas (24h)', style: TextStyle(color: UranioColors.textPrimary, fontWeight: FontWeight.w700)),
          ...stories.map((s) => ListTile(
                leading: CircleAvatar(backgroundImage: NetworkImage(s.avatarUrl)),
                title: Text(s.userName, style: const TextStyle(color: UranioColors.textPrimary)),
              )),
          const SizedBox(height: 20),
          const Text('Fijados', style: TextStyle(color: UranioColors.textPrimary, fontWeight: FontWeight.w700)),
          ...pins.map((s) => ListTile(
                leading: CircleAvatar(backgroundImage: NetworkImage(s.avatarUrl)),
                title: Text(s.userName, style: const TextStyle(color: UranioColors.textPrimary)),
              )),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// TOP ELO
/// ---------------------------------------------------------------------
class EloEntry {
  final String userName;
  final int elo;
  final int rank;
  EloEntry({required this.userName, required this.elo, required this.rank});
}

class EloCard extends StatelessWidget {
  final List<EloEntry> ranking;
  const EloCard({super.key, required this.ranking});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      heroTag: 'elo-card',
      fullViewBuilder: (_) => _EloFullView(ranking: ranking),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.emoji_events_rounded, color: UranioColors.accent, size: 18),
              SizedBox(width: 8),
              Text('Top Elo', style: TextStyle(color: UranioColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          ...ranking.take(3).map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Text('#${e.rank}', style: const TextStyle(color: UranioColors.accent, fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(e.userName, style: const TextStyle(color: UranioColors.textPrimary, fontSize: 13))),
                    Text('${e.elo}', style: const TextStyle(color: UranioColors.textSecondary, fontSize: 13)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _EloFullView extends StatelessWidget {
  final List<EloEntry> ranking;
  const _EloFullView({required this.ranking});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ranking Elo')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: ranking.length,
        itemBuilder: (context, i) {
          final e = ranking[i];
          return ListTile(
            leading: Text('#${e.rank}', style: const TextStyle(color: UranioColors.accent, fontWeight: FontWeight.w700)),
            title: Text(e.userName, style: const TextStyle(color: UranioColors.textPrimary)),
            trailing: Text('${e.elo} pts', style: const TextStyle(color: UranioColors.textSecondary)),
          );
        },
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// PRÓXIMOS PLANES
/// ---------------------------------------------------------------------
class QuickPlan {
  final String title;
  final DateTime when;
  final int confirmedCount;
  QuickPlan({required this.title, required this.when, this.confirmedCount = 0});
}

class PlansCard extends StatelessWidget {
  final List<QuickPlan> plans;
  const PlansCard({super.key, required this.plans});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      heroTag: 'plans-card',
      fullViewBuilder: (_) => _PlansFullView(plans: plans),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.event_rounded, color: UranioColors.accent, size: 18),
              SizedBox(width: 8),
              Text('Próximos planes',
                  style: TextStyle(color: UranioColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          if (plans.isEmpty)
            const Text('No hay planes por ahora', style: TextStyle(color: UranioColors.textSecondary, fontSize: 13))
          else
            ...plans.take(2).map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text(p.title, style: const TextStyle(color: UranioColors.textPrimary, fontSize: 13))),
                      Text('${p.confirmedCount} van', style: const TextStyle(color: UranioColors.accent, fontSize: 12)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class _PlansFullView extends StatelessWidget {
  final List<QuickPlan> plans;
  const _PlansFullView({required this.plans});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Planes')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: plans.length,
        itemBuilder: (context, i) {
          final p = plans[i];
          return ListTile(
            title: Text(p.title, style: const TextStyle(color: UranioColors.textPrimary)),
            subtitle: Text('${p.when}', style: const TextStyle(color: UranioColors.textSecondary)),
            trailing: Text('${p.confirmedCount} confirmados', style: const TextStyle(color: UranioColors.accent)),
          );
        },
      ),
    );
  }
}
