/// Typed drag payloads keep page blocks and nested Canvas layers from being
/// accepted by the wrong drop target.
sealed class WebsiteEditorDragPayload {
  const WebsiteEditorDragPayload();
}

final class ExistingWebsiteBlockDragPayload extends WebsiteEditorDragPayload {
  const ExistingWebsiteBlockDragPayload({
    required this.blockId,
    required this.sessionRevision,
    required this.pageId,
    required this.pageSlug,
  });

  final String blockId;
  final int sessionRevision;
  final String? pageId;
  final String? pageSlug;

  /// A drag is a command lease over one editor document, not merely a block
  /// id. Re-opening the same page produces a new [sessionRevision], so a drag
  /// born before a page switch cannot be accepted by the later session even
  /// when its ids happen to match again (the ABA case).
  bool matchesDocument({
    required int sessionRevision,
    required String? pageId,
    required String? pageSlug,
  }) =>
      this.sessionRevision == sessionRevision &&
      this.pageId == pageId &&
      this.pageSlug == pageSlug;
}

final class NewWebsiteBlockDragPayload extends WebsiteEditorDragPayload {
  const NewWebsiteBlockDragPayload(this.blockType);

  final String blockType;
}

final class CanvasElementDragPayload extends WebsiteEditorDragPayload {
  const CanvasElementDragPayload(this.elementType);

  final String elementType;
}
