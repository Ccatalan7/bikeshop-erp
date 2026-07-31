import 'website_seo_center_models.dart';

/// Durable editor-to-storefront publication state.
///
/// This is operational evidence only. It never proves that Google crawled or
/// indexed a URL, and it does not own any editable SEO value.
enum StorefrontPublicationRequestState {
  queued,
  dispatching,
  dispatched,
  dispatchUnknown,
  running,
  sealed,
  succeeded,
  failed,
  deadLetter,
  superseded,
  unknown,
}

enum StorefrontPublicationAvailability {
  configured,
  notConfigured,
  unsupported,
  readFailed,
}

StorefrontPublicationRequestState _requestState(Object? raw) {
  return switch (raw?.toString().trim().toLowerCase()) {
    'queued' => StorefrontPublicationRequestState.queued,
    'dispatching' => StorefrontPublicationRequestState.dispatching,
    'dispatched' => StorefrontPublicationRequestState.dispatched,
    'dispatch_unknown' => StorefrontPublicationRequestState.dispatchUnknown,
    'running' => StorefrontPublicationRequestState.running,
    'sealed' => StorefrontPublicationRequestState.sealed,
    'succeeded' => StorefrontPublicationRequestState.succeeded,
    'failed' => StorefrontPublicationRequestState.failed,
    'dead_letter' => StorefrontPublicationRequestState.deadLetter,
    'superseded' => StorefrontPublicationRequestState.superseded,
    _ => StorefrontPublicationRequestState.unknown,
  };
}

class StorefrontPublicationQueueInfo {
  const StorefrontPublicationQueueInfo({
    required this.requestId,
    required this.state,
    required this.source,
    required this.requestedRevision,
    required this.coalescedCount,
    this.availableAt,
    this.createdAt,
  });

  factory StorefrontPublicationQueueInfo.fromJson(Object? raw) {
    final json = _stringMap(raw);
    return StorefrontPublicationQueueInfo(
      requestId: _text(json['request_id'] ?? json['requestId']),
      state: _requestState(json['state']),
      source: _text(json['source']),
      requestedRevision: _nonNegativeInt(
        json['requested_revision'] ?? json['requestedRevision'],
      ),
      coalescedCount: _nonNegativeInt(
        json['coalesced_count'] ?? json['coalescedCount'],
      ),
      availableAt: _dateTime(json['available_at'] ?? json['availableAt']),
      createdAt: _dateTime(json['created_at'] ?? json['createdAt']),
    );
  }

  final String requestId;
  final StorefrontPublicationRequestState state;
  final String source;
  final int requestedRevision;
  final int coalescedCount;
  final DateTime? availableAt;
  final DateTime? createdAt;
}

class StorefrontPublicationActiveAttempt {
  const StorefrontPublicationActiveAttempt({
    required this.requestId,
    required this.attemptId,
    required this.state,
    required this.requestedRevision,
    required this.attemptNo,
    required this.githubRunId,
    required this.githubRunAttempt,
    required this.githubSha,
    required this.githubRunUrl,
    this.startedAt,
    this.sealedAt,
    required this.failureStage,
    required this.errorClass,
    required this.errorMessage,
  });

  factory StorefrontPublicationActiveAttempt.fromJson(Object? raw) {
    final json = _stringMap(raw);
    return StorefrontPublicationActiveAttempt(
      requestId: _text(json['request_id'] ?? json['requestId']),
      attemptId: _text(json['attempt_id'] ?? json['attemptId']),
      state: _requestState(json['state']),
      requestedRevision: _nonNegativeInt(
        json['requested_revision'] ?? json['requestedRevision'],
      ),
      attemptNo: _nonNegativeInt(json['attempt_no'] ?? json['attemptNo']),
      githubRunId: _text(json['github_run_id'] ?? json['githubRunId']),
      githubRunAttempt: _nonNegativeInt(
        json['github_run_attempt'] ?? json['githubRunAttempt'],
      ),
      githubSha: _text(json['github_sha'] ?? json['githubSha']),
      githubRunUrl: _text(json['github_run_url'] ?? json['githubRunUrl']),
      startedAt: _dateTime(json['started_at'] ?? json['startedAt']),
      sealedAt: _dateTime(json['sealed_at'] ?? json['sealedAt']),
      failureStage: _text(json['failure_stage'] ?? json['failureStage']),
      errorClass: _text(json['error_class'] ?? json['errorClass']),
      errorMessage: _text(json['error_message'] ?? json['errorMessage']),
    );
  }

