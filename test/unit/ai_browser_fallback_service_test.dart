import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_browser_proposal.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_browser_fallback_service.dart';
import 'package:vinabike_erp/shared/models/supplier.dart';

void main() {
  group('AIBrowserFallbackService', () {
    test('default proposal IDs are opaque and encode no session or portal',
        () async {
      final service = AIBrowserFallbackService(
        loadSuppliers: () async => [_defaultSupplier()],
        authorityTenantId: 'tenant-a',
      );

      final proposal = (await service.createProposal(
        sessionId: 'session-sensitive-reference',
        supplierPortalId: 'supplier-a',
      ))
          .value!;

      expect(
        proposal.proposalId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(proposal.proposalId, isNot(contains('session-sensitive')));
      expect(proposal.proposalId, isNot(contains('supplier-a')));
    });

    test('releases only the sanitized catalog destination and only once',
        () async {
      final service = _service(
        suppliers: [
          _supplier(
            id: 'supplier-a',
            name: 'Proveedor A',
            website:
                'https://buyer:secret@portal.example/login?token=private#cart',
            portalUsername: 'account-secret',
            portalPassword: 'password-secret',
          ),
        ],
      );

      final creation = await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'supplier-a',
      );

      expect(creation.isSuccess, isTrue);
      final proposal = creation.value!;
      expect(proposal.supplierPortalId, 'supplier-a');
      expect(proposal.supplierName, 'Proveedor A');
      expect(proposal.host, 'portal.example');
      expect(proposal.proposalId, isNotEmpty);

      final firstConsume = service.consumeProposal(
        sessionId: 'session-a',
        proposalId: proposal.proposalId,
      );
      expect(firstConsume.isSuccess, isTrue);
      expect(
        firstConsume.value!.uri,
        Uri.parse('https://portal.example/login'),
      );
      expect(firstConsume.value!.uri.userInfo, isEmpty);
      expect(firstConsume.value!.uri.hasQuery, isFalse);
      expect(firstConsume.value!.uri.hasFragment, isFalse);

      final secondConsume = service.consumeProposal(
        sessionId: 'session-a',
        proposalId: proposal.proposalId,
      );
      expect(
        secondConsume.failure?.code,
        AIBrowserFallbackFailureCode.proposalUnavailable,
      );
      expect(service.pendingProposalCount, 0);
    });

    test('accepts an exact canonical ID, never a free URL or fuzzy name',
        () async {
      final service = _service(
        suppliers: [
          _supplier(
            id: 'supplier-a',
            name: 'Proveedor A',
            website: 'https://portal.example',
          ),
        ],
      );

      final freeUrl = await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'https://attacker.example/steal?secret=value',
      );
      final fuzzyName = await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'Proveedor A',
      );
      final syntacticallyValidAttacker = await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'attacker.example',
      );

      expect(
        freeUrl.failure?.code,
        AIBrowserFallbackFailureCode.invalidRequest,
      );
      expect(
        freeUrl.failure?.publicMessage,
        isNot(contains('attacker')),
      );
      expect(
        fuzzyName.failure?.code,
        AIBrowserFallbackFailureCode.invalidRequest,
      );
      expect(
        syntacticallyValidAttacker.failure?.code,
        AIBrowserFallbackFailureCode.portalUnavailable,
      );
      expect(service.pendingProposalCount, 0);
    });

    test('honors catalog filtering and canonical deduplication', () async {
      final service = _service(
        suppliers: [
          _supplier(
            id: 'inactive',
            name: 'Inactivo',
            website: 'https://inactive.example',
            isActive: false,
          ),
          _supplier(
            id: 'http-copy',
            name: 'HTTP copy',
            website: 'http://portal.example',
          ),
          _supplier(
            id: 'secure-copy',
            name: 'Secure copy',
            website: 'https://www.portal.example/login',
          ),
        ],
      );

      final inactive = await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'inactive',
      );
      final deduplicated = await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'http-copy',
      );
      final canonical = await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'secure-copy',
      );

      expect(
        inactive.failure?.code,
        AIBrowserFallbackFailureCode.portalUnavailable,
      );
      expect(
        deduplicated.failure?.code,
        AIBrowserFallbackFailureCode.portalUnavailable,
      );
      expect(canonical.isSuccess, isTrue);
      final destination = service.consumeProposal(
        sessionId: 'session-a',
        proposalId: canonical.value!.proposalId,
      );
      expect(
        destination.value?.uri,
        Uri.parse('https://www.portal.example/login'),
      );
    });

    test('a cross-session attempt cannot inspect or burn a proposal', () async {
      final service = _service(suppliers: [_defaultSupplier()]);
      final proposal = (await service.createProposal(
        sessionId: 'session-owner',
        supplierPortalId: 'supplier-a',
      ))
          .value!;

      final foreignAttempt = service.consumeProposal(
        sessionId: 'session-other',
        proposalId: proposal.proposalId,
      );
      expect(
        foreignAttempt.failure?.code,
        AIBrowserFallbackFailureCode.proposalUnavailable,
      );
      expect(service.pendingProposalCountForSession('session-owner'), 1);

      expect(
        service
            .consumeProposal(
              sessionId: 'session-owner',
              proposalId: proposal.proposalId,
            )
            .isSuccess,
        isTrue,
      );
    });

    test('expiry invalidates the proposal at the exact boundary', () async {
      var now = DateTime.utc(2026, 8, 4, 20);
      final service = _service(
        suppliers: [_defaultSupplier()],
        now: () => now,
        proposalTtl: const Duration(minutes: 2),
      );
      final proposal = (await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'supplier-a',
      ))
          .value!;

      now = proposal.expiresAt;
      final result = service.consumeProposal(
        sessionId: 'session-a',
        proposalId: proposal.proposalId,
      );

      expect(
        result.failure?.code,
        AIBrowserFallbackFailureCode.proposalUnavailable,
      );
      expect(service.pendingProposalCount, 0);
    });

    test('session invalidation is scoped and reset invalidates everything',
        () async {
      final service = _service(suppliers: [_defaultSupplier()]);
      final proposalA = (await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'supplier-a',
      ))
          .value!;
      final proposalB = (await service.createProposal(
        sessionId: 'session-b',
        supplierPortalId: 'supplier-a',
      ))
          .value!;

      service.invalidateSession('session-a');
      expect(
        service
            .consumeProposal(
              sessionId: 'session-a',
              proposalId: proposalA.proposalId,
            )
            .failure
            ?.code,
        AIBrowserFallbackFailureCode.proposalUnavailable,
      );
      expect(
        service
            .consumeProposal(
              sessionId: 'session-b',
              proposalId: proposalB.proposalId,
            )
            .isSuccess,
        isTrue,
      );

      final proposalC = (await service.createProposal(
        sessionId: 'session-c',
        supplierPortalId: 'supplier-a',
      ))
          .value!;
      service.reset();
      expect(
        service
            .consumeProposal(
              sessionId: 'session-c',
              proposalId: proposalC.proposalId,
            )
            .failure
            ?.code,
        AIBrowserFallbackFailureCode.proposalUnavailable,
      );
    });

    test('session invalidation during I/O cannot publish a stale proposal',
        () async {
      final loader = Completer<Iterable<Supplier>>();
      final service = AIBrowserFallbackService(
        loadSuppliers: () => loader.future,
        authorityTenantId: 'tenant-a',
      );

      final pendingCreation = service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'supplier-a',
      );
      service.invalidateSession('session-a');
      loader.complete([_defaultSupplier()]);

      final result = await pendingCreation;
      expect(
        result.failure?.code,
        AIBrowserFallbackFailureCode.requestInvalidated,
      );
      expect(service.pendingProposalCount, 0);
    });

    test('reentrant reset from the clock cannot publish after invalidation',
        () async {
      var clockCalls = 0;
      late AIBrowserFallbackService service;
      service = AIBrowserFallbackService(
        loadSuppliers: () async => [_defaultSupplier()],
        authorityTenantId: 'tenant-a',
        now: () {
          clockCalls++;
          if (clockCalls == 1) service.reset();
          return DateTime.utc(2026, 8, 4, 20);
        },
      );

      final result = await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'supplier-a',
      );

      expect(
        result.failure?.code,
        AIBrowserFallbackFailureCode.requestInvalidated,
      );
      expect(service.pendingProposalCount, 0);
    });

    test('a global reset also invalidates catalog I/O already in flight',
        () async {
      final loader = Completer<Iterable<Supplier>>();
      final service = AIBrowserFallbackService(
        loadSuppliers: () => loader.future,
        authorityTenantId: 'tenant-a',
      );

      final pendingCreation = service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'supplier-a',
      );
      service.reset();
      loader.complete([_defaultSupplier()]);

      final result = await pendingCreation;
      expect(
        result.failure?.code,
        AIBrowserFallbackFailureCode.requestInvalidated,
      );
      expect(service.pendingProposalCount, 0);
    });

    test('a timeout keeps its real load bounded until that load settles',
        () async {
      final stuckLoader = Completer<Iterable<Supplier>>();
      var loadCalls = 0;
      final service = AIBrowserFallbackService(
        loadSuppliers: () {
          loadCalls++;
          return loadCalls == 1
              ? stuckLoader.future
              : Future<Iterable<Supplier>>.value([_defaultSupplier()]);
        },
        authorityTenantId: 'tenant-a',
        catalogLoadTimeout: const Duration(milliseconds: 10),
        maxConcurrentCatalogLoads: 1,
      );

      final timedOut = await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'supplier-a',
      );
      final stillBounded = await service.createProposal(
        sessionId: 'session-b',
        supplierPortalId: 'supplier-a',
      );
      stuckLoader.complete([_defaultSupplier()]);
      await Future<void>.delayed(Duration.zero);
      final recovered = await service.createProposal(
        sessionId: 'session-b',
        supplierPortalId: 'supplier-a',
      );

      expect(
        timedOut.failure?.code,
        AIBrowserFallbackFailureCode.catalogUnavailable,
      );
      expect(
        stillBounded.failure?.code,
        AIBrowserFallbackFailureCode.temporarilyUnavailable,
      );
      expect(recovered.isSuccess, isTrue);
      expect(loadCalls, 2);
    });

    test('clock failures stay inside the closed sanitized vocabulary',
        () async {
      final service = AIBrowserFallbackService(
        loadSuppliers: () async => [_defaultSupplier()],
        authorityTenantId: 'tenant-a',
        now: () => throw StateError('clock-api-secret'),
      );

      final creation = await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'supplier-a',
      );
      final consumption = service.consumeProposal(
        sessionId: 'session-a',
        proposalId: '00000000-0000-4000-8000-000000000000',
      );

      expect(
        creation.failure?.code,
        AIBrowserFallbackFailureCode.temporarilyUnavailable,
      );
      expect(
        consumption.failure?.code,
        AIBrowserFallbackFailureCode.temporarilyUnavailable,
      );
      expect(creation.failure?.publicMessage, isNot(contains('clock-api')));
      expect(() => service.pendingProposalCount, returnsNormally);
    });

    test('pending proposals remain globally and per-session bounded', () async {
      final service = _service(
        suppliers: [
          _defaultSupplier(),
          _supplier(
            id: 'supplier-b',
            name: 'Proveedor B',
            website: 'https://portal-b.example',
          ),
        ],
        maxPendingProposals: 2,
        maxPendingPerSession: 1,
      );

      final first = (await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'supplier-a',
      ))
          .value!;
      final second = (await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'supplier-b',
      ))
          .value!;
      final third = (await service.createProposal(
        sessionId: 'session-b',
        supplierPortalId: 'supplier-a',
      ))
          .value!;

      expect(service.pendingProposalCount, 2);
      expect(service.pendingProposalCountForSession('session-a'), 1);
      expect(
        service
            .consumeProposal(
              sessionId: 'session-a',
              proposalId: first.proposalId,
            )
            .failure
            ?.code,
        AIBrowserFallbackFailureCode.proposalUnavailable,
      );
      expect(
        service
            .consumeProposal(
              sessionId: 'session-a',
              proposalId: second.proposalId,
            )
            .isSuccess,
        isTrue,
      );
      expect(
        service
            .consumeProposal(
              sessionId: 'session-b',
              proposalId: third.proposalId,
            )
            .isSuccess,
        isTrue,
      );
    });

    test('catalog size and concurrent loads are bounded', () async {
      final oversized = _service(
        suppliers: [
          _defaultSupplier(),
          _supplier(
            id: 'supplier-b',
            name: 'Proveedor B',
            website: 'https://portal-b.example',
          ),
        ],
        maxCatalogRecords: 1,
      );
      final oversizedResult = await oversized.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'supplier-a',
      );
      expect(
        oversizedResult.failure?.code,
        AIBrowserFallbackFailureCode.catalogUnavailable,
      );

      final loader = Completer<Iterable<Supplier>>();
      final busy = AIBrowserFallbackService(
        loadSuppliers: () => loader.future,
        authorityTenantId: 'tenant-a',
        maxConcurrentCatalogLoads: 1,
      );
      final first = busy.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'supplier-a',
      );
      final second = await busy.createProposal(
        sessionId: 'session-b',
        supplierPortalId: 'supplier-a',
      );
      expect(
        second.failure?.code,
        AIBrowserFallbackFailureCode.temporarilyUnavailable,
      );
      loader.complete([_defaultSupplier()]);
      expect((await first).isSuccess, isTrue);
    });

    test('fails closed when the loader crosses the authority tenant', () async {
      final service = _service(
        suppliers: [
          _defaultSupplier(),
          _supplier(
            id: 'foreign',
            name: 'Foreign',
            website: 'https://foreign.example',
            tenantId: 'tenant-b',
          ),
        ],
      );

      final result = await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'supplier-a',
      );

      expect(
        result.failure?.code,
        AIBrowserFallbackFailureCode.catalogUnavailable,
      );
      expect(service.pendingProposalCount, 0);
    });

    test('rejects non-HTTPS and private-network destinations', () async {
      final service = _service(
        suppliers: [
          _supplier(
            id: 'http-only',
            name: 'HTTP',
            website: 'http://portal.example',
          ),
          _supplier(
            id: 'loopback',
            name: 'Loopback',
            website: 'https://127.0.0.1/login',
          ),
          _supplier(
            id: 'short-loopback',
            name: 'Short loopback',
            website: 'https://127.1/login',
          ),
          _supplier(
            id: 'octal-loopback',
            name: 'Octal loopback',
            website: 'https://0177.0.0.1/login',
          ),
          _supplier(
            id: 'hex-loopback',
            name: 'Hex loopback',
            website: 'https://0x7f.0.0.1/login',
          ),
          _supplier(
            id: 'private',
            name: 'Private',
            website: 'https://192.168.1.20/login',
          ),
          _supplier(
            id: 'internal',
            name: 'Internal',
            website: 'https://portal.internal/login',
          ),
        ],
      );

      for (final id in const <String>[
        'http-only',
        'loopback',
        'short-loopback',
        'octal-loopback',
        'hex-loopback',
        'private',
        'internal',
      ]) {
        final result = await service.createProposal(
          sessionId: 'session-$id',
          supplierPortalId: id,
        );
        expect(
          result.failure?.code,
          AIBrowserFallbackFailureCode.portalUnavailable,
        );
      }
      expect(service.pendingProposalCount, 0);
    });

    test('loader failures expose fixed copy without exception details',
        () async {
      final service = AIBrowserFallbackService(
        loadSuppliers: () async {
          throw StateError(
            'db-password-secret https://private.internal.example',
          );
        },
        authorityTenantId: 'tenant-a',
      );

      final result = await service.createProposal(
        sessionId: 'session-a',
        supplierPortalId: 'supplier-a',
      );
      final exposed = '${result.failure?.code} '
          '${result.failure?.publicMessage}';

      expect(
        result.failure?.code,
        AIBrowserFallbackFailureCode.catalogUnavailable,
      );
      expect(exposed, isNot(contains('password-secret')));
      expect(exposed, isNot(contains('private.internal')));
      expect(exposed, isNot(contains('supplier-a')));
    });
  });
}

