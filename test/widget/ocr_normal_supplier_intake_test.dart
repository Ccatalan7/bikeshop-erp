import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart'
    as catalog;
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart'
    as catalog_models;
import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/models/supplier.dart';
import 'package:vinabike_erp/shared/services/inventory_service.dart';
import 'package:vinabike_erp/shared/services/invoice_parser_service.dart';
import 'package:vinabike_erp/shared/services/ocr_file_handoff_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/ocr_upload_widget.dart';

final _supplierJson = <String, dynamic>{
  'id': 'derman',
  'tenant_id': 'test-tenant',
  'name': 'Derman',
  'created_at': '2026-09-03',
  'updated_at': '2026-09-03',
};

Product _product(String code) => Product(
    id: 'product-$code',
    name: 'Inventario $code',
    sku: code,
    price: 15000,
    cost: 6000,
    stockQuantity: 7,
    category: ProductCategory.other,
    supplierId: 'derman',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026));

class _Inventory extends ChangeNotifier implements InventoryService {
  final requests = <String>[];
  final supplierRequests = <String>[];
  final pending = <String, Completer<Product?>>{};
  final productsByCode = <String, Product>{};
  final supplierProductsByCode = <String, Product>{};
  final failures = <String>{};
  int nameSearches = 0;
  Completer<List<Product>>? pendingNameSearch;

  @override
  Future<Product?> getProductBySku(String sku) async {
    requests.add(sku);
    if (failures.contains(sku)) throw StateError('Lookup unavailable');
    if (pending.containsKey(sku)) return pending[sku]!.future;
    return productsByCode[sku];
  }

  @override
  Future<Product?> getProductBySupplierCodeForSupplier({
    required String supplierId,
    required String supplierCode,
  }) async {
    supplierRequests.add('$supplierId:$supplierCode');
    return supplierProductsByCode[supplierCode];
  }