  final String requestId;
  final String attemptId;
  final StorefrontPublicationRequestState state;
  final int requestedRevision;
  final int attemptNo;
  final String githubRunId;
  final int githubRunAttempt;
  final String githubSha;
  final String githubRunUrl;
  final DateTime? startedAt;
  final DateTime? sealedAt;
  final String failureStage;
  final String errorClass;
  final String errorMessage;
}

class StorefrontPublicationSuccess {
  const StorefrontPublicationSuccess({
    required this.requestId,
    required this.attemptId,
    required this.publishedRevision,
    required this.githubRunId,
    required this.githubRunAttempt,
    required this.githubSha,
    required this.githubRunUrl,
    required this.ownerSourceSha256,
    required this.buildInputSha256,
    required this.releaseManifestSha256,
    this.releaseBuiltAt,
    this.primaryVerifiedAt,
    this.customVerifiedAt,
    this.completedAt,
  });

  factory StorefrontPublicationSuccess.fromJson(Object? raw) {
    final json = _stringMap(raw);
    return StorefrontPublicationSuccess(
      requestId: _text(json['request_id'] ?? json['requestId']),
      attemptId: _text(json['attempt_id'] ?? json['attemptId']),
      publishedRevision: _nonNegativeInt(
        json['published_revision'] ?? json['publishedRevision'],
      ),
      githubRunId: _text(json['github_run_id'] ?? json['githubRunId']),
      githubRunAttempt: _nonNegativeInt(
        json['github_run_attempt'] ?? json['githubRunAttempt'],
      ),
      githubSha: _text(json['github_sha'] ?? json['githubSha']),
      githubRunUrl: _text(json['github_run_url'] ?? json['githubRunUrl']),
      ownerSourceSha256: _text(
        json['owner_source_sha256'] ?? json['ownerSourceSha256'],
      ),
      buildInputSha256: _text(
        json['build_input_sha256'] ?? json['buildInputSha256'],
      ),
      releaseManifestSha256: _text(
        json['release_manifest_sha256'] ?? json['releaseManifestSha256'],
      ),
      releaseBuiltAt: _dateTime(
        json['release_built_at'] ?? json['releaseBuiltAt'],
      ),
      primaryVerifiedAt: _dateTime(
        json['primary_verified_at'] ?? json['primaryVerifiedAt'],
      ),
      customVerifiedAt: _dateTime(
        json['custom_verified_at'] ?? json['customVerifiedAt'],
      ),
      completedAt: _dateTime(json['completed_at'] ?? json['completedAt']),
    );
  }

  final String requestId;
  final String attemptId;
  final int publishedRevision;
  final String githubRunId;
  final int githubRunAttempt;
  final String githubSha;
  final String githubRunUrl;
  final String ownerSourceSha256;
  final String buildInputSha256;
  final String releaseManifestSha256;
  final DateTime? releaseBuiltAt;
  final DateTime? primaryVerifiedAt;
  final DateTime? customVerifiedAt;
  final DateTime? completedAt;

  bool get hasCompleteCorrelation =>
      _isUuid(requestId) &&
      publishedRevision > 0 &&
      _isSha256(ownerSourceSha256) &&
      _isSha256(buildInputSha256) &&
      _isSha256(releaseManifestSha256);

