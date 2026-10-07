import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Stream<String?> websiteHtmlDraftPicksImpl() {
  late final StreamController<String?> controller;
  web.EventListener? listener;
  controller = StreamController<String?>(
    onListen: () {
      listener = ((web.MessageEvent event) {
        final data = event.data.dartify();
        if (data is Map && data['type'] == 'vb-draft-pick') {
          final id = data['id'];
          controller.add(id is String && id.isNotEmpty ? id : null);
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
