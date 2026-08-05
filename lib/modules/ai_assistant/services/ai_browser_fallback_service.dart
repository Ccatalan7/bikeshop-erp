import 'dart:async';
import 'dart:collection';

import 'package:uuid/uuid.dart';

import '../../../shared/models/supplier.dart';
import '../../../shared/services/browser_supplier_portal_catalog.dart';
import '../models/ai_browser_proposal.dart';

typedef AIBrowserSupplierLoader = Future<Iterable<Supplier>> Function();

/// Safe local bridge between an assistant portal choice and a future explicit
/// browser card.
///
/// The assistant supplies only a canonical supplier/portal ID. Supplier data
/// comes from the authority-scoped loader and the destination is resolved only
/// through [buildBrowserSupplierPortalCatalog]. The service never accepts a
/// model-provided URL and never performs navigation itself.
class AIBrowserFallbackService {
  AIBrowserFallbackService({
    required AIBrowserSupplierLoader loadSuppliers,
    required String authorityTenantId,
    DateTime Function()? now,
    this.proposalTtl = const Duration(minutes: 5),
    this.catalogLoadTimeout = const Duration(seconds: 15),
    this.maxPendingProposals = 64,
    this.maxPendingPerSession = 8,
    this.maxConcurrentCatalogLoads = 8,
    this.maxCatalogRecords = 2048,
  })  : _loadSuppliers = loadSuppliers,
        _authorityTenantId = authorityTenantId.trim(),
        _now = now ?? DateTime.now {
    if (_authorityTenantId.isEmpty ||
        _authorityTenantId.length > _maxIdentifierLength) {
      throw ArgumentError.value(
        authorityTenantId,
        'authorityTenantId',
        'Must be a bounded, non-empty tenant identifier.',
      );
    }
    if (proposalTtl <= Duration.zero) {
      throw ArgumentError.value(
        proposalTtl,
        'proposalTtl',
        'Must be positive.',
      );
    }
    if (maxPendingProposals <= 0) {
      throw ArgumentError.value(
        maxPendingProposals,
        'maxPendingProposals',
        'Must be positive.',
      );
    }
    if (catalogLoadTimeout <= Duration.zero) {
      throw ArgumentError.value(
        catalogLoadTimeout,
        'catalogLoadTimeout',
        'Must be positive.',
      );
    }
    if (maxPendingPerSession <= 0 ||
        maxPendingPerSession > maxPendingProposals) {
      throw ArgumentError.value(
        maxPendingPerSession,
        'maxPendingPerSession',
        'Must be positive and no greater than maxPendingProposals.',
      );
    }
    if (maxConcurrentCatalogLoads <= 0) {
      throw ArgumentError.value(
        maxConcurrentCatalogLoads,
        'maxConcurrentCatalogLoads',
        'Must be positive.',
      );
    }
    if (maxCatalogRecords <= 0) {
      throw ArgumentError.value(
        maxCatalogRecords,
        'maxCatalogRecords',
        'Must be positive.',
      );
    }
  }

