import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Desktop/Mobile implementation for video banner
/// Uses native video_player with a robust global controller cache.
class VideoBannerPlatform {
  static Widget buildVideoBackground({
    required String? youtubeVideoId,
    required String? videoFileUrl,
    required double width,
    required double height,
  }) {
    if (youtubeVideoId != null && youtubeVideoId.isNotEmpty) {
      return _YouTubeNativePlayer(
        key: ValueKey('yt-$youtubeVideoId'),
        videoId: youtubeVideoId,
        width: width,
        height: height,
      );
    }
    return const SizedBox.shrink();
  }

  static bool get isSupported => true;
}

class SharedVideoController {
  final VideoPlayerController controller;
  bool _isDisposed = false;

  SharedVideoController(this.controller);

  bool get isDisposed => _isDisposed;

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await controller.dispose();
  }
}

/// Manages playing video controllers to allow seamless reuse across widget rebuilds
class _VideoControllerManager {
  static final _VideoControllerManager _instance = _VideoControllerManager._();
  factory _VideoControllerManager() => _instance;
  _VideoControllerManager._();

  final Map<String, SharedVideoController> _controllers = {};
  final Map<String, Future<SharedVideoController?>> _pendingInits = {};
  final Map<String, int> _refCount = {};
  final Map<String, Timer> _disposalTimers = {};

  Future<SharedVideoController?> getController(String videoId) async {
    // 1. Resurrect: If scheduled for disposal, cancel it!
    if (_disposalTimers.containsKey(videoId)) {
      _disposalTimers[videoId]?.cancel();
      _disposalTimers.remove(videoId);
    }

    // 2. Reuse active controller
    if (_controllers.containsKey(videoId)) {
      final shared = _controllers[videoId]!;
      if (!shared.isDisposed) {
        _refCount[videoId] = (_refCount[videoId] ?? 0) + 1;
        return shared;
      } else {
        _controllers.remove(videoId); // verify cleanup
      }
    }

    // 3. Join pending init if exists (Dedup)
    if (_pendingInits.containsKey(videoId)) {
      final shared = await _pendingInits[videoId];
      if (shared != null && !shared.isDisposed) {
        _refCount[videoId] = (_refCount[videoId] ?? 0) + 1;
        return shared;
      }
      // If pending init failed or returned disposed, continue to create new
    }

    // 4. Create New
    final future = _initializeController(videoId);
    _pendingInits[videoId] = future;

    final shared = await future;
    _pendingInits.remove(videoId); // Done

    if (shared != null) {
      _controllers[videoId] = shared;
      _refCount[videoId] = 1; // First ref
    }
    return shared;
  }

  Future<SharedVideoController?> _initializeController(String videoId) async {
    try {
      var yt = YoutubeExplode();
      var manifest = await yt.videos.streamsClient.getManifest(videoId);
      var streamInfo = manifest.muxed.withHighestBitrate();
      yt.close();

      final controller = VideoPlayerController.networkUrl(streamInfo.url);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();

      return SharedVideoController(controller);
    } catch (e) {
      debugPrint('Error initializing controller for $videoId: $e');
      return null;
    }
  }

  void releaseController(String videoId) {
    if (_refCount.containsKey(videoId)) {
      _refCount[videoId] = (_refCount[videoId] ?? 1) - 1;
    }

    // If no one is using it, schedule disposal
    if ((_refCount[videoId] ?? 0) <= 0) {
      // Cancel any existing timer to reset the clock
      _disposalTimers[videoId]?.cancel();

      // Wait 2 seconds before actually killing it.
      // This is plenty of time for drag/drop re-mounts.
      _disposalTimers[videoId] = Timer(const Duration(seconds: 2), () {
        _cleanUp(videoId);
      });
    }
  }

  void _cleanUp(String videoId) {
    if ((_refCount[videoId] ?? 0) > 0) return; // Resurrected!

    _disposalTimers.remove(videoId);

    final shared = _controllers[videoId];
    if (shared != null) {
      shared.dispose().catchError((e) => debugPrint('Dispose error: $e'));
      _controllers.remove(videoId);
    }
    _refCount.remove(videoId);
  }
}

class _YouTubeNativePlayer extends StatefulWidget {
  final String videoId;
  final double width;
  final double height;

  const _YouTubeNativePlayer({
    super.key,
    required this.videoId,
    required this.width,
    required this.height,
  });

  @override
  State<_YouTubeNativePlayer> createState() => _YouTubeNativePlayerState();
}

class _YouTubeNativePlayerState extends State<_YouTubeNativePlayer> {
  SharedVideoController? _sharedController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    _VideoControllerManager().getController(widget.videoId).then((shared) {
      if (!mounted) {
        if (shared != null) {
          _VideoControllerManager().releaseController(widget.videoId);
        }
        return;
      }
      setState(() {
        _sharedController = shared;
        _isLoading = shared == null;
      });
    });
  }

  @override
  void didUpdateWidget(covariant _YouTubeNativePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _VideoControllerManager().releaseController(oldWidget.videoId);
      setState(() {
        _sharedController = null;
        _isLoading = true;
      });
      _connect();
    }
  }

  @override
  void dispose() {
    _VideoControllerManager().releaseController(widget.videoId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading ||
        _sharedController == null ||
        _sharedController!.isDisposed) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: Colors.black54,
        child: const Center(
            child: SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white54))),
      );
    }

    // Safety: check initialized
    if (!_sharedController!.controller.value.isInitialized) {
      return Container(
          width: widget.width, height: widget.height, color: Colors.black);
    }

    return ClipRect(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _sharedController!.controller.value.size.width,
            height: _sharedController!.controller.value.size.height,
            child: VideoPlayer(_sharedController!.controller),
          ),
        ),
      ),
    );
  }
}
