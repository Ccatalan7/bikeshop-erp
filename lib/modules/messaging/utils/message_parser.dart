import '../../../shared/services/route_share_service.dart';

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

class AppRouteLinkSegment extends MessageSegment {
  final Uri uri;
  final String route;

  const AppRouteLinkSegment(super.text, this.uri, this.route);
}

enum RefType {
  job,
  invoice,
  product,
  task;

  static RefType? fromPrefix(String prefix) {
    switch (prefix.toUpperCase()) {
      case 'JOB':
        return RefType.job;
      case 'INV':
        return RefType.invoice;
      case 'PROD':
        return RefType.product;
      case 'TASK':
        return RefType.task;
      default:
        return null;
    }
  }
}

class MessageParser {
  // Matches #PREFIX-VALUE or #PREFIXVALUE (where VALUE must start with digit if no hyphen)
  // This avoids matching words like #INVALID as an invoice reference.
  static final RegExp _refRegex = RegExp(
      r'#(JOB|INV|PROD|TASK)(?:-([A-Za-z0-9-_]+)|(\d[A-Za-z0-9-_]*))',
      caseSensitive: false);

  static final RegExp _appRouteLinkRegex = RegExp(
    r'(?:vinabike://app/open\?|https?://)[^\s\])>}]+',
    caseSensitive: false,
  );

  static List<MessageSegment> parse(String text) {
    final segments = <MessageSegment>[];
    final matches = <_MessageMatch>[];
    int lastIndex = 0;

    for (final match in _refRegex.allMatches(text)) {
      final prefix = match.group(1)!;
      final id = match.group(2) ?? match.group(3)!;
      final type = RefType.fromPrefix(prefix);

      if (type != null) {
        matches.add(
          _MessageMatch(
            match.start,
            match.end,
            ReferenceSegment(text.substring(match.start, match.end), type, id),
          ),
        );
      }
    }

    for (final match in _appRouteLinkRegex.allMatches(text)) {
      final value = text.substring(match.start, match.end);
      final uri = Uri.tryParse(value);
      if (uri == null) continue;

      final route = RouteShareService.routeFromUri(uri);
      if (route == null) continue;

      matches.add(
        _MessageMatch(
          match.start,
          match.end,
          AppRouteLinkSegment(value, uri, route),
        ),
      );
    }

    matches.sort((a, b) => a.start.compareTo(b.start));

    for (final match in matches) {
      if (match.start < lastIndex) continue;

      if (match.start > lastIndex) {
        segments.add(TextSegment(text.substring(lastIndex, match.start)));
      }

      segments.add(match.segment);
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      segments.add(TextSegment(text.substring(lastIndex)));
    }

    return segments;
  }
}

class _MessageMatch {
  final int start;
  final int end;
  final MessageSegment segment;

  const _MessageMatch(this.start, this.end, this.segment);
}