  static const int _maxIdentifierLength = 200;
  static const int _maxSupplierNameLength = 512;
  static const int _maxWebsiteLength = 2048;
  static const int _maxProposalIdAttempts = 8;
  static final RegExp _canonicalIdPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]*$',
  );

  final AIBrowserSupplierLoader _loadSuppliers;
  final String _authorityTenantId;
  final DateTime Function() _now;

  final Duration proposalTtl;
  final Duration catalogLoadTimeout;
  final int maxPendingProposals;
  final int maxPendingPerSession;
  final int maxConcurrentCatalogLoads;
  final int maxCatalogRecords;

  final LinkedHashMap<String, _StoredBrowserProposal> _pending =
      LinkedHashMap<String, _StoredBrowserProposal>();
  final Map<String, int> _sessionGenerations = <String, int>{};
  final Map<String, int> _activeRequestsBySession = <String, int>{};
  int _activeCatalogLoads = 0;
  int _resetGeneration = 0;

  /// Creates a proposal without exposing or opening its destination.
  ///
  /// [supplierPortalId] must exactly match the `supplierId` of an entry in the
  /// canonical catalog. It is not a URL, host, supplier name or search query.
  Future<AIBrowserFallbackResult<AIBrowserProposal>> createProposal({
    required String sessionId,
    required String supplierPortalId,
  }) async {
    final normalizedSessionId = _normalizeCanonicalId(sessionId);
    final normalizedPortalId = _normalizeCanonicalId(supplierPortalId);
    if (normalizedSessionId == null || normalizedPortalId == null) {
      return _failure(AIBrowserFallbackFailureCode.invalidRequest);
    }

    if (_activeCatalogLoads >= maxConcurrentCatalogLoads ||
        (_activeRequestsBySession[normalizedSessionId] ?? 0) > 0) {
      return _failure(AIBrowserFallbackFailureCode.temporarilyUnavailable);
    }

    final capturedResetGeneration = _resetGeneration;
    final capturedSessionGeneration =
        _sessionGenerations[normalizedSessionId] ?? 0;
    _activeCatalogLoads++;
    _activeRequestsBySession.update(
      normalizedSessionId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    var catalogSlotOwnedByLoad = false;

    try {
      // Register the request before invoking the injectable clock. A reentrant
      // reset/invalidate from any infrastructure callback is then observable.
      final requestStartedAt = _safeUtcNow();
      if (requestStartedAt == null) {
        return _failure(AIBrowserFallbackFailureCode.temporarilyUnavailable);
      }
      if (_wasInvalidated(
        sessionId: normalizedSessionId,
        resetGeneration: capturedResetGeneration,
        sessionGeneration: capturedSessionGeneration,
      )) {
        return _failure(AIBrowserFallbackFailureCode.requestInvalidated);
      }
      _purgeExpiredAt(requestStartedAt);

      Iterable<Supplier> loadedSuppliers;
      Future<Iterable<Supplier>> loadFuture;
      try {
        loadFuture = _loadSuppliers();
      } catch (_) {
        if (_wasInvalidated(
          sessionId: normalizedSessionId,
          resetGeneration: capturedResetGeneration,
          sessionGeneration: capturedSessionGeneration,
        )) {
          return _failure(AIBrowserFallbackFailureCode.requestInvalidated);
        }
        return _failure(AIBrowserFallbackFailureCode.catalogUnavailable);
      }

      // The timeout bounds caller latency, not the underlying Future. Keep its
      // global slot occupied until it really settles so repeated timeouts can
      // never exceed [maxConcurrentCatalogLoads].
      try {
        final releaseFuture = loadFuture.then<void>(
          (_) => _releaseCatalogLoad(),
          onError: (Object _, StackTrace __) {
            _releaseCatalogLoad();
          },
        );
        catalogSlotOwnedByLoad = true;
        unawaited(releaseFuture);
      } catch (_) {
        return _failure(AIBrowserFallbackFailureCode.catalogUnavailable);
      }
      try {
        loadedSuppliers = await loadFuture.timeout(catalogLoadTimeout);
      } catch (_) {
        if (_wasInvalidated(
          sessionId: normalizedSessionId,
          resetGeneration: capturedResetGeneration,
          sessionGeneration: capturedSessionGeneration,
        )) {
          return _failure(AIBrowserFallbackFailureCode.requestInvalidated);
        }
        return _failure(AIBrowserFallbackFailureCode.catalogUnavailable);
      }

      if (_wasInvalidated(
        sessionId: normalizedSessionId,
        resetGeneration: capturedResetGeneration,
        sessionGeneration: capturedSessionGeneration,
      )) {
        return _failure(AIBrowserFallbackFailureCode.requestInvalidated);
      }

      BrowserSupplierPortalEntry? selectedEntry;
      try {
        final boundedSuppliers = _boundedSuppliers(loadedSuppliers);
        if (boundedSuppliers == null) {
          return _failure(AIBrowserFallbackFailureCode.catalogUnavailable);
        }
        for (final entry in buildBrowserSupplierPortalCatalog(
          boundedSuppliers,
        )) {
          if (entry.supplierId != normalizedPortalId) continue;
          if (selectedEntry != null) {
            return _failure(AIBrowserFallbackFailureCode.portalUnavailable);
          }
          selectedEntry = entry;
        }
      } catch (_) {
        return _failure(AIBrowserFallbackFailureCode.catalogUnavailable);
      }

      if (selectedEntry == null) {
        return _failure(AIBrowserFallbackFailureCode.portalUnavailable);
      }
      final destination = _destinationFromCatalog(selectedEntry);
      if (destination == null) {
        return _failure(AIBrowserFallbackFailureCode.portalUnavailable);
      }

      // Recheck immediately before publishing: resetSession/reset may run
      // while the authority-scoped loader is awaiting I/O.
      if (_wasInvalidated(
        sessionId: normalizedSessionId,
        resetGeneration: capturedResetGeneration,
        sessionGeneration: capturedSessionGeneration,
      )) {
        return _failure(AIBrowserFallbackFailureCode.requestInvalidated);
      }

      final proposalId = _allocateProposalId();
      if (proposalId == null) {
        return _failure(AIBrowserFallbackFailureCode.temporarilyUnavailable);
      }

      // ID generation and the injectable clock are trusted infrastructure
      // callbacks, but may still re-enter reset paths in tests or adapters.
      // Recheck after both, immediately before mutating pending proposals.
      if (_wasInvalidated(
        sessionId: normalizedSessionId,
        resetGeneration: capturedResetGeneration,
        sessionGeneration: capturedSessionGeneration,
      )) {
        return _failure(AIBrowserFallbackFailureCode.requestInvalidated);
      }
      final proposalCreatedAt = _safeUtcNow();
      if (proposalCreatedAt == null) {
        return _failure(AIBrowserFallbackFailureCode.temporarilyUnavailable);
      }
      if (_wasInvalidated(
        sessionId: normalizedSessionId,
        resetGeneration: capturedResetGeneration,
        sessionGeneration: capturedSessionGeneration,
      )) {
        return _failure(AIBrowserFallbackFailureCode.requestInvalidated);
      }

      DateTime expiresAt;
      try {
        expiresAt = proposalCreatedAt.add(proposalTtl);
      } catch (_) {
        return _failure(AIBrowserFallbackFailureCode.temporarilyUnavailable);
      }
      _trimForInsertion(normalizedSessionId, now: proposalCreatedAt);
      if (_wasInvalidated(
        sessionId: normalizedSessionId,
        resetGeneration: capturedResetGeneration,
        sessionGeneration: capturedSessionGeneration,
      )) {
        return _failure(AIBrowserFallbackFailureCode.requestInvalidated);
      }
      final proposal = AIBrowserProposal(
        proposalId: proposalId,
        supplierPortalId: destination.supplierPortalId,
        supplierName: destination.supplierName,
        host: destination.host,
        expiresAt: expiresAt,
      );
      _pending[proposalId] = _StoredBrowserProposal(
        sessionId: normalizedSessionId,
        proposal: proposal,
        destination: destination,
      );
      return AIBrowserFallbackResult<AIBrowserProposal>.success(proposal);
    } finally {
      if (!catalogSlotOwnedByLoad) _releaseCatalogLoad();
      final remaining =
          (_activeRequestsBySession[normalizedSessionId] ?? 1) - 1;
      if (remaining <= 0) {
        _activeRequestsBySession.remove(normalizedSessionId);
      } else {
        _activeRequestsBySession[normalizedSessionId] = remaining;
      }
      _cleanupSessionGeneration(normalizedSessionId);
    }
  }

  /// Atomically releases a catalog-derived destination at most once.
  ///
  /// Unknown, expired, already-consumed and cross-session proposal IDs share
  /// one failure so callers cannot probe another assistant session's state.
  AIBrowserFallbackResult<AIBrowserDestination> consumeProposal({
    required String sessionId,
    required String proposalId,
  }) {
    final normalizedSessionId = _normalizeCanonicalId(sessionId);
    final normalizedProposalId = _normalizeCanonicalId(proposalId);
    if (normalizedSessionId == null || normalizedProposalId == null) {
      return _failure(AIBrowserFallbackFailureCode.proposalUnavailable);
    }

    final now = _safeUtcNow();
    if (now == null) {
      return _failure(AIBrowserFallbackFailureCode.temporarilyUnavailable);
    }
    _purgeExpiredAt(now);
    final stored = _pending[normalizedProposalId];
    if (stored == null || stored.sessionId != normalizedSessionId) {
      return _failure(AIBrowserFallbackFailureCode.proposalUnavailable);
    }

    _pending.remove(normalizedProposalId);
    _cleanupSessionGeneration(normalizedSessionId);
    return AIBrowserFallbackResult<AIBrowserDestination>.success(
      stored.destination,
    );
  }

  /// Invalidates this session's pending proposals and in-flight loads.
  void invalidateSession(String sessionId) {
    final normalizedSessionId = _normalizeCanonicalId(sessionId);
    if (normalizedSessionId == null) return;

    _removeWhere(
      (stored) => stored.sessionId == normalizedSessionId,
    );
    if ((_activeRequestsBySession[normalizedSessionId] ?? 0) > 0) {
      _sessionGenerations.update(
        normalizedSessionId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    } else {
      _sessionGenerations.remove(normalizedSessionId);
    }
  }

  /// Invalidates every pending proposal and every load already in flight.
  void reset() {
    _pending.clear();
    _sessionGenerations.clear();
    _resetGeneration++;
  }

  int get pendingProposalCount {
    final now = _safeUtcNow();
    if (now != null) _purgeExpiredAt(now);
    return _pending.length;
  }

  int pendingProposalCountForSession(String sessionId) {
    final normalizedSessionId = _normalizeCanonicalId(sessionId);
    if (normalizedSessionId == null) return 0;
    final now = _safeUtcNow();
    if (now != null) _purgeExpiredAt(now);
    return _pendingCountForSession(normalizedSessionId);
  }

  bool _wasInvalidated({
    required String sessionId,
    required int resetGeneration,
    required int sessionGeneration,
  }) {
    return _resetGeneration != resetGeneration ||
        (_sessionGenerations[sessionId] ?? 0) != sessionGeneration;
  }

  List<Supplier>? _boundedSuppliers(Iterable<Supplier> suppliers) {
    final bounded = <Supplier>[];
    var visited = 0;
    for (final supplier in suppliers) {
      visited++;
      if (visited > maxCatalogRecords) return null;
      if (supplier.tenantId.trim() != _authorityTenantId) return null;
      if (supplier.id.length > _maxIdentifierLength ||
          supplier.name.length > _maxSupplierNameLength ||
          (supplier.website?.length ?? 0) > _maxWebsiteLength) {
        continue;
      }
      final portalUri = _safePortalUri(supplier.website);
      if (portalUri == null) continue;

      // Only this secret-free projection reaches the shared catalog. Supplier
      // credentials, contacts, bank data and notes stay outside browser state.
      final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      bounded.add(
        Supplier(
          id: supplier.id,
          tenantId: _authorityTenantId,
          name: supplier.name,
          website: portalUri.toString(),
          isActive: supplier.isActive,
          createdAt: epoch,
          updatedAt: epoch,
        ),
      );
    }
    return bounded;
  }

  AIBrowserDestination? _destinationFromCatalog(
    BrowserSupplierPortalEntry entry,
  ) {
    final uri = Uri.tryParse(entry.url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !_isPublicPortalHost(uri.host) ||
        (uri.hasPort && uri.port != 443) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.host.toLowerCase() != entry.host.toLowerCase()) {
      return null;
    }
    return AIBrowserDestination(
      supplierPortalId: entry.supplierId,
      supplierName: entry.supplierName,
      host: entry.host,
      uri: uri,
    );
  }

  Uri? _safePortalUri(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    final candidate = raw.contains('://') ? raw : 'https://$raw';
    final parsed = Uri.tryParse(candidate);
    if (parsed == null ||
        parsed.scheme.toLowerCase() != 'https' ||
        parsed.host.isEmpty ||
        !_isPublicPortalHost(parsed.host) ||
        (parsed.hasPort && parsed.port != 443)) {
      return null;
    }
    return Uri(
      scheme: 'https',
      host: parsed.host.toLowerCase(),
      path: parsed.path,
    );
  }

  bool _isPublicPortalHost(String rawHost) {
    final host = rawHost.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (host.isEmpty ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host.endsWith('.lan') ||
        host.contains(':')) {
      return false;
    }

    final labels = host.split('.');
    final numericLabelPattern = RegExp(r'^(?:[0-9]+|0x[0-9a-f]+)$');
    final looksLikeNumericAddress =
        labels.every((label) => numericLabelPattern.hasMatch(label));
    final canonicalDecimalLabelPattern = RegExp(r'^[0-9]+$');
    if (looksLikeNumericAddress &&
        (labels.length != 4 ||
            labels.any(
              (label) => !canonicalDecimalLabelPattern.hasMatch(label),
            ))) {
      // URL stacks accept shorthand such as 127.1 and hexadecimal forms as
      // IP addresses. Treat every non-canonical numeric address as unsafe
      // instead of letting it fall through as a hostname.
      return false;
    }

    final octets = labels.map(int.tryParse).toList(growable: false);
    if (octets.length != 4 || octets.any((octet) => octet == null)) {
      return host.contains('.') && labels.every((label) => label.isNotEmpty);
    }
    if (labels.any((label) => label.length > 1 && label.startsWith('0'))) {
      // Avoid octal interpretation differences between URL and DNS stacks.
      return false;
    }
    final values = octets.cast<int>();
    if (values.any((octet) => octet < 0 || octet > 255)) return false;
    final first = values[0];
    final second = values[1];
    return first != 0 &&
        first != 10 &&
        first != 127 &&
        !(first == 100 && second >= 64 && second <= 127) &&
        !(first == 169 && second == 254) &&
        !(first == 172 && second >= 16 && second <= 31) &&
        !(first == 192 && second == 168) &&
        !(first == 198 && (second == 18 || second == 19)) &&
        first < 224;
  }

  String? _allocateProposalId() {
    for (var attempt = 0; attempt < _maxProposalIdAttempts; attempt++) {
      String candidate;
      try {
        candidate = _newProposalId();
      } catch (_) {
        return null;
      }
      if (_normalizeCanonicalId(candidate) == candidate &&
          !_pending.containsKey(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  void _trimForInsertion(String sessionId, {required DateTime now}) {
    _purgeExpiredAt(now);
    while (_pendingCountForSession(sessionId) >= maxPendingPerSession) {
      final oldestForSession = _pending.entries.firstWhere(
        (entry) => entry.value.sessionId == sessionId,
      );
      _removeProposal(oldestForSession.key);
    }
    while (_pending.length >= maxPendingProposals) {
      _removeProposal(_pending.keys.first);
    }
  }

  void _purgeExpiredAt(DateTime now) {
    final affectedSessions = <String>{};
    _pending.removeWhere((_, stored) {
      final expired = !stored.proposal.isValidAt(now);
      if (expired) affectedSessions.add(stored.sessionId);
      return expired;
    });
    for (final sessionId in affectedSessions) {
      _cleanupSessionGeneration(sessionId);
    }
  }

  void _removeWhere(bool Function(_StoredBrowserProposal stored) predicate) {
    final keys = _pending.entries
        .where((entry) => predicate(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in keys) {
      _pending.remove(key);
    }
  }

  void _removeProposal(String proposalId) {
    final removed = _pending.remove(proposalId);
    if (removed != null) _cleanupSessionGeneration(removed.sessionId);
  }

  void _cleanupSessionGeneration(String sessionId) {
    if ((_activeRequestsBySession[sessionId] ?? 0) > 0) return;
    if (_pending.values.any((stored) => stored.sessionId == sessionId)) return;
    _sessionGenerations.remove(sessionId);
  }

  int _pendingCountForSession(String sessionId) =>
      _pending.values.where((stored) => stored.sessionId == sessionId).length;

  DateTime? _safeUtcNow() {
    try {
      return _now().toUtc();
    } catch (_) {
      return null;
    }
  }

  void _releaseCatalogLoad() {
    if (_activeCatalogLoads > 0) _activeCatalogLoads--;
  }

  static String? _normalizeCanonicalId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > _maxIdentifierLength ||
        !_canonicalIdPattern.hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  static AIBrowserFallbackResult<T> _failure<T extends Object>(
    AIBrowserFallbackFailureCode code,
  ) {
    return AIBrowserFallbackResult<T>.failure(
      AIBrowserFallbackFailure(code),
    );
  }

  static String _newProposalId() => const Uuid().v4();
}

class _StoredBrowserProposal {
  const _StoredBrowserProposal({
    required this.sessionId,
    required this.proposal,
    required this.destination,
  });

  final String sessionId;
  final AIBrowserProposal proposal;
  final AIBrowserDestination destination;
}
