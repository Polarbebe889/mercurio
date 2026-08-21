/// Modelos planos del API de El Bunker.

class Musica {
  final String? provider, titulo, artista, album, artworkUrl;
  final bool reproduciendo;

  Musica(this.provider, this.titulo, this.artista, this.album, this.artworkUrl,
      this.reproduciendo);

  factory Musica.fromJson(Map<String, dynamic> j) => Musica(
        j['provider'], j['titulo'], j['artista'], j['album'], j['artwork_url'],
        j['reproduciendo'] ?? false,
      );
}

class Usuario {
  final int id;
  final String username, displayName, emoji, avatarColor;
  final int elo;
  final String? statusText;
  final Musica? musica;
  final List<NotaVoz> notasVoz;

  Usuario(this.id, this.username, this.displayName, this.emoji,
      this.avatarColor, this.elo, this.statusText, this.musica, this.notasVoz);

  factory Usuario.fromJson(Map<String, dynamic> j) => Usuario(
        j['id'], j['username'], j['display_name'], j['emoji'],
        j['avatar_color'], j['elo'] ?? 1000, j['status_text'],
        j['musica'] == null ? null : Musica.fromJson(j['musica']),
        (j['notas_voz'] as List? ?? [])
            .map((e) => NotaVoz.fromJson(e))
            .toList(),
      );
}

class NotaVoz {
  final int id;
  final int usuarioId;
  final String audioUrl;
  final int durationS;
  final DateTime? expiresAt;

  NotaVoz(this.id, this.usuarioId, this.audioUrl, this.durationS, this.expiresAt);

  factory NotaVoz.fromJson(Map<String, dynamic> j) => NotaVoz(
        j['id'], j['usuario_id'], j['audio_url'], j['duration_s'],
        j['expires_at'] == null ? null : DateTime.parse(j['expires_at']),
      );
}

class PinAudio {
  final int id, usuarioId;
  final String audioUrl, caption;
  final int durationS;

  PinAudio(this.id, this.usuarioId, this.audioUrl, this.caption, this.durationS);

  factory PinAudio.fromJson(Map<String, dynamic> j) => PinAudio(
        j['id'], j['usuario_id'], j['audio_url'], j['caption'], j['duration_s']);
}

class Drop {
  final int id, usuarioId;
  final String imgUrl;
  final String? caption;
  final DateTime created;

  Drop(this.id, this.usuarioId, this.imgUrl, this.caption, this.created);

  factory Drop.fromJson(Map<String, dynamic> j) => Drop(
        j['id'], j['usuario_id'], j['img_url'], j['caption'],
        DateTime.parse(j['created_at']));
}

class Partida {
  final int id;
  final String juego;
  final int marcador1, marcador2;
  final int? ganadorId;
  final String? reactionAudio;
  final J1 j1;
  final J2 j2;

  Partida(this.id, this.juego, this.marcador1, this.marcador2, this.ganadorId,
      this.reactionAudio, this.j1, this.j2);

  factory Partida.fromJson(Map<String, dynamic> j) => Partida(
        j['id'], j['juego'], j['marcador1'], j['marcador2'], j['ganador_id'],
        j['reaction_audio'],
        J1(j['jugador1']['id'], j['jugador1']['display_name'],
            j['jugador1']['elo'], j['jugador1']['elo_final']),
        J2(j['jugador2']['id'], j['jugador2']['display_name'],
            j['jugador2']['elo'], j['jugador2']['elo_final']),
      );
}

class J1 {
  final int id;
  final String displayName;
  final int elo, eloFinal;
  J1(this.id, this.displayName, this.elo, this.eloFinal);
}

class J2 {
  final int id;
  final String displayName;
  final int elo, eloFinal;
  J2(this.id, this.displayName, this.elo, this.eloFinal);
}

class RankingRow {
  final int posicion, id, elo, victorias, empates, derrotas;
  final String displayName, emoji;

  RankingRow(this.posicion, this.id, this.elo, this.victorias, this.empates,
      this.derrotas, this.displayName, this.emoji);

  factory RankingRow.fromJson(Map<String, dynamic> j) => RankingRow(
        j['posicion'], j['id'], j['elo'], j['victorias'], j['empates'],
        j['derrotas'], j['display_name'], j['emoji']);
}

class Plan {
  final int id, creadorId;
  final String titulo;
  final String? descripcion, lugar;
  final DateTime startsAt;
  final List<PlanEstado> estados;

  Plan(this.id, this.creadorId, this.titulo, this.descripcion, this.lugar,
      this.startsAt, this.estados);

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
        j['id'], j['creador_id'], j['titulo'], j['descripcion'], j['lugar'],
        DateTime.parse(j['starts_at']),
        (j['estados'] as List? ?? []).map((e) => PlanEstado.fromJson(e)).toList(),
      );

  String estadoDe(int usuarioId) {
    for (var e in estados) {
      if (e.usuarioId == usuarioId) return e.estado;
    }
    return 'sin_confirmar';
  }
}

class PlanEstado {
  final int usuarioId;
  final String estado;

  PlanEstado(this.usuarioId, this.estado);

  factory PlanEstado.fromJson(Map<String, dynamic> j) =>
      PlanEstado(j['usuario_id'], j['estado']);
}