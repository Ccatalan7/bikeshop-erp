import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/accounting/models/account.dart';
import 'package:vinabike_erp/modules/accounting/models/expense_category.dart';
import 'package:vinabike_erp/modules/purchases/models/supplier_foundation.dart';
import 'package:vinabike_erp/modules/purchases/pages/supplier_form_page.dart';
import 'package:vinabike_erp/modules/purchases/services/supplier_credential_service.dart';
import 'package:vinabike_erp/modules/purchases/services/supplier_relationship_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  const supplierId = '20000000-0000-0000-0000-000000000002';

  Future<void> pumpEditor(
    WidgetTester tester, {
    required _FakeSupplierEditorDataSource source,
    String? editingSupplierId,
    Size size = const Size(390, 844),
    Brightness brightness = Brightness.light,
    Key? pageKey,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: brightness,
        ),
        home: Scaffold(
          body: SupplierFormPage(
            key: pageKey,
            supplierId: editingSupplierId,
            dataSource: source,
            includeWorkspaceShell: false,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets(
    'alta compacta revela contacto sólo después de la acción progresiva',
    (tester) async {
      final source = _FakeSupplierEditorDataSource(catalog: _catalog());

      await pumpEditor(tester, source: source);

      expect(find.text('Identidad'), findsOneWidget);
      expect(find.text('Relación con el taller'), findsOneWidget);
      expect(find.text('Tipo de entidad'), findsNothing);
      final legalDetails =
          find.byKey(const ValueKey('supplier-show-legal-details'));
      expect(legalDetails, findsOneWidget);
      await tester.ensureVisible(legalDetails);
      await tester.tap(legalDetails);
      await tester.pumpAndSettle();
      expect(find.text('Tipo de entidad'), findsOneWidget);
      expect(find.text('Contacto y ubicación'), findsNothing);
      expect(
        find.byKey(const ValueKey('supplier-show-optional-details')),
        findsOneWidget,
      );

      final reveal =
          find.byKey(const ValueKey('supplier-show-optional-details'));
      await tester.ensureVisible(reveal);
      await tester.tap(reveal);
      await tester.pump();

      expect(find.text('Contacto y ubicación'), findsOneWidget);
      expect(reveal, findsNothing);
    },
  );

  testWidgets(
    'roles múltiples llegan juntos a un único command y un error conserva el borrador',
    (tester) async {
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        saveError: StateError('offline'),
      );
      await pumpEditor(tester, source: source);

      await tester.enterText(
        find.byKey(const ValueKey('supplier-display-name')),
        'Proveedor híbrido',
      );
      // T20 · una sola pregunta. Se elige por la hoja, no por una pared de
      // casillas, y el segundo caso mixto entra por «Agregar otra».
      for (final label in ['Bienes y repuestos', 'Servicios digitales']) {
        final opener = find.byKey(const ValueKey('supplier-choose-relation'));
        final adder = find.byKey(const ValueKey('supplier-add-relation'));
        final trigger = opener.evaluate().isNotEmpty ? opener : adder;
        await tester.ensureVisible(trigger);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      // Dos relaciones declaradas, cada una con su tarjeta.
      expect(find.byKey(const ValueKey('supplier-relation-goods')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('supplier-relation-digital')),
          findsOneWidget);

      final save = find.byKey(const ValueKey('supplier-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(source.profileCommands, hasLength(1));
      expect(source.childMutationCalls, 0);
      final command = source.profileCommands.single;
      expect(command, isA<SaveSupplierRelationshipProfileCommand>());
      expect(command.supplierId, isNull);
      expect(command.party.displayName, 'Proveedor híbrido');
      expect(
        command.roles.map((selection) => selection.definition.code),
        unorderedEquals(['goods_vendor', 'digital_platform']),
      );
      expect(
        command.capabilities.map((selection) => selection.definition.code),
        <String>['digital_services'],
      );
      expect(command.tags, isEmpty);

      final nameField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('supplier-display-name')),
      );
      expect(nameField.controller?.text, 'Proveedor híbrido');
      expect(find.text('No se pudo guardar el proveedor'), findsOneWidget);
      expect(find.byKey(const ValueKey('supplier-relation-goods')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('supplier-relation-digital')),
          findsOneWidget);
      expect(
        tester.widget<FilledButton>(save).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'una relación sólo ofrece sus subtipos y deriva la capacidad compatible',
    (tester) async {
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        saveError: StateError('offline'),
      );
      await pumpEditor(tester, source: source);

      await tester.enterText(
        find.byKey(const ValueKey('supplier-display-name')),
        'Proveedor de repuestos',
      );
      final chooseRelation =
          find.byKey(const ValueKey('supplier-choose-relation'));
      await tester.ensureVisible(chooseRelation);
      await tester.tap(chooseRelation);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bienes y repuestos').last);
      await tester.pumpAndSettle();

      final goodsSubtype = find.byKey(const ValueKey('supplier-subtype-goods'));
      await tester.ensureVisible(goodsSubtype);
      await tester.tap(goodsSubtype);
      await tester.pumpAndSettle();
      expect(find.text('Inventario o reventa'), findsOneWidget);
      expect(find.text('Insumos de taller'), findsOneWidget);
      expect(find.text('Electricidad'), findsNothing);
      await tester.tap(find.text('Inventario o reventa'));
      await tester.pumpAndSettle();

      final save = find.byKey(const ValueKey('supplier-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(source.profileCommands, hasLength(1));
      final command = source.profileCommands.single;
      expect(
        command.roles.map((selection) => selection.definition.code),
        ['goods_vendor'],
      );
      expect(
        command.capabilities.map((selection) => selection.definition.code),
        ['inventory_goods'],
      );
      expect(command.tags, isEmpty);
    },
  );

  testWidgets(
    'editar no borra clasificaciones históricas que la pregunta guiada no muestra',
    (tester) async {
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profileWithHiddenAssignments(),
        saveError: StateError('offline'),
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
      );

      expect(find.text('Rol interno heredado'), findsNothing);
      expect(find.text('Portal con acceso'), findsNothing);
      expect(find.text('Crítico para la operación'), findsNothing);

      final save = find.byKey(const ValueKey('supplier-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      final command = source.profileCommands.single;
      expect(
        command.roles.map((selection) => selection.definition.code),
        unorderedEquals(<String>['goods_vendor', 'preferred_partner']),
      );
      expect(
        command.capabilities.map((selection) => selection.definition.code),
        <String>['credential_portal'],
      );
      expect(
        command.tags.map((selection) => selection.definition.code),
        <String>['critical'],
      );
    },
  );

  testWidgets(
    'edición admite dimensiones vacías sin exigir RUT factura ni acceso',
    (tester) async {
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profile(),
        canManageCredentials: true,
        saveError: StateError('offline'),
      );

      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
      );

      expect(find.text('Contacto y ubicación'), findsOneWidget);
      expect(find.text('Contratos y servicios'), findsOneWidget);
      expect(find.text('Criterios contables'), findsOneWidget);
      expect(find.text('Accesos'), findsOneWidget);
      expect(find.text('Sin accesos guardados.'), findsOneWidget);
      expect(source.credentialStatusCalls, 1);

      final taxLabel = find.text('RUT u otro identificador fiscal');
      final taxField = tester.widget<TextFormField>(
        find.ancestor(of: taxLabel, matching: find.byType(TextFormField)),
      );
      expect(taxField.controller?.text, isEmpty);
      expect(taxField.validator, isNull);

      final save = find.byKey(const ValueKey('supplier-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(source.profileCommands, hasLength(1));
      final command = source.profileCommands.single;
      expect(command.supplierId, supplierId);
      expect(command.taxIdentifier, isNull);
      expect(command.relationship.email, isNull);
      expect(
        command.toProfileRpcJson().keys.where(
              (key) => key.toLowerCase().contains('invoice'),
            ),
        isEmpty,
      );
      expect(source.credentialMutationCalls, 0);
      expect(find.text('No se pudo guardar el proveedor'), findsOneWidget);
    },
  );

  testWidgets(
    'token protegido puede guardarse sin inventar origen web en compacto',
    (tester) async {
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profile(),
        canManageCredentials: true,
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
        size: const Size(320, 640),
      );

      final addAccess = find.text('Agregar acceso');
      await tester.ensureVisible(addAccess);
      await tester.tap(addAccess);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byType(DropdownButtonFormField<SupplierCredentialKind>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Token de API').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.ancestor(
          of: find.text('Clave estable'),
          matching: find.byType(TextFormField),
        ),
        'api_principal',
      );
      await tester.enterText(
        find.ancestor(
          of: find.text('Secreto'),
          matching: find.byType(TextFormField),
        ),
        ' secreto exacto ',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Agregar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(source.credentialInputs, hasLength(1));
      expect(
          source.credentialInputs.single.kind, SupplierCredentialKind.apiToken);
      expect(source.credentialInputs.single.originUrl, isNull);
      expect(source.credentialInputs.single.secret, ' secreto exacto ');
    },
  );

  testWidgets(
    'rotar acceso puede retirar explícitamente un origen web anterior',
    (tester) async {
      final status = Completer<SupplierCredentialStatus>()
        ..complete(_credentialStatus(label: 'Acceso existente'));
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profile(),
        canManageCredentials: true,
        credentialStatusCompleter: status,
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
      );

      final rotate = find.widgetWithText(TextButton, 'Rotar');
      await tester.ensureVisible(rotate);
      await tester.tap(rotate);
      await tester.pumpAndSettle();
      final originField = find.ancestor(
        of: find.text('Origen HTTPS autorizado (opcional)'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(originField, '');
      await tester.enterText(
        find.ancestor(
          of: find.text('Nuevo secreto'),
          matching: find.byType(TextFormField),
        ),
        'rotación exacta',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Rotar'),
        ),
      );
      await tester.pumpAndSettle();

      expect(source.credentialInputs, hasLength(1));
      expect(source.credentialInputs.single.originUrl, isNull);
      expect(source.credentialInputs.single.clearOrigin, isTrue);
    },
  );

  testWidgets(
    'acceso username-only se conserva y exige una clave real para completarlo',
    (tester) async {
      final status = Completer<SupplierCredentialStatus>()
        ..complete(
          _credentialStatus(
            label: 'Cuenta heredada',
            username: 'cuenta.portal',
            secretAvailable: false,
          ),
        );
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profile(),
        canManageCredentials: true,
        credentialStatusCompleter: status,
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
      );

      expect(find.textContaining('Acceso de portal'), findsOneWidget);
      expect(find.textContaining('Sin clave guardada'), findsOneWidget);
      final complete = find.widgetWithText(TextButton, 'Completar');
      await tester.ensureVisible(complete);
      await tester.tap(complete);
      await tester.pumpAndSettle();

      expect(find.text('Completar acceso'), findsOneWidget);
      expect(find.text('Aún no hay una clave guardada'), findsOneWidget);
      final usernameField = tester.widget<TextFormField>(
        find.ancestor(
          of: find.text('Usuario (protegido)'),
          matching: find.byType(TextFormField),
        ),
      );
      expect(usernameField.controller?.text, 'cuenta.portal');

      final submit = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Completar'),
      );
      await tester.tap(submit);
      await tester.pump();
      expect(
        find.text('Ingresa una clave para completar este acceso'),
        findsOneWidget,
      );
      expect(source.credentialInputs, isEmpty);

      await tester.enterText(
        find.ancestor(
          of: find.text('Guardar una clave'),
          matching: find.byType(TextFormField),
        ),
        'clave real nueva',
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();

      expect(source.credentialInputs, hasLength(1));
      expect(source.credentialInputs.single.username, 'cuenta.portal');
      expect(source.credentialInputs.single.secret, 'clave real nueva');
      expect(source.credentialInputs.single.credentialKey, 'portal');
      expect(
        source.credentialInputs.single.expectedUpdatedAt,
        DateTime.utc(2026, 8, 8),
      );
      expect(find.text('Acceso completado'), findsOneWidget);
    },
  );

  testWidgets(
    'revocar credenciales descarta una respuesta antigua y restaurar exige lectura nueva',
    (tester) async {
      final stale = Completer<SupplierCredentialStatus>();
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profile(),
        canManageCredentials: true,
        credentialStatusCompleter: stale,
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
      );

      expect(source.credentialStatusCalls, 1);
      expect(find.text('Accesos'), findsOneWidget);

      source.setCredentialAuthority(false);
      await tester.pump();
      stale.complete(_credentialStatus(label: 'Acceso antiguo'));
      await tester.pumpAndSettle();

      expect(find.text('Accesos'), findsNothing);
      expect(find.text('Acceso antiguo'), findsNothing);
      expect(find.text('No se pudieron cargar los accesos'), findsNothing);

      final fresh = Completer<SupplierCredentialStatus>();
      source.credentialStatusCompleter = fresh;
      source.setCredentialAuthority(true);
      await tester.pump();

      expect(source.credentialStatusCalls, 2);
      expect(find.text('Accesos'), findsOneWidget);
      expect(find.text('Acceso antiguo'), findsNothing);

      fresh.complete(_credentialStatus());
      await tester.pumpAndSettle();
      expect(find.text('Sin accesos guardados.'), findsOneWidget);
      expect(find.text('Acceso antiguo'), findsNothing);
    },
  );

  testWidgets(
    'error antiguo de credenciales no publica aviso tras revocar autoridad',
    (tester) async {
      final stale = Completer<SupplierCredentialStatus>();
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profile(),
        canManageCredentials: true,
        credentialStatusCompleter: stale,
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
      );

      source.setCredentialAuthority(false);
      await tester.pump();
      stale.completeError(StateError('respuesta del tenant anterior'));
      await tester.pumpAndSettle();

      expect(find.text('Accesos'), findsNothing);
      expect(find.text('No se pudieron cargar los accesos'), findsNothing);
    },
  );

  testWidgets(
    'cambio de tenant invalida cargas base incluso si la autoridad vuelve a A',
    (tester) async {
      final staleA = Completer<SupplierProfile?>();
      final staleB = Completer<SupplierProfile?>();
      final freshA = Completer<SupplierProfile?>();
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profile(displayName: 'Tenant A vigente'),
        profileCompleters: [staleA, staleB, freshA],
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
        settle: false,
      );
      expect(source.profileCalls, 1);

      source.setBaseAuthority('authority-b');
      await tester.pump();
      expect(source.profileCalls, 2);
      source.setBaseAuthority('authority-a');
      await tester.pump();
      expect(source.profileCalls, 3);

      staleA.complete(_profile(displayName: 'Tenant A antiguo'));
      staleB.complete(_profile(displayName: 'Tenant B antiguo'));
      await tester.pump();

      expect(find.text('Tenant A antiguo'), findsNothing);
      expect(find.text('Tenant B antiguo'), findsNothing);
      expect(
        find.byKey(const ValueKey('supplier-display-name')),
        findsNothing,
      );

      freshA.complete(_profile(displayName: 'Tenant A vigente'));
      await tester.pumpAndSettle();

      final displayName = tester.widget<TextFormField>(
        find.byKey(const ValueKey('supplier-display-name')),
      );
      expect(displayName.controller?.text, 'Tenant A vigente');
      expect(find.text('Tenant A antiguo'), findsNothing);
      expect(find.text('Tenant B antiguo'), findsNothing);
    },
  );

  testWidgets('320 px permanece sin overflow en claro y oscuro',
      (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profile(),
        canManageCredentials: true,
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
        size: const Size(320, 640),
        brightness: brightness,
        pageKey: ValueKey(brightness),
      );

      expect(tester.takeException(), isNull, reason: brightness.name);
      expect(find.text('Editar proveedor'), findsOneWidget);
      expect(find.text('Contratos y servicios'), findsOneWidget);
      expect(find.text('Criterios contables'), findsOneWidget);
      expect(find.text('Accesos'), findsOneWidget);
    }
  });

  testWidgets(
    'criterio nuevo elige relación y envía condiciones múltiples',
    (tester) async {
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profileWithAccountingContext(),
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
      );

      final newPolicy = find.text('Nuevo criterio');
      await tester.ensureVisible(newPolicy);
      await tester.tap(newPolicy);
      await tester.pumpAndSettle();

      expect(find.text('Alcance del criterio'), findsOneWidget);
      expect(find.text('Una relación específica'), findsOneWidget);
      expect(find.text('Señales de contexto'), findsOneWidget);

      await tester.enterText(
        find.ancestor(
          of: find.text('Nombre del criterio'),
          matching: find.byType(TextFormField),
        ),
        'Inventario por factura',
      );
      await tester.tap(
        find.byKey(const ValueKey('supplier-accounting-engagement')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arriendo local').last);
      await tester.pumpAndSettle();

      final addRule =
          find.byKey(const ValueKey('supplier-accounting-add-rule'));
      await tester.ensureVisible(addRule);
      await tester.tap(addRule);
      await tester.pump();
      final firstRuleValue =
          _findByValueKeyPrefix('supplier-accounting-rule-value-');
      expect(firstRuleValue, findsOneWidget);
      await tester.enterText(
        firstRuleValue,
        '33',
      );

      await tester.ensureVisible(addRule);
      await tester.tap(addRule);
      await tester.pump();
      final ruleKinds = _findByValueKeyPrefix('supplier-accounting-rule-kind-');
      await tester.ensureVisible(ruleKinds.last);
      await tester.tap(ruleKinds.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descripción del documento').last);
      await tester.pumpAndSettle();
      final ruleValues =
          _findByValueKeyPrefix('supplier-accounting-rule-value-');
      await tester.enterText(ruleValues.last, 'repuestos');

      await tester.tap(
        find.byKey(const ValueKey('supplier-accounting-save-version')),
      );
      await tester.pumpAndSettle();

      expect(source.createdAccountingPolicies, hasLength(1));
      final command = source.createdAccountingPolicies.single;
      expect(command.policy.engagementId, _engagementId);
      expect(command.initialVersion.effectiveFrom, DateTime(2026, 8, 8));
      expect(command.rules, hasLength(2));
      expect(command.rules[0].kind, SupplierAccountingRuleKind.documentType);
      expect(command.rules[0].operator, SupplierAccountingRuleOperator.equals);
      expect(command.rules[0].operand, {'document_type': '33'});
      expect(command.rules[1].kind, SupplierAccountingRuleKind.description);
      expect(
        command.rules[1].operator,
        SupplierAccountingRuleOperator.contains,
      );
      expect(command.rules[1].operand, {'text': 'repuestos'});
      expect(find.text('No se pudo guardar el criterio'), findsOneWidget);
    },
  );

  testWidgets(
    'nueva versión conserva reglas actuales incluso si son avanzadas',
    (tester) async {
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profileWithAccountingContext(includePolicy: true),
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
      );

      final append = find.text('Agregar versión').last;
      await tester.ensureVisible(append);
      await tester.tap(append);
      await tester.pumpAndSettle();

      expect(find.text('Alcance: relación específica'), findsOneWidget);
      expect(find.text('Condición existente conservada'), findsOneWidget);
      expect(find.textContaining('Coincide con patrón'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('supplier-accounting-save-version')),
      );
      await tester.pumpAndSettle();

      expect(source.appendedAccountingPolicies, hasLength(1));
      final command = source.appendedAccountingPolicies.single;
      expect(command.version.effectiveFrom, DateTime(2026, 8, 8));
      expect(command.rules, hasLength(2));
      expect(command.rules[0].operand, {'document_type': '33'});
      expect(command.rules[1].kind, SupplierAccountingRuleKind.description);
      expect(command.rules[1].operator, SupplierAccountingRuleOperator.regex);
      expect(command.rules[1].operand, {'text': r'^flete\b'});
    },
  );

  testWidgets(
    'relación creada en la fecha operacional agrega desde el día civil siguiente',
    (tester) async {
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profileWithAccountingContext(
          engagementEffectiveFrom: '2026-08-08',
        ),
        appendEngagementError: const PostgrestException(
          message: 'Next engagement version must start after current version',
          code: '23514',
        ),
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
      );

      final append = find.text('Agregar versión');
      await tester.ensureVisible(append);
      await tester.tap(append);
      await tester.pumpAndSettle();

      final effectiveFrom = find.byKey(
        const ValueKey('supplier-engagement-effective-from'),
      );
      expect(
        tester.widget<TextFormField>(effectiveFrom).controller?.text,
        '09-08-2026',
      );

      await tester.tap(find.text('Guardar versión').last);
      await tester.pumpAndSettle();

      expect(source.appendedEngagements, hasLength(1));
      expect(
        source.appendedEngagements.single.version.effectiveFrom,
        DateTime(2026, 8, 9),
      );
      expect(find.text('La fecha de vigencia ya no es válida'), findsOneWidget);
    },
  );

  testWidgets(
    'fecha futura elegida y operation id sobreviven al reintento de criterio',
    (tester) async {
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profileWithAccountingContext(
          includePolicy: true,
          policyVersions: const [
            {
              'id': _policyVersionId,
              'tenant_id': _tenantId,
              'policy_id': _policyId,
              'version_number': 1,
              'effective_from': '2026-08-08',
              'operational_nature_code': 'operating_expense',
              'operational_nature_definition_id':
                  '80000000-0000-0000-0000-000000000008',
              'tax_treatment': 'not_applicable',
              'currency_code': 'CLP',
            },
          ],
        ),
        appendAccountingError: const PostgrestException(
          message: 'Next policy version must start after current version',
          code: '23514',
        ),
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
      );

      final append = find.text('Agregar versión').last;
      await tester.ensureVisible(append);
      await tester.tap(append);
      await tester.pumpAndSettle();

      final effectiveFrom = find.byKey(
        const ValueKey('supplier-accounting-effective-from'),
      );
      expect(
        tester.widget<TextFormField>(effectiveFrom).controller?.text,
        '09-08-2026',
      );

      await tester.tap(effectiveFrom);
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').last);
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(effectiveFrom).controller?.text,
        '15-08-2026',
      );

      await tester.tap(
        find.byKey(const ValueKey('supplier-accounting-save-version')),
      );
      await tester.pumpAndSettle();

      expect(find.text('La fecha de vigencia ya no es válida'), findsOneWidget);
      expect(find.textContaining('Revisa la conexión'), findsNothing);
      expect(source.appendedAccountingPolicies, hasLength(1));
      final firstCommand = source.appendedAccountingPolicies.single;
      expect(firstCommand.version.effectiveFrom, DateTime(2026, 8, 15));

      final reopen = find.text('Reabrir propuesta');
      await tester.ensureVisible(reopen);
      await tester.tap(reopen);
      await tester.pumpAndSettle();

      final retainedEffectiveFrom = find.byKey(
        const ValueKey('supplier-accounting-effective-from'),
      );
      expect(
        tester.widget<TextFormField>(retainedEffectiveFrom).controller?.text,
        '15-08-2026',
      );
      await tester.tap(
        find.byKey(const ValueKey('supplier-accounting-save-version')),
      );
      await tester.pumpAndSettle();

      expect(source.appendedAccountingPolicies, hasLength(2));
      final retryCommand = source.appendedAccountingPolicies.last;
      expect(retryCommand.operationId, firstCommand.operationId);
      expect(retryCommand.version.effectiveFrom, DateTime(2026, 8, 15));
    },
  );

  testWidgets(
    'append contable parte de la última versión futura y conserva sus reglas',
    (tester) async {
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profileWithAccountingContext(
          includePolicy: true,
          policyVersions: const [
            {
              'id': _policyVersionId,
              'tenant_id': _tenantId,
              'policy_id': _policyId,
              'version_number': 1,
              'effective_from': '2026-01-01',
              'effective_to': '2026-08-31',
              'operational_nature_code': 'operating_expense',
              'operational_nature_definition_id':
                  '80000000-0000-0000-0000-000000000008',
              'tax_treatment': 'not_applicable',
              'currency_code': 'CLP',
            },
            {
              'id': _futurePolicyVersionId,
              'tenant_id': _tenantId,
              'policy_id': _policyId,
              'version_number': 2,
              'effective_from': '2026-09-01',
              'operational_nature_code': 'operating_expense',
              'operational_nature_definition_id':
                  '80000000-0000-0000-0000-000000000008',
              'tax_treatment': 'exempt',
              'expected_document_type': '56',
              'currency_code': 'USD',
              'line_nature': 'freight',
              'posture': {'basis': 'scheduled'},
            },
          ],
          accountingRules: const [
            {
              'id': '97000000-0000-0000-0000-000000000097',
              'tenant_id': _tenantId,
              'policy_version_id': _futurePolicyVersionId,
              'rule_kind': 'document_type',
              'operator': 'equals',
              'operand': {'document_type': '56'},
              'priority': 10,
              'is_active': true,
            },
          ],
        ),
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
      );

      final append = find.text('Agregar versión').last;
      await tester.ensureVisible(append);
      await tester.tap(append);
      await tester.pumpAndSettle();

      final effectiveFrom = find.byKey(
        const ValueKey('supplier-accounting-effective-from'),
      );
      expect(
        tester.widget<TextFormField>(effectiveFrom).controller?.text,
        '02-09-2026',
      );
      await tester.tap(
        find.byKey(const ValueKey('supplier-accounting-save-version')),
      );
      await tester.pumpAndSettle();

      expect(source.appendedAccountingPolicies, hasLength(1));
      final command = source.appendedAccountingPolicies.single;
      expect(command.version.effectiveFrom, DateTime(2026, 9, 2));
      expect(command.version.expectedDocumentType, '56');
      expect(command.version.currencyCode, 'USD');
      expect(command.version.lineNature, SupplierAccountingLineNature.freight);
      expect(command.version.publicPosture, {'basis': 'scheduled'});
      expect(command.rules, hasLength(1));
      expect(command.rules.single.operand, {'document_type': '56'});
    },
  );

  testWidgets(
    'respaldo general y ausencia de condiciones requieren confirmación',
    (tester) async {
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profileWithAccountingContext(),
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
      );

      final newPolicy = find.text('Nuevo criterio');
      await tester.ensureVisible(newPolicy);
      await tester.tap(newPolicy);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.ancestor(
          of: find.text('Nombre del criterio'),
          matching: find.byType(TextFormField),
        ),
        'Respaldo general',
      );

      await tester.tap(
        find.byKey(const ValueKey('supplier-accounting-scope')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proveedor completo (respaldo)').last);
      await tester.pumpAndSettle();

      final unconditional = find.byKey(
        const ValueKey('supplier-accounting-confirm-unconditional'),
      );
      await tester.ensureVisible(unconditional);
      await tester.tap(unconditional);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('supplier-accounting-save-version')),
      );
      await tester.pump();

      expect(source.createdAccountingPolicies, isEmpty);
      expect(
        find.text('Confirma que este criterio será un respaldo general'),
        findsWidgets,
      );

      final fallback = find.byKey(
        const ValueKey('supplier-accounting-confirm-fallback'),
      );
      await tester.ensureVisible(fallback);
      await tester.tap(fallback);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('supplier-accounting-save-version')),
      );
      await tester.pumpAndSettle();

      expect(source.createdAccountingPolicies, hasLength(1));
      expect(
          source.createdAccountingPolicies.single.policy.engagementId, isNull);
      expect(source.createdAccountingPolicies.single.rules, isEmpty);
    },
  );

  testWidgets(
    'sin capacidad contable no carga catálogos ni ofrece escritores',
    (tester) async {
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profileWithAccountingContext(includePolicy: true),
        canManageAccounting: false,
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
      );

      expect(find.text('Criterios contables'), findsOneWidget);
      expect(find.text('Inventario factura'), findsOneWidget);
      expect(find.text('Nuevo criterio'), findsNothing);
      expect(find.text('Agregar versión'), findsOneWidget);
      expect(source.accountCatalogCalls, 0);
      expect(source.expenseCategoryCatalogCalls, 0);

      source.setAccountingAuthority(true);
      await tester.pumpAndSettle();

      expect(source.accountCatalogCalls, 1);
      expect(source.expenseCategoryCatalogCalls, 1);
      expect(find.text('Nuevo criterio'), findsOneWidget);
      expect(find.text('Agregar versión'), findsNWidgets(2));
    },
  );

  testWidgets('editor contable a 320 px no desborda en claro ni oscuro',
      (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final source = _FakeSupplierEditorDataSource(
        catalog: _catalog(),
        profile: _profileWithAccountingContext(includePolicy: true),
      );
      await pumpEditor(
        tester,
        source: source,
        editingSupplierId: supplierId,
        size: const Size(320, 640),
        brightness: brightness,
        pageKey: ValueKey('accounting-${brightness.name}'),
      );

      final newPolicy = find.text('Nuevo criterio');
      await tester.ensureVisible(newPolicy);
      await tester.tap(newPolicy);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: brightness.name);
      expect(find.text('Nuevo criterio contable'), findsOneWidget);
      expect(find.text('Alcance del criterio'), findsOneWidget);
      expect(find.text('Señales de contexto'), findsOneWidget);
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();

      final append = find.text('Agregar versión').last;
      await tester.ensureVisible(append);
      await tester.tap(append);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: brightness.name);
      expect(find.text('Agregar versión de criterio'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('supplier-accounting-effective-from')),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();
    }
  });
}

