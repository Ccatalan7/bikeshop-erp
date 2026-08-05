import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Risk assigned by the runtime to an assistant tool.
///
/// A model may choose a tool, but it cannot change this value or downgrade the
/// approval rules attached to it.
enum AIToolRiskLevel {
  read,
  draft,
  reversibleWrite,
  sensitiveWrite,
  publicResearch,
  authenticatedBrowser,
}

/// Whether retries of a tool call need a stable operation key.
enum AIToolIdempotencyPolicy {
  notApplicable,
  optional,
  required,
}

/// Runtime-owned capabilities derived from the authenticated ERP profile.
///
/// These are discovery gates, not substitutes for RLS. The domain reader must
/// still verify every returned row against the turn tenant.
abstract final class AIToolPermission {
  static const String operationalRead = 'ai.read.operational';
  static const String salesRead = 'ai.read.sales';
  static const String purchasesRead = 'ai.read.purchases';
}

/// Terminal state recorded for one attempted tool execution.
enum AIToolReceiptStatus {
  succeeded,
  rejected,
  timedOut,
  failed,
}

/// Closed failure vocabulary exposed beyond the tool runtime.
///
/// Executor exceptions and policy explanations never become user-facing
/// strings. Callers receive one of these codes and its fixed copy instead.
enum AIToolFailureCode {
  duplicateTool,
  unknownTool,
  unauthorized,
  invalidArguments,
  approvalRequired,
  idempotencyKeyRequired,
  concurrentExecutionDenied,
  turnLimitExceeded,
  timeout,
  oversizedOutput,
  invalidOutput,
  readBackRequired,
  executionFailed,
}

extension AIToolFailureCopy on AIToolFailureCode {
  String get publicMessage => switch (this) {
        AIToolFailureCode.duplicateTool =>
          'La herramienta está registrada más de una vez.',
        AIToolFailureCode.unknownTool =>
          'La herramienta solicitada no está disponible.',
        AIToolFailureCode.unauthorized =>
          'No tienes autorización para usar esta herramienta.',
        AIToolFailureCode.invalidArguments =>
          'Los argumentos de la herramienta no cumplen el contrato.',
        AIToolFailureCode.approvalRequired =>
          'Esta operación necesita una aprobación válida.',
        AIToolFailureCode.idempotencyKeyRequired =>
          'Esta operación necesita una clave de idempotencia.',
        AIToolFailureCode.concurrentExecutionDenied =>
          'La herramienta ya tiene una ejecución en curso.',
        AIToolFailureCode.turnLimitExceeded =>
          'El turno alcanzó su límite seguro de herramientas.',
        AIToolFailureCode.timeout =>
          'La herramienta excedió el tiempo permitido.',
        AIToolFailureCode.oversizedOutput =>
          'La herramienta devolvió más información de la permitida.',
        AIToolFailureCode.invalidOutput =>
          'La herramienta devolvió un resultado no válido.',
        AIToolFailureCode.readBackRequired =>
          'La operación no pudo verificar su resultado.',
        AIToolFailureCode.executionFailed =>
          'La herramienta no pudo completar la operación.',
      };
}

/// Tenant-bound authority captured at the beginning of an assistant run.
class AIToolAuthority {
  factory AIToolAuthority({
    required String userId,
    required String tenantId,
    required String role,
    required Set<String> permissions,
  }) {
    return AIToolAuthority._(
      userId: _requiredValue(userId, 'userId'),
      tenantId: _requiredValue(tenantId, 'tenantId'),
      role: _requiredValue(role, 'role'),
      permissions: Set<String>.unmodifiable(
        permissions.map((permission) => permission.trim()).where(
              (permission) => permission.isNotEmpty,
            ),
      ),
    );
  }

  const AIToolAuthority._({
    required this.userId,
    required this.tenantId,
    required this.role,
    required this.permissions,
  });

  final String userId;
  final String tenantId;
  final String role;
  final Set<String> permissions;

  bool hasEveryPermission(Iterable<String> requiredPermissions) =>
      requiredPermissions.every(permissions.contains);

