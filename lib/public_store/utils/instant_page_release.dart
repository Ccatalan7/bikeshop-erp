import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import '../../shared/utils/web_url.dart';

/// Avisa a la página instantánea (docs/architecture/storefront-instant-page.md)
/// que la ruta ya tiene sus datos en pantalla. Se retira después del frame
/// que los dibuja, así no queda un cuadro vacío entre las dos.
///
/// Con [imageUrl] espera además a que la foto principal esté decodificada, a
/// lo sumo [imageWait]: la instantánea ya la mostraba, y retirarla antes deja
/// ver el marco vacío mientras la tienda la decodifica. Sólo cuenta el primer
/// aviso de la carga de la página.
void releaseInstantPageWhenReady(
  BuildContext context,
  String reason, {
  String? imageUrl,
  Duration imageWait = const Duration(milliseconds: 1500),
}) {
  if (!kIsWeb || _releaseScheduled) return;
  _releaseScheduled = true;
  final image = imageUrl?.trim() ?? '';
  final ready = image.isEmpty
      ? Future<void>.value()
      : precacheImage(NetworkImage(image), context)
          .catchError((Object _) {})
          .timeout(imageWait, onTimeout: () {});
  unawaited(ready.whenComplete(() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => releaseInstantPage(reason))
      ..scheduleFrame();
  }));
}

bool _releaseScheduled = false;
