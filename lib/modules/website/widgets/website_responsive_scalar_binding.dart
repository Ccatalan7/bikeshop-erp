import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/website_block_definition.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';
import '../models/website_responsive_authoring.dart';
import '../models/website_responsive_field_state.dart';
import '../providers/website_edit_mode_provider.dart';
import 'website_responsive_media_binding.dart';

/// Which document node a schema field belongs to.
///
/// A nested field must never be written at the block root. Making the owner an
/// explicit, typed argument is what stops that by construction: a control that
/// forgets to pass it does not compile, instead of silently writing
/// `block_data.imageUrl` while the user is editing slide 3.
@immutable
sealed class WebsiteResponsiveFieldOwner {
  const WebsiteResponsiveFieldOwner();
}

/// The block's own `block_data`.
@immutable
final class WebsiteResponsiveRootField extends WebsiteResponsiveFieldOwner {
  const WebsiteResponsiveRootField();
}

/// One item of a schema collection — a slide, a plan, a testimonial.
@immutable
final class WebsiteResponsiveRepeaterField extends WebsiteResponsiveFieldOwner {
  const WebsiteResponsiveRepeaterField({
    required this.collectionKeys,
    required this.itemIndex,
    this.identityKey,
    this.identityValue,
  });

  /// Reads the item's own identity when it already has one.
  ///
  /// It never invents an id and never migrates the document: an item without a
  /// stable key is addressed by its explicit index, which is exactly how the
  /// rest of the editor addresses it today.
  factory WebsiteResponsiveRepeaterField.forItem({
    required List<String> collectionKeys,
    required int itemIndex,
    required Map<String, dynamic> item,
    List<String> identityKeys = const <String>['id'],
  }) {
    for (final key in identityKeys) {
      final raw = item[key];
      if (raw == null) continue;
      final value = raw.toString().trim();
      if (value.isEmpty) continue;
      return WebsiteResponsiveRepeaterField(
        collectionKeys: collectionKeys,
        itemIndex: itemIndex,
        identityKey: key,
        identityValue: raw,
      );
    }
    return WebsiteResponsiveRepeaterField(
      collectionKeys: collectionKeys,
      itemIndex: itemIndex,
    );
  }

  final List<String> collectionKeys;
  final int itemIndex;
  final String? identityKey;
  final Object? identityValue;
}

/// One persisted property written by a single inline gesture.
///
/// The slot describes WHAT the user touched; this describes WHERE it lands.
/// Canonical key first, followed by the aliases the product still reads for the
/// same value — the same convention the shared content widgets already use.
@immutable
class WebsiteInlinePropertyWrite {
  const WebsiteInlinePropertyWrite({
    required this.keys,
    required this.value,
    this.policyKeys = const <String>[],
    this.mayLackSchema = false,
  }) : assert(keys.length > 0);

  final List<String> keys;
  final Object? value;

  /// Keys of the schema field that DECLARES this write's policy.
  ///
  /// Empty means [keys] declares its own. A companion — text formatting, an
  /// action label or variant — is governed by the property that owns it, the
  /// one the registry names with `formattingKey`, `actionLabelKey` or
  /// `actionVariantKey`. A presenter never invents a policy of its own.
  final List<String> policyKeys;

  /// This property is allowed NOT to exist in the registry.
  ///
  /// It does not force a scope: where a family declares the property it
  /// resolves and obeys its policy like any other — `Button.style` does. It
  /// only silences the debug tripwire for the two persisted values that have
  /// no schema field by design:
  ///
  /// * `actions`, the composite mirror of label, destination and variant; and
  /// * `actionVariant`, which the CTA families declare through
  ///   `actionVariantKey` on their link field instead of as a field of their
  ///   own.
  ///
  /// Both are written with the shared value, next to the destination they
  /// belong to. Any other unresolved key is a schema gap, and fails loudly in
  /// debug and test rather than writing the base in silence.
  final bool mayLackSchema;
}

