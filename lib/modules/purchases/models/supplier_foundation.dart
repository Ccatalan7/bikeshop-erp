import 'package:flutter/foundation.dart';

import '../../../shared/models/supplier.dart' show PaymentTerms, SupplierType;
import '../../../shared/models/tax_treatment.dart';

/// The legal nature of an external party. This is identity data and must not
/// be used as a shortcut for accounting or purchase behavior.
enum ExternalPartyKind {
  organization,
  person,
  publicAuthority,
  other;

  static ExternalPartyKind fromJson(dynamic value) {
    return switch (value?.toString()) {
      'organization' || 'company' => ExternalPartyKind.organization,
      'person' || 'individual' => ExternalPartyKind.person,
      'government_entity' ||
      'public_authority' ||
      'publicAuthority' =>
        ExternalPartyKind.publicAuthority,
      _ => ExternalPartyKind.other,
    };
  }

  String get dbValue => switch (this) {
        ExternalPartyKind.publicAuthority => 'government_entity',
        _ => name,
      };
}

enum SupplierRelationshipStatus {
  active,
  inactive;

  static SupplierRelationshipStatus fromJson(dynamic value) {
    return switch (value?.toString()) {
      'inactive' => SupplierRelationshipStatus.inactive,
      _ => SupplierRelationshipStatus.active,
    };
  }
}

enum SupplierRoleKind {
  goodsVendor,
  serviceProvider,
  logisticsProvider,
  utilityProvider,
  landlord,
  governmentAuthority,
  digitalPlatform,
  other;

  static SupplierRoleKind fromJson(dynamic value) {
    return switch (value?.toString()) {
      'goods_vendor' || 'goodsVendor' => SupplierRoleKind.goodsVendor,
      'service_provider' ||
      'serviceProvider' =>
        SupplierRoleKind.serviceProvider,
      'logistics_provider' ||
      'carrier' ||
      'transport' =>
        SupplierRoleKind.logisticsProvider,
      'utility_provider' ||
      'utilityProvider' =>
        SupplierRoleKind.utilityProvider,
      'digital_platform' ||
      'digitalPlatform' =>
        SupplierRoleKind.digitalPlatform,
      'landlord' || 'lessor' => SupplierRoleKind.landlord,
      'government_authority' ||
      'tax_authority' ||
      'taxAuthority' =>
        SupplierRoleKind.governmentAuthority,
      _ => SupplierRoleKind.other,
    };
  }

  String get dbValue => switch (this) {
        SupplierRoleKind.goodsVendor => 'goods_vendor',
        SupplierRoleKind.serviceProvider => 'service_provider',
        SupplierRoleKind.logisticsProvider => 'logistics_provider',
        SupplierRoleKind.utilityProvider => 'utility_provider',
        SupplierRoleKind.governmentAuthority => 'government_authority',
        SupplierRoleKind.digitalPlatform => 'digital_platform',
        _ => name,
      };
}

enum SupplierCapabilityKind {
  purchaseInvoices,
  inventoryGoods,
  workshopConsumables,
  freightTransport,
  digitalServices,
  utilities,
  rentLease,
  taxPayments,
  credentialPortal,
  other;

  static SupplierCapabilityKind fromJson(dynamic value) {
    return switch (value?.toString()) {
      'purchase_invoices' => SupplierCapabilityKind.purchaseInvoices,
      'inventory_goods' => SupplierCapabilityKind.inventoryGoods,
      'workshop_consumables' => SupplierCapabilityKind.workshopConsumables,
      'freight_transport' => SupplierCapabilityKind.freightTransport,
      'digital_services' => SupplierCapabilityKind.digitalServices,
      'utilities' => SupplierCapabilityKind.utilities,
      'rent_lease' => SupplierCapabilityKind.rentLease,
      'tax_payments' => SupplierCapabilityKind.taxPayments,
      'credential_portal' => SupplierCapabilityKind.credentialPortal,
      _ => SupplierCapabilityKind.other,
    };
  }

  String get dbValue => switch (this) {
        SupplierCapabilityKind.purchaseInvoices => 'purchase_invoices',
        SupplierCapabilityKind.inventoryGoods => 'inventory_goods',
        SupplierCapabilityKind.workshopConsumables => 'workshop_consumables',
        SupplierCapabilityKind.freightTransport => 'freight_transport',
        SupplierCapabilityKind.digitalServices => 'digital_services',
        SupplierCapabilityKind.rentLease => 'rent_lease',
        SupplierCapabilityKind.taxPayments => 'tax_payments',
        SupplierCapabilityKind.credentialPortal => 'credential_portal',
        _ => name,
      };
}

enum SupplierEngagementKind {
  contract,
  serviceAccount,
  subscription,
  lease,
  utility,
  taxObligation,
  portal,
  other;

  static SupplierEngagementKind fromJson(dynamic value) {
    return switch (value?.toString()) {
      'contract' ||
      'transport_agreement' ||
      'transportAgreement' =>
        SupplierEngagementKind.contract,
      'service_account' ||
      'serviceAccount' =>
        SupplierEngagementKind.serviceAccount,
      'subscription' ||
      'domain_registration' ||
      'domainRegistration' =>
        SupplierEngagementKind.subscription,
      'lease' => SupplierEngagementKind.lease,
      'utility' ||
      'utility_account' ||
      'utilityAccount' =>
        SupplierEngagementKind.utility,
      'tax_obligation' ||
      'taxObligation' =>
        SupplierEngagementKind.taxObligation,
      'portal' => SupplierEngagementKind.portal,
      _ => SupplierEngagementKind.other,
    };
  }

  String get dbValue => switch (this) {
        SupplierEngagementKind.serviceAccount => 'service_account',
        SupplierEngagementKind.taxObligation => 'tax_obligation',
        _ => name,
      };
}

enum SupplierEngagementStatus {
  draft,
  active,
  suspended,
  ended;

  static SupplierEngagementStatus fromJson(dynamic value) {
    return switch (value?.toString()) {
      'draft' => SupplierEngagementStatus.draft,
      'ended' => SupplierEngagementStatus.ended,
      'suspended' || 'inactive' => SupplierEngagementStatus.suspended,
      _ => SupplierEngagementStatus.active,
    };
  }
}

enum SupplierEngagementBillingCycle {
  free,
  monthly,
  bimonthly,
  quarterly,
  semiannual,
  annual,
  irregular,
  none;

  static SupplierEngagementBillingCycle fromJson(dynamic value) {
    return SupplierEngagementBillingCycle.values.firstWhere(
      (item) => item.name == value?.toString(),
      orElse: () => SupplierEngagementBillingCycle.none,
    );
  }
}

enum SupplierAccountingPolicyStatus {
  draft,
  active,
  retired;

  static SupplierAccountingPolicyStatus fromJson(dynamic value) {
    return switch (value?.toString()) {
      'active' => SupplierAccountingPolicyStatus.active,
      'superseded' => SupplierAccountingPolicyStatus.retired,
      'retired' => SupplierAccountingPolicyStatus.retired,
      _ => SupplierAccountingPolicyStatus.draft,
    };
  }
}

enum SupplierAccountingTaxTreatment {
  noTax,
  taxIncluded,
  exempt,
  notApplicable;

  String get dbValue => switch (this) {
        SupplierAccountingTaxTreatment.noTax => 'no_tax',
        SupplierAccountingTaxTreatment.taxIncluded => 'tax_included',
        SupplierAccountingTaxTreatment.notApplicable => 'not_applicable',
        _ => name,
      };

  static SupplierAccountingTaxTreatment fromJson(dynamic value) {
    return switch (value?.toString()) {
      'no_tax' => SupplierAccountingTaxTreatment.noTax,
      'tax_included' => SupplierAccountingTaxTreatment.taxIncluded,
      'exempt' => SupplierAccountingTaxTreatment.exempt,
      _ => SupplierAccountingTaxTreatment.notApplicable,
    };
  }
}

enum SupplierAccountingLineNature {
  inventory,
  workshopConsumable,
  operatingExpense,
  service,
  freight,
  capitalAsset,
  tax,
  discount,
  other;

  String get dbValue => switch (this) {
        SupplierAccountingLineNature.workshopConsumable =>
          'workshop_consumable',
        SupplierAccountingLineNature.operatingExpense => 'operating_expense',
        SupplierAccountingLineNature.capitalAsset => 'capital_asset',
        _ => name,
      };

  static SupplierAccountingLineNature fromJson(dynamic value) {
    return switch (value?.toString()) {
      'inventory' => SupplierAccountingLineNature.inventory,
      'workshop_consumable' => SupplierAccountingLineNature.workshopConsumable,
      'operating_expense' => SupplierAccountingLineNature.operatingExpense,
      'service' => SupplierAccountingLineNature.service,
      'freight' => SupplierAccountingLineNature.freight,
      'capital_asset' => SupplierAccountingLineNature.capitalAsset,
      'tax' => SupplierAccountingLineNature.tax,
      'discount' => SupplierAccountingLineNature.discount,
      _ => SupplierAccountingLineNature.other,
    };
  }
}

enum SupplierAccountingRuleKind {
  documentType,
  issuerIdentifier,
  description,
  lineDescription,
  engagement,
  amountRange,
  manual;

  String get dbValue => switch (this) {
        SupplierAccountingRuleKind.documentType => 'document_type',
        SupplierAccountingRuleKind.issuerIdentifier => 'issuer_identifier',
        SupplierAccountingRuleKind.lineDescription => 'line_description',
        SupplierAccountingRuleKind.amountRange => 'amount_range',
        _ => name,
      };
}

enum SupplierAccountingRuleOperator {
  equals,
  contains,
  prefix,
  regex,
  between,
  present,
}

enum SupplierAccountingEvidenceSourceType {
  purchaseInvoice,
  purchaseInvoiceLine,
  expense,
  expenseLine,
  receivedTaxDocument,
  manual;

  String get dbValue => switch (this) {
        SupplierAccountingEvidenceSourceType.purchaseInvoice =>
          'purchase_invoice',
        SupplierAccountingEvidenceSourceType.purchaseInvoiceLine =>
          'purchase_invoice_line',
        SupplierAccountingEvidenceSourceType.expenseLine => 'expense_line',
        SupplierAccountingEvidenceSourceType.receivedTaxDocument =>
          'received_tax_document',
        _ => name,
      };

  bool get requiresLineId =>
      this == SupplierAccountingEvidenceSourceType.purchaseInvoiceLine ||
      this == SupplierAccountingEvidenceSourceType.expenseLine;
}

enum SupplierAccountingEvidenceDecision {
  suggested,
  accepted,
  overridden,
  rejected,
  autoFilled;

  static SupplierAccountingEvidenceDecision fromJson(dynamic value) {
    return switch (value?.toString()) {
      'suggested' => SupplierAccountingEvidenceDecision.suggested,
      'accepted' => SupplierAccountingEvidenceDecision.accepted,
      'overridden' => SupplierAccountingEvidenceDecision.overridden,
      'rejected' => SupplierAccountingEvidenceDecision.rejected,
      'auto_filled' ||
      'autoFilled' =>
        SupplierAccountingEvidenceDecision.autoFilled,
      _ => SupplierAccountingEvidenceDecision.suggested,
    };
  }