Finder _findByValueKeyPrefix(String prefix) => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith(prefix);
    });

const _tenantId = '10000000-0000-0000-0000-000000000001';
const _supplierFixtureId = '20000000-0000-0000-0000-000000000002';
const _engagementId = '91000000-0000-0000-0000-000000000091';
const _engagementVersionId = '92000000-0000-0000-0000-000000000092';
const _policyId = '93000000-0000-0000-0000-000000000093';
const _policyVersionId = '94000000-0000-0000-0000-000000000094';
const _futurePolicyVersionId = '94100000-0000-0000-0000-000000000194';

SupplierClassificationCatalog _catalog() {
  SupplierClassificationDefinition definition({
    required String id,
    required SupplierClassificationDefinitionKind kind,
    required String code,
    required String label,
  }) =>
      SupplierClassificationDefinition(
        id: id,
        tenantId: '10000000-0000-0000-0000-000000000001',
        kind: kind,
        code: code,
        label: label,
      );

  return SupplierClassificationCatalog(
    roles: [
      definition(
        id: '40000000-0000-0000-0000-000000000004',
        kind: SupplierClassificationDefinitionKind.role,
        code: 'goods_vendor',
        label: 'Bienes e inventario',
      ),
      definition(
        id: '50000000-0000-0000-0000-000000000005',
        kind: SupplierClassificationDefinitionKind.role,
        code: 'digital_platform',
        label: 'Servicios digitales',
      ),
      definition(
        id: '51000000-0000-0000-0000-000000000005',
        kind: SupplierClassificationDefinitionKind.role,
        code: 'preferred_partner',
        label: 'Rol interno heredado',
      ),
    ],
    capabilities: [
      definition(
        id: '61000000-0000-0000-0000-000000000006',
        kind: SupplierClassificationDefinitionKind.capability,
        code: 'inventory_goods',
        label: 'Bienes de inventario',
      ),
      definition(
        id: '61100000-0000-0000-0000-000000000006',
        kind: SupplierClassificationDefinitionKind.capability,
        code: 'workshop_consumables',
        label: 'Insumos de taller',
      ),
      definition(
        id: '61200000-0000-0000-0000-000000000006',
        kind: SupplierClassificationDefinitionKind.capability,
        code: 'digital_services',
        label: 'Servicios digitales',
      ),
      definition(
        id: '60000000-0000-0000-0000-000000000006',
        kind: SupplierClassificationDefinitionKind.capability,
        code: 'credential_portal',
        label: 'Portal con acceso',
      ),
    ],
    tags: [
      definition(
        id: '70000000-0000-0000-0000-000000000007',
        kind: SupplierClassificationDefinitionKind.tag,
        code: 'critical',
        label: 'Crítico para la operación',
      ),
    ],
    operationalNatures: [
      definition(
        id: '80000000-0000-0000-0000-000000000008',
        kind: SupplierClassificationDefinitionKind.operationalNature,
        code: 'operating_expense',
        label: 'Gasto operacional',
      ),
    ],
  );
}

