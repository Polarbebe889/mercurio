import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Servicio robusto de grabación de voz para Mercurio.
///
/// CAUSA MÁS PROBABLE DEL CRASH ORIGINAL:
/// 1. Se llamaba a `record.start()` sin verificar el permiso de micrófono
///    primero -> excepción nativa no controlada en Android/iOS.
/// 2. Se llamaba a start() dos veces seguidas (doble tap) sin proteger el
///    estado -> el plugin lanza una excepción porque ya hay una sesión activa.
/// 3. No había try/catch alrededor de las llamadas async del plugin, así que
///    cualquier PlatformException subía sin control hasta tumbar la app.
/// 4. Faltaban las declaraciones de permiso en AndroidManifest.xml / Info.plist
///    (ver notas al final de este archivo).
///
/// Esta versión encapsula TODO el manejo de errores para que la UI nunca
/// reciba una excepción sin capturar.
class AudioRecorderService {
  AudioRecorderService._internal();
  static final AudioRecorderService instance = AudioRecorderService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// Verifica y solicita el permiso de micrófono de forma explícita.
  Future<bool> _ensurePermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted) return true;
    // status.isPermanentlyDenied -> deberías mandar al usuario a Settings
    // con openAppSettings() desde la UI, no aquí.
    return false;
  }

  /// Inicia la grabación. Devuelve la ruta del archivo o `null` si algo
  /// falló — nunca lanza una excepción hacia quien lo llama.
  Future<String?> startRecording() async {
    if (_isRecording) {
      // Protege contra doble-tap / doble-start, causa común del crash.
      debugPrint('[AudioRecorderService] Ya hay una grabación en curso, ignorando start()');
      return null;
    }

    try {
      final hasPermission = await _ensurePermission();
      if (!hasPermission) {
        debugPrint('[AudioRecorderService] Permiso de micrófono denegado');
        return null;
      }

      // Segunda verificación usando el propio plugin, por robustez entre
      // versiones de Android/iOS.
      final recorderHasPermission = await _recorder.hasPermission();
      if (!recorderHasPermission) {
        debugPrint('[AudioRecorderService] record.hasPermission() devolvió false');
        return null;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/mercurio_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _currentPath = path;
      _isRecording = true;
      return path;
    } catch (e, stackTrace) {
      debugPrint('[AudioRecorderService] Error al iniciar grabación: $e');
      debugPrintStack(stackTrace: stackTrace);
      _isRecording = false;
      _currentPath = null;
      return null;
    }
  }

  /// Detiene la grabación y devuelve la ruta del archivo final (o null).
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    try {
      final path = await _recorder.stop();
      _isRecording = false;
      final finalPath = path ?? _currentPath;

      if (finalPath == null) return null;

      final file = File(finalPath);
      if (!await file.exists()) return null;

      final size = await file.length();
      if (size == 0) {
        debugPrint('[AudioRecorderService] Archivo de audio vacío, se descarta');
        return null;
      }
      return finalPath;
    } catch (e) {
      debugPrint('[AudioRecorderService] Error al detener grabación: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Cancela y borra la grabación en curso (ej. el usuario desliza para cancelar).
  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    try {
      await _recorder.cancel();
    } catch (e) {
      debugPrint('[AudioRecorderService] Error al cancelar grabación: $e');
    } finally {
      _isRecording = false;
      if (_currentPath != null) {
        final f = File(_currentPath!);
        if (await f.exists()) await f.delete();
      }
      _currentPath = null;
    }
  }

  /// Libera los recursos nativos del recorder. Llamar SIEMPRE en el
  /// dispose() del widget/controlador que use este servicio.
  Future<void> disposeService() async {
    if (_isRecording) {
      await cancelRecording();
    }
    await _recorder.dispose();
  }
}

/// -----------------------------------------------------------------------
/// EJEMPLO DE USO SEGURO EN UI (hold-to-record) — evita setState() después
/// de dispose(), que es otra causa típica de crashes intermitentes.
/// -----------------------------------------------------------------------
class VoiceRecordButton extends StatefulWidget {
  final void Function(String path) onRecorded;
  const VoiceRecordButton({super.key, required this.onRecorded});

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  bool _recording = false;

  Future<void> _start() async {
    final path = await AudioRecorderService.instance.startRecording();
    if (!mounted) return; // evita setState tras dispose
    if (path != null) {
      setState(() => _recording = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo acceder al micrófono')),
      );
    }
  }

  Future<void> _stop() async {
    final path = await AudioRecorderService.instance.stopRecording();
    if (!mounted) return;
    setState(() => _recording = false);
    if (path != null) widget.onRecorded(path);
  }

  @override
  void dispose() {
    // Si el usuario navega fuera mientras graba, cancelamos en vez de
    // dejar el recorder nativo colgado (fuente de crashes al reabrir).
    if (_recording) {
      AudioRecorderService.instance.cancelRecording();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) => _stop(),
      child: CircleAvatar(
        radius: 34,
        backgroundColor: _recording ? const Color(0xFFEF4444) : const Color(0xFF22D3EE),
        child: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.black),
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// CONFIGURACIÓN NATIVA NECESARIA (sin esto, el permiso nunca se concede
/// y `record` puede lanzar una excepción nativa no controlada):
///
/// android/app/src/main/AndroidManifest.xml
///   <uses-permission android:name="android.permission.RECORD_AUDIO" />
///
/// ios/Runner/Info.plist
///   <key>NSMicrophoneUsageDescription</key>
///   <string>Mercurio necesita el micrófono para enviar notas de voz</string>
///
/// pubspec.yaml (versiones orientativas, ajusta a las últimas estables):
///   record: ^5.1.2
///   permission_handler: ^11.3.1
///   path_provider: ^2.1.3
/// -----------------------------------------------------------------------
