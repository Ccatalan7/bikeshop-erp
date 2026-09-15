import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// What a finished recording hands back to the composer.
class ChatVoiceNote {
  const ChatVoiceNote({
    required this.bytes,
    required this.fileName,
    required this.duration,
  });

  final Uint8List bytes;
  final String fileName;
  final Duration duration;
}

/// Records a voice note as AAC in an `.m4a` container — the one audio format
/// every target (macOS, iOS, Android, web) encodes, and one WhatsApp accepts
/// as an audio message. Lives while the recording bar is shown; the
/// composer owns the sending.
class ChatVoiceRecorderController extends ChangeNotifier {
  ChatVoiceRecorderController();

  static const Duration maxDuration = Duration(minutes: 5);

  // Created on the first tap, not with the composer: constructing the
  // recorder opens its platform channel, and a session without the plugin
  // (a hot reload after adding it) must not throw while idle.
  AudioRecorder? _recorderInstance;
  AudioRecorder get _recorder => _recorderInstance ??= AudioRecorder();
  Timer? _ticker;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  bool _disposed = false;
  String? _error;

  Duration get elapsed => _elapsed;
  bool get isRecording => _recording;
  String? get error => _error;

  /// Starts recording. Returns `false` (with [error] set) when the microphone
  /// is not available or permission was refused.
  Future<bool> start() async {
    if (_recording) return true;
    _error = null;
    try {
      if (!await _recorder.hasPermission()) {
        _error = 'Sin permiso para usar el micrófono.';
        notifyListeners();
        return false;
      }
      String path = '';
      if (!kIsWeb) {
        final directory = await getTemporaryDirectory();
        path =
            '${directory.path}/nota-de-voz-${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      _startedAt = DateTime.now();
      _elapsed = Duration.zero;
      _recording = true;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        final startedAt = _startedAt;
        if (startedAt == null || _disposed) return;
        _elapsed = DateTime.now().difference(startedAt);
        if (_elapsed >= maxDuration) {
          unawaited(stop());
          return;
        }
        notifyListeners();
      });
      notifyListeners();
      return true;
    } on MissingPluginException {
      // The recorder plugin links at build time: a session that was only hot
      // reloaded after adding it has no microphone until the next launch.
      _error = 'Reinicia la app para habilitar las notas de voz.';
      _recording = false;
      notifyListeners();
      return false;
    } catch (error) {
      _error = 'No se pudo iniciar la grabación: $error';
      _recording = false;
      notifyListeners();
      return false;
    }
  }

  Completer<ChatVoiceNote?>? _stopping;

  /// Stops and returns the note, or `null` when nothing usable was recorded.
  Future<ChatVoiceNote?> stop() async {
    final pending = _stopping;
    if (pending != null) return pending.future;
    if (!_recording) return null;
    final completer = Completer<ChatVoiceNote?>();
    _stopping = completer;
    _ticker?.cancel();
    _ticker = null;
    final duration =
        _startedAt == null ? _elapsed : DateTime.now().difference(_startedAt!);
    try {
      final output = await _recorder.stop();
      _recording = false;
      notifyListeners();
      if (output == null || output.isEmpty) {
        completer.complete(null);
        return completer.future;
      }
      final bytes = await _readOutput(output);
      if (bytes == null || bytes.isEmpty || duration.inMilliseconds < 400) {
        completer.complete(null);
        return completer.future;
      }
      completer.complete(
        ChatVoiceNote(
          bytes: bytes,
          fileName: 'nota-de-voz-${DateTime.now().millisecondsSinceEpoch}.m4a',
          duration: duration,
        ),
      );
    } catch (error) {
      _error = 'No se pudo cerrar la grabación: $error';
      _recording = false;
      notifyListeners();
      completer.complete(null);
    } finally {
      _stopping = null;
    }
    return completer.future;
  }

  Future<Uint8List?> _readOutput(String output) async {
    if (kIsWeb) {
      final response = await http.get(Uri.parse(output));
      return response.statusCode == 200 ? response.bodyBytes : null;
    }
    final file = File(output);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    unawaited(file.delete().catchError((_) => file));
    return bytes;
  }

  /// Discards the recording.
  Future<void> cancel() async {
    _ticker?.cancel();
    _ticker = null;
    if (_recording) {
      try {
        final output = await _recorder.stop();
        if (!kIsWeb && output != null && output.isNotEmpty) {
          unawaited(File(output).delete().catchError((_) => File(output)));
        }
      } catch (_) {
        // Nothing to keep either way.
      }
    }
    _recording = false;
    _elapsed = Duration.zero;
    _startedAt = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    final recorder = _recorderInstance;
    if (recorder != null) unawaited(recorder.dispose());
    super.dispose();
  }
}

/// The bar that replaces the text field while a note is being recorded:
/// a red dot, the elapsed time, cancel, and send.
class ChatVoiceRecordingBar extends StatelessWidget {
  const ChatVoiceRecordingBar({
    super.key,
    required this.controller,
    required this.onCancel,
    required this.onSend,
  });

  final ChatVoiceRecorderController controller;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  static const Key cancelKey = Key('chat-voice-cancel');
  static const Key sendKey = Key('chat-voice-send');

  static String clock(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final error = controller.error;
        return Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: error == null ? scheme.error : scheme.outline,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  error ?? 'Grabando · ${clock(controller.elapsed)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              IconButton(
                key: cancelKey,
                tooltip: 'Descartar',
                onPressed: onCancel,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              if (error == null)
                IconButton(
                  key: sendKey,
                  tooltip: 'Enviar nota de voz',
                  onPressed: onSend,
                  icon: Icon(Icons.send_rounded, color: scheme.primary),
                ),
            ],
          ),
        );
      },
    );
  }
}
