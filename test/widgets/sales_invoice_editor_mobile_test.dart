import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/accounting/services/accounting_service.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/crm/models/crm_models.dart';
import 'package:vinabike_erp/modules/crm/services/customer_service.dart';
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';
import 'package:vinabike_erp/modules/sales/services/sales_service.dart';
import 'package:vinabike_erp/modules/sales/widgets/sales_invoice_editor.dart';
import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/inventory_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          headers: const {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
  });

  testWidgets(
    'compact invoice keeps the mobile composition and protects inline back',
    (tester) async {
      tester.view.physicalSize = const Size(384, 824);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final semanticsHandle = tester.ensureSemantics();

      final database = DatabaseService();
      final accounting = AccountingService(database);
      final sales = SalesService(database, accounting, TenantService());
      final customers = _InvoiceEditorCustomerService(database);
      final inventory = _InvoiceEditorInventoryService();
      final bikeshop = BikeshopService(database);
      addTearDown(sales.dispose);
      addTearDown(customers.dispose);
      addTearDown(inventory.dispose);
      addTearDown(bikeshop.dispose);
      addTearDown(accounting.dispose);
      addTearDown(database.dispose);

      var closeRequests = 0;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DatabaseService>.value(value: database),
            ChangeNotifierProvider<SalesService>.value(value: sales),
            ChangeNotifierProvider<CustomerService>.value(value: customers),
            ChangeNotifierProvider<InventoryService>.value(value: inventory),
            ChangeNotifierProvider<BikeshopService>.value(value: bikeshop),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: SalesInvoiceEditor(
                isCompact: true,
                allowFullScreenExpansion: false,
                onCloseRequested: () => closeRequests++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('invoice-editor-inline-back')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('invoice-editor-mobile-lines')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('invoice-editor-issue-date')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('invoice-editor-due-date')),
        findsOneWidget,
      );
      expect(find.byTooltip('Buscar cliente'), findsOneWidget);
      final backButton =
          find.byKey(const ValueKey('invoice-editor-inline-back'));
      final saveButton = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Guardar factura',
      );
      expect(saveButton, findsOneWidget);
      expect(
        tester.widget<IconButton>(backButton).tooltip,
        'Volver a trabajos',
      );
      expect(
        tester.widget<IconButton>(saveButton).tooltip,
        'Guardar factura',
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Emisión: ')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Vencimiento: ')),
        findsOneWidget,
      );
      _expectMinimumTouchTarget(tester, backButton);
      _expectMinimumTouchTarget(tester, saveButton);
      _expectMinimumTouchTarget(
        tester,
        find.byKey(const ValueKey('invoice-editor-issue-date')),
      );
      _expectMinimumTouchTarget(
        tester,
        find.byKey(const ValueKey('invoice-editor-due-date')),
      );
      expect(tester.takeException(), isNull);

      final referenceField = find.widgetWithText(
        TextFormField,
        'Referencia / Observaciones',
      );
      await tester.ensureVisible(referenceField);
      await tester.enterText(referenceField, 'Revisión móvil');
      await tester.pump();

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(referenceField);
      await tester.pumpAndSettle();

      expect(referenceField.hitTestable(), findsOneWidget);
      expect(saveButton.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      final inlineBack = tester.widget<IconButton>(
        backButton,
      );
      inlineBack.onPressed!.call();
      inlineBack.onPressed!.call();
      await tester.pumpAndSettle();

      expect(find.text('¿Descartar cambios?'), findsOneWidget);
      expect(closeRequests, 0);

      await tester.tap(find.text('Continuar editando'));
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar cambios?'), findsNothing);
      expect(closeRequests, 0);

      await tester.tap(backButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar cambios'));
      await tester.pumpAndSettle();

      expect(closeRequests, 1);
      expect(tester.takeException(), isNull);
      semanticsHandle.dispose();
    },
  );

  testWidgets(
    'loaded compact invoice exposes one semantic payment action at every boundary',
    (tester) async {
      tester.view.physicalSize = const Size(384, 824);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semanticsHandle = tester.ensureSemantics();

      final database = DatabaseService();
      final accounting = AccountingService(database);
      final invoice = _invoiceWithBalance();
      final sales = _InvoiceEditorSalesService(
        database,
        accounting,
        invoice,
      );
      final customers = _InvoiceEditorCustomerService(database);
      final inventory = _InvoiceEditorInventoryService();
      final bikeshop = BikeshopService(database);
      addTearDown(sales.dispose);
      addTearDown(customers.dispose);
      addTearDown(inventory.dispose);
      addTearDown(bikeshop.dispose);
      addTearDown(accounting.dispose);
      addTearDown(database.dispose);

      final requestCompleter = Completer<void>();
      var paymentRequests = 0;
      await tester.pumpWidget(
        _loadedInvoiceHarness(
          database: database,
          sales: sales,
          customers: customers,
          inventory: inventory,
          bikeshop: bikeshop,
          invoice: invoice,
          onRegisterPaymentRequested: (requestedInvoice) {
            expect(requestedInvoice.id, invoice.id);
            paymentRequests++;
            return requestCompleter.future;
          },
        ),
      );
      await tester.pumpAndSettle();

      const paymentKey = ValueKey('invoice-editor-register-payment');
      final paymentAction = find.byKey(paymentKey);
      for (final width in <double>[384, 599, 600, 899, 900, 1440]) {
        tester.view.physicalSize = Size(width, width == 1440 ? 900 : 824);
        await tester.pump();

        expect(paymentAction, findsOneWidget, reason: 'viewport $width');
        expect(
          find.bySemanticsLabel('Registrar abono'),
          findsOneWidget,
          reason: 'viewport $width',
        );
        _expectMinimumTouchTarget(tester, paymentAction);
        expect(tester.takeException(), isNull, reason: 'viewport $width');
      }

      final enabledAction = tester.widget<FilledButton>(paymentAction);
      enabledAction.onPressed!.call();
      enabledAction.onPressed!.call();
      await tester.pump();

      expect(paymentRequests, 1);
      expect(tester.widget<FilledButton>(paymentAction).onPressed, isNull);

      requestCompleter.complete();
      await tester.pumpAndSettle();

      expect(paymentRequests, 1);
      expect(tester.widget<FilledButton>(paymentAction).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      semanticsHandle.dispose();
    },
  );

  testWidgets(
    'compact payment action stays hidden for an ineligible invoice',
    (tester) async {
      tester.view.physicalSize = const Size(384, 824);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final database = DatabaseService();
      final accounting = AccountingService(database);
      final invoice =
          _invoiceWithBalance().copyWith(status: InvoiceStatus.cancelled);
      final sales = _InvoiceEditorSalesService(
        database,
        accounting,
        invoice,
      );
      final customers = _InvoiceEditorCustomerService(database);
      final inventory = _InvoiceEditorInventoryService();
      final bikeshop = BikeshopService(database);
      addTearDown(sales.dispose);
      addTearDown(customers.dispose);
      addTearDown(inventory.dispose);
      addTearDown(bikeshop.dispose);
      addTearDown(accounting.dispose);
      addTearDown(database.dispose);

      await tester.pumpWidget(
        _loadedInvoiceHarness(
          database: database,
          sales: sales,
          customers: customers,
          inventory: inventory,
          bikeshop: bikeshop,
          invoice: invoice,
          onRegisterPaymentRequested: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('invoice-editor-register-payment')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _loadedInvoiceHarness({
  Key? editorKey,
  required DatabaseService database,
  required SalesService sales,
  required CustomerService customers,
  required InventoryService inventory,
  required BikeshopService bikeshop,
  required Invoice invoice,
  required Future<void> Function(Invoice invoice) onRegisterPaymentRequested,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DatabaseService>.value(value: database),
      ChangeNotifierProvider<SalesService>.value(value: sales),
      ChangeNotifierProvider<CustomerService>.value(value: customers),
      ChangeNotifierProvider<InventoryService>.value(value: inventory),
      ChangeNotifierProvider<BikeshopService>.value(value: bikeshop),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.3),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SalesInvoiceEditor(
          key: editorKey,
          invoiceId: invoice.id,
          isCompact: true,
          allowFullScreenExpansion: false,
          onCloseRequested: () {},
          onRegisterPaymentRequested: onRegisterPaymentRequested,
        ),
      ),
    ),
  );
}

void _expectMinimumTouchTarget(
  WidgetTester tester,
  Finder finder,
) {
  final size = tester.getSize(finder);
  expect(size.width, greaterThanOrEqualTo(48));
  expect(size.height, greaterThanOrEqualTo(48));
}

class _InvoiceEditorCustomerService extends CustomerService {
  _InvoiceEditorCustomerService(DatabaseService database)
      : super(database, TenantService());

  @override
  Future<List<Customer>> getCustomersForList({
    bool forceRefresh = false,
  }) async {
    return [_customer];
  }
}

class _InvoiceEditorInventoryService extends InventoryService {
  _InvoiceEditorInventoryService() : super(db: null);

  @override
  Future<List<Product>> loadProductPreviewPage({
    required int page,
    int pageSize = 80,
    bool reset = false,
  }) async {
    return const [];
  }
}

class _InvoiceEditorSalesService extends SalesService {
  _InvoiceEditorSalesService(
    DatabaseService database,
    AccountingService accounting,
    this.invoice,
  ) : super(database, accounting, TenantService());

  Invoice invoice;

  @override
  Future<Invoice?> fetchInvoice(String id, {bool refresh = false}) async {
    return invoice.id == id ? invoice : null;
  }
}

Invoice _invoiceWithBalance() {
  return Invoice(
    id: 'invoice-mobile',
    tenantId: 'tenant-mobile',
    invoiceNumber: 'FV-00902',
    customerId: _customer.id,
    customerName: _customer.name,
    date: DateTime(2026, 7, 26),
    status: InvoiceStatus.confirmed,
    total: 100000,
    paidAmount: 25000,
    balance: 75000,
  );
}

final _customer = Customer(
  id: 'customer-mobile',
  tenantId: 'tenant-mobile',
  name: 'Cliente móvil',
  rut: '11.111.111-1',
);
