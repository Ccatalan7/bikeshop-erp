import 'website_html_draft_picks_stub.dart'
    if (dart.library.js_interop) 'website_html_draft_picks_web.dart';

/// The sections picked in the editor's «Vista HTML» when the ERP runs on the
/// web: there the page is a frame and tells the ERP with a message
/// (`{type: 'vb-draft-pick', id}`) instead of the web view's handler. Empty
/// on the other platforms.
Stream<String?> websiteHtmlDraftPicks() => websiteHtmlDraftPicksImpl();