  bool matchesLiveRelease(WebsiteSeoReleaseArtifactEvidence release) {
    final evidence = release.publication;
    return hasCompleteCorrelation &&
        primaryVerifiedAt != null &&
        customVerifiedAt != null &&
        release.provesTrackedPublication &&
        evidence != null &&
        evidence.requestId == requestId &&
        evidence.ownerRevision == publishedRevision &&
        _sameDigest(evidence.ownerSourceSha256, ownerSourceSha256) &&
        _sameDigest(evidence.buildInputSha256, buildInputSha256);
  }
}

class StorefrontPublicationFailure {
  const StorefrontPublicationFailure({
    required this.requestId,
    required this.attemptId,
    required this.state,
    required this.requestedRevision,
    required this.attemptNo,
    required this.failureStage,
    required this.errorClass,
    required this.errorMessage,
    this.finishedAt,
  });

  factory StorefrontPublicationFailure.fromJson(Object? raw) {
    final json = _stringMap(raw);
    return StorefrontPublicationFailure(
      requestId: _text(json['request_id'] ?? json['requestId']),
      attemptId: _text(json['attempt_id'] ?? json['attemptId']),
      state: _requestState(json['state']),
      requestedRevision: _nonNegativeInt(
        json['requested_revision'] ?? json['requestedRevision'],
      ),
      attemptNo: _nonNegativeInt(json['attempt_no'] ?? json['attemptNo']),
      failureStage: _text(json['failure_stage'] ?? json['failureStage']),
      errorClass: _text(json['error_class'] ?? json['errorClass']),
      errorMessage: _text(json['error_message'] ?? json['errorMessage']),
      finishedAt: _dateTime(json['finished_at'] ?? json['finishedAt']),
    );
  }

  final String requestId;
  final String attemptId;
  final StorefrontPublicationRequestState state;
  final int requestedRevision;
  final int attemptNo;
  final String failureStage;
  final String errorClass;
  final String errorMessage;
  final DateTime? finishedAt;
}

class StorefrontPublicationStatus {
  const StorefrontPublicationStatus({
    required this.availability,
    required this.dispatchEnabled,
    required this.desiredRevision,
    required this.lastPublishedRevision,
    required this.requestState,
    required this.requestId,
    required this.lastPublishedRequestId,
    required this.canRetry,
    required this.statusMessage,
    required this.targetKey,
    required this.expectedStoreOrigin,
    required this.expectedFirebaseOrigin,
    this.lastOwnerChangeAt,
    this.lastPublishedAt,
    this.lastDispatchTickAt,
    required this.lastDispatchErrorClass,
    required this.lastDispatchErrorMessage,
    this.queue,
    this.active,
    this.lastSuccess,
    this.latestFailure,
    this.observedAt,
  });

  const StorefrontPublicationStatus.readFailure({
    required this.statusMessage,
    this.observedAt,
  })  : availability = StorefrontPublicationAvailability.readFailed,
        dispatchEnabled = false,
        desiredRevision = 0,
        lastPublishedRevision = 0,
        requestState = StorefrontPublicationRequestState.unknown,
        requestId = '',
        lastPublishedRequestId = '',
        canRetry = false,
        targetKey = '',
        expectedStoreOrigin = '',
        expectedFirebaseOrigin = '',
        lastOwnerChangeAt = null,
        lastPublishedAt = null,
        lastDispatchTickAt = null,
        lastDispatchErrorClass = '',
        lastDispatchErrorMessage = '',
        queue = null,
        active = null,
        lastSuccess = null,
        latestFailure = null;