SupplierProfile _profile({
  String displayName = 'Proveedor mutable',
  String tenantId = _tenantId,
}) =>
    SupplierProfile.fromJson({
      'tenant_id': tenantId,
      'supplier_id': '20000000-0000-0000-0000-000000000002',
      'party_id': '30000000-0000-0000-0000-000000000003',
      'party_kind': 'organization',
      'display_name': displayName,
      'is_active': true,
      'has_portal_credential': false,
      'relationship_roles': const [
        {
          'id': '90000000-0000-0000-0000-000000000009',
          'definition_id': '40000000-0000-0000-0000-000000000004',
          'code': 'goods_vendor',
          'label': 'Bienes e inventario',
          'source': 'manual',
          'metadata': <String, dynamic>{},
        },
      ],
      'relationship_capabilities': const <Map<String, dynamic>>[],
      'relationship_tags': const <Map<String, dynamic>>[],
      'engagements': const <Map<String, dynamic>>[],
      'accounting': const {
        'policies': <Map<String, dynamic>>[],
        'rules': <Map<String, dynamic>>[],
        'recent_evidence': <Map<String, dynamic>>[],
        'observed_account_ids': <String>[],
      },
    });

SupplierProfile _profileWithHiddenAssignments() =>
    SupplierProfile.fromJson(const {
      'tenant_id': _tenantId,
      'supplier_id': _supplierFixtureId,
      'party_id': '30000000-0000-0000-0000-000000000003',
      'party_kind': 'organization',
      'display_name': 'Proveedor con historia',
      'is_active': true,
      'has_portal_credential': false,
      'relationship_roles': [
        {
          'id': '90000000-0000-0000-0000-000000000009',
          'definition_id': '40000000-0000-0000-0000-000000000004',
          'code': 'goods_vendor',
          'label': 'Bienes e inventario',
          'source': 'manual',
          'metadata': <String, dynamic>{},
        },
        {
          'id': '90100000-0000-0000-0000-000000000009',
          'definition_id': '51000000-0000-0000-0000-000000000005',
          'code': 'preferred_partner',
          'label': 'Rol interno heredado',
          'source': 'manual',
          'metadata': <String, dynamic>{},
        },
      ],
      'relationship_capabilities': [
        {
          'id': '90200000-0000-0000-0000-000000000009',
          'definition_id': '60000000-0000-0000-0000-000000000006',
          'code': 'credential_portal',
          'label': 'Portal con acceso',
          'source': 'manual',
          'metadata': <String, dynamic>{},
        },
      ],
      'relationship_tags': [
        {
          'id': '90300000-0000-0000-0000-000000000009',
          'definition_id': '70000000-0000-0000-0000-000000000007',
          'code': 'critical',
          'label': 'Crítico para la operación',
          'source': 'manual',
          'metadata': <String, dynamic>{},
        },
      ],
      'engagements': <Map<String, dynamic>>[],
      'accounting': {
        'policies': <Map<String, dynamic>>[],
        'rules': <Map<String, dynamic>>[],
        'recent_evidence': <Map<String, dynamic>>[],
        'observed_account_ids': <String>[],
      },
    });

