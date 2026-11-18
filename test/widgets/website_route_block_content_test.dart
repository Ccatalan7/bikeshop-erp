import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/website_route_block_content.dart';

/// The «Ruta» block in the editor's canvas (2026-11-17), which the HTML
/// storefront draws the same (`website_route_view.dart`): the reader picks
/// where they leave from and every figure beside the map follows the way
/// picked; a block without a route says what it needs only in the editor.

const _primary = Color(0xFF123F68);
const _accent = Color(0xFFFF6F00);

Map<String, dynamic> _route() => {
      'map_image': 'https://cdn.example/mapa.svg',
      'map_west': -71.995,
      'map_north': -32.975,
      'map_east': -71.345,
      'map_south': -33.3,
      'map_credit': '© colaboradores de OpenStreetMap',
      'destination': 'Santuario',
      'profile_title': 'El perfil',
      'routes': [
        {
          'label': 'Desde Viña',
          'start': 'Plaza Sucre',
          'track': '-33.0250, -71.5522\n-33.1000, -71.5200\n'
              '-33.2580, -71.4382',
          'profile': '0, 17\n5, 300\n6, 297\n10, 350\n12, 340\n'
              '28.14, 416\n36.18, 291',
          'points': '12,8 | Ruta 68 | Entras por Las Palmas.\n'
              '36,2 | Santuario | Km 78,8 de la Ruta 68.',
        },
        {
          'label': 'Desde Valparaíso',
          'start': 'Plaza Sotomayor',
          'track': '-33.0400, -71.6200\n-33.2580, -71.4382',
          'profile': '0, 10\n35.3, 291',
        },
      ],
    };

Future<void> _pump(
  WidgetTester tester,
  Map<String, dynamic> data, {
  double width = 1440,
  bool showEmptyHint = false,
  bool interactive = true,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width, 3200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteRouteBlockContent(
            data: data,
            primaryColor: _primary,
            accentColor: _accent,
            showEmptyHint: showEmptyHint,
            interactive: interactive,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the facts beside the map follow the way the reader picks',
      (tester) async {
    await _pump(tester, _route());

    expect(find.text('Desde dónde sales'), findsOneWidget);
    expect(find.text('Plaza Sucre'), findsOneWidget);
    expect(find.text('36,2 km'), findsOneWidget);
    expect(find.text('≈410 m'), findsOneWidget);
    expect(find.text('416 m, en el km 28,1'), findsOneWidget);
    expect(find.text('RUTA 68'), findsOneWidget);

    await tester.tap(find.text('Desde Valparaíso'));
    await tester.pump();

    expect(find.text('Plaza Sotomayor'), findsOneWidget);
    expect(find.text('35,3 km'), findsOneWidget);
    expect(find.text('36,2 km'), findsNothing);
    // That way names no points: its list is gone with it.
    expect(find.text('RUTA 68'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a column beside the map on a desktop, one under the other on '
      'a phone', (tester) async {
    await _pump(tester, _route());
    final pickDesktop = tester.getTopLeft(find.text('Desde dónde sales'));
    final creditDesktop = tester.getTopLeft(
      find.text('© colaboradores de OpenStreetMap'),
    );
    expect(creditDesktop.dx, greaterThan(720));
    expect(pickDesktop.dx, lessThan(720));
    expect(
      find.text(
        'Pasa el mouse sobre el perfil para ver la altura en cada kilómetro.',
      ),
      findsOneWidget,
    );

    await _pump(tester, _route(), width: 390);
    final pick = tester.getBottomLeft(find.text('Desde dónde sales'));
    final credit = tester.getTopLeft(
      find.text('© colaboradores de OpenStreetMap'),
    );
    expect(credit.dy, greaterThan(pick.dy));
    expect(
      find.text('Toca el perfil para ver la altura en cada kilómetro.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'in Edit the block is inert: a click selects it, never picks a '
      'way', (tester) async {
    await _pump(tester, _route(), interactive: false);

    await tester.tap(find.text('Desde Valparaíso'), warnIfMissed: false);
    await tester.pump();

    expect(find.text('36,2 km'), findsOneWidget);
    expect(find.text('35,3 km'), findsNothing);
  });

  testWidgets('a block without a route says what it needs only in the editor',
      (tester) async {
    await _pump(tester, {'routes': []}, showEmptyHint: true);
    expect(
      find.textContaining('Escribe en el panel el trazado y el perfil'),
      findsOneWidget,
    );

    await _pump(tester, {'routes': []});
    expect(
      find.textContaining('Escribe en el panel el trazado y el perfil'),
      findsNothing,
    );
  });
}
