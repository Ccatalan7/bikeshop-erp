const _protectedTextTags = <String>{
  'a',
  'script',
  'style',
  'textarea',
};

final _htmlTagPattern = RegExp(
  r'<!--.*?-->|<![^>]*>|<[^>]*>',
  caseSensitive: false,
  dotAll: true,
);

final _tagNamePattern = RegExp(
  r'^<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9:_-]*)',
);

final _bareWebUrlPattern = RegExp(
  r'https?(?::|&#0*58;|&#x0*3a;|&colon;)(?://|(?:(?:&#0*47;|&#x0*2f;|&sol;)){2})[^\s<>"\x27]+',
  caseSensitive: false,
);

/// Turns visible bare HTTP(S) URLs into links without rewriting the email HTML.
///
/// Existing anchors and text inside style, script, or textarea elements are
/// left untouched. Preformatted text remains eligible because Gmail wraps
/// complete `text/plain` messages in `<pre>`. Keeping the original markup intact is
/// important for real-world email HTML, which is frequently malformed or uses
/// provider-specific conditional comments.
String linkifyBareEmailUrls(String content) {
  if (content.isEmpty || !_bareWebUrlPattern.hasMatch(content)) return content;

  final output = StringBuffer();
  final protectedDepth = <String, int>{};
  var cursor = 0;

  for (final tagMatch in _htmlTagPattern.allMatches(content)) {
    final text = content.substring(cursor, tagMatch.start);
    output.write(
      protectedDepth.isEmpty ? _linkifyVisibleText(text) : text,
    );

    final tag = tagMatch.group(0)!;
    output.write(tag);
    _updateProtectedDepth(tag, protectedDepth);
    cursor = tagMatch.end;
  }

  final remaining = content.substring(cursor);
  output.write(
    protectedDepth.isEmpty ? _linkifyVisibleText(remaining) : remaining,
  );
  return output.toString();
}

void _updateProtectedDepth(String tag, Map<String, int> protectedDepth) {
  final match = _tagNamePattern.firstMatch(tag);
  if (match == null) return;

  final isClosing = match.group(1) == '/';
  final name = match.group(2)!.toLowerCase();
  if (!_protectedTextTags.contains(name)) return;

  if (protectedDepth.isNotEmpty && !protectedDepth.containsKey(name)) {
    return;
  }

  if (isClosing) {
    final depth = protectedDepth[name] ?? 0;
    if (depth <= 1) {
      protectedDepth.remove(name);
    } else {
      protectedDepth[name] = depth - 1;
    }
    return;
  }

  if (tag.trimRight().endsWith('/>')) return;
  protectedDepth[name] = (protectedDepth[name] ?? 0) + 1;
}

String _linkifyVisibleText(String text) {
  return text.replaceAllMapped(_bareWebUrlPattern, (match) {
    final matched = match.group(0)!;
    final splitAt = _linkEnd(matched);
    if (splitAt == 0) return matched;

    final url = matched.substring(0, splitAt);
    final trailing = matched.substring(splitAt);
    final escapedUrl = _escapeHtmlAttribute(_decodeUrlEntities(url));
    return '<a class="vinabike-auto-link" href="$escapedUrl" '
        'target="_self" rel="noopener noreferrer" '
        'style="color:#0b57d0;text-decoration:underline;">'
        '$url</a>$trailing';
  });
}

String _decodeUrlEntities(String value) {
  return value
      .replaceAll(
        RegExp(r'&#0*58;|&#x0*3a;|&colon;', caseSensitive: false),
        ':',
      )
      .replaceAll(
        RegExp(r'&#0*47;|&#x0*2f;|&sol;', caseSensitive: false),
        '/',
      )
      .replaceAll(RegExp(r'&amp;', caseSensitive: false), '&');
}

int _linkEnd(String value) {
  var end = value.length;
  while (end > 0 && '.,;:!?'.contains(value[end - 1])) {
    end--;
  }

  const pairedClosers = {')': '(', ']': '[', '}': '{'};
  while (end > 0) {
    final closer = value[end - 1];
    final opener = pairedClosers[closer];
    if (opener == null) break;

    final candidate = value.substring(0, end);
    final openCount = _characterCount(candidate, opener);
    final closeCount = _characterCount(candidate, closer);
    if (closeCount <= openCount) break;
    end--;
  }
  return end;
}

int _characterCount(String value, String character) {
  return RegExp(RegExp.escape(character)).allMatches(value).length;
}

String _escapeHtmlAttribute(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
