import 'package:flutter/material.dart';
import '../theme/uranio_theme.dart';
import 'section_card.dart';

class LobbyMember {
  final String id;
  final String name;
  final String avatarUrl;
  final bool isSpeaking;
  final bool isInLobby;

  LobbyMember({
    required this.id,
    required this.name,
    required this.avatarUrl,
    this.isSpeaking = false,
    this.isInLobby = false,
  });
}

class LobbyCard extends StatelessWidget {
  final List<LobbyMember> members;
  const LobbyCard({super.key, required this.members});

  @override
  Widget build(BuildContext context) {
    final activeCount = members.where((m) => m.isInLobby).length;
    return SectionCard(
      heroTag: 'lobby-card',
      glow: activeCount > 0,
      fullViewBuilder: (_) => _LobbyFullView(members: members),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.podcasts_rounded, color: UranioColors.accent, size: 18),
              const SizedBox(width: 8),
              const Text('Lobby',
                  style: TextStyle(color: UranioColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              Text('$activeCount activos', style: const TextStyle(color: UranioColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: members.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _VoiceRingAvatar(member: members[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceRingAvatar extends StatefulWidget {
  final LobbyMember member;
  const _VoiceRingAvatar({required this.member});

  @override
  State<_VoiceRingAvatar> createState() => _VoiceRingAvatarState();
}

class _VoiceRingAvatarState extends State<_VoiceRingAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;

    if (!m.isInLobby) {
      return Opacity(
        opacity: 0.45,
        child: CircleAvatar(radius: 26, backgroundImage: NetworkImage(m.avatarUrl)),
      );
    }

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = m.isSpeaking ? 1.0 + (_pulseController.value * 0.12) : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: m.isSpeaking ? UranioColors.accent : UranioColors.accent.withOpacity(0.35),
            width: m.isSpeaking ? 2.5 : 2,
          ),
          boxShadow: m.isSpeaking
              ? [BoxShadow(color: UranioColors.accent.withOpacity(0.5), blurRadius: 10, spreadRadius: 1)]
              : null,
        ),
        child: CircleAvatar(radius: 24, backgroundImage: NetworkImage(m.avatarUrl)),
      ),
    );
  }
}

class _LobbyFullView extends StatelessWidget {
  final List<LobbyMember> members;
  const _LobbyFullView({required this.members});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lobby')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: members.length,
        itemBuilder: (context, i) {
          final m = members[i];
          return ListTile(
            leading: CircleAvatar(backgroundImage: NetworkImage(m.avatarUrl)),
            title: Text(m.name, style: const TextStyle(color: UranioColors.textPrimary)),
            subtitle: Text(
              m.isSpeaking ? 'Hablando…' : (m.isInLobby ? 'En el lobby' : 'Desconectado'),
              style: const TextStyle(color: UranioColors.textSecondary),
            ),
          );
        },
      ),
    );
  }
}
