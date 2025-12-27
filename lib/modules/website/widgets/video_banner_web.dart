import 'dart:html' as html;
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
  
  static Widget _buildYouTubePlayer(String videoId, double width, double height) {
    final viewId = 'youtube-$videoId-${_viewIdCounter++}';
    
    if (!_registeredViews.contains(viewId)) {
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        viewId,
        (int id) {
          final iframe = html.IFrameElement()
            ..src = 'https://www.youtube.com/embed/$videoId?autoplay=1&mute=1&loop=1&playlist=$videoId&controls=0&showinfo=0&rel=0&modestbranding=1&playsinline=1&enablejsapi=1&origin=${html.window.location.origin}'
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.position = 'absolute'
            ..style.top = '50%'
            ..style.left = '50%'
            ..style.transform = 'translate(-50%, -50%)'
            ..style.minWidth = '177.78vh' // 16:9 aspect ratio
            ..style.minHeight = '56.25vw'
            ..style.pointerEvents = 'none' // Allow scroll events to pass through
            ..allow = 'autoplay; encrypted-media'
            ..allowFullscreen = true;

          // Hint to browsers that support it.
          // (For above-the-fold videos this may not delay, but it avoids eager load in some cases.)
          iframe.setAttribute('loading', 'lazy');
          
          // Wrap in a container div to handle sizing
          final container = html.DivElement()
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.position = 'relative'
            ..style.overflow = 'hidden'
            ..style.pointerEvents = 'none' // Allow scroll events to pass through
            ..append(iframe);
          
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
  
  static Widget _buildVideoPlayer(String videoUrl, double width, double height) {
    final viewId = 'video-${videoUrl.hashCode}-${_viewIdCounter++}';
    
    if (!_registeredViews.contains(viewId)) {
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        viewId,
        (int id) {
          final video = html.VideoElement()
            ..src = videoUrl
            ..autoplay = true
            ..muted = true
            ..loop = true
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.objectFit = 'cover'
            ..style.position = 'absolute'
            ..style.top = '0'
            ..style.left = '0'
            ..style.pointerEvents = 'none'; // Allow scroll events to pass through
          
          // Wrap in a container div
          final container = html.DivElement()
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.position = 'relative'
            ..style.overflow = 'hidden'
            ..style.pointerEvents = 'none' // Allow scroll events to pass through
            ..append(video);
          
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
