import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **No verificado no es una alternativa, y no es cobertura.**
///
/// La categoría define el universo que hay que revisar; que una fila sobreviva
/// a él no la convierte en compatible. Con la necesidad real de pastillas
/// BR-MT200 la pantalla decía «49 alternativas internas elegibles» y ofrecía
/// `Elegir producto` sobre patines V-Brake y pastillas Avid: 47 de esas 49 no
/// tenían un solo criterio establecido.
Map<String, dynamic> _option(
  String id,
  String name, {
  required String matchState,
  required int atp,
  String coverage = 'full',
}) =>
    <String, dynamic>{
      'productId': id,
      'name': name,
      'atp': atp,
      'coverage': coverage,
      'matchState': matchState,
      'evidenceComplete': matchState == 'strong',
      'blocksExternal': false,
    };

SupplyStockResolution _resolution({
  required int eligible,
  required int reviewed,
  required int unverified,
  required String coverage,
  required List<Map<String, dynamic>> items,
  bool hasMore = false,
}) =>
    SupplyStockResolution.fromJson(<String, dynamic>{
      'needId': 'need-pastillas',
      'needVersion': 3,
      'revisionNo': 3,
      'quantity': 6,
      'unit': 'juego',
      'lane': 'family',
      'status': 'ok',
      'coverage': coverage,
      'blocksExternal': false,
      'items': items,
      'counts': <String, dynamic>{
        'eligible': eligible,
        'reviewed': reviewed,
        'unverified': unverified,
      },
      'page': <String, dynamic>{
        'limit': 20,
        'offset': 0,
        'total': hasMore ? reviewed : items.length,
        'returned': items.length,
        'hasMore': hasMore,
      },
    });

