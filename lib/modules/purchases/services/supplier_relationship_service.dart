import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/supplier.dart' as legacy;
import '../../../shared/models/supplier_ocr_template.dart';
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/services/authority_scoped_cache.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/legacy_supplier_adapter.dart';
import '../models/supplier_foundation.dart';

@immutable
class SupplierProfilePage {
  SupplierProfilePage({
    required List<SupplierProfile> items,
    required this.offset,
    required this.limit,
    required this.hasMore,
  }) : items = List.unmodifiable(items);

  final List<SupplierProfile> items;
  final int offset;
  final int limit;
  final bool hasMore;

  int? get nextOffset => hasMore ? offset + items.length : null;
}

@immutable
class SupplierClassificationCandidatePage {
  SupplierClassificationCandidatePage({
    required List<SupplierClassificationCandidate> items,
    required this.offset,
    required this.limit,
    required this.hasMore,
  }) : items = List.unmodifiable(items);

  final List<SupplierClassificationCandidate> items;
  final int offset;
  final int limit;
  final bool hasMore;

  int? get nextOffset => hasMore ? offset + items.length : null;
}

@immutable
class SupplierClassificationCandidateReviewResult {
  const SupplierClassificationCandidateReviewResult({
    required this.candidate,
    required this.idempotentReplay,
  });

  final SupplierClassificationCandidate candidate;
  final bool idempotentReplay;
}

enum SupplierClassificationDefinitionCommandAction {
  create,
  update;

  static SupplierClassificationDefinitionCommandAction fromJson(
    dynamic value,
  ) {
    return switch (value?.toString()) {
      'create' => SupplierClassificationDefinitionCommandAction.create,
      'update' => SupplierClassificationDefinitionCommandAction.update,
      _ => throw const FormatException(
          'Invalid supplier classification definition command action',
        ),
    };
  }
}

@immutable
class SupplierClassificationDefinitionCommandResult {
  const SupplierClassificationDefinitionCommandResult({
    required this.operationId,
    required this.vocabulary,
    required this.action,
    required this.appliedDefinition,
    required this.currentDefinition,
    required this.idempotentReplay,
  });

  factory SupplierClassificationDefinitionCommandResult.fromJson(
    Map<String, dynamic> json, {
    required SupplierClassificationDefinitionKind kind,
  }) {
    final vocabulary = SupplierClassificationDefinitionKind.fromJson(
      json['vocabulary'],
    );
    if (vocabulary != kind) {
      throw const FormatException(
        'Classification definition response vocabulary changed',
      );
    }
    return SupplierClassificationDefinitionCommandResult(
      operationId: _requiredRowText(json, 'operation_id'),
      vocabulary: vocabulary,
      action: SupplierClassificationDefinitionCommandAction.fromJson(
        json['action'],
      ),
      appliedDefinition: SupplierClassificationDefinition.fromJson(
        _requiredNestedMap(json, 'applied_definition'),
        kind: kind,
      ),
      currentDefinition: SupplierClassificationDefinition.fromJson(
        _requiredNestedMap(json, 'current_definition'),
        kind: kind,
      ),
      idempotentReplay: json['idempotent_replay'] as bool? ?? false,
    );
  }

  final String operationId;
  final SupplierClassificationDefinitionKind vocabulary;
  final SupplierClassificationDefinitionCommandAction action;
  final SupplierClassificationDefinition appliedDefinition;
  final SupplierClassificationDefinition currentDefinition;
  final bool idempotentReplay;
}

@immutable
class SupplierEconomicTimelinePage {
  const SupplierEconomicTimelinePage({
    required this.timeline,
    required this.offset,
    required this.limit,
    required this.hasMore,
  });

  final SupplierEconomicReadModel timeline;
  final int offset;
  final int limit;
  final bool hasMore;

  int? get nextOffset => hasMore ? offset + timeline.activities.length : null;
}

@immutable
class SupplierProfileCommandResult {
  const SupplierProfileCommandResult({
    required this.profile,
    this.idempotentReplay = false,
  });

  final SupplierProfile profile;
  final bool idempotentReplay;
}

@immutable
class UpdateSupplierOcrTemplateCommand {
  UpdateSupplierOcrTemplateCommand({
    required this.operationId,
    required this.supplierId,
    required this.expectedUpdatedAt,
    required this.template,
  }) {
    _validateOperationId(operationId);
    if (supplierId.trim().isEmpty) {
      throw ArgumentError.value(
        supplierId,
        'supplierId',
        'A durable supplier id is required',
      );
    }
  }

  final String operationId;
  final String supplierId;
  final DateTime expectedUpdatedAt;
  final SupplierOcrTemplate template;
}

/// El vendedor del proveedor: la persona a la que el ERP le escribe por
/// WhatsApp. Comando estrecho e idempotente, calcado del de la plantilla OCR,
/// porque el perfil (`save_supplier_relationship_profile`) no lo acepta.
class UpdateSupplierSalesRepCommand {
  UpdateSupplierSalesRepCommand({
    required this.operationId,
    required this.supplierId,
    required this.expectedUpdatedAt,
    this.name,
    this.phone,
    this.email,
  }) {
    _validateOperationId(operationId);
    if (supplierId.trim().isEmpty) {
      throw ArgumentError.value(
        supplierId,
        'supplierId',
        'A durable supplier id is required',
      );
    }
  }

  final String operationId;
  final String supplierId;
  final DateTime expectedUpdatedAt;
  final String? name;
  final String? phone;
  final String? email;

  /// Un espacio en blanco es «sin dato», no un dato.
  Map<String, dynamic> toJson() => {
        'name': _blankToNull(name),
        'phone': _blankToNull(phone),
        'email': _blankToNull(email),
      };

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

@immutable
class SupplierSalesRepCommandResult {
  const SupplierSalesRepCommandResult({
    required this.operationId,
    required this.tenantId,
    required this.supplierId,
    required this.name,
    required this.phone,
    required this.email,
    required this.updatedAt,
    required this.idempotentReplay,
  });

  factory SupplierSalesRepCommandResult.fromJson(Map<String, dynamic> json) {
    final salesRep = json['sales_rep'];
    final rep = salesRep is Map
        ? Map<String, dynamic>.from(salesRep)
        : const <String, dynamic>{};
    return SupplierSalesRepCommandResult(
      operationId: _requiredRowText(json, 'operation_id'),
      tenantId: _requiredRowText(json, 'tenant_id'),
      supplierId: _requiredRowText(json, 'supplier_id'),
      name: _nullableRowText(rep, 'name'),
      phone: _nullableRowText(rep, 'phone'),
      email: _nullableRowText(rep, 'email'),
      updatedAt: DateTime.parse(_requiredRowText(json, 'updated_at')).toUtc(),
      idempotentReplay: json['idempotent_replay'] as bool? ?? false,
    );
  }

  final String operationId;
  final String tenantId;
  final String supplierId;
  final String? name;
  final String? phone;
  final String? email;
  final DateTime updatedAt;
  final bool idempotentReplay;

  static String? _nullableRowText(Map<String, dynamic> row, String key) {
    final value = row[key]?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }
}

/// Crea (sin `contactId`) o edita una persona del proveedor. `isPrimary`
/// verdadero la vuelve el destino del ERP y baja a la anterior.
class SaveSupplierContactCommand {
  SaveSupplierContactCommand({
    required this.operationId,
    required this.supplierId,
    required this.name,
    this.contactId,
    this.expectedUpdatedAt,
    this.role,
    this.phone,
    this.email,
    this.notes,
    this.isPrimary,
  }) {
    _validateOperationId(operationId);
    if (supplierId.trim().isEmpty) {
      throw ArgumentError.value(
        supplierId,
        'supplierId',
        'A durable supplier id is required',
      );
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'A contact needs a name');
    }
    if (contactId != null && expectedUpdatedAt == null) {
      throw ArgumentError.value(
        expectedUpdatedAt,
        'expectedUpdatedAt',
        'Editing a contact requires its expected updated_at',
      );
    }
  }

  final String operationId;
  final String supplierId;
  final String? contactId;
  final DateTime? expectedUpdatedAt;
  final String name;
  final String? role;
  final String? phone;
  final String? email;
  final String? notes;

  /// `null` deja la marca como está; `true`/`false` la cambian.
  final bool? isPrimary;

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'role': UpdateSupplierSalesRepCommand._blankToNull(role),
        'phone': UpdateSupplierSalesRepCommand._blankToNull(phone),
        'email': UpdateSupplierSalesRepCommand._blankToNull(email),
        'notes': UpdateSupplierSalesRepCommand._blankToNull(notes),
        if (isPrimary != null) 'is_primary': isPrimary,
      };
}

/// Desactiva (conserva hilos y archivos, deja de ser principal) o reactiva.
class SetSupplierContactStatusCommand {
  SetSupplierContactStatusCommand({
    required this.operationId,
    required this.supplierId,
    required this.contactId,
    required this.expectedUpdatedAt,
    required this.isActive,
  }) {
    _validateOperationId(operationId);
    if (supplierId.trim().isEmpty || contactId.trim().isEmpty) {
      throw ArgumentError('A durable supplier and contact id are required');
    }
  }

  final String operationId;
  final String supplierId;
  final String contactId;
  final DateTime expectedUpdatedAt;
  final bool isActive;
}

@immutable
class SupplierContactCommandResult {
  const SupplierContactCommandResult({
    required this.operationId,
    required this.tenantId,
    required this.supplierId,
    required this.contact,
    required this.idempotentReplay,
  });

  factory SupplierContactCommandResult.fromJson(Map<String, dynamic> json) {
    final contactJson = json['contact'];
    return SupplierContactCommandResult(
      operationId: _requiredRowText(json, 'operation_id'),
      tenantId: _requiredRowText(json, 'tenant_id'),
      supplierId: _requiredRowText(json, 'supplier_id'),
      contact: SupplierContact.fromJson(
        contactJson is Map
            ? Map<String, dynamic>.from(contactJson)
            : const <String, dynamic>{},
      ),
      idempotentReplay: json['idempotent_replay'] as bool? ?? false,
    );
  }

  final String operationId;
  final String tenantId;
  final String supplierId;
  final SupplierContact contact;
  final bool idempotentReplay;
}

@immutable
class SupplierOcrTemplateCommandResult {
  const SupplierOcrTemplateCommandResult({
    required this.operationId,
    required this.tenantId,
    required this.supplierId,
    required this.template,
    required this.updatedAt,
    required this.idempotentReplay,
  });

  factory SupplierOcrTemplateCommandResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return SupplierOcrTemplateCommandResult(
      operationId: _requiredRowText(json, 'operation_id'),
      tenantId: _requiredRowText(json, 'tenant_id'),
      supplierId: _requiredRowText(json, 'supplier_id'),
      template: SupplierOcrTemplate.fromJson(json['ocr_template']),
      updatedAt: DateTime.parse(_requiredRowText(json, 'updated_at')).toUtc(),
      idempotentReplay: json['idempotent_replay'] as bool? ?? false,
    );
  }

  final String operationId;
  final String tenantId;
  final String supplierId;
  final SupplierOcrTemplate template;
  final DateTime updatedAt;
  final bool idempotentReplay;
}

abstract interface class SupplierRelationshipRepository {
  Future<List<Map<String, dynamic>>> fetchProfileRows({
    required String tenantId,
    required bool activeOnly,
    required int offset,
    required int limit,
  });

  Future<Map<String, dynamic>?> fetchProfileRow({
    required String tenantId,
    required String supplierId,
  });

  Future<Map<String, dynamic>?> fetchExternalPartyRow({
    required String tenantId,
    required String partyId,
  });

  Future<List<Map<String, dynamic>>> fetchDefinitionRows({
    required String tenantId,
    required SupplierClassificationDefinitionKind kind,
    required bool activeOnly,
  });

