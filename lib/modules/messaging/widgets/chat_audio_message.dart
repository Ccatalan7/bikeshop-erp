import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/message.dart';
import '../services/chat_media_cache.dart';

/// A voice note or audio file in the timeline: play/pause, a scrubber, the
/// elapsed and total time. The bytes come from the device cache — once per
/// device, then instantly — through the same path as images.
///
/// One player per bubble is fine: a bubble that scrolls out of view is
/// disposed and stops; two notes never play at once because starting one
/// stops the one that was playing.
class ChatAudioMessage extends StatefulWidget {
  const ChatAudioMessage({
    super.key,
    required this.message,
    required this.resolveUrl,
    required this.isMe,
    this.width = 240,
  });

  final Message message;
  final Future<String?> Function() resolveUrl;
  final bool isMe;
  final double width;

  static const Key playKey = Key('chat-audio-play');

  @override
  State<ChatAudioMessage> createState() => _ChatAudioMessageState();
}

class _ChatAudioMessageState extends State<ChatAudioMessage> {
  static _ChatAudioMessageState? _playing;

  final AudioPlayer _player = AudioPlayer();
  final ChatMediaCache _cache = ChatMediaCache.instance;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<PlayerState>? _stateSub;

  Duration _position = Duration.zero;
  Duration? _duration;
  bool _isPlaying = false;
  bool _loading = false;
  bool _failed = false;
  bool _sourceReady = false;

  @override
  void initState() {
    super.initState();
    _durationSub = _player.onDurationChanged.listen((value) {
      if (mounted && value > Duration.zero) setState(() => _duration = value);
    });
    _positionSub = _player.onPositionChanged.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    });
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });
    final seconds = _declaredSeconds();
    if (seconds != null) _duration = Duration(seconds: seconds);
  }

  int? _declaredSeconds() {
    final raw = widget.message.metadata['duration_seconds'] ??
        widget.message.metadata['durationSeconds'];
    if (raw is num) return raw.round();
    return int.tryParse(raw?.toString() ?? '');
  }

  @override
  void dispose() {
    if (identical(_playing, this)) _playing = null;
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String? get _key => ChatMediaCache.keyFor(widget.message);

  String? _extension() {
    final value = widget.message.metadata['extension']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<bool> _prepareSource() async {
    if (_sourceReady) return true;
    final key = _key;
    if (key == null) return false;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      // Voice notes from WhatsApp arrive as OGG/Opus, which Apple players
      // cannot decode; the media function stores a WAV twin next to them
      // and points to it here.
      final playbackKey = _playbackKey() ?? key;
      Uint8List? bytes = await _cache.read(playbackKey);
      bytes ??= await _cache.fetch(
        playbackKey,
        resolveUrl: widget.resolveUrl,
        fileExtension: playbackKey == key ? _extension() : 'wav',
      );
      if (bytes == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _failed = true;
          });
        }
        return false;
      }
      final path = kIsWeb ? null : await _cache.filePath(playbackKey);
      if (path != null) {
        await _player.setSource(DeviceFileSource(path));
      } else {
        await _player.setSource(BytesSource(bytes));
      }
      _sourceReady = true;
      if (mounted) setState(() => _loading = false);
      return true;
    } catch (error) {
      debugPrint('ChatAudioMessage: no se pudo preparar el audio: $error');
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return false;
    }
  }

  String? _playbackKey() {
    final path = widget.message.metadata['playback_storage_path']?.toString();
    if (path == null || path.trim().isEmpty) return null;
    return 'path:${path.trim()}';
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.pause();
      return;
    }
    final ready = await _prepareSource();
    if (!ready || !mounted) return;
    final other = _playing;
    if (other != null && !identical(other, this) && other.mounted) {
      await other._player.pause();
    }
    _playing = this;
    await _player.resume();
  }

  Future<void> _seek(double fraction) async {
    final total = _duration;
    if (total == null || !_sourceReady) return;
    final target = Duration(
      milliseconds: (total.inMilliseconds * fraction).round(),
    );
    await _player.seek(target);
    if (mounted) setState(() => _position = target);
  }

  static String _clock(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = widget.isMe ? scheme.onPrimary : scheme.onSurface;
    final muted = foreground.withValues(alpha: 0.72);
    final total = _duration;
    final progress = total == null || total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final shown = _isPlaying || _position > Duration.zero ? _position : total;

    return SizedBox(
      width: widget.width,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: _loading
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                : IconButton(
                    key: ChatAudioMessage.playKey,
                    padding: EdgeInsets.zero,
                    tooltip: _failed
                        ? 'No se pudo cargar. Toca para reintentar.'
                        : _isPlaying
                            ? 'Pausar'
                            : 'Reproducir',
                    onPressed: _toggle,
                    icon: Icon(
                      _failed
                          ? Icons.refresh_rounded
                          : _isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                      color: foreground,
                      size: 30,
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: foreground,
                    inactiveTrackColor: foreground.withValues(alpha: 0.3),
                    thumbColor: foreground,
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: _sourceReady ? _seek : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6, right: 6),
                  child: Text(
                    shown == null ? 'Nota de voz' : _clock(shown),
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
