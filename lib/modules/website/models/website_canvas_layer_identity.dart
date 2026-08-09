import 'website_canvas_responsive_document.dart';

/// How a Canvas layer names itself to the operator.
///
/// **Why this is typed and not a string built at each call site.** The dock and
/// the `O-05` sheet both have to say which layer is being operated, and they
/// were saying `Bloque · capa` — a sentence that identifies nothing when a
/// canvas holds a headline, a button and three shapes. t10 frame **10d** shows
/// what a layer row says: a kind glyph, a real name, and its responsive state.
/// This is the naming half of that row, owned once so the two surfaces cannot
/// describe the same layer differently.
///
/// The name is the layer's own useful text when it has any — a headline is best
/// identified by its headline — and falls back to the kind. It is never the
/// serialized id.
abstract final class WebsiteCanvasLayerIdentity {
  /// The human word for a layer kind. `10d` labels rows by what they are.
  static String labelForKind(WebsiteCanvasLayerKind kind) => switch (kind) {
        WebsiteCanvasLayerKind.text => 'Texto',
        WebsiteCanvasLayerKind.button => 'Botón',
        WebsiteCanvasLayerKind.image => 'Imagen',
        WebsiteCanvasLayerKind.shape => 'Forma',
        WebsiteCanvasLayerKind.product => 'Producto',
        WebsiteCanvasLayerKind.productsGallery => 'Galería',
        WebsiteCanvasLayerKind.unknown => 'Capa',
      };

  /// What the operator is told they are editing.
  ///
  /// Useful text first — that is how a person finds the layer they meant — and
  /// the kind when the layer carries none. Trimmed to one line so a paragraph
  /// cannot push a dock row into a second line.
  static String describe(WebsiteCanvasLayerProjection layer) {
    final kindLabel = labelForKind(layer.kind);
    final text = _usefulText(layer);
    if (text == null) return kindLabel;
    return '$kindLabel · $text';
  }

  /// The layer's own words, if it has any worth showing.
  static String? _usefulText(WebsiteCanvasLayerProjection layer) {
    for (final key in const <String>['text', 'label', 'title', 'altText']) {
      final raw = layer.data[key];
      if (raw is! String) continue;
      final value = _oneLine(raw);
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  /// Collapses whitespace and caps the length. A layer name is an identity,
  /// not the content itself.
  static String _oneLine(String raw, {int maxLength = 28}) {
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= maxLength) return collapsed;
    return '${collapsed.substring(0, maxLength - 1)}…';
  }
}
