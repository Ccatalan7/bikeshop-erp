import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/current_user_profile.dart';
import '../../../shared/services/current_user_profile_service.dart';

enum SupplierCredentialKind {
  portalPassword,
  apiToken,
  other;

  static SupplierCredentialKind fromJson(dynamic value) {
    return switch (value?.toString()) {
      'portal_password' ||
      'portalPassword' =>
        SupplierCredentialKind.portalPassword,
      'api_token' || 'apiToken' => SupplierCredentialKind.apiToken,
      _ => SupplierCredentialKind.other,
    };
  }

  String get dbValue => switch (this) {
        SupplierCredentialKind.portalPassword => 'portal_password',
        SupplierCredentialKind.apiToken => 'api_token',
        SupplierCredentialKind.other => 'other',
      };
}

@immutable
class SupplierCredentialMetadata {
  const SupplierCredentialMetadata({
    required this.tenantId,
    required this.supplierId,
    required this.kind,
    required this.credentialKey,
    this.engagementId,
    this.originUrl,
    this.label,
    this.username,
    this.updatedAt,
    this.secretAvailable = true,
  });

  factory SupplierCredentialMetadata.fromJson(Map<String, dynamic> json) {
    final credentialKey =
        _optionalText(json['credential_key']) ?? defaultCredentialKey;
    _validateCredentialKey(credentialKey);
    final rawOrigin = _optionalText(json['origin_url']);
    return SupplierCredentialMetadata(
      tenantId: _requiredText(json, 'tenant_id'),
      supplierId: _requiredText(json, 'supplier_id'),
      kind: SupplierCredentialKind.fromJson(json['credential_kind']),
      credentialKey: credentialKey,
      engagementId: _optionalText(json['engagement_id']),
      originUrl: rawOrigin == null
          ? null
          : _requireCanonicalSupplierCredentialOrigin(rawOrigin),
      label: _optionalText(json['label']),
      username: _optionalText(json['username']),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      secretAvailable: _secretAvailableFromJson(json),
    );
  }

  final String tenantId;
  final String supplierId;
  final SupplierCredentialKind kind;
  final String credentialKey;
  final String? engagementId;
  final String? originUrl;
  final String? label;
  final String? username;
  final DateTime? updatedAt;
  final bool secretAvailable;

  @override
  String toString() =>
      'SupplierCredentialMetadata(supplierId: $supplierId, kind: ${kind.dbValue}, key: $credentialKey)';

  bool matchesHttpsOrigin(String value) {
    final expected = originUrl;
    if (expected == null) return false;
    return canonicalSupplierCredentialOrigin(value) == expected;
  }
}

const defaultCredentialKey = 'default';

/// Short-lived, on-demand credential returned by the protected RPC.
///
/// It is deliberately not serializable and its string representation never
/// includes the username or secret.
@immutable
class SupplierCredential {
  const SupplierCredential({
    required this.metadata,
    required this.secret,
  });

  factory SupplierCredential.fromJson(Map<String, dynamic> json) {
    final metadata = SupplierCredentialMetadata.fromJson(json);
    if (!metadata.secretAvailable) {
      throw const FormatException(
        'Credential response declared its secret unavailable',
      );
    }
    final secret = _requiredRawSecret(json, 'secret');
    return SupplierCredential(
      metadata: metadata,
      secret: secret,
    );
  }

  final SupplierCredentialMetadata metadata;
  final String secret;

  String? get username => metadata.username;

  @override
  String toString() =>
      'SupplierCredential(supplierId: ${metadata.supplierId}, kind: ${metadata.kind.dbValue}, redacted: true)';
}

@immutable
class SupplierCredentialInput {
  SupplierCredentialInput({
    required this.operationId,
    required this.supplierId,
    required this.kind,
    required this.credentialKey,
    required this.secret,
    this.expectedUpdatedAt,
    this.engagementId,
    String? originUrl,
    this.clearEngagement = false,
    this.clearOrigin = false,
    this.label,
    this.username,
  }) : originUrl = originUrl == null
            ? null
            : _requireCanonicalSupplierCredentialOrigin(originUrl) {
    _validateOperationId(operationId);
    if (supplierId.trim().isEmpty) {
      throw ArgumentError.value(supplierId, 'supplierId', 'Required');
    }
    if (secret.isEmpty) {
      throw ArgumentError.value('', 'secret', 'Required');
    }
    _validateCredentialKey(credentialKey);
    if (clearEngagement && engagementId != null) {
      throw ArgumentError.value(
        engagementId,
        'engagementId',
        'Cannot set and clear engagement together',
      );
    }
    if (clearOrigin && originUrl != null) {
      throw ArgumentError.value(
        originUrl,
        'originUrl',
        'Cannot set and clear origin together',
      );
    }
  }

