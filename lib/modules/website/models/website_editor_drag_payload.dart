/// Typed drag payloads keep page blocks and nested Canvas layers from being
/// accepted by the wrong drop target.
sealed class WebsiteEditorDragPayload {
  const WebsiteEditorDragPayload();
}

final class ExistingWebsiteBlockDragPayload extends WebsiteEditorDragPayload {
  const ExistingWebsiteBlockDragPayload(this.blockId);

  final String blockId;
}

final class NewWebsiteBlockDragPayload extends WebsiteEditorDragPayload {
  const NewWebsiteBlockDragPayload(this.blockType);

  final String blockType;
}

final class CanvasElementDragPayload extends WebsiteEditorDragPayload {
  const CanvasElementDragPayload(this.elementType);

  final String elementType;
}
