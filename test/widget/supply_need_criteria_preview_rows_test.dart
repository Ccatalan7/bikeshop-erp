import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/widgets/supply_need_refinement_editor.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **Cambiar un criterio es para ver los resultados, no un contador.**
///
/// La previsualización decía «de 27 revisadas quedarían 3» y no nombraba
/// ninguna: enterarse de *cuáles* obligaba a guardar, que es justo lo que esta
/// superficie existe para evitar. Las filas son las de la corrida real de RBX
/// del 2026-08-30 con `700c` + válvula Auto, donde «auto» es la válvula
/// —Schrader— y no el vehículo.

SpecTemplate _tubeTemplate() => SpecTemplate(
      id: 'tpl-tube',
      key: 'tube',
      name: 'Cámaras',
      technicalFamily: 'tube',
      fields: <SpecTemplateField>[
        for (final definition in const <List<String>>[
          <String>['wheel_size', 'Tamaño de rueda'],
          <String>['valve_type', 'Tipo de Válvula'],
        ])
          SpecTemplateField(
            specDefinitionId: 'def-${definition[0]}',
            sectionKey: 'general',
            sortOrder: 1,
            isRequired: false,
            visibilityRules: const <Map<String, dynamic>>[],
            definition: SpecDefinition(
              id: 'def-${definition[0]}',
              key: definition[0],
              label: definition[1],
              dataType: 'single_select',
              options: const <String>['700c', '650b'],
              sortOrder: 1,
            ),
          ),
      ],
    );

const List<SupplyNeedEditPreviewRow> _tres = <SupplyNeedEditPreviewRow>[
  SupplyNeedEditPreviewRow(
    supplierName: 'RBX',
    code: '14473',
    name: 'CAMARA 700 X 18/25C V/AUTO 60MM',
    isConfirmed: true,
    brand: 'RBX',
    priceNet: 2130,
  ),
  SupplyNeedEditPreviewRow(
    supplierName: 'RBX',
    code: '10663',
    name: 'CAMARA 700 X 28/38C V/AUTO 48MM (28-5/8-1/4)',
    isConfirmed: true,
    brand: 'RBX',
    priceNet: 1980,
  ),
  SupplyNeedEditPreviewRow(
    supplierName: 'RBX',
    code: '18335',
    name: 'CAMARA 700 X 38/45C V/AMERICANA 48MM (28-5/8-1/4)',
    isConfirmed: true,
    brand: 'RBX',
    priceNet: 2090,
  ),
];

List<SupplyNeedEditPreviewRow> _muchas(int count) => <SupplyNeedEditPreviewRow>[
      for (var index = 0; index < count; index += 1)
        SupplyNeedEditPreviewRow(
          supplierName: 'RBX',
          code: '90$index',
          name: 'CAMARA 700 X 18/25C V/FRANCESA ${index}MM',
          isConfirmed: index.isEven,
          priceNet: 2000 + index.toDouble(),
        ),
    ];

/// El editor arranca con `700c` guardado; la prueba agrega la válvula, que es
/// lo que hace `_predicatesChanged` verdadero y enciende la previsualización.
/// Cuántas veces se le pidió la previsualización al dueño del cálculo.
int _previewCalls = 0;

Widget _editor(List<SupplyNeedEditPreviewRow> rows) =>
    SupplyNeedRefinementEditor(
      template: _tubeTemplate(),
      title: 'Criterios de Cámaras 700',
      categoryLabel: 'cámaras',
      criteria: const SupplyNeedCriteria(
        predicates: <SupplyNeedPredicate>[
          SupplyNeedPredicate(
            field: 'wheel_size',
            operator: 'eq',
            values: <Object>['700c'],
          ),
        ],
        categoryId: 'cat-tubes',
        categoryPath: 'Componentes / Ruedas / Cámaras',
        revisionNo: 3,
        technicalFamily: 'tube',
      ),
      busy: false,
      onSave: (_) {},
      onCancel: () {},
      previewFor: (predicates) {
        _previewCalls += 1;
        return SupplyNeedEditPreview(
          reviewed: 27,
          confirmed: rows.where((row) => row.isConfirmed).length,
          unverified: rows.where((row) => !row.isConfirmed).length,
          rows: rows,
        );
      },
    );