  final String operationId;
  final String supplierId;
  final SupplierCredentialKind kind;
  final String credentialKey;
  final String secret;
  final DateTime? expectedUpdatedAt;
  final String? engagementId;
  final String? originUrl;
  final bool clearEngagement;
  final bool clearOrigin;
  final String? label;
  final String? username;
}

enum SupplierCredentialUpsertAction {
  create,
  rotate;

  static SupplierCredentialUpsertAction fromJson(dynamic value) {
    return switch (value?.toString()) {
      'create' => SupplierCredentialUpsertAction.create,
      'rotate' => SupplierCredentialUpsertAction.rotate,
      _ => throw const FormatException(
          'Invalid supplier credential upsert action',
        ),
    };
  }
}

/// Durable receipt for one credential create/rotation attempt.
///
/// [appliedCredential] is the metadata written by this operation. On an old
/// receipt replay, [currentCredential] may be newer or null if a later command
/// rotated/deleted the same key. Neither object contains the secret.
@immutable
class SupplierCredentialUpsertResult {
  const SupplierCredentialUpsertResult({
    required this.operationId,
    required this.action,
    required this.idempotentReplay,
    required this.appliedCredential,
    required this.currentCredential,
  });

  factory SupplierCredentialUpsertResult.fromJson(Map<String, dynamic> json) {
    final operationId = _requiredText(json, 'operation_id');
    _validateOperationId(operationId);
    if (json['credential_stored'] != true) {
      throw const FormatException('Credential upsert was not stored');
    }
    final applied = SupplierCredentialMetadata.fromJson(
      _requiredNestedMap(json, 'applied_credential'),
    );
    if (!applied.secretAvailable) {
      throw const FormatException(
        'Applied credential did not store a secret',
      );
    }
    final current = _optionalCredentialMetadata(json['current_credential']);
    _verifyReceiptScope(json, applied);
    if (current != null && !_sameCredentialScope(current, applied)) {
      throw const FormatException(
        'Current credential escaped the applied receipt scope',
      );
    }
    return SupplierCredentialUpsertResult(
      operationId: operationId,
      action: SupplierCredentialUpsertAction.fromJson(json['action']),
      idempotentReplay: json['idempotent_replay'] as bool? ?? false,
      appliedCredential: applied,
      currentCredential: current,
    );
  }

  final String operationId;
  final SupplierCredentialUpsertAction action;
  final bool idempotentReplay;
  final SupplierCredentialMetadata appliedCredential;
  final SupplierCredentialMetadata? currentCredential;

  @override
  String toString() =>
      'SupplierCredentialUpsertResult(operationId: $operationId, '
      'action: ${action.name}, replay: $idempotentReplay, redacted: true)';
}

@immutable
class SupplierCredentialTombstone {
  const SupplierCredentialTombstone({
    required this.credentialId,
    required this.tenantId,
    required this.supplierId,
    required this.kind,
    required this.credentialKey,
    required this.previousUpdatedAt,
    required this.deletedAt,
    this.engagementId,
    this.originUrl,
    this.label,
    this.username,
  });

  factory SupplierCredentialTombstone.fromJson(Map<String, dynamic> json) {
    final credentialKey = _requiredText(json, 'credential_key');
    _validateCredentialKey(credentialKey);
    final rawOrigin = _optionalText(json['origin_url']);
    return SupplierCredentialTombstone(
      credentialId: _requiredText(json, 'credential_id'),
      tenantId: _requiredText(json, 'tenant_id'),
      supplierId: _requiredText(json, 'supplier_id'),
      kind: SupplierCredentialKind.fromJson(json['credential_kind']),
      credentialKey: credentialKey,
      engagementId: _optionalText(json['engagement_id']),
      originUrl: rawOrigin == null
          ? null
          : _requireCanonicalSupplierCredentialOrigin(rawOrigin),
      label: _optionalText(json['label']),
      username: _optionalText(json['username']),
      previousUpdatedAt: _requiredDateTime(json, 'previous_updated_at'),
      deletedAt: _requiredDateTime(json, 'deleted_at'),
    );
  }

