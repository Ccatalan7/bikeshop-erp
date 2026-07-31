import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/models/storefront_publication_status.dart';
import 'package:vinabike_erp/modules/website/models/website_seo_center_models.dart';
import 'package:vinabike_erp/modules/website/services/storefront_publication_service.dart';

void main() {
  const tenantId = '5443b130-cc28-45af-a420-cd500b288890';
  const requestId = '11111111-1111-4111-8111-111111111111';
  final ownerDigest = List.filled(64, 'a').join();
  final buildDigest = List.filled(64, 'b').join();
  final releaseDigest = List.filled(64, 'c').join();
  final now = DateTime.utc(2026, 7, 28, 22, 30);

  Map<String, dynamic> configuredStatus({
    int desiredRevision = 12,
    int lastPublishedRevision = 12,
    String requestState = 'succeeded',
    Object? latestFailure,
  }) {
    return {
      'supported': true,
      'configured': true,
      'target_key': 'vinabike-store',
      'expected_store_origin': 'https://vinabike.cl',
      'expected_firebase_origin': 'https://vinabike-store.web.app',
      'dispatch_enabled': true,
      'desired_revision': desiredRevision,
      'last_published_revision': lastPublishedRevision,
      'request_state': requestState,
      'request_id': requestId,
      'last_published_request_id': requestId,
      'can_retry': latestFailure != null,
      'last_success': {
        'request_id': requestId,
        'attempt_id': '22222222-2222-4222-8222-222222222222',
        'published_revision': lastPublishedRevision,
        'github_run_id': 42,
        'github_run_attempt': 1,
        'github_sha': List.filled(40, 'd').join(),
        'github_run_url':
            'https://github.com/Ccatalan7/bikeshop-erp/actions/runs/42',
        'owner_source_sha256': ownerDigest,
        'build_input_sha256': buildDigest,
        'release_manifest_sha256': releaseDigest,
        'release_built_at': '2026-07-28T22:20:00Z',
        'primary_verified_at': '2026-07-28T22:21:00Z',
        'custom_verified_at': '2026-07-28T22:22:00Z',
        'completed_at': '2026-07-28T22:23:00Z',
      },
      'latest_failure': latestFailure,
    };
  }

  WebsiteSeoReleaseArtifactEvidence liveRelease({
    String? request = requestId,
    int revision = 12,
    String? ownerHash,
    String? buildHash,
  }) {
    return WebsiteSeoReleaseArtifactEvidence.fromJson({
      'url': 'https://vinabike.cl/release.json',
      'documentValid': true,
      'commit': List.filled(40, 'd').join(),
      'run': '42',
      'builtAt': '2026-07-28T22:20:00Z',
      'target': 'store',
      'source': 'github-actions',
      'dirty': false,
      'deployValid': true,
      'publication': {
        'requestId': request,
        'ownerRevision': revision,
        'ownerSourceSha256': ownerHash ?? ownerDigest,
        'buildInputSha256': buildHash ?? buildDigest,
      },
      'publicationTracked': true,
      'publicationValid': true,
    });
  }

  test('status sends only tenant identity and parses real nested evidence',
      () async {
    final calls = <(String, Map<String, dynamic>)>[];
    final service = StorefrontPublicationService(
      clock: () => now,
      invoke: (rpc, params) async {
        calls.add((rpc, params));
        return configuredStatus();
      },
    );

    final status = await service.loadStatus(tenantId);

    expect(calls, hasLength(1));
    expect(calls.single.$1, StorefrontPublicationService.statusRpc);
    expect(calls.single.$2, {'p_tenant_id': tenantId});
    expect(status.availability, StorefrontPublicationAvailability.configured);
    expect(status.ledgerClaimsCurrentRevision, isTrue);
    expect(status.provesCurrentLiveRelease(liveRelease()), isTrue);
    expect(status.lastSuccess?.buildInputSha256, buildDigest);
    expect(status.hasUnpublishedChanges, isFalse);
    expect(status.observedAt, now);
  });

  test('ledger success alone never proves a mismatched live release', () {
    final status = StorefrontPublicationStatus.fromJson(configuredStatus());

    expect(status.ledgerClaimsCurrentRevision, isTrue);
    expect(
      status.provesCurrentLiveRelease(
        liveRelease(buildHash: List.filled(64, 'e').join()),
      ),
      isFalse,
    );
  });

  test('newer nested failure is not hidden by an older success', () {
    final status = StorefrontPublicationStatus.fromJson(
      configuredStatus(
        desiredRevision: 13,
        lastPublishedRevision: 12,
        requestState: 'failed',
        latestFailure: {
          'request_id': '33333333-3333-4333-8333-333333333333',
          'attempt_id': '44444444-4444-4444-8444-444444444444',
          'state': 'failed',
          'requested_revision': 13,
          'attempt_no': 3,
          'failure_stage': 'verify_custom_origin',
          'error_class': 'release_mismatch',
          'error_message': 'technical detail',
          'finished_at': '2026-07-28T22:25:00Z',
        },
      ),
    );

    expect(status.hasUnpublishedChanges, isTrue);
    expect(status.hasFailed, isTrue);
    expect(status.ledgerClaimsCurrentRevision, isFalse);
    expect(status.latestFailure?.failureStage, 'verify_custom_origin');
  });

  test('an older failed attempt does not override the completed revision', () {
    final status = StorefrontPublicationStatus.fromJson(
      configuredStatus(
        latestFailure: {
          'request_id': '33333333-3333-4333-8333-333333333333',
          'attempt_id': '44444444-4444-4444-8444-444444444444',
          'state': 'failed',
          'requested_revision': 12,
          'attempt_no': 1,
          'failure_stage': 'build',
          'error_class': 'transient',
          'finished_at': '2026-07-28T22:10:00Z',
        },
      ),
    );

    expect(status.hasFailed, isFalse);
    expect(status.ledgerClaimsCurrentRevision, isTrue);
  });

  test('unsupported, unconfigured and read failure remain distinct', () {
    final unsupported = StorefrontPublicationStatus.fromJson({
      'supported': false,
      'configured': false,
    });
    final unconfigured = StorefrontPublicationStatus.fromJson({
      'supported': true,
      'configured': false,
      'dispatch_enabled': false,
    });
    final malformed = StorefrontPublicationStatus.fromJson(null);

    expect(
      unsupported.availability,
      StorefrontPublicationAvailability.unsupported,
    );
    expect(
      unconfigured.availability,
      StorefrontPublicationAvailability.notConfigured,
    );
    expect(unconfigured.supported, isTrue);
    expect(
      malformed.availability,
      StorefrontPublicationAvailability.readFailed,
    );
  });

  test('retry sends only tenant and failed request, and localizes reason',
      () async {
    late String rpc;
    late Map<String, dynamic> body;
    final service = StorefrontPublicationService(
      clock: () => now,
      invoke: (calledRpc, params) async {
        rpc = calledRpc;
        body = params;
        return {
          'accepted': true,
          'enqueued': true,
          'reason': 'manual_retry',
          'message': 'The storefront publication retry is queued',
          'status': {
            ...configuredStatus(
              desiredRevision: 13,
              lastPublishedRevision: 12,
              requestState: 'queued',
            ),
            'queue': {
              'request_id': requestId,
              'state': 'queued',
              'source': 'manual_retry',
              'requested_revision': 13,
              'coalesced_count': 0,
            },
          },
        };
      },
    );

    final result = await service.retry(
      tenantId: tenantId,
      failedRequestId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );

    expect(rpc, StorefrontPublicationService.retryRpc);
    expect(body, {
      'p_tenant_id': tenantId,
      'p_failed_request_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    });
    expect(
      body.keys,
      isNot(containsAll(['target', 'url', 'ref', 'revision', 'workflow'])),
    );
    expect(result.accepted, isTrue);
    expect(result.enqueued, isTrue);
    expect(result.reason, 'manual_retry');
    expect(result.message, 'El reintento quedó en cola.');
    expect(
      result.status.requestState,
      StorefrontPublicationRequestState.queued,
    );
  });

  test('typed retry failures preserve actionable meaning without secrets',
      () async {
    Future<StorefrontPublicationRetryResult> retryWithCode(String code) {
      final service = StorefrontPublicationService(
        clock: () => now,
        invoke: (_, __) async => throw PostgrestException(
          message: 'credential-shaped detail',
          code: code,
        ),
      );
      return service.retry(tenantId: tenantId);
    }

    final limited = await retryWithCode('PT429');
    final forbidden = await retryWithCode('42501');

    expect(limited.reason, 'rate_limited');
    expect(limited.message, contains('cinco minutos'));
    expect(limited.message, isNot(contains('credential-shaped')));
    expect(forbidden.reason, 'forbidden');
    expect(forbidden.message, contains('permiso'));
  });

  test('transport failures remain read failures and never invent success',
      () async {
    final service = StorefrontPublicationService(
      clock: () => now,
      invoke: (_, __) async => throw StateError('credential-shaped detail'),
    );

    final status = await service.loadStatus(tenantId);
    final retry = await service.retry(tenantId: tenantId);

    expect(status.readFailed, isTrue);
    expect(status.statusMessage, isNot(contains('credential-shaped')));
    expect(retry.accepted, isFalse);
    expect(retry.reason, 'transport_failed');
    expect(retry.message, isNot(contains('credential-shaped')));
  });
}