  /// Stable pseudonymous scope identity for receipts.
  ///
  /// Raw user and tenant values never cross the receipt or audit serialization
  /// boundary. Role and permissions are deliberately excluded so an actor's
  /// receipts remain groupable after a legitimate capability change.
  String get auditScopeHash {
    final canonical = jsonEncode(<String, String>{
      'tenantId': tenantId,
      'userId': userId,
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}

/// A JSON Schema whose root is a closed object.
///
/// Every object node must explicitly set `additionalProperties: false`. This
/// keeps both the schema announced to the model and the arguments accepted by
/// the runtime closed by construction.
class AIToolInputSchema {
  factory AIToolInputSchema.closedObject({
    Map<String, Object?> properties = const <String, Object?>{},
    List<String> required = const <String>[],
  }) {
    return AIToolInputSchema.fromJson(<String, Object?>{
      'type': 'object',
      'properties': properties,
      'required': required,
      'additionalProperties': false,
    });
  }

  factory AIToolInputSchema.fromJson(Map<String, Object?> schema) {
    final frozen = _freezeJsonMap(schema);
    if (frozen['type'] != 'object' || frozen['additionalProperties'] != false) {
      throw ArgumentError(
        'Tool input schema must be a closed object.',
        'schema',
      );
    }
    _verifyClosedObjectSchemas(frozen, path: r'$');
    _verifyRequiredProperties(frozen, path: r'$');
    _verifyTypedSchemaNodes(frozen, path: r'$');
    return AIToolInputSchema._(frozen);
  }

  const AIToolInputSchema._(this._json);

  final Map<String, Object?> _json;

  Map<String, Object?> get json => _json;

  bool accepts(Map<String, Object?> arguments) =>
      _isJsonCompatible(arguments) && _matchesSchema(_json, arguments);
}

/// Definition owned by the runtime, never by the model.
class AIToolDefinition {
  factory AIToolDefinition({
    required String name,
    required String version,
    required String description,
    required AIToolInputSchema inputSchema,
    required Set<String> requiredPermissions,
    required AIToolRiskLevel risk,
    required bool requiresApproval,
    required Duration timeout,
    required int maxResults,
    required int maxOutputBytes,
    required bool allowsParallelExecution,
    required AIToolIdempotencyPolicy idempotency,
    bool requiresReadBack = false,
  }) {
    final normalizedName = name.trim();
    if (!_toolNamePattern.hasMatch(normalizedName)) {
      throw ArgumentError.value(
        name,
        'name',
        'Use a stable lower_snake_case tool name.',
      );
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
    if (maxResults <= 0) {
      throw ArgumentError.value(maxResults, 'maxResults', 'Must be positive.');
    }
    if (maxOutputBytes <= 0) {
      throw ArgumentError.value(
        maxOutputBytes,
        'maxOutputBytes',
        'Must be positive.',
      );
    }
    if (requiredPermissions.any((permission) => permission.trim().isEmpty)) {
      throw ArgumentError(
        'Required permissions must not contain empty values.',
        'requiredPermissions',
      );
    }

    final isWrite = risk == AIToolRiskLevel.reversibleWrite ||
        risk == AIToolRiskLevel.sensitiveWrite;
    if (isWrite && !requiresApproval) {
      throw ArgumentError(
        'Write tools must require approval.',
        'requiresApproval',
      );
    }
    if (isWrite && idempotency != AIToolIdempotencyPolicy.required) {
      throw ArgumentError(
        'Write tools must require idempotency.',
        'idempotency',
      );
    }
    if (isWrite && requiredPermissions.isEmpty) {
      throw ArgumentError(
        'Write tools must require an explicit ERP permission.',
        'requiredPermissions',
      );
    }
    if (isWrite && !requiresReadBack) {
      throw ArgumentError(
        'Write tools must require a canonical read-back.',
        'requiresReadBack',
      );
    }

    return AIToolDefinition._(
      name: normalizedName,
      version: _requiredValue(version, 'version'),
      description: _requiredValue(description, 'description'),
      inputSchema: inputSchema,
      requiredPermissions: Set<String>.unmodifiable(
        requiredPermissions.map((permission) => permission.trim()).where(
              (permission) => permission.isNotEmpty,
            ),
      ),
      risk: risk,
      requiresApproval: requiresApproval,
      timeout: timeout,
      maxResults: maxResults,
      maxOutputBytes: maxOutputBytes,
      allowsParallelExecution: allowsParallelExecution,
      idempotency: idempotency,
      requiresReadBack: requiresReadBack,
    );
  }

  const AIToolDefinition._({
    required this.name,
    required this.version,
    required this.description,
    required this.inputSchema,
    required this.requiredPermissions,
    required this.risk,
    required this.requiresApproval,
    required this.timeout,
    required this.maxResults,
    required this.maxOutputBytes,
    required this.allowsParallelExecution,
    required this.idempotency,
    required this.requiresReadBack,
  });

  final String name;
  final String version;
  final String description;
  final AIToolInputSchema inputSchema;
  final Set<String> requiredPermissions;
  final AIToolRiskLevel risk;
  final bool requiresApproval;
  final Duration timeout;
  final int maxResults;
  final int maxOutputBytes;
  final bool allowsParallelExecution;
  final AIToolIdempotencyPolicy idempotency;
  final bool requiresReadBack;

  /// Safe subset that can be announced to a model after policy filtering.
  AIToolAdvertisement get advertisement => AIToolAdvertisement._(
        name: name,
        version: version,
        description: description,
        inputSchema: inputSchema.json,
      );
}

/// Model-visible declaration. It deliberately carries no executor or policy.
class AIToolAdvertisement {
  const AIToolAdvertisement._({
    required this.name,
    required this.version,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String version;
  final String description;
  final Map<String, Object?> inputSchema;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'version': version,
        'description': description,
        'inputSchema': inputSchema,
      };
}

/// Approval issued outside the model and bound to one authority and tool.
class AIToolApproval {
  factory AIToolApproval({
    required String approvalId,
    required String toolName,
    required String toolVersion,
    required String userId,
    required String tenantId,
    required Map<String, Object?> arguments,
    required String? idempotencyKey,
    required DateTime expiresAt,
  }) {
    final normalizedIdempotencyKey = idempotencyKey?.trim();
    return AIToolApproval._(
      approvalId: _requiredValue(approvalId, 'approvalId'),
      toolName: _requiredValue(toolName, 'toolName'),
      toolVersion: _requiredValue(toolVersion, 'toolVersion'),
      userId: _requiredValue(userId, 'userId'),
      tenantId: _requiredValue(tenantId, 'tenantId'),
      argumentsHash: _sha256OfCanonicalJson(arguments),
      idempotencyKeyHash: normalizedIdempotencyKey == null ||
              normalizedIdempotencyKey.isEmpty
          ? null
          : sha256.convert(utf8.encode(normalizedIdempotencyKey)).toString(),
      expiresAt: expiresAt.toUtc(),
    );
  }

  const AIToolApproval._({
    required this.approvalId,
    required this.toolName,
    required this.toolVersion,
    required this.userId,
    required this.tenantId,
    required this.argumentsHash,
    required this.idempotencyKeyHash,
    required this.expiresAt,
  });

  final String approvalId;
  final String toolName;
  final String toolVersion;
  final String userId;
  final String tenantId;
  final String argumentsHash;
  final String? idempotencyKeyHash;
  final DateTime expiresAt;

  bool authorizes({
    required AIToolDefinition definition,
    required AIToolAuthority authority,
    required Map<String, Object?> arguments,
    required String? idempotencyKey,
    required DateTime now,
  }) {
    final normalizedIdempotencyKey = idempotencyKey?.trim();
    final actualIdempotencyKeyHash =
        normalizedIdempotencyKey == null || normalizedIdempotencyKey.isEmpty
            ? null
            : sha256.convert(utf8.encode(normalizedIdempotencyKey)).toString();
    return toolName == definition.name &&
        toolVersion == definition.version &&
        userId == authority.userId &&
        tenantId == authority.tenantId &&
        argumentsHash == _sha256OfCanonicalJson(arguments) &&
        idempotencyKeyHash == actualIdempotencyKeyHash &&
        expiresAt.isAfter(now.toUtc());
  }
}

/// Immutable input passed to a canonical tool executor.
class AIToolExecutionContext {
  AIToolExecutionContext({
    required this.definition,
    required this.authority,
    required Map<String, Object?> arguments,
    required this.idempotencyKey,
  }) : arguments = _freezeJsonMap(arguments);

  final AIToolDefinition definition;
  final AIToolAuthority authority;
  final Map<String, Object?> arguments;
  final String? idempotencyKey;
}

/// Typed output returned by an executor before runtime limit checks.
class AIToolExecutorResult {
  AIToolExecutorResult({
    required Map<String, Object?> data,
    required this.resultCount,
    this.readBackVerified = false,
  }) : data = _freezeJsonMap(data);

  final Map<String, Object?> data;
  final int resultCount;
  final bool readBackVerified;
}

typedef AIToolExecutor = Future<AIToolExecutorResult> Function(
  AIToolExecutionContext context,
);

/// Executor signal for a result that violates its trusted output contract.
/// Details are deliberately absent from the public failure path.
class AIToolExecutorOutputException implements Exception {
  const AIToolExecutorOutputException();
}

/// Secret-free evidence for one attempt.
///
/// Inputs, outputs, approval IDs, idempotency keys and executor exception text
/// are intentionally absent. Durable storage may add hashes later without
/// widening this client-side contract.
class AIToolReceipt {
  const AIToolReceipt({
    required this.toolName,
    required this.toolVersion,
    required this.risk,
    required this.authorityScopeHash,
    required this.status,
    required this.startedAt,
    required this.completedAt,
    required this.resultCount,
    required this.approvalUsed,
    required this.idempotencyUsed,
    required this.readBackVerified,
    required this.failureCode,
  });

  final String toolName;
  final String? toolVersion;
  final AIToolRiskLevel? risk;
  final String authorityScopeHash;
  final AIToolReceiptStatus status;
  final DateTime startedAt;
  final DateTime completedAt;
  final int resultCount;
  final bool approvalUsed;
  final bool idempotencyUsed;
  final bool readBackVerified;
  final AIToolFailureCode? failureCode;

  Duration get duration => completedAt.difference(startedAt);

  String? get publicMessage => failureCode?.publicMessage;

  Map<String, Object?> toAuditJson() => <String, Object?>{
        'toolName': toolName,
        if (toolVersion != null) 'toolVersion': toolVersion,
        if (risk != null) 'risk': risk!.name,
        'authorityScopeHash': authorityScopeHash,
        'status': status.name,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'completedAt': completedAt.toUtc().toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'resultCount': resultCount,
        'approvalUsed': approvalUsed,
        'idempotencyUsed': idempotencyUsed,
        'readBackVerified': readBackVerified,
        if (failureCode != null) 'failureCode': failureCode!.name,
      };
}

/// Successful output paired with its audit receipt.
class AIToolExecution {
  AIToolExecution({
    required Map<String, Object?> data,
    required this.receipt,
  }) : data = _freezeJsonMap(data);

  final Map<String, Object?> data;
  final AIToolReceipt receipt;
}

/// Sanitized configuration/registration failure.
class AIToolRegistryException implements Exception {
  const AIToolRegistryException(this.code);

  final AIToolFailureCode code;

  String get message => code.publicMessage;

  @override
  String toString() => 'AIToolRegistryException: $message';
}

/// Sanitized invocation failure with a receipt suitable for auditing.
class AIToolExecutionException implements Exception {
  const AIToolExecutionException({
    required this.code,
    required this.receipt,
  });

  final AIToolFailureCode code;
  final AIToolReceipt receipt;

  String get message => code.publicMessage;

  @override
  String toString() => 'AIToolExecutionException: $message';
}

final RegExp _toolNamePattern = RegExp(r'^[a-z][a-z0-9_]{1,63}$');

String _requiredValue(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
  return normalized;
}

Map<String, Object?> _freezeJsonMap(Map<dynamic, dynamic> source) {
  final result = <String, Object?>{};
  for (final entry in source.entries) {
    if (entry.key is! String) {
      throw ArgumentError('JSON object keys must be strings.');
    }
    result[entry.key as String] = _freezeJsonValue(entry.value);
  }
  return UnmodifiableMapView<String, Object?>(result);
}

Object? _freezeJsonValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map) return _freezeJsonMap(value);
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeJsonValue));
  }
  throw ArgumentError.value(value, 'schema', 'Value is not JSON-compatible.');
}

