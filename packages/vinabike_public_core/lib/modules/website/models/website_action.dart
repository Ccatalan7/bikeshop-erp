import 'website_block_type.dart';

/// Canonical value for any visible website action such as a banner button,
/// carousel button, pricing-plan button, or standalone button block.
///
/// Persisted blocks may still contain legacy label/link keys. The editor keeps
/// those keys synchronized for compatibility, while `actions` is the shared
/// structured representation consumed by renderers.
class WebsiteActionValue {
  const WebsiteActionValue({
    required this.label,
    required this.href,
    this.variant = WebsiteActionVariant.filled,
  });

  final String label;
  final String href;
  final WebsiteActionVariant variant;

  bool get isConfigured => href.trim().isNotEmpty;

  WebsiteActionValue copyWith({
    String? label,
    String? href,
    WebsiteActionVariant? variant,
  }) {
    return WebsiteActionValue(
      label: label ?? this.label,
      href: href ?? this.href,
      variant: variant ?? this.variant,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': 'navigate',
        'label': label.trim(),
        'to': href.trim(),
        'variant': variant.storageValue,
      };

  /// Resolves the primary navigate action from one block/item/slide.
  ///
  /// Visible editor fields are preferred when present because older editor
  /// versions changed those fields without updating `actions`. New writes keep
  /// both representations synchronized.
  static WebsiteActionValue? resolvePrimary(
    Map<String, dynamic> data, {
    required List<String> labelKeys,
    required List<String> hrefKeys,
    List<String> variantKeys = const ['actionVariant'],
    String defaultLabel = 'Ver más',
    String defaultHref = '',
    WebsiteActionVariant defaultVariant = WebsiteActionVariant.filled,
    bool enabled = true,
  }) {
    if (!enabled) return null;

    ({bool present, String value}) firstField(List<String> keys) {
      for (final key in keys) {
        if (data.containsKey(key)) {
          return (present: true, value: data[key]?.toString().trim() ?? '');
        }
      }
      return (present: false, value: '');
    }

    final fieldLabel = firstField(labelKeys);
    final fieldHref = firstField(hrefKeys);
    final structured = _firstNavigateAction(data['actions']);

    final href = fieldHref.present
        ? fieldHref.value
        : (structured?['to'] ?? structured?['href'] ?? defaultHref)
            .toString()
            .trim();
    if (href.isEmpty) return null;

    final structuredLabel =
        (structured?['label'] ?? structured?['text'] ?? '').toString().trim();
    final label = fieldLabel.present
        ? (fieldLabel.value.isNotEmpty ? fieldLabel.value : defaultLabel)
        : (structuredLabel.isNotEmpty ? structuredLabel : defaultLabel);
    final variantField = firstField(variantKeys);
    final rawVariant = fieldHref.present && variantField.present
        ? variantField.value
        : (structured?['variant'] ?? structured?['style'])?.toString() ?? '';

    return WebsiteActionValue(
      label: label.trim().isEmpty ? defaultLabel : label.trim(),
      href: href,
      variant: WebsiteActionVariant.fromStorage(
        rawVariant,
        fallback: defaultVariant,
      ),
    );
  }

  /// Replaces the first navigate action and preserves unrelated future action
  /// types. An empty destination removes the primary navigate action.
  static List<Map<String, dynamic>> mergePrimary(
    dynamic rawActions,
    WebsiteActionValue value,
  ) {
    final actions = <Map<String, dynamic>>[];
    if (rawActions is List) {
      for (final item in rawActions) {
        if (item is Map) actions.add(Map<String, dynamic>.from(item));
      }
    }

    final index = actions.indexWhere(_isNavigateAction);
    if (!value.isConfigured) {
      if (index >= 0) actions.removeAt(index);
      return actions;
    }

    if (index >= 0) {
      actions[index] = <String, dynamic>{
        ...actions[index],
        ...value.toJson(),
      };
    } else {
      actions.insert(0, value.toJson());
    }
    return actions;
  }

  static Map<String, dynamic>? _firstNavigateAction(dynamic rawActions) {
    if (rawActions is! List) return null;
    for (final item in rawActions) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      if (_isNavigateAction(map)) return map;
    }
    return null;
  }

  static bool _isNavigateAction(Map<String, dynamic> action) {
    final type = (action['type'] ?? '').toString().trim().toLowerCase();
    return type.isEmpty || type == 'navigate';
  }
}

enum WebsiteActionVariant {
  filled,
  outline,
  text;

  String get storageValue => switch (this) {
        WebsiteActionVariant.filled => 'filled',
        WebsiteActionVariant.outline => 'outline',
        WebsiteActionVariant.text => 'text',
      };

  static WebsiteActionVariant fromStorage(
    String? raw, {
    WebsiteActionVariant fallback = WebsiteActionVariant.filled,
  }) {
    return switch (raw?.trim().toLowerCase()) {
      'outline' || 'outlined' => WebsiteActionVariant.outline,
      'text' => WebsiteActionVariant.text,
      'filled' || 'primary' => WebsiteActionVariant.filled,
      _ => fallback,
    };
  }
}