  final String credentialId;
  final String tenantId;
  final String supplierId;
  final SupplierCredentialKind kind;
  final String credentialKey;
  final String? engagementId;
  final String? originUrl;
  final String? label;
  final String? username;
  final DateTime previousUpdatedAt;
  final DateTime deletedAt;

  @override
  String toString() =>
      'SupplierCredentialTombstone(supplierId: $supplierId, key: '
      '$credentialKey, deletedAt: $deletedAt, redacted: true)';
}

/// Durable receipt for one version-checked credential deletion.
@immutable
class SupplierCredentialDeleteResult {
  const SupplierCredentialDeleteResult({
    required this.operationId,
    required this.idempotentReplay,
    required this.tombstone,
    required this.currentCredential,
  });

  factory SupplierCredentialDeleteResult.fromJson(Map<String, dynamic> json) {
    final operationId = _requiredText(json, 'operation_id');
    _validateOperationId(operationId);
    if (json['action']?.toString() != 'delete' || json['deleted'] != true) {
      throw const FormatException('Invalid supplier credential delete receipt');
    }
    final tombstone = SupplierCredentialTombstone.fromJson(
      _requiredNestedMap(json, 'tombstone'),
    );
    _verifyTombstoneReceiptScope(json, tombstone);
    final current = _optionalCredentialMetadata(json['current_credential']);
    if (current != null &&
        (current.tenantId != tombstone.tenantId ||
            current.supplierId != tombstone.supplierId ||
            current.kind != tombstone.kind ||
            current.credentialKey != tombstone.credentialKey)) {
      throw const FormatException(
        'Current credential escaped the delete receipt scope',
      );
    }
    return SupplierCredentialDeleteResult(
      operationId: operationId,
      idempotentReplay: json['idempotent_replay'] as bool? ?? false,
      tombstone: tombstone,
      currentCredential: current,
    );
  }

  final String operationId;
  final bool idempotentReplay;
  final SupplierCredentialTombstone tombstone;
  final SupplierCredentialMetadata? currentCredential;

  @override
  String toString() =>
      'SupplierCredentialDeleteResult(operationId: $operationId, '
      'replay: $idempotentReplay, redacted: true)';
}

@immutable
class SupplierCredentialStatus {
  SupplierCredentialStatus({
    required this.tenantId,
    required this.supplierId,
    required this.hasPortalCredential,
    List<SupplierCredentialMetadata> credentials = const [],
  }) : credentials = List.unmodifiable(credentials);

  factory SupplierCredentialStatus.fromJson(Map<String, dynamic> json) {
    final tenantId = _requiredText(json, 'tenant_id');
    final supplierId = _requiredText(json, 'supplier_id');
    final rawCredentials = json['credentials'];
    final credentials = rawCredentials is List
        ? rawCredentials.whereType<Map>().map((raw) {
            final item = Map<String, dynamic>.from(raw);
            item['tenant_id'] = tenantId;
            item['supplier_id'] = supplierId;
            return SupplierCredentialMetadata.fromJson(item);
          }).toList(growable: false)
        : const <SupplierCredentialMetadata>[];
    final identities = <String>{};
    for (final credential in credentials) {
      if (!identities.add(
        '${credential.kind.dbValue}|${credential.credentialKey}',
      )) {
        throw const FormatException('Duplicate supplier credential metadata');
      }
    }
    return SupplierCredentialStatus(
      tenantId: tenantId,
      supplierId: supplierId,
      hasPortalCredential: json['has_portal_credential'] as bool? ?? false,
      credentials: credentials,
    );
  }

  final String tenantId;
  final String supplierId;
  final bool hasPortalCredential;
  final List<SupplierCredentialMetadata> credentials;

  Iterable<SupplierCredentialMetadata> forHttpsOrigin(
    String origin, {
    SupplierCredentialKind? kind,
  }) {
    final canonical = canonicalSupplierCredentialOrigin(origin);
    if (canonical == null) return const [];
    return credentials.where(
      (credential) =>
          credential.originUrl == canonical &&
          (kind == null || credential.kind == kind),
    );
  }
}

enum SupplierCredentialOriginMatchStatus {
  noMatch,
  unique,
  ambiguous;

  static SupplierCredentialOriginMatchStatus fromJson(dynamic value) {
    return switch (value?.toString()) {
      'no_match' => SupplierCredentialOriginMatchStatus.noMatch,
      'unique' => SupplierCredentialOriginMatchStatus.unique,
      'ambiguous' => SupplierCredentialOriginMatchStatus.ambiguous,
      _ => throw const FormatException(
          'Invalid supplier credential origin match status',
        ),
    };
  }
}

