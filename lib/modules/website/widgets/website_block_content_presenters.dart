import 'package:flutter/material.dart';

import '../models/website_action.dart';
import 'text_formatting_toolbar.dart';

typedef WebsiteInlineTextPresenter = Widget Function(
  BuildContext context,
  WebsiteInlineTextSlot slot,
);

typedef WebsiteInlineMediaPresenter = Widget Function(
  BuildContext context,
  WebsiteInlineMediaSlot slot,
);

typedef WebsiteInlineActionPresenter = Widget Function(
  BuildContext context,
  WebsiteInlineActionSlot slot,
);

/// Edit-only presentation hooks for the shared Website block content tree.
///
/// Public and Preview omit this object. The slots describe persisted fields,
/// while the callbacks inject inline controls without giving the shared
/// renderer access to the editor provider.
class WebsiteBlockContentPresenters {
  const WebsiteBlockContentPresenters({
    this.text,
    this.media,
    this.action,
  });

  final WebsiteInlineTextPresenter? text;
  final WebsiteInlineMediaPresenter? media;
  final WebsiteInlineActionPresenter? action;
}

/// Identifies one persisted item inside a schema-defined block collection.
///
/// The shared content widgets only describe the target. The editor bridge
/// resolves it against the latest document state and performs one atomic
/// command, so content rendering never depends on the editor provider.
class WebsiteInlineRepeaterTarget {
  const WebsiteInlineRepeaterTarget({
    required this.collectionKeys,
    required this.itemIndex,
    this.identityKey,
    this.identityValue,
  }) : assert(collectionKeys.length > 0);

  /// Canonical collection key first, followed by any persisted aliases.
  final List<String> collectionKeys;
  final int itemIndex;

  /// Optional stable identity for collections that already persist one.
  ///
  /// Legacy Website Builder repeaters are index-owned today, so callers must
  /// not manufacture an ID merely to populate these fields.
  final String? identityKey;
  final Object? identityValue;
}

class WebsiteInlineTextSlot {
  const WebsiteInlineTextSlot({
    required this.id,
    required this.value,
    required this.valueKeys,
    required this.baseStyle,
    this.formatting = const TextFormatting(),
    this.formattingKeys = const <String>[],
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.placeholder,
    this.displayTransform,
    this.maxWidth,
    this.widthKeys = const <String>[],
    this.toolbarPreset = TextToolbarPreset.basic,
    this.repeaterTarget,
  }) : assert(valueKeys.length > 0);

  final String id;
  final String value;
  final List<String> valueKeys;
  final TextStyle baseStyle;
  final TextFormatting formatting;
  final List<String> formattingKeys;
  final TextAlign textAlign;
  final int? maxLines;
  final String? placeholder;

  /// A visual-only transformation. The editing buffer always keeps [value].
  final String Function(String value)? displayTransform;
  final double? maxWidth;
  final List<String> widthKeys;
  final TextToolbarPreset toolbarPreset;
  final WebsiteInlineRepeaterTarget? repeaterTarget;

  /// Matches the inline editor's alignment semantics: persisted formatting
  /// overrides the block's visual default, while `start` means "not set".
  TextAlign get resolvedTextAlign => formatting.textAlign == TextAlign.start
      ? textAlign
      : formatting.textAlign;
}

/// How the inline image editor exposes its "change image" affordance.
///
/// [hoverOverlay] is the default for simple, self-contained images: the
/// whole surface is a pick target and hover mounts the full overlay.
/// [inspectorOnly] is the opt-in policy for INTERACTIVE BACKGROUNDS —
/// media that sits underneath real content such as a hero/carousel CTA,
/// arrows, dots and nested selection. There the background renders
/// completely passively: no hover overlay, no gesture surface and no
/// inline chrome of any kind. Image editing lives exclusively in the
/// block/slide inspector's canonical picker (e.g. the carousel slide's
/// `Imagen y encuadre` section, or the hero's schema image field).
enum WebsiteInlineMediaEditAffordance {
  hoverOverlay,
  inspectorOnly,
}

class WebsiteInlineMediaSlot {
  const WebsiteInlineMediaSlot({
    required this.id,
    required this.url,
    required this.valueKeys,
    required this.fit,
    required this.alignment,
    required this.fallback,
    this.borderRadius,
    this.semanticLabel,
    this.repeaterTarget,
    this.editAffordance = WebsiteInlineMediaEditAffordance.hoverOverlay,
  }) : assert(valueKeys.length > 0);

  final String id;
  final String? url;
  final List<String> valueKeys;
  final BoxFit fit;
  final Alignment alignment;
  final Widget fallback;
  final BorderRadius? borderRadius;
  final String? semanticLabel;
  final WebsiteInlineRepeaterTarget? repeaterTarget;
  final WebsiteInlineMediaEditAffordance editAffordance;
}

class WebsiteInlineActionSlot {
  const WebsiteInlineActionSlot({
    required this.id,
    required this.action,
    required this.labelKeys,
    required this.hrefKeys,
    required this.child,
    this.variantKeys = const <String>[],
    this.actionsKey = 'actions',
    this.repeaterTarget,
  })  : assert(labelKeys.length > 0),
        assert(hrefKeys.length > 0);

  final String id;
  final WebsiteActionValue action;
  final List<String> labelKeys;
  final List<String> hrefKeys;
  final List<String> variantKeys;
  final String actionsKey;
  final Widget child;
  final WebsiteInlineRepeaterTarget? repeaterTarget;
}
