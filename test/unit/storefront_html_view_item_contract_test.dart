// `view_item` and Meta's `ViewContent` belong to the page of a product, never
// to a card's «Agregar» button (2026-11-24). The home has a products block and
// no product of its own; its cards' buttons carry `data-product-id` too, and
// the page script used to take the first one as the page's product, so every
// visit to the home counted as a view of the Maxxis aro 29 tube in GA4 and
// Meta (281 of 764 `view_item` from 27-oct to 23-nov). This runs the page
// script itself in Node against a stub page whose `querySelector` matches
// attribute selectors the way a browser does.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The page script, as the server sends it.
String _pageScript() {
  final source = File(
    'services/storefront_html/lib/src/storefront_script.dart',
  ).readAsStringSync();
  final start = source.indexOf("r'''") + 4;
  return source.substring(start, source.indexOf("'''", start));
}

/// A card's «Agregar» button, as `website_products_view.dart` and the
/// fitting list of `product_page_view.dart` write it.
Map<String, String> _quickAdd(String id, String sku, String name) => {
  'data-quick-add': '',
  'data-product-id': id,
  'data-max': '3',
  'data-item-id': sku,
  'data-item-name': name,
  'data-price': '6990',
};

/// The product section of a product page (`product_page_view.dart`).
Map<String, String> _productSection(String id, String sku, String name) => {
  'data-product-id': id,
  'data-item-id': sku,
  'data-item-name': name,
  'data-price': '550000',
  'data-max': '2',
};

/// Loads the script on a page whose elements, in document order, carry
/// [elements]' attributes, with measurement allowed, and returns what it sent
/// to `gtag` and `fbq`.
Future<({List<List<dynamic>> gtag, List<List<dynamic>> fbq})> _load(
  List<Map<String, String>> elements,
) async {
  final dir = await Directory.systemTemp.createTemp('view-item-contract');
  addTearDown(() => dir.delete(recursive: true));
  final page = File('${dir.path}/page.js')..writeAsStringSync(_pageScript());
  final harness = File('${dir.path}/harness.js')
    ..writeAsStringSync('''
const noop = () => {};
const toKey = (attr) => attr.replace(/^data-/, '').replace(/-([a-z])/g, (_, c) => c.toUpperCase());
const elements = ${jsonEncode(elements)}.map((attrs) => {
  const dataset = {};
  for (const [name, value] of Object.entries(attrs)) {
    if (name.startsWith('data-')) dataset[toKey(name)] = value;
  }
  return {
    attrs, dataset,
    hasAttribute: (name) => name in attrs,
    getAttribute: (name) => (name in attrs ? attrs[name] : null),
    getClientRects: () => [{}],
    querySelector: () => null,
    querySelectorAll: () => [],
    addEventListener: noop,
    classList: { add: noop, remove: noop, toggle: noop, contains: () => false },
  };
});
// Attribute selectors as a browser reads them: `[a]`, `[a]:not([b])`.
// Anything else finds nothing, as on a page without it.
function match(selector) {
  const m = /^\\[([a-z-]+)\\]((?::not\\(\\[[a-z-]+\\]\\))*)\$/.exec(selector);
  if (!m) return null;
  const without = [...m[2].matchAll(/:not\\(\\[([a-z-]+)\\]\\)/g)].map((x) => x[1]);
  return elements.filter((e) => e.hasAttribute(m[1]) && without.every((a) => !e.hasAttribute(a)));
}
const gtag = [];
const fbq = [];
globalThis.window = globalThis;
window.addEventListener = noop;
window.vinabikeMeasurementAllowed = true;
window.gtag = (...args) => gtag.push(args);
window.fbq = (...args) => fbq.push(args);
globalThis.location = { hash: '', href: 'https://vinabike.cl/', pathname: '/' };
globalThis.localStorage = { getItem: () => null, setItem: noop, removeItem: noop };
Object.defineProperty(globalThis, 'navigator', { value: { locks: {
  request: (name, fn) => Promise.resolve().then(fn),
} } });
globalThis.document = {
  documentElement: { classList: { add: noop } },
  body: { dataset: { tenant: 't', cartKey: 'k' } },
  head: { appendChild: noop },
  createElement: () => ({}),
  addEventListener: noop,
  getElementById: () => null,
  querySelector: (s) => { const found = match(s); return found && found.length ? found[0] : null; },
  querySelectorAll: (s) => match(s) || [],
};
require(${jsonEncode(page.path)});
setTimeout(() => process.stdout.write(JSON.stringify({ gtag, fbq })), 20);
''');
  final result = await Process.run('node', [harness.path]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  final out = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  List<List<dynamic>> calls(String key) =>
      (out[key] as List).map((c) => (c as List).toList()).toList();
  return (gtag: calls('gtag'), fbq: calls('fbq'));
}

List<List<dynamic>> _events(List<List<dynamic>> calls, String name) =>
    calls.where((c) => c.length > 1 && c[1] == name).toList();

void main() {
  final hasNode = Process.runSync('which', ['node']).exitCode == 0;
  final skip = hasNode ? false : 'node is not installed';

  test(
    'the home with a products block reports no product view',
    () async {
      final sent = await _load([
        _quickAdd('p-tube', '4717784040202', 'Cámara Maxxis aro 29'),
        _quickAdd('p-chain', 'C2725', 'Cadena KMC HV408'),
      ]);
      expect(_events(sent.gtag, 'view_item'), isEmpty);
      expect(_events(sent.fbq, 'ViewContent'), isEmpty);
    },
    skip: skip,
  );

  test(
    'a product page reports its own product once, not a fitting card',
    () async {
      final sent = await _load([
        _productSection('p-fork', 'SRM00685', 'Horquilla RockShox Recon'),
        _quickAdd('p-tube', '4717784040202', 'Cámara Maxxis aro 29'),
      ]);
      final views = _events(sent.gtag, 'view_item');
      expect(views, hasLength(1));
      final items = (views.single[2] as Map)['items'] as List;
      expect((items.single as Map)['item_id'], 'SRM00685');
      final content = _events(sent.fbq, 'ViewContent');
      expect(content, hasLength(1));
      expect((content.single[2] as Map)['content_ids'], ['SRM00685']);
    },
    skip: skip,
  );
}