Future<void> _pump(
    WidgetTester tester, SupplyStockResolution resolution) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1455, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.resolve(
      preset: AppearancePresets.all.first,
      brightness: Brightness.light,
    ),
    home: Scaffold(
      body: FamilyStockOptions(
        resolution: resolution,
        busy: false,
        compact: false,
        onChooseProduct: (_) {},
        onCompareProviders: () {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('el título cuenta lo comprobado, no el universo revisado',
      (tester) async {
    await _pump(
      tester,
      _resolution(
        eligible: 2,
        reviewed: 49,
        unverified: 47,
        coverage: 'partial',
        items: <Map<String, dynamic>>[
          _option('a', 'PASTILLA SHIMANO ORGANICA',
              matchState: 'strong', atp: 6),
          _option('b', 'PASTILLA SHIMANO B01S',
              matchState: 'weak', atp: 2, coverage: 'partial'),
          _option('c', 'PATIN FRENO V-BRAKE', matchState: 'unverified', atp: 9),
        ],
      ),
    );
    expect(find.text('2 alternativas internas comprobadas'), findsOneWidget);
    expect(find.textContaining('49 alternativas'), findsNothing,
        reason: 'el universo de la categoría no son alternativas');
    expect(
      find.textContaining('Se revisaron 49 productos de la categoría y 47 '
          'quedaron sin verificar'),
      findsOneWidget,
      reason: 'lo revisado no se esconde: explica por qué hay tan pocas',
    );
  });

  testWidgets('una fila sin verificar se ve, pero no se puede elegir',
      (tester) async {
    await _pump(
      tester,
      _resolution(
        eligible: 1,
        reviewed: 3,
        unverified: 2,
        coverage: 'full',
        items: <Map<String, dynamic>>[
          _option('a', 'PASTILLA SHIMANO ORGANICA',
              matchState: 'strong', atp: 6),
          _option('c', 'PATIN FRENO V-BRAKE', matchState: 'unverified', atp: 9),
          _option('d', 'PASTILLA AVID METALICA',
              matchState: 'unverified', atp: 9),
        ],
      ),
    );
    // La comprobada conserva su acción.
    expect(
        find.byKey(const ValueKey('choose-stock-product-a')), findsOneWidget);
    // Las no verificadas siguen a la vista —el operador puede mirarlas—…
    expect(find.text('PATIN FRENO V-BRAKE'), findsOneWidget);
    expect(find.text('PASTILLA AVID METALICA'), findsOneWidget);
    // …pero sin el atajo que las declara compatibles.
    expect(find.byKey(const ValueKey('choose-stock-product-c')), findsNothing);
    expect(find.byKey(const ValueKey('choose-stock-product-d')), findsNothing);
    expect(
      find.byKey(const ValueKey('unverified-stock-note-c')),
      findsOneWidget,
      reason: 'y se dice por qué no se puede elegir',
    );
  });

  testWidgets('sin nada comprobado no se anuncian alternativas',
      (tester) async {
    await _pump(
      tester,
      _resolution(
        eligible: 0,
        reviewed: 12,
        unverified: 12,
        coverage: 'none',
        items: <Map<String, dynamic>>[
          _option('c', 'PATIN FRENO V-BRAKE', matchState: 'unverified', atp: 9),
        ],
      ),
    );
    expect(find.text('0 alternativas internas comprobadas'), findsOneWidget);
    expect(find.byKey(const ValueKey('choose-stock-product-c')), findsNothing);
  });

  testWidgets('un estado que nadie conoce no habilita elegir', (tester) async {
    // **La lista es positiva, igual que en el servidor.** Decidiendo por «no es
    // unverified», un estado futuro —el día que el servidor publique uno—
    // volvería a mostrar `Elegir producto` sobre algo que nadie comprobó: lo
    // desconocido caería del lado de lo permitido.
    await _pump(
      tester,
      _resolution(
        eligible: 1,
        reviewed: 2,
        unverified: 1,
        coverage: 'full',
        items: <Map<String, dynamic>>[
          _option('a', 'PASTILLA SHIMANO ORGANICA',
              matchState: 'strong', atp: 6),
          _option('z', 'PASTILLA ESTADO FUTURO',
              matchState: 'partially_established', atp: 9),
        ],
      ),
    );
    expect(
        find.byKey(const ValueKey('choose-stock-product-a')), findsOneWidget);
    expect(find.text('PASTILLA ESTADO FUTURO'), findsOneWidget,
        reason: 'sigue visible: no saber no es esconder');
    expect(find.byKey(const ValueKey('choose-stock-product-z')), findsNothing,
        reason: 'pero un estado desconocido no es una comprobación');
  });

  testWidgets('la banda dice el total del grupo, no lo que trajo la página',
      (tester) async {
    // Contando las filas recibidas, la banda decía 11 y pasaba a 22 al cargar
    // más sobre un grupo que en realidad tiene 47: el número crecía con el
    // scroll y no describía nada.
    await _pump(
      tester,
      _resolution(
        eligible: 2,
        reviewed: 49,
        unverified: 47,
        coverage: 'partial',
        items: <Map<String, dynamic>>[
          _option('a', 'PASTILLA SHIMANO ORGANICA',
              matchState: 'strong', atp: 6),
          _option('b', 'PASTILLA SHIMANO J04C',
              matchState: 'weak', atp: 0, coverage: 'none'),
          _option('c', 'PATIN FRENO V-BRAKE', matchState: 'unverified', atp: 9),
        ],
      ),
    );
    expect(
        find.text('POR CONFIRMAR CONTRA LOS CRITERIOS · 47'), findsOneWidget);
    expect(find.text('POR CONFIRMAR CONTRA LOS CRITERIOS · 1'), findsNothing,
        reason: 'no es cuántas llegaron en esta página');
  });

  testWidgets('el pie pagina productos revisados, no alternativas',
      (tester) async {
    await _pump(
      tester,
      _resolution(
        eligible: 2,
        reviewed: 49,
        unverified: 47,
        coverage: 'partial',
        hasMore: true,
        items: <Map<String, dynamic>>[
          _option('a', 'PASTILLA SHIMANO ORGANICA',
              matchState: 'strong', atp: 6),
          _option('c', 'PATIN FRENO V-BRAKE', matchState: 'unverified', atp: 9),
        ],
      ),
    );
    expect(find.textContaining('de 49 productos revisados'), findsOneWidget);
    expect(find.textContaining('alternativas en bodega'), findsNothing,
        reason: 'lo paginado es el conjunto entero, comprobado y no');
  });
}