SupplierCredentialStatus _credentialStatus({
  String? label,
  String? username,
  bool secretAvailable = true,
}) =>
    SupplierCredentialStatus(
      tenantId: _tenantId,
      supplierId: _supplierFixtureId,
      hasPortalCredential: label != null && secretAvailable,
      credentials: label == null
          ? const []
          : [
              SupplierCredentialMetadata(
                tenantId: _tenantId,
                supplierId: _supplierFixtureId,
                kind: SupplierCredentialKind.portalPassword,
                credentialKey: 'portal',
                originUrl: 'https://portal.proveedor.cl',
                label: label,
                username: username,
                updatedAt: DateTime.utc(2026, 8, 8),
                secretAvailable: secretAvailable,
              ),
            ],
    );

SupplierProfile _profileWithAccountingContext({
  bool includePolicy = false,
  String engagementEffectiveFrom = '2026-01-01',
  List<Map<String, dynamic>>? policyVersions,
  List<Map<String, dynamic>>? accountingRules,
}) =>
    SupplierProfile.fromJson({
      'tenant_id': _tenantId,
      'supplier_id': _supplierFixtureId,
      'party_id': '30000000-0000-0000-0000-000000000003',
      'party_kind': 'organization',
      'display_name': 'Proveedor contextual',
      'is_active': true,
      'has_portal_credential': false,
      'effective_business_date': '2026-08-08',
      'relationship_roles': const [
        {
          'id': '90000000-0000-0000-0000-000000000009',
          'definition_id': '40000000-0000-0000-0000-000000000004',
          'code': 'goods_vendor',
          'label': 'Bienes e inventario',
          'source': 'manual',
          'metadata': <String, dynamic>{},
        },
      ],
      'relationship_capabilities': const <Map<String, dynamic>>[],
      'relationship_tags': const <Map<String, dynamic>>[],
      'engagements': [
        {
          'id': _engagementId,
          'tenant_id': _tenantId,
          'supplier_id': _supplierFixtureId,
          'engagement_kind': 'lease',
          'code': 'lease-local',
          'name': 'Arriendo local',
          'status': 'active',
          'effective_business_date': '2026-08-08',
          'versions': [
            {
              'id': _engagementVersionId,
              'tenant_id': _tenantId,
              'engagement_id': _engagementId,
              'version_number': 1,
              'effective_from': engagementEffectiveFrom,
              'billing_cycle': 'monthly',
            },
          ],
        },
      ],
      'accounting': {
        'policies': includePolicy
            ? [
                {
                  'id': _policyId,
                  'tenant_id': _tenantId,
                  'supplier_id': _supplierFixtureId,
                  'engagement_id': _engagementId,
                  'effective_business_date': '2026-08-08',
                  'code': 'inventory-invoice',
                  'name': 'Inventario factura',
                  'status': 'active',
                  'versions': policyVersions ??
                      const [
                        {
                          'id': _policyVersionId,
                          'tenant_id': _tenantId,
                          'policy_id': _policyId,
                          'version_number': 1,
                          'effective_from': '2026-01-01',
                          'operational_nature_code': 'operating_expense',
                          'operational_nature_definition_id':
                              '80000000-0000-0000-0000-000000000008',
                          'tax_treatment': 'not_applicable',
                          'currency_code': 'CLP',
                        },
                      ],
                },
              ]
            : <Map<String, dynamic>>[],
        'rules': includePolicy
            ? accountingRules ??
                const [
                  {
                    'id': '95000000-0000-0000-0000-000000000095',
                    'tenant_id': _tenantId,
                    'policy_version_id': _policyVersionId,
                    'rule_kind': 'document_type',
                    'operator': 'equals',
                    'operand': {'document_type': '33'},
                    'priority': 10,
                    'is_active': true,
                  },
                  {
                    'id': '96000000-0000-0000-0000-000000000096',
                    'tenant_id': _tenantId,
                    'policy_version_id': _policyVersionId,
                    'rule_kind': 'description',
                    'operator': 'regex',
                    'operand': {'text': r'^flete\b'},
                    'priority': 20,
                    'is_active': true,
                  },
                ]
            : <Map<String, dynamic>>[],
        'recent_evidence': const <Map<String, dynamic>>[],
        'observed_account_ids': const <String>[],
      },
    });

