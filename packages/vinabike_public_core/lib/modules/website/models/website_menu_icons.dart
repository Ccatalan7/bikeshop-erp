/// The icons a header menu item can carry (`website_navigation.icon`), as the
/// editor's «Navegación» offers them: one drawing per part of the bike, in
/// the shop's own words. The wide menu draws them beside its sections and the
/// phone menu beside its rows; the HTML store inlines [WebsiteMenuIcon.svg]
/// and the Flutter canvas paints the same markup.
///
/// Each drawing is a 24 × 24 line icon in `currentColor`, so the menu's
/// colors (and the dark theme) carry it. A key that is not here draws nothing:
/// a row keeps its place without an icon.
final class WebsiteMenuIcon {
  const WebsiteMenuIcon(this.key, this.label, this.body);

  /// What `website_navigation.icon` stores.
  final String key;

  /// The name the editor's picker shows.
  final String label;

  /// The drawing: SVG elements stroked with `currentColor`.
  final String body;

  /// The whole `<svg>`, hidden from assistive technology: the row's words
  /// name it.
  String svg({double size = 20}) {
    final px = size == size.roundToDouble() ? '${size.round()}' : '$size';
    return '<svg width="$px" height="$px" viewBox="0 0 24 24" fill="none" '
        'stroke="currentColor" stroke-width="1.7" stroke-linecap="round" '
        'stroke-linejoin="round" aria-hidden="true">$body</svg>';
  }
}