  Future<List<Map<String, dynamic>>> fetchClassificationCandidateRows({
    required String tenantId,
    required SupplierClassificationCandidateStatus? status,
    required SupplierClassificationDefinitionKind? targetVocabulary,
    required String? supplierId,
    required int offset,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> fetchIdentifierRows({
    required String tenantId,
    required String partyId,
  });

  Future<List<Map<String, dynamic>>> fetchRoleRows({
    required String tenantId,
    required String supplierId,
  });

  Future<List<Map<String, dynamic>>> fetchCapabilityRows({
    required String tenantId,
    required String supplierId,
  });

  Future<List<Map<String, dynamic>>> fetchTagRows({
    required String tenantId,
    required String supplierId,
  });
  Future<List<Map<String, dynamic>>> fetchContactRows({
    required String tenantId,
    required String supplierId,
  });

  Future<List<Map<String, dynamic>>> fetchEngagementRows({
    required String tenantId,
    required String supplierId,
  });

  Future<List<Map<String, dynamic>>> fetchEngagementVersionRows({
    required String tenantId,
    required List<String> engagementIds,
  });

  Future<List<Map<String, dynamic>>> fetchSiteRows({
    required String tenantId,
    required List<String> siteIds,
  });

  Future<List<Map<String, dynamic>>> fetchBusinessSiteRows({
    required String tenantId,
  });

  Future<List<Map<String, dynamic>>> fetchPolicyRows({
    required String tenantId,
    required String supplierId,
  });

  Future<List<Map<String, dynamic>>> fetchPolicyVersionRows({
    required String tenantId,
    required List<String> policyIds,
  });

  Future<List<Map<String, dynamic>>> fetchRuleRows({
    required String tenantId,
    required List<String> policyVersionIds,
  });

  Future<List<Map<String, dynamic>>> fetchEvidenceRows({
    required String tenantId,
    required String supplierId,
    required int limit,
  });

  Future<List<Map<String, dynamic>>> fetchReceivedTaxDocumentRows({
    required String tenantId,
    required String supplierId,
  });

  Future<List<Map<String, dynamic>>> fetchEconomicSummaryRows({
    required String tenantId,
    required String supplierId,
  });

  Future<List<Map<String, dynamic>>> fetchEconomicTimelineRows({
    required String tenantId,
    required String supplierId,
    required bool recognizedOnly,
    required int offset,
    required int limit,
  });
}

abstract interface class LegacySupplierReadRepository {
  Future<List<legacy.Supplier>> fetchPage({
    required String tenantId,
    required bool activeOnly,
    required int offset,
    required int limit,
  });

  Future<legacy.Supplier?> fetchOne({
    required String tenantId,
    required String supplierId,
  });
}

@immutable
class SupplierClassificationSelection {
  SupplierClassificationSelection({
    required this.definition,
    this.assignmentId,
    Map<String, dynamic> publicMetadata = const {},
  }) : publicMetadata = _sanitizePublicMap(publicMetadata);

  final SupplierClassificationDefinition definition;
  final String? assignmentId;
  final Map<String, dynamic> publicMetadata;

  Map<String, dynamic> toRpcJson() => {
        'id': assignmentId,
        'code': definition.code,
        'metadata': publicMetadata,
      };
}

@immutable
class SaveSupplierRelationshipProfileCommand {
  SaveSupplierRelationshipProfileCommand({
    required this.operationId,
    required this.party,
    required this.relationship,
    List<SupplierClassificationSelection> roles = const [],
    List<SupplierClassificationSelection> capabilities = const [],
    List<SupplierClassificationSelection> tags = const [],
    this.supplierId,
    this.expectedUpdatedAt,
    this.taxIdentifier,
    this.taxCountryCode,
    this.address,
    this.city,
    this.region,
    this.comuna,
    this.legacyType,
    this.defaultTaxTreatment,
  })  : roles = List.unmodifiable(roles),
        capabilities = List.unmodifiable(capabilities),
        tags = List.unmodifiable(tags) {
    _validateOperationId(operationId);
  }

  final String operationId;
  final String? supplierId;
  final DateTime? expectedUpdatedAt;
  final ExternalParty party;
  final SupplierRelationship relationship;
  final List<SupplierClassificationSelection> roles;
  final List<SupplierClassificationSelection> capabilities;
  final List<SupplierClassificationSelection> tags;
  final String? taxIdentifier;
  final String? taxCountryCode;
  final String? address;
  final String? city;
  final String? region;
  final String? comuna;
  final legacy.SupplierType? legacyType;
  final TaxTreatment? defaultTaxTreatment;

  Map<String, dynamic> toProfileRpcJson() {
    final payload = <String, dynamic>{
      'operation_id': operationId,
      'party_kind': party.kind.dbValue,
      'display_name': party.displayName,
      'legal_name': party.legalName,
      'trade_name': party.tradeName,
      'aliases': party.aliases,
      'country_code': party.countryCode,
      'party_notes': party.notes,
      'party_metadata': party.publicMetadata,
      // This is a full-profile command: null explicitly clears the active tax
      // identifier. Historical party identifiers are read context and must
      // never silently resurrect a value the editor removed.
      'tax_identifier': taxIdentifier,
      'tax_country_code': taxCountryCode,
      'email': relationship.email,
      'phone': relationship.phone,
      'address': address,
      'city': city,
      'region': region,
      'comuna': comuna,
      'contact_person': relationship.contactPerson,
      'website': relationship.website,
      'notes': relationship.notes,
      'is_active': relationship.isActive,
      'legacy_type': legacyType?.name,
      'payment_terms': relationship.paymentTermsCode,
      'default_tax_treatment': defaultTaxTreatment?.toValue(),
    };
    return payload;
  }
}

@immutable
class SupplierEngagementShellInput {
  SupplierEngagementShellInput({
    required this.kind,
    required this.code,
    required this.name,
    required this.status,
    this.businessSiteId,
    this.startsOn,
    this.endsOn,
    Map<String, dynamic> publicMetadata = const {},
  }) : publicMetadata = _sanitizePublicMap(publicMetadata) {
    _requireCommandText(code, 'code');
    _requireCommandText(name, 'name');
    if (startsOn != null && endsOn != null && endsOn!.isBefore(startsOn!)) {
      throw ArgumentError.value(endsOn, 'endsOn', 'Must not precede startsOn');
    }
  }

  final SupplierEngagementKind kind;
  final String code;
  final String name;
  final SupplierEngagementStatus status;
  final String? businessSiteId;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final Map<String, dynamic> publicMetadata;

  Map<String, dynamic> toRpcJson() => {
        'site_id': _optionalCommandText(businessSiteId),
        'engagement_kind': kind.dbValue,
        'code': code.trim(),
        'name': name.trim(),
        'status': status.name,
        'starts_on': startsOn == null ? null : _databaseDate(startsOn!),
        'ends_on': endsOn == null ? null : _databaseDate(endsOn!),
        'metadata': publicMetadata,
      };
}

@immutable
class SupplierEngagementVersionInput {
  SupplierEngagementVersionInput({
    required this.effectiveFrom,
    this.externalReference,
    this.serviceIdentifier,
    this.billingCycle = SupplierEngagementBillingCycle.none,
    this.currencyCode = 'CLP',
    this.expectedAmount,
    this.dueDay,
    this.portalUrl,
    Map<String, dynamic> publicTerms = const {},
  }) : publicTerms = _sanitizePublicMap(publicTerms) {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currencyCode.toUpperCase())) {
      throw ArgumentError.value(currencyCode, 'currencyCode', 'Use ISO-4217');
    }
    if (expectedAmount != null && expectedAmount! < 0) {
      throw ArgumentError.value(
        expectedAmount,
        'expectedAmount',
        'Must not be negative',
      );
    }
    final normalizedDueDay = dueDay;
    if (normalizedDueDay != null &&
        (normalizedDueDay < 1 || normalizedDueDay > 31)) {
      throw RangeError.range(normalizedDueDay, 1, 31, 'dueDay');
    }
  }

  final DateTime effectiveFrom;
  final String? externalReference;
  final String? serviceIdentifier;
  final SupplierEngagementBillingCycle billingCycle;
  final String currencyCode;
  final double? expectedAmount;
  final int? dueDay;
  final String? portalUrl;
  final Map<String, dynamic> publicTerms;

  Map<String, dynamic> toRpcJson({required bool includeEffectiveFrom}) => {
        if (includeEffectiveFrom)
          'effective_from': _databaseDate(effectiveFrom),
        'external_reference': _optionalCommandText(externalReference),
        'service_identifier': _optionalCommandText(serviceIdentifier),
        'billing_cycle': billingCycle.name,
        'currency_code': currencyCode.toUpperCase(),
        'expected_amount': expectedAmount,
        'due_day': dueDay,
        'portal_url': _optionalCommandText(portalUrl),
        'terms': publicTerms,
      };
}

@immutable
class CreateSupplierEngagementCommand {
  CreateSupplierEngagementCommand({
    required this.operationId,
    required this.supplierId,
    required this.engagement,
    required this.initialVersion,
  }) {
    _validateOperationId(operationId);
    _requireCommandText(supplierId, 'supplierId');
  }

  final String operationId;
  final String supplierId;
  final SupplierEngagementShellInput engagement;
  final SupplierEngagementVersionInput initialVersion;
}

@immutable
class UpdateSupplierEngagementShellCommand {
  UpdateSupplierEngagementShellCommand({
    required this.engagementId,
    required this.expectedUpdatedAt,
    required this.engagement,
  }) {
    _requireCommandText(engagementId, 'engagementId');
  }

  final String engagementId;
  final DateTime expectedUpdatedAt;
  final SupplierEngagementShellInput engagement;
}

@immutable
class AppendSupplierEngagementVersionCommand {
  AppendSupplierEngagementVersionCommand({
    required this.operationId,
    required this.engagementId,
    required this.version,
  }) {
    _validateOperationId(operationId);
    _requireCommandText(engagementId, 'engagementId');
  }

  final String operationId;
  final String engagementId;
  final SupplierEngagementVersionInput version;
}

@immutable
class SupplierEngagementCommandResult {
  const SupplierEngagementCommandResult({
    required this.engagement,
    required this.appliedVersion,
    required this.currentVersion,
    this.closedVersion,
    this.idempotentReplay = false,
  });

  factory SupplierEngagementCommandResult.fromJson(Map<String, dynamic> json) {
    final engagementRow = _requiredNestedMap(json, 'engagement');
    final currentRow = _requiredNestedMap(json, 'current_version');
    final appliedRow =
        _optionalNestedMap(json['applied_version']) ?? currentRow;
    final closedRow = _optionalNestedMap(json['closed_version']);
    return SupplierEngagementCommandResult(
      engagement: SupplierEngagement.fromJson({
        ...engagementRow,
        'versions': [currentRow],
      }),
      appliedVersion: SupplierEngagementVersion.fromJson(appliedRow),
      currentVersion: SupplierEngagementVersion.fromJson(currentRow),
      closedVersion: closedRow == null
          ? null
          : SupplierEngagementVersion.fromJson(closedRow),
      idempotentReplay: json['idempotent_replay'] as bool? ?? false,
    );
  }

  final SupplierEngagement engagement;
  final SupplierEngagementVersion appliedVersion;
  final SupplierEngagementVersion currentVersion;
  final SupplierEngagementVersion? closedVersion;
  final bool idempotentReplay;
}

@immutable
class SupplierAccountingPolicyShellInput {
  SupplierAccountingPolicyShellInput({
    required this.code,
    required this.name,
    required this.status,
    this.engagementId,
    this.priority = 100,
    this.allowExactAutofill = false,
  }) {
    _requireCommandText(code, 'code');
    _requireCommandText(name, 'name');
  }

  final String code;
  final String name;
  final SupplierAccountingPolicyStatus status;
  final String? engagementId;
  final int priority;
  final bool allowExactAutofill;

  Map<String, dynamic> toRpcJson() => {
        'engagement_id': _optionalCommandText(engagementId),
        'code': code.trim(),
        'name': name.trim(),
        'status': status.name,
        'priority': priority,
        'allow_exact_autofill': allowExactAutofill,
      };
}

@immutable
class SupplierAccountingPolicyVersionInput {
  SupplierAccountingPolicyVersionInput({
    required this.effectiveFrom,
    required this.operationalNature,
    this.legacyExpenseCategoryId,
    this.debitAccountId,
    this.liabilityAccountId,
    this.taxTreatment = SupplierAccountingTaxTreatment.notApplicable,
    this.expectedDocumentType,
    this.currencyCode = 'CLP',
    this.lineNature,
    Map<String, dynamic> publicPosture = const {},
  }) : publicPosture = _sanitizePublicMap(publicPosture) {
    if (operationalNature.kind !=
        SupplierClassificationDefinitionKind.operationalNature) {
      throw ArgumentError.value(
        operationalNature.kind,
        'operationalNature',
        'Must be an operational-nature definition',
      );
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currencyCode.toUpperCase())) {
      throw ArgumentError.value(currencyCode, 'currencyCode', 'Use ISO-4217');
    }
  }

  final DateTime effectiveFrom;
  final SupplierClassificationDefinition operationalNature;
  final String? legacyExpenseCategoryId;
  final String? debitAccountId;
  final String? liabilityAccountId;
  final SupplierAccountingTaxTreatment taxTreatment;
  final String? expectedDocumentType;
  final String currencyCode;
  final SupplierAccountingLineNature? lineNature;
  final Map<String, dynamic> publicPosture;

  Map<String, dynamic> toRpcJson({required bool includeEffectiveFrom}) => {
        if (includeEffectiveFrom)
          'effective_from': _databaseDate(effectiveFrom),
        'operational_nature_code': operationalNature.code,
        'legacy_expense_category_id':
            _optionalCommandText(legacyExpenseCategoryId),
        'debit_account_id': _optionalCommandText(debitAccountId),
        'liability_account_id': _optionalCommandText(liabilityAccountId),
        'tax_treatment': taxTreatment.dbValue,
        'expected_document_type': _optionalCommandText(expectedDocumentType),
        'currency_code': currencyCode.toUpperCase(),
        'line_nature': lineNature?.dbValue,
        'posture': publicPosture,
      };
}

@immutable
class SupplierAccountingRuleInput {
  SupplierAccountingRuleInput({
    required this.kind,
    required this.operator,
    Map<String, dynamic> operand = const {},
    this.priority = 100,
    this.isActive = true,
  }) : operand = _sanitizePublicMap(operand);

  final SupplierAccountingRuleKind kind;
  final SupplierAccountingRuleOperator operator;
  final Map<String, dynamic> operand;
  final int priority;
  final bool isActive;

  Map<String, dynamic> toRpcJson() => {
        'rule_kind': kind.dbValue,
        'operator': operator.name,
        'operand': operand,
        'priority': priority,
        'is_active': isActive,
      };
}

@immutable
class CreateSupplierAccountingPolicyCommand {
  CreateSupplierAccountingPolicyCommand({
    required this.operationId,
    required this.supplierId,
    required this.policy,
    required this.initialVersion,
    List<SupplierAccountingRuleInput> rules = const [],
  }) : rules = List.unmodifiable(rules) {
    _validateOperationId(operationId);
    _requireCommandText(supplierId, 'supplierId');
  }

  final String operationId;
  final String supplierId;
  final SupplierAccountingPolicyShellInput policy;
  final SupplierAccountingPolicyVersionInput initialVersion;
  final List<SupplierAccountingRuleInput> rules;
}

@immutable
class UpdateSupplierAccountingPolicyShellCommand {
  UpdateSupplierAccountingPolicyShellCommand({
    required this.policyId,
    required this.expectedUpdatedAt,
    required this.policy,
  }) {
    _requireCommandText(policyId, 'policyId');
  }