  factory StorefrontPublicationStatus.fromJson(Object? raw) {
    final json = _stringMap(raw);
    if (json.isEmpty) {
      return const StorefrontPublicationStatus.readFailure(
        statusMessage: 'La respuesta de publicación no es válida.',
      );
    }
    final supported = json['supported'] == true;
    final configured = json['configured'] == true;
    return StorefrontPublicationStatus(
      availability: !supported
          ? StorefrontPublicationAvailability.unsupported
          : configured
              ? StorefrontPublicationAvailability.configured
              : StorefrontPublicationAvailability.notConfigured,
      dispatchEnabled:
          json['dispatch_enabled'] == true || json['dispatchEnabled'] == true,
      desiredRevision:
          _nonNegativeInt(json['desired_revision'] ?? json['desiredRevision']),
      lastPublishedRevision: _nonNegativeInt(
        json['last_published_revision'] ?? json['lastPublishedRevision'],
      ),
      requestState: _requestState(
        json['request_state'] ?? json['requestState'],
      ),
      requestId: _text(json['request_id'] ?? json['requestId']),
      lastPublishedRequestId: _text(
        json['last_published_request_id'] ?? json['lastPublishedRequestId'],
      ),
      canRetry: json['can_retry'] == true || json['canRetry'] == true,
      statusMessage: _text(
        json['status_message'] ?? json['statusMessage'],
      ),
      targetKey: _text(json['target_key'] ?? json['targetKey']),
      expectedStoreOrigin: _text(
        json['expected_store_origin'] ?? json['expectedStoreOrigin'],
      ),
      expectedFirebaseOrigin: _text(
        json['expected_firebase_origin'] ?? json['expectedFirebaseOrigin'],
      ),
      lastOwnerChangeAt: _dateTime(
        json['last_owner_change_at'] ?? json['lastOwnerChangeAt'],
      ),
      lastPublishedAt: _dateTime(
        json['last_published_at'] ?? json['lastPublishedAt'],
      ),
      lastDispatchTickAt: _dateTime(
        json['last_dispatch_tick_at'] ?? json['lastDispatchTickAt'],
      ),
      lastDispatchErrorClass: _text(
        json['last_dispatch_error_class'] ?? json['lastDispatchErrorClass'],
      ),
      lastDispatchErrorMessage: _text(
        json['last_dispatch_error_message'] ?? json['lastDispatchErrorMessage'],
      ),
      queue: _nested(
        json['queue'],
        StorefrontPublicationQueueInfo.fromJson,
      ),
      active: _nested(
        json['active'],
        StorefrontPublicationActiveAttempt.fromJson,
      ),
      lastSuccess: _nested(
        json['last_success'] ?? json['lastSuccess'],
        StorefrontPublicationSuccess.fromJson,
      ),
      latestFailure: _nested(
        json['latest_failure'] ?? json['latestFailure'],
        StorefrontPublicationFailure.fromJson,
      ),
      observedAt: _dateTime(json['observed_at'] ?? json['observedAt']),
    );
  }

  final StorefrontPublicationAvailability availability;
  final bool dispatchEnabled;
  final int desiredRevision;
  final int lastPublishedRevision;
  final StorefrontPublicationRequestState requestState;
  final String requestId;
  final String lastPublishedRequestId;
  final bool canRetry;
  final String statusMessage;
  final String targetKey;
  final String expectedStoreOrigin;
  final String expectedFirebaseOrigin;
  final DateTime? lastOwnerChangeAt;
  final DateTime? lastPublishedAt;
  final DateTime? lastDispatchTickAt;
  final String lastDispatchErrorClass;
  final String lastDispatchErrorMessage;
  final StorefrontPublicationQueueInfo? queue;
  final StorefrontPublicationActiveAttempt? active;
  final StorefrontPublicationSuccess? lastSuccess;
  final StorefrontPublicationFailure? latestFailure;
  final DateTime? observedAt;

  bool get supported =>
      availability != StorefrontPublicationAvailability.unsupported &&
      availability != StorefrontPublicationAvailability.readFailed;

  bool get configured =>
      availability == StorefrontPublicationAvailability.configured;

  bool get readFailed =>
      availability == StorefrontPublicationAvailability.readFailed;

  bool get hasUnpublishedChanges => desiredRevision > lastPublishedRevision;

  bool get hasTrackedPublication =>
      lastPublishedRevision > 0 && lastPublishedRequestId.isNotEmpty;

  bool get isWorking =>
      active != null ||
      queue != null ||
      switch (requestState) {
        StorefrontPublicationRequestState.queued ||
        StorefrontPublicationRequestState.dispatching ||
        StorefrontPublicationRequestState.dispatched ||
        StorefrontPublicationRequestState.dispatchUnknown ||
        StorefrontPublicationRequestState.running ||
        StorefrontPublicationRequestState.sealed =>
          true,
        _ => false,
      };