  String get dbValue => switch (this) {
        SupplierAccountingEvidenceDecision.autoFilled => 'auto_filled',
        _ => name,
      };
}

enum ReceivedTaxDocumentKind {
  invoice,
  exemptInvoice,
  creditNote,
  debitNote,
  receipt,
  other;

  static ReceivedTaxDocumentKind fromJson(dynamic value) {
    return switch (value?.toString()) {
      '33' || '46' || 'invoice' => ReceivedTaxDocumentKind.invoice,
      '34' ||
      'exempt_invoice' ||
      'exemptInvoice' =>
        ReceivedTaxDocumentKind.exemptInvoice,
      '61' ||
      'credit_note' ||
      'creditNote' =>
        ReceivedTaxDocumentKind.creditNote,
      '56' || 'debit_note' || 'debitNote' => ReceivedTaxDocumentKind.debitNote,
      '39' || '41' || 'receipt' => ReceivedTaxDocumentKind.receipt,
      'other' => ReceivedTaxDocumentKind.other,
      _ => ReceivedTaxDocumentKind.other,
    };
  }

  String get dbValue => switch (this) {
        ReceivedTaxDocumentKind.exemptInvoice => 'exempt_invoice',
        ReceivedTaxDocumentKind.creditNote => 'credit_note',
        ReceivedTaxDocumentKind.debitNote => 'debit_note',
        _ => name,
      };
}

enum ReceivedTaxDocumentStatus {
  captured,
  validated,
  linked,
  voided;

  static ReceivedTaxDocumentStatus fromJson(dynamic value) {
    return switch (value?.toString()) {
      'validated' => ReceivedTaxDocumentStatus.validated,
      'linked' || 'accounted' => ReceivedTaxDocumentStatus.linked,
      'voided' => ReceivedTaxDocumentStatus.voided,
      _ => ReceivedTaxDocumentStatus.captured,
    };
  }
}

enum SupplierEconomicActivityKind {
  purchaseInvoice,
  expense,
  purchasePayment,
  expensePayment,
  purchaseCreditNote,
  purchaseSupplierRefund,
  creditNote,
  suppliedProduct,
  other;

  static SupplierEconomicActivityKind fromJson(dynamic value) {
    return switch (value?.toString()) {
      'purchase_invoice' ||
      'purchaseInvoice' =>
        SupplierEconomicActivityKind.purchaseInvoice,
      'expense' => SupplierEconomicActivityKind.expense,
      'purchase_payment' ||
      'purchasePayment' =>
        SupplierEconomicActivityKind.purchasePayment,
      'expense_payment' ||
      'expensePayment' =>
        SupplierEconomicActivityKind.expensePayment,
      'purchase_credit_note' ||
      'purchaseCreditNote' =>
        SupplierEconomicActivityKind.purchaseCreditNote,
      'purchase_supplier_refund' ||
      'purchaseSupplierRefund' =>
        SupplierEconomicActivityKind.purchaseSupplierRefund,
      'credit_note' || 'creditNote' => SupplierEconomicActivityKind.creditNote,
      'supplied_product' ||
      'suppliedProduct' =>
        SupplierEconomicActivityKind.suppliedProduct,
      _ => SupplierEconomicActivityKind.other,
    };
  }
}

enum SupplierProfileDataCompletenessStatus {
  known,
  partial,
  unknown;

  static SupplierProfileDataCompletenessStatus fromJson(dynamic value) {
    return switch (value?.toString()) {
      'known' => SupplierProfileDataCompletenessStatus.known,
      'partial' => SupplierProfileDataCompletenessStatus.partial,
      _ => SupplierProfileDataCompletenessStatus.unknown,
    };
  }
}

enum SupplierProfileClassificationStatus {
  classified,
  unclassified,
  notApplicable,
  unknown;

  static SupplierProfileClassificationStatus fromJson(dynamic value) {
    return switch (value?.toString()) {
      'classified' => SupplierProfileClassificationStatus.classified,
      'unclassified' => SupplierProfileClassificationStatus.unclassified,
      'not_applicable' => SupplierProfileClassificationStatus.notApplicable,
      _ => SupplierProfileClassificationStatus.unknown,
    };
  }
}

enum SupplierProfileAccountingPolicyStatus {
  configured,
  missingPolicy,
  notApplicable,
  unknown;

  static SupplierProfileAccountingPolicyStatus fromJson(dynamic value) {
    return switch (value?.toString()) {
      'configured' => SupplierProfileAccountingPolicyStatus.configured,
      'missing_policy' => SupplierProfileAccountingPolicyStatus.missingPolicy,
      'not_applicable' => SupplierProfileAccountingPolicyStatus.notApplicable,
      _ => SupplierProfileAccountingPolicyStatus.unknown,
    };
  }
}

enum SupplierValidationIncidentSeverity {
  info,
  warning,
  error,
  unknown;

  static SupplierValidationIncidentSeverity fromJson(dynamic value) {
    return switch (value?.toString()) {
      'info' => SupplierValidationIncidentSeverity.info,
      'warning' => SupplierValidationIncidentSeverity.warning,
      'error' => SupplierValidationIncidentSeverity.error,
      _ => SupplierValidationIncidentSeverity.unknown,
    };
  }
}

enum SupplierValidationIncidentScopeType {
  supplier,
  identity,
  engagement,
  accountingPolicy,
  credential,
  taxDocument,
  unknown;

  static SupplierValidationIncidentScopeType fromJson(dynamic value) {
    return switch (value?.toString()) {
      'supplier' => SupplierValidationIncidentScopeType.supplier,
      'identity' => SupplierValidationIncidentScopeType.identity,
      'engagement' => SupplierValidationIncidentScopeType.engagement,
      'accounting_policy' =>
        SupplierValidationIncidentScopeType.accountingPolicy,
      'credential' => SupplierValidationIncidentScopeType.credential,
      'tax_document' => SupplierValidationIncidentScopeType.taxDocument,
      _ => SupplierValidationIncidentScopeType.unknown,
    };
  }
}

enum SupplierValidationIncidentSource {
  migrationValidation,
  domainValidation,
  integrationValidation,
  unknown;

  static SupplierValidationIncidentSource fromJson(dynamic value) {
    return switch (value?.toString()) {
      'migration_validation' =>
        SupplierValidationIncidentSource.migrationValidation,
      'domain_validation' => SupplierValidationIncidentSource.domainValidation,
      'integration_validation' =>
        SupplierValidationIncidentSource.integrationValidation,
      _ => SupplierValidationIncidentSource.unknown,
    };
  }
}

enum SupplierValidationIncidentStatus {
  pending,
  resolved,
  dismissed,
  unknown;

  static SupplierValidationIncidentStatus fromJson(dynamic value) {
    return switch (value?.toString()) {
      'pending' => SupplierValidationIncidentStatus.pending,
      'resolved' => SupplierValidationIncidentStatus.resolved,
      'dismissed' => SupplierValidationIncidentStatus.dismissed,
      _ => SupplierValidationIncidentStatus.unknown,
    };
  }
}

enum SupplierEconomicDataQualityStatus {
  complete,
  needsReview,
  notRecognized,
  notApplicable,
  lifecycleOnly,
  unknown;

  static SupplierEconomicDataQualityStatus fromJson(dynamic value) {
    return switch (value?.toString()) {
      'complete' => SupplierEconomicDataQualityStatus.complete,
      'needs_review' => SupplierEconomicDataQualityStatus.needsReview,
      'not_recognized' => SupplierEconomicDataQualityStatus.notRecognized,
      'not_applicable' => SupplierEconomicDataQualityStatus.notApplicable,
      'lifecycle_only' => SupplierEconomicDataQualityStatus.lifecycleOnly,
      _ => SupplierEconomicDataQualityStatus.unknown,
    };
  }
}

/// Indicates whether a profile came from the complete foundation or from the
/// secret-free legacy compatibility projection used before the migration is
/// available. Legacy profiles are intentionally read-only for classifications.
enum SupplierProfileDataSource {
  foundation,
  legacyReadOnly,
}

enum SupplierClassificationDefinitionKind {
  role,
  capability,
  tag,
  operationalNature;

  static SupplierClassificationDefinitionKind fromJson(dynamic value) {
    return switch (value?.toString()) {
      'role' => SupplierClassificationDefinitionKind.role,
      'capability' => SupplierClassificationDefinitionKind.capability,
      'tag' => SupplierClassificationDefinitionKind.tag,
      'operational_nature' ||
      'operationalNature' =>
        SupplierClassificationDefinitionKind.operationalNature,
      _ => throw const FormatException(
          'Invalid supplier classification vocabulary',
        ),
    };
  }

  String get dbValue => switch (this) {
        SupplierClassificationDefinitionKind.operationalNature =>
          'operational_nature',
        _ => name,
      };
}

/// Tenant-owned vocabulary entry. Assignment commands reference [id]; [code]
/// is a stable read value, never free text authored by the supplier form.
@immutable
class SupplierClassificationDefinition {
  SupplierClassificationDefinition({
    required this.id,
    required this.tenantId,
    required this.kind,
    required this.code,
    required this.label,
    this.description,
    this.natureGroup,
    List<String> aliases = const [],
    this.isActive = true,
    this.isSystem = false,
    Map<String, dynamic> publicMetadata = const {},
    this.createdAt,
    this.updatedAt,
  })  : aliases = List.unmodifiable(aliases),
        publicMetadata = _publicMap(publicMetadata);

