import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'website_html_draft_picks.dart';

Stream<WebsiteHtmlDraftMessage> websiteHtmlDraftPicksImpl(String nonce) {
  late final StreamController<WebsiteHtmlDraftMessage> controller;
  web.EventListener? listener;
  controller = StreamController<WebsiteHtmlDraftMessage>(
    onListen: () {
      listener = ((web.MessageEvent event) {
        final data = event.data.dartify();
        if (data is! Map || data['nonce'] != nonce) return;
        final message = WebsiteHtmlDraftMessage.fromPost(data);
        if (message != null) controller.add(message);
      }).toJS;
      web.window.addEventListener('message', listener);
    },
    onCancel: () {
      if (listener != null) {
        web.window.removeEventListener('message', listener);
      }
    },
  );
  return controller.stream;
}
