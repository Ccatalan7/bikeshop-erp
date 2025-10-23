import 'dart:convert';
import 'dart:html' as html;

void setStructuredDataScript(String id, Map<String, dynamic> data) {
  removeStructuredDataScript(id);

  final script = html.ScriptElement()
    ..id = id
    ..type = 'application/ld+json'
    ..text = jsonEncode(data);

  final head = html.document.head ?? html.document.querySelector('head');
  if (head != null) {
    head.append(script);
  } else {
    // Fallback for unusual renderers where <head> is not available.
    html.document.body?.append(script);
  }

  assert(() {
    final exists = html.document.getElementById(id) != null;
    if (!exists) {
      html.window.console.warn(
        '[StructuredData] Failed to append script with id "$id".',
      );
    }
    return true;
  }());
}

void removeStructuredDataScript(String id) {
  final existing = html.document.getElementById(id);
  existing?.remove();
}
