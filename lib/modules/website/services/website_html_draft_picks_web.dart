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
        final id = switch (data['id']) {
          final String id when id.isNotEmpty => id,
          _ => null,
        };
        switch (data['type']) {
          case 'vb-draft-pick':
            controller.add((id: id, action: null));
          case 'vb-draft-action':
            if (data['action'] case final String action when id != null) {
              controller.add((id: id, action: action));
            }
        }
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
