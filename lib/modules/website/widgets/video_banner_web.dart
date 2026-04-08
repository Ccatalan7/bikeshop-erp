import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Web implementation for video banner
/// Uses HTML video element and YouTube iframe
class VideoBannerPlatform {
  static int _viewIdCounter = 0;
  static final Set<String> _registeredViews = {};

  static Widget buildVideoBackground({
    required String? youtubeVideoId,
    required String? videoFileUrl,
    required double width,
    required double height,
  }) {
    if (youtubeVideoId != null) {
      return _buildYouTubePlayer(youtubeVideoId, width, height);
    } else if (videoFileUrl != null) {
      return _buildVideoPlayer(videoFileUrl, width, height);
    }
    return const SizedBox.shrink();
  }

  static Widget _buildYouTubePlayer(
      String videoId, double width, double height) {
    final viewId = 'youtube-$videoId-${_viewIdCounter++}';

    if (!_registeredViews.contains(viewId)) {
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        viewId,
        (int id) {
          final iframe =
              web.document.createElement('iframe') as web.HTMLIFrameElement;
          iframe.src =
              'https://www.youtube.com/embed/$videoId?autoplay=1&mute=1&loop=1&playlist=$videoId&controls=0&showinfo=0&rel=0&modestbranding=1&playsinline=1&enablejsapi=1&origin=${web.window.location.origin}';
          iframe.style.border = 'none';
          iframe.style.width = '100%';
          iframe.style.height = '100%';
          iframe.style.position = 'absolute';
          iframe.style.top = '50%';
          iframe.style.left = '50%';
          iframe.style.transform = 'translate(-50%, -50%)';
          iframe.style.minWidth = '177.78vh'; // 16:9 aspect ratio
          iframe.style.minHeight = '56.25vw';
          iframe.style.pointerEvents = 'none';
          iframe.style.zIndex = '-1';
          iframe.allow = 'autoplay; encrypted-media';
          iframe.allowFullscreen = true;

          // Hint to browsers that support it.
          iframe.setAttribute('loading', 'lazy');

          // Wrap in a container div to handle sizing
          final container =
              web.document.createElement('div') as web.HTMLDivElement;
          container.style.width = '100%';
          container.style.height = '100%';
          container.style.position = 'relative';
          container.style.overflow = 'hidden';
          container.style.pointerEvents = 'none';
          container.appendChild(iframe);

          return container;
        },
      );
      _registeredViews.add(viewId);
    }

    return IgnorePointer(
      child: SizedBox(
        width: width,
        height: height,
        child: HtmlElementView(viewType: viewId),
      ),
    );
  }

  static Widget _buildVideoPlayer(
      String videoUrl, double width, double height) {
    final viewId = 'video-${videoUrl.hashCode}-${_viewIdCounter++}';

    if (!_registeredViews.contains(viewId)) {
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        viewId,
        (int id) {
          final video =
              web.document.createElement('video') as web.HTMLVideoElement;
          video.src = videoUrl;
          video.autoplay = true;
          video.muted = true;
          video.loop = true;
          video.style.width = '100%';
          video.style.height = '100%';
          video.style.objectFit = 'cover';
          video.style.position = 'absolute';
          video.style.top = '0';
          video.style.left = '0';
          video.style.zIndex = '-1';
          video.style.pointerEvents = 'none';

          // Wrap in a container div
          final container =
              web.document.createElement('div') as web.HTMLDivElement;
          container.style.width = '100%';
          container.style.height = '100%';
          container.style.position = 'relative';
          container.style.overflow = 'hidden';
          container.style.pointerEvents = 'none';
          container.append(video);

          return container;
        },
      );
      _registeredViews.add(viewId);
    }

    return IgnorePointer(
      child: SizedBox(
        width: width,
        height: height,
        child: HtmlElementView(viewType: viewId),
      ),
    );
  }

  static bool get isSupported => true;
}
