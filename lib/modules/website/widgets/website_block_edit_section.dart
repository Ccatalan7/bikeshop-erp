/// The three groups a block inspector exposes, named once for every host.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 · `T-04 VbSubTabs`
/// ("Contenido / Diseño / Estilo").
///
/// It lives in its own file on purpose. The contextual sheet must be able to
/// name a section **without** pulling the deferred editor library into the
/// eager bundle; a type declared inside that library would force the load at
/// the first mention.
enum WebsiteBlockEditSection {
  content('Contenido'),
  layout('Diseño'),
  style('Estilo');

  const WebsiteBlockEditSection(this.label);

  /// The exact word t10 uses. Not a key, not a class name — the visible label.
  final String label;
}
