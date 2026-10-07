import 'website_block_type.dart';

/// Where a block keeps one of the photos the editor replaces where it is
/// drawn: the keys of its address (its own first, then older names) and the
/// list it belongs to (a gallery photo, a team member).
///
/// One owner for the editor (2026-10-07): the Flutter canvas's media slots
/// and the photos of the editor's «Vista HTML» name the same fields, and the
/// HTML page names a photo by [spec], never by its keys. The hero's and the
/// carousel's backgrounds are not here on purpose: under their buttons and
/// arrows they are replaced from the panel, as on the canvas.
enum WebsiteImageFields {
  /// The «about» block's photo.
  about(['imageUrl', 'image']),

  /// The call to action's background.
  cta(['backgroundImage', 'imageUrl']),

  /// The services block's photo.
  services(['imageUrl']),

  /// A gallery photo.
  gallery(['imageUrl'], collection: ['images']),

  /// A team member's portrait.
  team(['avatarUrl', 'image'], collection: ['members', 'team', 'items']);

  const WebsiteImageFields(this.keys, {this.collection = const []});

  final List<String> keys;

  /// The list the photo's item is in (its canonical key first); empty for a
  /// photo of the block itself.
  final List<String> collection;

  /// The one block type that draws this photo: a page that names it for any
  /// other block names a photo that block does not have.
  WebsiteBlockType get block => switch (this) {
    about => WebsiteBlockType.about,
    cta => WebsiteBlockType.cta,
    services => WebsiteBlockType.services,
    gallery => WebsiteBlockType.gallery,
    team => WebsiteBlockType.team,
  };

  /// How the editor's HTML names this photo: `about`, or `gallery#2` for the
  /// one of the item stored at [index].
  String spec([int index = 0]) => collection.isEmpty ? name : '$name#$index';

  /// The photo and item position a [spec] names; `null` for anything else.
  static ({WebsiteImageFields fields, int index})? parse(String spec) {
    final hash = spec.indexOf('#');
    final name = hash < 0 ? spec : spec.substring(0, hash);
    WebsiteImageFields? fields;
    for (final value in values) {
      if (value.name == name) fields = value;
    }
    if (fields == null) return null;
    if (fields.collection.isEmpty) {
      return hash < 0 ? (fields: fields, index: 0) : null;
    }
    if (hash < 0) return null;
    final raw = spec.substring(hash + 1);
    final index = RegExp(r'^\d{1,4}$').hasMatch(raw) ? int.parse(raw) : null;
    return index == null ? null : (fields: fields, index: index);
  }
}
