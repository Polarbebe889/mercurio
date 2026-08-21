import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../config.dart';
import '../main.dart';
import '../models.dart';

class VozScreen extends StatefulWidget {
  const VozScreen({super.key});

  @override
  State<VozScreen> createState() => _VozScreenState();
}

class _VozScreenState extends State<VozScreen> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  bool _grabando = false;
  final Stopwatch _crono = Stopwatch();

  final _pinCtrl = TextEditingController();
  bool _grabandoPin = false;

  @override
  void initState() {
    super.initState();
    _configurarAudio();
  }

  Future<void> _configurarAudio() async {
    try {
      await _player.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ));
      debugPrint('[Voz] AudioContext playback configurado (iOS silencioso OK)');
    } catch (e, st) {
      debugPrint('[Voz] error setAudioContext: $e\n$st');
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _grabar({required bool pin}) async {
    if (_grabando || _grabandoPin) return;
    if (!await _recorder.hasPermission()) {
      _snack('Permiso de micrófono denegado');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('bunker_');
    final path =
        '${dir.path}/voz_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    } catch (e) {
      _snack('No pude grabar: $e');
      return;
    }
    setState(() {
      if (pin) {
        _grabandoPin = true;
      } else {
        _grabando = true;
      }
      _crono..reset()..start();
    });
    await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _grabando = false;
      _grabandoPin = false;
      _crono.stop();
    });
    final seg = _crono.elapsed.inSeconds.clamp(1, 600);
    if (seg < 1) {
      _snack('Grabación muy corta (min 1s)');
      return;
    }
    try {
      if (pin) {
        final caption = await _pedirTexto('Caption del pin', 'Frase del pin');
        await app.api!.subirPin(File(path), caption ?? '', seg);
        _snack('Pin fijado');
      } else {
        await app.api!.subirHistoria(File(path), seg);
        _snack('Historia subida (24h)');
      }
    } catch (e) {
      _snack('$e');
    } finally {
      try {
        File(path).delete();
      } catch (_) {}
    }
  }

  Future<String?> _pedirTexto(String titulo, String hint) {
    final ctrl = TextEditingController(text: _pinCtrl.text);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(controller: ctrl, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _preview(NotaVoz n) async {
    final url = AppConfig.fullUrl(n.audioUrl);
    debugPrint('[Voz] play request: $url (orig: ${n.audioUrl})');
    try {
      // Asegura sesión iOS playback antes de cada play (por si fue interrumpida)
      await _player.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ));
      await _player.stop();
      await _player.play(UrlSource(url));
      _snack('▶ ${n.durationS}s');
      debugPrint('[Voz] play OK: $url');
    } catch (e, st) {
      debugPrint('[Voz] ERROR streaming $url: $e\n$st');
      _snack('Error audio: $e');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Column(
        children: [
          // ── historias activas 24h ──
          SizedBox(
            height: 150,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              children: [
                _botonGrabar(_grabando, () => _grabar(pin: false)),
                for (final n in app.historias) _nota(n),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text('PIN DE AUDIO — permanentemente fijado',
                    style: TextStyle(fontSize: 11, color: Colors.white38))),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => app.recargarTodo(),
              child: app.pines.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 80),
                        Center(
                            child: Text('Sin pines aún',
                                style: TextStyle(color: Colors.white38))),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: app.pines.length,
                      itemBuilder: (context, i) => _PinTile(app.pines[i]),
                    ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF12161A),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _pinCtrl,
                  decoration: const InputDecoration(
                      hintText: 'Fijar audio con frase…', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              _grabandoPin
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton.filled(
                      icon: const Icon(Icons.push_pin),
                      onPressed: () => _grabar(pin: true),
                    ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _botonGrabar(bool grabando, VoidCallback onTap) {
    return GestureDetector(
      onTap: grabando ? null : onTap,
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1C2125),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              grabando ? Icons.fiber_manual_record : Icons.mic,
              color: grabando ? Colors.redAccent : const Color(0xFF22D3EE),
              size: 30,
            ),
            const SizedBox(height: 6),
            Text(grabando ? 'Grabando…' : 'Grabar voz',
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _nota(NotaVoz n) {
    final autor = app.usuarioPorId(n.usuarioId);
    final soy = autor?.id == app.yo?.id;
    return GestureDetector(
      onTap: () => _preview(n),
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF22D3EE), width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${autor?.emoji ?? '🎙️'}',
                style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text('${n.durationS}s',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
            if (soy)
              InkWell(
                onTap: () => app.api!.borrarHistoria(n.id),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 14, color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PinTile extends StatefulWidget {
  final PinAudio pin;
  const _PinTile(this.pin);

  @override
  State<_PinTile> createState() => _PinTileState();
}

class _PinTileState extends State<_PinTile> {
  final _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _configAudioPin();
  }

  Future<void> _configAudioPin() async {
    try {
      await _player.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ));
    } catch (e, st) {
      debugPrint('[Pin] error setAudioContext: $e\n$st');
    }
  }

  Future<void> _playPin(PinAudio pin) async {
    final url = AppConfig.fullUrl(pin.audioUrl);
    debugPrint('[Pin] play $url');
    try {
      await _player.stop();
      await _player.play(UrlSource(url));
      debugPrint('[Pin] play OK: $url');
    } catch (e, st) {
      debugPrint('[Pin] ERROR $url: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error audio: $e')));
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pin = widget.pin;
    final autor = app.usuarioPorId(pin.usuarioId);
    final soy = autor?.id == app.yo?.id;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.push_pin, size: 18),
        ),
        title: Text(pin.caption.isEmpty ? 'audio fijado' : pin.caption,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${autor?.displayName ?? ''} · ${pin.durationS}s'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () => _playPin(pin),
            ),
            if (soy)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => app.api!.borrarPin(pin.id),
              ),
          ],
        ),
      ),
    );
  }
}