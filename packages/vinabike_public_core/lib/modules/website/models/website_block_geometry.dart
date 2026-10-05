/// How a valid persisted `blockHeight` constrains a Website Builder block.
///
/// The capability registry is the owner of this value. Page composition,
/// editor chrome and the inspector must all consume the same profile.
enum WebsitePageBlockHeightBehavior {
  /// The content uses the persisted height as both its minimum and maximum.
  exact,

  /// The content may grow, but never below the persisted height.
  minimum,

  /// The content owns its intrinsic height and ignores a persisted height.
  intrinsic;

  /// Visible inspector label. Intrinsic content has no height control.
  String? get inspectorLabel => switch (this) {
        WebsitePageBlockHeightBehavior.exact => 'Altura',
        WebsitePageBlockHeightBehavior.minimum => 'Altura mínima',
        WebsitePageBlockHeightBehavior.intrinsic => null,
      };

  /// Help copy shown when the custom height control is expanded.
  String? get inspectorResizeHint => switch (this) {
        WebsitePageBlockHeightBehavior.exact =>
          'También puedes arrastrar el borde inferior del bloque',
        WebsitePageBlockHeightBehavior.minimum =>
          'El contenido puede crecer; arrastra para cambiar el mínimo',
        WebsitePageBlockHeightBehavior.intrinsic => null,
      };
}
