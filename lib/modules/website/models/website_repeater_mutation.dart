import 'package:flutter/foundation.dart';

/// Stable-or-positional address for one item in an editor-owned collection.
///
/// Persisted identity always wins. [fallbackIndex] exists only for legacy
/// items that genuinely have no identity; the provider protects that fallback
/// with the lease's exact source document, so it can never drift to a sibling.
@immutable
class WebsiteRepeaterItemRef {
  const WebsiteRepeaterItemRef.index(this.fallbackIndex)
      : identityKey = null,
        identityValue = null;

  const WebsiteRepeaterItemRef.persisted({
    required this.fallbackIndex,
    required String this.identityKey,
    required Object this.identityValue,
  });

  factory WebsiteRepeaterItemRef.fromItem({
    required int index,
    required Map<String, dynamic> item,
    String identityKey = 'id',
  }) {
    final identity = item[identityKey];
    if (_isPersistedRepeaterIdentity(identity)) {
      return WebsiteRepeaterItemRef.persisted(
        fallbackIndex: index,
        identityKey: identityKey,
        identityValue: identity! as Object,
      );
    }
    return WebsiteRepeaterItemRef.index(index);
  }

  final int fallbackIndex;
  final String? identityKey;
  final Object? identityValue;

  bool get hasIdentity => identityKey != null && identityValue != null;

  @override
  bool operator ==(Object other) =>
      other is WebsiteRepeaterItemRef &&
      other.fallbackIndex == fallbackIndex &&
      other.identityKey == identityKey &&
      other.identityValue == identityValue;

  @override
  int get hashCode => Object.hash(fallbackIndex, identityKey, identityValue);
}

/// One item traversed before reaching a nested collection.
@immutable
class WebsiteRepeaterAncestorRef {
  WebsiteRepeaterAncestorRef({
    required Iterable<String> collectionKeys,
    required this.item,
    this.itemIdentityKey = 'id',
  }) : collectionKeys = List<String>.unmodifiable(collectionKeys);

  final List<String> collectionKeys;
  final WebsiteRepeaterItemRef item;
  final String itemIdentityKey;
}

/// Exact semantic location of a collection in one Website Builder block.
///
/// [collectionKeys] contains the canonical key first and persisted aliases
/// afterwards. [ancestors] makes the address arbitrarily nestable without
/// teaching a widget how to rebuild any parent list.
@immutable
class WebsiteRepeaterCollectionTarget {
  WebsiteRepeaterCollectionTarget({
    required this.blockId,
    required Iterable<String> collectionKeys,
    Iterable<WebsiteRepeaterAncestorRef> ancestors =
        const <WebsiteRepeaterAncestorRef>[],
    this.itemIdentityKey = 'id',
    this.minItems,
    this.maxItems,
    this.requiresSelection = true,
  })  : collectionKeys = List<String>.unmodifiable(collectionKeys),
        ancestors = List<WebsiteRepeaterAncestorRef>.unmodifiable(ancestors);

  final String blockId;
  final List<WebsiteRepeaterAncestorRef> ancestors;
  final List<String> collectionKeys;
  final String itemIdentityKey;
  final int? minItems;
  final int? maxItems;
  final bool requiresSelection;

  WebsiteRepeaterItemRef itemRef(
    Map<String, dynamic> item,
    int index,
  ) {
    return WebsiteRepeaterItemRef.fromItem(
      index: index,
      item: item,
      identityKey: itemIdentityKey,
    );
  }

  /// Addresses a collection stored inside [parentItem].
  WebsiteRepeaterCollectionTarget nested({
    required WebsiteRepeaterItemRef parentItem,
    required Iterable<String> collectionKeys,
    String itemIdentityKey = 'id',
    int? minItems,
    int? maxItems,
  }) {
    return WebsiteRepeaterCollectionTarget(
      blockId: blockId,
      ancestors: <WebsiteRepeaterAncestorRef>[
        ...ancestors,
        WebsiteRepeaterAncestorRef(
          collectionKeys: this.collectionKeys,
          item: parentItem,
          itemIdentityKey: this.itemIdentityKey,
        ),
      ],
      collectionKeys: collectionKeys,
      itemIdentityKey: itemIdentityKey,
      minItems: minItems,
      maxItems: maxItems,
      requiresSelection: requiresSelection,
    );
  }
}