class _FakeSupplierEditorDataSource implements SupplierEditorDataSource {
  _FakeSupplierEditorDataSource({
    required this.catalog,
    this.profile,
    this.saveError,
    this.appendEngagementError,
    this.appendAccountingError,
    this.credentialStatusCompleter,
    List<Completer<SupplierProfile?>> profileCompleters = const [],
    this.canManageCredentials = false,
    this.canManageAccounting = true,
  }) : profileCompleters = [...profileCompleters];

  final SupplierClassificationCatalog catalog;
  final SupplierProfile? profile;
  final Object? saveError;
  final Object? appendEngagementError;
  final Object? appendAccountingError;
  Completer<SupplierCredentialStatus>? credentialStatusCompleter;
  final List<Completer<SupplierProfile?>> profileCompleters;
  final List<SaveSupplierRelationshipProfileCommand> profileCommands = [];
  final List<AppendSupplierEngagementVersionCommand> appendedEngagements = [];
  final List<CreateSupplierAccountingPolicyCommand> createdAccountingPolicies =
      [];
  final List<AppendSupplierAccountingPolicyVersionCommand>
      appendedAccountingPolicies = [];

  @override
  bool canManageCredentials;

  @override
  bool canManageAccounting;

  int childMutationCalls = 0;
  int credentialMutationCalls = 0;
  int credentialStatusCalls = 0;
  final List<SupplierCredentialInput> credentialInputs = [];
  int profileCalls = 0;
  int accountCatalogCalls = 0;
  int expenseCategoryCatalogCalls = 0;
  final ValueNotifier<int> _authority = ValueNotifier(0);
  String _authorityLease = 'authority-a';