/// Where a block keeps one of its buttons: the keys of its label, its
/// destination and its look, the list it belongs to (a slide, a plan) and
/// whether it is the block's primary action, which `actions` mirrors.
///
/// One owner for the editor (2026-10-07): the Flutter canvas's action slots
/// and the buttons of the editor's «Vista HTML» name the same fields, and
/// the HTML page names a button by [spec], never by its keys, so a page can
/// only ask to edit a button the block has.
enum WebsiteButtonFields {
  /// The standalone button block.
  button(['label', 'text'], ['link'], variant: ['style']),

  /// The hero's button: outlined unless the block says otherwise.
  hero(
    ['ctaText', 'buttonText', 'label'],
    ['ctaLink', 'buttonLink', 'link'],
    defaultVariant: WebsiteActionVariant.outline,
  ),

  /// A carousel slide's button, outlined as the hero's.
  slide(
    ['ctaText', 'buttonText'],
    ['ctaLink', 'buttonLink'],
    collection: ['slides'],
    defaultVariant: WebsiteActionVariant.outline,
  ),

  /// The call to action's main button.
  cta(['buttonText', 'ctaText'], ['buttonLink', 'ctaLink']),

  /// The call to action's second button: never the block's primary action,
  /// always outlined.
  ctaSecondary(
    ['secondaryText'],
    ['secondaryLink'],
    variant: [],
    mirrorsPrimary: false,
    defaultVariant: WebsiteActionVariant.outline,
  ),

  /// A pricing plan's button.
  plan(
    ['ctaText', 'buttonText'],
    ['ctaLink', 'buttonLink'],
    collection: ['plans', 'items'],
  );

  const WebsiteButtonFields(
    this.label,
    this.href, {
    this.variant = const ['actionVariant'],
    this.collection = const [],
    this.mirrorsPrimary = true,
    this.defaultVariant = WebsiteActionVariant.filled,
  });

  final List<String> label;
  final List<String> href;
  final List<String> variant;

  /// The list the button's item is in (its canonical key first); empty for
  /// a button of the block itself.
  final List<String> collection;
  final bool mirrorsPrimary;

  /// The look the button has when the block does not say one.
  final WebsiteActionVariant defaultVariant;

  /// The button as [data] (the block's, or its item's) stores it, for the
  /// editor to edit: the visible fields where present, otherwise the
  /// block's first navigate action (`actions`, written before the fields).
  /// An empty label or destination stays empty: what the block shows then
  /// is its own rule, and writing it back changes nothing.
  WebsiteActionValue storedIn(Map<String, dynamic> data) {
    ({bool present, String value}) first(List<String> keys) {
      for (final key in keys) {
        if (data.containsKey(key)) {
          return (present: true, value: data[key]?.toString().trim() ?? '');
        }
      }
      return (present: false, value: '');
    }

    final structured = mirrorsPrimary
        ? WebsiteActionValue.resolvePrimary(
            data,
            labelKeys: const [],
            hrefKeys: const [],
            variantKeys: const [],
            defaultLabel: '',
            defaultVariant: defaultVariant,
          )
        : null;
    final storedLabel = first(label);
    final storedHref = first(href);
    final storedVariant = first(variant);
    return WebsiteActionValue(
      label: storedLabel.present ? storedLabel.value : structured?.label ?? '',
      href: storedHref.present ? storedHref.value : structured?.href ?? '',
      variant: storedVariant.present
          ? WebsiteActionVariant.fromStorage(
              storedVariant.value,
              fallback: defaultVariant,
            )
          : structured?.variant ?? defaultVariant,
    );
  }

  /// Where the block's primary action is mirrored, or `null` for a button
  /// that is not it.
  String? get actionsKey => mirrorsPrimary ? 'actions' : null;

  /// The one block type that draws this button: a page that names it for
  /// any other block names a button that block does not have, even when
  /// both keep a label under the same key.
  WebsiteBlockType get block => switch (this) {
    button => WebsiteBlockType.button,
    hero => WebsiteBlockType.hero,
    slide => WebsiteBlockType.carousel,
    cta || ctaSecondary => WebsiteBlockType.cta,
    plan => WebsiteBlockType.pricing,
  };

  /// How the editor's HTML names this button: `cta`, or `plan#2` for the
  /// one of the item stored at [index].
  String spec([int index = 0]) => collection.isEmpty ? name : '$name#$index';

  /// The button and item position a [spec] names; `null` for anything else.
  static ({WebsiteButtonFields fields, int index})? parse(String spec) {
    final hash = spec.indexOf('#');
    final name = hash < 0 ? spec : spec.substring(0, hash);
    WebsiteButtonFields? fields;
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