  bool get hasFailed {
    final failure = latestFailure;
    if (failure != null &&
        hasUnpublishedChanges &&
        failure.requestedRevision > lastPublishedRevision &&
        failure.requestedRevision == desiredRevision) {
      return true;
    }
    return switch (requestState) {
      StorefrontPublicationRequestState.failed ||
      StorefrontPublicationRequestState.deadLetter =>
        true,
      _ => false,
    };
  }

  /// A ledger success is necessary but not sufficient for "published".
  ///
  /// The caller must additionally compare the exact request, revision and
  /// hashes against the live release manifest. Dispatch may be disabled after
  /// a successful publication without invalidating that evidence.
  bool get ledgerClaimsCurrentRevision {
    final success = lastSuccess;
    return configured &&
        desiredRevision > 0 &&
        desiredRevision == lastPublishedRevision &&
        lastPublishedRequestId.isNotEmpty &&
        success != null &&
        success.requestId == lastPublishedRequestId &&
        success.publishedRevision == desiredRevision &&
        success.hasCompleteCorrelation &&
        success.primaryVerifiedAt != null &&
        success.customVerifiedAt != null;
  }

  bool provesCurrentLiveRelease(WebsiteSeoReleaseArtifactEvidence release) {
    final success = lastSuccess;
    return ledgerClaimsCurrentRevision &&
        success != null &&
        success.matchesLiveRelease(release);
  }

  StorefrontPublicationStatus withObservedAt(DateTime value) {
    return StorefrontPublicationStatus(
      availability: availability,
      dispatchEnabled: dispatchEnabled,
      desiredRevision: desiredRevision,
      lastPublishedRevision: lastPublishedRevision,
      requestState: requestState,
      requestId: requestId,
      lastPublishedRequestId: lastPublishedRequestId,
      canRetry: canRetry,
      statusMessage: statusMessage,
      targetKey: targetKey,
      expectedStoreOrigin: expectedStoreOrigin,
      expectedFirebaseOrigin: expectedFirebaseOrigin,
      lastOwnerChangeAt: lastOwnerChangeAt,
      lastPublishedAt: lastPublishedAt,
      lastDispatchTickAt: lastDispatchTickAt,
      lastDispatchErrorClass: lastDispatchErrorClass,
      lastDispatchErrorMessage: lastDispatchErrorMessage,
      queue: queue,
      active: active,
      lastSuccess: lastSuccess,
      latestFailure: latestFailure,
      observedAt: value.toUtc(),
    );
  }
}

class StorefrontPublicationRetryResult {
  const StorefrontPublicationRetryResult({
    required this.accepted,
    required this.enqueued,
    required this.reason,
    required this.message,
    required this.status,
  });

  final bool accepted;
  final bool enqueued;
  final String reason;
  final String message;
  final StorefrontPublicationStatus status;
}

T? _nested<T>(Object? raw, T Function(Object? raw) parse) {
  final json = _stringMap(raw);
  return json.isEmpty ? null : parse(json);
}

Map<String, dynamic> _stringMap(Object? raw) {
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  if (raw is List && raw.length == 1) return _stringMap(raw.single);
  return const {};
}

int _nonNegativeInt(Object? raw) {
  final value = raw is num ? raw.toInt() : int.tryParse(_text(raw));
  return value == null || value < 0 ? 0 : value;
}

String _text(Object? raw) => raw?.toString().trim() ?? '';

DateTime? _dateTime(Object? raw) {
  final value = _text(raw);
  return value.isEmpty ? null : DateTime.tryParse(value)?.toUtc();
}

bool _isUuid(String value) => RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value);

bool _isSha256(String value) =>
    RegExp(r'^[0-9a-f]{64}$', caseSensitive: false).hasMatch(value);

bool _sameDigest(String left, String right) =>
    left.toLowerCase() == right.toLowerCase();
