import '../../../shared/models/supplier.dart';
import '../../../shared/models/supplier_ocr_template.dart';
import 'supplier_foundation.dart';

/// Explicit compatibility boundary while the existing `suppliers` row evolves
/// into [SupplierRelationship]. It never transports credentials and it does
/// not infer accounting behavior from the legacy SupplierType field.
abstract final class LegacySupplierAdapter {
  static SupplierProfile toProfile(
    Supplier supplier, {
    ExternalPartyKind partyKind = ExternalPartyKind.other,
    List<SupplierRole> roles = const [],
    List<SupplierCapability> capabilities = const [],
    List<SupplierTag> tags = const [],
    bool? hasCredentialReference,
    String? externalPartyId,
    SupplierAccountingProfileSummary? accounting,
  }) {
    final partyId = externalPartyId ?? supplier.id;
    final identifiers = <ExternalPartyIdentifier>[
      if ((supplier.rut ?? '').trim().isNotEmpty)
        ExternalPartyIdentifier(
          id: '',
          tenantId: supplier.tenantId,
          externalPartyId: partyId,
          kind: 'tax_id',
          value: supplier.rut!.trim(),
          normalizedValue: supplier.rut!.replaceAll(RegExp(r'[^0-9kK]'), ''),
          issuerCountry: 'CL',
          isPrimary: true,
        ),
    ];
    final party = ExternalParty(
      id: partyId,
      tenantId: supplier.tenantId,
      kind: partyKind,
      name: supplier.displayName,
      legalName: _nullable(supplier.legalName),
      tradeName: _nullable(supplier.tradeName),
      aliases: supplier.aliases,
      identifiers: identifiers,
      isActive: supplier.isActive,
      createdAt: supplier.createdAt,
      updatedAt: supplier.updatedAt,
    );
    final relationship = SupplierRelationship(
      id: supplier.id,
      tenantId: supplier.tenantId,
      externalPartyId: partyId,
      name: supplier.name,
      status: supplier.isActive
          ? SupplierRelationshipStatus.active
          : SupplierRelationshipStatus.inactive,
      email: supplier.email,
      phone: supplier.phone,
      contactPerson: supplier.contactPerson,
      website: supplier.website,
      notes: supplier.notes,
      paymentTermsCode: supplier.paymentTerms.name,
      roles: roles,
      capabilities: capabilities,
      tags: tags,
      hasCredentialReference: hasCredentialReference,
      createdAt: supplier.createdAt,
      updatedAt: supplier.updatedAt,
    );
    return SupplierProfile(
      party: party,
      relationship: relationship,
      accounting: accounting,
      legacyDetails: SupplierLegacyOperationalDetails(
        address: supplier.address,
        city: supplier.city,
        region: supplier.region,
        comuna: supplier.comuna,
        salesRepName: supplier.salesRepName,
        salesRepPhone: supplier.salesRepPhone,
        salesRepEmail: supplier.salesRepEmail,
        type: supplier.type,
        paymentTerms: supplier.paymentTerms,
        defaultTaxTreatment: supplier.defaultTaxTreatment,
      ),
      dataSource: SupplierProfileDataSource.legacyReadOnly,
    );
  }

  static Supplier toLegacy(
    SupplierProfile profile, {
    Supplier? previous,
  }) {
    final relationship = profile.relationship;
    final party = profile.party;
    if (relationship.id.isEmpty) {
      throw ArgumentError.value(
        relationship.id,
        'profile.relationship.id',
        'The compatibility supplier ID must be durable',
      );
    }
    final primaryRut = party.identifiers
        .where((item) =>
            (item.kind == 'tax_id' || item.kind == 'cl_rut') && item.isPrimary)
        .map((item) => item.value)
        .firstOrNull;
    final now = DateTime.now().toUtc();
    return Supplier(
      id: relationship.id,
      tenantId: relationship.tenantId,
      name: relationship.name,
      legalName: party.legalName,
      tradeName: party.tradeName,
      ownerName: previous?.ownerName,
      aliases: party.aliases,
      email: relationship.email,
      phone: relationship.phone,
      rut: primaryRut ?? previous?.rut,
      address: profile.legacyDetails.address,
      city: profile.legacyDetails.city,
      region: profile.legacyDetails.region,
      comuna: profile.legacyDetails.comuna,
      type: profile.legacyDetails.type,
      contactPerson: relationship.contactPerson,
      website: relationship.website,
      bankDetails: previous?.bankDetails ?? const {},
      paymentTerms: _paymentTerms(
        relationship.paymentTermsCode,
        profile.legacyDetails.paymentTerms,
      ),
      defaultTaxTreatment: profile.legacyDetails.defaultTaxTreatment,
      imageUrl: previous?.imageUrl,
      salesRepName:
          profile.legacyDetails.salesRepName ?? previous?.salesRepName,
      salesRepPhone:
          profile.legacyDetails.salesRepPhone ?? previous?.salesRepPhone,
      salesRepEmail:
          profile.legacyDetails.salesRepEmail ?? previous?.salesRepEmail,
      purchaseInstructions: previous?.purchaseInstructions,
      ocrTemplate: previous?.ocrTemplate ?? const SupplierOcrTemplate(),
      notes: relationship.notes,
      isActive: relationship.isActive,
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    );
  }

  static String? _nullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static PaymentTerms _paymentTerms(
    String? raw,
    PaymentTerms? fallback,
  ) {
    return PaymentTerms.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => fallback ?? PaymentTerms.net30,
    );
  }
}