abstract final class WebsiteMenuIcons {
  /// In the order the picker shows them: the parts of the bike, then what
  /// goes with the rider.
  static const all = <WebsiteMenuIcon>[
    WebsiteMenuIcon(
      'transmision',
      'Transmisión',
      '<circle cx="12" cy="12" r="7.4"/><circle cx="12" cy="12" r="3.6" '
          'stroke-width="1.4"/><circle cx="12" cy="12" r="1.2" '
          'stroke-width="1.3"/><path stroke-width="2" d="M20.11 14.17 21.56 '
          '14.56M17.94 17.94 19 19M14.17 20.11 14.56 21.56M9.83 20.11 9.44 '
          '21.56M6.06 17.94 5 19M3.89 14.17 2.44 14.56M3.89 9.83 2.44 9.44M6.06 '
          '6.06 5 5M9.83 3.89 9.44 2.44M14.17 3.89 14.56 2.44M17.94 6.06 19 '
          '5M20.11 9.83 21.56 9.44"/>',
    ),
    WebsiteMenuIcon(
      'neumatico',
      'Neumático',
      '<circle cx="12" cy="12" r="8.6" stroke-width="2.8"/><circle cx="12" '
          'cy="12" r="4.6" stroke-width="1.5"/><path d="M12 7.4v2.2" '
          'stroke-width="1.6"/>',
    ),
    WebsiteMenuIcon(
      'rueda',
      'Rueda',
      '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="1.7" '
          'stroke-width="1.5"/><path stroke-width="1.3" d="M12 3.6v6.7M12 '
          '13.7v6.7M4.7 7.8l5.8 3.3M13.5 12.9l5.8 3.3M4.7 16.2l5.8-3.3M13.5 '
          '11.1l5.8-3.3"/>',
    ),
    WebsiteMenuIcon(
      'freno',
      'Freno',
      '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="2.6" '
          'stroke-width="1.5"/><g stroke-width="1.3"><circle cx="12" cy="6.2" '
          'r="1"/><circle cx="17.02" cy="9.1" r="1"/><circle cx="17.02" '
          'cy="14.9" r="1"/><circle cx="12" cy="17.8" r="1"/><circle '
          'cx="6.98" cy="14.9" r="1"/><circle cx="6.98" cy="9.1" r="1"/></g>',
    ),
    WebsiteMenuIcon(
      'cambio',
      'Cambio',
      '<g stroke-width="1.6"><circle cx="9" cy="7.5" r="2.6"/><circle '
          'cx="14.5" cy="16.5" r="2.6"/><path d="M6.6 8.9 12 17.8M11.4 6.2l5.4 '
          '9M9 4.9V2.8"/></g>',
    ),
    WebsiteMenuIcon(
      'funda',
      'Fundas y piolas',
      '<path d="M4 19c3.5 0 4.5-3.5 8-3.5s4-7.5 8-7.5M20 8V4"/><circle cx="4" '
          'cy="19" r="1.4" stroke-width="1.5"/>',
    ),
    WebsiteMenuIcon(
      'direccion',
      'Dirección',
      '<path d="M3 8.5c1.8 0 2.6 1.6 4.6 1.6h8.8c2 0 2.8-1.6 4.6-1.6M12 '
          '10.1v7.4M9.2 17.5h5.6"/>',
    ),
    WebsiteMenuIcon(
      'perno',
      'Pernos y otros',
      '<g stroke-width="1.6"><path d="M8.5 3.5h7l1.8 3-1.8 3h-7l-1.8-3zM10.4 '
          '9.5v11h3.2v-11"/><path d="M10.4 13h3.2M10.4 16.2h3.2" '
          'stroke-width="1.2"/></g>',
    ),
    WebsiteMenuIcon(
      'herramienta',
      'Herramienta',
      '<path d="M15.6 3.4a4.4 4.4 0 0 0-4.3 5.7l-7 7a2 2 0 0 0 2.8 2.8l7-7a4.4 '
          '4.4 0 0 0 5.7-4.3l-2.6 2.6-2.5-.7-.7-2.5z"/>',
    ),
    WebsiteMenuIcon(
      'bicicleta',
      'Bicicleta',
      '<circle cx="5.5" cy="15.5" r="3.6"/><circle cx="18.5" cy="15.5" '
          'r="3.6"/><path d="M5.5 15.5 9.5 9.5h6.5M5.5 15.5H11l-1.5-6M11 '
          '15.5l5-6 2.5 6M8 7.5h3M16 9.5l-.8-2.5h2" stroke-width="1.5"/>',
    ),
    WebsiteMenuIcon(
      'casco',
      'Casco',
      '<path d="M3.5 15.5a8.5 8.5 0 0 1 17 0M3.5 15.5h17l-1.5 2.5H6.5z"/>'
          '<path d="M9.5 8.2 11 12.5M14.8 7.6l-.8 4.6" stroke-width="1.4"/>',
    ),
    WebsiteMenuIcon(
      'ropa',
      'Ropa',
      '<path d="M8.5 4 4 6.5l1.8 4 2.2-1V20h8V9.5l2.2 1 1.8-4L15.5 4c-.6 '
          '1.4-1.9 2.2-3.5 2.2S9.1 5.4 8.5 4z"/>',
    ),
    WebsiteMenuIcon(
      'candado',
      'Candado',
      '<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8 '
          '10.5V8a4 4 0 0 1 8 0v2.5M12 14.5v2"/>',
    ),
    WebsiteMenuIcon(
      'luz',
      'Luz',
      '<path d="M4 9.5h7.5a2.5 2.5 0 0 1 0 5H4z"/><path d="M17 8.5l3.5-1.5M17 '
          '12h4M17 15.5l3.5 1.5" stroke-width="1.5"/>',
    ),
    WebsiteMenuIcon(
      'pedal',
      'Pedal',
      '<rect x="5.5" y="7" width="13" height="10" rx="2.5"/><path d="M2.5 '
          '12h3M18.5 12h3"/><path d="M8.5 9.8v4.4M12 9.8v4.4M15.5 9.8v4.4" '
          'stroke-width="1.3"/>',
    ),
    WebsiteMenuIcon(
      'asiento',
      'Asiento',
      '<path d="M3.5 9.6c0-1.4 1.6-2.1 3.5-2.1 3 0 5 1 8 1.6 2.6.5 5.5 1 5.5 '
          '2.6 0 1.2-2 1.8-4.5 1.8-2.7 0-4.4 1.5-7 1.5-3 0-5.5-2.9-5.5-5.4zM12 '
          '14.6V20"/>',
    ),
    WebsiteMenuIcon(
      'bombin',
      'Bombín',
      '<path d="M8 3.5h8M12 3.5V8M6.5 20.5h11"/><rect x="9.5" y="8" width="5" '
          'height="11" rx="1.2"/>',
    ),
  ];

  static final Map<String, WebsiteMenuIcon> _byKey = {
    for (final icon in all) icon.key: icon,
  };

  /// The icon [key] names, or null when there is none (blank or unknown).
  static WebsiteMenuIcon? of(String? key) =>
      key == null ? null : _byKey[key.trim().toLowerCase()];
}
