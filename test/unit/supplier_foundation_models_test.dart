// ignore_for_file: prefer_const_literals_to_create_immutables

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/legacy_supplier_adapter.dart';
import 'package:vinabike_erp/modules/purchases/models/supplier_foundation.dart';
import 'package:vinabike_erp/shared/models/supplier.dart';
import 'package:vinabike_erp/shared/models/supplier_ocr_template.dart';

void main() {
  const tenantId = '10000000-0000-0000-0000-000000000001';
  const supplierId = '20000000-0000-0000-0000-000000000002';
  const partyId = '30000000-0000-0000-0000-000000000003';

  group('supplier foundation database vocabulary', () {
    test('writes the exact closed enum values', () {
      expect(
        ExternalPartyKind.publicAuthority.dbValue,
        'government_entity',
      );
      expect(
        SupplierEngagementKind.serviceAccount.dbValue,
        'service_account',
      );
      expect(
        SupplierEngagementKind.taxObligation.dbValue,
        'tax_obligation',
      );
      expect(
        SupplierAccountingEvidenceDecision.autoFilled.dbValue,
        'auto_filled',
      );
      expect(
        ReceivedTaxDocumentStatus.values.map((item) => item.name),
        ['captured', 'validated', 'linked', 'voided'],
      );
    });

    test('assignment dates are inclusive and writes match real columns', () {
      final role = SupplierRole.fromJson({
        'id': 'role-1',
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'role_code': 'goods_vendor',
        'assignment_source': 'manual',
        'valid_from': '2026-08-01',
        'valid_to': '2026-08-08',
        'metadata': {'source_note': 'confirmed'},
      });
      final capability = SupplierCapability.fromJson({
        'id': 'capability-1',
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'capability_code': 'portal_access',
        'assignment_source': 'observed',
        'valid_from': '2026-08-01',
        'valid_to': '2026-08-08',
        'metadata': {'url': 'https://supplier.example'},
      });

      expect(role.isEffectiveAt(DateTime(2026, 8, 8, 23, 59)), isTrue);
      expect(role.isEffectiveAt(DateTime(2026, 8, 9)), isFalse);
      expect(
        role.toJson().keys,
        containsAll([
          'role_code',
          'assignment_source',
          'metadata',
          'valid_from',
          'valid_to',
        ]),
      );
      expect(capability.isEffectiveAt(DateTime(2026, 8, 8, 23, 59)), isTrue);
      expect(capability.toJson()['capability_code'], 'portal_access');
      expect(capability.toJson(), isNot(contains('is_enabled')));
      expect(capability.toJson(), isNot(contains('public_configuration')));
      expect(capability.toJson(), isNot(contains('valid_until')));
    });

    test('engagement and accounting versions use effective dates inclusively',
        () {
      final engagementVersion = SupplierEngagementVersion.fromJson({
        'id': 'engagement-version-1',
        'tenant_id': tenantId,
        'engagement_id': 'engagement-1',
        'version_number': 2,
        'effective_from': '2026-01-01',
        'effective_to': '2026-08-08',
        'billing_cycle': 'monthly',
      });
      final policyVersion = SupplierAccountingPolicyVersionSummary.fromJson({
        'id': 'policy-version-1',
        'tenant_id': tenantId,
        'policy_id': 'policy-1',
        'version_number': 3,
        'effective_from': '2026-01-01',
        'effective_to': '2026-08-08',
        'operational_nature_code': 'inventory',
      });

      expect(
        engagementVersion.isEffectiveAt(DateTime(2026, 8, 8, 23, 59)),
        isTrue,
      );
      expect(
        engagementVersion.isEffectiveAt(DateTime(2026, 8, 9)),
        isFalse,
      );
      expect(engagementVersion.toJson()['effective_from'], isNotNull);
      expect(engagementVersion.toJson()['effective_to'], isNotNull);
      expect(policyVersion.isEffectiveAt(DateTime(2026, 8, 8, 23, 59)), true);
      expect(policyVersion.isEffectiveAt(DateTime(2026, 8, 9)), false);
    });

    test('current versions require the server-owned tenant business date', () {
      Map<String, dynamic> engagementJson({String? businessDate}) => {
            'id': 'engagement-1',
            'tenant_id': tenantId,
            'supplier_id': supplierId,
            'engagement_kind': 'subscription',
            'code': 'workspace',
            'name': 'Workspace',
            'status': 'active',
            if (businessDate != null) 'effective_business_date': businessDate,
            'versions': [
              {
                'id': 'engagement-version-1',
                'tenant_id': tenantId,
                'engagement_id': 'engagement-1',
                'version_number': 1,
                'effective_from': '2026-08-08',
                'effective_to': '2026-08-08',
                'billing_cycle': 'free',
              },
              {
                'id': 'engagement-version-2',
                'tenant_id': tenantId,
                'engagement_id': 'engagement-1',
                'version_number': 2,
                'effective_from': '2026-08-09',
                'billing_cycle': 'monthly',
              },
            ],
          };
      Map<String, dynamic> policyJson({String? businessDate}) => {
            'id': 'policy-1',
            'tenant_id': tenantId,
            'supplier_id': supplierId,
            'code': 'workspace-default',
            'name': 'Workspace',
            'status': 'active',
            if (businessDate != null) 'effective_business_date': businessDate,
            'versions': [
              {
                'id': 'policy-version-1',
                'tenant_id': tenantId,
                'policy_id': 'policy-1',
                'version_number': 1,
                'effective_from': '2026-08-08',
                'effective_to': '2026-08-08',
                'operational_nature_code': 'digital_service',
              },
              {
                'id': 'policy-version-2',
                'tenant_id': tenantId,
                'policy_id': 'policy-1',
                'version_number': 2,
                'effective_from': '2026-08-09',
                'operational_nature_code': 'digital_subscription',
              },
            ],
          };

      expect(
        SupplierEngagement.fromJson(
          engagementJson(businessDate: '2026-08-08'),
        ).currentVersion?.version,
        1,
      );
      expect(
        SupplierEngagement.fromJson(
          engagementJson(businessDate: '2026-08-08'),
        ).latestVersion?.version,
        2,
      );
      expect(
        SupplierAccountingPolicySummary.fromJson(
          policyJson(businessDate: '2026-08-08'),
        ).currentVersion?.version,
        1,
      );
      expect(
        SupplierAccountingPolicySummary.fromJson(
          policyJson(businessDate: '2026-08-08'),
        ).latestVersion?.version,
        2,
      );
      expect(
        SupplierEngagement.fromJson(engagementJson()).currentVersion,
        isNull,
      );
      expect(
        SupplierEngagement.fromJson(engagementJson()).latestVersion?.version,
        2,
      );
      expect(
        SupplierAccountingPolicySummary.fromJson(policyJson()).currentVersion,
        isNull,
      );
      expect(
        SupplierAccountingPolicySummary.fromJson(policyJson())
            .latestVersion
            ?.version,
        2,
      );
    });
  });

  group('secret-free public metadata', () {
    test('sanitizes reserved material recursively through lists', () {
      final capability = SupplierCapability.fromJson({
        'id': 'capability-1',
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'capability_code': 'portal_access',
        'metadata': {
          'safe': [
            {
              'label': 'Portal',
              'password': 'must-not-survive',
              'nested': {
                'api_token': 'must-not-survive',
                'api-key': 'must-not-survive',
                'private_key': 'must-not-survive',
                'authorization': 'must-not-survive',
                'bearer': 'must-not-survive',
                'passcode': 'must-not-survive',
                'url': 'https://supplier.example',
              },
            },
          ],
          'credential_hint': 'must-not-survive',
        },
      });

      final safe = capability.publicConfiguration['safe'] as List<dynamic>;
      final first = safe.single as Map<String, dynamic>;
      final nested = first['nested'] as Map<String, dynamic>;
      expect(first, isNot(contains('password')));
      expect(nested, isNot(contains('api_token')));
      expect(nested, isNot(contains('api-key')));
      expect(nested, isNot(contains('private_key')));
      expect(nested, isNot(contains('authorization')));
      expect(nested, isNot(contains('bearer')));
      expect(nested, isNot(contains('passcode')));
      expect(nested['url'], 'https://supplier.example');
      expect(
        capability.publicConfiguration,
        isNot(contains('credential_hint')),
      );
    });
  });

  group('profile and legacy compatibility', () {
    test('canonical any-credential projection wins the legacy portal flag', () {
      final relationship = SupplierRelationship.fromJson(const {
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'party_id': partyId,
        'display_name': 'API only',
        'is_active': true,
        'has_credential_reference': true,
        'has_portal_credential': false,
      });

      expect(relationship.hasCredentialReference, isTrue);
    });

    test('maps the secret-free profile view without claiming credential state',
        () {
      final profile = SupplierProfile.fromJson({
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'party_id': partyId,
        'party_kind': 'organization',
        'display_name': 'Andes Industrial',
        'legal_name': 'Andes Industrial SpA',
        'trade_name': 'Andes',
        'tax_identifier': '76.123.456-7',
        'is_active': true,
        'email': 'compras@andes.example',
        'relationship_roles': [
          {
            'code': 'goods_vendor',
            'valid_from': '2026-01-01',
            'source': 'manual',
          },
        ],
        'relationship_capabilities': [
          {
            'code': 'product_catalog',
            'valid_from': '2026-01-01',
            'source': 'observed',
          },
        ],
        'relationship_tags': [
          {
            'code': 'bike_parts',
            'label': 'Repuestos bicicleta',
            'valid_from': '2026-01-01',
            'source': 'manual',
          },
        ],
        'active_engagement_count': 2,
        'active_policy_count': 1,
        'effective_business_date': '2026-08-08',
        'recognized_document_count': 8,
        'validation_issue_count': 1,
        'validation_incidents': [
          {
            'code': 'legacy_portal_origin_not_canonical',
            'severity': 'warning',
            'scope_type': 'credential',
            'scope_id': supplierId,
            'related_code': 'portal_password',
            'field_key': 'origin_url',
            'display_reason':
                'El origen del portal heredado necesita revisión.',
            'source': 'migration_validation',
            'status': 'pending',
          },
        ],
        'data_completeness_status': 'partial',
        'classification_status': 'classified',
        'accounting_policy_status': 'configured',
      });

      expect(profile.party.id, partyId);
      expect(profile.party.identifiers.single.kind, 'tax_id');
      expect(profile.party.identifiers.single.tenantId, tenantId);
      expect(profile.relationship.id, supplierId);
      expect(
          profile.relationship.roles.single.kind, SupplierRoleKind.goodsVendor);
      expect(profile.relationship.hasCredentialReference, isNull);
      expect(profile.activeEngagementCount, 2);
      expect(profile.activePolicyCount, 1);
      expect(profile.effectiveBusinessDate, DateTime(2026, 8, 8));
      expect(profile.attentionSignals?.recognizedDocumentCount, 8);
      expect(profile.attentionSignals?.validationIssueCount, 1);
      expect(
        profile.attentionSignals?.validationIncidents.single.displayReason,
        'El origen del portal heredado necesita revisión.',
      );
      expect(
        profile.attentionSignals?.validationIncidents.single.fieldKey,
        'origin_url',
      );
      expect(
        profile.attentionSignals?.dataCompletenessStatus,
        SupplierProfileDataCompletenessStatus.partial,
      );
      expect(
        profile.attentionSignals?.classificationStatus,
        SupplierProfileClassificationStatus.classified,
      );
      expect(
        profile.attentionSignals?.accountingPolicyStatus,
        SupplierProfileAccountingPolicyStatus.configured,
      );
      expect(profile.dataSource, SupplierProfileDataSource.foundation);
      expect(profile.classificationWritesAvailable, isTrue);
    });

    test('legacy adapter preserves identity without inventing classifications',
        () {
      final createdAt = DateTime.utc(2025, 1, 1);
      final supplier = Supplier(
        id: supplierId,
        tenantId: tenantId,
        name: 'Proveedor sin clasificar',
        rut: '76.123.456-7',
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final profile = LegacySupplierAdapter.toProfile(supplier);

      expect(profile.party.id, supplierId);
      expect(profile.party.kind, ExternalPartyKind.other);
      expect(profile.party.legalName, isNull);
      expect(profile.party.tradeName, isNull);
      expect(profile.relationship.id, supplierId);
      expect(profile.relationship.roles, isEmpty);
      expect(profile.relationship.capabilities, isEmpty);
      expect(profile.relationship.tags, isEmpty);
      expect(profile.accounting.policies, isEmpty);
      expect(profile.party.identifiers.single.kind, 'tax_id');
      expect(profile.attentionSignals, isNull);
      expect(profile.dataSource, SupplierProfileDataSource.legacyReadOnly);
      expect(profile.classificationWritesAvailable, isFalse);

      final roundTrip = LegacySupplierAdapter.toLegacy(profile);
      expect(roundTrip.id, supplierId);
      expect(roundTrip.legalName, isNull);
      expect(roundTrip.tradeName, isNull);
    });

    test('legacy supplier reads and writes remain OCR-safe and secret-free',
        () {
      expect(Supplier.secretFreeSelect, isNot(contains('portal_username')));
      expect(Supplier.secretFreeSelect, isNot(contains('portal_password')));
      expect(Supplier.secretFreeSelect, contains('ocr_template'));

      final now = DateTime.utc(2026, 8, 8);
      final supplier = Supplier(
        id: supplierId,
        tenantId: tenantId,
        name: 'OCR supplier',
        ocrTemplate: const SupplierOcrTemplate(
          enabled: true,
          discountParser: SupplierOcrDiscountParser.anchoredTrailingNumeric,
        ),
        createdAt: now,
        updatedAt: now,
      );
      expect(supplier.toJson()['ocr_template'], {
        'enabled': true,
        'discount_parser': 'anchoredTrailingNumeric',
      });
      expect(supplier.toJson(), isNot(contains('portal_password')));
    });
  });

  group('economic projections', () {
    test('keeps purchases and expenses in separate monetary universes', () {
      final summary = SupplierEconomicSummaryReadModel.fromJson({
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'party_id': partyId,
        'currency_code': 'CLP',
        'purchase_document_count': 2,
        'purchase_gross_amount': 100000,
        'purchase_paid_amount': 60000,
        'purchase_balance_amount': 40000,
        'purchase_payment_count': 1,
        'expense_document_count': 3,
        'expense_gross_amount': 50000,
        'expense_paid_amount': 50000,
        'expense_balance_amount': 0,
        'expense_payment_count': 2,
        'payment_count': 3,
        'total_document_count': 5,
        'traced_document_count': 4,
        'untraced_document_count': 1,
        'unclassified_line_count': 2,
        'payment_state_anomaly_count': 1,
        'expense_payment_ledger_gap_document_count': 2,
        'excluded_lifecycle_document_count': 3,
        'provenance_coverage': 0.8,
        'provenance_status': 'partial',
        'data_quality_status': 'needs_review',
        'last_activity_at': '2026-08-08',
      });

      expect(summary.purchases.grossAmount, 100000);
      expect(summary.expenses.grossAmount, 50000);
      expect(summary.totalDocumentCount, 5);
      expect(summary.paymentCount, 3);
      expect(summary.tracedDocumentCount, 4);
      expect(summary.untracedDocumentCount, 1);
      expect(summary.unclassifiedLineCount, 2);
      expect(summary.paymentStateAnomalyCount, 1);
      expect(summary.expensePaymentLedgerGapDocumentCount, 2);
      expect(summary.excludedLifecycleDocumentCount, 3);
      expect(summary.provenanceCoverage, 0.8);
      expect(
        summary.dataQualityStatus,
        SupplierEconomicDataQualityStatus.needsReview,
      );
      expect(summary.lastActivityAt, DateTime.parse('2026-08-08'));
    });

    test('timeline supports suppliers with no economic activity', () {
      final timeline = SupplierEconomicReadModel.fromRows(
        const [],
        tenantId: tenantId,
        supplierId: supplierId,
      );

      expect(timeline.tenantId, tenantId);
      expect(timeline.supplierId, supplierId);
      expect(timeline.activities, isEmpty);
    });

    test('timeline never treats document identity as journal provenance', () {
      final timeline = SupplierEconomicReadModel.fromRows([
        {
          'tenant_id': tenantId,
          'supplier_id': supplierId,
          'party_id': partyId,
          'event_type': 'purchase_payment',
          'event_id': 'payment-1',
          'event_date': '2026-08-08',
          'currency_code': 'CLP',
          'gross_amount': 25000,
          'paid_amount': 25000,
          'balance_amount': 0,
          'payment_count': 1,
          'is_recognized': true,
          'data_quality_status': 'complete',
          'source_document_id': 'invoice-1',
          'metadata': {'payment_id': 'payment-1'},
        },
      ]);

      expect(
        timeline.activities.single.kind,
        SupplierEconomicActivityKind.purchasePayment,
      );
      expect(timeline.activities.single.sourceDocumentId, 'invoice-1');
      expect(timeline.activities.single.paymentCount, 1);
      expect(timeline.activities.single.isRecognized, isTrue);
      expect(
        timeline.activities.single.dataQualityStatus,
        SupplierEconomicDataQualityStatus.complete,
      );
    });

    test('timeline preserves canonical credit-note and refund event kinds', () {
      expect(
        SupplierEconomicActivityKind.fromJson('purchase_credit_note'),
        SupplierEconomicActivityKind.purchaseCreditNote,
      );
      expect(
        SupplierEconomicActivityKind.fromJson('purchase_supplier_refund'),
        SupplierEconomicActivityKind.purchaseSupplierRefund,
      );
      expect(
        SupplierEconomicActivityKind.fromJson('credit_note'),
        SupplierEconomicActivityKind.creditNote,
      );
    });

    test('no recognized documents keep monetary aggregates null', () {
      final summary = SupplierEconomicSummaryReadModel.fromJson({
        'tenant_id': tenantId,
        'supplier_id': supplierId,
        'party_id': partyId,
        'currency_code': 'CLP',
        'purchase_document_count': 0,
        'purchase_payment_count': 0,
        'expense_document_count': 0,
        'expense_payment_count': 0,
        'total_document_count': 0,
        'excluded_lifecycle_document_count': 2,
        'data_quality_status': 'lifecycle_only',
      });

      expect(summary.purchases.grossAmount, isNull);
      expect(summary.expenses.grossAmount, isNull);
      expect(summary.totalDocumentCount, 0);
      expect(summary.excludedLifecycleDocumentCount, 2);
      expect(
        summary.dataQualityStatus,
        SupplierEconomicDataQualityStatus.lifecycleOnly,
      );
    });
  });

  test('received tax document identity follows issuer type and folio', () {
    final document = ReceivedTaxDocument.fromJson({
      'id': 'document-1',
      'tenant_id': tenantId,
      'issuer_party_id': partyId,
      'supplier_id': supplierId,
      'document_type_code': 'invoice',
      'normalized_folio': 'F123',
      'received_at': '2026-08-08T12:00:00Z',
      'status': 'validated',
    });

    expect(document.naturalIdentity, '$partyId|invoice|F123');
    expect(document.status, ReceivedTaxDocumentStatus.validated);
    expect(document.toJson()['issuer_party_id'], partyId);
  });

  test('Chile DTE numeric codes map without defaulting unknown to invoice', () {
    expect(ReceivedTaxDocumentKind.fromJson('33'),
        ReceivedTaxDocumentKind.invoice);
    expect(ReceivedTaxDocumentKind.fromJson('34'),
        ReceivedTaxDocumentKind.exemptInvoice);
    expect(ReceivedTaxDocumentKind.fromJson('56'),
        ReceivedTaxDocumentKind.debitNote);
    expect(ReceivedTaxDocumentKind.fromJson('61'),
        ReceivedTaxDocumentKind.creditNote);
    expect(ReceivedTaxDocumentKind.fromJson('39'),
        ReceivedTaxDocumentKind.receipt);
    expect(
        ReceivedTaxDocumentKind.fromJson('999'), ReceivedTaxDocumentKind.other);
  });
}
