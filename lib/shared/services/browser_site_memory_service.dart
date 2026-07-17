import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BrowserVisitedPage {
  const BrowserVisitedPage({
    required this.url,
    required this.title,
    required this.visitedAt,
  });

  final String url;
  final String title;
  final DateTime visitedAt;
}

class BrowserSiteMemoryEntry {
  const BrowserSiteMemoryEntry({
    required this.origin,
    required this.host,
    required this.title,
    required this.lastUrl,
    required this.lastVisitedAt,
    required this.visitCount,
  });

  final String origin;
  final String host;
  final String title;
  final String lastUrl;
  final DateTime lastVisitedAt;
  final int visitCount;

  String encode() => jsonEncode({
        'origin': origin,
        'host': host,
        'title': title,
        'lastUrl': lastUrl,
        'lastVisitedAt': lastVisitedAt.toIso8601String(),
        'visitCount': visitCount,
      });

  static BrowserSiteMemoryEntry? tryDecode(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) return null;
      final origin = decoded['origin'];
      final uri = origin is String ? Uri.tryParse(origin) : null;
      if (uri == null ||
          uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        return null;
      }
      final title = decoded['title'];
      final visitCount = decoded['visitCount'];
      final encodedLastUrl = decoded['lastUrl'];
      return BrowserSiteMemoryEntry(
        origin: uri.origin,
        host: uri.host,
        title: title is String && title.trim().isNotEmpty
            ? title.trim()
            : uri.host,
        lastUrl: _safeRevisitUrl(
          encodedLastUrl is String ? encodedLastUrl : uri.origin,
          expectedOrigin: uri.origin,
        ),
        lastVisitedAt: DateTime.tryParse('${decoded['lastVisitedAt']}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        visitCount: visitCount is int && visitCount > 0 ? visitCount : 1,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Persistent, per-ERP-user memory of sites visited from any browser tab.
class BrowserSiteMemoryService {
  BrowserSiteMemoryService._();

  static const prefsKey = 'vinabike_browser_sites_v1';
  static const maxEntries = 500;
  static final Map<String, Future<void>> _writeTails = {};

  static String _storageKey(String? userId) {
    final identity = userId?.trim();
    return '$prefsKey::${identity?.isNotEmpty == true ? identity : 'anonymous'}';
  }

  static Future<List<BrowserSiteMemoryEntry>> load(String? userId) async {
    final storageKey = _storageKey(userId);
    await (_writeTails[storageKey] ?? Future<void>.value());
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs, storageKey);
  }

  static Future<List<BrowserSiteMemoryEntry>> recordVisit({
    required String? userId,
    required String url,
    required String title,
    DateTime? visitedAt,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return load(userId);
    }

    return _mutate(userId, (entries) {
      final origin = uri.origin;
      final existingIndex = entries.indexWhere(
        (entry) => entry.origin == origin,
      );
      final existing =
          existingIndex < 0 ? null : entries.removeAt(existingIndex);
      final cleanTitle = title.trim();
      final candidateLastUrl = _safeRevisitUrl(
        uri.toString(),
        expectedOrigin: origin,
      );
      final lastUrl = _preferredRevisitUrl(
        existing: existing?.lastUrl,
        candidate: candidateLastUrl,
        origin: origin,
      );
      final preservesExistingPage = existing != null &&
          candidateLastUrl == origin &&
          lastUrl == existing.lastUrl;
      final updated = BrowserSiteMemoryEntry(
        origin: origin,
        host: uri.host,
        title: preservesExistingPage
            ? existing.title
            : (cleanTitle.isNotEmpty
                ? cleanTitle
                : (existing?.title ?? uri.host)),
        lastUrl: lastUrl,
        lastVisitedAt: visitedAt ?? DateTime.now(),
        visitCount: (existing?.visitCount ?? 0) + 1,
      );
      return <BrowserSiteMemoryEntry>[updated, ...entries];
    });
  }

  static Future<List<BrowserSiteMemoryEntry>> mergeFromHistory({
    required String? userId,
    required List<BrowserVisitedPage> history,
  }) {
    return _mutate(userId, (entries) {
      final existingOrigins = entries.map((entry) => entry.origin).toSet();
      final rootOnlyExistingOrigins = entries
          .where((entry) => entry.lastUrl == entry.origin)
          .map((entry) => entry.origin)
          .toSet();
      final byOrigin = <String, BrowserSiteMemoryEntry>{
        for (final entry in entries) entry.origin: entry,
      };
      for (final page in history.reversed) {
        final uri = Uri.tryParse(page.url);
        if (uri == null ||
            uri.host.isEmpty ||
            (uri.scheme != 'http' && uri.scheme != 'https')) {
          continue;
        }
        final existing = byOrigin[uri.origin];
        final candidateLastUrl = _safeRevisitUrl(
          uri.toString(),
          expectedOrigin: uri.origin,
        );
        final isExistingMemory = existingOrigins.contains(uri.origin);
        if (isExistingMemory &&
            (!rootOnlyExistingOrigins.contains(uri.origin) ||
                candidateLastUrl == uri.origin)) {
          continue;
        }
        final lastUrl = _preferredRevisitUrl(
          existing: existing?.lastUrl,
          candidate: candidateLastUrl,
          origin: uri.origin,
        );
        final preservesExistingPage = existing != null &&
            candidateLastUrl == uri.origin &&
            lastUrl == existing.lastUrl;
        byOrigin[uri.origin] = BrowserSiteMemoryEntry(
          origin: uri.origin,
          host: uri.host,
          title: preservesExistingPage
              ? existing.title
              : (page.title.trim().isEmpty ? uri.host : page.title.trim()),
          lastUrl: lastUrl,
          lastVisitedAt:
              existing != null && existing.lastVisitedAt.isAfter(page.visitedAt)
                  ? existing.lastVisitedAt
                  : page.visitedAt,
          visitCount: isExistingMemory
              ? existing!.visitCount
              : (existing?.visitCount ?? 0) + 1,
        );
      }
      return byOrigin.values.toList(growable: false);
    });
  }

  static Future<List<BrowserSiteMemoryEntry>> _mutate(
    String? userId,
    List<BrowserSiteMemoryEntry> Function(List<BrowserSiteMemoryEntry>) change,
  ) async {
    final storageKey = _storageKey(userId);
    final previous = _writeTails[storageKey] ?? Future<void>.value();
    final completer = Completer<List<BrowserSiteMemoryEntry>>();
    final write = previous.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final entries = _read(prefs, storageKey).toList(growable: true);
        final changed = change(entries)
          ..sort((a, b) => b.lastVisitedAt.compareTo(a.lastVisitedAt));
        final bounded = changed.take(maxEntries).toList(growable: false);
        await prefs.setStringList(
          storageKey,
          bounded.map((entry) => entry.encode()).toList(growable: false),
        );
        completer.complete(bounded);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _writeTails[storageKey] = write;
    try {
      await write;
      return await completer.future;
    } finally {
      if (identical(_writeTails[storageKey], write)) {
        _writeTails.remove(storageKey);
      }
    }
  }

  static List<BrowserSiteMemoryEntry> _read(
    SharedPreferences prefs,
    String storageKey,
  ) {
    final entries = <BrowserSiteMemoryEntry>[];
    for (final encoded in prefs.getStringList(storageKey) ?? const <String>[]) {
      final entry = BrowserSiteMemoryEntry.tryDecode(encoded);
      if (entry != null) entries.add(entry);
    }
    entries.sort((a, b) => b.lastVisitedAt.compareTo(a.lastVisitedAt));
    return entries.take(maxEntries).toList(growable: false);
  }
}

String _safeRevisitUrl(
  String value, {
  required String expectedOrigin,
}) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.origin != expectedOrigin) {
    return expectedOrigin;
  }

  const unsafePathTokens = <String>{
    'logout',
    'signout',
    'cerrar_sesion',
    'cerrar-sesion',
    'delete',
    'eliminar',
    'oauth',
    'callback',
    'password-reset',
    'reset-password',
  };
  final hasUnsafePath = uri.pathSegments.any((segment) {
    final normalized = segment.toLowerCase();
    return unsafePathTokens.any(normalized.contains);
  });
  if (hasUnsafePath || uri.path.isEmpty || uri.path == '/') {
    return expectedOrigin;
  }

  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}

String _preferredRevisitUrl({
  required String? existing,
  required String candidate,
  required String origin,
}) {
  if (candidate == origin && existing != null && existing != origin) {
    return existing;
  }
  return candidate;
}
