import 'website_html_draft_picks.dart';

Stream<WebsiteHtmlDraftMessage> websiteHtmlDraftPicksImpl(String nonce) =>
    const Stream<WebsiteHtmlDraftMessage>.empty();

void websiteHtmlDraftFramePointerImpl(String frameId, {required bool takes}) {}

bool websiteHtmlDraftTellImpl(
  String nonce,
  String call,
  List<Object?> arguments,
) =>
    false;
