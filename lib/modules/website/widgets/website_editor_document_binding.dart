import 'package:flutter/widgets.dart';

import '../providers/website_edit_mode_provider.dart';

/// Provenance of a routed page's loaded content.
///
/// `editor` content (draft/unpublished rows read through
/// `loadEditorPageWithBlocks`) carries the lease fingerprint that authorized
/// it and may only render while that exact lease is still granted. `public`
/// content has no authority requirement.
enum WebsitePageContentAudience { public, editor }

/// Shared, idempotent page-document binding for the storefront consumers
/// (Home, dynamic CMS pages and static policy pages).
///
/// The FSM route command owns the MODE; this binding owns attaching the
/// routed page's DOCUMENT to the open editor session once its data is ready.
/// It is safe to call from `build` on every rebuild: page identity is checked
/// first and [WebsiteEditModeProvider.activatePageDocument] defers its
/// notification to the end of the frame, so consumers need no scheduling
/// flags, delays or per-page synchronizers.
class WebsiteEditorDocumentBinding {
  const WebsiteEditorDocumentBinding._();

  static void bind(
    BuildContext context, {
    required WebsiteEditModeProvider editProvider,
    required bool ready,
    required List<Map<String, dynamic>> Function() blocks,
    required Map<String, dynamic> Function() settings,
    String? pageId,
    String? pageSlug,
  }) {
    // A kept-alive offstage page (persistent shell) must never rebind the
    // active document while the user is viewing another page.
    if (!TickerMode.of(context)) return;
    if (!editProvider.isInEditorContext) return;
    if (!ready) return;
    if (editProvider.ownsPageDocument(pageId: pageId, pageSlug: pageSlug)) {
      return;
    }
    editProvider.activatePageDocument(
      blocks(),
      settings(),
      pageId: pageId,
      pageSlug: pageSlug,
    );
  }
}