/// El ancho que decide la composición es **el disponible**, no el del
/// dispositivo: el editor vive dentro del scroll de la superficie y puede
/// recibir menos espacio que la pantalla. Por eso se acota con un `SizedBox` y
/// la ventana se deja holgada — si se estrechara la ventana, lo que se estaría
/// probando sería el overlay del selector, no la tabla.
Future<void> _pump(
  WidgetTester tester,
  List<SupplyNeedEditPreviewRow> rows, {
  double width = 1200,
}) async {
  _previewCalls = 0;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(child: _editor(rows)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Enciende la previsualización cambiando el tipo de válvula.
Future<void> _elegirValvula(WidgetTester tester) async {
  await tester.tap(find.text('Sin especificar').last);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text('700c').last);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('sin cambios no se dibuja ninguna fila', (tester) async {
    await _pump(tester, _tres);
    expect(
      find.byKey(const ValueKey('need-criteria-preview-rows')),
      findsNothing,
    );
  });

  testWidgets('al cambiar un criterio se nombran los que quedarían',
      (tester) async {
    await _pump(tester, _tres);
    await _elegirValvula(tester);

    expect(
      find.byKey(const ValueKey('need-criteria-preview-rows')),
      findsOneWidget,
    );
    // Nombre, código y estado de cada uno: con eso se revisa sin guardar.
    for (final row in _tres) {
      expect(
        find.bySemanticsLabel(
          '${row.name} · ${row.code} · ${row.supplierName} · Cumple',
        ),
        findsOneWidget,
        reason: row.code,
      );
    }
    // Y el contador sigue describiendo esa misma lista.
    expect(find.textContaining('quedarían 3'), findsOneWidget);
  });

  testWidgets('lo que falta confirmar no se dibuja como si cumpliera',
      (tester) async {
    await _pump(tester, _muchas(2));
    await _elegirValvula(tester);
    expect(find.text('Cumple'), findsOneWidget);
    expect(find.text('Falta confirmar'), findsOneWidget);
  });

  testWidgets('una lista larga no empuja Guardar fuera: entra por divulgación',
      (tester) async {
    await _pump(tester, _muchas(20));
    await _elegirValvula(tester);

    expect(find.text('Ver las 12 restantes'), findsOneWidget);
    expect(find.textContaining('CAMARA 700 X 18/25C V/FRANCESA 0MM'),
        findsOneWidget);
    expect(find.textContaining('CAMARA 700 X 18/25C V/FRANCESA 19MM'),
        findsNothing);

    await tester.tap(find.text('Ver las 12 restantes'));
    await tester.pump();
    expect(find.text('Ver menos'), findsOneWidget);
  });

  testWidgets('el texto y las filas consumen UN solo cálculo por build',
      (tester) async {
    // **No basta prometerlo en un comentario.** La frase y la lista lo pedían
    // cada una por su cuenta a un getter, así que iban dos veces por frame y
    // nada impedía que devolvieran conjuntos distintos: es exactamente cómo un
    // contador termina describiendo otra lista.
    await _pump(tester, _muchas(20));
    await _elegirValvula(tester);

    // Un rebuild limpio y medido: la divulgación inline es un `setState` y
    // nada más.
    _previewCalls = 0;
    await tester.tap(find.text('Ver las 12 restantes'));
    await tester.pump();
    expect(_previewCalls, 1);
  });

  for (final host in const <List<Object>>[
    <Object>['escritorio', 1200.0],
    <Object>['tablet', 780.0],
    <Object>['teléfono', 380.0],
  ]) {
    testWidgets('sin desborde en ${host[0]}', (tester) async {
      await _pump(tester, _muchas(20), width: host[1] as double);
      await _elegirValvula(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('need-criteria-preview-rows')),
        findsOneWidget,
      );
      // Bajo el corte de teléfono la fila se apila: el encabezado de tabla no
      // existe, porque no tendría columnas que rotular.
      expect(
        find.text('Precio neto'),
        host[1] as double < 600 ? findsNothing : findsOneWidget,
      );
    });
  }
}
