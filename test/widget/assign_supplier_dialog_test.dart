import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/services/messaging_service.dart';
import 'package:vinabike_erp/modules/messaging/widgets/assign_supplier_dialog.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/shared/models/supplier.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

// Proveedores y personas inventados.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  Future<_RecordingMessaging> pumpDialog(
    WidgetTester tester, {
    String? failWith,
  }) async {
    final messaging = _RecordingMessaging(failWith: failWith);
    SupplierChatAssignment? popped;
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<PurchaseService>(
        create: (_) => _SuppliersPurchaseService(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    popped = await showDialog<SupplierChatAssignment>(
                      context: context,
                      builder: (_) => AssignSupplierDialog(
                        conversationId: 'conversation-1',
                        contactName: 'Persona Nueva',
                        phoneLabel: '+56 9 3000 0004',
                        messagingService: messaging,
                      ),
                    );
                    messaging.popped = popped;
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return messaging;
  }

  testWidgets('picks a supplier and moves the chat with one operation',
      (tester) async {
    final messaging = await pumpDialog(tester);

    expect(find.text('Es de un proveedor'), findsOneWidget);
    expect(
      find.textContaining('+56 9 3000 0004 queda como contacto'),
      findsOneWidget,
    );
    final submit = find.byKey(const ValueKey('assign-supplier-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull,
        reason: 'nothing to move until a supplier is chosen');

    await tester.enterText(
      find.byKey(const ValueKey('assign-supplier-search')),
      'ciclo',
    );
    await tester.pump();
    expect(find.text('Proveedor Andino'), findsNothing);
    await tester.tap(find.text('Ciclos del Valle'));
    await tester.pump();
    expect(
      find.textContaining('Reemplaza a Vendedor Anterior'),
      findsOneWidget,
    );

    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(messaging.calls, hasLength(1));
    final call = messaging.calls.single;
    expect(call.supplierId, 'supplier-ciclos');
    expect(call.contactName, 'Persona Nueva');
    expect(call.isPrimary, isTrue);
    expect(call.operationId, isNotEmpty);
    expect(messaging.popped?.supplierName, 'Ciclos del Valle');
    expect(find.text('Es de un proveedor'), findsNothing);
  });

  testWidgets('a chat bound to a customer explains itself inside the dialog',
      (tester) async {
    final messaging = await pumpDialog(
      tester,
      failWith:
          'Este chat está unido a un cliente; no se puede pasar a Proveedores.',
    );

    await tester.tap(find.text('Proveedor Andino'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('assign-supplier-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('se queda en Mensajería'), findsOneWidget);
    expect(find.text('Es de un proveedor'), findsOneWidget,
        reason: 'the dialog stays open with the reason');
    expect(messaging.popped, isNull);
  });
}

class _AssignCall {
  _AssignCall(this.supplierId, this.operationId, this.contactName,
      this.isPrimary);

  final String supplierId;
  final String operationId;
  final String? contactName;
  final bool isPrimary;
}

class _RecordingMessaging extends MessagingService {
  _RecordingMessaging({this.failWith});

  final String? failWith;
  final calls = <_AssignCall>[];
  SupplierChatAssignment? popped;

  @override
  Future<SupplierChatAssignment> assignConversationToSupplier({
    required String conversationId,
    required String supplierId,
    required String operationId,
    String? contactName,
    bool isPrimary = false,
  }) async {
    calls.add(_AssignCall(supplierId, operationId, contactName, isPrimary));
    if (failWith != null) {
      throw PostgrestException(message: failWith!, code: '23514');
    }
    return SupplierChatAssignment(
      conversationId: conversationId,
      supplierId: supplierId,
      supplierName: supplierId == 'supplier-ciclos'
          ? 'Ciclos del Valle'
          : 'Proveedor Andino',
      supplierContactId: 'contact-1',
      contactCreated: true,
    );
  }
}

class _SuppliersPurchaseService extends PurchaseService {
  _SuppliersPurchaseService() : super(DatabaseService(), TenantService());

  static final _now = DateTime(2026, 10, 13);

  @override
  Future<List<Supplier>> getSuppliers({
    bool forceRefresh = false,
    bool activeOnly = false,
  }) async {
    return [
      Supplier(
        id: 'supplier-andino',
        tenantId: 'tenant-1',
        name: 'Proveedor Andino',
        createdAt: _now,
        updatedAt: _now,
      ),
      Supplier(
        id: 'supplier-ciclos',
        tenantId: 'tenant-1',
        name: 'Ciclos del Valle',
        salesRepName: 'Vendedor Anterior',
        createdAt: _now,
        updatedAt: _now,
      ),
    ];
  }
}