void _verifyClosedObjectSchemas(
  Object? node, {
  required String path,
}) {
  if (node is Map<String, Object?>) {
    final isObject = node['type'] == 'object' || node.containsKey('properties');
    if (isObject && node['additionalProperties'] != false) {
      throw ArgumentError('Object schema at $path must be closed.');
    }
    for (final entry in node.entries) {
      _verifyClosedObjectSchemas(entry.value, path: '$path.${entry.key}');
    }
    return;
  }
  if (node is List<Object?>) {
    for (var index = 0; index < node.length; index++) {
      _verifyClosedObjectSchemas(node[index], path: '$path[$index]');
    }
  }
}

void _verifyRequiredProperties(
  Object? node, {
  required String path,
}) {
  if (node is Map<String, Object?>) {
    final isObject = node['type'] == 'object' || node.containsKey('properties');
    final properties = node['properties'];
    final required = node['required'];
    if (isObject && required is! List<Object?>) {
      throw ArgumentError('Required fields at $path must be a list.');
    }
    final propertyNames = properties is Map<String, Object?>
        ? properties.keys.toSet()
        : const <String>{};
    final requiredNames = <String>{};
    if (required is List<Object?>) {
      for (final field in required) {
        if (field is! String || !propertyNames.contains(field)) {
          throw ArgumentError('Required field at $path is not a property.');
        }
        requiredNames.add(field);
      }
    }
    if (isObject &&
        (requiredNames.length != (required as List<Object?>).length ||
            requiredNames.length != propertyNames.length ||
            !requiredNames.containsAll(propertyNames))) {
      throw ArgumentError(
        'Every property at $path must be required; represent optional values '
        'with a nullable type.',
      );
    }
    for (final entry in node.entries) {
      _verifyRequiredProperties(entry.value, path: '$path.${entry.key}');
    }
    return;
  }
  if (node is List<Object?>) {
    for (var index = 0; index < node.length; index++) {
      _verifyRequiredProperties(node[index], path: '$path[$index]');
    }
  }
}