/// Secret- and username-free discovery result for one exact HTTPS origin.
@immutable
class SupplierCredentialOriginLookup {
  SupplierCredentialOriginLookup({
    required this.tenantId,
    required this.canonicalOrigin,
    required this.requestedKind,
    required this.status,
    required this.matchCount,
    required List<SupplierCredentialMetadata> candidates,
    this.match,
  }) : candidates = List.unmodifiable(candidates);

  factory SupplierCredentialOriginLookup.fromJson(Map<String, dynamic> json) {
    final tenantId = _requiredText(json, 'tenant_id');
    final rawOrigin = _requiredText(json, 'canonical_origin').toLowerCase();
    final canonicalOrigin = canonicalSupplierCredentialOrigin(rawOrigin);
    if (canonicalOrigin == null || canonicalOrigin != rawOrigin) {
      throw const FormatException(
        'Credential discovery returned a non-canonical origin',
      );
    }
    final rawKind = _optionalText(json['credential_kind']);
    final requestedKind =
        rawKind == null ? null : SupplierCredentialKind.fromJson(rawKind);
    final rawCandidates = json['candidates'];
    if (rawCandidates is! List) {
      throw const FormatException(
        'Credential discovery candidates must be an array',
      );
    }
    SupplierCredentialMetadata parseCandidate(dynamic raw) {
      if (raw is! Map) {
        throw const FormatException(
          'Credential discovery candidate must be an object',
        );
      }
      final row = Map<String, dynamic>.from(raw)..['tenant_id'] = tenantId;
      final candidate = SupplierCredentialMetadata.fromJson(row);
      if (candidate.originUrl != canonicalOrigin ||
          (requestedKind != null && candidate.kind != requestedKind)) {
        throw const FormatException(
          'Credential discovery candidate escaped its origin scope',
        );
      }
      return candidate;
    }

    final candidates =
        rawCandidates.map(parseCandidate).toList(growable: false);
    final matchCount = _requiredNonNegativeInt(json, 'match_count');
    if (matchCount != candidates.length) {
      throw const FormatException(
        'Credential discovery count does not match its candidates',
      );
    }
    final status = SupplierCredentialOriginMatchStatus.fromJson(
      json['match_status'],
    );
    final rawMatch = json['match'];
    final match = rawMatch == null ? null : parseCandidate(rawMatch);
    final validShape = switch (status) {
      SupplierCredentialOriginMatchStatus.noMatch =>
        matchCount == 0 && match == null,
      SupplierCredentialOriginMatchStatus.unique => matchCount == 1 &&
          match != null &&
          _sameCredentialBinding(match, candidates.single),
      SupplierCredentialOriginMatchStatus.ambiguous =>
        matchCount > 1 && match == null,
    };
    if (!validShape) {
      throw const FormatException('Invalid credential discovery result shape');
    }
    final identities = <String>{};
    for (final candidate in candidates) {
      if (!identities.add(
        '${candidate.supplierId}|${candidate.kind.dbValue}|'
        '${candidate.credentialKey}',
      )) {
        throw const FormatException(
          'Duplicate credential discovery candidate',
        );
      }
    }
    return SupplierCredentialOriginLookup(
      tenantId: tenantId,
      canonicalOrigin: canonicalOrigin,
      requestedKind: requestedKind,
      status: status,
      matchCount: matchCount,
      match: match,
      candidates: candidates,
    );
  }

  final String tenantId;
  final String canonicalOrigin;
  final SupplierCredentialKind? requestedKind;
  final SupplierCredentialOriginMatchStatus status;
  final int matchCount;
  final SupplierCredentialMetadata? match;
  final List<SupplierCredentialMetadata> candidates;

  bool get isUnique =>
      status == SupplierCredentialOriginMatchStatus.unique && match != null;

  @override
  String toString() =>
      'SupplierCredentialOriginLookup(origin: $canonicalOrigin, status: ${status.name}, count: $matchCount)';
}

/// A credential revealed only after exact-origin discovery and a second
/// post-reveal binding check. Diagnostics remain redacted by both nested DTOs.
@immutable
class SupplierCredentialOriginResolution {
  const SupplierCredentialOriginResolution({
    required this.lookup,
    required this.credential,
  });

  final SupplierCredentialOriginLookup lookup;
  final SupplierCredential credential;

  @override
  String toString() =>
      'SupplierCredentialOriginResolution(origin: ${lookup.canonicalOrigin}, redacted: true)';
}