enum WebsiteRepeaterMovePlacement { before, after }

/// A structural or item-scoped mutation. No command accepts a replacement
/// collection: list reconstruction belongs exclusively to the provider.
@immutable
sealed class WebsiteRepeaterCommand {
  const WebsiteRepeaterCommand();
}

@immutable
final class WebsiteRepeaterAddItem extends WebsiteRepeaterCommand {
  WebsiteRepeaterAddItem(Map<String, dynamic> seed)
      : seed = _freezeRepeaterMap(seed);

  final Map<String, dynamic> seed;
}

@immutable
final class WebsiteRepeaterDuplicateItem extends WebsiteRepeaterCommand {
  const WebsiteRepeaterDuplicateItem(this.source);

  final WebsiteRepeaterItemRef source;
}

@immutable
final class WebsiteRepeaterDeleteItem extends WebsiteRepeaterCommand {
  const WebsiteRepeaterDeleteItem(this.target);

  final WebsiteRepeaterItemRef target;
}

@immutable
final class WebsiteRepeaterMoveItem extends WebsiteRepeaterCommand {
  const WebsiteRepeaterMoveItem({
    required this.source,
    required this.anchor,
    required this.placement,
  });

  final WebsiteRepeaterItemRef source;
  final WebsiteRepeaterItemRef anchor;
  final WebsiteRepeaterMovePlacement placement;
}

@immutable
final class WebsiteRepeaterPatchItem extends WebsiteRepeaterCommand {
  WebsiteRepeaterPatchItem({
    required this.target,
    required Map<String, dynamic> updates,
  }) : updates = _freezeRepeaterMap(updates);

  final WebsiteRepeaterItemRef target;
  final Map<String, dynamic> updates;
}

enum WebsiteRepeaterMutationResult {
  committed,
  unchanged,
  rejected;

  bool get accepted => this != WebsiteRepeaterMutationResult.rejected;
  bool get changed => this == WebsiteRepeaterMutationResult.committed;
}

/// Result plus the item the collection navigator should select next.
@immutable
class WebsiteRepeaterMutationOutcome {
  const WebsiteRepeaterMutationOutcome._({
    required this.result,
    this.selectionIndex,
    this.selectionItem,
  });

  const WebsiteRepeaterMutationOutcome.committed({
    int? selectionIndex,
    WebsiteRepeaterItemRef? selectionItem,
  }) : this._(
          result: WebsiteRepeaterMutationResult.committed,
          selectionIndex: selectionIndex,
          selectionItem: selectionItem,
        );

  const WebsiteRepeaterMutationOutcome.unchanged({
    int? selectionIndex,
    WebsiteRepeaterItemRef? selectionItem,
  }) : this._(
          result: WebsiteRepeaterMutationResult.unchanged,
          selectionIndex: selectionIndex,
          selectionItem: selectionItem,
        );

  const WebsiteRepeaterMutationOutcome.rejected()
      : this._(result: WebsiteRepeaterMutationResult.rejected);

  final WebsiteRepeaterMutationResult result;
  final int? selectionIndex;
  final WebsiteRepeaterItemRef? selectionItem;
}

bool _isPersistedRepeaterIdentity(Object? value) {
  return value is String && value.isNotEmpty || value is num || value is bool;
}

Map<String, dynamic> _freezeRepeaterMap(Map<String, dynamic> source) {
  return Map<String, dynamic>.unmodifiable(
    source.map(
      (key, value) => MapEntry(key, _freezeRepeaterValue(value)),
    ),
  );
}

Object? _freezeRepeaterValue(Object? value) {
  if (value is Map) {
    return Map<Object?, Object?>.unmodifiable(
      value.map(
        (key, nested) => MapEntry(key, _freezeRepeaterValue(nested)),
      ),
    );
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeRepeaterValue));
  }
  if (value is Set) {
    return Set<Object?>.unmodifiable(value.map(_freezeRepeaterValue));
  }
  return value;
}