  @override
  String get authorityFingerprint =>
      'test-$_authorityLease-$canManageAccounting-'
      '$canManageCredentials';

  @override
  Listenable get authorityChanges => _authority;

  @override
  Stream<Object?>? get authAuthorityChanges => null;

  @override
  Future<SupplierClassificationCatalog> getClassificationCatalog() async =>
      catalog;

  @override
  Future<SupplierProfile?> getProfile(String requestedSupplierId) async {
    expect(requestedSupplierId, profile?.relationship.id);
    profileCalls++;
    if (profileCompleters.isNotEmpty) {
      return profileCompleters.removeAt(0).future;
    }
    return profile;
  }

  @override
  Future<SupplierProfileCommandResult> saveProfile(
    SaveSupplierRelationshipProfileCommand command,
  ) async {
    profileCommands.add(command);
    final error = saveError;
    if (error != null) throw error;
    return SupplierProfileCommandResult(profile: profile ?? _profile());
  }

  @override
  Future<SupplierEngagementCommandResult> createEngagement(
    CreateSupplierEngagementCommand command,
  ) async {
    childMutationCalls++;
    throw UnsupportedError('Not used by these editor tests.');
  }

  @override
  Future<SupplierEngagementCommandResult> appendEngagementVersion(
    AppendSupplierEngagementVersionCommand command,
  ) async {
    childMutationCalls++;
    appendedEngagements.add(command);
    throw appendEngagementError ??
        UnsupportedError('Not used by these editor tests.');
  }

