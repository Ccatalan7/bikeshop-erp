import 'package:flutter/material.dart';

import '../models/website_canvas_manipulation.dart';
import '../models/website_responsive_authoring.dart';
import '../providers/website_edit_mode_provider.dart';
import '../services/website_service.dart';

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

/// Starts one direct-manipulation mode for one layer in this binding's exact
/// Canvas document.
typedef WebsiteCanvasManipulationRequest = bool Function(
  String layerId,
  WebsiteCanvasManipulationMode mode, {
  required WebsiteViewport viewport,
});

typedef WebsiteCanvasManipulationAvailabilityReader
    = WebsiteCanvasManipulationAvailability Function(
  String layerId,
  WebsiteCanvasManipulationMode mode, {
  required WebsiteViewport viewport,
});

/// Writes a manipulation patch only while [expectedSession] is still the arm
/// that admitted the pointer. The owner compares, revalidates and persists in
/// one synchronous operation.
typedef WebsiteCanvasManipulationCommit = bool Function(
  WebsiteCanvasManipulationSession expectedSession,
  Map<String, dynamic> expectedDocument,
  int expectedDocumentEpoch,
  Map<String, Object?> values, {
  required WebsiteWriteScope scope,
});

/// Stops the exact session only. An old Canvas must not cancel a newer arm,
/// even when document, layer, mode and viewport happen to be identical.
typedef WebsiteCanvasManipulationStop = bool Function(
  WebsiteCanvasManipulationSession expectedSession,
);

/// Captures one exact editor owner before an asynchronous Canvas command.
typedef WebsiteCanvasAsyncIntentCapture = WebsiteEditorAsyncIntent? Function(
  String layerId, {
  required WebsiteWriteScope scope,
  required WebsiteViewport viewport,
});

/// Commits one async layer patch only through the intent captured before the
/// picker/dialog was opened.
typedef WebsiteCanvasAsyncLayerCommit = WebsiteInlineMutationResult Function(
  WebsiteEditorAsyncIntent expectedIntent,
  String layerId,
  Map<String, Object?> values, {
  required WebsiteWriteScope scope,
  required WebsiteViewport viewport,
});

/// Claims tenant-exact remote side effects (uploads/background removal) with
/// the same Canvas intent captured before the picker yielded.
typedef WebsiteCanvasAsyncRemoteAuthority = WebsiteEditorRemoteWriteAuthority?
    Function(
  WebsiteEditorAsyncIntent expectedIntent,
  String layerId, {
  required WebsiteWriteScope scope,
  required WebsiteViewport viewport,
  required String operation,
  required bool Function() isLiveBinding,
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
    required this.documentTarget,
    required this.activeElementId,
    required this.onActiveElementChanged,
    this.manipulationSession,
    this.manipulationAvailability,
    this.requestManipulation,
    this.commitManipulation,
    this.stopManipulation,
    this.captureAsyncIntent,
    this.commitAsyncLayerProperties,
    this.remoteWriteAuthority,
    this.insertLayer,
    this.removeLayer,
    this.duplicateLayer,
    this.readDocument,
    this.documentEpoch,
    this.canvasMeasurementGeneration = 0,
    this.onCanvasSizeChanged,
    this.onBackgroundTap,
    this.writeScope,
    this.setRootProperties,
    this.clearRootOverrides,
    this.setLayerProperties,
    this.clearLayerOverrides,
    this.reorderLayer,
  });

  /// Stable identity of the document every command closure below addresses.
  ///
  /// This belongs to the binding rather than ambient Provider state because
  /// multiple Canvas blocks and carousel slides may retain local selections at
  /// the same time. Direct manipulation must never leak between them.
  final WebsiteCanvasDocumentTarget documentTarget;

  final String? activeElementId;

  /// The one application-level manipulation session. Consumers must use
  /// [isManipulating] instead of inspecting only its mode.
  final WebsiteCanvasManipulationSession? manipulationSession;

  final WebsiteCanvasManipulationAvailabilityReader? manipulationAvailability;
  final WebsiteCanvasManipulationRequest? requestManipulation;
  final WebsiteCanvasManipulationCommit? commitManipulation;
  final WebsiteCanvasManipulationStop? stopManipulation;
  final WebsiteCanvasAsyncIntentCapture? captureAsyncIntent;
  final WebsiteCanvasAsyncLayerCommit? commitAsyncLayerProperties;
  final WebsiteCanvasAsyncRemoteAuthority? remoteWriteAuthority;

  bool isManipulating(
    String layerId,
    WebsiteCanvasManipulationMode mode, {
    required WebsiteViewport viewport,
  }) =>
      manipulationSession?.matches(
        document: documentTarget,
        layerId: layerId,
        mode: mode,
        viewport: viewport,
      ) ??
      false;

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

  /// Monotonic owner epoch for the page document.
  ///
  /// The immutable snapshot catches ordinary source drift; this epoch also
  /// catches ABA (`B -> A -> B`) where bytes happen to equal the pointer-down
  /// document again before release.
  final int Function()? documentEpoch;

  /// Lease for renderer geometry reports.
  ///
  /// Clearing or replacing the active page invalidates every prior report,
  /// even when the replacement Canvas happens to have the same target and
  /// size. [CanvasBlock] uses this generation to re-run the handshake and to
  /// discard a post-frame callback born under an older document.
  final int canvasMeasurementGeneration;
  final ValueChanged<Size>? onCanvasSizeChanged;
  final VoidCallback? onBackgroundTap;

  final WebsiteCanvasRootWrite? setRootProperties;
  final WebsiteCanvasRootReset? clearRootOverrides;
  final WebsiteCanvasLayerWrite? setLayerProperties;
  final WebsiteCanvasLayerReset? clearLayerOverrides;
  final WebsiteCanvasLayerReorder? reorderLayer;
}
