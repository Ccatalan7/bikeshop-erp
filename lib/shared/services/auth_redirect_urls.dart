import 'package:flutter/foundation.dart';

abstract final class AuthRedirectUrls {
  static const String nativeScheme = 'vinabike';
  static const String nativeHost = 'app';

  static String? authCallback({
    required bool isWeb,
    Uri? webBase,
    TargetPlatform? platform,
  }) {
    return _build(
      path: '/auth/callback',
      isWeb: isWeb,
      webBase: webBase,
      platform: platform,
    );
  }

  static String? passwordReset({
    required bool isWeb,
    Uri? webBase,
    TargetPlatform? platform,
  }) {
    return _build(
      path: '/reset-password',
      isWeb: isWeb,
      webBase: webBase,
      platform: platform,
    );
  }

  static String? _build({
    required String path,
    required bool isWeb,
    Uri? webBase,
    TargetPlatform? platform,
  }) {
    if (isWeb) {
      final base = webBase ?? Uri.base;
      return '${base.origin}$path';
    }

    final target = platform ?? defaultTargetPlatform;
    if (target != TargetPlatform.android &&
        target != TargetPlatform.iOS &&
        target != TargetPlatform.macOS) {
      return null;
    }

    return Uri(
      scheme: nativeScheme,
      host: nativeHost,
      path: path,
    ).toString();
  }
}
