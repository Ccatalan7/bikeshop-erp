import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

const _blockedElements = <String>{
  'applet',
  'base',
  'embed',
  'form',
  'frame',
  'frameset',
  'iframe',
  'link',
  'math',
  'object',
  'script',
  'svg',
};

const _urlAttributes = <String>{
  'action',
  'background',
  'cite',
  'data-href',
  'data-link',
  'data-url',
  'dynsrc',
  'formaction',
  'href',
  'longdesc',
  'lowsrc',
  'poster',
  'src',
};

final _controlAndWhitespace = RegExp(r'[\u0000-\u0020\u007f-\u009f]');
final _schemePattern = RegExp(r'^([a-z][a-z0-9+.-]*):');

/// Removes active content from provider-owned HTML before it enters the native
/// WebView. The reader needs JavaScript for its own navigation/keyboard bridge,
/// so sender scripts and event attributes must never share that execution
/// context.
String sanitizeEmailHtml(String content) {
  if (content.trim().isEmpty) return content;

  final isDocument = RegExp(
    r'<!doctype\b|<html\b|<head\b|<body\b',
    caseSensitive: false,
  ).hasMatch(content);
  final Document? document = isDocument ? html_parser.parse(content) : null;
  final DocumentFragment? fragment =
      isDocument ? null : html_parser.parseFragment(content);

  final elements = (document ?? fragment!).querySelectorAll('*').toList(
        growable: false,
      );
  for (final element in elements) {
    final tag = element.localName?.toLowerCase() ?? '';
    if (_blockedElements.contains(tag)) {
      element.remove();
      continue;
    }

    if (tag == 'meta' && _attribute(element, 'http-equiv') != null) {
      element.remove();
      continue;
    }
    if (tag == 'style' && _unsafeCss(element.text)) {
      element.remove();
      continue;
    }

    for (final key in element.attributes.keys.toList(growable: false)) {
      final name = key.toString().toLowerCase();
      final value = element.attributes[key] ?? '';
      if (name.startsWith('on') ||
          name == 'srcdoc' ||
          name == 'ping' ||
          name == 'srcset' ||
          name == 'xlink:href') {
        element.attributes.remove(key);
        continue;
      }
      if (name == 'style' && _unsafeCss(value)) {
        element.attributes.remove(key);
        continue;
      }
      if (_urlAttributes.contains(name) && !_isSafeUrl(value, name)) {
        element.attributes.remove(key);
      }
    }

    if (tag == 'a' && _attribute(element, 'href') != null) {
      element.attributes['rel'] = 'noopener noreferrer';
    }
  }

  return document?.outerHtml ?? fragment!.outerHtml;
}

String? _attribute(Element element, String name) {
  for (final entry in element.attributes.entries) {
    if (entry.key.toString().toLowerCase() == name) return entry.value;
  }
  return null;
}

bool _unsafeCss(String value) {
  final normalized = value.toLowerCase().replaceAll(_controlAndWhitespace, '');
  return normalized.contains('expression(') ||
      normalized.contains('javascript:') ||
      normalized.contains('vbscript:') ||
      normalized.contains('behavior:') ||
      normalized.contains('-moz-binding') ||
      normalized.contains('@import');
}

bool _isSafeUrl(String value, String attribute) {
  final normalized =
      value.trim().toLowerCase().replaceAll(_controlAndWhitespace, '');
  if (normalized.isEmpty) return true;

  if (normalized.startsWith('data:')) {
    if (attribute != 'src' && attribute != 'background') return false;
    return RegExp(
      r'^data:image/(?:png|jpe?g|gif|webp);base64,',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  final scheme = _schemePattern.firstMatch(normalized)?.group(1);
  if (scheme == null) return true;
  if (attribute == 'href' ||
      attribute == 'cite' ||
      attribute.startsWith('data-')) {
    return const {'http', 'https', 'mailto', 'tel'}.contains(scheme);
  }
  return const {'http', 'https', 'cid'}.contains(scheme);
}
