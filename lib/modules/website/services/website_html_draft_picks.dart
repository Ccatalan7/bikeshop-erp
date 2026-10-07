import 'website_html_draft_picks_stub.dart'
    if (dart.library.js_interop) 'website_html_draft_picks_web.dart';

/// The sections picked in the editor's «Vista HTML» when the ERP runs on the
/// web: there the page is a frame and tells the ERP with a message
/// (`{type: 'vb-draft-pick', id, nonce}`) instead of the web view's handler.
/// [nonce] is the one the view gave its page: a message from any other
/// window is not a pick. Empty on the other platforms.
Stream<String?> websiteHtmlDraftPicks(String nonce) =>
    websiteHtmlDraftPicksImpl(nonce);