/// The one writer for inline (in-canvas) authoring.
///
/// Design source: `Website Builder Responsive Authoring` `handoff-t10`
/// `property_policy_matrix`. It introduces no control and no visual value: it
/// is the missing half of the protocol, the one the INSPECTOR already had.
///
/// Before it existed, an inline edit called `updateBlockData*` directly, so it
/// ignored viewport, policy and the visible `Común` / `Sólo este viewport`
/// scope: a phone canvas could render a mobile override while typing on it
/// silently rewrote the shared base. Every inline gesture now resolves, at the
/// moment of the write:
///
/// * the owner — the block root or one repeater item, by its stable identity;
/// * the canonical property, read from the registry rather than from the first
///   string a content widget happened to list;
/// * the policy that property declares, so `sharedOnly` can never grow an
///   override and Desktop always writes the base;
/// * the live write scope, so a change that follows `Personalizar` in the same
///   frame still lands on the override the user just asked for;
/// * the aliases the product still consumes — written only with the shared
///   value, never duplicated inside a viewport override.
@immutable
class WebsiteInlineResponsiveWriter {
  const WebsiteInlineResponsiveWriter({
    required this.provider,
    required this.blockId,
    required this.blockType,
    this.hostClass = WebsiteAuthoringHostClass.desktop,
  });

  final WebsiteEditModeProvider provider;
  final String blockId;

  /// Null for a block type outside the registry; every write then falls back
  /// to the shared value, which is exactly the pre-protocol behaviour.
  final WebsiteBlockType? blockType;
  final WebsiteAuthoringHostClass hostClass;

  /// Commits one gesture.
  ///
  /// Writes that land on the same scope are committed together, so replacing a
  /// CTA — label, destination, variant and composite — stays one history entry
  /// and one undo step. A gesture that mixed scopes would commit one entry per
  /// scope; no shipped slot does, because an action's four properties are all
  /// shared, and every other gesture writes a single property.
  void write({
    required WebsiteResponsiveFieldOwner owner,
    required List<WebsiteInlinePropertyWrite> writes,
  }) {
    final shared = <String, Object?>{};
    final sharedPolicies = <String, WebsiteResponsivePropertyPolicy>{};
    final scoped = <String, Object?>{};
    final scopedPolicies = <String, WebsiteResponsivePropertyPolicy>{};

    for (final request in writes) {
      if (request.keys.isEmpty) continue;
      final policySource =
          request.policyKeys.isEmpty ? request.keys : request.policyKeys;
      final field = _schemaField(owner, policySource);
      // A registered block with an unresolved property is a schema gap, and it
      // fails here rather than writing the base in silence. An UNREGISTERED
      // block type is a different situation — there is no schema to consult at
      // all — and keeps the pre-protocol shared behaviour.
      assert(
        blockType == null || field != null || request.mayLackSchema,
        'Inline write for "${request.keys.first}" has no schema field on '
        '$blockType. Declare it in the registry, or mark it as a shared '
        'companion; it must not fall back silently.',
      );

      final policy =
          field?.responsivePolicy ?? WebsiteResponsivePropertyPolicy.sharedOnly;
      // The registry owns the canonical key. A slot that listed an alias first
      // would otherwise persist the alias as the authority.
      final canonical = request.policyKeys.isEmpty && field != null
          ? field.key
          : request.keys.first;
      final scope = WebsiteAuthoringContext(
        hostClass: hostClass,
        previewViewport: provider.previewViewport,
        writeScope: _liveScope(owner, canonical, policy),
      ).effectiveWriteScope(policy);

      if (scope == WebsiteWriteScope.viewport) {
        scoped[canonical] = request.value;
        scopedPolicies[canonical] = policy;
        continue;
      }

      shared[canonical] = request.value;
      sharedPolicies[canonical] = policy;
      for (final companion in _sharedCompanions(request, field, canonical)) {
        shared[companion] = request.value;
        sharedPolicies[companion] = policy;
      }
    }

    if (shared.isNotEmpty) {
      _commit(owner, shared, sharedPolicies, WebsiteWriteScope.shared);
    }
    if (scoped.isNotEmpty) {
      _commit(owner, scoped, scopedPolicies, WebsiteWriteScope.viewport);
    }
  }

  /// The aliases that still receive the shared value.
  ///
  /// A viewport override never reaches this: duplicating an alias inside an
  /// override is how a fourth responsive model gets born.
  Set<String> _sharedCompanions(
    WebsiteInlinePropertyWrite request,
    WebsiteBlockFieldSchema? field,
    String canonical,
  ) {
    return <String>{
      ...request.keys,
      if (request.policyKeys.isEmpty && field != null)
        ...field.migrationAliases,
    }..remove(canonical);
  }

