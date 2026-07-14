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
    final actionVariantField = firstField(const ['actionVariant']);
    final rawVariant = fieldHref.present && actionVariantField.present
        ? actionVariantField.value
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