class SupplierCredentialAccessDenied implements Exception {
  const SupplierCredentialAccessDenied();

  @override
  String toString() => 'Supplier credential access is not authorized';
}

abstract interface class SupplierCredentialGateway {
  Future<dynamic> rpc(
    String functionName, {
    required Map<String, dynamic> params,
  });
}

class SupabaseSupplierCredentialGateway implements SupplierCredentialGateway {
  SupabaseSupplierCredentialGateway([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<dynamic> rpc(
    String functionName, {
    required Map<String, dynamic> params,
  }) {
    return _client.rpc(functionName, params: params);
  }
}

/// The only Flutter boundary allowed to request supplier credentials.
///
/// Values are fetched on demand and never cached. The local profile capability
/// prevents accidental calls; the RPC independently enforces the same tenant
/// authority and remains the security owner.
class SupplierCredentialService {
  SupplierCredentialService({
    required CurrentUserProfileService profileService,
    SupabaseClient? client,
    SupplierCredentialGateway? gateway,
    String? Function()? currentAuthUserId,
    Stream<Object?>? authorityEvents,
  })  : _profileService = profileService,
        assert(client == null || gateway == null),
        _gateway = gateway ?? SupabaseSupplierCredentialGateway(client),
        _currentAuthUserId = currentAuthUserId ??
            (() => (client ?? Supabase.instance.client).auth.currentUser?.id),
        _authorityEvents = authorityEvents ??
            (gateway == null
                ? (client ?? Supabase.instance.client).auth.onAuthStateChange
                : null);

  final CurrentUserProfileService _profileService;
  final SupplierCredentialGateway _gateway;
  final String? Function() _currentAuthUserId;
  final Stream<Object?>? _authorityEvents;

  String? get currentAuthUserId => _currentAuthUserId();

  Stream<Object?>? get authorityEvents => _authorityEvents;

  /// Secret-free metadata inventory. It still requires the dedicated
  /// credential-manager authority because usernames and portal origins are
  /// operationally sensitive.
  Future<SupplierCredentialStatus> getStatus({
    required String supplierId,
  }) async {
    _requireText(supplierId, 'supplierId');
    final lease = _captureAuthority(requireManagement: true);
    final response = await _gateway.rpc(
      'get_supplier_credential_status',
      params: {
        'p_tenant_id': lease.tenantId,
        'p_supplier_id': supplierId,
      },
    );
    _verifyAuthority(lease);
    final status = SupplierCredentialStatus.fromJson(
      _responseMap(response, 'get_supplier_credential_status'),
    );
    if (status.tenantId != lease.tenantId || status.supplierId != supplierId) {
      throw const FormatException(
        'Supplier credential status escaped its requested scope',
      );
    }
    for (final credential in status.credentials) {
      _verifyScope(
        credential,
        tenantId: lease.tenantId,
        supplierId: supplierId,
        kind: credential.kind,
        credentialKey: credential.credentialKey,
      );
    }
    return status;
  }

  Future<SupplierCredential?> get({
    required String supplierId,
    required SupplierCredentialKind kind,
    required String credentialKey,
  }) async {
    _requireText(supplierId, 'supplierId');
    _validateCredentialKey(credentialKey);
    final lease = _captureAuthority(requireManagement: true);
    return _getWithLease(
      lease,
      supplierId: supplierId,
      kind: kind,
      credentialKey: credentialKey,
    );
  }

  /// Finds credential metadata by an exact HTTPS origin without reading a
  /// supplier website or revealing a username/secret.
  Future<SupplierCredentialOriginLookup> findForOrigin({
    required String origin,
    SupplierCredentialKind? kind,
  }) async {
    final canonicalOrigin = _requireCanonicalSupplierCredentialOrigin(origin);
    final lease = _captureAuthority(requireManagement: true);
    return _findForOriginWithLease(
      lease,
      canonicalOrigin: canonicalOrigin,
      kind: kind,
    );
  }

  /// Resolves and reveals exactly one portal credential bound to [origin].
  ///
  /// Discovery is repeated after the reveal. A concurrent change that makes
  /// the origin ambiguous or moves the selected key fails closed before the
  /// secret leaves this service boundary.
  Future<SupplierCredentialOriginResolution?> revealPortalCredentialForOrigin(
      {required String origin}) async {
    final canonicalOrigin = _requireCanonicalSupplierCredentialOrigin(origin);
    final lease = _captureAuthority(requireManagement: true);
    final initial = await _findForOriginWithLease(
      lease,
      canonicalOrigin: canonicalOrigin,
      kind: SupplierCredentialKind.portalPassword,
    );
    final selected = initial.match;
    if (!initial.isUnique || selected == null) return null;
    if (!selected.secretAvailable) return null;
    final credential = await _getWithLease(
      lease,
      supplierId: selected.supplierId,
      kind: selected.kind,
      credentialKey: selected.credentialKey,
    );
    if (credential == null ||
        !_sameCredentialBinding(credential.metadata, selected) ||
        credential.metadata.originUrl != canonicalOrigin) {
      return null;
    }
    final confirmed = await _findForOriginWithLease(
      lease,
      canonicalOrigin: canonicalOrigin,
      kind: SupplierCredentialKind.portalPassword,
    );
    final confirmedMatch = confirmed.match;
    if (!confirmed.isUnique ||
        confirmedMatch == null ||
        !_sameCredentialBinding(confirmedMatch, credential.metadata)) {
      return null;
    }
    return SupplierCredentialOriginResolution(
      lookup: confirmed,
      credential: credential,
    );
  }

  Future<SupplierCredential?> _getWithLease(
    _SupplierCredentialAuthorityLease lease, {
    required String supplierId,
    required SupplierCredentialKind kind,
    required String credentialKey,
  }) async {
    try {
      final response = await _gateway.rpc(
        'get_supplier_credential_v2',
        params: {
          'p_tenant_id': lease.tenantId,
          'p_supplier_id': supplierId,
          'p_credential_kind': kind.dbValue,
          'p_credential_key': credentialKey,
        },
      );
      _verifyAuthority(lease);
      if (response == null) return null;
      final credential = SupplierCredential.fromJson(
        _responseMap(response, 'get_supplier_credential_v2'),
      );
      _verifyScope(
        credential.metadata,
        tenantId: lease.tenantId,
        supplierId: supplierId,
        kind: kind,
        credentialKey: credentialKey,
      );
      return credential;
    } on PostgrestException catch (error) {
      if (error.code == 'P0002') {
        _verifyAuthority(lease);
        return null;
      }
      rethrow;
    }
  }

  Future<SupplierCredentialOriginLookup> _findForOriginWithLease(
    _SupplierCredentialAuthorityLease lease, {
    required String canonicalOrigin,
    required SupplierCredentialKind? kind,
  }) async {
    final response = await _gateway.rpc(
      'find_supplier_credential_for_origin',
      params: {
        'p_tenant_id': lease.tenantId,
        'p_origin_url': canonicalOrigin,
        'p_credential_kind': kind?.dbValue,
      },
    );
    _verifyAuthority(lease);
    final lookup = SupplierCredentialOriginLookup.fromJson(
      _responseMap(response, 'find_supplier_credential_for_origin'),
    );
    if (lookup.tenantId != lease.tenantId ||
        lookup.canonicalOrigin != canonicalOrigin ||
        lookup.requestedKind != kind) {
      throw const FormatException(
        'Credential discovery escaped its requested scope',
      );
    }
    return lookup;
  }

  Future<SupplierCredentialUpsertResult> upsert(
    SupplierCredentialInput input,
  ) async {
    final lease = _captureAuthority(requireManagement: true);
    final response = await _gateway.rpc(
      'upsert_supplier_credential_v2',
      params: {
        'p_tenant_id': lease.tenantId,
        'p_supplier_id': input.supplierId,
        'p_credential_kind': input.kind.dbValue,
        'p_credential_key': input.credentialKey,
        'p_operation_id': input.operationId,
        'p_expected_updated_at':
            input.expectedUpdatedAt?.toUtc().toIso8601String(),
        'p_engagement_id': input.engagementId,
        'p_origin_url': input.originUrl,
        'p_label': _optionalText(input.label),
        'p_username': _optionalText(input.username),
        'p_secret': input.secret,
        'p_clear_engagement': input.clearEngagement,
        'p_clear_origin': input.clearOrigin,
      },
    );
    _verifyAuthority(lease);
    final result = SupplierCredentialUpsertResult.fromJson(
      _responseMap(response, 'upsert_supplier_credential_v2'),
    );
    if (result.operationId != input.operationId) {
      throw const FormatException(
        'Credential receipt operation id escaped its request',
      );
    }
    _verifyScope(
      result.appliedCredential,
      tenantId: lease.tenantId,
      supplierId: input.supplierId,
      kind: input.kind,
      credentialKey: input.credentialKey,
    );
    final current = result.currentCredential;
    if (current != null) {
      _verifyScope(
        current,
        tenantId: lease.tenantId,
        supplierId: input.supplierId,
        kind: input.kind,
        credentialKey: input.credentialKey,
      );
    }
    return result;
  }

  Future<SupplierCredentialDeleteResult> delete({
    required String supplierId,
    required SupplierCredentialKind kind,
    required String credentialKey,
    required String operationId,
    required DateTime expectedUpdatedAt,
  }) async {
    _requireText(supplierId, 'supplierId');
    _validateCredentialKey(credentialKey);
    _validateOperationId(operationId);
    final lease = _captureAuthority(requireManagement: true);
    final response = await _gateway.rpc(
      'delete_supplier_credential_v2',
      params: {
        'p_tenant_id': lease.tenantId,
        'p_supplier_id': supplierId,
        'p_credential_kind': kind.dbValue,
        'p_credential_key': credentialKey,
        'p_operation_id': operationId,
        'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String(),
      },
    );
    _verifyAuthority(lease);
    final result = SupplierCredentialDeleteResult.fromJson(
      _responseMap(response, 'delete_supplier_credential_v2'),
    );
    if (result.operationId != operationId ||
        result.tombstone.tenantId != lease.tenantId ||
        result.tombstone.supplierId != supplierId ||
        result.tombstone.kind != kind ||
        result.tombstone.credentialKey != credentialKey) {
      throw const FormatException('Credential delete receipt escaped scope');
    }
    final current = result.currentCredential;
    if (current != null) {
      _verifyScope(
        current,
        tenantId: lease.tenantId,
        supplierId: supplierId,
        kind: kind,
        credentialKey: credentialKey,
      );
    }
    return result;
  }

  _SupplierCredentialAuthorityLease _captureAuthority({
    required bool requireManagement,
  }) {
    final profile = _profileService.profile;
    if (profile == null ||
        _currentAuthUserId() != profile.userId ||
        (requireManagement && !profile.canManageSupplierCredentials)) {
      throw const SupplierCredentialAccessDenied();
    }
    return _SupplierCredentialAuthorityLease(
      profile: profile,
      userId: profile.userId,
      tenantId: profile.tenantId,
      requireManagement: requireManagement,
    );
  }

  void _verifyAuthority(_SupplierCredentialAuthorityLease lease) {
    final current = _profileService.profile;
    if (_currentAuthUserId() != lease.userId ||
        !identical(current, lease.profile) ||
        current?.userId != lease.userId ||
        current?.tenantId != lease.tenantId ||
        (lease.requireManagement &&
            current?.canManageSupplierCredentials != true)) {
      throw const SupplierCredentialAccessDenied();
    }
  }

  void _verifyScope(
    SupplierCredentialMetadata metadata, {
    required String tenantId,
    required String supplierId,
    required SupplierCredentialKind kind,
    required String credentialKey,
  }) {
    if (metadata.tenantId != tenantId ||
        metadata.supplierId != supplierId ||
        metadata.kind != kind ||
        metadata.credentialKey != credentialKey) {
      throw const FormatException(
        'Supplier credential response escaped its requested scope',
      );
    }
  }
}

class _SupplierCredentialAuthorityLease {
  const _SupplierCredentialAuthorityLease({
    required this.profile,
    required this.userId,
    required this.tenantId,
    required this.requireManagement,
  });

  final CurrentUserProfile profile;
  final String userId;
  final String tenantId;
  final bool requireManagement;
}

Map<String, dynamic> _responseMap(dynamic response, String operation) {
  if (response is! Map) {
    throw FormatException('Invalid $operation response');
  }
  return Map<String, dynamic>.from(response);
}

Map<String, dynamic> _requiredNestedMap(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value is! Map) throw FormatException('Missing $key');
  return Map<String, dynamic>.from(value);
}

SupplierCredentialMetadata? _optionalCredentialMetadata(dynamic value) {
  if (value == null) return null;
  if (value is! Map) {
    throw const FormatException('Invalid current credential metadata');
  }
  return SupplierCredentialMetadata.fromJson(
    Map<String, dynamic>.from(value),
  );
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = DateTime.tryParse(json[key]?.toString() ?? '');
  if (value == null) throw FormatException('Missing $key');
  return value.toUtc();
}

void _verifyReceiptScope(
  Map<String, dynamic> receipt,
  SupplierCredentialMetadata metadata,
) {
  if (receipt['tenant_id']?.toString() != metadata.tenantId ||
      receipt['supplier_id']?.toString() != metadata.supplierId ||
      receipt['credential_kind']?.toString() != metadata.kind.dbValue ||
      receipt['credential_key']?.toString() != metadata.credentialKey) {
    throw const FormatException(
      'Applied credential escaped the receipt scope',
    );
  }
}

void _verifyTombstoneReceiptScope(
  Map<String, dynamic> receipt,
  SupplierCredentialTombstone tombstone,
) {
  if (receipt['tenant_id']?.toString() != tombstone.tenantId ||
      receipt['supplier_id']?.toString() != tombstone.supplierId ||
      receipt['credential_kind']?.toString() != tombstone.kind.dbValue ||
      receipt['credential_key']?.toString() != tombstone.credentialKey) {
    throw const FormatException('Tombstone escaped the receipt scope');
  }
}

bool _sameCredentialScope(
  SupplierCredentialMetadata left,
  SupplierCredentialMetadata right,
) {
  return left.tenantId == right.tenantId &&
      left.supplierId == right.supplierId &&
      left.kind == right.kind &&
      left.credentialKey == right.credentialKey;
}

String _requiredText(Map<String, dynamic> json, String key) {
  final value = _optionalText(json[key]);
  if (value == null) throw FormatException('Missing $key');
  return value;
}

String _requiredRawSecret(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Missing $key');
  }
  return value;
}

