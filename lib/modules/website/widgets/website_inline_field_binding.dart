import '../models/website_block_definition.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';
import '../models/website_responsive_authoring.dart';
import '../models/website_responsive_projection.dart';
import '../providers/website_edit_mode_provider.dart';
import 'website_block_content_presenters.dart';

/// How an inline control writes the fields of one block: the schema field
/// behind a slot's keys, the transaction's properties (canonical key,
/// responsive policy, companions), the target the provider leases and the
/// value the slot shows.
///
/// One owner for every surface that edits a block where it is drawn: the
/// Flutter canvas's text, image and action slots and the texts of the
/// editor's «Vista HTML».
class WebsiteInlineFieldBinding {
  const WebsiteInlineFieldBinding({
    required this.provider,
    required this.blockId,
    required this.blockType,
  });

  final WebsiteEditModeProvider provider;
  final String blockId;
  final String blockType;

  /// The registered type of the block, or `null` for one the registry does
  /// not know.
  WebsiteBlockType? get registeredType {
    final normalized = blockType.trim().toLowerCase();
    for (final type in WebsiteBlockType.values) {
      if (type.name.toLowerCase() == normalized) return type;
    }
    return null;
  }

  /// The node a write lands on: the block's own data, or one item of a
  /// collection.
  WebsiteInlineManipulationOwner ownerFor(WebsiteInlineRepeaterTarget? target) {
    if (target == null) return const WebsiteInlineBlockOwner();
    return WebsiteInlineRepeaterOwner(
      collectionKeys: target.collectionKeys,
      itemIndex: target.itemIndex,
      identityKey: target.identityKey,
      identityValue: target.identityValue,
    );
  }

  /// The schema field one of [keys] names, at the block's root or in one of
  /// [target]'s collections.
  WebsiteBlockFieldSchema? schemaFieldFor(
    WebsiteInlineRepeaterTarget? target,
    List<String> keys,
  ) {
    final type = registeredType;
    if (type == null) return null;
    if (target == null) {
      for (final key in keys) {
        final field = WebsiteBlockRegistry.fieldForPath(type, key);
        if (field != null) return field;
      }
      return null;
    }
    for (final collectionKey in target.collectionKeys) {
      for (final key in keys) {
        final field = WebsiteBlockRegistry.fieldForPath(
          type,
          '$collectionKey.$key',
        );
        if (field != null) return field;
      }
    }
    return null;
  }

  /// The transaction property for [keys]: the schema's canonical key and
  /// responsive policy (or [policyKeys]' for a companion such as a text's
  /// formatting), with the other keys and the schema's aliases written
  /// alongside while the scope is shared.
  WebsiteInlineManipulationProperty? propertyFor(
    WebsiteInlineRepeaterTarget? target,
    List<String> keys, {
    List<String> policyKeys = const <String>[],
    bool mayLackSchema = false,
  }) {
    if (keys.isEmpty) return null;
    final policySource = policyKeys.isEmpty ? keys : policyKeys;
    final field = schemaFieldFor(target, policySource);
    assert(
      registeredType == null || field != null || mayLackSchema,
      'Inline transaction for "${keys.first}" has no schema field on '
      '$blockType.',
    );
    final canonical =
        policyKeys.isEmpty && field != null ? field.key : keys.first;
    final companions = <String>{
      ...keys,
      if (policyKeys.isEmpty && field != null) ...field.migrationAliases,
    }..remove(canonical);
    return WebsiteInlineManipulationProperty(
      canonicalKey: canonical,
      policy:
          field?.responsivePolicy ?? WebsiteResponsivePropertyPolicy.sharedOnly,
      sharedCompanionKeys: companions,
    );
  }