  @override
  Future<SupplierAccountingPolicyCommandResult> createAccountingPolicy(
    CreateSupplierAccountingPolicyCommand command,
  ) async {
    childMutationCalls++;
    createdAccountingPolicies.add(command);
    throw UnsupportedError('Not used by these editor tests.');
  }

  @override
  Future<SupplierAccountingPolicyCommandResult> appendAccountingPolicyVersion(
    AppendSupplierAccountingPolicyVersionCommand command,
  ) async {
    childMutationCalls++;
    appendedAccountingPolicies.add(command);
    throw appendAccountingError ??
        UnsupportedError('Not used by these editor tests.');
  }

  @override
  Future<SupplierCredentialStatus> getCredentialStatus(
    String requestedSupplierId,
  ) async {
    credentialStatusCalls++;
    final completer = credentialStatusCompleter;
    if (completer != null) return completer.future;
    return SupplierCredentialStatus(
      tenantId: profile?.relationship.tenantId ??
          '10000000-0000-0000-0000-000000000001',
      supplierId: requestedSupplierId,
      hasPortalCredential: false,
    );
  }

  @override
  Future<SupplierCredentialUpsertResult> upsertCredential(
    SupplierCredentialInput input,
  ) async {
    childMutationCalls++;
    credentialMutationCalls++;
    credentialInputs.add(input);
    final metadata = SupplierCredentialMetadata(
      tenantId: profile?.relationship.tenantId ?? _tenantId,
      supplierId: input.supplierId,
      kind: input.kind,
      credentialKey: input.credentialKey,
      engagementId: input.engagementId,
      originUrl: input.originUrl,
      label: input.label,
      username: input.username,
      updatedAt: DateTime.utc(2026, 8, 9),
    );
    return SupplierCredentialUpsertResult(
      operationId: input.operationId,
      action: SupplierCredentialUpsertAction.create,
      idempotentReplay: false,
      appliedCredential: metadata,
      currentCredential: metadata,
    );
  }

  @override
  Future<SupplierCredentialDeleteResult> deleteCredential({
    required String supplierId,
    required SupplierCredentialKind kind,
    required String credentialKey,
    required String operationId,
    required DateTime expectedUpdatedAt,
  }) async {
    childMutationCalls++;
    credentialMutationCalls++;
    throw UnsupportedError('Not used by these editor tests.');
  }

  @override
  Future<List<Account>> getAccounts() async {
    accountCatalogCalls++;
    return const [];
  }

  @override
  Future<List<ExpenseCategory>> getExpenseCategories() async {
    expenseCategoryCatalogCalls++;
    return const [];
  }

  void setAccountingAuthority(bool value) {
    canManageAccounting = value;
    _authority.value++;
  }

  void setCredentialAuthority(bool value) {
    canManageCredentials = value;
    _authority.value++;
  }

  void setBaseAuthority(String lease) {
    _authorityLease = lease;
    _authority.value++;
  }
}
