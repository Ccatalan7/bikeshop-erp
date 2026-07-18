/// Canonical defaults for every editor-native Canvas layer.
///
/// Canvas layers can be created from the canvas, the right inspector, or the
/// edit-mode provider. All entry points must use this factory so new shared
/// capabilities (transform, locking, responsive behavior, crop/focal data)
/// cannot drift between creation surfaces.
Map<String, dynamic> createCanvasElement({
  required String id,
  required String type,
  double x = 24,
  double y = 24,
}) {
  final base = <String, dynamic>{
    'id': id,
    'type': type,
    'x': x,
    'y': y,
    'rotation': 0.0,
    'locked': false,
    'anim': 'none',
  };

  return switch (type) {
    'button' => {
        ...base,
        'w': 220.0,
        'h': 56.0,
        'label': 'Botón',
        'style': 'filled',
        'inheritTheme': true,
        'bgColor': '#00A09D',
        'fgColor': '#FFFFFF',
        'radius': 12.0,
        'fontSize': 14.0,
        'letterSpacing': 0.0,
        'uppercase': false,
        'shadow': false,
        'link': '/',
      },
    'image' => {
        ...base,
        'w': 320.0,
        'h': 200.0,
        'imageUrl': '',
        'productId': '',
        'imageSource': 'manual',
        'fit': 'cover',
        'focalPointX': 0.5,
        'focalPointY': 0.5,
        'radius': 12.0,
        'altText': '',
      },
    'shape' => {
        ...base,
        'w': 320.0,
        'h': 200.0,
        'shape': 'rectangle',
        'fillColor': '#1F2937',
        'borderColor': '#1F2937',
        'borderWidth': 0.0,
        'radius': 0.0,
      },
    'product' => {
        ...base,
        'w': 280.0,
        'h': 320.0,
        'productId': '',
        'showPrice': true,
      },
    'productsGallery' => {
        ...base,
        'w': 520.0,
        'h': 360.0,
        'mode': 'latest',
        'productIds': <String>[],
        'maxProducts': 6,
        'layout': 'grid',
        'columns': 3,
        'cardWidth': 300,
        'showPrice': true,
      },
    _ => {
        ...base,
        'type': 'text',
        'w': 360.0,
        'h': 72.0,
        'text': 'Texto',
        'fontSize': 28.0,
        'fontWeight': 'w700',
        'fontRole': 'heading',
        'color': '#111111',
        'align': 'left',
        'letterSpacing': 0.0,
        'lineHeight': 1.1,
        'uppercase': false,
      },
  };
}
