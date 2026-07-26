import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/widgets/stock_movements_responsive_frame.dart';

void main() {
  group('StockMovementsResponsiveFrame compact composition', () {
    for (final size in const <Size>[
      Size(384, 824),
      Size(599, 900),
      Size(600, 900),
      Size(899, 900),
    ]) {
      testWidgets(
        '${size.width.toInt()} preserves list context through detail and back',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await _pumpHarness(tester, size: size);

          expect(
            find.byKey(const ValueKey('stock-movements-compact-header')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('stock-movements-desktop-split')),
            findsNothing,
          );
          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey('stock-movements-mode-recent')),
                )
                .height,
            greaterThanOrEqualTo(48),
          );
          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey('stock-movements-mode-product')),
                )
                .height,
            greaterThanOrEqualTo(48),
          );

          await tester.tap(
            find.byKey(const ValueKey('stock-movements-mode-product')),
          );
          await tester.pump();

          final state = tester.state<_StockMovementHarnessState>(
            find.byType(_StockMovementHarness),
          );
          state.productScrollController.jumpTo(320);
          await tester.pump();
          final previousOffset = state.productScrollController.offset;

          await tester.tap(
            find.byKey(const ValueKey('stock-product-action-7')),
          );
          await tester.pump();

          expect(
            find.byKey(
              const ValueKey('stock-movements-compact-product-detail'),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(
              const ValueKey('stock-movements-compact-product-list'),
            ),
            findsNothing,
          );
          expect(
            find.bySemanticsLabel('Volver a productos'),
            findsOneWidget,
          );
          expect(
            tester.getSize(
              find.byKey(const ValueKey('stock-movements-compact-back')),
            ),
            Size(size.width, 48),
          );

          await tester.tap(
            find.byKey(const ValueKey('stock-movements-compact-back')),
          );
          await tester.pump();

          expect(
            find.byKey(
              const ValueKey('stock-movements-compact-product-list'),
            ),
            findsOneWidget,
          );
          expect(
            state.productScrollController.offset,
            closeTo(previousOffset, 0.01),
          );
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  });

  group('StockMovementsResponsiveFrame desktop composition', () {
    for (final size in const <Size>[
      Size(900, 900),
      Size(1440, 900),
    ]) {
      testWidgets(
        '${size.width.toInt()} keeps the product split and desktop header',
        (tester) async {
          await _pumpHarness(
            tester,
            size: size,
            initialRecentMode: false,
          );

          expect(
            find.byKey(const ValueKey('stock-movements-compact-header')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('stock-movements-desktop-split')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('stock-desktop-header')),
            findsOneWidget,
          );
          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey('stock-product-list')),
                )
                .width,
            400,
          );
          expect(
            find.byKey(const ValueKey('stock-product-detail')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  testWidgets('compact reference is a named 48px action', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    const size = Size(384, 824);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 220,
                child: StockMovementCompactReferenceAction(
                  label: 'Factura FV-00905',
                  onTap: () => taps++,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final action = find.bySemanticsLabel('Abrir Factura FV-00905');
    expect(action, findsOneWidget);
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
    await tester.tap(action);
    expect(taps, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required Size size,
  bool initialRecentMode = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: const TextScaler.linear(1.3),
        ),
        child: Scaffold(
          body: _StockMovementHarness(
            initialRecentMode: initialRecentMode,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _StockMovementHarness extends StatefulWidget {
  const _StockMovementHarness({
    required this.initialRecentMode,
  });

  final bool initialRecentMode;

  @override
  State<_StockMovementHarness> createState() => _StockMovementHarnessState();
}

class _StockMovementHarnessState extends State<_StockMovementHarness> {
  late bool _isRecentMode;
  bool _hasSelectedProduct = false;
  final ScrollController productScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _isRecentMode = widget.initialRecentMode;
  }

  @override
  Widget build(BuildContext context) {
    return StockMovementsResponsiveFrame(
      isRecentMode: _isRecentMode,
      hasSelectedProduct: _hasSelectedProduct,
      desktopHeader: const SizedBox(
        key: ValueKey('stock-desktop-header'),
        height: 64,
        child: Text('Movimientos desktop'),
      ),
      recentBody: const SizedBox(
        key: ValueKey('stock-recent-body'),
        child: Text('Movimientos recientes'),
      ),
      productList: ListView.builder(
        key: const ValueKey('stock-product-list'),
        controller: productScrollController,
        itemExtent: 64,
        itemCount: 40,
        itemBuilder: (context, index) {
          return TextButton(
            key: ValueKey('stock-product-action-$index'),
            onPressed: () => setState(() => _hasSelectedProduct = true),
            child: Text('Producto $index'),
          );
        },
      ),
      productDetail: const SizedBox(
        key: ValueKey('stock-product-detail'),
        child: Center(child: Text('Historial del producto')),
      ),
      onSelectRecentMode: () {
        setState(() {
          _isRecentMode = true;
          _hasSelectedProduct = false;
        });
      },
      onSelectProductMode: () {
        setState(() {
          _isRecentMode = false;
          _hasSelectedProduct = false;
        });
      },
      onBackToProducts: () {
        setState(() => _hasSelectedProduct = false);
      },
      desktopProductListWidth: 400,
      onDesktopPanelResize: (_) {},
    );
  }

  @override
  void dispose() {
    productScrollController.dispose();
    super.dispose();
  }
}
