import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Una marca casi cuadrada llena el círculo; una muy ancha o muy alta se
/// contiene, porque recortarla a un círculo deja las letras del medio.
///
/// Una foto de persona siempre llena: es como se ve bien una cara.
@visibleForTesting
bool counterpartyImageFillsCircle({
  required bool isMark,
  required double aspectRatio,
}) {
  if (!isMark) return true;
  return aspectRatio >= 0.8 && aspectRatio <= 1.25;
}

/// La imagen de la contraparte de una conversación, en el círculo del avatar.
///
/// **Llena el círculo, como WhatsApp.** Los logos de proveedor se preparan
/// cuadrados —el avatar de su página, o la marca centrada con aire propio— y
/// dibujarlos contenidos con un 14 % de margen los dejaba a dos tercios del
/// avatar, sobre un anillo de color que no dice nada (pedido del dueño,
/// 2026-09-18). Lo que decide si llena es **la forma real de la imagen**, no el
/// tipo de contraparte: «Agregar imagen…» en la ficha acepta cualquier archivo,
/// y un logotipo de 415×77 —el primero de TeknoBike— recortado a un círculo son
/// tres letras. Esa forma se lee de la imagen decodificada; mientras no llega,
/// se ve el respaldo, y la fila no cambia de tamaño.
class CounterpartyAvatarImage extends StatefulWidget {
  const CounterpartyAvatarImage({
    super.key,
    required this.url,
    required this.size,
    required this.isMark,
    required this.backdrop,
    required this.fallback,
  });

  final String url;
  final double size;

  /// La imagen es la marca de una organización (un proveedor), no una cara.
  final bool isMark;

  /// Lo que se ve detrás de una imagen transparente o contenida.
  final Color backdrop;

  /// Lo que se muestra mientras carga y si falla.
  final Widget fallback;

  @override
  State<CounterpartyAvatarImage> createState() =>
      _CounterpartyAvatarImageState();
}

class _CounterpartyAvatarImageState extends State<CounterpartyAvatarImage> {
  ImageProvider? _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _aspectRatio;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(CounterpartyAvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.size != widget.size) {
      _resolve();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _resolve() {
    final pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final side = (widget.size * pixelRatio).ceil();
    // `fit` conserva la proporción al decodificar: con `exact` (lo que hace
    // pedir ancho y alto a la vez) una imagen ancha llega cuadrada y la forma
    // que decide si llena el círculo se pierde antes de leerla.
    final provider = ResizeImage(
      CachedNetworkImageProvider(widget.url, cacheKey: widget.url),
      width: side,
      height: side,
      policy: ResizeImagePolicy.fit,
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _detach();
    _provider = provider;
    _aspectRatio = null;
    _failed = false;
    final listener = ImageStreamListener(
      (info, _) {
        final image = info.image;
        final ratio = image.height == 0 ? 1.0 : image.width / image.height;
        info.dispose();
        if (!mounted || ratio == _aspectRatio) return;
        setState(() => _aspectRatio = ratio);
      },
      onError: (_, __) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _detach() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final ratio = _aspectRatio;
    if (_failed || provider == null || ratio == null) return widget.fallback;

    final fills = counterpartyImageFillsCircle(
      isMark: widget.isMark,
      aspectRatio: ratio,
    );
    return Container(
      width: widget.size,
      height: widget.size,
      padding: fills ? EdgeInsets.zero : EdgeInsets.all(widget.size * 0.14),
      decoration: BoxDecoration(
        color: widget.backdrop,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image(
        image: provider,
        fit: fills ? BoxFit.cover : BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => widget.fallback,
      ),
    );
  }
}