  factory SupplierClassificationDefinition.fromJson(
    Map<String, dynamic> json, {
    required SupplierClassificationDefinitionKind kind,
  }) {
    return SupplierClassificationDefinition(
      id: _requiredTextValue(json['id'], 'id'),
      tenantId: _requiredTextValue(json['tenant_id'], 'tenant_id'),
      kind: kind,
      code: _requiredTextValue(json['code'], 'code'),
      label: _requiredTextValue(json['label'], 'label'),
      description: _nullableText(json['description']),
      natureGroup: _nullableText(json['nature_group']),
      aliases: _stringList(json['aliases']),
      isActive: json['is_active'] as bool? ?? true,
      isSystem: json['is_system'] as bool? ?? false,
      publicMetadata: _map(json['metadata']),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  final String id;
  final String tenantId;
  final SupplierClassificationDefinitionKind kind;
  final String code;
  final String label;
  final String? description;
  final String? natureGroup;
  final List<String> aliases;
  final bool isActive;
  final bool isSystem;
  final Map<String, dynamic> publicMetadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

@immutable
class SupplierClassificationCatalog {
  SupplierClassificationCatalog({
    List<SupplierClassificationDefinition> roles = const [],
    List<SupplierClassificationDefinition> capabilities = const [],
    List<SupplierClassificationDefinition> tags = const [],
    List<SupplierClassificationDefinition> operationalNatures = const [],
  })  : roles = List.unmodifiable(roles),
        capabilities = List.unmodifiable(capabilities),
        tags = List.unmodifiable(tags),
        operationalNatures = List.unmodifiable(operationalNatures);

  final List<SupplierClassificationDefinition> roles;
  final List<SupplierClassificationDefinition> capabilities;
  final List<SupplierClassificationDefinition> tags;
  final List<SupplierClassificationDefinition> operationalNatures;

  Iterable<SupplierClassificationDefinition> get all sync* {
    yield* roles;
    yield* capabilities;
    yield* tags;
    yield* operationalNatures;
  }

  SupplierClassificationDefinition? byId(String id) {
    for (final definition in all) {
      if (definition.id == id) return definition;
    }
    return null;
  }
}

enum SupplierClassificationCandidateSourceKind {
  legacySupplierType,
  legacyExpenseCategory,
  legacyExpenseTag;

  static SupplierClassificationCandidateSourceKind fromJson(dynamic value) {
    return switch (value?.toString()) {
      'legacy_supplier_type' =>
        SupplierClassificationCandidateSourceKind.legacySupplierType,
      'legacy_expense_category' =>
        SupplierClassificationCandidateSourceKind.legacyExpenseCategory,
      'legacy_expense_tag' =>
        SupplierClassificationCandidateSourceKind.legacyExpenseTag,
      _ => throw const FormatException(
          'Invalid supplier classification candidate source',
        ),
    };
  }

  String get dbValue => switch (this) {
        SupplierClassificationCandidateSourceKind.legacySupplierType =>
          'legacy_supplier_type',
        SupplierClassificationCandidateSourceKind.legacyExpenseCategory =>
          'legacy_expense_category',
        SupplierClassificationCandidateSourceKind.legacyExpenseTag =>
          'legacy_expense_tag',
      };
}

enum SupplierClassificationCandidateStatus {
  pending,
  confirmed,
  rejected;

  static SupplierClassificationCandidateStatus fromJson(dynamic value) {
    return switch (value?.toString()) {
      'pending' => SupplierClassificationCandidateStatus.pending,
      'confirmed' => SupplierClassificationCandidateStatus.confirmed,
      'rejected' => SupplierClassificationCandidateStatus.rejected,
      _ => throw const FormatException(
          'Invalid supplier classification candidate status',
        ),
    };
  }
}

/// Server-owned legacy-classification review item.
///
/// [suggestedCode] is only a proposal. Reading this object never assigns that
/// code to a supplier, policy, or accounting row.
@immutable
class SupplierClassificationCandidate {
  SupplierClassificationCandidate({
    required this.id,
    required this.tenantId,
    required this.sourceKind,
    required this.sourceValue,
    required this.targetVocabulary,
    required this.status,
    this.supplierId,
    this.supplierDisplayName,
    this.sourceId,
    this.suggestedCode,
    this.suggestedLabel,
    this.rationale,
    this.reviewedBy,
    this.reviewedAt,
    Map<String, dynamic> publicMetadata = const {},
    this.createdAt,
    this.updatedAt,
  }) : publicMetadata = _publicMap(publicMetadata);

  factory SupplierClassificationCandidate.fromJson(
    Map<String, dynamic> json,
  ) {
    return SupplierClassificationCandidate(
      id: _requiredTextValue(
        json['candidate_id'] ?? json['id'],
        'candidate_id',
      ),
      tenantId: _requiredTextValue(json['tenant_id'], 'tenant_id'),
      supplierId: _nullableText(json['supplier_id']),
      supplierDisplayName: _nullableText(json['supplier_display_name']),
      sourceKind: SupplierClassificationCandidateSourceKind.fromJson(
        json['source_kind'],
      ),
      sourceId: _nullableText(json['source_id']),
      sourceValue: _requiredTextValue(json['source_value'], 'source_value'),
      targetVocabulary: SupplierClassificationDefinitionKind.fromJson(
        json['target_vocabulary'],
      ),
      suggestedCode: _nullableText(json['suggested_code']),
      suggestedLabel: _nullableText(json['suggested_label']),
      status: SupplierClassificationCandidateStatus.fromJson(json['status']),
      rationale: _nullableText(json['rationale']),
      reviewedBy: _nullableText(json['reviewed_by']),
      reviewedAt: _date(json['reviewed_at']),
      publicMetadata: _map(json['metadata']),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  final String id;
  final String tenantId;
  final String? supplierId;
  final String? supplierDisplayName;
  final SupplierClassificationCandidateSourceKind sourceKind;
  final String? sourceId;
  final String sourceValue;
  final SupplierClassificationDefinitionKind targetVocabulary;
  final String? suggestedCode;
  final String? suggestedLabel;
  final SupplierClassificationCandidateStatus status;
  final String? rationale;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final Map<String, dynamic> publicMetadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

@immutable
class ExternalPartyIdentifier {
  ExternalPartyIdentifier({
    required this.id,
    required this.tenantId,
    required this.externalPartyId,
    required this.kind,
    required this.value,
    this.normalizedValue,
    this.issuerCountry,
    this.isPrimary = false,
    this.validFrom,
    this.validUntil,
    Map<String, dynamic> publicMetadata = const {},
  }) : publicMetadata = _publicMap(publicMetadata);

  factory ExternalPartyIdentifier.fromJson(Map<String, dynamic> json) {
    return ExternalPartyIdentifier(
      id: _text(json['id']),
      tenantId: _text(json['tenant_id']),
      externalPartyId: _text(
        json['external_party_id'] ?? json['party_id'],
      ),
      kind: _text(json['identifier_kind'] ?? json['kind'], fallback: 'other'),
      value: _text(
        json['display_value'] ??
            json['identifier_value'] ??
            json['value'] ??
            json['normalized_value'],
      ),
      normalizedValue: _nullableText(json['normalized_value']),
      issuerCountry: _nullableText(
        json['country_code'] ?? json['issuer_country'],
      ),
      isPrimary: json['is_primary'] as bool? ?? false,
      validFrom: _date(json['valid_from']),
      validUntil: _date(json['valid_to']),
      publicMetadata: _map(json['metadata']),
    );
  }

  final String id;
  final String tenantId;
  final String externalPartyId;
  final String kind;
  final String value;
  final String? normalizedValue;
  final String? issuerCountry;
  final bool isPrimary;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final Map<String, dynamic> publicMetadata;

  bool isEffectiveAt(DateTime instant) =>
      _dateRangeContains(instant, validFrom, validUntil);

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'party_id': externalPartyId,
        'identifier_kind': kind,
        'display_value': value,
        'normalized_value': normalizedValue,
        'country_code': issuerCountry,
        'is_primary': isPrimary,
        'valid_from': validFrom?.toIso8601String(),
        'valid_to': validUntil?.toIso8601String(),
        'metadata': publicMetadata,
      };
}

@immutable
class ExternalParty {
  ExternalParty({
    required this.id,
    required this.tenantId,
    required this.kind,
    required this.name,
    this.legalName,
    this.tradeName,
    this.countryCode,
    this.notes,
    List<String> aliases = const [],
    List<ExternalPartyIdentifier> identifiers = const [],
    Map<String, dynamic> publicMetadata = const {},
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  })  : aliases = List.unmodifiable(aliases),
        identifiers = List.unmodifiable(identifiers),
        publicMetadata = _publicMap(publicMetadata);

  factory ExternalParty.fromJson(Map<String, dynamic> json) {
    final partyId = _text(json['id'] ?? json['party_id']);
    final tenantId = _text(json['tenant_id']);
    final identifierRows = _mapList(
      json['identifiers'] ?? json['party_identifiers'],
    ).map(
      (item) => <String, dynamic>{
        ...item,
        'tenant_id': item['tenant_id'] ?? tenantId,
        'party_id': item['party_id'] ?? partyId,
      },
    );
    return ExternalParty(
      id: partyId,
      tenantId: tenantId,
      kind: ExternalPartyKind.fromJson(
        json['party_kind'] ?? json['kind'],
      ),
      name: _text(
        json['display_name'] ??
            json['party_display_name'] ??
            json['legal_name'] ??
            json['party_legal_name'],
      ),
      legalName: _nullableText(
        json['legal_name'] ?? json['party_legal_name'],
      ),
      tradeName: _nullableText(
        json['trade_name'] ?? json['party_trade_name'],
      ),
      aliases: _stringList(json['aliases'] ?? json['party_aliases']),
      countryCode: _nullableText(json['country_code']),
      notes: _nullableText(json['notes'] ?? json['party_notes']),
      identifiers: identifierRows
          .map(ExternalPartyIdentifier.fromJson)
          .toList(growable: false),
      publicMetadata: _map(json['metadata']),
      isActive: json['is_active'] as bool? ??
          json['party_is_active'] as bool? ??
          true,
      createdAt: _date(json['created_at'] ?? json['party_created_at']),
      updatedAt: _date(json['updated_at'] ?? json['party_updated_at']),
    );
  }

  final String id;
  final String tenantId;
  final ExternalPartyKind kind;
  final String name;
  final String? legalName;
  final String? tradeName;
  final String? countryCode;
  final String? notes;
  final List<String> aliases;
  final List<ExternalPartyIdentifier> identifiers;
  final Map<String, dynamic> publicMetadata;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayName => name;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'party_kind': kind.dbValue,
        'display_name': name,
        'legal_name': legalName,
        'trade_name': tradeName,
        'country_code': countryCode,
        'notes': notes,
        'metadata': publicMetadata,
        'is_active': isActive,
      };
}

@immutable
class SupplierRole {
  SupplierRole({
    required this.id,
    required this.tenantId,
    required this.supplierId,
    required this.code,
    this.definitionId,
    this.label,
    this.assignmentSource = 'manual',
    this.validFrom,
    this.validUntil,
    Map<String, dynamic> publicMetadata = const {},
  }) : publicMetadata = _publicMap(publicMetadata);

  factory SupplierRole.fromJson(Map<String, dynamic> json) {
    return SupplierRole(
      id: _text(json['id']),
      tenantId: _text(json['tenant_id']),
      supplierId: _text(json['supplier_id']),
      code: _requiredTextValue(
        json['role_code'] ?? json['role'] ?? json['code'],
        'role_code',
      ),
      definitionId: _nullableText(
        json['role_definition_id'] ?? json['definition_id'],
      ),
      label: _nullableText(json['role_label'] ?? json['label']),
      assignmentSource: _text(
        json['assignment_source'] ?? json['source'],
        fallback: 'manual',
      ),
      validFrom: _date(json['valid_from']),
      validUntil: _date(json['valid_until'] ?? json['valid_to']),
      publicMetadata: _map(json['metadata']),
    );
  }

  final String id;
  final String tenantId;
  final String supplierId;
  final String code;
  final String? definitionId;
  final String? label;
  final String assignmentSource;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final Map<String, dynamic> publicMetadata;

  SupplierRoleKind get kind => SupplierRoleKind.fromJson(code);

  bool isEffectiveAt(DateTime instant) {
    return _dateRangeContains(instant, validFrom, validUntil);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'role_code': code,
        'definition_id': definitionId,
        'label': label,
        'assignment_source': assignmentSource,
        'valid_from': validFrom?.toUtc().toIso8601String(),
        'valid_to': validUntil?.toUtc().toIso8601String(),
        'metadata': publicMetadata,
      };
}

@immutable
class SupplierCapability {
  SupplierCapability({
    required this.id,
    required this.tenantId,
    required this.supplierId,
    required this.code,
    this.definitionId,
    this.label,
    this.assignmentSource = 'manual',
    Map<String, dynamic> publicConfiguration = const {},
    this.validFrom,
    this.validUntil,
  }) : publicConfiguration = _publicMap(publicConfiguration);

  factory SupplierCapability.fromJson(Map<String, dynamic> json) {
    return SupplierCapability(
      id: _text(json['id']),
      tenantId: _text(json['tenant_id']),
      supplierId: _text(json['supplier_id']),
      code: _requiredTextValue(
        json['capability_code'] ?? json['capability'] ?? json['code'],
        'capability_code',
      ),
      definitionId: _nullableText(
        json['capability_definition_id'] ?? json['definition_id'],
      ),
      label: _nullableText(json['capability_label'] ?? json['label']),
      assignmentSource: _text(
        json['assignment_source'] ?? json['source'],
        fallback: 'manual',
      ),
      publicConfiguration: _map(
        json['metadata'] ??
            json['public_configuration'] ??
            json['configuration'],
      ),
      validFrom: _date(json['valid_from']),
      validUntil: _date(json['valid_until'] ?? json['valid_to']),
    );
  }

  final String id;
  final String tenantId;
  final String supplierId;
  final String code;
  final String? definitionId;
  final String? label;
  final String assignmentSource;
  final Map<String, dynamic> publicConfiguration;
  final DateTime? validFrom;
  final DateTime? validUntil;

  SupplierCapabilityKind get kind => SupplierCapabilityKind.fromJson(code);

  bool isEffectiveAt(DateTime instant) {
    return _dateRangeContains(instant, validFrom, validUntil);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'capability_code': code,
        'definition_id': definitionId,
        'label': label,
        'assignment_source': assignmentSource,
        'metadata': publicConfiguration,
        'valid_from': validFrom?.toUtc().toIso8601String(),
        'valid_to': validUntil?.toUtc().toIso8601String(),
      };
}

@immutable
class SupplierTag {
  SupplierTag({
    required this.id,
    required this.tenantId,
    required this.supplierId,
    required this.code,
    required this.label,
    this.definitionId,
    this.assignmentSource = 'manual',
    this.validFrom,
    this.validUntil,
    Map<String, dynamic> publicMetadata = const {},
  }) : publicMetadata = _publicMap(publicMetadata);

  factory SupplierTag.fromJson(Map<String, dynamic> json) {
    return SupplierTag(
      id: _text(json['id']),
      tenantId: _text(json['tenant_id']),
      supplierId: _text(json['supplier_id']),
      code: _text(json['tag_code'] ?? json['code']),
      label: _text(json['label'] ?? json['tag_code'] ?? json['code']),
      definitionId: _nullableText(
        json['tag_definition_id'] ?? json['definition_id'],
      ),
      assignmentSource: _text(
        json['assignment_source'] ?? json['source'],
        fallback: 'manual',
      ),
      validFrom: _date(json['valid_from']),
      validUntil: _date(json['valid_to']),
      publicMetadata: _map(json['metadata']),
    );
  }

  final String id;
  final String tenantId;
  final String supplierId;
  final String code;
  final String label;
  final String? definitionId;
  final String assignmentSource;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final Map<String, dynamic> publicMetadata;

  bool isEffectiveAt(DateTime instant) =>
      _dateRangeContains(instant, validFrom, validUntil);

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'tag_code': code,
        'label': label,
        'definition_id': definitionId,
        'assignment_source': assignmentSource,
        'valid_from': validFrom?.toIso8601String(),
        'valid_to': validUntil?.toIso8601String(),
        'metadata': publicMetadata,
      };
}

/// Complete assignment history for audit/detail use. The lists directly on
/// [SupplierRelationship] contain only confirmed assignments effective on the
/// server-published tenant business date, so a form cannot promote observed
/// evidence or resurrect expired rows while replacing the editable set.
@immutable
class SupplierClassificationHistory {
  SupplierClassificationHistory({
    List<SupplierRole> roles = const [],
    List<SupplierCapability> capabilities = const [],
    List<SupplierTag> tags = const [],
  })  : roles = List.unmodifiable(roles),
        capabilities = List.unmodifiable(capabilities),
        tags = List.unmodifiable(tags);

  final List<SupplierRole> roles;
  final List<SupplierCapability> capabilities;
  final List<SupplierTag> tags;
}

@immutable
class SupplierRelationship {
  SupplierRelationship({
    required this.id,
    required this.tenantId,
    required this.externalPartyId,
    required this.name,
    required this.status,
    this.email,
    this.phone,
    this.contactPerson,
    this.website,
    this.notes,
    this.paymentTermsCode,
    this.serviceRelationshipSummary,
    List<SupplierRole> roles = const [],
    List<SupplierCapability> capabilities = const [],
    List<SupplierTag> tags = const [],
    this.hasCredentialReference,
    this.createdAt,
    this.updatedAt,
  })  : roles = List.unmodifiable(roles),
        capabilities = List.unmodifiable(capabilities),
        tags = List.unmodifiable(tags);

  factory SupplierRelationship.fromJson(Map<String, dynamic> json) {
    final active = json['is_active'] as bool?;
    return SupplierRelationship(
      id: _text(json['id'] ?? json['supplier_id']),
      tenantId: _text(json['tenant_id']),
      externalPartyId: _text(json['party_id'] ?? json['external_party_id']),
      name: _text(
        json['name'] ?? json['supplier_name'] ?? json['display_name'],
      ),
      status: active == false
          ? SupplierRelationshipStatus.inactive
          : SupplierRelationshipStatus.fromJson(
              json['relationship_status'] ?? json['status'],
            ),
      email: _nullableText(json['email']),
      phone: _nullableText(json['phone']),
      contactPerson: _nullableText(json['contact_person']),
      website: _nullableText(json['website']),
      notes: _nullableText(json['notes']),
      paymentTermsCode: _nullableText(json['payment_terms']),
      serviceRelationshipSummary: _nullableText(
        json['service_relationship_summary'],
      ),
      roles: _scopedItems(
        json['roles'] ?? json['relationship_roles'],
        tenantId: _text(json['tenant_id']),
        supplierId: _text(json['id'] ?? json['supplier_id']),
      ).map(SupplierRole.fromJson).toList(growable: false),
      capabilities: _scopedItems(
        json['capabilities'] ?? json['relationship_capabilities'],
        tenantId: _text(json['tenant_id']),
        supplierId: _text(json['id'] ?? json['supplier_id']),
      ).map(SupplierCapability.fromJson).toList(growable: false),
      tags: _scopedItems(
        json['tags'] ?? json['relationship_tags'],
        tenantId: _text(json['tenant_id']),
        supplierId: _text(json['id'] ?? json['supplier_id']),
      ).map(SupplierTag.fromJson).toList(growable: false),
      hasCredentialReference: (json['has_credential_reference'] ??
          json['has_portal_credential']) as bool?,
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  /// This ID intentionally remains the existing `suppliers.id`. The database
  /// evolves that table into the relationship owner so purchase/product FKs do
  /// not fork into a parallel identity graph.
  final String id;
  final String tenantId;
  final String externalPartyId;
  final String name;
  final SupplierRelationshipStatus status;
  final String? email;
  final String? phone;
  final String? contactPerson;
  final String? website;
  final String? notes;
  final String? paymentTermsCode;

  /// Nullable, server-authored display summary of active/effective service
  /// engagements. Clients must not reconstruct it from partial engagement
  /// data when the projection does not publish it.
  final String? serviceRelationshipSummary;
  final List<SupplierRole> roles;
  final List<SupplierCapability> capabilities;
  final List<SupplierTag> tags;
  final bool? hasCredentialReference;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == SupplierRelationshipStatus.active;

  bool hasRole(SupplierRoleKind role) => roles.any((item) => item.kind == role);

  bool hasCapability(SupplierCapabilityKind capability) =>
      capabilities.any((item) => item.kind == capability);

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'party_id': externalPartyId,
        'name': name,
        'email': email,
        'phone': phone,
        'contact_person': contactPerson,
        'website': website,
        'notes': notes,
        'payment_terms': paymentTermsCode,
        'is_active': isActive,
      };
}

@immutable
class SupplierLegacyOperationalDetails {
  const SupplierLegacyOperationalDetails({
    this.address,
    this.city,
    this.region,
    this.comuna,
    this.salesRepName,
    this.salesRepPhone,
    this.salesRepEmail,
    this.imageUrl,
    this.type = SupplierType.local,
    this.paymentTerms = PaymentTerms.net30,
    this.defaultTaxTreatment = TaxTreatment.noTax,
  });

  factory SupplierLegacyOperationalDetails.fromJson(
    Map<String, dynamic> json,
  ) {
    return SupplierLegacyOperationalDetails(
      address: _nullableText(json['address']),
      city: _nullableText(json['city']),
      region: _nullableText(json['region']),
      comuna: _nullableText(json['comuna']),
      salesRepName: _nullableText(json['sales_rep_name']),
      salesRepPhone: _nullableText(json['sales_rep_phone']),
      salesRepEmail: _nullableText(json['sales_rep_email']),
      imageUrl: _nullableText(json['image_url']),
      type: SupplierType.values.firstWhere(
        (item) => item.name == json['legacy_type']?.toString(),
        orElse: () => SupplierType.local,
      ),
      paymentTerms: PaymentTerms.values.firstWhere(
        (item) => item.name == json['payment_terms']?.toString(),
        orElse: () => PaymentTerms.net30,
      ),
      defaultTaxTreatment: TaxTreatment.fromString(
        json['default_tax_treatment']?.toString(),
      ),
    );
  }

  final String? address;
  final String? city;
  final String? region;
  final String? comuna;

  /// El vendedor: la persona a la que el ERP le escribe por WhatsApp.
  /// Vive en `suppliers.sales_rep_*` y se edita con el comando estrecho
  /// `update_supplier_sales_rep`, no con el perfil.
  final String? salesRepName;
  final String? salesRepPhone;
  final String? salesRepEmail;

  /// Logo o foto del proveedor (`suppliers.image_url`), que la ficha muestra
  /// como avatar de su cabecera.
  final String? imageUrl;
  final SupplierType type;
  final PaymentTerms paymentTerms;
  final TaxTreatment defaultTaxTreatment;

  bool get hasSalesRep =>
      (salesRepName ?? '').trim().isNotEmpty ||
      (salesRepPhone ?? '').trim().isNotEmpty ||
      (salesRepEmail ?? '').trim().isNotEmpty;
}

@immutable
class BusinessSite {
  BusinessSite({
    required this.id,
    required this.tenantId,
    required this.code,
    required this.name,
    this.siteKind = 'other',
    this.address,
    this.comuna,
    this.city,
    this.region,
    this.countryCode = 'CL',
    this.isActive = true,
    Map<String, dynamic> publicMetadata = const {},
    this.createdAt,
    this.updatedAt,
  }) : publicMetadata = _publicMap(publicMetadata);

  factory BusinessSite.fromJson(Map<String, dynamic> json) {
    return BusinessSite(
      id: _text(json['id'] ?? json['site_id']),
      tenantId: _text(json['tenant_id']),
      name: _text(json['name']),
      code: _text(json['code']),
      siteKind: _text(json['site_kind'], fallback: 'other'),
      address: _nullableText(json['address']),
      comuna: _nullableText(json['comuna']),
      city: _nullableText(json['city']),
      region: _nullableText(json['region']),
      countryCode: _text(json['country_code'], fallback: 'CL'),
      isActive: json['is_active'] as bool? ?? true,
      publicMetadata: _map(json['metadata']),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  final String id;
  final String tenantId;
  final String code;
  final String name;
  final String siteKind;
  final String? address;
  final String? comuna;
  final String? city;
  final String? region;
  final String countryCode;
  final bool isActive;
  final Map<String, dynamic> publicMetadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        'code': code,
        'site_kind': siteKind,
        'address': address,
        'comuna': comuna,
        'city': city,
        'region': region,
        'country_code': countryCode,
        'is_active': isActive,
        'metadata': publicMetadata,
      };
}

@immutable
class SupplierEngagementVersion {
  SupplierEngagementVersion({
    required this.id,
    required this.tenantId,
    required this.engagementId,
    required this.version,
    required this.validFrom,
    this.operationId,
    this.validUntil,
    this.externalReference,
    this.serviceIdentifier,
    this.billingCadence = 'none',
    this.currencyCode = 'CLP',
    this.expectedAmount,
    this.dueDay,
    this.portalUrl,
    Map<String, dynamic> publicMetadata = const {},
    this.createdAt,
    this.updatedAt,
  }) : publicMetadata = _publicMap(publicMetadata);

  factory SupplierEngagementVersion.fromJson(Map<String, dynamic> json) {
    return SupplierEngagementVersion(
      id: _text(json['id']),
      tenantId: _text(json['tenant_id']),
      engagementId: _text(json['engagement_id']),
      version: _integer(json['version'] ?? json['version_number'], fallback: 1),
      validFrom: _date(json['effective_from'] ?? json['valid_from']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      validUntil: _date(
        json['effective_to'] ?? json['valid_until'] ?? json['valid_to'],
      ),
      operationId: _nullableText(json['operation_id']),
      externalReference: _nullableText(json['external_reference']),
      serviceIdentifier: _nullableText(json['service_identifier']),
      billingCadence: _text(
        json['billing_cycle'] ?? json['billing_cadence'],
        fallback: json['is_free'] == true ? 'free' : 'none',
      ),
      currencyCode: _text(json['currency_code'], fallback: 'CLP'),
      expectedAmount: _nullableNumber(json['expected_amount']),
      dueDay: _nullableInteger(json['due_day']),
      portalUrl: _nullableText(json['portal_url']),
      publicMetadata: _map(
        json['terms'] ?? json['public_metadata'] ?? json['metadata'],
      ),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  final String id;
  final String tenantId;
  final String engagementId;
  final int version;
  final DateTime validFrom;
  final DateTime? validUntil;
  final String? operationId;
  final String? externalReference;
  final String? serviceIdentifier;
  final String billingCadence;
  final String currencyCode;
  final double? expectedAmount;
  final int? dueDay;
  final String? portalUrl;
  final Map<String, dynamic> publicMetadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isFree => billingCadence == 'free';

  bool isEffectiveAt(DateTime instant) =>
      _dateRangeContains(instant, validFrom, validUntil);

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'engagement_id': engagementId,
        'version_number': version,
        'effective_from': validFrom.toIso8601String(),
        'effective_to': validUntil?.toIso8601String(),
        'operation_id': operationId,
        'external_reference': externalReference,
        'service_identifier': serviceIdentifier,
        'billing_cycle': billingCadence,
        'currency_code': currencyCode,
        'expected_amount': expectedAmount,
        'due_day': dueDay,
        'portal_url': portalUrl,
        'terms': publicMetadata,
      };
}

@immutable
class SupplierEngagement {
  SupplierEngagement({
    required this.id,
    required this.tenantId,
    required this.supplierId,
    required this.kind,
    required this.code,
    required this.name,
    required this.status,
    this.operationId,
    this.businessSiteId,
    this.startsOn,
    this.endsOn,
    this.effectiveBusinessDate,
    Map<String, dynamic> publicMetadata = const {},
    List<SupplierEngagementVersion> versions = const [],
    this.createdAt,
    this.updatedAt,
  })  : publicMetadata = _publicMap(publicMetadata),
        versions = List.unmodifiable(versions);

  factory SupplierEngagement.fromJson(Map<String, dynamic> json) {
    return SupplierEngagement(
      id: _text(json['id']),
      tenantId: _text(json['tenant_id']),
      supplierId: _text(json['supplier_id']),
      kind: SupplierEngagementKind.fromJson(
        json['engagement_kind'] ?? json['kind'],
      ),
      code: _text(json['code']),
      name: _text(json['name']),
      status: SupplierEngagementStatus.fromJson(json['status']),
      operationId: _nullableText(json['operation_id']),
      businessSiteId: _nullableText(
        json['site_id'] ?? json['business_site_id'],
      ),
      startsOn: _date(json['starts_on']),
      endsOn: _date(json['ends_on']),
      effectiveBusinessDate: _date(json['effective_business_date']),
      publicMetadata: _map(json['metadata']),
      versions: _mapList(json['versions'])
          .map(SupplierEngagementVersion.fromJson)
          .toList(growable: false),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  final String id;
  final String tenantId;
  final String supplierId;
  final SupplierEngagementKind kind;
  final String code;
  final String name;
  final SupplierEngagementStatus status;
  final String? operationId;
  final String? businessSiteId;
  final DateTime? startsOn;
  final DateTime? endsOn;

  /// Tenant-local civil date published by the database read model.
  ///
  /// Domain validity must never fall back to the device clock because the
  /// operator and tenant can be in different time zones.
  final DateTime? effectiveBusinessDate;
  final Map<String, dynamic> publicMetadata;
  final List<SupplierEngagementVersion> versions;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  SupplierEngagementVersion? versionAt(DateTime instant) {
    final effective = versions.where((item) => item.isEffectiveAt(instant));
    if (effective.isEmpty) return null;
    return effective.reduce(
      (left, right) => left.version > right.version ? left : right,
    );
  }

  SupplierEngagementVersion? get currentVersion =>
      effectiveBusinessDate == null ? null : versionAt(effectiveBusinessDate!);

  /// Newest authored version, including one whose validity starts in the
  /// future. Writers append after this version; readers use [currentVersion].
  SupplierEngagementVersion? get latestVersion {
    if (versions.isEmpty) return null;
    return versions.reduce((left, right) {
      if (right.validFrom.isAfter(left.validFrom)) return right;
      if (right.validFrom.isAtSameMomentAs(left.validFrom) &&
          right.version > left.version) {
        return right;
      }
      return left;
    });
  }

  String? get externalReference => currentVersion?.externalReference;

  String? get portalUrl => currentVersion?.portalUrl;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'site_id': businessSiteId,
        'engagement_kind': kind.dbValue,
        'code': code,
        'name': name,
        'status': status.name,
        'operation_id': operationId,
        'starts_on': startsOn?.toIso8601String(),
        'ends_on': endsOn?.toIso8601String(),
        'metadata': publicMetadata,
      };
}

@immutable
class SupplierAccountingPolicyVersionSummary {
  SupplierAccountingPolicyVersionSummary({
    required this.id,
    required this.tenantId,
    required this.policyId,
    required this.version,
    required this.effectiveFrom,
    required this.operationalNatureCode,
    this.operationId,
    this.operationalNatureDefinitionId,
    this.operationalNatureLabel,
    this.operationalNatureGroup,
    this.effectiveUntil,
    this.legacyExpenseCategoryId,
    this.debitAccountId,
    this.liabilityAccountId,
    this.taxTreatmentCode = 'not_applicable',
    this.expectedDocumentType,
    this.currencyCode = 'CLP',
    this.lineNature,
    Map<String, dynamic> posture = const {},
  }) : posture = _publicMap(posture);

  factory SupplierAccountingPolicyVersionSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return SupplierAccountingPolicyVersionSummary(
      id: _text(json['id']),
      tenantId: _text(json['tenant_id']),
      policyId: _text(json['policy_id']),
      version: _integer(json['version_number'], fallback: 1),
      effectiveFrom: _date(json['effective_from']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      effectiveUntil: _date(json['effective_to'] ?? json['effective_until']),
      operationalNatureCode: _text(json['operational_nature_code']),
      operationId: _nullableText(json['operation_id']),
      operationalNatureDefinitionId: _nullableText(
        json['operational_nature_definition_id'],
      ),
      operationalNatureLabel: _nullableText(
        json['operational_nature_label'],
      ),
      operationalNatureGroup: _nullableText(
        json['operational_nature_group'],
      ),
      legacyExpenseCategoryId:
          _nullableText(json['legacy_expense_category_id']),
      debitAccountId: _nullableText(json['debit_account_id']),
      liabilityAccountId: _nullableText(json['liability_account_id']),
      taxTreatmentCode:
          _text(json['tax_treatment'], fallback: 'not_applicable'),
      expectedDocumentType: _nullableText(json['expected_document_type']),
      currencyCode: _text(json['currency_code'], fallback: 'CLP'),
      lineNature: _nullableText(json['line_nature']),
      posture: _map(json['posture']),
    );
  }

  final String id;
  final String tenantId;
  final String policyId;
  final int version;
  final DateTime effectiveFrom;
  final DateTime? effectiveUntil;
  final String operationalNatureCode;
  final String? operationId;
  final String? operationalNatureDefinitionId;
  final String? operationalNatureLabel;
  final String? operationalNatureGroup;
  final String? legacyExpenseCategoryId;
  final String? debitAccountId;
  final String? liabilityAccountId;
  final String taxTreatmentCode;
  final String? expectedDocumentType;
  final String currencyCode;
  final String? lineNature;
  final Map<String, dynamic> posture;

  bool isEffectiveAt(DateTime instant) =>
      _dateRangeContains(instant, effectiveFrom, effectiveUntil);

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'policy_id': policyId,
        'version_number': version,
        'effective_from': effectiveFrom.toIso8601String(),
        'effective_to': effectiveUntil?.toIso8601String(),
        'operation_id': operationId,
        'operational_nature_code': operationalNatureCode,
        'legacy_expense_category_id': legacyExpenseCategoryId,
        'debit_account_id': debitAccountId,
        'liability_account_id': liabilityAccountId,
        'tax_treatment': taxTreatmentCode,
        'expected_document_type': expectedDocumentType,
        'currency_code': currencyCode,
        'line_nature': lineNature,
        'posture': posture,
      };
}

@immutable
class SupplierAccountingPolicySummary {
  SupplierAccountingPolicySummary({
    required this.id,
    required this.tenantId,
    required this.supplierId,
    required this.code,
    required this.name,
    required this.status,
    this.operationId,
    this.engagementId,
    this.effectiveBusinessDate,
    this.priority = 100,
    this.allowExactAutofill = false,
    List<SupplierAccountingPolicyVersionSummary> versions = const [],
  }) : versions = List.unmodifiable(versions);

  factory SupplierAccountingPolicySummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return SupplierAccountingPolicySummary(
      id: _text(json['id']),
      tenantId: _text(json['tenant_id']),
      supplierId: _text(json['supplier_id']),
      engagementId: _nullableText(json['engagement_id']),
      effectiveBusinessDate: _date(json['effective_business_date']),
      code: _text(json['code']),
      name: _text(json['name']),
      status: SupplierAccountingPolicyStatus.fromJson(json['status']),
      operationId: _nullableText(json['operation_id']),
      priority: _integer(json['priority'], fallback: 100),
      allowExactAutofill: json['allow_exact_autofill'] as bool? ?? false,
      versions: _mapList(json['versions'])
          .map(SupplierAccountingPolicyVersionSummary.fromJson)
          .toList(growable: false),
    );
  }

  final String id;
  final String tenantId;
  final String supplierId;
  final String? engagementId;

  /// Tenant-local civil date published by the database read model.
  final DateTime? effectiveBusinessDate;
  final String code;
  final String name;
  final SupplierAccountingPolicyStatus status;
  final String? operationId;
  final int priority;
  final bool allowExactAutofill;
  final List<SupplierAccountingPolicyVersionSummary> versions;

  SupplierAccountingPolicyVersionSummary? versionAt(DateTime instant) {
    final effective = versions.where((item) => item.isEffectiveAt(instant));
    if (effective.isEmpty) return null;
    return effective.reduce(
      (left, right) => left.version > right.version ? left : right,
    );
  }

  SupplierAccountingPolicyVersionSummary? get currentVersion =>
      effectiveBusinessDate == null ? null : versionAt(effectiveBusinessDate!);

  /// Newest authored version, including one whose validity starts in the
  /// future. Writers append after this version; readers use [currentVersion].
  SupplierAccountingPolicyVersionSummary? get latestVersion {
    if (versions.isEmpty) return null;
    return versions.reduce((left, right) {
      if (right.effectiveFrom.isAfter(left.effectiveFrom)) return right;
      if (right.effectiveFrom.isAtSameMomentAs(left.effectiveFrom) &&
          right.version > left.version) {
        return right;
      }
      return left;
    });
  }

  /// Exact rules may only prefill a draft; this never authorizes approval or
  /// posting.
  bool get permitsExactDraftAutofill =>
      status == SupplierAccountingPolicyStatus.active && allowExactAutofill;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'engagement_id': engagementId,
        'code': code,
        'name': name,
        'status': status.name,
        'operation_id': operationId,
        'priority': priority,
        'allow_exact_autofill': allowExactAutofill,
      };
}

@immutable
class SupplierAccountingRuleSummary {
  SupplierAccountingRuleSummary({
    required this.id,
    required this.tenantId,
    required this.policyVersionId,
    required this.ruleKind,
    required this.operatorCode,
    required this.priority,
    required Map<String, dynamic> operand,
    this.isActive = true,
  }) : operand = _publicMap(operand);

  factory SupplierAccountingRuleSummary.fromJson(Map<String, dynamic> json) {
    return SupplierAccountingRuleSummary(
      id: _text(json['id']),
      tenantId: _text(json['tenant_id']),
      policyVersionId: _text(json['policy_version_id']),
      ruleKind: _text(json['rule_kind']),
      operatorCode: _text(json['operator']),
      priority: _integer(json['priority'], fallback: 100),
      operand: _map(json['operand'] ?? json['criteria']),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  final String id;
  final String tenantId;
  final String policyVersionId;
  final String ruleKind;
  final String operatorCode;
  final int priority;
  final Map<String, dynamic> operand;
  final bool isActive;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'policy_version_id': policyVersionId,
        'rule_kind': ruleKind,
        'operator': operatorCode,
        'operand': operand,
        'priority': priority,
        'is_active': isActive,
      };
}

@immutable
class SupplierAccountingEvidenceSummary {
  SupplierAccountingEvidenceSummary({
    required this.id,
    required this.tenantId,
    required this.supplierId,
    required this.operationId,
    required this.sourceType,
    required this.sourceId,
    required this.decision,
    required this.effectiveAt,
    required this.operationalNatureCode,
    required this.operationalNatureLabel,
    this.policyVersionId,
    this.ruleId,
    this.sourceLineId,
    this.debitAccountId,
    this.debitAccountCode,
    this.liabilityAccountId,
    this.liabilityAccountCode,
    this.legacyExpenseCategoryId,
    this.legacyExpenseCategoryName,
    this.rationale,
    this.idempotentReplay = false,
    Map<String, dynamic> appliedSnapshot = const {},
  }) : appliedSnapshot = _publicMap(appliedSnapshot);

  factory SupplierAccountingEvidenceSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return SupplierAccountingEvidenceSummary(
      id: _text(json['id']),
      tenantId: _text(json['tenant_id']),
      supplierId: _text(json['supplier_id']),
      operationId: _requiredTextValue(json['operation_id'], 'operation_id'),
      sourceType: _text(json['source_type']),
      sourceId: _text(json['source_id']),
      decision: SupplierAccountingEvidenceDecision.fromJson(
        json['decision'],
      ),
      effectiveAt: _date(json['applied_at'] ?? json['effective_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      operationalNatureCode: _text(json['operational_nature_code']),
      operationalNatureLabel: _requiredTextValue(
        json['operational_nature_label'],
        'operational_nature_label',
      ),
      policyVersionId: _nullableText(json['policy_version_id']),
      ruleId: _nullableText(json['rule_id']),
      sourceLineId: _nullableText(json['source_line_id']),
      debitAccountId: _nullableText(json['debit_account_id']),
      debitAccountCode: _nullableText(json['debit_account_code']),
      liabilityAccountId: _nullableText(json['liability_account_id']),
      liabilityAccountCode: _nullableText(json['liability_account_code']),
      legacyExpenseCategoryId:
          _nullableText(json['legacy_expense_category_id']),
      legacyExpenseCategoryName:
          _nullableText(json['legacy_expense_category_name']),
      rationale: _nullableText(json['rationale']),
      idempotentReplay: json['idempotent_replay'] as bool? ?? false,
      appliedSnapshot: _map(json['evidence'] ?? json['applied_snapshot']),
    );
  }

  final String id;
  final String tenantId;
  final String supplierId;
  final String operationId;
  final String sourceType;
  final String sourceId;
  final SupplierAccountingEvidenceDecision decision;
  final DateTime effectiveAt;
  final String operationalNatureCode;
  final String operationalNatureLabel;
  final String? policyVersionId;
  final String? ruleId;
  final String? sourceLineId;
  final String? debitAccountId;
  final String? debitAccountCode;
  final String? liabilityAccountId;
  final String? liabilityAccountCode;
  final String? legacyExpenseCategoryId;
  final String? legacyExpenseCategoryName;
  final String? rationale;
  final bool idempotentReplay;
  final Map<String, dynamic> appliedSnapshot;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'operation_id': operationId,
        'policy_version_id': policyVersionId,
        'rule_id': ruleId,
        'source_type': sourceType,
        'source_id': sourceId,
        'source_line_id': sourceLineId,
        'decision': decision.dbValue,
        'operational_nature_code': operationalNatureCode,
        'operational_nature_label': operationalNatureLabel,
        'debit_account_id': debitAccountId,
        'debit_account_code': debitAccountCode,
        'liability_account_id': liabilityAccountId,
        'liability_account_code': liabilityAccountCode,
        'legacy_expense_category_id': legacyExpenseCategoryId,
        'legacy_expense_category_name': legacyExpenseCategoryName,
        'rationale': rationale,
        'evidence': appliedSnapshot,
        'applied_at': effectiveAt.toUtc().toIso8601String(),
        'idempotent_replay': idempotentReplay,
      };
}

@immutable
class SupplierAccountingProfileSummary {
  SupplierAccountingProfileSummary({
    List<SupplierAccountingPolicySummary> policies = const [],
    List<SupplierAccountingRuleSummary> rules = const [],
    List<SupplierAccountingEvidenceSummary> recentEvidence = const [],
    List<String> observedAccountIds = const [],
    this.requiresClassificationReview,
  })  : policies = List.unmodifiable(policies),
        rules = List.unmodifiable(rules),
        recentEvidence = List.unmodifiable(recentEvidence),
        observedAccountIds = List.unmodifiable(observedAccountIds);

  factory SupplierAccountingProfileSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    return SupplierAccountingProfileSummary(
      policies: _mapList(json['policies'])
          .map(SupplierAccountingPolicySummary.fromJson)
          .toList(growable: false),
      rules: _mapList(json['rules'])
          .map(SupplierAccountingRuleSummary.fromJson)
          .toList(growable: false),
      recentEvidence: _mapList(json['recent_evidence'] ?? json['evidence'])
          .map(SupplierAccountingEvidenceSummary.fromJson)
          .toList(growable: false),
      observedAccountIds: _stringList(json['observed_account_ids']),
      requiresClassificationReview:
          json.containsKey('requires_classification_review')
              ? json['requires_classification_review'] as bool?
              : null,
    );
  }

  final List<SupplierAccountingPolicySummary> policies;
  final List<SupplierAccountingRuleSummary> rules;
  final List<SupplierAccountingEvidenceSummary> recentEvidence;
  final List<String> observedAccountIds;

  /// Null means the canonical server projection did not publish this signal;
  /// consumers must suppress the attention section instead of inferring it.
  final bool? requiresClassificationReview;
}

@immutable
class ReceivedTaxDocument {
  ReceivedTaxDocument({
    required this.id,
    required this.tenantId,
    required this.externalPartyId,
    required this.documentTypeCode,
    required this.normalizedFolio,
    required this.receivedAt,
    required this.status,
    this.supplierId,
    this.purchaseInvoiceId,
    this.displayFolio,
    this.issuedOn,
    this.netAmount = 0,
    this.exemptAmount = 0,
    this.taxAmount = 0,
    this.totalAmount = 0,
    this.currencyCode = 'CLP',
    this.source = 'manual',
    Map<String, dynamic> publicMetadata = const {},
    this.createdAt,
    this.updatedAt,
  }) : publicMetadata = _publicMap(publicMetadata);

  factory ReceivedTaxDocument.fromJson(Map<String, dynamic> json) {
    return ReceivedTaxDocument(
      id: _text(json['id']),
      tenantId: _text(json['tenant_id']),
      supplierId: _nullableText(json['supplier_id']),
      externalPartyId: _text(
        json['issuer_party_id'] ??
            json['external_party_id'] ??
            json['party_id'],
      ),
      purchaseInvoiceId: _nullableText(json['purchase_invoice_id']),
      documentTypeCode: _text(
        json['document_type_code'] ??
            json['document_kind'] ??
            json['document_type'],
      ),
      normalizedFolio: _text(
        json['normalized_folio'] ?? json['folio'] ?? json['document_number'],
      ),
      displayFolio: _nullableText(json['display_folio']),
      issuedOn: _date(json['issued_on'] ?? json['issue_date']),
      receivedAt:
          _date(json['received_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: ReceivedTaxDocumentStatus.fromJson(json['status']),
      netAmount: _number(json['net_amount']),
      exemptAmount: _number(json['exempt_amount']),
      taxAmount: _number(json['tax_amount']),
      totalAmount: _number(json['total_amount']),
      currencyCode: _text(json['currency_code'], fallback: 'CLP'),
      source: _text(json['source'], fallback: 'manual'),
      publicMetadata: _map(json['metadata']),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  final String id;
  final String tenantId;
  final String? supplierId;
  final String externalPartyId;
  final String? purchaseInvoiceId;
  final String documentTypeCode;
  final String normalizedFolio;
  final String? displayFolio;
  final DateTime? issuedOn;
  final DateTime receivedAt;
  final ReceivedTaxDocumentStatus status;
  final double netAmount;
  final double exemptAmount;
  final double taxAmount;
  final double totalAmount;
  final String currencyCode;
  final String source;
  final Map<String, dynamic> publicMetadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ReceivedTaxDocumentKind get kind =>
      ReceivedTaxDocumentKind.fromJson(documentTypeCode);

  String get folio => displayFolio ?? normalizedFolio;

  /// Stable issuer-scoped identity for duplicate detection. Database
  /// constraints remain the enforcement authority.
  String get naturalIdentity =>
      '$externalPartyId|$documentTypeCode|$normalizedFolio';

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        'issuer_party_id': externalPartyId,
        'supplier_id': supplierId,
        'purchase_invoice_id': purchaseInvoiceId,
        'document_type_code': documentTypeCode,
        'normalized_folio': normalizedFolio,
        'display_folio': displayFolio,
        'issued_on': issuedOn?.toIso8601String(),
        'received_at': receivedAt.toUtc().toIso8601String(),
        'currency_code': currencyCode,
        'net_amount': netAmount,
        'exempt_amount': exemptAmount,
        'tax_amount': taxAmount,
        'total_amount': totalAmount,
        'status': status.name,
        'source': source,
        'metadata': publicMetadata,
      };
}

@immutable
class SupplierEconomicAmountBreakdown {
  const SupplierEconomicAmountBreakdown({
    required this.documentCount,
    required this.paymentCount,
    required this.grossAmount,
    required this.paidAmount,
    required this.balanceAmount,
  });

  final int documentCount;
  final int paymentCount;
  final double? grossAmount;
  final double? paidAmount;
  final double? balanceAmount;
}

@immutable
class SupplierEconomicSummaryReadModel {
  const SupplierEconomicSummaryReadModel({
    required this.tenantId,
    required this.supplierId,
    required this.externalPartyId,
    required this.currencyCode,
    required this.purchases,
    required this.expenses,
    required this.totalDocumentCount,
    required this.paymentCount,
    required this.tracedDocumentCount,
    required this.untracedDocumentCount,
    required this.unclassifiedLineCount,
    required this.paymentStateAnomalyCount,
    required this.expensePaymentLedgerGapDocumentCount,
    required this.excludedLifecycleDocumentCount,
    required this.provenanceStatus,
    required this.dataQualityStatus,
    this.provenanceCoverage,
    this.lastActivityAt,
  });

  factory SupplierEconomicSummaryReadModel.fromJson(
    Map<String, dynamic> json,
  ) {
    SupplierEconomicAmountBreakdown breakdown(String prefix) {
      return SupplierEconomicAmountBreakdown(
        documentCount: _integer(json['${prefix}_document_count']),
        paymentCount: _integer(json['${prefix}_payment_count']),
        grossAmount: _nullableNumber(json['${prefix}_gross_amount']),
        paidAmount: _nullableNumber(json['${prefix}_paid_amount']),
        balanceAmount: _nullableNumber(json['${prefix}_balance_amount']),
      );
    }

    return SupplierEconomicSummaryReadModel(
      tenantId: _text(json['tenant_id']),
      supplierId: _text(json['supplier_id']),
      externalPartyId: _text(json['party_id']),
      currencyCode: _text(json['currency_code'], fallback: 'CLP'),
      purchases: breakdown('purchase'),
      expenses: breakdown('expense'),
      totalDocumentCount: _integer(json['total_document_count']),
      paymentCount: _integer(json['payment_count']),
      tracedDocumentCount: _integer(json['traced_document_count']),
      untracedDocumentCount: _integer(json['untraced_document_count']),
      unclassifiedLineCount: _integer(json['unclassified_line_count']),
      paymentStateAnomalyCount: _integer(json['payment_state_anomaly_count']),
      expensePaymentLedgerGapDocumentCount:
          _integer(json['expense_payment_ledger_gap_document_count']),
      excludedLifecycleDocumentCount:
          _integer(json['excluded_lifecycle_document_count']),
      provenanceCoverage: _nullableNumber(json['provenance_coverage']),
      provenanceStatus:
          _text(json['provenance_status'], fallback: 'not_applicable'),
      dataQualityStatus: SupplierEconomicDataQualityStatus.fromJson(
        json['data_quality_status'],
      ),
      lastActivityAt: _date(
        json['last_activity_at'] ?? json['last_movement_at'],
      ),
    );
  }

  final String tenantId;
  final String supplierId;
  final String externalPartyId;
  final String currencyCode;
  final SupplierEconomicAmountBreakdown purchases;
  final SupplierEconomicAmountBreakdown expenses;
  final int totalDocumentCount;
  final int paymentCount;
  final int tracedDocumentCount;
  final int untracedDocumentCount;
  final int unclassifiedLineCount;
  final int paymentStateAnomalyCount;
  final int expensePaymentLedgerGapDocumentCount;
  final int excludedLifecycleDocumentCount;
  final double? provenanceCoverage;
  final String provenanceStatus;
  final SupplierEconomicDataQualityStatus dataQualityStatus;
  final DateTime? lastActivityAt;
}

@immutable
class SupplierEconomicActivity {
  SupplierEconomicActivity({
    required this.tenantId,
    required this.supplierId,
    required this.externalPartyId,
    required this.id,
    required this.kind,
    required this.occurredAt,
    required this.currencyCode,
    required this.grossAmount,
    required this.paidAmount,
    required this.balanceAmount,
    required this.paymentCount,
    required this.isRecognized,
    required this.dataQualityStatus,
    this.documentNumber,
    this.documentStatus,
    this.paymentStatus,
    this.sourceDocumentId,
    Map<String, dynamic> publicMetadata = const {},
  }) : publicMetadata = _publicMap(publicMetadata);

  factory SupplierEconomicActivity.fromJson(Map<String, dynamic> json) {
    return SupplierEconomicActivity(
      tenantId: _text(json['tenant_id']),
      supplierId: _text(json['supplier_id']),
      externalPartyId: _text(json['party_id']),
      id: _text(json['event_id']),
      kind: SupplierEconomicActivityKind.fromJson(json['event_type']),
      occurredAt:
          _date(json['event_date']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      documentNumber: _nullableText(json['document_number']),
      documentStatus: _nullableText(json['event_status']),
      paymentStatus: _nullableText(json['payment_status']),
      currencyCode: _text(json['currency_code'], fallback: 'CLP'),
      grossAmount: _number(json['gross_amount']),
      paidAmount: _number(json['paid_amount']),
      balanceAmount: _nullableNumber(json['balance_amount']),
      paymentCount: _integer(json['payment_count']),
      isRecognized: json['is_recognized'] as bool? ?? false,
      dataQualityStatus: SupplierEconomicDataQualityStatus.fromJson(
        json['data_quality_status'],
      ),
      sourceDocumentId: _nullableText(json['source_document_id']),
      publicMetadata: _map(json['metadata']),
    );
  }

  final String tenantId;
  final String supplierId;
  final String externalPartyId;
  final String id;
  final SupplierEconomicActivityKind kind;
  final DateTime occurredAt;
  final String? documentNumber;
  final String? documentStatus;
  final String? paymentStatus;
  final String currencyCode;
  final double grossAmount;
  final double paidAmount;
  final double? balanceAmount;
  final int paymentCount;
  final bool isRecognized;
  final SupplierEconomicDataQualityStatus dataQualityStatus;
  final String? sourceDocumentId;
  final Map<String, dynamic> publicMetadata;
}

/// Timeline projection. Amount summaries intentionally do not live here:
/// consumers must read [SupplierEconomicSummaryReadModel] instead of adding
/// heterogeneous purchase, expense and payment events in Flutter.
@immutable
class SupplierEconomicReadModel {
  SupplierEconomicReadModel({
    required this.tenantId,
    required this.supplierId,
    List<SupplierEconomicActivity> activities = const [],
  }) : activities = List.unmodifiable(activities);

  factory SupplierEconomicReadModel.fromRows(
    List<Map<String, dynamic>> rows, {
    String? tenantId,
    String? supplierId,
  }) {
    if (rows.isEmpty) {
      if (tenantId == null || supplierId == null) {
        throw const FormatException(
          'An empty economic timeline requires its authority scope',
        );
      }
      return SupplierEconomicReadModel(
        tenantId: tenantId,
        supplierId: supplierId,
      );
    }
    final activities = rows
        .map(SupplierEconomicActivity.fromJson)
        .toList(growable: false)
      ..sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    final first = activities.first;
    if (activities.any(
      (item) =>
          item.tenantId != first.tenantId ||
          item.supplierId != first.supplierId,
    )) {
      throw const FormatException('Economic timeline mixed authority scopes');
    }
    return SupplierEconomicReadModel(
      tenantId: first.tenantId,
      supplierId: first.supplierId,
      activities: activities,
    );
  }

  final String tenantId;
  final String supplierId;
  final List<SupplierEconomicActivity> activities;
}

@immutable
class SupplierValidationIncident {
  const SupplierValidationIncident({
    required this.code,
    required this.severity,
    required this.scopeType,
    required this.scopeId,
    required this.displayReason,
    required this.source,
    required this.status,
    this.relatedCode,
    this.fieldKey,
  });

  factory SupplierValidationIncident.fromJson(Map<String, dynamic> json) {
    return SupplierValidationIncident(
      code: _requiredTextValue(json['code'], 'validation_incident.code'),
      severity: SupplierValidationIncidentSeverity.fromJson(json['severity']),
      scopeType: SupplierValidationIncidentScopeType.fromJson(
        json['scope_type'],
      ),
      scopeId: _requiredTextValue(
        json['scope_id'],
        'validation_incident.scope_id',
      ),
      relatedCode: _nullableText(json['related_code']),
      fieldKey: _nullableText(json['field_key']),
      displayReason: _requiredTextValue(
        json['display_reason'],
        'validation_incident.display_reason',
      ),
      source: SupplierValidationIncidentSource.fromJson(json['source']),
      status: SupplierValidationIncidentStatus.fromJson(json['status']),
    );
  }

  final String code;
  final SupplierValidationIncidentSeverity severity;
  final SupplierValidationIncidentScopeType scopeType;
  final String scopeId;
  final String? relatedCode;

  /// Routing metadata only. User-facing copy always comes from
  /// [displayReason], never from this database/schema key.
  final String? fieldKey;
  final String displayReason;
  final SupplierValidationIncidentSource source;
  final SupplierValidationIncidentStatus status;
}

/// Server-owned attention and coverage signals from
/// `supplier_profile_read_model`.
///
/// A null [SupplierProfile.attentionSignals] means that the active database
/// projection does not publish this contract (for example, the staged legacy
/// fallback). Consumers must suppress attention UI in that state and must not
/// derive an equivalent from contact, tax, classification, or policy fields.
@immutable
class SupplierProfileAttentionSignals {
  SupplierProfileAttentionSignals({
    required this.recognizedDocumentCount,
    required this.validationIssueCount,
    required this.dataCompletenessStatus,
    required this.classificationStatus,
    required this.accountingPolicyStatus,
    required List<SupplierValidationIncident> validationIncidents,
  }) : validationIncidents = List.unmodifiable(validationIncidents);

  static SupplierProfileAttentionSignals? tryFromJson(
    Map<String, dynamic> json,
  ) {
    const requiredKeys = {
      'recognized_document_count',
      'validation_issue_count',
      'validation_incidents',
      'data_completeness_status',
      'classification_status',
      'accounting_policy_status',
    };
    if (!requiredKeys.every(json.containsKey)) return null;
    final incidents = _mapList(json['validation_incidents'])
        .map(SupplierValidationIncident.fromJson)
        .toList(growable: false);
    final validationIssueCount = _integer(json['validation_issue_count']);
    if (validationIssueCount != incidents.length) {
      throw const FormatException(
        'Supplier validation incident count does not match its projection',
      );
    }
    return SupplierProfileAttentionSignals(
      recognizedDocumentCount: _integer(json['recognized_document_count']),
      validationIssueCount: validationIssueCount,
      dataCompletenessStatus: SupplierProfileDataCompletenessStatus.fromJson(
        json['data_completeness_status'],
      ),
      classificationStatus: SupplierProfileClassificationStatus.fromJson(
        json['classification_status'],
      ),
      accountingPolicyStatus: SupplierProfileAccountingPolicyStatus.fromJson(
        json['accounting_policy_status'],
      ),
      validationIncidents: incidents,
    );
  }

  final int recognizedDocumentCount;
  final int validationIssueCount;
  final SupplierProfileDataCompletenessStatus dataCompletenessStatus;
  final SupplierProfileClassificationStatus classificationStatus;
  final SupplierProfileAccountingPolicyStatus accountingPolicyStatus;
  final List<SupplierValidationIncident> validationIncidents;
}

@immutable
class SupplierProfile {
  SupplierProfile({
    required this.party,
    required this.relationship,
    List<BusinessSite> sites = const [],
    List<SupplierEngagement> engagements = const [],
    SupplierClassificationHistory? classificationHistory,
    SupplierAccountingProfileSummary? accounting,
    SupplierLegacyOperationalDetails? legacyDetails,
    this.receivedTaxDocumentCount = 0,
    this.activeEngagementCount = 0,
    this.activePolicyCount = 0,
    this.effectiveBusinessDate,
    this.attentionSignals,
    this.dataSource = SupplierProfileDataSource.foundation,
  })  : assert(party.tenantId == relationship.tenantId),
        assert(party.id == relationship.externalPartyId),
        sites = List.unmodifiable(sites),
        engagements = List.unmodifiable(engagements),
        classificationHistory =
            classificationHistory ?? SupplierClassificationHistory(),
        accounting = accounting ?? SupplierAccountingProfileSummary(),
        legacyDetails =
            legacyDetails ?? const SupplierLegacyOperationalDetails();

  factory SupplierProfile.fromJson(Map<String, dynamic> json) {
    final relationshipJson =
        _map(json['relationship']).isEmpty ? json : _map(json['relationship']);
    var partyJson = _map(json['party']);
    if (partyJson.isEmpty) {
      partyJson = <String, dynamic>{
        'id': json['party_id'],
        'tenant_id': json['tenant_id'],
        'party_kind': json['party_kind'],
        'display_name': json['party_display_name'] ?? json['display_name'],
        'legal_name': json['party_legal_name'] ?? json['legal_name'],
        'trade_name': json['party_trade_name'] ?? json['trade_name'],
        'aliases': json['party_aliases'] ?? json['aliases'],
        'country_code': json['country_code'],
        'notes': json['party_notes'],
        'metadata': json['party_metadata'],
        'identifiers': json['party_identifiers'] ??
            json['identifiers'] ??
            [
              if (_nullableText(json['tax_identifier']) != null)
                {
                  'id': json['tax_identifier_id'] ?? '',
                  'tenant_id': json['tenant_id'],
                  'party_id': json['party_id'],
                  'identifier_kind': 'tax_id',
                  'display_value': json['tax_identifier'],
                  'normalized_value': json['tax_identifier'],
                  'country_code': json['tax_country_code'] ?? 'CL',
                  'is_primary': true,
                },
            ],
        'is_active': json['party_is_active'] ?? json['is_active'],
        'created_at': json['party_created_at'],
        'updated_at': json['party_updated_at'],
      };
    }
    final historyJson = _map(json['classification_history']);
    final relationshipTenantId = _text(
      relationshipJson['tenant_id'] ?? json['tenant_id'],
    );
    final relationshipId = _text(
      relationshipJson['id'] ??
          relationshipJson['supplier_id'] ??
          json['supplier_id'],
    );
    return SupplierProfile(
      party: ExternalParty.fromJson(partyJson),
      relationship: SupplierRelationship.fromJson(relationshipJson),
      sites: _mapList(json['sites'])
          .map(BusinessSite.fromJson)
          .toList(growable: false),
      engagements: _mapList(json['engagements'])
          .map(SupplierEngagement.fromJson)
          .toList(growable: false),
      classificationHistory: SupplierClassificationHistory(
        roles: _scopedItems(
          historyJson['roles'],
          tenantId: relationshipTenantId,
          supplierId: relationshipId,
        ).map(SupplierRole.fromJson).toList(growable: false),
        capabilities: _scopedItems(
          historyJson['capabilities'],
          tenantId: relationshipTenantId,
          supplierId: relationshipId,
        ).map(SupplierCapability.fromJson).toList(growable: false),
        tags: _scopedItems(
          historyJson['tags'],
          tenantId: relationshipTenantId,
          supplierId: relationshipId,
        ).map(SupplierTag.fromJson).toList(growable: false),
      ),
      accounting: SupplierAccountingProfileSummary.fromJson(
        _map(json['accounting']),
      ),
      legacyDetails: SupplierLegacyOperationalDetails.fromJson(json),
      receivedTaxDocumentCount: _integer(json['received_tax_document_count']),
      activeEngagementCount: _integer(json['active_engagement_count']),
      activePolicyCount: _integer(json['active_policy_count']),
      effectiveBusinessDate: _date(json['effective_business_date']),
      attentionSignals: SupplierProfileAttentionSignals.tryFromJson(json),
      dataSource: SupplierProfileDataSource.foundation,
    );
  }

  final ExternalParty party;
  final SupplierRelationship relationship;
  final List<BusinessSite> sites;
  final List<SupplierEngagement> engagements;
  final SupplierClassificationHistory classificationHistory;
  final SupplierAccountingProfileSummary accounting;
  final SupplierLegacyOperationalDetails legacyDetails;
  final int receivedTaxDocumentCount;
  final int activeEngagementCount;
  final int activePolicyCount;

  /// Canonical tenant-local civil date used by every effective relationship,
  /// engagement, and policy projection in this profile.
  final DateTime? effectiveBusinessDate;
  final SupplierProfileAttentionSignals? attentionSignals;
  final SupplierProfileDataSource dataSource;

  String get displayName => party.displayName;

  String? get serviceRelationshipSummary =>
      relationship.serviceRelationshipSummary;

  bool get classificationWritesAvailable =>
      dataSource == SupplierProfileDataSource.foundation;
}

String _text(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String? _nullableText(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _requiredTextValue(dynamic value, String field) {
  final text = _nullableText(value);
  if (text == null) throw FormatException('Missing $field');
  return text;
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

bool _dateRangeContains(
  DateTime instant,
  DateTime? startsOn,
  DateTime? endsOn,
) {
  DateTime day(DateTime value) => DateTime(value.year, value.month, value.day);
  final target = day(instant);
  return (startsOn == null || !target.isBefore(day(startsOn))) &&
      (endsOn == null || !target.isAfter(day(endsOn)));
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double? _nullableNumber(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int _integer(dynamic value, {int fallback = 0}) {
  return _nullableInteger(value) ?? fallback;
}

int? _nullableInteger(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => item.map(
            (key, child) => MapEntry(key.toString(), child),
          ))
      .toList(growable: false);
}

List<Map<String, dynamic>> _scopedItems(
  dynamic value, {
  required String tenantId,
  required String supplierId,
}) {
  return _mapList(value)
      .map(
        (item) => <String, dynamic>{
          ...item,
          'tenant_id': item['tenant_id'] ?? tenantId,
          'supplier_id': item['supplier_id'] ?? supplierId,
        },
      )
      .toList(growable: false);
}

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  final text = _nullableText(value);
  if (text == null) return const [];
  return text
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, dynamic> _publicMap(Map<String, dynamic> source) {
  final safe = <String, dynamic>{};
  for (final entry in source.entries) {
    if (_isReservedPublicKey(entry.key)) {
      continue;
    }
    safe[entry.key] = _publicValue(entry.value);
  }
  return Map.unmodifiable(safe);
}

bool _isReservedPublicKey(String key) {
  final normalized = key.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();
  return RegExp(
    'password|secret|token|apikey|privatekey|passcode|authorization|bearer|credential',
  ).hasMatch(normalized);
}

dynamic _publicValue(dynamic value) {
  if (value is Map) return _publicMap(_map(value));
  if (value is Iterable) {
    return List<dynamic>.unmodifiable(value.map(_publicValue));
  }
  return value;
}

/// Una persona del proveedor: a quien se le escribe, con cargo, WhatsApp y
/// correo. Una es la principal (el destino del ERP); las demás pueden estar
/// activas o desactivadas. Desactivar conserva sus chats y archivos: nunca
/// se borra.
@immutable
class SupplierContact {
  const SupplierContact({
    required this.id,
    required this.tenantId,
    required this.supplierId,
    required this.name,
    this.role,
    this.phone,
    this.email,
    this.notes,
    this.isPrimary = false,
    this.isActive = true,
    this.deactivatedAt,
    this.source = 'manual',
    required this.updatedAt,
  });

  factory SupplierContact.fromJson(Map<String, dynamic> json) {
    return SupplierContact(
      id: json['id'].toString(),
      tenantId: json['tenant_id'].toString(),
      supplierId: json['supplier_id'].toString(),
      name: json['name']?.toString().trim() ?? '',
      role: _nullableText(json['role']),
      phone: _nullableText(json['phone']),
      email: _nullableText(json['email']),
      notes: _nullableText(json['notes']),
      isPrimary: json['is_primary'] == true,
      isActive: json['is_active'] != false,
      deactivatedAt: _nullableText(json['deactivated_at']) == null
          ? null
          : DateTime.parse(json['deactivated_at'].toString()).toUtc(),
      source: json['source']?.toString() ?? 'manual',
      updatedAt: DateTime.parse(json['updated_at'].toString()).toUtc(),
    );
  }

  final String id;
  final String tenantId;
  final String supplierId;
  final String name;
  final String? role;
  final String? phone;
  final String? email;
  final String? notes;
  final bool isPrimary;
  final bool isActive;
  final DateTime? deactivatedAt;

  /// `manual`, `sales_rep_backfill` o `whatsapp_backfill`: el último es una
  /// persona que el ERP conoció por un hilo y a la que nadie ha puesto nombre.
  final String source;
  final DateTime updatedAt;

  bool get hasPhone => (phone ?? '').trim().isNotEmpty;
  bool get wasDiscoveredFromWhatsApp => source == 'whatsapp_backfill';
}