int _requiredNonNegativeInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
  if (parsed == null || parsed < 0) {
    throw FormatException('Invalid $key');
  }
  return parsed;
}

bool _sameCredentialBinding(
  SupplierCredentialMetadata left,
  SupplierCredentialMetadata right,
) {
  final leftVersion = left.updatedAt?.toUtc();
  final rightVersion = right.updatedAt?.toUtc();
  return left.tenantId == right.tenantId &&
      left.supplierId == right.supplierId &&
      left.kind == right.kind &&
      left.credentialKey == right.credentialKey &&
      left.engagementId == right.engagementId &&
      left.originUrl == right.originUrl &&
      left.secretAvailable == right.secretAvailable &&
      leftVersion != null &&
      rightVersion != null &&
      leftVersion.isAtSameMomentAs(rightVersion);
}

String? _optionalText(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _secretAvailableFromJson(Map<String, dynamic> json) {
  final hasCanonical = json.containsKey('has_secret');
  final hasAlias = json.containsKey('secret_available');
  final canonical =
      hasCanonical ? _requiredBool(json['has_secret'], 'has_secret') : null;
  final alias = hasAlias
      ? _requiredBool(json['secret_available'], 'secret_available')
      : null;
  if (canonical != null && alias != null && canonical != alias) {
    throw const FormatException(
      'Conflicting supplier credential secret availability',
    );
  }
  return canonical ?? alias ?? true;
}

bool _requiredBool(dynamic value, String key) {
  if (value is! bool) throw FormatException('Invalid $key');
  return value;
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Required');
  }
}