  WebsiteWriteScope _liveScope(
    WebsiteResponsiveFieldOwner owner,
    String propertyKey,
    WebsiteResponsivePropertyPolicy policy,
  ) {
    return switch (owner) {
      WebsiteResponsiveRootField() => provider.fieldWriteScope(
          blockId: blockId,
          propertyKey: propertyKey,
          policy: policy,
        ),
      WebsiteResponsiveRepeaterField(
        collectionKeys: final collectionKeys,
        itemIndex: final itemIndex,
        identityKey: final identityKey,
        identityValue: final identityValue,
      ) =>
        provider.repeaterFieldWriteScope(
          blockId: blockId,
          collectionKeys: collectionKeys,
          itemIndex: itemIndex,
          propertyKey: propertyKey,
          policy: policy,
          identityKey: identityKey,
          identityValue: identityValue,
        ),
    };
  }

  void _commit(
    WebsiteResponsiveFieldOwner owner,
    Map<String, Object?> values,
    Map<String, WebsiteResponsivePropertyPolicy> policies,
    WebsiteWriteScope scope,
  ) {
    switch (owner) {
      case WebsiteResponsiveRootField():
        provider.setBlockResponsiveProperties(
          blockId,
          values,
          policies: policies,
          scope: scope,
        );
      case WebsiteResponsiveRepeaterField(
          collectionKeys: final collectionKeys,
          itemIndex: final itemIndex,
          identityKey: final identityKey,
          identityValue: final identityValue,
        ):
        provider.setBlockRepeaterItemResponsiveProperties(
          blockId,
          collectionKeys: collectionKeys,
          itemIndex: itemIndex,
          values: values,
          policies: policies,
          scope: scope,
          identityKey: identityKey,
          identityValue: identityValue,
        );
    }
  }