const Set<String> _supportedSchemaTypes = <String>{
  'null',
  'string',
  'integer',
  'number',
  'boolean',
  'array',
  'object',
};

void _verifyTypedSchemaNodes(
  Map<String, Object?> schema, {
  required String path,
}) {
  final type = schema['type'];
  final typeNames = switch (type) {
    String value => <String>[value],
    List<Object?> values => values.whereType<String>().toList(growable: false),
    _ => const <String>[],
  };
  if (typeNames.isEmpty ||
      typeNames.length != (type is List<Object?> ? type.length : 1) ||
      typeNames
          .any((candidate) => !_supportedSchemaTypes.contains(candidate))) {
    throw ArgumentError(
      'Schema node at $path must declare a supported JSON type.',
    );
  }

  final properties = schema['properties'];
  if (properties is Map<String, Object?>) {
    for (final entry in properties.entries) {
      final child = entry.value;
      if (child is! Map<String, Object?>) {
        throw ArgumentError(
            'Property schema at $path.${entry.key} is invalid.');
      }
      _verifyTypedSchemaNodes(child, path: '$path.${entry.key}');
    }
  }

  final items = schema['items'];
  if (items != null) {
    if (items is! Map<String, Object?>) {
      throw ArgumentError('Array item schema at $path is invalid.');
    }
    _verifyTypedSchemaNodes(items, path: '$path[]');
  }
}

