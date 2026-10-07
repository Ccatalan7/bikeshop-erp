import 'website_html_draft_picks_stub.dart'
    if (dart.library.js_interop) 'website_html_draft_picks_web.dart';

/// What the page of the editor's «Vista HTML» tells the ERP when it runs on
/// the web: there the page is a frame and sends messages instead of calling
/// the web view's handlers. A pick (`{type: 'vb-draft-pick', id, nonce}`)
/// has no [action]; a press on the block bar
/// (`{type: 'vb-draft-action', id, action, nonce}`) has one.
typedef WebsiteHtmlDraftMessage = ({String? id, String? action});

/// The page's messages signed with [nonce], the one the view gave its page:
/// a message from any other window is ignored. Empty on the other
/// platforms.
Stream<WebsiteHtmlDraftMessage> websiteHtmlDraftPicks(String nonce) =>
    websiteHtmlDraftPicksImpl(nonce);
