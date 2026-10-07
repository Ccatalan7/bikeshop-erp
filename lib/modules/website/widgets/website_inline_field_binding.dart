import '../models/website_block_capabilities.dart';
import '../models/website_block_definition.dart';
import '../models/website_block_geometry.dart';
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
    final node = _node(target, viewport);
    if (node == null) return null;
    for (final key in keys) {
      if (node.containsKey(key)) return node[key]?.toString() ?? '';
    }
    return '';
  }

  /// What [key] holds as the block is drawn in [viewport].
  Object? _value(
    WebsiteInlineRepeaterTarget? target,
    String key,
    WebsiteViewport viewport,
  ) =>
      _node(target, viewport)?[key];

  /// The block's data (or [target]'s item) as it is drawn in [viewport].
  Map<dynamic, dynamic>? _node(
    WebsiteInlineRepeaterTarget? target,
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
      // The item is addressed where it is stored, as the lease writes it;
      // the band's projection may have left out what is not an item.
      Object? stored;
      Object? projected;
      for (final key in target.collectionKeys) {
        if (raw.containsKey(key)) {
          stored = raw[key];
          projected = data[key];
          break;
        }
      }
      final index = target.itemIndex;
      if (stored is! List ||
          projected is! List ||
          index < 0 ||
          index >= stored.length ||
          stored[index] is! Map) {
        return null;
      }
      final at = projected.length == stored.length
          ? index
          : stored.take(index).whereType<Map>().length;
      final item = at < projected.length ? projected[at] : null;
      node = item is Map ? item : null;
    }
    return node;
  }

  /// How the block's height is authored: exactly, as a minimum, or not at
  /// all (its content owns it).
  WebsitePageBlockHeightBehavior get heightBehavior {
    final type = registeredType;
    return type == null
        ? WebsitePageBlockHeightBehavior.intrinsic
        : WebsiteBlockCapabilityRegistry.profileFor(type).heightBehavior;
  }

  /// The heights the block's handle may set, by its type.
  ({double min, double max}) get heightRange => (
        min: switch (blockType) {
          'hero' || 'carousel' => 200,
          'canvas' => 100,
          'products' => 250,
          'services' || 'features' => 150,
          'testimonials' || 'gallery' => 200,
          _ => 100,
        },
        max: switch (blockType) {
          'hero' || 'carousel' => 1000,
          'products' => 900,
          'canvas' => 1600,
          _ => 800,
        },
      );

  /// The block's height transaction, leased now for one drag of its handle;
  /// `null` for a block whose content owns its height, one not drawn yet or
  /// not picked.
  WebsiteInlineManipulationLease? beginHeight() {
    if (heightBehavior == WebsitePageBlockHeightBehavior.intrinsic) {
      return null;
    }
    final target = targetFor(null, [
      WebsiteInlineManipulationProperty.fromSchema(
        WebsiteBlockMetaFields.blockHeight,
      ),
    ]);
    return target == null ? null : provider.beginInlineManipulation(target);
  }

  /// Writes [height] (`null`: back to the content's own) with [lease], as
  /// one step of the history; `false` when the draft changed under it.
  bool commitHeight(WebsiteInlineManipulationLease lease, double? height) {
    final written = provider.commitInlineManipulation(lease, {
      WebsiteBlockMetaFields.blockHeight.key: height,
    });
    if (!written) provider.cancelInlineManipulation(lease);
    return written;
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
    // The text's formatting travels in the same transaction, under the
    // text's policy, as the canvas's toolbar writes it.
    final formattingKey =
        schema.supportsFormatting ? schema.resolvedFormattingKey : null;
    final formattingProperty = formattingKey == null
        ? null
        : propertyFor(item, [formattingKey], policyKeys: keys);
    final target = property == null
        ? null
        : targetFor(item, [
            property,
            if (formattingProperty != null) formattingProperty,
          ]);
    final lease =
        target == null ? null : provider.beginInlineManipulation(target);
    if (property == null || text == null || lease == null) return null;
    final formatting = formattingProperty == null
        ? null
        : switch (_value(item, formattingProperty.canonicalKey, viewport)) {
            final Map<dynamic, dynamic> stored => <String, Object?>{
                for (final MapEntry(:key, :value) in stored.entries)
                  key.toString(): value,
              },
            _ => <String, Object?>{},
          };
    return WebsiteInlineTextWrite._(
      provider,
      property.canonicalKey,
      lease,
      text,
      formattingKey: formattingProperty?.canonicalKey,
      formatting: formatting,
    );
  }
}

/// A text being written where it is drawn ([WebsiteInlineFieldBinding.beginText]).
class WebsiteInlineTextWrite {
  WebsiteInlineTextWrite._(
    this._provider,
    this.key,
    this._lease,
    this.text, {
    this.formattingKey,
    this.formatting,
  });

  final WebsiteEditModeProvider _provider;

  /// The field's canonical key.
  final String key;
  final WebsiteInlineManipulationLease _lease;

  /// The text it holds as drawn, when the writing began.
  final String text;

  /// Where its formatting is kept, for a text that has one.
  final String? formattingKey;

  /// Its formatting as drawn when the writing began (`TextFormatting`'s
  /// JSON); `null` for a text without one.
  final Map<String, Object?>? formatting;

  /// The formatting a toolbar may change: bold, italic, underline and the
  /// size, each a value or `null` for none. Anything else keeps what
  /// [formatting] has.
  static const formattingChanges = {'bold', 'italic', 'underline', 'fontSize'};

  /// Whether [changes] are ones a toolbar may make: [formattingChanges]
  /// only, of their kinds, a size between 6 and 200.
  static bool acceptsFormattingChanges(Map<String, Object?> changes) =>
      changes.entries.every(
        (entry) => switch ((entry.key, entry.value)) {
          ('bold' || 'italic' || 'underline', bool() || null) => true,
          ('fontSize', null) => true,
          ('fontSize', final num size) =>
            size.isFinite && size >= 6 && size <= 200,
          _ => false,
        },
      );

  /// [formatting] with [changes] applied (see [acceptsFormattingChanges]),
  /// or `null` when they change nothing.
  Map<String, Object?>? formattingWith(Map<String, Object?> changes) {
    final current = formatting;
    if (current == null ||
        changes.isEmpty ||
        !acceptsFormattingChanges(changes)) {
      return null;
    }
    final next = Map<String, Object?>.of(current);
    for (final MapEntry(:key, :value) in changes.entries) {
      if (value == null || value == false) {
        next.remove(key);
      } else {
        next[key] = value is num ? value.toDouble() : value;
      }
    }
    final same = next.length == current.length &&
        next.entries.every((entry) => current[entry.key] == entry.value);
    return same ? null : next;
  }

  /// Writes [value], and [formatting] if given, as one step; `false` when
  /// the draft changed under it (nothing is written then) or nothing would
  /// change.
  bool commit(String value, {Map<String, Object?>? formatting}) {
    final formattingKey = this.formattingKey;
    final written = _provider.commitInlineManipulation(_lease, {
      key: value,
      if (formatting != null && formattingKey != null)
        formattingKey: formatting,
    });
    if (!written) cancel();
    return written;
  }

  /// Leaves the field as it was.
  void cancel() => _provider.cancelInlineManipulation(_lease);
}
