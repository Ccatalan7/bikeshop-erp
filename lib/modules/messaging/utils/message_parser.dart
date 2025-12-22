abstract class MessageSegment {
  final String text;
  const MessageSegment(this.text);
}

class TextSegment extends MessageSegment {
  const TextSegment(super.text);
}

class ReferenceSegment extends MessageSegment {
  final RefType type;
  final String id; // The raw ID part (e.g., "123" from "#JOB-123")

  const ReferenceSegment(super.text, this.type, this.id);
}

enum RefType {
  job,
  invoice,
  product;

  static RefType? fromPrefix(String prefix) {
    switch (prefix.toUpperCase()) {
      case 'JOB':
        return RefType.job;
      case 'INV':
        return RefType.invoice;
      case 'PROD':
        return RefType.product;
      default:
        return null;
    }
  }
}

class MessageParser {
  // Matches #PREFIX-VALUE or #PREFIXVALUE (where VALUE must start with digit if no hyphen)
  // This avoids matching words like #INVALID as an invoice reference.
  static final RegExp _refRegex = RegExp(
      r'#(JOB|INV|PROD)(?:-([A-Za-z0-9-_]+)|(\d[A-Za-z0-9-_]*))',
      caseSensitive: false);

  static List<MessageSegment> parse(String text) {
    final segments = <MessageSegment>[];
    int lastIndex = 0;

    for (final match in _refRegex.allMatches(text)) {
      // Add preceding text
      if (match.start > lastIndex) {
        segments.add(TextSegment(text.substring(lastIndex, match.start)));
      }

      // Group 1: Prefix
      final prefix = match.group(1)!;
      // Group 2: Value with hyphen (matched without hyphen in capturing group)
      // Group 3: Value without hyphen (starts with digit)
      final id = match.group(2) ?? match.group(3)!;

      final type = RefType.fromPrefix(prefix);

      if (type != null) {
        // match.end might not be correct if we used non-capturing groups? No, .end is match end.
        segments.add(
            ReferenceSegment(text.substring(match.start, match.end), type, id));
      } else {
        segments.add(TextSegment(text.substring(match.start, match.end)));
      }

      lastIndex = match.end;
    }

    // Add remaining text
    if (lastIndex < text.length) {
      segments.add(TextSegment(text.substring(lastIndex)));
    }

    return segments;
  }
}