  /// The target the provider leases: the block in the band it is drawn in
  /// (`renderedBlockViewportFor`), or `null` before it has been drawn.
  WebsiteInlineManipulationTarget? targetFor(
    WebsiteInlineRepeaterTarget? target,
    List<WebsiteInlineManipulationProperty> properties, {
    bool requiresSelection = true,
  }) {
    final viewport = provider.renderedBlockViewportFor(blockId);
    if (viewport == null || properties.isEmpty) return null;
    return WebsiteInlineManipulationTarget(
      blockId: blockId,
      owner: ownerFor(target),
      viewport: viewport,
      properties: properties,
      requiresSelection: requiresSelection,
    );
  }

  /// A one-shot guard for a discrete write to [target].
  WebsiteInlineManipulationLease? captureLease(
    WebsiteInlineManipulationTarget? target,
  ) {
    return target == null ? null : provider.captureInlineMutationLease(target);
  }

  /// The text the field of [keys] holds as the block is drawn in [viewport]
  /// (its copy for that band, where it has one), or `null` when the block,
  /// the item or the field is not there.
  String? textValue(
    WebsiteInlineRepeaterTarget? target,
    List<String> keys,
    WebsiteViewport viewport,
  ) {
    final type = registeredType;
    final block = provider.getBlock(blockId);
    final raw = block?['block_data'];
    if (type == null || raw is! Map) return null;
    final data = WebsiteResponsiveBlockProjection.project(
      type: type,
      data: Map<String, dynamic>.from(raw)..remove('visibility'),
      viewport: viewport,
    );
    Map<dynamic, dynamic>? node = data;
    if (target != null) {
      Object? collection;
      for (final key in target.collectionKeys) {
        if (data.containsKey(key)) {
          collection = data[key];
          break;
        }
      }
      if (collection is! List ||
          target.itemIndex < 0 ||
          target.itemIndex >= collection.length) {
        return null;
      }
      final item = collection[target.itemIndex];
      node = item is Map ? item : null;
    }
    if (node == null) return null;
    for (final key in keys) {
      if (node.containsKey(key)) return node[key]?.toString() ?? '';
    }
    return '';
  }

  /// Starts writing the text field of [keys] (of [item], for one in a list)
  /// where it is drawn, as the canvas's `InlineEditableTextV2` does: one
  /// transaction leased now and written once, as one step of the history.
  /// Only a text field the block's schema declares, in the band the block
  /// is drawn in, with the block picked; `null` otherwise.
  WebsiteInlineTextWrite? beginText(
    WebsiteInlineRepeaterTarget? item,
    List<String> keys,
  ) {
    final schema = schemaFieldFor(item, keys);
    final viewport = provider.renderedBlockViewportFor(blockId);
    if (schema == null ||
        viewport == null ||
        (schema.type != WebsiteBlockFieldType.text &&
            schema.type != WebsiteBlockFieldType.textarea)) {
      return null;
    }
    final property = propertyFor(item, keys);
    final text = textValue(item, keys, viewport);
    final target = property == null ? null : targetFor(item, [property]);
    final lease =
        target == null ? null : provider.beginInlineManipulation(target);
    if (property == null || text == null || lease == null) return null;
    return WebsiteInlineTextWrite._(
        provider, property.canonicalKey, lease, text);
  }
}

/// A text being written where it is drawn ([WebsiteInlineFieldBinding.beginText]).
class WebsiteInlineTextWrite {
  WebsiteInlineTextWrite._(this._provider, this.key, this._lease, this.text);

  final WebsiteEditModeProvider _provider;

  /// The field's canonical key.
  final String key;
  final WebsiteInlineManipulationLease _lease;

  /// The text it holds as drawn, when the writing began.
  final String text;

  /// Writes [value]; `false` when the draft changed under it (nothing is
  /// written then) or [value] is what it held.
  bool commit(String value) {
    final written = _provider.commitInlineManipulation(_lease, {key: value});
    if (!written) cancel();
    return written;
  }

  /// Leaves the field as it was.
  void cancel() => _provider.cancelInlineManipulation(_lease);
}