bool _matchesSchema(Map<String, Object?> schema, Object? value) {
  final enumValues = schema['enum'];
  if (enumValues is List<Object?> && !enumValues.contains(value)) return false;

  final allOf = schema['allOf'];
  if (allOf is List<Object?> &&
      !allOf.whereType<Map<String, Object?>>().every(
            (candidate) => _matchesSchema(candidate, value),
          )) {
    return false;
  }
  final anyOf = schema['anyOf'];
  if (anyOf is List<Object?> &&
      !anyOf.whereType<Map<String, Object?>>().any(
            (candidate) => _matchesSchema(candidate, value),
          )) {
    return false;
  }
  final oneOf = schema['oneOf'];
  if (oneOf is List<Object?> &&
      oneOf
              .whereType<Map<String, Object?>>()
              .where((candidate) => _matchesSchema(candidate, value))
              .length !=
          1) {
    return false;
  }

  final type = schema['type'];
  if (type is List<Object?>) {
    return type.whereType<String>().any(
          (candidate) => _matchesSchema(
            <String, Object?>{...schema, 'type': candidate},
            value,
          ),
        );
  }

  switch (type) {
    case 'null':
      return value == null;
    case 'string':
      if (value is! String) return false;
      final minLength = schema['minLength'];
      final maxLength = schema['maxLength'];
      if (minLength is num && value.length < minLength.toInt()) return false;
      if (maxLength is num && value.length > maxLength.toInt()) return false;
      final pattern = schema['pattern'];
      if (pattern is String) {
        try {
          if (!RegExp(pattern).hasMatch(value)) return false;
        } catch (_) {
          return false;
        }
      }
      return true;
    case 'integer':
      if (value is! num ||
          (value is double && !value.isFinite) ||
          value.truncateToDouble() != value.toDouble()) {
        return false;
      }
      return _matchesNumericBounds(schema, value);
    case 'number':
      if (value is! num) return false;
      return _matchesNumericBounds(schema, value);
    case 'boolean':
      return value is bool;
    case 'array':
      if (value is! List) return false;
      final minItems = schema['minItems'];
      final maxItems = schema['maxItems'];
      if (minItems is num && value.length < minItems.toInt()) return false;
      if (maxItems is num && value.length > maxItems.toInt()) return false;
      final items = schema['items'];
      if (items is! Map<String, Object?>) return true;
      return value.every((item) => _matchesSchema(items, item));
    case 'object':
      if (value is! Map) return false;
      final arguments = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key is! String) return false;
        arguments[entry.key as String] = entry.value;
      }
      final properties = schema['properties'];
      final propertySchemas = properties is Map<String, Object?>
          ? properties
          : const <String, Object?>{};
      if (schema['additionalProperties'] == false &&
          arguments.keys.any((key) => !propertySchemas.containsKey(key))) {
        return false;
      }
      final required = schema['required'];
      if (required is List<Object?> &&
          required.whereType<String>().any(
                (key) => !arguments.containsKey(key),
              )) {
        return false;
      }
      for (final entry in arguments.entries) {
        final propertySchema = propertySchemas[entry.key];
        if (propertySchema is Map<String, Object?> &&
            !_matchesSchema(propertySchema, entry.value)) {
          return false;
        }
      }
      return true;
    case null:
      return false;
    default:
      return false;
  }
}

