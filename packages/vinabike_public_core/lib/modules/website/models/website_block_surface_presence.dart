/// The keys of a block's authored surface inside its shared map
/// (`WebsiteBlockSurfaceFields` in the app owns the schema): `block_data
/// .style` when that value is a map, otherwise `block_data.surfaceStyle` (a
/// standalone button keeps its variant in the scalar `style`).
const websiteBlockSurfaceMapKeys = <String>{
  'paddingTop',
  'paddingRight',
  'paddingBottom',
  'paddingLeft',
  'backgroundType',
  'backgroundColor',
  'gradientColor1',
  'gradientColor2',
  'gradientDirection',
  'borderWidth',
  'borderColor',
  'borderRadius',
  'borderStyle',
  'shadowEnabled',
  'shadowOffsetX',
  'shadowOffsetY',
  'shadowBlur',
  'shadowSpread',
  'shadowColor',
};

/// Whether [data] gives the block a surface of its own: a background, a
/// frame or padding written in the block's style, or a padding override for
/// a phone or tablet (`responsive.<viewport>.surfacePadding…`). A renderer
/// that does not paint surfaces yet treats such a block as one it does not
/// draw, so the page is never shown without what the editor saved.
bool websiteBlockHasAuthoredSurface(Map<String, dynamic> data) {
  final base = data['style'] is Map ? data['style'] : data['surfaceStyle'];
  if (base is Map &&
      base.entries.any(
        (entry) =>
            websiteBlockSurfaceMapKeys.contains(entry.key) &&
            entry.value != null,
      )) {
    return true;
  }
  final responsive = data['responsive'];
  if (responsive is Map) {
    for (final viewport in responsive.values) {
      if (viewport is Map &&
          viewport.entries.any(
            (entry) =>
                entry.key.toString().startsWith('surfacePadding') &&
                entry.value != null,
          )) {
        return true;
      }
    }
  }
  return false;
}