void _validateCredentialKey(String value) {
  if (!RegExp(r'^[a-z][a-z0-9_.-]*$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'credentialKey',
      'Use a lowercase stable key',
    );
  }
}

void _validateOperationId(String value) {
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)) {
    throw ArgumentError.value(value, 'operationId', 'Use a UUID');
  }
}

/// Returns the exact HTTPS origin representation accepted by the database.
/// Paths, userinfo, query strings, fragments, and non-HTTPS schemes fail
/// closed. Port 443 is normalized away.
String? canonicalSupplierCredentialOrigin(String value) {
  final normalized = value.trim().toLowerCase();
  final match = RegExp(
    r'^https://(\[[0-9a-f:.]+\]|[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?)(?::([0-9]{1,5}))?$',
  ).firstMatch(normalized);
  if (match == null) return null;
  final host = match.group(1)!;
  if (host.contains('..')) return null;
  final rawPort = match.group(2);
  final port = rawPort == null ? null : int.tryParse(rawPort);
  if (rawPort != null && (port == null || port < 1 || port > 65535)) {
    return null;
  }
  return 'https://$host${port == null || port == 443 ? '' : ':$port'}';
}

String _requireCanonicalSupplierCredentialOrigin(String value) {
  final origin = canonicalSupplierCredentialOrigin(value);
  if (origin == null) {
    throw ArgumentError.value(
      value,
      'originUrl',
      'Use an exact HTTPS origin without path, query, fragment, or userinfo',
    );
  }
  return origin;
}