  /// Resolves the schema field for a slot's key list.
  ///
  /// The keys are tried in order, which is what validates the content widgets'
  /// convention against the registry: the canonical key resolves first, and an
  /// alias only resolves when the canonical one is absent from the schema.
  WebsiteBlockFieldSchema? _schemaField(
    WebsiteResponsiveFieldOwner owner,
    List<String> keys,
  ) {
    final type = blockType;
    if (type == null) return null;

    switch (owner) {
      case WebsiteResponsiveRootField():
        for (final key in keys) {
          final field = WebsiteBlockRegistry.fieldForPath(type, key);
          if (field != null) return field;
        }
        return null;
      case WebsiteResponsiveRepeaterField(collectionKeys: final collectionKeys):
        for (final collectionKey in collectionKeys) {
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
  }
}

/// The canonical binding for every NON-media schema field.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 frames 10a/10b/10c and
/// `handoff-t10/spec.json` `property_policy_matrix`.
///
/// It is the scalar twin of [WebsiteResponsiveMediaBinding] and exists for the
/// same reason: inheritance, scope and persistence are decided **once**, by the
/// model layer, so no control has to interpret them again. A control receives a
/// resolved value and three callbacks; it never sees a serialized key, never
/// chooses a viewport and never decides whether a change is common or an
/// override.
///
/// What it guarantees:
///
/// * the value shown is `override(viewport actual) ?? shared`, resolved by the
///   provider — not `block_data[key]` read behind the resolver's back;
/// * a `sharedOnly` property writes top-level and can never grow a `responsive`
///   map, because the authoring context coerces its scope before the codec sees
///   it;
/// * a shared write keeps the migration aliases the product still reads, and a
///   viewport write creates only the canonical authority — projection is what
///   keeps them in parity, not a second copy of the value;
/// * every mutation is one provider call, therefore one history step.
@immutable
class WebsiteResponsiveScalarBinding<T> {
  const WebsiteResponsiveScalarBinding({
    required this.state,
    required this.write,
    required this.customize,
    required this.reset,
  });

  /// Resolved inheritance for the field. Feeds `ResponsiveFieldShell`.
  final WebsiteResponsiveFieldState<T> state;

  /// Persists a new value at the scope the state already resolved.
  final ValueChanged<Object?> write;

  /// Promotes the next write of this field to a viewport override.
  final VoidCallback customize;

  /// Removes the override — canonical authority plus legacy aliases — and
  /// returns the field to the shared value. It never copies the shared number
  /// over the override.
  final VoidCallback reset;

  /// The effective value for the previewed viewport.
  T? get value => state.resolved.value;

  // ---------------------------------------------------------------- decoders
  //
  // Every decoder answers one question: *is there a real value here?* An
  // absent key, an explicit null and a blank where blank means "unset" all
  // resolve to null, so reading a document can never manufacture an override
  // that the user did not create.

  /// Free text. A present empty string is a deliberate value and survives; only
  /// an absent or null raw is "no value".
  static String? decodeText(Object? raw) => raw?.toString();

  /// A choice. Blank is not a choice.
  static String? decodeOption(Object? raw) {
    if (raw == null) return null;
    final value = raw.toString().trim();
    return value.isEmpty ? null : value;
  }

  /// A colour token. Blank is unset.
  static String? decodeColor(Object? raw) => decodeOption(raw);

  static num? decodeNumber(Object? raw) {
    if (raw is num) return raw;
    if (raw is String) return num.tryParse(raw.trim());
    return null;
  }

  static bool? decodeBoolean(Object? raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final value = raw.trim().toLowerCase();
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
    return null;
  }

  /// Chips. A list of tokens, or the comma-separated form the editor accepts.
  static List<String>? decodeStringList(Object? raw) {
    if (raw == null) return null;
    if (raw is List) {
      final values = raw
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      return values.isEmpty ? null : values;
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    final values = text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return values.isEmpty ? null : values;
  }

  /// The decoder a schema field's own type asks for.
  ///
  /// Media is deliberately absent: an image belongs to
  /// [WebsiteResponsiveMediaBinding], which also owns its framing.
  static WebsiteResponsiveDecoder<Object> decoderFor(
    WebsiteBlockFieldType type,
  ) {
    return switch (type) {
      WebsiteBlockFieldType.number => decodeNumber,
      WebsiteBlockFieldType.toggle => decodeBoolean,
      WebsiteBlockFieldType.select => decodeOption,
      WebsiteBlockFieldType.color => decodeColor,
      WebsiteBlockFieldType.chips => decodeStringList,
      _ => decodeText,
    };
  }

  // ----------------------------------------------------------------- factory

  /// Binds [field] on [owner] to the provider's canonical operations.
  ///
  /// [sharedCompanionKeys] are keys the product still reads for the same value
  /// — migration aliases, and any product-owned duplicate such as the CTA
  /// `description`. They are written **only** on a shared write, in the same
  /// atomic call, so one edit stays one history step. A viewport override never
  /// touches them: the projection resolves the canonical authority, and copying
  /// a value into an alias per viewport is how a fourth responsive model gets
  /// born.
  /// [unavailableReason] marks the field as not editable **here** and says why
  /// in the operator's words. It exists for the honest case the plan demands:
  /// a property whose consumer computes the value itself for this viewport —
  /// the storefront's own auto-layout — so offering an override would be a
  /// control that changes nothing. The field stays visible and inert with its
  /// reason rather than disappearing or lying.
  factory WebsiteResponsiveScalarBinding.forField({
    required WebsiteEditModeProvider provider,
    required String blockId,
    required WebsiteBlockFieldSchema field,
    required WebsiteResponsiveFieldOwner owner,
    required WebsiteResponsiveDecoder<T> decode,
    T? fallback,
    WebsiteAuthoringHostClass hostClass = WebsiteAuthoringHostClass.desktop,
    WebsiteViewport? viewport,
    List<String> sharedCompanionKeys = const <String>[],
    String? unavailableReason,
  }) {
    final targetViewport = viewport ?? provider.previewViewport;
    final aliases = field.legacyResponsiveAliases;
    final legacyReader = aliases.isEmpty
        // Shared helper, not a media concept: "read a pre-migration mobile-only
        // alias, and never migrate while reading".
        ? null
        : WebsiteResponsiveMediaBinding.legacyMobileReader<T>(aliases, decode);

    final policy = field.responsivePolicy;
    final companions = <String>{
      ...field.migrationAliases,
      ...sharedCompanionKeys,
    }..remove(field.key);

    final mutationOwner = switch (owner) {
      WebsiteResponsiveRootField() => const WebsiteInlineBlockOwner(),
      WebsiteResponsiveRepeaterField(
        collectionKeys: final collectionKeys,
        itemIndex: final itemIndex,
        identityKey: final identityKey,
        identityValue: final identityValue,
      ) =>
        WebsiteInlineRepeaterOwner(
          collectionKeys: collectionKeys,
          itemIndex: itemIndex,
          identityKey: identityKey,
          identityValue: identityValue,
        ),
    };
    final mutationTarget = WebsiteInlineManipulationTarget(
      blockId: blockId,
      owner: mutationOwner,
      viewport: targetViewport,
      properties: <WebsiteInlineManipulationProperty>[
        WebsiteInlineManipulationProperty.fromSchema(
          field,
          sharedCompanionKeys: companions,
        ),
      ],
      requiresSelection: true,
    );

    // A binding may receive several edits before Flutter rebuilds it (IME
    // composition and rapid TextField input are the common cases). Keep one
    // exact one-shot lease in the closure and refresh it only after an
    // admitted commit/no-op. A rejected callback is stale by definition and
    // is never allowed to recapture against whatever page, item, scope or
    // viewport happens to be current now.
    var mutationLease = provider.captureInlineMutationLease(mutationTarget);
    void guardedWrite(Object? value) {
      final lease = mutationLease;
      if (lease == null) return;
      mutationLease = null;
      final result = provider.commitInlineMutation(
        lease,
        <String, Object?>{field.key: value},
      );
      if (result.accepted) {
        mutationLease = provider.captureInlineMutationLease(mutationTarget);
      }
    }

    switch (owner) {
      case WebsiteResponsiveRootField():
        final state = provider.responsiveFieldState<T>(
          blockId: blockId,
          schema: field,
          decode: decode,
          hostClass: hostClass,
          viewport: targetViewport,
          fallback: fallback,
          readLegacyOverride: legacyReader,
          unavailableReason: unavailableReason,
        );
        return WebsiteResponsiveScalarBinding<T>(
          state: state,
          write: guardedWrite,
          customize: () => provider.setFieldWriteScope(
            blockId: blockId,
            propertyKey: field.key,
            policy: policy,
            scope: WebsiteWriteScope.viewport,
            viewport: targetViewport,
          ),
          reset: () => provider.clearBlockResponsiveOverride(
            blockId,
            field.key,
            policies: <String, WebsiteResponsivePropertyPolicy>{
              field.key: policy,
            },
            viewport: targetViewport,
            legacyPropertyKeys: aliases,
          ),
        );

      case WebsiteResponsiveRepeaterField(
          collectionKeys: final collectionKeys,
          itemIndex: final itemIndex,
          identityKey: final identityKey,
          identityValue: final identityValue,
        ):
        final state = provider.responsiveRepeaterFieldState<T>(
          blockId: blockId,
          collectionKeys: collectionKeys,
          itemIndex: itemIndex,
          identityKey: identityKey,
          identityValue: identityValue,
          schema: field,
          decode: decode,
          hostClass: hostClass,
          viewport: targetViewport,
          fallback: fallback,
          readLegacyOverride: legacyReader,
          unavailableReason: unavailableReason,
        );
        return WebsiteResponsiveScalarBinding<T>(
          state: state,
          write: guardedWrite,
          customize: () => provider.setRepeaterFieldWriteScope(
            blockId: blockId,
            collectionKeys: collectionKeys,
            itemIndex: itemIndex,
            propertyKey: field.key,
            policy: policy,
            scope: WebsiteWriteScope.viewport,
            viewport: targetViewport,
            identityKey: identityKey,
            identityValue: identityValue,
          ),
          reset: () => provider.clearBlockRepeaterItemResponsiveOverride(
            blockId,
            collectionKeys: collectionKeys,
            itemIndex: itemIndex,
            propertyKey: field.key,
            policies: <String, WebsiteResponsivePropertyPolicy>{
              field.key: policy,
            },
            viewport: targetViewport,
            legacyPropertyKeys: aliases,
            identityKey: identityKey,
            identityValue: identityValue,
          ),
        );
    }
  }
}