  final String policyId;
  final DateTime expectedUpdatedAt;
  final SupplierAccountingPolicyShellInput policy;
}

@immutable
class AppendSupplierAccountingPolicyVersionCommand {
  AppendSupplierAccountingPolicyVersionCommand({
    required this.operationId,
    required this.policyId,
    required this.version,
    List<SupplierAccountingRuleInput> rules = const [],
  }) : rules = List.unmodifiable(rules) {
    _validateOperationId(operationId);
    _requireCommandText(policyId, 'policyId');
  }

  final String operationId;
  final String policyId;
  final SupplierAccountingPolicyVersionInput version;
  final List<SupplierAccountingRuleInput> rules;
}

@immutable
class SupplierAccountingPolicyCommandResult {
  SupplierAccountingPolicyCommandResult({
    required this.policy,
    required this.appliedVersion,
    required this.currentVersion,
    List<SupplierAccountingRuleSummary> rules = const [],
    this.closedVersion,
    this.idempotentReplay = false,
  }) : rules = List.unmodifiable(rules);

  factory SupplierAccountingPolicyCommandResult.fromJson(
    Map<String, dynamic> json, {
    SupplierClassificationDefinition? operationalNature,
  }) {
    final policyRow = _requiredNestedMap(json, 'policy');
    final rawCurrent = _requiredNestedMap(json, 'current_version');
    final rawApplied =
        _optionalNestedMap(json['applied_version']) ?? rawCurrent;
    final rawClosed = _optionalNestedMap(json['closed_version']);
    Map<String, dynamic> enrich(Map<String, dynamic> row) {
      final definitionMatches = operationalNature != null &&
          row['operational_nature_code']?.toString() == operationalNature.code;
      return {
        ...row,
        if (definitionMatches) ...{
          'operational_nature_definition_id': operationalNature.id,
          'operational_nature_label': operationalNature.label,
          'operational_nature_group': operationalNature.natureGroup,
        },
      };
    }

    final current = enrich(rawCurrent);
    final applied = enrich(rawApplied);
    final closed = rawClosed == null ? null : enrich(rawClosed);
    final ruleRows = _mapRows(json['rules']);
    return SupplierAccountingPolicyCommandResult(
      policy: SupplierAccountingPolicySummary.fromJson({
        ...policyRow,
        'versions': [current],
      }),
      appliedVersion: SupplierAccountingPolicyVersionSummary.fromJson(applied),
      currentVersion: SupplierAccountingPolicyVersionSummary.fromJson(current),
      closedVersion: closed == null
          ? null
          : SupplierAccountingPolicyVersionSummary.fromJson(closed),
      rules: ruleRows
          .map(SupplierAccountingRuleSummary.fromJson)
          .toList(growable: false),
      idempotentReplay: json['idempotent_replay'] as bool? ?? false,
    );
  }

  final SupplierAccountingPolicySummary policy;
  final SupplierAccountingPolicyVersionSummary appliedVersion;
  final SupplierAccountingPolicyVersionSummary currentVersion;
  final SupplierAccountingPolicyVersionSummary? closedVersion;
  final List<SupplierAccountingRuleSummary> rules;
  final bool idempotentReplay;
}

@immutable
class AppendSupplierAccountingEvidenceCommand {
  AppendSupplierAccountingEvidenceCommand({
    required this.operationId,
    required this.supplierId,
    required this.sourceType,
    required this.sourceId,
    required this.decision,
    required this.operationalNature,
    this.sourceLineId,
    this.policyVersionId,
    this.ruleId,
    this.debitAccountId,
    this.liabilityAccountId,
    this.legacyExpenseCategoryId,
    this.rationale,
    Map<String, dynamic> publicEvidence = const {},
  }) : publicEvidence = _sanitizePublicMap(publicEvidence) {
    _validateOperationId(operationId);
    _requireCommandText(supplierId, 'supplierId');
    _requireCommandText(sourceId, 'sourceId');
    if (sourceType.requiresLineId &&
        _optionalCommandText(sourceLineId) == null) {
      throw ArgumentError.value(sourceLineId, 'sourceLineId', 'Required');
    }
    if (operationalNature.kind !=
        SupplierClassificationDefinitionKind.operationalNature) {
      throw ArgumentError.value(
        operationalNature.kind,
        'operationalNature',
        'Must be an operational-nature definition',
      );
    }
    if (decision == SupplierAccountingEvidenceDecision.autoFilled) {
      throw ArgumentError.value(
        decision,
        'decision',
        'auto_filled is reserved for a future server-side evaluator',
      );
    }
  }

  final String operationId;
  final String supplierId;
  final SupplierAccountingEvidenceSourceType sourceType;
  final String sourceId;
  final String? sourceLineId;
  final SupplierAccountingEvidenceDecision decision;
  final SupplierClassificationDefinition operationalNature;
  final String? policyVersionId;
  final String? ruleId;
  final String? debitAccountId;
  final String? liabilityAccountId;
  final String? legacyExpenseCategoryId;
  final String? rationale;
  final Map<String, dynamic> publicEvidence;

  Map<String, dynamic> toRpcJson() => {
        'operation_id': operationId,
        'policy_version_id': _optionalCommandText(policyVersionId),
        'rule_id': _optionalCommandText(ruleId),
        'source_type': sourceType.dbValue,
        'source_id': sourceId,
        'source_line_id': _optionalCommandText(sourceLineId),
        'decision': decision.dbValue,
        'operational_nature_code': operationalNature.code,
        'debit_account_id': _optionalCommandText(debitAccountId),
        'liability_account_id': _optionalCommandText(liabilityAccountId),
        'legacy_expense_category_id':
            _optionalCommandText(legacyExpenseCategoryId),
        'rationale': _optionalCommandText(rationale),
        'evidence': publicEvidence,
      };
}

@immutable
class ReviewSupplierClassificationCandidateCommand {
  ReviewSupplierClassificationCandidateCommand({
    required this.candidateId,
    required this.decision,
    this.canonicalCode,
    this.rationale,
  }) {
    _requireCommandText(candidateId, 'candidateId');
    final code = _optionalCommandText(canonicalCode);
    if (decision == SupplierClassificationCandidateStatus.pending) {
      throw ArgumentError.value(
        decision,
        'decision',
        'Only confirmed or rejected decisions can be submitted',
      );
    }
    if (decision == SupplierClassificationCandidateStatus.confirmed &&
        (code == null || !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(code))) {
      throw ArgumentError.value(
        canonicalCode,
        'canonicalCode',
        'Confirmed candidates require a canonical snake_case code',
      );
    }
    if (decision == SupplierClassificationCandidateStatus.rejected &&
        code != null) {
      throw ArgumentError.value(
        canonicalCode,
        'canonicalCode',
        'Rejected candidates cannot select a canonical code',
      );
    }
  }

  final String candidateId;
  final SupplierClassificationCandidateStatus decision;
  final String? canonicalCode;
  final String? rationale;

  String? get normalizedCanonicalCode =>
      _optionalCommandText(canonicalCode)?.toLowerCase();

  String? get normalizedRationale => _optionalCommandText(rationale);
}

@immutable
class UpsertSupplierClassificationDefinitionCommand {
  UpsertSupplierClassificationDefinitionCommand({
    required this.operationId,
    required this.kind,
    required this.code,
    required this.label,
    this.expectedUpdatedAt,
    this.description,
    this.natureGroup,
    List<String> aliases = const [],
    this.isActive = true,
    Map<String, dynamic> publicMetadata = const {},
  })  : aliases = List.unmodifiable(
          aliases.map((item) => item.trim()).where((item) => item.isNotEmpty),
        ),
        publicMetadata = _sanitizePublicMap(publicMetadata) {
    _validateOperationId(operationId);
    _requireCommandText(code, 'code');
    _requireCommandText(label, 'label');
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(code)) {
      throw ArgumentError.value(code, 'code', 'Use canonical snake_case');
    }
    const natureGroups = {
      'inventory',
      'operating_expense',
      'service',
      'tax',
      'asset',
      'other',
    };
    if (kind == SupplierClassificationDefinitionKind.operationalNature &&
        !natureGroups.contains(natureGroup)) {
      throw ArgumentError.value(
        natureGroup,
        'natureGroup',
        'Required for operational nature',
      );
    }
  }

  final String operationId;
  final SupplierClassificationDefinitionKind kind;
  final String code;
  final String label;
  final DateTime? expectedUpdatedAt;
  final String? description;
  final String? natureGroup;
  final List<String> aliases;
  final bool isActive;
  final Map<String, dynamic> publicMetadata;

  String get vocabulary => kind.dbValue;

  Map<String, dynamic> toRpcJson() => {
        'code': code,
        'label': label.trim(),
        'description': _optionalCommandText(description),
        if (kind == SupplierClassificationDefinitionKind.operationalNature)
          'nature_group': natureGroup,
        'aliases': aliases,
        'is_active': isActive,
        'metadata': publicMetadata,
      };
}

abstract interface class SupplierRelationshipCommandGateway {
  Future<Map<String, dynamic>> saveProfile({
    required String tenantId,
    required SaveSupplierRelationshipProfileCommand command,
  });

  Future<Map<String, dynamic>> updateOcrTemplate({
    required String tenantId,
    required UpdateSupplierOcrTemplateCommand command,
  });

  Future<Map<String, dynamic>> updateSalesRep({
    required String tenantId,
    required UpdateSupplierSalesRepCommand command,
  });
  Future<Map<String, dynamic>> saveContact({
    required String tenantId,
    required SaveSupplierContactCommand command,
  });
  Future<Map<String, dynamic>> setContactStatus({
    required String tenantId,
    required SetSupplierContactStatusCommand command,
  });
  Future<Map<String, dynamic>> updateImageUrl({
    required String tenantId,
    required String supplierId,
    required String? imageUrl,
  });

  Future<Map<String, dynamic>> createEngagement({
    required String tenantId,
    required CreateSupplierEngagementCommand command,
  });

  Future<Map<String, dynamic>> updateEngagementShell({
    required String tenantId,
    required UpdateSupplierEngagementShellCommand command,
  });

  Future<Map<String, dynamic>> appendEngagementVersion({
    required String tenantId,
    required AppendSupplierEngagementVersionCommand command,
  });

  Future<Map<String, dynamic>> createAccountingPolicy({
    required String tenantId,
    required CreateSupplierAccountingPolicyCommand command,
  });

  Future<Map<String, dynamic>> updateAccountingPolicyShell({
    required String tenantId,
    required UpdateSupplierAccountingPolicyShellCommand command,
  });

  Future<Map<String, dynamic>> appendAccountingPolicyVersion({
    required String tenantId,
    required AppendSupplierAccountingPolicyVersionCommand command,
  });

  Future<Map<String, dynamic>> appendAccountingEvidence({
    required String tenantId,
    required AppendSupplierAccountingEvidenceCommand command,
  });

  Future<Map<String, dynamic>> upsertClassificationDefinition({
    required String tenantId,
    required UpsertSupplierClassificationDefinitionCommand command,
  });

  Future<Map<String, dynamic>> reviewClassificationCandidate({
    required String tenantId,
    required ReviewSupplierClassificationCandidateCommand command,
  });
}

