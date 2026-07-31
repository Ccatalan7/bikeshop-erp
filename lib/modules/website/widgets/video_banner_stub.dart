import 'package:flutter/material.dart';

/// Stub implementation for non-web platforms
/// Video banners will show a static image with play button on non-web platforms
class VideoBannerPlatform {
  static Widget buildVideoBackground({
    required String? youtubeVideoId,
    required String? videoFileUrl,
    required double width,
    required double height,
  }) {
    // On non-web platforms, return an empty container
    // The image background will be shown instead
    return const SizedBox.shrink();
  }

  static bool get isSupported => false;
}