AIBrowserFallbackService _service({
  required List<Supplier> suppliers,
  DateTime Function()? now,
  Duration proposalTtl = const Duration(minutes: 5),
  int maxPendingProposals = 64,
  int maxPendingPerSession = 8,
  int maxConcurrentCatalogLoads = 8,
  int maxCatalogRecords = 2048,
}) {
  return AIBrowserFallbackService(
    loadSuppliers: () async => suppliers,
    authorityTenantId: 'tenant-a',
    now: now,
    proposalTtl: proposalTtl,
    maxPendingProposals: maxPendingProposals,
    maxPendingPerSession: maxPendingPerSession,
    maxConcurrentCatalogLoads: maxConcurrentCatalogLoads,
    maxCatalogRecords: maxCatalogRecords,
  );
}

Supplier _defaultSupplier() => _supplier(
      id: 'supplier-a',
      name: 'Proveedor A',
      website: 'https://portal-a.example/login',
    );

Supplier _supplier({
  required String id,
  required String name,
  required String website,
  bool isActive = true,
  String? portalUsername,
  String? portalPassword,
  String tenantId = 'tenant-a',
}) {
  final timestamp = DateTime.utc(2026, 8, 4);
  return Supplier(
    id: id,
    tenantId: tenantId,
    name: name,
    website: website,
    portalUsername: portalUsername,
    portalPassword: portalPassword,
    isActive: isActive,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
