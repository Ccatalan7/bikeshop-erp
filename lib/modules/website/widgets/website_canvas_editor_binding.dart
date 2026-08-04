import 'package:flutter/material.dart';

import '../models/website_responsive_authoring.dart';

/// Writes several root properties of the Canvas document as one transaction.
///
/// Returns whether the document actually changed: a value-identical write is a
/// no-op and must not dirty the draft or create a history entry.
typedef WebsiteCanvasRootWrite = bool Function(
  Map<String, Object?> values, {
  required WebsiteWriteScope scope,
  required WebsiteViewport viewport,
});

/// Resets several root viewport overrides as one transaction.
typedef WebsiteCanvasRootReset = bool Function(
  Iterable<String> keys, {
  required WebsiteViewport viewport,
});

/// Writes several properties of ONE layer, addressed by its id.
typedef WebsiteCanvasLayerWrite = bool Function(
  String layerId,
  Map<String, Object?> values, {
  required WebsiteWriteScope scope,
  required WebsiteViewport viewport,
});

/// Resets several viewport overrides of ONE layer, addressed by its id.
typedef WebsiteCanvasLayerReset = bool Function(
  String layerId,
  Iterable<String> keys, {
  required WebsiteViewport viewport,
});

/// Adds one canonical layer at [index]; returns whether it landed.
typedef WebsiteCanvasLayerInsert = bool Function(
  Map<String, dynamic> layer, {
  required int index,
});

/// Removes ONE identity and every responsive branch it owned.
typedef WebsiteCanvasLayerRemove = bool Function(String layerId);

/// Deep-copies ONE layer, overrides included, under a new identity.
typedef WebsiteCanvasLayerDuplicate = bool Function(
  String layerId,
  String newLayerId,
);

/// The identities the addressed Canvas document currently carries, so a new
/// id can be minted without colliding with one.
typedef WebsiteCanvasDocumentReader = Map<String, dynamic>? Function();

/// Moves ONE layer in the z-order.
///
/// Shared scope moves the base list; a tablet or mobile scope records the
/// typed per-viewport exception instead.
typedef WebsiteCanvasLayerReorder = bool Function(
  String layerId,
  int targetIndex, {
  required WebsiteWriteScope scope,
  required WebsiteViewport viewport,
});

/// Edit-only commands and transient selection for one Canvas content tree.
///
/// The persisted Canvas payload never owns [activeElementId]. Public and
/// Preview omit this binding, while Edit passes it through the same deferred
/// content renderer used by visitors.
///
/// The command closures are the single atomic write path for a Canvas, and
/// they are identical for a standalone block and for a Canvas inside a
/// carousel slide — the host resolves which document they address. Each call
/// is one transaction: one document, one notification, one history entry.
class WebsiteCanvasEditorBinding {
  const WebsiteCanvasEditorBinding({
    required this.activeElementId,
    required this.onActiveElementChanged,
    this.insertLayer,
    this.removeLayer,
    this.duplicateLayer,
    this.readDocument,
    this.onCanvasSizeChanged,
    this.onBackgroundTap,
    this.writeScope,
    this.setRootProperties,
    this.clearRootOverrides,
    this.setLayerProperties,
    this.clearLayerOverrides,
    this.reorderLayer,
  });

  final String? activeElementId;

  /// The scope the NEXT property write is attributed to.
  ///
  /// A resolver rather than a value: the editor can change the attribution
  /// between two gestures, and the Canvas must read the current one at the
  /// moment it writes, not the one captured when this binding was built.
  /// Absent means shared, which is also what desktop coerces to.
  final WebsiteWriteScope Function()? writeScope;

  final ValueChanged<String?> onActiveElementChanged;

  /// Layer lifecycle. Structure is shared across viewports: these change the
  /// document's common identity set, while the property commands below own
  /// presentation and visibility per viewport.
  final WebsiteCanvasLayerInsert? insertLayer;
  final WebsiteCanvasLayerRemove? removeLayer;
  final WebsiteCanvasLayerDuplicate? duplicateLayer;

  /// Read-only view of the addressed document, used to mint an id that does
  /// not collide with an identity it already carries.
  final WebsiteCanvasDocumentReader? readDocument;
  final ValueChanged<Size>? onCanvasSizeChanged;
  final VoidCallback? onBackgroundTap;

  final WebsiteCanvasRootWrite? setRootProperties;
  final WebsiteCanvasRootReset? clearRootOverrides;
  final WebsiteCanvasLayerWrite? setLayerProperties;
  final WebsiteCanvasLayerReset? clearLayerOverrides;
  final WebsiteCanvasLayerReorder? reorderLayer;
}