bool _matchesNumericBounds(Map<String, Object?> schema, num value) {
  final minimum = schema['minimum'];
  final maximum = schema['maximum'];
  final exclusiveMinimum = schema['exclusiveMinimum'];
  final exclusiveMaximum = schema['exclusiveMaximum'];
  if (minimum is num && value < minimum) return false;
  if (maximum is num && value > maximum) return false;
  if (exclusiveMinimum is num && value <= exclusiveMinimum) return false;
  if (exclusiveMaximum is num && value >= exclusiveMaximum) return false;
  return true;
}

bool _isJsonCompatible(Object? value) {
  if (value is double && !value.isFinite) return false;
  if (value == null || value is String || value is num || value is bool) {
    return true;
  }
  if (value is List) return value.every(_isJsonCompatible);
  if (value is Map) {
    return value.entries.every(
      (entry) => entry.key is String && _isJsonCompatible(entry.value),
    );
  }
  return false;
}

String _sha256OfCanonicalJson(Object? value) {
  final canonical = jsonEncode(_canonicalJsonValue(value));
  return sha256.convert(utf8.encode(canonical)).toString();
}

Object? _canonicalJsonValue(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw ArgumentError('Approval arguments must be finite JSON data.');
    }
    return value;
  }
  if (value is List) {
    return value.map(_canonicalJsonValue).toList(growable: false);
  }
  if (value is Map) {
    final entries = value.entries.toList(growable: false)
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    final canonical = <String, Object?>{};
    for (final entry in entries) {
      if (entry.key is! String) {
        throw ArgumentError('Approval argument keys must be strings.');
      }
      canonical[entry.key as String] = _canonicalJsonValue(entry.value);
    }
    return canonical;
  }
  throw ArgumentError('Approval arguments must be JSON-compatible.');
}
