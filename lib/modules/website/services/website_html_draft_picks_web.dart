import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'website_html_draft_picks.dart';

/// The page of each view, by the view's nonce, once it said it is ready:
/// the frame is of another origin and cannot be scripted, only written to.
final _pages = <String, _Frame>{};

/// A window of another origin: the browser lets it be written to and
/// nothing else. Reading any of its properties throws a `SecurityError`, and
/// dart2js compiles a null check (`!`) or a type check into exactly such a
/// read (`source.toString`): measured in the published ERP on 2026-10-07,
/// where `event.source!` threw and the editor never answered its page. So it
/// is wrapped as it comes, without a check, and only `postMessage` is called.
extension type _Frame._(JSObject _) {
  external void postMessage(JSAny? message, JSString targetOrigin);
}

Stream<WebsiteHtmlDraftMessage> websiteHtmlDraftPicksImpl(String nonce) {
  late final StreamController<WebsiteHtmlDraftMessage> controller;
  web.EventListener? listener;
  controller = StreamController<WebsiteHtmlDraftMessage>(
    onListen: () {
      listener = ((web.MessageEvent event) {
        final data = event.data.dartify();
        if (data is! Map || data['nonce'] != nonce) return;
        final source = event.source;
        if (data['type'] == 'vb-draft-ready' && source != null) {
          _pages[nonce] = _Frame._(source);
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

void websiteHtmlDraftFramePointerImpl(String frameId, {required bool takes}) {
  final frame = web.document.getElementById(frameId);
  if (frame == null) return;
  (frame as web.HTMLElement).style.pointerEvents = takes ? '' : 'none';
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