  @override
  Future<List<Product>> searchProducts(
    String query, {
    int limit = 200,
    ProductType? productType,
  }) async {
    nameSearches++;
    return pendingNameSearch == null ? [] : await pendingNameSearch!.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Purchases extends ChangeNotifier implements PurchaseService {
  List<Supplier> suppliers = [];
  Completer<List<Supplier>>? pending;
  @override
  Future<List<Supplier>> getSuppliers({
    bool forceRefresh = false,
    bool activeOnly = false,
  }) async {
    if (pending != null) return pending!.future;
    return suppliers;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Catalog extends ChangeNotifier implements catalog.InventoryService {
  @override
  Future<List<catalog_models.Product>> getProducts(
          {String? searchTerm,
          String? categoryId,
          bool? lowStockOnly,
          bool forceRefresh = false}) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Picker extends FilePicker {
  Completer<FilePickerResult?> result = Completer<FilePickerResult?>();
  int opens = 0;
  @override
  Future<FilePickerResult?> pickFiles(
      {String? dialogTitle,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Function(FilePickerStatus)? onFileLoading,
      bool allowCompression = true,
      int compressionQuality = 30,
      bool allowMultiple = false,
      bool withData = false,
      bool withReadStream = false,
      bool lockParentWindow = false,
      bool readSequential = false}) {
    opens++;
    return result.future;
  }
}

class _Backend {
  int supplierReads = 0;
  int ocrReads = 0;
  String vendor = 'Proveedor no reconocido';
  Completer<http.Response>? supplierResponse;
  bool supplierError = false;
  Map<String, dynamic>? ocrDocument;
  Future<http.Response> request(http.Request request) async {
    if (request.url.path.endsWith('/veryfi-ocr')) {
      ocrReads++;
      expect(jsonDecode(request.body)['contentType'], 'application/pdf');
      // Controlled OCR response with missing codes, not a claim to reproduce
      // the original supplier PDF/provider recognition accuracy.
      return http.Response(
          jsonEncode(ocrDocument ??
              {
                'vendor': {'name': vendor},
                'invoice_number': '10228',
                'date': '2026-09-03',
                'total': 26184,
                'line_items': [
                  {
                    'description': 'Motor sellado',
                    'quantity': 2,
                    'unit_price': 7810,
                    'total': 15620
                  },
                  {
                    'description': 'Pedales aluminio',
                    'quantity': 4,
                    'unit_price': 2641,
                    'total': 10564
                  },
                ],
              }),
          200,
          headers: {'content-type': 'application/json'});
    }
    if (request.url.path.endsWith('/suppliers')) {
      supplierReads++;
      if (supplierError) {
        return http.Response('{"message":"Unavailable"}', 503,
            headers: {'content-type': 'application/json'});
      }
      if (supplierResponse != null) return supplierResponse!.future;
      return suppliers();
    }
    throw StateError(
        'Unexpected request: ${request.method} ${request.url.path}');
  }

  http.Response suppliers() => http.Response(jsonEncode([_supplierJson]), 200,
      headers: {'content-type': 'application/json'});
}

void main() {
  late _Backend backend;
  late _Picker picker;
  late _Inventory inventory;
  late _Purchases purchases;
  late GlobalKey<NavigatorState> nested;
  ParsedInvoice? applied;
  late Uint8List pdfBytes;

  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    await (FontLoader('Barlow')
          ..addFont(rootBundle.load('assets/fonts/Barlow-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Barlow-SemiBold.ttf')))
        .load();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://ocr-test.supabase.co',
        anonKey: 'test-key',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient((request) async {
          final response = await backend.request(request);
          return http.Response.bytes(response.bodyBytes, response.statusCode,
              headers: response.headers, request: request);
        }));
    final pdf = PdfDocument();
    pdf.pages.add().graphics.drawString('FACTURA 10228 - prueba de ingreso PDF',
        PdfStandardFont(PdfFontFamily.helvetica, 12),
        bounds: const ui.Rect.fromLTWH(0, 0, 400, 30));
    pdfBytes = Uint8List.fromList(pdf.saveSync());
    pdf.dispose();
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() {
    backend = _Backend();
    inventory = _Inventory();
    purchases = _Purchases();
    nested = GlobalKey<NavigatorState>();
    applied = null;
  });

  // Supabase's JSON codec runs in a real isolate; give its port time to
  // complete before pumpAndSettle advances the fake timeout clock.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester,
      {double width = 1440,
      Brightness brightness = Brightness.light,
      bool initialFile = true}) async {
    picker = _Picker();
    FilePicker.platform = picker;
    await tester.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final theme = AppTheme.resolve(
        preset: AppearancePresets.vinabike, brightness: brightness);
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<InventoryService>.value(value: inventory),
          ChangeNotifierProvider<catalog.InventoryService>(
              create: (_) => _Catalog()),
          ChangeNotifierProvider<PurchaseService>.value(value: purchases),
        ],
        child: MaterialApp(
          theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'Barlow')),
          home: Scaffold(
              body: Navigator(
                  key: nested,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => const Text('Borrador de compra')))),
        )));
    unawaited(nested.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => OCRUploadWidget(
              provider: OCRProvider.veryfi,
              initialFile: !initialFile
                  ? null
                  : OcrFileHandoffPayload(
                      id: 'normal-pdf',
                      target: OcrFileHandoffTarget.purchaseInvoice,
                      fileName: 'derman-10228.pdf',
                      mimeType: 'application/pdf',
                      extension: 'pdf',
                      bytes: pdfBytes),
              onComplete: (invoice) {
                applied = invoice;
              },
            ))));
    await settle(tester);
    expect(find.text(initialFile ? 'Factura leída' : 'Carga la factura'),
        findsOneWidget);
    expect(backend.ocrReads, initialFile ? 1 : 0);
    expect(tester.takeException(), isNull);
  }

  Future<void> selectSupplier(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('ocr-preview-review-products')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('ocr-supplier-derman')));
    await settle(tester);
    expect(find.byKey(const Key('ocr-supplier-picker')), findsNothing);
    expect(
        find.byWidgetPredicate(
            (widget) => widget is ModalBarrier && (widget.color?.a ?? 0) > 0),
        findsNothing);
    expect(find.text('Factura leída'), findsOneWidget);
    expect(nested.currentState!.canPop(), isTrue);
  }

  Future<void> edit(WidgetTester tester, int row, String code) async {
    final field = find.byKey(Key('ocr-preview-code-$row'));
    await tester.ensureVisible(field);
    await tester.enterText(field, code);
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
  }

  for (final width in [1440.0, 430.0]) {
    testWidgets('net supplier lines reconcile with explicit IVA at $width',
        (tester) async {
      backend.ocrDocument = {
        'vendor': {'name': 'Derman'},
        'subtotal': 8258,
        'tax': 1569,
        'total': 9827,
        'line_items': [
          {
            'description': 'Neumático',
            'quantity': 2,
            'price': null,
            'total': 8258
          }
        ],
      };
      inventory.productsByCode['TIRE'] = _product('TIRE');
      await pump(tester, width: width);
      expect(find.textContaining('Revisar antes de importar'), findsNothing);
      expect(find.textContaining('IVA  \$ 1.569'), findsOneWidget);
      expect(find.textContaining('Diferencia  \$ 0'), findsOneWidget);
      expect(find.textContaining('4.129'), findsWidgets);
      await selectSupplier(tester);
      await edit(tester, 0, 'TIRE');
      await settle(tester);
      await tester.tap(find.text('Usar esta factura'));
      await settle(tester);
      expect(applied!.taxAmount, 1569);
      expect(applied!.lineItems.single.quantity, 2);
      expect(applied!.lineItems.single.unitPrice, 4129);
      expect(applied!.lineItems.single.total, 8258);
    });
  }

  testWidgets('unexplained header differences are not reclassified as IVA',
      (tester) async {
    backend.ocrDocument = {
      'subtotal': 8258,
      'tax': 1569,
      'total': 10827,
      'line_items': [
        {
          'description': 'Neumático',
          'quantity': 2,
          'price': null,
          'total': 8258
        }
      ],
    };
    await pump(tester);
    expect(find.textContaining('Revisar antes de importar'), findsOneWidget);
    expect(find.textContaining('IVA  '), findsNothing);
    expect(find.textContaining('Diferencia  \$ 2.569'), findsOneWidget);
  });

  testWidgets(
      'automatic supplier lookup cannot hold the OCR preview indefinitely',
      (tester) async {
    purchases.pending = Completer<List<Supplier>>();
    await pump(tester);
    expect(find.text('Seleccionar proveedor'), findsWidgets);
    purchases.pending!.complete([Supplier.fromJson(_supplierJson)]);
    await settle(tester);
    expect(find.text('Seleccionar proveedor'), findsWidgets);
    expect(find.text('Factura leída'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'opening the file chooser is not OCR work; cancel and retry stay usable',
      (tester) async {
    await pump(tester, initialFile: false);
    final select = find.byKey(const Key('ocr-upload-select-file'));
    await tester.tap(select);
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Leyendo la factura…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(backend.ocrReads, 0);
    expect(picker.opens, 1);
    expect(tester.widget<FilledButton>(select).onPressed, isNull);
    picker.result.complete(null);
    await settle(tester);
    expect(tester.widget<FilledButton>(select).onPressed, isNotNull);
    picker.result = Completer<FilePickerResult?>();
    await tester.tap(select);
    await tester.pump();
    picker.result.complete(FilePickerResult([
      PlatformFile(
          name: 'derman-test.pdf', size: pdfBytes.length, bytes: pdfBytes),
    ]));
    await settle(tester);
    expect(find.text('Factura leída'), findsOneWidget);
    expect(backend.ocrReads, 1);
    expect(tester.takeException(), isNull);
  });

  for (final completion in ['cancel', 'selected', 'failure']) {
    testWidgets(
        'closing OCR while the file chooser is pending ignores $completion',
        (tester) async {
      await pump(tester, initialFile: false);
      await tester.tap(find.byKey(const Key('ocr-upload-select-file')));
      await tester.pump();
      nested.currentState!.pop();
      await settle(tester);
      if (completion == 'failure') {
        picker.result.completeError(StateError('Native picker closed'));
      } else if (completion == 'selected') {
        picker.result.complete(FilePickerResult([
          PlatformFile(
              name: 'derman-test.pdf', size: pdfBytes.length, bytes: pdfBytes),
        ]));
      } else {
        picker.result.complete(null);
      }
      await settle(tester);
      expect(find.text('Borrador de compra'), findsOneWidget);
      expect(backend.ocrReads, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('normal PDF exposes editable codes in the invoice preview',
      (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('ocr-preview-code-0')), findsOneWidget);
    expect(find.byKey(const Key('ocr-preview-code-1')), findsOneWidget);
    expect(find.text('Productos de la factura'), findsOneWidget);
  });

  testWidgets(
      'supplier selection preserves nested invoice route and closes only its picker',
      (tester) async {
    backend.supplierResponse = Completer<http.Response>();
    await pump(tester);
    await tester.tap(find.byKey(const Key('ocr-preview-review-products')));
    await tester.pump();
    expect(find.text('Cargando proveedores…'), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (widget) => widget is ModalBarrier && (widget.color?.a ?? 0) > 0),
        findsNothing);
    expect(find.text('Factura leída'), findsOneWidget);
    backend.supplierResponse!.complete(backend.suppliers());
    await settle(tester);
    await tester.enterText(
        find.byKey(const Key('ocr-supplier-search')), 'derm');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ocr-supplier-derman')));
    await settle(tester);
    expect(
        find.byWidgetPredicate(
            (widget) => widget is ModalBarrier && (widget.color?.a ?? 0) > 0),
        findsNothing);
    expect(find.text('Factura leída'), findsOneWidget);
    expect(nested.currentState!.canPop(), isTrue);
    expect(backend.supplierReads, 1);
    expect(tester.takeException(), isNull);
  });

  for (final width in [1440.0, 390.0]) {
    testWidgets(
        'supplier selection renders before catalog verification at $width',
        (tester) async {
      await pump(tester, width: width);
      inventory.pendingNameSearch = Completer<List<Product>>();
      await tester.tap(find.byKey(const Key('ocr-preview-review-products')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('ocr-supplier-derman')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The directory already gave us the chosen supplier. Slow catalog reads
      // must not withhold the visible acknowledgement of that choice.
      expect(find.byKey(const Key('ocr-supplier-picker')), findsNothing);
      expect(find.text('Derman'), findsOneWidget);
      expect(find.text('Verificando productos…'), findsOneWidget);
      expect(inventory.nameSearches, 2);
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const Key('ocr-preview-review-products')))
              .onPressed,
          isNull);
      expect(applied, isNull);
      expect(nested.currentState!.canPop(), isTrue);

      inventory.pendingNameSearch!.complete([]);
      await settle(tester);
      expect(find.text('Derman'), findsOneWidget);
      expect(find.text('Verificando productos…'), findsNothing);
      expect(find.byKey(const Key('ocr-preview-code-0')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final timeout in [false, true]) {
    testWidgets(
        'supplier ${timeout ? 'timeout' : 'failure'} leaves a retryable invoice',
        (tester) async {
      if (timeout) {
        backend.supplierResponse = Completer<http.Response>();
      } else {
        backend.supplierError = true;
      }
      await pump(tester);
      await tester.tap(find.byKey(const Key('ocr-preview-review-products')));
      await tester.pump();
      if (timeout) await tester.pump(const Duration(seconds: 16));
      await settle(tester);
      expect(
          find.byWidgetPredicate(
              (widget) => widget is ModalBarrier && (widget.color?.a ?? 0) > 0),
          findsNothing);
      expect(find.text('Factura leída'), findsOneWidget);
      expect(find.textContaining('Reintenta.'), findsOneWidget);
      backend.supplierError = false;
      backend.supplierResponse?.complete(backend.suppliers());
      backend.supplierResponse = null;
      await tester.tap(find.text('Reintentar'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('ocr-supplier-derman')));
      await settle(tester);
      expect(find.byKey(const Key('ocr-supplier-picker')), findsNothing);
      expect(find.text('Factura leída'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [1440.0, 390.0]) {
    testWidgets(
        'normal PDF codes resolve real records and preserve amounts at width $width',
        (tester) async {
      await pump(tester, width: width, brightness: Brightness.dark);
      await selectSupplier(tester);
      inventory.productsByCode['INT-1'] = _product('INT-1');
      inventory.supplierProductsByCode['PROV-2'] = _product('INT-2');
      final previousNameSearches = inventory.nameSearches;
      await edit(tester, 0, 'INT-1');
      await edit(tester, 1, 'PROV-2');
      expect(inventory.nameSearches, previousNameSearches);
      expect(inventory.supplierRequests, contains('derman:PROV-2'));
      await tester.tap(find.byKey(const Key('ocr-preview-review-products')));
      await settle(tester);
      expect(applied?.supplierName, 'Derman');
      expect(applied?.lineItems.map((item) => item.matchedProductId),
          ['product-INT-1', 'product-INT-2']);
      expect(applied?.lineItems.map((item) => item.sku), ['INT-1', 'PROV-2']);
      expect(applied?.lineItems.map((item) => item.quantity), [2, 4]);
      expect(applied?.lineItems.map((item) => item.total), [15620, 10564]);
      expect(applied?.total, 26184);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'per-row debounce and revisions reject old matches; clearing invalidates identity',
      (tester) async {
    await pump(tester);
    await selectSupplier(tester);
    inventory.pending['OLD'] = Completer<Product?>();
    inventory.productsByCode['NEW'] = _product('NEW');
    inventory.productsByCode['SECOND'] = _product('SECOND');
    await edit(tester, 0, 'OLD');
    await edit(tester, 0, 'NEW');
    await edit(tester, 1, 'SECOND');
    inventory.pending['OLD']!.complete(_product('OLD'));
    await settle(tester);
    expect(find.textContaining('Inventario OLD'), findsNothing);
    await edit(tester, 0, '');
    expect(find.textContaining('Inventario NEW'), findsNothing);
    expect(find.textContaining('Inventario SECOND'), findsWidgets);
    expect(find.text('Usar esta factura'), findsNothing);
    await edit(tester, 0, 'NEW');
    await tester.tap(find.byKey(const Key('ocr-preview-review-products')));
    await settle(tester);
    expect(applied?.lineItems.first.matchedProductId, 'product-NEW');
    expect(tester.takeException(), isNull);
  });

  testWidgets('code lookup errors preserve the edit and allow explicit retry',
      (tester) async {
    await pump(tester);
    await selectSupplier(tester);
    inventory.failures.add('RETRY');
    await edit(tester, 0, 'RETRY');
    expect(find.text('No se pudo verificar'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('ocr-preview-code-0')))
            .controller!
            .text,
        'RETRY');
    inventory.failures.clear();
    inventory.productsByCode['RETRY'] = _product('RETRY');
    await tester.tap(find.byTooltip('Verificar código de la línea 1'));
    await settle(tester);
    expect(find.text('No se pudo verificar'), findsNothing);
    expect(find.textContaining('Inventario RETRY'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reloading discards verification after acknowledging the supplier',
      (tester) async {
    await pump(tester);
    inventory.pendingNameSearch = Completer<List<Product>>();
    await tester.tap(find.byKey(const Key('ocr-preview-review-products')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('ocr-supplier-derman')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Derman'), findsOneWidget);
    await tester.tap(find.text('Volver a cargar'));
    await tester.pump();
    inventory.pendingNameSearch!.complete([]);
    await settle(tester);
    expect(find.text('Carga la factura'), findsOneWidget);
    expect(find.text('Derman'), findsNothing);
    expect(find.text('Factura leída'), findsNothing);
    expect(applied, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reloading the document discards a pending supplier response',
      (tester) async {
    backend.supplierResponse = Completer<http.Response>();
    await pump(tester);
    await tester.tap(find.byKey(const Key('ocr-preview-review-products')));
    await tester.pump();
    await tester.tap(find.text('Volver a cargar'));
    await tester.pump();
    backend.supplierResponse!.complete(backend.suppliers());
    await settle(tester);
    expect(find.byKey(const Key('ocr-supplier-picker')), findsNothing);
    expect(find.text('Factura leída'), findsNothing);
    expect(
        find.byWidgetPredicate(
            (widget) => widget is ModalBarrier && (widget.color?.a ?? 0) > 0),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'AliExpress source codes do not become ordinary editable catalog codes',
      (tester) async {
    backend.vendor = 'AliExpress';
    purchases.suppliers = [
      Supplier.fromJson({..._supplierJson, 'name': 'AliExpress'})
    ];
    await pump(tester);
    expect(find.byKey(const Key('ocr-preview-code-0')), findsNothing);
    expect(inventory.requests, isEmpty);
    expect(inventory.supplierRequests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
