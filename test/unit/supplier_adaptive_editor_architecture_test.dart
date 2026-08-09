import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/modules/purchases/pages/supplier_form_page.dart',
    ).readAsStringSync();
  });

  test('editor is identity first and has no legacy classifier or KPI UI', () {
    expect(source.indexOf("title: 'Identidad'"), greaterThan(0));
    expect(
      source.indexOf("title: 'Identidad'"),
      lessThan(source.indexOf("title: 'Clasificación'")),
    );
    expect(source, contains("'Nombre visible'"));
    expect(source, contains("'Tipo de contraparte'"));
    expect(source, contains('_selectedRoleIds.isEmpty'));
    expect(source, isNot(contains('SupplierType')));
    expect(source, isNot(contains('FilterChip(')));
    expect(source, isNot(contains('ChoiceChip(')));
    expect(source, isNot(contains('InputChip(')));
    expect(source, isNot(contains('KPI')));
    expect(source, isNot(contains('TabController')));
    expect(source, contains('_showOptionalDetails = false'));
    expect(source, contains("'supplier-show-optional-details'"));
    expect(source, contains("'Agregar contacto y ubicación'"));
    expect(source, isNot(contains('ExpansionTile')));
  });

  test('profile writes fail closed through the relationship foundation', () {
    expect(source, contains('SaveSupplierRelationshipProfileCommand('));
    expect(source, contains('_relationshipService.saveProfile(command)'));
    expect(source,
        contains('expectedUpdatedAt: existing?.relationship.updatedAt'));
    expect(source, contains('SupplierFoundationUnavailable'));
    expect(source, contains('No se guardó ni se creó un registro alternativo'));
    expect(source, contains('ReturnNavigation.close('));
    expect(source, isNot(contains('PurchaseService')));
    expect(source, isNot(contains('saveSupplier(')));
    expect(source, contains("error.code == '40001'"));
    expect(source, contains("'No se pudo guardar el proveedor'"));
    expect(source, contains('jsonEncode({'));
    expect(source, isNot(contains("].join('|')")));
  });

  test('roles capabilities and tags are independent checkbox rows', () {
    expect(source, contains('SupplierClassificationSelection('));
    expect(source, contains('assignmentId: assignmentIds[definition.id]'));
    expect(source, contains('Checkbox('));
    expect(
        source, contains('constraints: const BoxConstraints(minHeight: 48)'));
    expect(source, contains("code != 'free_service'"));
    expect(source, contains("code != 'free-service'"));
  });

  test(
      'relationships and accounting append versions instead of editing history',
      () {
    expect(source, contains('CreateSupplierEngagementCommand('));
    expect(source, contains('AppendSupplierEngagementVersionCommand('));
    expect(source, contains('CreateSupplierAccountingPolicyCommand('));
    expect(source, contains('AppendSupplierAccountingPolicyVersionCommand('));
    expect(source, contains('SupplierEngagementBillingCycle.free'));
    expect(source, contains('Se agregó una versión nueva'));
    expect(source, isNot(contains('updateEngagementShell(')));
    expect(source, isNot(contains('updateAccountingPolicyShell(')));
  });

  test('accounting scope and contextual rules are explicit and versioned', () {
    expect(source, contains("'Alcance del criterio'"));
    expect(source, contains("'Una relación específica'"));
    expect(source, contains("'Proveedor completo (respaldo)'"));
    expect(source, contains("'Confirmo el alcance para todo el proveedor'"));
    expect(source, contains("'Señales de contexto'"));
    expect(source, contains("'Agregar condición'"));
    expect(source, contains('rules: draft.rules'));
    expect(source, contains('SupplierAccountingRuleKind.documentType'));
    expect(source, contains('SupplierAccountingRuleKind.description'));
    expect(source, contains('SupplierAccountingRuleKind.lineDescription'));
    expect(source, isNot(contains('SupplierAccountingRuleOperator.regex,')));
    expect(source, isNot(contains('DateTime.now()')));
    expect(source, contains('supplier.effectiveBusinessDate'));
    expect(source, contains('existing?.latestVersion'));
    expect(source, contains("'supplier-accounting-effective-from'"));
    expect(source, contains("'supplier-engagement-effective-from'"));
    expect(source, contains('_nextCivilDate(version.effectiveFrom)'));
    expect(source, contains('_nextCivilDate(version.validFrom)'));
    expect(source, contains("error.code != '23514'"));
  });

  test('accounting catalogs and writers honor the profile capability lease',
      () {
    expect(source, contains('bool get canManageAccounting'));
    expect(source, contains('profile?.canAccessAccounting == true'));
    expect(source, contains('if (_source.canManageAccounting)'));
    expect(source, contains('_accountingCatalogGeneration'));
    expect(source,
        contains('authorityFingerprint == _source.authorityFingerprint'));
    expect(
        source, contains('canManageAccounting ? \'Agregar versión\' : null'));
  });

  test('credential editor is metadata-first multi-key and exact-origin', () {
    expect(source, contains('SupplierCredentialStatus'));
    expect(source, contains('credentialKey: draft.credentialKey'));
    expect(source, contains('expectedUpdatedAt: existing?.updatedAt'));
    expect(source, contains('operationId: draft.operationId'));
    expect(
      source,
      contains(
        'clearOrigin: existing?.originUrl != null && draft.origin == null',
      ),
    );
    expect(source, contains("if (text.isEmpty) return null"));
    expect(
      source,
      matches(RegExp(r'origin:\s+originText\.isEmpty\s+\?\s+null')),
    );
    expect(source, contains('canonicalSupplierCredentialOrigin'));
    expect(source, contains("'Origen HTTPS autorizado (opcional)'"));
    expect(source, contains('SupplierCredentialService'));
    expect(source, isNot(contains('SupplierCredentialRevealController')));
    expect(source, isNot(contains('.get(')));
    expect(source, isNot(contains('portalPasswordController')));
    expect(source, contains('authAuthorityChanges'));
    expect(source, contains('_handleAuthAuthorityChanged'));
    expect(source, contains('_credentialStatusGeneration'));
    expect(source, contains('_credentialStatusLeaseIsCurrent'));
    expect(source, contains('_invalidateAuthorityBoundEditorState'));
    expect(source, contains('generation != _loadGeneration'));
    expect(source, contains('setState(() => _credentialStatus = null)'));
  });

  test('one adaptive writer keeps touch targets at the canonical breakpoint',
      () {
    expect(source, contains('MediaQuery.sizeOf(context).width < 900'));
    expect(source, contains('MainLayout('));
    expect(source, contains('includeWorkspaceShell'));
    expect(source, isNot(contains('Colors.white')));
    expect(source, isNot(matches(RegExp(r'Color\(0x[0-9a-fA-F]+'))));
    expect(source, contains("'Catálogos contables no disponibles'"));
    expect(source, contains('accountCatalogUnavailable'));
    expect(source, isNot(contains('getAccounts().catchError')));
  });
}
