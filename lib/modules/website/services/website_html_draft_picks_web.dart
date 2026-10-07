import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'website_html_draft_picks.dart';

/// The page of each view, by the view's nonce, once it said it is ready:
/// the frame is of another origin and cannot be scripted, only written to.
final _pages = <String, web.Window>{};

Stream<WebsiteHtmlDraftMessage> websiteHtmlDraftPicksImpl(String nonce) {
  late final StreamController<WebsiteHtmlDraftMessage> controller;
  web.EventListener? listener;
  controller = StreamController<WebsiteHtmlDraftMessage>(
    onListen: () {
      listener = ((web.MessageEvent event) {
        final data = event.data.dartify();
        if (data is! Map || data['nonce'] != nonce) return;
        if (data['type'] == 'vb-draft-ready' && event.source != null) {
          _pages[nonce] = event.source! as web.Window;
        }
        final message = WebsiteHtmlDraftMessage.fromPost(data);
        if (message != null) controller.add(message);
      }).toJS;
      web.window.addEventListener('message', listener);
    },
    onCancel: () {
      _pages.remove(nonce);
      if (listener != null) {
        web.window.removeEventListener('message', listener);
      }
    },
  );
  return controller.stream;
}

bool websiteHtmlDraftTellImpl(
  String nonce,
  String call,
  List<Object?> arguments,
) {
  final page = _pages[nonce];
  if (page == null) return false;
  page.postMessage(
    <String, Object?>{
      'type': 'vb-host',
      'nonce': nonce,
      'call': call,
      'args': arguments,
    }.jsify(),
    '*'.toJS,
  );
  return true;
}