class SupabaseSupplierRelationshipCommandGateway
    implements SupplierRelationshipCommandGateway {
  SupabaseSupplierRelationshipCommandGateway([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> saveProfile({
    required String tenantId,
    required SaveSupplierRelationshipProfileCommand command,
  }) async {
    final response = await _client.rpc(
      'save_supplier_relationship_profile',
      params: {
        'p_tenant_id': tenantId,
        'p_supplier_id': command.supplierId,
        'p_expected_updated_at':
            command.expectedUpdatedAt?.toUtc().toIso8601String(),
        'p_profile': command.toProfileRpcJson(),
        'p_roles': command.roles
            .map((selection) => selection.toRpcJson())
            .toList(growable: false),
        'p_capabilities': command.capabilities
            .map((selection) => selection.toRpcJson())
            .toList(growable: false),
        'p_tags': command.tags
            .map((selection) => selection.toRpcJson())
            .toList(growable: false),
      },
    );
    return _responseMap(response, 'save_supplier_relationship_profile');
  }

  @override
  Future<Map<String, dynamic>> updateOcrTemplate({
    required String tenantId,
    required UpdateSupplierOcrTemplateCommand command,
  }) async {
    final response = await _client.rpc(
      'update_supplier_ocr_template',
      params: {
        'p_tenant_id': tenantId,
        'p_supplier_id': command.supplierId,
        'p_expected_updated_at':
            command.expectedUpdatedAt.toUtc().toIso8601String(),
        'p_operation_id': command.operationId,
        'p_ocr_template': command.template.toJson(),
      },
    );
    return _responseMap(response, 'update_supplier_ocr_template');
  }

  @override
  Future<Map<String, dynamic>> updateSalesRep({
    required String tenantId,
    required UpdateSupplierSalesRepCommand command,
  }) async {
    final response = await _client.rpc(
      'update_supplier_sales_rep',
      params: {
        'p_tenant_id': tenantId,
        'p_supplier_id': command.supplierId,
        'p_expected_updated_at':
            command.expectedUpdatedAt.toUtc().toIso8601String(),
        'p_operation_id': command.operationId,
        'p_sales_rep': command.toJson(),
      },
    );
    return _responseMap(response, 'update_supplier_sales_rep');
  }

  @override
  Future<Map<String, dynamic>> saveContact({
    required String tenantId,
    required SaveSupplierContactCommand command,
  }) async {
    final response = await _client.rpc(
      'save_supplier_contact',
      params: {
        'p_tenant_id': tenantId,
        'p_supplier_id': command.supplierId,
        'p_contact_id': command.contactId,
        'p_expected_updated_at':
            command.expectedUpdatedAt?.toUtc().toIso8601String(),
        'p_operation_id': command.operationId,
        'p_contact': command.toJson(),
      },
    );
    return _responseMap(response, 'save_supplier_contact');
  }

  @override
  Future<Map<String, dynamic>> setContactStatus({
    required String tenantId,
    required SetSupplierContactStatusCommand command,
  }) async {
    final response = await _client.rpc(
      'set_supplier_contact_status',
      params: {
        'p_tenant_id': tenantId,
        'p_supplier_id': command.supplierId,
        'p_contact_id': command.contactId,
        'p_expected_updated_at':
            command.expectedUpdatedAt.toUtc().toIso8601String(),
        'p_operation_id': command.operationId,
        'p_is_active': command.isActive,
      },
    );
    return _responseMap(response, 'set_supplier_contact_status');
  }

  /// La imagen del proveedor es una columna simple de `suppliers` cubierta
  /// por la política de tenant: se escribe directo, sin recibo, porque
  /// reemplazarla dos veces deja el mismo estado.
  @override
  Future<Map<String, dynamic>> updateImageUrl({
    required String tenantId,
    required String supplierId,
    required String? imageUrl,
  }) async {
    final response = await _client
        .from('suppliers')
        .update({'image_url': imageUrl})
        .eq('tenant_id', tenantId)
        .eq('id', supplierId)
        .select('id, tenant_id, image_url')
        .single();
    return _responseMap(response, 'update_supplier_image');
  }

  @override
  Future<Map<String, dynamic>> createEngagement({
    required String tenantId,
    required CreateSupplierEngagementCommand command,
  }) async {
    final response = await _client.rpc(
      'create_supplier_engagement',
      params: {
        'p_tenant_id': tenantId,
        'p_supplier_id': command.supplierId,
        'p_engagement': {
          ...command.engagement.toRpcJson(),
          'operation_id': command.operationId,
        },
        'p_initial_version':
            command.initialVersion.toRpcJson(includeEffectiveFrom: true),
      },
    );
    return _responseMap(response, 'create_supplier_engagement');
  }

  @override
  Future<Map<String, dynamic>> updateEngagementShell({
    required String tenantId,
    required UpdateSupplierEngagementShellCommand command,
  }) async {
    final response = await _client.rpc(
      'update_supplier_engagement_shell',
      params: {
        'p_tenant_id': tenantId,
        'p_engagement_id': command.engagementId,
        'p_expected_updated_at':
            command.expectedUpdatedAt.toUtc().toIso8601String(),
        'p_engagement': command.engagement.toRpcJson(),
      },
    );
    return _responseMap(response, 'update_supplier_engagement_shell');
  }

  @override
  Future<Map<String, dynamic>> appendEngagementVersion({
    required String tenantId,
    required AppendSupplierEngagementVersionCommand command,
  }) async {
    final response = await _client.rpc(
      'append_supplier_engagement_version',
      params: {
        'p_tenant_id': tenantId,
        'p_engagement_id': command.engagementId,
        'p_effective_from': _databaseDate(command.version.effectiveFrom),
        'p_version': {
          ...command.version.toRpcJson(includeEffectiveFrom: false),
          'operation_id': command.operationId,
        },
      },
    );
    return _responseMap(response, 'append_supplier_engagement_version');
  }

  @override
  Future<Map<String, dynamic>> createAccountingPolicy({
    required String tenantId,
    required CreateSupplierAccountingPolicyCommand command,
  }) async {
    final response = await _client.rpc(
      'create_supplier_accounting_policy',
      params: {
        'p_tenant_id': tenantId,
        'p_supplier_id': command.supplierId,
        'p_policy': {
          ...command.policy.toRpcJson(),
          'operation_id': command.operationId,
        },
        'p_initial_version':
            command.initialVersion.toRpcJson(includeEffectiveFrom: true),
        'p_rules': command.rules
            .map((rule) => rule.toRpcJson())
            .toList(growable: false),
      },
    );
    return _responseMap(response, 'create_supplier_accounting_policy');
  }

  @override
  Future<Map<String, dynamic>> updateAccountingPolicyShell({
    required String tenantId,
    required UpdateSupplierAccountingPolicyShellCommand command,
  }) async {
    final response = await _client.rpc(
      'update_supplier_accounting_policy_shell',
      params: {
        'p_tenant_id': tenantId,
        'p_policy_id': command.policyId,
        'p_expected_updated_at':
            command.expectedUpdatedAt.toUtc().toIso8601String(),
        'p_policy': command.policy.toRpcJson(),
      },
    );
    return _responseMap(response, 'update_supplier_accounting_policy_shell');
  }

  @override
  Future<Map<String, dynamic>> appendAccountingPolicyVersion({
    required String tenantId,
    required AppendSupplierAccountingPolicyVersionCommand command,
  }) async {
    final response = await _client.rpc(
      'append_supplier_accounting_policy_version',
      params: {
        'p_tenant_id': tenantId,
        'p_policy_id': command.policyId,
        'p_effective_from': _databaseDate(command.version.effectiveFrom),
        'p_version': {
          ...command.version.toRpcJson(includeEffectiveFrom: false),
          'operation_id': command.operationId,
        },
        'p_rules': command.rules
            .map((rule) => rule.toRpcJson())
            .toList(growable: false),
      },
    );
    return _responseMap(
      response,
      'append_supplier_accounting_policy_version',
    );
  }

  @override
  Future<Map<String, dynamic>> appendAccountingEvidence({
    required String tenantId,
    required AppendSupplierAccountingEvidenceCommand command,
  }) async {
    final response = await _client.rpc(
      'append_supplier_accounting_evidence',
      params: {
        'p_tenant_id': tenantId,
        'p_supplier_id': command.supplierId,
        'p_payload': command.toRpcJson(),
      },
    );
    return _responseMap(response, 'append_supplier_accounting_evidence');
  }

  @override
  Future<Map<String, dynamic>> upsertClassificationDefinition({
    required String tenantId,
    required UpsertSupplierClassificationDefinitionCommand command,
  }) async {
    final response = await _client.rpc(
      'upsert_supplier_classification_definition_v2',
      params: {
        'p_tenant_id': tenantId,
        'p_vocabulary': command.vocabulary,
        'p_definition': command.toRpcJson(),
        'p_operation_id': command.operationId,
        'p_expected_updated_at':
            command.expectedUpdatedAt?.toUtc().toIso8601String(),
      },
    );
    return _responseMap(
      response,
      'upsert_supplier_classification_definition_v2',
    );
  }

  @override
  Future<Map<String, dynamic>> reviewClassificationCandidate({
    required String tenantId,
    required ReviewSupplierClassificationCandidateCommand command,
  }) async {
    final response = await _client.rpc(
      'review_supplier_classification_candidate',
      params: {
        'p_tenant_id': tenantId,
        'p_candidate_id': command.candidateId,
        'p_decision': command.decision.name,
        'p_canonical_code': command.normalizedCanonicalCode,
        'p_rationale': command.normalizedRationale,
      },
    );
    return _responseMap(
      response,
      'review_supplier_classification_candidate',
    );
  }
}

class SupabaseLegacySupplierReadRepository
    implements LegacySupplierReadRepository {
  SupabaseLegacySupplierReadRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<legacy.Supplier>> fetchPage({
    required String tenantId,
    required bool activeOnly,
    required int offset,
    required int limit,
  }) async {
    dynamic query = _client
        .from('suppliers')
        .select(legacy.Supplier.secretFreeSelect)
        .eq('tenant_id', tenantId);
    if (activeOnly) query = query.eq('is_active', true);
    final response =
        await query.order('name').order('id').range(offset, offset + limit - 1);
    return _rows(response)
        .map(legacy.Supplier.fromJson)
        .toList(growable: false);
  }

  @override
  Future<legacy.Supplier?> fetchOne({
    required String tenantId,
    required String supplierId,
  }) async {
    final response = await _client
        .from('suppliers')
        .select(legacy.Supplier.secretFreeSelect)
        .eq('tenant_id', tenantId)
        .eq('id', supplierId)
        .maybeSingle();
    if (response == null) return null;
    return legacy.Supplier.fromJson(Map<String, dynamic>.from(response));
  }
}

class SupabaseSupplierRelationshipRepository
    implements SupplierRelationshipRepository {
  SupabaseSupplierRelationshipRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  static const profileSelect =
      'tenant_id,supplier_id,party_id,party_kind,display_name,legal_name,'
      'trade_name,country_code,party_notes,party_metadata,tax_identifier_id,'
      'tax_identifier,tax_country_code,is_active,email,phone,website,'
      'contact_person,address,city,region,comuna,legacy_type,payment_terms,'
      'notes,aliases,default_tax_treatment,has_credential_reference,'
      'has_portal_credential,'
      'relationship_roles,relationship_capabilities,relationship_tags,'
      'active_engagement_count,active_policy_count,effective_business_date,'
      'service_relationship_summary,'
      'recognized_document_count,'
      'validation_issue_count,validation_incidents,data_completeness_status,'
      'classification_status,accounting_policy_status,created_at,updated_at';
  static const definitionSelect =
      'id,tenant_id,code,label,description,aliases,is_active,is_system,'
      'metadata,created_at,updated_at';
  static const operationalNatureDefinitionSelect =
      'id,tenant_id,code,label,nature_group,description,aliases,is_active,'
      'is_system,metadata,created_at,updated_at';
  static const classificationCandidateSelect =
      'tenant_id,candidate_id,supplier_id,supplier_display_name,source_kind,'
      'source_id,source_value,target_vocabulary,suggested_code,suggested_label,'
      'status,rationale,reviewed_by,reviewed_at,metadata,created_at,updated_at';
  static const identifierSelect =
      'id,tenant_id,party_id,identifier_kind,country_code,normalized_value,'
      'display_value,is_primary,valid_from,valid_to,metadata,created_at,'
      'updated_at';
  static const roleSelect =
      'id,tenant_id,supplier_id,role_code,valid_from,valid_to,'
      'assignment_source,metadata,created_at,updated_at';
  static const capabilitySelect =
      'id,tenant_id,supplier_id,capability_code,valid_from,valid_to,'
      'assignment_source,metadata,created_at,updated_at';
  static const tagSelect =
      'id,tenant_id,supplier_id,tag_code,label,valid_from,valid_to,'
      'assignment_source,metadata,created_at,updated_at';
  static const engagementSelect =
      'id,tenant_id,supplier_id,site_id,engagement_kind,code,name,status,'
      'starts_on,ends_on,operation_id,metadata,created_at,updated_at';
  static const engagementVersionSelect =
      'id,tenant_id,engagement_id,version_number,effective_from,effective_to,'
      'external_reference,service_identifier,billing_cycle,currency_code,'
      'expected_amount,due_day,portal_url,operation_id,terms,created_at,'
      'updated_at';
  static const siteSelect =
      'id,tenant_id,code,name,site_kind,address,city,region,comuna,country_code,'
      'is_active,metadata,created_at,updated_at';
  static const activeBusinessSiteSelect =
      'tenant_id,site_id,code,name,site_kind,address,city,region,comuna,'
      'country_code,metadata,created_at,updated_at';
  static const policySelect =
      'id,tenant_id,supplier_id,engagement_id,code,name,status,priority,'
      'allow_exact_autofill,operation_id,created_at,updated_at';
  static const policyVersionSelect =
      'id,tenant_id,policy_id,version_number,effective_from,effective_to,'
      'operational_nature_code,legacy_expense_category_id,debit_account_id,'
      'liability_account_id,tax_treatment,expected_document_type,'
      'currency_code,line_nature,operation_id,posture';
  static const ruleSelect =
      'id,tenant_id,policy_version_id,rule_kind,operator,operand,priority,'
      'is_active';
  static const evidenceSelect =
      'id,tenant_id,supplier_id,policy_version_id,rule_id,source_type,'
      'source_id,source_line_id,decision,operational_nature_code,'
      'operational_nature_label,debit_account_id,debit_account_code,'
      'liability_account_id,liability_account_code,'
      'legacy_expense_category_id,legacy_expense_category_name,rationale,'
      'evidence,operation_id,applied_at';
  static const receivedTaxDocumentSelect =
      'id,tenant_id,issuer_party_id,supplier_id,purchase_invoice_id,'
      'document_type_code,normalized_folio,display_folio,issued_on,received_at,'
      'currency_code,net_amount,exempt_amount,tax_amount,total_amount,status,'
      'source,metadata,created_at,updated_at';
  static const economicSummarySelect =
      'tenant_id,supplier_id,party_id,currency_code,purchase_document_count,'
      'purchase_gross_amount,purchase_paid_amount,purchase_balance_amount,'
      'purchase_payment_count,'
      'expense_document_count,expense_gross_amount,expense_paid_amount,'
      'expense_balance_amount,expense_payment_count,payment_count,'
      'total_document_count,traced_document_count,untraced_document_count,'
      'unclassified_line_count,payment_state_anomaly_count,'
      'expense_payment_ledger_gap_document_count,'
      'excluded_lifecycle_document_count,provenance_coverage,'
      'provenance_status,data_quality_status,last_activity_at';
  static const economicTimelineSelect =
      'tenant_id,supplier_id,party_id,event_type,event_id,event_date,'
      'document_number,event_status,payment_status,currency_code,gross_amount,'
      'paid_amount,balance_amount,payment_count,is_recognized,'
      'data_quality_status,source_document_id,metadata';

  static const _pageSize = 500;

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> fetchProfileRows({
    required String tenantId,
    required bool activeOnly,
    required int offset,
    required int limit,
  }) async {
    dynamic query = _client
        .from('supplier_profile_read_model')
        .select(profileSelect)
        .eq('tenant_id', tenantId);
    if (activeOnly) query = query.eq('is_active', true);
    final response = await query
        .order('display_name')
        .order('supplier_id')
        .range(offset, offset + limit - 1);
    return _rows(response);
  }

  @override
  Future<Map<String, dynamic>?> fetchProfileRow({
    required String tenantId,
    required String supplierId,
  }) async {
    final response = await _client
        .from('supplier_profile_read_model')
        .select(profileSelect)
        .eq('tenant_id', tenantId)
        .eq('supplier_id', supplierId)
        .maybeSingle();
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  @override
  Future<Map<String, dynamic>?> fetchExternalPartyRow({
    required String tenantId,
    required String partyId,
  }) async {
    final response = await _client
        .from('external_parties')
        .select(
          'id,tenant_id,party_kind,display_name,legal_name,trade_name,'
          'country_code,is_active,notes,metadata,created_at,updated_at',
        )
        .eq('tenant_id', tenantId)
        .eq('id', partyId)
        .maybeSingle();
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDefinitionRows({
    required String tenantId,
    required SupplierClassificationDefinitionKind kind,
    required bool activeOnly,
  }) async {
    final table = switch (kind) {
      SupplierClassificationDefinitionKind.role => 'supplier_role_definitions',
      SupplierClassificationDefinitionKind.capability =>
        'supplier_capability_definitions',
      SupplierClassificationDefinitionKind.tag => 'supplier_tag_definitions',
      SupplierClassificationDefinitionKind.operationalNature =>
        'operational_nature_definitions',
    };
    final select =
        kind == SupplierClassificationDefinitionKind.operationalNature
            ? operationalNatureDefinitionSelect
            : definitionSelect;
    return _fetchAll((from, to) async {
      dynamic query =
          _client.from(table).select(select).eq('tenant_id', tenantId);
      if (activeOnly) query = query.eq('is_active', true);
      return query.order('label').order('id').range(from, to);
    });
  }

  @override
  Future<List<Map<String, dynamic>>> fetchClassificationCandidateRows({
    required String tenantId,
    required SupplierClassificationCandidateStatus? status,
    required SupplierClassificationDefinitionKind? targetVocabulary,
    required String? supplierId,
    required int offset,
    required int limit,
  }) async {
    dynamic query = _client
        .from('supplier_classification_candidate_read_model')
        .select(classificationCandidateSelect)
        .eq('tenant_id', tenantId);
    if (status != null) query = query.eq('status', status.name);
    if (targetVocabulary != null) {
      query = query.eq('target_vocabulary', targetVocabulary.dbValue);
    }
    if (supplierId != null) query = query.eq('supplier_id', supplierId);
    final response = await query
        .order('created_at', ascending: false)
        .order('candidate_id')
        .range(offset, offset + limit - 1);
    return _rows(response);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchIdentifierRows({
    required String tenantId,
    required String partyId,
  }) {
    return _fetchAll(
      (from, to) => _client
          .from('external_party_identifiers')
          .select(identifierSelect)
          .eq('tenant_id', tenantId)
          .eq('party_id', partyId)
          .order('valid_from', ascending: false)
          .order('id')
          .range(from, to),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRoleRows({
    required String tenantId,
    required String supplierId,
  }) {
    return _fetchAll(
      (from, to) => _client
          .from('supplier_relationship_roles')
          .select(roleSelect)
          .eq('tenant_id', tenantId)
          .eq('supplier_id', supplierId)
          .order('valid_from', ascending: false)
          .order('id')
          .range(from, to),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCapabilityRows({
    required String tenantId,
    required String supplierId,
  }) {
    return _fetchAll(
      (from, to) => _client
          .from('supplier_relationship_capabilities')
          .select(capabilitySelect)
          .eq('tenant_id', tenantId)
          .eq('supplier_id', supplierId)
          .order('valid_from', ascending: false)
          .order('id')
          .range(from, to),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchContactRows({
    required String tenantId,
    required String supplierId,
  }) {
    return _fetchAll(
      (from, to) => _client
          .from('supplier_contacts')
          .select(
            'id, tenant_id, supplier_id, name, role, phone, email, notes, '
            'is_primary, is_active, deactivated_at, source, updated_at',
          )
          .eq('tenant_id', tenantId)
          .eq('supplier_id', supplierId)
          .order('is_primary', ascending: false)
          .order('is_active', ascending: false)
          .order('name')
          .order('id')
          .range(from, to),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTagRows({
    required String tenantId,
    required String supplierId,
  }) {
    return _fetchAll(
      (from, to) => _client
          .from('supplier_relationship_tags')
          .select(tagSelect)
          .eq('tenant_id', tenantId)
          .eq('supplier_id', supplierId)
          .order('valid_from', ascending: false)
          .order('id')
          .range(from, to),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEngagementRows({
    required String tenantId,
    required String supplierId,
  }) {
    return _fetchAll(
      (from, to) => _client
          .from('supplier_engagements')
          .select(engagementSelect)
          .eq('tenant_id', tenantId)
          .eq('supplier_id', supplierId)
          .order('name')
          .order('id')
          .range(from, to),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEngagementVersionRows({
    required String tenantId,
    required List<String> engagementIds,
  }) {
    if (engagementIds.isEmpty) return Future.value(const []);
    return _fetchAll(
      (from, to) => _client
          .from('supplier_engagement_versions')
          .select(engagementVersionSelect)
          .eq('tenant_id', tenantId)
          .inFilter('engagement_id', engagementIds)
          .order('engagement_id')
          .order('version_number')
          .order('id')
          .range(from, to),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSiteRows({
    required String tenantId,
    required List<String> siteIds,
  }) {
    if (siteIds.isEmpty) return Future.value(const []);
    return _fetchAll(
      (from, to) => _client
          .from('business_sites')
          .select(siteSelect)
          .eq('tenant_id', tenantId)
          .inFilter('id', siteIds)
          .order('name')
          .order('id')
          .range(from, to),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchBusinessSiteRows({
    required String tenantId,
  }) {
    return _fetchAll(
      (from, to) => _client
          .from('active_business_site_read_model')
          .select(activeBusinessSiteSelect)
          .eq('tenant_id', tenantId)
          .order('name')
          .order('site_id')
          .range(from, to),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPolicyRows({
    required String tenantId,
    required String supplierId,
  }) {
    return _fetchAll(
      (from, to) => _client
          .from('supplier_accounting_policies')
          .select(policySelect)
          .eq('tenant_id', tenantId)
          .eq('supplier_id', supplierId)
          .order('priority')
          .order('id')
          .range(from, to),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPolicyVersionRows({
    required String tenantId,
    required List<String> policyIds,
  }) {
    if (policyIds.isEmpty) return Future.value(const []);
    return _fetchAll(
      (from, to) => _client
          .from('supplier_accounting_policy_versions')
          .select(policyVersionSelect)
          .eq('tenant_id', tenantId)
          .inFilter('policy_id', policyIds)
          .order('policy_id')
          .order('version_number')
          .order('id')
          .range(from, to),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRuleRows({
    required String tenantId,
    required List<String> policyVersionIds,
  }) {
    if (policyVersionIds.isEmpty) return Future.value(const []);
    return _fetchAll(
      (from, to) => _client
          .from('supplier_accounting_rules')
          .select(ruleSelect)
          .eq('tenant_id', tenantId)
          .inFilter('policy_version_id', policyVersionIds)
          .order('priority')
          .order('id')
          .range(from, to),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEvidenceRows({
    required String tenantId,
    required String supplierId,
    required int limit,
  }) async {
    final response = await _client
        .from('supplier_accounting_evidence')
        .select(evidenceSelect)
        .eq('tenant_id', tenantId)
        .eq('supplier_id', supplierId)
        .order('applied_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    return _rows(response);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchReceivedTaxDocumentRows({
    required String tenantId,
    required String supplierId,
  }) {
    return _fetchAll(
      (from, to) => _client
          .from('received_tax_documents')
          .select(receivedTaxDocumentSelect)
          .eq('tenant_id', tenantId)
          .eq('supplier_id', supplierId)
          .order('issued_on', ascending: false)
          .order('id', ascending: false)
          .range(from, to),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEconomicSummaryRows({
    required String tenantId,
    required String supplierId,
  }) {
    return _fetchAll(
      (from, to) => _client
          .from('supplier_economic_summary_read_model')
          .select(economicSummarySelect)
          .eq('tenant_id', tenantId)
          .eq('supplier_id', supplierId)
          .order('currency_code')
          .range(from, to),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchEconomicTimelineRows({
    required String tenantId,
    required String supplierId,
    required bool recognizedOnly,
    required int offset,
    required int limit,
  }) async {
    if (!recognizedOnly) {
      throw ArgumentError.value(
        recognizedOnly,
        'recognizedOnly',
        'The canonical supplier timeline publishes recognized activity only',
      );
    }
    final response = await _client
        .from('supplier_economic_read_model')
        .select(economicTimelineSelect)
        .eq('tenant_id', tenantId)
        .eq('supplier_id', supplierId)
        .eq('is_recognized', true)
        .order('event_date', ascending: false)
        .order('event_id', ascending: false)
        .range(offset, offset + limit - 1);
    return _rows(response);
  }

  Future<List<Map<String, dynamic>>> _fetchAll(
    Future<dynamic> Function(int from, int to) fetchPage,
  ) async {
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = _rows(await fetchPage(offset, offset + _pageSize - 1));
      rows.addAll(page);
      if (page.length < _pageSize) return rows;
      offset += page.length;
    }
  }
}

class SupplierRelationshipService {
  SupplierRelationshipService({
    required TenantService tenantService,
    SupplierRelationshipRepository? repository,
    LegacySupplierReadRepository? legacyRepository,
    SupplierRelationshipCommandGateway? commandGateway,
  })  : _tenantService = tenantService,
        _repository = repository ?? SupabaseSupplierRelationshipRepository(),
        _legacyRepository =
            legacyRepository ?? SupabaseLegacySupplierReadRepository(),
        _commandGateway = commandGateway;

  static const defaultPageSize = 100;
  static const maximumPageSize = 500;
  static const recentEvidenceLimit = 100;

  /// Sube en uno cada vez que un comando de proveedor confirma en el
  /// servidor. Quien cachea proveedores (`PurchaseService`) lo escucha para
  /// invalidar: así la ficha no necesita conocer a sus lectores.
  final ValueNotifier<int> supplierCommandRevision = ValueNotifier<int>(0);

  final TenantService _tenantService;
  final SupplierRelationshipRepository _repository;
  final LegacySupplierReadRepository _legacyRepository;
  SupplierRelationshipCommandGateway? _commandGateway;
  final AuthorityCacheScope _authorityScope = AuthorityCacheScope();

  Future<SupplierProfileCommandResult> saveProfile(
    SaveSupplierRelationshipProfileCommand command,
  ) async {
    final lease = await _requireLease();
    _verifyProfileCommand(command, lease.scope.tenantId);
    try {
      final gateway =
          _commandGateway ??= SupabaseSupplierRelationshipCommandGateway();
      final response = await gateway.saveProfile(
        tenantId: lease.scope.tenantId,
        command: command,
      );
      await _verifyLease(lease);
      _verifyRows([response], lease.scope.tenantId);
      final result = SupplierProfile.fromJson(response);
      final expectedSupplierId = command.supplierId;
      if (expectedSupplierId != null &&
          result.relationship.id != expectedSupplierId) {
        throw const AuthorityScopeChangedException();
      }
      return SupplierProfileCommandResult(
        profile: result,
        idempotentReplay: response['idempotent_replay'] as bool? ?? false,
      );
    } catch (error) {
      if (_isFoundationUnavailable(error)) {
        throw const SupplierFoundationUnavailable();
      }
      rethrow;
    }
  }

  Future<SupplierOcrTemplateCommandResult> updateOcrTemplate(
    UpdateSupplierOcrTemplateCommand command,
  ) async {
    final lease = await _requireLease();
    final response = await _runCommand(
      lease,
      (gateway) => gateway.updateOcrTemplate(
        tenantId: lease.scope.tenantId,
        command: command,
      ),
    );
    final result = SupplierOcrTemplateCommandResult.fromJson(response);
    if (result.tenantId != lease.scope.tenantId ||
        result.supplierId != command.supplierId ||
        result.operationId != command.operationId) {
      throw const AuthorityScopeChangedException();
    }
    return result;
  }

  Future<SupplierSalesRepCommandResult> updateSalesRep(
    UpdateSupplierSalesRepCommand command,
  ) async {
    final lease = await _requireLease();
    final response = await _runCommand(
      lease,
      (gateway) => gateway.updateSalesRep(
        tenantId: lease.scope.tenantId,
        command: command,
      ),
    );
    final result = SupplierSalesRepCommandResult.fromJson(response);
    if (result.tenantId != lease.scope.tenantId ||
        result.supplierId != command.supplierId ||
        result.operationId != command.operationId) {
      throw const AuthorityScopeChangedException();
    }
    return result;
  }

  /// Las personas de un proveedor, principal primero, activas antes que
  /// desactivadas.
  Future<List<SupplierContact>> listSupplierContacts(String supplierId) async {
    _requireId(supplierId, 'supplierId');
    final lease = await _requireLease();
    final rows = await _repository.fetchContactRows(
      tenantId: lease.scope.tenantId,
      supplierId: supplierId,
    );
    await _verifyLease(lease);
    _verifyRows(rows, lease.scope.tenantId);
    return rows.map(SupplierContact.fromJson).toList(growable: false);
  }

  Future<SupplierContactCommandResult> saveSupplierContact(
    SaveSupplierContactCommand command,
  ) async {
    final lease = await _requireLease();
    final response = await _runCommand(
      lease,
      (gateway) => gateway.saveContact(
        tenantId: lease.scope.tenantId,
        command: command,
      ),
    );
    return _verifiedContactResult(
        response, lease, command.supplierId, command.operationId);
  }

  Future<SupplierContactCommandResult> setSupplierContactStatus(
    SetSupplierContactStatusCommand command,
  ) async {
    final lease = await _requireLease();
    final response = await _runCommand(
      lease,
      (gateway) => gateway.setContactStatus(
        tenantId: lease.scope.tenantId,
        command: command,
      ),
    );
    return _verifiedContactResult(
        response, lease, command.supplierId, command.operationId);
  }

  /// Cambia o quita la imagen del proveedor. Sube la revisión de comandos
  /// como cualquier otra escritura, para que las cachés relean.
  Future<void> updateSupplierImage(String supplierId, String? imageUrl) async {
    _requireId(supplierId, 'supplierId');
    final lease = await _requireLease();
    final response = await _runCommand(
      lease,
      (gateway) => gateway.updateImageUrl(
        tenantId: lease.scope.tenantId,
        supplierId: supplierId,
        imageUrl: imageUrl,
      ),
    );
    if (response['tenant_id']?.toString() != lease.scope.tenantId ||
        response['id']?.toString() != supplierId) {
      throw const AuthorityScopeChangedException();
    }
  }

  SupplierContactCommandResult _verifiedContactResult(
    Map<String, dynamic> response,
    AuthorityCacheLease lease,
    String supplierId,
    String operationId,
  ) {
    final result = SupplierContactCommandResult.fromJson(response);
    if (result.tenantId != lease.scope.tenantId ||
        result.supplierId != supplierId ||
        result.operationId != operationId) {
      throw const AuthorityScopeChangedException();
    }
    return result;
  }

  Future<SupplierEngagementCommandResult> createEngagement(
    CreateSupplierEngagementCommand command,
  ) async {
    final lease = await _requireLease();
    final response = await _runCommand(
      lease,
      (gateway) => gateway.createEngagement(
        tenantId: lease.scope.tenantId,
        command: command,
      ),
    );
    final result = SupplierEngagementCommandResult.fromJson(response);
    _verifyEngagementResult(
      result,
      tenantId: lease.scope.tenantId,
      supplierId: command.supplierId,
    );
    _verifyOperationId(command.operationId, result.appliedVersion.operationId);
    _verifyOperationId(command.operationId, result.engagement.operationId);
    return result;
  }

  Future<SupplierEngagementCommandResult> updateEngagementShell(
    UpdateSupplierEngagementShellCommand command,
  ) async {
    final lease = await _requireLease();
    final response = await _runCommand(
      lease,
      (gateway) => gateway.updateEngagementShell(
        tenantId: lease.scope.tenantId,
        command: command,
      ),
    );
    final result = SupplierEngagementCommandResult.fromJson(response);
    _verifyEngagementResult(
      result,
      tenantId: lease.scope.tenantId,
      engagementId: command.engagementId,
    );
    return result;
  }

  Future<SupplierEngagementCommandResult> appendEngagementVersion(
    AppendSupplierEngagementVersionCommand command,
  ) async {
    final lease = await _requireLease();
    final response = await _runCommand(
      lease,
      (gateway) => gateway.appendEngagementVersion(
        tenantId: lease.scope.tenantId,
        command: command,
      ),
    );
    final result = SupplierEngagementCommandResult.fromJson(response);
    _verifyEngagementResult(
      result,
      tenantId: lease.scope.tenantId,
      engagementId: command.engagementId,
    );
    _verifyOperationId(command.operationId, result.appliedVersion.operationId);
    return result;
  }

  Future<SupplierAccountingPolicyCommandResult> createAccountingPolicy(
    CreateSupplierAccountingPolicyCommand command,
  ) async {
    final lease = await _requireLease();
    _verifyOperationalNature(
      command.initialVersion.operationalNature,
      lease.scope.tenantId,
    );
    final response = await _runCommand(
      lease,
      (gateway) => gateway.createAccountingPolicy(
        tenantId: lease.scope.tenantId,
        command: command,
      ),
    );
    final result = SupplierAccountingPolicyCommandResult.fromJson(
      response,
      operationalNature: command.initialVersion.operationalNature,
    );
    _verifyPolicyResult(
      result,
      tenantId: lease.scope.tenantId,
      supplierId: command.supplierId,
    );
    _verifyOperationId(command.operationId, result.appliedVersion.operationId);
    _verifyOperationId(command.operationId, result.policy.operationId);
    return result;
  }

  Future<SupplierAccountingPolicyCommandResult> updateAccountingPolicyShell(
    UpdateSupplierAccountingPolicyShellCommand command,
  ) async {
    final lease = await _requireLease();
    final response = await _runCommand(
      lease,
      (gateway) => gateway.updateAccountingPolicyShell(
        tenantId: lease.scope.tenantId,
        command: command,
      ),
    );
    final result = SupplierAccountingPolicyCommandResult.fromJson(response);
    _verifyPolicyResult(
      result,
      tenantId: lease.scope.tenantId,
      policyId: command.policyId,
    );
    return result;
  }

  Future<SupplierAccountingPolicyCommandResult> appendAccountingPolicyVersion(
    AppendSupplierAccountingPolicyVersionCommand command,
  ) async {
    final lease = await _requireLease();
    _verifyOperationalNature(
      command.version.operationalNature,
      lease.scope.tenantId,
    );
    final response = await _runCommand(
      lease,
      (gateway) => gateway.appendAccountingPolicyVersion(
        tenantId: lease.scope.tenantId,
        command: command,
      ),
    );
    final result = SupplierAccountingPolicyCommandResult.fromJson(
      response,
      operationalNature: command.version.operationalNature,
    );
    _verifyPolicyResult(
      result,
      tenantId: lease.scope.tenantId,
      policyId: command.policyId,
    );
    _verifyOperationId(command.operationId, result.appliedVersion.operationId);
    return result;
  }

  Future<SupplierAccountingEvidenceSummary> appendAccountingEvidence(
    AppendSupplierAccountingEvidenceCommand command,
  ) async {
    final lease = await _requireLease();
    _verifyOperationalNature(
      command.operationalNature,
      lease.scope.tenantId,
    );
    final response = await _runCommand(
      lease,
      (gateway) => gateway.appendAccountingEvidence(
        tenantId: lease.scope.tenantId,
        command: command,
      ),
    );
    _verifyRows([response], lease.scope.tenantId);
    _verifySupplierRows([response], command.supplierId);
    final result = SupplierAccountingEvidenceSummary.fromJson(response);
    if (result.operationId != command.operationId ||
        result.operationalNatureCode != command.operationalNature.code ||
        result.operationalNatureLabel != command.operationalNature.label) {
      throw const AuthorityScopeChangedException();
    }
    return result;
  }

  Future<SupplierClassificationDefinitionCommandResult>
      upsertClassificationDefinition(
    UpsertSupplierClassificationDefinitionCommand command,
  ) async {
    final lease = await _requireLease();
    final response = await _runCommand(
      lease,
      (gateway) => gateway.upsertClassificationDefinition(
        tenantId: lease.scope.tenantId,
        command: command,
      ),
    );
    final result = SupplierClassificationDefinitionCommandResult.fromJson(
      response,
      kind: command.kind,
    );
    _verifyRows(
      [
        result.appliedDefinition,
        result.currentDefinition,
      ]
          .map((definition) => {
                'tenant_id': definition.tenantId,
              })
          .toList(growable: false),
      lease.scope.tenantId,
    );
    if (result.operationId != command.operationId ||
        result.vocabulary != command.kind ||
        result.appliedDefinition.code != command.code ||
        result.currentDefinition.code != command.code) {
      throw const AuthorityScopeChangedException();
    }
    return result;
  }

  Future<SupplierClassificationCandidateReviewResult>
      reviewClassificationCandidate(
    ReviewSupplierClassificationCandidateCommand command,
  ) async {
    final lease = await _requireLease();
    final response = await _runCommand(
      lease,
      (gateway) => gateway.reviewClassificationCandidate(
        tenantId: lease.scope.tenantId,
        command: command,
      ),
    );
    _verifyRows([response], lease.scope.tenantId);
    final candidate = SupplierClassificationCandidate.fromJson(response);
    final expectedCode =
        command.decision == SupplierClassificationCandidateStatus.confirmed
            ? command.normalizedCanonicalCode
            : null;
    if (candidate.id != command.candidateId ||
        candidate.status != command.decision ||
        candidate.suggestedCode != expectedCode ||
        candidate.rationale != command.normalizedRationale) {
      throw const AuthorityScopeChangedException();
    }
    return SupplierClassificationCandidateReviewResult(
      candidate: candidate,
      idempotentReplay: response['idempotent_replay'] as bool? ?? false,
    );
  }

  Future<Map<String, dynamic>> _runCommand(
    AuthorityCacheLease lease,
    Future<Map<String, dynamic>> Function(
      SupplierRelationshipCommandGateway gateway,
    ) operation,
  ) async {
    try {
      final gateway =
          _commandGateway ??= SupabaseSupplierRelationshipCommandGateway();
      final response = await operation(gateway);
      await _verifyLease(lease);
      // Confirmó en el servidor: quien cachee proveedores debe releer.
      supplierCommandRevision.value++;
      return response;
    } catch (error) {
      if (_isFoundationUnavailable(error)) {
        throw const SupplierFoundationUnavailable();
      }
      rethrow;
    }
  }

  void _verifyProfileCommand(
    SaveSupplierRelationshipProfileCommand command,
    String tenantId,
  ) {
    if (command.party.tenantId != tenantId ||
        command.relationship.tenantId != tenantId) {
      throw const AuthorityScopeChangedException();
    }
    final supplierId = command.supplierId;
    if (supplierId != null && command.expectedUpdatedAt == null) {
      throw ArgumentError.value(
        command.expectedUpdatedAt,
        'command.expectedUpdatedAt',
        'Required when updating an existing supplier',
      );
    }
    if (supplierId != null && command.relationship.id != supplierId) {
      throw ArgumentError.value(
        command.relationship.id,
        'command.relationship.id',
        'Must match supplierId',
      );
    }
    if (command.relationship.externalPartyId != command.party.id) {
      throw ArgumentError.value(
        command.relationship.externalPartyId,
        'command.relationship.externalPartyId',
        'Must match party.id',
      );
    }
    _verifySelections(
      command.roles,
      SupplierClassificationDefinitionKind.role,
      tenantId,
    );
    _verifySelections(
      command.capabilities,
      SupplierClassificationDefinitionKind.capability,
      tenantId,
    );
    _verifySelections(
      command.tags,
      SupplierClassificationDefinitionKind.tag,
      tenantId,
    );
  }

  Future<List<SupplierProfile>> listSupplierProfiles({
    bool activeOnly = false,
  }) async {
    final lease = await _requireLease();
    final profiles = <SupplierProfile>[];
    var offset = 0;
    while (true) {
      final page = await _listSupplierProfilesPage(
        lease: lease,
        activeOnly: activeOnly,
        offset: offset,
        limit: maximumPageSize,
      );
      profiles.addAll(page.items);
      final next = page.nextOffset;
      if (next == null) return List.unmodifiable(profiles);
      offset = next;
    }
  }

  Future<SupplierProfilePage> listSupplierProfilesPage({
    bool activeOnly = false,
    int offset = 0,
    int limit = defaultPageSize,
  }) async {
    _validatePage(offset: offset, limit: limit);
    final lease = await _requireLease();
    return _listSupplierProfilesPage(
      lease: lease,
      activeOnly: activeOnly,
      offset: offset,
      limit: limit,
    );
  }

  Future<SupplierProfilePage> _listSupplierProfilesPage({
    required AuthorityCacheLease lease,
    required bool activeOnly,
    required int offset,
    required int limit,
  }) async {
    await _verifyLease(lease);
    try {
      final rows = await _repository.fetchProfileRows(
        tenantId: lease.scope.tenantId,
        activeOnly: activeOnly,
        offset: offset,
        limit: limit + 1,
      );
      await _verifyLease(lease);
      _verifyRows(rows, lease.scope.tenantId);
      final hasMore = rows.length > limit;
      final pageRows = hasMore ? rows.take(limit) : rows;
      return SupplierProfilePage(
        items: pageRows.map(SupplierProfile.fromJson).toList(growable: false),
        offset: offset,
        limit: limit,
        hasMore: hasMore,
      );
    } catch (error) {
      if (!_isProfileListTransitionFallback(error)) rethrow;
      final suppliers = await _legacyRepository.fetchPage(
        tenantId: lease.scope.tenantId,
        activeOnly: activeOnly,
        offset: offset,
        limit: limit + 1,
      );
      await _verifyLease(lease);
      _verifyLegacySuppliers(suppliers, lease.scope.tenantId);
      final hasMore = suppliers.length > limit;
      final page = hasMore ? suppliers.take(limit) : suppliers;
      return SupplierProfilePage(
        items:
            page.map(LegacySupplierAdapter.toProfile).toList(growable: false),
        offset: offset,
        limit: limit,
        hasMore: hasMore,
      );
    }
  }

  Future<SupplierClassificationCatalog> getClassificationCatalog({
    bool activeOnly = true,
  }) async {
    final lease = await _requireLease();
    try {
      final results = await Future.wait([
        for (final kind in SupplierClassificationDefinitionKind.values)
          _repository.fetchDefinitionRows(
            tenantId: lease.scope.tenantId,
            kind: kind,
            activeOnly: activeOnly,
          ),
      ]);
      await _verifyLease(lease);
      _verifyRows(results.expand((rows) => rows), lease.scope.tenantId);
      List<SupplierClassificationDefinition> parse(
        SupplierClassificationDefinitionKind kind,
      ) {
        final rows = results[kind.index];
        return rows
            .map(
              (row) => SupplierClassificationDefinition.fromJson(
                row,
                kind: kind,
              ),
            )
            .toList(growable: false);
      }

      return SupplierClassificationCatalog(
        roles: parse(SupplierClassificationDefinitionKind.role),
        capabilities: parse(
          SupplierClassificationDefinitionKind.capability,
        ),
        tags: parse(SupplierClassificationDefinitionKind.tag),
        operationalNatures: parse(
          SupplierClassificationDefinitionKind.operationalNature,
        ),
      );
    } catch (error) {
      if (!_isFoundationUnavailable(error)) rethrow;
      await _verifyLease(lease);
      return SupplierClassificationCatalog();
    }
  }

  Future<List<SupplierClassificationCandidate>> listClassificationCandidates({
    SupplierClassificationCandidateStatus? status =
        SupplierClassificationCandidateStatus.pending,
    SupplierClassificationDefinitionKind? targetVocabulary,
    String? supplierId,
  }) async {
    final normalizedSupplierId = _optionalCommandText(supplierId);
    final lease = await _requireLease();
    final candidates = <SupplierClassificationCandidate>[];
    var offset = 0;
    while (true) {
      final page = await _listClassificationCandidatesPage(
        lease: lease,
        status: status,
        targetVocabulary: targetVocabulary,
        supplierId: normalizedSupplierId,
        offset: offset,
        limit: maximumPageSize,
      );
      candidates.addAll(page.items);
      final next = page.nextOffset;
      if (next == null) return List.unmodifiable(candidates);
      offset = next;
    }
  }

  Future<SupplierClassificationCandidatePage> listClassificationCandidatesPage({
    SupplierClassificationCandidateStatus? status =
        SupplierClassificationCandidateStatus.pending,
    SupplierClassificationDefinitionKind? targetVocabulary,
    String? supplierId,
    int offset = 0,
    int limit = defaultPageSize,
  }) async {
    _validatePage(offset: offset, limit: limit);
    final normalizedSupplierId = _optionalCommandText(supplierId);
    final lease = await _requireLease();
    return _listClassificationCandidatesPage(
      lease: lease,
      status: status,
      targetVocabulary: targetVocabulary,
      supplierId: normalizedSupplierId,
      offset: offset,
      limit: limit,
    );
  }

  Future<SupplierClassificationCandidatePage>
      _listClassificationCandidatesPage({
    required AuthorityCacheLease lease,
    required SupplierClassificationCandidateStatus? status,
    required SupplierClassificationDefinitionKind? targetVocabulary,
    required String? supplierId,
    required int offset,
    required int limit,
  }) async {
    await _verifyLease(lease);
    try {
      final rows = await _repository.fetchClassificationCandidateRows(
        tenantId: lease.scope.tenantId,
        status: status,
        targetVocabulary: targetVocabulary,
        supplierId: supplierId,
        offset: offset,
        limit: limit + 1,
      );
      await _verifyLease(lease);
      _verifyRows(rows, lease.scope.tenantId);
      if (supplierId != null) {
        _verifySupplierRows(rows, supplierId);
      }
      final hasMore = rows.length > limit;
      final pageRows = hasMore ? rows.take(limit) : rows;
      return SupplierClassificationCandidatePage(
        items: pageRows
            .map(SupplierClassificationCandidate.fromJson)
            .toList(growable: false),
        offset: offset,
        limit: limit,
        hasMore: hasMore,
      );
    } catch (error) {
      if (_isFoundationUnavailable(error)) {
        throw const SupplierFoundationUnavailable();
      }
      rethrow;
    }
  }

  Future<List<BusinessSite>> listBusinessSites({
    bool activeOnly = true,
  }) async {
    if (!activeOnly) {
      throw ArgumentError.value(
        activeOnly,
        'activeOnly',
        'The canonical business-site selector publishes active sites only',
      );
    }
    final lease = await _requireLease();
    try {
      final rows = await _repository.fetchBusinessSiteRows(
        tenantId: lease.scope.tenantId,
      );
      await _verifyLease(lease);
      _verifyRows(rows, lease.scope.tenantId);
      return rows.map(BusinessSite.fromJson).toList(growable: false);
    } catch (error) {
      if (!_isFoundationUnavailable(error)) rethrow;
      await _verifyLease(lease);
      return const [];
    }
  }

  Future<SupplierProfile?> getSupplierProfile(String supplierId) async {
    _requireId(supplierId, 'supplierId');
    final lease = await _requireLease();
    try {
      return await _getFoundationProfile(lease, supplierId);
    } catch (error) {
      if (!_isFoundationUnavailable(error)) rethrow;
      final supplier = await _legacyRepository.fetchOne(
        tenantId: lease.scope.tenantId,
        supplierId: supplierId,
      );
      await _verifyLease(lease);
      if (supplier == null) return null;
      _verifyLegacySuppliers([supplier], lease.scope.tenantId);
      return LegacySupplierAdapter.toProfile(supplier);
    }
  }

  /// Las tres columnas del vendedor como claves del perfil, o `null` si la
  /// fila no se pudo leer: la ficha sigue mostrándose sin vendedor antes que
  /// no mostrarse.
  Future<Map<String, dynamic>?> _legacySalesRepRow(
    String tenantId,
    String supplierId,
  ) async {
    try {
      final supplier = await _legacyRepository.fetchOne(
        tenantId: tenantId,
        supplierId: supplierId,
      );
      if (supplier == null || supplier.tenantId != tenantId) return null;
      return <String, dynamic>{
        'sales_rep_name': supplier.salesRepName,
        'sales_rep_phone': supplier.salesRepPhone,
        'sales_rep_email': supplier.salesRepEmail,
        'image_url': supplier.imageUrl,
      };
    } catch (_) {
      return null;
    }
  }

  Future<SupplierProfile?> _getFoundationProfile(
    AuthorityCacheLease lease,
    String supplierId,
  ) async {
    final tenantId = lease.scope.tenantId;
    final base = await _repository.fetchProfileRow(
      tenantId: tenantId,
      supplierId: supplierId,
    );
    if (base == null) {
      await _verifyLease(lease);
      return null;
    }
    _verifyRows([base], tenantId);
    final partyId = _requiredRowText(base, 'party_id');

    final partyFuture = _repository.fetchExternalPartyRow(
      tenantId: tenantId,
      partyId: partyId,
    );
    // El vendedor (`sales_rep_*`) no está en la vista de perfil y no vale
    // rehacer sus 1.600 líneas por tres columnas: se lee de la fila del
    // proveedor, que ya expone el select sin secretos.
    final salesRepFuture = _legacySalesRepRow(tenantId, supplierId);
    final firstResultsFuture = Future.wait([
      _repository.fetchIdentifierRows(tenantId: tenantId, partyId: partyId),
      _repository.fetchRoleRows(tenantId: tenantId, supplierId: supplierId),
      _repository.fetchCapabilityRows(
        tenantId: tenantId,
        supplierId: supplierId,
      ),
      _repository.fetchTagRows(tenantId: tenantId, supplierId: supplierId),
      _repository.fetchEngagementRows(
        tenantId: tenantId,
        supplierId: supplierId,
      ),
      _repository.fetchPolicyRows(tenantId: tenantId, supplierId: supplierId),
      _repository.fetchReceivedTaxDocumentRows(
        tenantId: tenantId,
        supplierId: supplierId,
      ),
      _repository.fetchDefinitionRows(
        tenantId: tenantId,
        kind: SupplierClassificationDefinitionKind.role,
        activeOnly: false,
      ),
      _repository.fetchDefinitionRows(
        tenantId: tenantId,
        kind: SupplierClassificationDefinitionKind.capability,
        activeOnly: false,
      ),
      _repository.fetchDefinitionRows(
        tenantId: tenantId,
        kind: SupplierClassificationDefinitionKind.tag,
        activeOnly: false,
      ),
      _repository.fetchDefinitionRows(
        tenantId: tenantId,
        kind: SupplierClassificationDefinitionKind.operationalNature,
        activeOnly: false,
      ),
    ]);
    final externalPartyRow = await partyFuture;
    final firstResults = await firstResultsFuture;
    final identifierRows = firstResults[0];
    final roleRows = firstResults[1];
    final capabilityRows = firstResults[2];
    final tagRows = firstResults[3];
    final engagementRows = firstResults[4];
    final policyRows = firstResults[5];
    final documentRows = firstResults[6];
    final roleDefinitions = firstResults[7];
    final capabilityDefinitions = firstResults[8];
    final tagDefinitions = firstResults[9];
    final operationalNatureDefinitions = firstResults[10];

    final engagementIds = _rowIds(engagementRows);
    final policyIds = _rowIds(policyRows);
    final secondResults = await Future.wait([
      _repository.fetchEngagementVersionRows(
        tenantId: tenantId,
        engagementIds: engagementIds,
      ),
      _repository.fetchSiteRows(
        tenantId: tenantId,
        siteIds: engagementRows
            .map((row) => row['site_id']?.toString())
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList(growable: false),
      ),
      _repository.fetchPolicyVersionRows(
        tenantId: tenantId,
        policyIds: policyIds,
      ),
      _repository.fetchEvidenceRows(
        tenantId: tenantId,
        supplierId: supplierId,
        limit: recentEvidenceLimit,
      ),
    ]);
    final engagementVersionRows = secondResults[0];
    final siteRows = secondResults[1];
    final policyVersionRows = secondResults[2];
    final evidenceRows = secondResults[3];
    final ruleRows = await _repository.fetchRuleRows(
      tenantId: tenantId,
      policyVersionIds: _rowIds(policyVersionRows),
    );

    await _verifyLease(lease);
    _verifyRows(
      [
        base,
        if (externalPartyRow != null) externalPartyRow,
        ...firstResults.expand((rows) => rows),
        ...secondResults.expand((rows) => rows),
        ...ruleRows,
      ],
      tenantId,
    );
    _verifySupplierRows(
      [
        ...roleRows,
        ...capabilityRows,
        ...tagRows,
        ...engagementRows,
        ...policyRows,
        ...documentRows,
        ...evidenceRows,
      ],
      supplierId,
    );

    final salesRep = await salesRepFuture;
    final summary = SupplierProfile.fromJson({
      ...base,
      if (salesRep != null) ...salesRep,
    });
    final party = ExternalParty.fromJson({
      ...(externalPartyRow ?? base),
      'id': partyId,
      'tenant_id': tenantId,
      'aliases': base['aliases'],
      'identifiers': identifierRows,
    });
    final roleDefinitionByCode = _definitionsByCode(roleDefinitions);
    final capabilityDefinitionByCode =
        _definitionsByCode(capabilityDefinitions);
    final tagDefinitionByCode = _definitionsByCode(tagDefinitions);
    final operationalNatureDefinitionByCode =
        _definitionsByCode(operationalNatureDefinitions);
    final roleHistory = roleRows
        .map(
          (row) => SupplierRole.fromJson(
            _withDefinition(row, roleDefinitionByCode, 'role'),
          ),
        )
        .toList(growable: false);
    final capabilityHistory = capabilityRows
        .map(
          (row) => SupplierCapability.fromJson(
            _withDefinition(row, capabilityDefinitionByCode, 'capability'),
          ),
        )
        .toList(growable: false);
    final tagHistory = tagRows
        .map(
          (row) => SupplierTag.fromJson(
            _withDefinition(row, tagDefinitionByCode, 'tag'),
          ),
        )
        .toList(growable: false);
    final relationship = _relationshipWithAssignments(
      summary.relationship,
      roles: summary.relationship.roles
          .map(
            (assignment) => SupplierRole.fromJson(
              _withDefinition(
                assignment.toJson(),
                roleDefinitionByCode,
                'role',
              ),
            ),
          )
          .toList(growable: false),
      capabilities: summary.relationship.capabilities
          .map(
            (assignment) => SupplierCapability.fromJson(
              _withDefinition(
                assignment.toJson(),
                capabilityDefinitionByCode,
                'capability',
              ),
            ),
          )
          .toList(growable: false),
      tags: summary.relationship.tags
          .map(
            (assignment) => SupplierTag.fromJson(
              _withDefinition(
                assignment.toJson(),
                tagDefinitionByCode,
                'tag',
              ),
            ),
          )
          .toList(growable: false),
    );
    final engagements = engagementRows.map((row) {
      final engagementId = _requiredRowText(row, 'id');
      return SupplierEngagement.fromJson({
        ...row,
        'effective_business_date':
            summary.effectiveBusinessDate?.toIso8601String(),
        'versions': engagementVersionRows
            .where((version) => version['engagement_id'] == engagementId)
            .toList(growable: false),
      });
    }).toList(growable: false);
    final policies = policyRows.map((row) {
      final policyId = _requiredRowText(row, 'id');
      return SupplierAccountingPolicySummary.fromJson({
        ...row,
        'effective_business_date':
            summary.effectiveBusinessDate?.toIso8601String(),
        'versions': policyVersionRows
            .where((version) => version['policy_id'] == policyId)
            .map(
              (version) => _withOperationalNatureDefinition(
                version,
                operationalNatureDefinitionByCode,
              ),
            )
            .toList(growable: false),
      });
    }).toList(growable: false);
    final evidence = evidenceRows
        .map(SupplierAccountingEvidenceSummary.fromJson)
        .toList(growable: false);

    return SupplierProfile(
      party: party,
      relationship: relationship,
      sites: siteRows.map(BusinessSite.fromJson).toList(growable: false),
      engagements: engagements,
      classificationHistory: SupplierClassificationHistory(
        roles: roleHistory,
        capabilities: capabilityHistory,
        tags: tagHistory,
      ),
      accounting: SupplierAccountingProfileSummary(
        policies: policies,
        rules: ruleRows
            .map(SupplierAccountingRuleSummary.fromJson)
            .toList(growable: false),
        recentEvidence: evidence,
        observedAccountIds: evidence
            .map((item) => item.debitAccountId)
            .whereType<String>()
            .toSet()
            .toList(growable: false),
      ),
      legacyDetails: summary.legacyDetails,
      receivedTaxDocumentCount: documentRows.length,
      activeEngagementCount: summary.activeEngagementCount,
      activePolicyCount: summary.activePolicyCount,
      effectiveBusinessDate: summary.effectiveBusinessDate,
      attentionSignals: summary.attentionSignals,
    );
  }

  Future<List<SupplierEconomicSummaryReadModel>> getEconomicSummary(
    String supplierId,
  ) async {
    _requireId(supplierId, 'supplierId');
    final lease = await _requireLease();
    try {
      final rows = await _repository.fetchEconomicSummaryRows(
        tenantId: lease.scope.tenantId,
        supplierId: supplierId,
      );
      await _verifyLease(lease);
      _verifyRows(rows, lease.scope.tenantId);
      _verifySupplierRows(rows, supplierId);
      return rows
          .map(SupplierEconomicSummaryReadModel.fromJson)
          .toList(growable: false);
    } catch (error) {
      if (!_isFoundationUnavailable(error)) rethrow;
      await _verifyLease(lease);
      return const [];
    }
  }

  Future<SupplierEconomicTimelinePage> getEconomicTimelinePage(
    String supplierId, {
    int offset = 0,
    int limit = defaultPageSize,
  }) async {
    _requireId(supplierId, 'supplierId');
    _validatePage(offset: offset, limit: limit);
    final lease = await _requireLease();
    try {
      final rows = await _repository.fetchEconomicTimelineRows(
        tenantId: lease.scope.tenantId,
        supplierId: supplierId,
        recognizedOnly: true,
        offset: offset,
        limit: limit + 1,
      );
      await _verifyLease(lease);
      _verifyRows(rows, lease.scope.tenantId);
      _verifySupplierRows(rows, supplierId);
      final hasMore = rows.length > limit;
      final pageRows =
          hasMore ? rows.take(limit).toList(growable: false) : rows;
      return SupplierEconomicTimelinePage(
        timeline: SupplierEconomicReadModel.fromRows(
          pageRows,
          tenantId: lease.scope.tenantId,
          supplierId: supplierId,
        ),
        offset: offset,
        limit: limit,
        hasMore: hasMore,
      );
    } catch (error) {
      if (!_isFoundationUnavailable(error)) rethrow;
      await _verifyLease(lease);
      return SupplierEconomicTimelinePage(
        timeline: SupplierEconomicReadModel(
          tenantId: lease.scope.tenantId,
          supplierId: supplierId,
        ),
        offset: offset,
        limit: limit,
        hasMore: false,
      );
    }
  }

  Future<List<ReceivedTaxDocument>> listReceivedTaxDocuments(
    String supplierId,
  ) async {
    _requireId(supplierId, 'supplierId');
    final lease = await _requireLease();
    try {
      final rows = await _repository.fetchReceivedTaxDocumentRows(
        tenantId: lease.scope.tenantId,
        supplierId: supplierId,
      );
      await _verifyLease(lease);
      _verifyRows(rows, lease.scope.tenantId);
      _verifySupplierRows(rows, supplierId);
      return rows.map(ReceivedTaxDocument.fromJson).toList(growable: false);
    } catch (error) {
      if (!_isFoundationUnavailable(error)) rethrow;
      await _verifyLease(lease);
      return const [];
    }
  }

  Future<AuthorityCacheLease> _requireLease() async {
    final userId = _tenantService.currentAuthUserId;
    if (userId == null || userId.isEmpty) {
      _authorityScope.resolve(userId: null, tenantId: null);
      throw const AuthorityScopeChangedException();
    }
    final tenantId = await _tenantService.getTenantId();
    if (_tenantService.currentAuthUserId != userId ||
        tenantId == null ||
        tenantId.isEmpty) {
      _authorityScope.resolve(userId: null, tenantId: null);
      throw const AuthorityScopeChangedException();
    }
    final resolution = _authorityScope.resolve(
      userId: userId,
      tenantId: tenantId,
    );
    if (!resolution.isAccepted) {
      throw const AuthorityScopeChangedException();
    }
    final lease = _authorityScope.capture();
    if (lease == null) throw const AuthorityScopeChangedException();
    return lease;
  }

  Future<void> _verifyLease(AuthorityCacheLease lease) async {
    final userId = _tenantService.currentAuthUserId;
    final tenantId = await _tenantService.getTenantId();
    final resolution = _authorityScope.resolve(
      userId: userId,
      tenantId: tenantId,
    );
    if (!resolution.isAccepted || !_authorityScope.owns(lease)) {
      throw const AuthorityScopeChangedException();
    }
  }
}

class SupplierFoundationUnavailable implements Exception {
  const SupplierFoundationUnavailable();

  @override
  String toString() =>
      'Supplier foundation is unavailable; legacy reads are read-only';
}

SupplierRelationship _relationshipWithAssignments(
  SupplierRelationship source, {
  required List<SupplierRole> roles,
  required List<SupplierCapability> capabilities,
  required List<SupplierTag> tags,
}) {
  return SupplierRelationship(
    id: source.id,
    tenantId: source.tenantId,
    externalPartyId: source.externalPartyId,
    name: source.name,
    status: source.status,
    email: source.email,
    phone: source.phone,
    contactPerson: source.contactPerson,
    website: source.website,
    notes: source.notes,
    paymentTermsCode: source.paymentTermsCode,
    serviceRelationshipSummary: source.serviceRelationshipSummary,
    roles: roles,
    capabilities: capabilities,
    tags: tags,
    hasCredentialReference: source.hasCredentialReference,
    createdAt: source.createdAt,
    updatedAt: source.updatedAt,
  );
}

Map<String, Map<String, dynamic>> _definitionsByCode(
  List<Map<String, dynamic>> rows,
) {
  return {
    for (final row in rows)
      if ((row['code']?.toString() ?? '').isNotEmpty)
        row['code'].toString(): row,
  };
}

Map<String, dynamic> _withDefinition(
  Map<String, dynamic> assignment,
  Map<String, Map<String, dynamic>> definitions,
  String prefix,
) {
  final code = assignment['${prefix}_code']?.toString() ?? '';
  final definition = definitions[code];
  return {
    ...assignment,
    '${prefix}_definition_id': definition?['id'],
    '${prefix}_label': definition?['label'],
  };
}

Map<String, dynamic> _withOperationalNatureDefinition(
  Map<String, dynamic> version,
  Map<String, Map<String, dynamic>> definitions,
) {
  final code = version['operational_nature_code']?.toString() ?? '';
  final definition = definitions[code];
  return {
    ...version,
    'operational_nature_definition_id': definition?['id'],
    'operational_nature_label': definition?['label'],
    'operational_nature_group': definition?['nature_group'],
  };
}

List<String> _rowIds(List<Map<String, dynamic>> rows) {
  return rows
      .map((row) => row['id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toList(growable: false);
}

void _verifyRows(Iterable<Map<String, dynamic>> rows, String tenantId) {
  if (rows.any((row) => row['tenant_id']?.toString() != tenantId)) {
    throw const AuthorityScopeChangedException();
  }
}

void _verifySupplierRows(
  Iterable<Map<String, dynamic>> rows,
  String supplierId,
) {
  if (rows.any((row) {
    final value = row['supplier_id'];
    return value != null && value.toString() != supplierId;
  })) {
    throw const AuthorityScopeChangedException();
  }
}

void _verifyLegacySuppliers(
  Iterable<legacy.Supplier> suppliers,
  String tenantId,
) {
  if (suppliers.any((supplier) => supplier.tenantId != tenantId)) {
    throw const AuthorityScopeChangedException();
  }
}

bool _isFoundationUnavailable(Object error) {
  if (error is SupplierFoundationUnavailable) return true;
  if (error is! PostgrestException) return false;
  if (error.code == '42P01' ||
      error.code == 'PGRST202' ||
      error.code == 'PGRST205') {
    return true;
  }
  final message = error.message.toLowerCase();
  return message.contains('supplier_profile_read_model') &&
      (message.contains('not found') || message.contains('does not exist'));
}

bool _isProfileListTransitionFallback(Object error) {
  if (_isFoundationUnavailable(error)) return true;
  return error is PostgrestException && error.code == '57014';
}

void _verifySelections(
  List<SupplierClassificationSelection> selections,
  SupplierClassificationDefinitionKind expectedKind,
  String tenantId,
) {
  final definitionIds = <String>{};
  final codes = <String>{};
  for (final selection in selections) {
    final definition = selection.definition;
    if (definition.tenantId != tenantId ||
        definition.kind != expectedKind ||
        !definition.isActive ||
        !definitionIds.add(definition.id) ||
        !codes.add(definition.code)) {
      throw ArgumentError.value(
        selections,
        expectedKind.name,
        'Assignments require unique active definitions from this tenant',
      );
    }
  }
}

void _verifyOperationalNature(
  SupplierClassificationDefinition definition,
  String tenantId,
) {
  if (definition.tenantId != tenantId ||
      definition.kind !=
          SupplierClassificationDefinitionKind.operationalNature ||
      !definition.isActive) {
    throw ArgumentError.value(
      definition,
      'operationalNature',
      'Requires an active operational-nature definition from this tenant',
    );
  }
}

void _verifyEngagementResult(
  SupplierEngagementCommandResult result, {
  required String tenantId,
  String? supplierId,
  String? engagementId,
}) {
  final engagement = result.engagement;
  final expectedId = engagementId ?? engagement.id;
  if (engagement.tenantId != tenantId ||
      engagement.id != expectedId ||
      (supplierId != null && engagement.supplierId != supplierId) ||
      result.appliedVersion.tenantId != tenantId ||
      result.appliedVersion.engagementId != expectedId ||
      result.currentVersion.tenantId != tenantId ||
      result.currentVersion.engagementId != expectedId ||
      (result.closedVersion != null &&
          (result.closedVersion!.tenantId != tenantId ||
              result.closedVersion!.engagementId != expectedId))) {
    throw const AuthorityScopeChangedException();
  }
}

void _verifyPolicyResult(
  SupplierAccountingPolicyCommandResult result, {
  required String tenantId,
  String? supplierId,
  String? policyId,
}) {
  final policy = result.policy;
  final expectedId = policyId ?? policy.id;
  if (policy.tenantId != tenantId ||
      policy.id != expectedId ||
      (supplierId != null && policy.supplierId != supplierId) ||
      result.appliedVersion.tenantId != tenantId ||
      result.appliedVersion.policyId != expectedId ||
      result.currentVersion.tenantId != tenantId ||
      result.currentVersion.policyId != expectedId ||
      (result.closedVersion != null &&
          (result.closedVersion!.tenantId != tenantId ||
              result.closedVersion!.policyId != expectedId)) ||
      result.rules.any(
        (rule) =>
            rule.tenantId != tenantId ||
            rule.policyVersionId != result.appliedVersion.id,
      )) {
    throw const AuthorityScopeChangedException();
  }
}

Map<String, dynamic> _sanitizePublicMap(Map<String, dynamic> source) {
  final safe = <String, dynamic>{};
  for (final entry in source.entries) {
    if (_isReservedPublicKey(entry.key)) {
      continue;
    }
    safe[entry.key] = _sanitizePublicValue(entry.value);
  }
  return Map.unmodifiable(safe);
}

bool _isReservedPublicKey(String key) {
  final normalized = key.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();
  return RegExp(
    'password|secret|token|apikey|privatekey|passcode|authorization|bearer|credential',
  ).hasMatch(normalized);
}

dynamic _sanitizePublicValue(dynamic value) {
  if (value is Map) {
    return _sanitizePublicMap(
      value.map((key, child) => MapEntry(key.toString(), child)),
    );
  }
  if (value is Iterable) {
    return List.unmodifiable(value.map(_sanitizePublicValue));
  }
  return value;
}

Map<String, dynamic> _responseMap(dynamic response, String operation) {
  if (response is! Map) throw FormatException('Invalid $operation response');
  return Map<String, dynamic>.from(response);
}

Map<String, dynamic> _requiredNestedMap(
  Map<String, dynamic> source,
  String field,
) {
  final result = _optionalNestedMap(source[field]);
  if (result == null) throw FormatException('Missing $field');
  return result;
}

Map<String, dynamic>? _optionalNestedMap(dynamic value) {
  if (value == null) return null;
  if (value is! Map) throw const FormatException('Expected JSON object');
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> _mapRows(dynamic value) {
  if (value == null) return const [];
  if (value is! List) throw const FormatException('Expected JSON array');
  return value.map((item) {
    if (item is! Map) throw const FormatException('Expected JSON object');
    return Map<String, dynamic>.from(item);
  }).toList(growable: false);
}

void _validatePage({required int offset, required int limit}) {
  if (offset < 0) throw RangeError.range(offset, 0, null, 'offset');
  if (limit < 1 || limit > SupplierRelationshipService.maximumPageSize) {
    throw RangeError.range(
      limit,
      1,
      SupplierRelationshipService.maximumPageSize,
      'limit',
    );
  }
}

void _requireId(String value, String name) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, name, 'Required');
}

void _requireCommandText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Required');
  }
}

void _validateOperationId(String value) {
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)) {
    throw ArgumentError.value(value, 'operationId', 'Must be a UUID');
  }
}

void _verifyOperationId(String expected, String? actual) {
  if (actual?.toLowerCase() != expected.toLowerCase()) {
    throw const AuthorityScopeChangedException();
  }
}

String? _optionalCommandText(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String _databaseDate(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-'
      '${twoDigits(value.month)}-${twoDigits(value.day)}';
}

String _requiredRowText(Map<String, dynamic> row, String field) {
  final value = row[field]?.toString().trim();
  if (value == null || value.isEmpty) throw FormatException('Missing $field');
  return value;
}

List<Map<String, dynamic>> _rows(dynamic response) {
  if (response is! List) {
    throw const FormatException('Expected supplier relationship row list');
  }
  return response
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}
