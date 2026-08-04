import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/modules/settings/pages/appearance_settings_page.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';

// `Configuración → Apariencia` en compacto: las acciones del logo y el selector
// de tema.
//
// El defecto de las acciones se vio en la app real a 430 px: las tres iban en un
// `Row` fijo y la etiqueta de un `*Button.icon` es `Flexible`, así que en vez de
// quejarse el botón partía la palabra —«Cam/biar/Logo», «Elimi/nar»— en claro y
// en oscuro.
//
// Lo que se afirma acá es **la palabra**, no la geometría: una sola línea y sin
// truncar (`didExceedMaxLines == false`, que es lo único que distingue el texto
// completo del texto con puntos suspensivos), con el objetivo táctil de 48 y sin
// desbordes. Los anchos concretos que se cruzan salen de las métricas de la
// fuente de prueba, que no son las del dispositivo; por eso los casos de borde
// se justifican por la regla de reparto de `Expanded`, no por un número copiado
// de un teléfono.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  for (final width in <double>[390, 430]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'logo actions keep whole words at ${width.toInt()}px '
        '${brightness.name} with a custom logo',
        (tester) async {
          await _pumpAppearance(
            tester,
            width: width,
            brightness: brightness,
            hasCustomLogo: true,
          );

          _expectWholeWordActions(tester, viewportWidth: width);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'logo actions keep whole words at ${width.toInt()}px '
        '${brightness.name} without a custom logo',
        (tester) async {
          await _pumpAppearance(
            tester,
            width: width,
            brightness: brightness,
            hasCustomLogo: false,
          );

          _expectWholeWordAction(
            tester,
            key: const ValueKey('appearance-logo-upload'),
            label: 'Subir Logo',
            viewportWidth: width,
          );
          expect(
            find.byKey(const ValueKey('appearance-logo-refresh')),
            findsNothing,
            reason: 'Refrescar has no meaning without a logo.',
          );
          expect(
            find.byKey(const ValueKey('appearance-logo-remove')),
            findsNothing,
            reason: 'Eliminar has no meaning without a logo.',
          );

          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  // ---------------------------------------------------------------------
  // Selector de tema (`Claro` / `Oscuro` / `Sistema`)
  //
  // `SegmentedButton` da a cada segmento `maxWidth / 3` y su etiqueta va
  // `Flexible` sin `maxLines`: cuando no alcanza, **parte la palabra en
  // silencio** — «Sistem/a» a 390 px en el dispositivo, y a 430 no. No lanza
  // excepción ni desborda, así que `takeException` no lo delata: hay que mirar
  // el párrafo.
  //
  // La corrección es **quitar el icono del segmento**: es la única palanca de
  // ancho que existe. `ButtonStyleButton` recorta a cero toda densidad
  // horizontal negativa y `_SegmentButton` sobrescribe el `padding` del estilo
  // mientras el segmento tenga icono, así que con icono el chrome son 54 px
  // fijos por segmento y sin icono son 28 — 26 px de holgura, que es justo lo
  // que faltaba a 390 px.
  //
  // Aviso para quien lea esto en rojo: la fuente de los widget tests da un em
  // cuadrado por carácter, así que acá `Sistema` mide 98.7 px donde en Roboto 14
  // mide ~54. Con esas métricas el segmento no cabe hasta ~444 px de ventana:
  // afirmar «una línea a 390» acá sería falso para cualquier implementación
  // correcta. Por eso la matriz 390/430 afirma lo comprobable —ausencia de los
  // iconos, palabras, densidad no forzada, objetivos de 48, selección, límites,
  // cero excepciones—, el corte de línea se afirma al ancho donde esta
  // tipografía sí cabe, y la holgura ganada se mide contra la composición
  // anterior. Los 390 px reales los confirma el runtime, no esta prueba.
  // ---------------------------------------------------------------------

  for (final width in <double>[390, 430]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'theme mode selector keeps its three words, its contract and its '
        'selection at ${width.toInt()}px ${brightness.name}',
        (tester) async {
          final appearance = await _pumpAppearance(
            tester,
            width: width,
            brightness: brightness,
            hasCustomLogo: true,
          );

          final selectorFinder = find.byKey(_themeModeKey);
          expect(selectorFinder, findsOneWidget);

          final selector =
              tester.widget<SegmentedButton<ThemeMode>>(selectorFinder);
          expect(
            selector.showSelectedIcon,
            isFalse,
            reason: 'The canonical compact selector drops the check icon.',
          );
          expect(
            selector.style?.visualDensity,
            isNull,
            reason: 'Density belongs to the ThemeData: forcing compact here '
                'bought no width and pushed the touch target under 48.',
          );
          expect(
            selector.selected,
            {ThemeMode.light},
            reason: 'The service starts on the light theme.',
          );

          for (final word in _themeModeWords) {
            expect(
              find.descendant(of: selectorFinder, matching: find.text(word)),
              findsOneWidget,
              reason: '$word must keep its literal wording and its segment.',
            );
          }
          for (final icon in const [
            Icons.light_mode,
            Icons.dark_mode,
            Icons.settings_brightness,
            Icons.check,
          ]) {
            expect(
              find.descendant(of: selectorFinder, matching: find.byIcon(icon)),
              findsNothing,
              reason: 'A segment icon costs 26px of the width the word needs.',
            );
          }
          expect(
            find.descendant(
              of: selectorFinder,
              matching: find.byType(Icon),
            ),
            findsNothing,
            reason: 'The three words carry the meaning on their own.',
          );

          final rect = tester.getRect(selectorFinder);
          expect(rect.left, greaterThanOrEqualTo(-0.01));
          expect(
            rect.right,
            lessThanOrEqualTo(width + 0.01),
            reason: 'The selector must stay inside the viewport.',
          );
          expect(
            rect.height,
            greaterThanOrEqualTo(48),
            reason: 'The selector must keep the compact touch height.',
          );

          // Cada segmento se toca por su propio botón, no por el conjunto.
          final segments = find.descendant(
              of: selectorFinder, matching: find.byType(TextButton));
          expect(segments, findsNWidgets(3));
          for (var index = 0; index < 3; index++) {
            final segment = tester.getSize(segments.at(index));
            expect(
              segment.height,
              greaterThanOrEqualTo(48),
              reason: 'Segment $index must expose a 48px touch target.',
            );
            expect(
              segment.width,
              greaterThanOrEqualTo(48),
              reason: 'Segment $index must expose a 48px touch target.',
            );
          }

          await tester.tap(
            find.descendant(
              of: selectorFinder,
              matching: find.text('Sistema'),
            ),
          );
          await tester.pump();

          expect(
            appearance.themeMode,
            ThemeMode.system,
            reason: 'Tapping a segment must still change the ThemeMode.',
          );
          expect(
            tester
                .widget<SegmentedButton<ThemeMode>>(find.byKey(_themeModeKey))
                .selected,
            {ThemeMode.system},
            reason: 'The segment itself carries the visible selection.',
          );

          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  /// El corte de línea, al ancho donde la fuente **de esta prueba** cabe.
  /// A 390/430 reales lo cubre el runtime; acá se afirma que el selector no
  /// parte ninguna de las tres palabras en cuanto tiene el espacio que su
  /// propia tipografía pide.
  testWidgets(
    'the theme mode selector says its three words on one line once they fit',
    (tester) async {
      for (final brightness in Brightness.values) {
        // 500 px es lo primero que la fuente de esta prueba tolera: sin icono
        // cada segmento pide 126.7 px, o sea 380.1 de contenido, y a 500 hay
        // 436. Con icono pedía 458.1 y ni a 500 cabía.
        await _pumpAppearance(
          tester,
          width: 500,
          brightness: brightness,
          hasCustomLogo: true,
        );

        for (final word in _themeModeWords) {
          _expectWholeWordParagraph(
            tester,
            text: find.descendant(
              of: find.byKey(_themeModeKey),
              matching: find.text(word),
            ),
            label: word,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  /// La holgura que compró quitar el icono, medida contra la composición
  /// anterior y sin depender de la tipografía activa.
  ///
  /// Si alguien vuelve a poner `icon:` en los segmentos, este ancho vuelve a
  /// subir y la prueba cae. Es el guardián del arreglo, no un adorno.
  testWidgets(
    'dropping the segment icons makes the selector measurably narrower',
    (tester) async {
      await _pumpAppearance(
        tester,
        width: 1280,
        brightness: Brightness.light,
        hasCustomLogo: true,
      );
      final shippedSize = tester.getSize(find.byKey(_themeModeKey));

      final reference = _LogoAppearanceService(logoUrl: null);
      addTearDown(reference.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            preset: reference.appearancePreset,
            brightness: Brightness.light,
          ),
          home: const Scaffold(
            body: Center(child: _IconLabelledThemeModeSelector()),
          ),
        ),
      );
      await tester.pump();
      final previousSize =
          tester.getSize(find.byType(_IconLabelledThemeModeSelector));

      expect(
        shippedSize.width,
        lessThan(previousSize.width),
        reason: 'shipped=${shippedSize.width} previous=${previousSize.width} — '
            'the icon is the only width lever this control has.',
      );
      expect(
        (previousSize.width - shippedSize.width) / 3,
        greaterThanOrEqualTo(24),
        reason: 'Each segment must gain back real room for its word, not a '
            'rounding difference.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a compact width with a larger text scale still says the whole word',
    (tester) async {
      await _pumpAppearance(
        tester,
        width: 430,
        brightness: Brightness.dark,
        hasCustomLogo: true,
        textScaleFactor: 1.3,
      );

      _expectWholeWordActions(tester, viewportWidth: 430);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the three logo actions stay on one row when the width really fits them',
    (tester) async {
      await _pumpAppearance(
        tester,
        width: 1280,
        brightness: Brightness.light,
        hasCustomLogo: true,
      );

      expect(
        find.byKey(const ValueKey('appearance-logo-actions-row')),
        findsOneWidget,
        reason: 'A desktop width must not be stacked defensively.',
      );
      final upload = tester.getRect(
        find.byKey(const ValueKey('appearance-logo-upload')),
      );
      final remove = tester.getRect(
        find.byKey(const ValueKey('appearance-logo-remove')),
      );
      expect(upload.top, closeTo(remove.top, 0.01));
      expect(upload.width, closeTo(remove.width, 0.01));
      _expectWholeWordActions(tester, viewportWidth: 1280);
      expect(tester.takeException(), isNull);
    },
  );

  /// **Borde de la fila.** `Expanded` le da a `Cambiar Logo` y a `Eliminar` el
  /// mismo ancho, así que la fila no cabe cuando *suman*, sino cuando la más
  /// ancha de las dos cabe **dos veces**. Con la condición por suma este ancho
  /// elegía fila y `Cambiar Logo` salía con puntos suspensivos.
  testWidgets(
    'an intermediate width does not take the row and keeps Cambiar Logo whole',
    (tester) async {
      await _pumpAppearance(
        tester,
        width: 700,
        brightness: Brightness.light,
        hasCustomLogo: true,
      );

      _expectWholeWordActions(tester, viewportWidth: 700);
      expect(
        find.byKey(const ValueKey('appearance-logo-actions-row')),
        findsNothing,
        reason: 'The row only fits when the widest flexible action fits twice.',
      );
      expect(
        find.byKey(const ValueKey('appearance-logo-actions-split')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  /// **Borde del par.** Mismo razonamiento un escalón más abajo: `Refrescar` y
  /// `Eliminar` también se reparten por igual, así que el par no cabe cuando
  /// suman sino cuando la más ancha cabe dos veces.
  testWidgets(
    'a width that only fits the narrower pair member stacks instead',
    (tester) async {
      await _pumpAppearance(
        tester,
        width: 440,
        brightness: Brightness.dark,
        hasCustomLogo: true,
      );

      _expectWholeWordActions(tester, viewportWidth: 440);
      expect(
        find.byKey(const ValueKey('appearance-logo-actions-split')),
        findsNothing,
        reason: 'The pair only fits when the widest of the two fits twice.',
      );
      expect(
        find.byKey(const ValueKey('appearance-logo-actions-stack')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the split composition puts the pair side by side under the primary',
    (tester) async {
      await _pumpAppearance(
        tester,
        width: 500,
        brightness: Brightness.light,
        hasCustomLogo: true,
      );

      expect(
        find.byKey(const ValueKey('appearance-logo-actions-split')),
        findsOneWidget,
      );
      final upload = tester.getRect(
        find.byKey(const ValueKey('appearance-logo-upload')),
      );
      final refresh = tester.getRect(
        find.byKey(const ValueKey('appearance-logo-refresh')),
      );
      final remove = tester.getRect(
        find.byKey(const ValueKey('appearance-logo-remove')),
      );
      expect(
        refresh.top,
        greaterThanOrEqualTo(upload.bottom),
        reason: 'The primary action keeps its own row.',
      );
      expect(refresh.top, closeTo(remove.top, 0.01));
      _expectWholeWordActions(tester, viewportWidth: 500);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the stacked composition keeps the three actions full width',
    (tester) async {
      await _pumpAppearance(
        tester,
        width: 430,
        brightness: Brightness.dark,
        hasCustomLogo: true,
      );

      expect(
        find.byKey(const ValueKey('appearance-logo-actions-stack')),
        findsOneWidget,
      );
      final upload = tester.getRect(
        find.byKey(const ValueKey('appearance-logo-upload')),
      );
      final refresh = tester.getRect(
        find.byKey(const ValueKey('appearance-logo-refresh')),
      );
      final remove = tester.getRect(
        find.byKey(const ValueKey('appearance-logo-remove')),
      );
      expect(refresh.top, greaterThanOrEqualTo(upload.bottom));
      expect(remove.top, greaterThanOrEqualTo(refresh.bottom));
      expect(upload.width, closeTo(refresh.width, 0.01));
      expect(refresh.width, closeTo(remove.width, 0.01));
      expect(tester.takeException(), isNull);
    },
  );
}

const _themeModeKey = ValueKey('appearance-theme-mode');
const _themeModeWords = <String>['Claro', 'Oscuro', 'Sistema'];

Future<_LogoAppearanceService> _pumpAppearance(
  WidgetTester tester, {
  required double width,
  required Brightness brightness,
  required bool hasCustomLogo,
  double textScaleFactor = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final appearance = _LogoAppearanceService(
    logoUrl: hasCustomLogo ? 'asset:///test-logo.png' : null,
  );
  addTearDown(appearance.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<AppearanceService>.value(
      value: appearance,
      child: MaterialApp(
        theme: AppTheme.resolve(
          preset: appearance.appearancePreset,
          brightness: brightness,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScaleFactor),
          ),
          child: child!,
        ),
        home: const AppearanceSettingsPage(),
      ),
    ),
  );
  await tester.pump();
  return appearance;
}

void _expectWholeWordActions(
  WidgetTester tester, {
  required double viewportWidth,
}) {
  _expectWholeWordAction(
    tester,
    key: const ValueKey('appearance-logo-upload'),
    label: 'Cambiar Logo',
    viewportWidth: viewportWidth,
  );
  _expectWholeWordAction(
    tester,
    key: const ValueKey('appearance-logo-refresh'),
    label: 'Refrescar',
    viewportWidth: viewportWidth,
  );
  _expectWholeWordAction(
    tester,
    key: const ValueKey('appearance-logo-remove'),
    label: 'Eliminar',
    viewportWidth: viewportWidth,
  );
}

/// Afirma que la acción dice su palabra **completa**, en una línea, con el alto
/// táctil del canon y dentro del viewport.
///
/// `size.width` no sirve para «sin truncar»: en un `Expanded` es el ancho
/// asignado, y vale lo mismo con la palabra entera que con puntos suspensivos.
/// Lo que distingue una de otra es `didExceedMaxLines`.
void _expectWholeWordAction(
  WidgetTester tester, {
  required Key key,
  required String label,
  required double viewportWidth,
}) {
  final action = find.byKey(key);
  expect(action, findsOneWidget, reason: '$label must be present.');

  final rect = tester.getRect(action);
  expect(
    rect.height,
    greaterThanOrEqualTo(48),
    reason: '$label must expose a 48px touch target.',
  );
  expect(
    rect.left,
    greaterThanOrEqualTo(-0.01),
    reason: '$label must stay inside the viewport.',
  );
  expect(
    rect.right,
    lessThanOrEqualTo(viewportWidth + 0.01),
    reason: '$label must stay inside the viewport.',
  );

  _expectWholeWordParagraph(
    tester,
    text: find.descendant(of: action, matching: find.text(label)),
    label: label,
  );
}

/// Afirma que el párrafo de `label` se pinta **entero y en una línea**.
///
/// Las dos formas de romperse necesitan dos aserciones distintas: una etiqueta
/// con `maxLines: 1` se **trunca** y eso lo delata `didExceedMaxLines`; una sin
/// `maxLines` —como la de un `ButtonSegment`— se **parte en varias líneas** y
/// entonces `didExceedMaxLines` es siempre `false` y quien delata es el alto.
/// El ancho asignado no distingue ninguno de los dos casos por sí solo.
void _expectWholeWordParagraph(
  WidgetTester tester, {
  required Finder text,
  required String label,
}) {
  expect(text, findsOneWidget, reason: '$label must keep its literal wording.');
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final reference = TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
  )..layout();

  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$label must render whole, not ellipsised.',
  );
  expect(
    paragraph.size.height,
    lessThan(reference.height + 1),
    reason: '$label must render on a single line, not wrapped.',
  );
  expect(
    paragraph.size.width,
    greaterThanOrEqualTo(reference.width - 0.5),
    reason: '$label must be given the width its own word needs.',
  );
}

/// La composición **anterior** del selector de tema: idéntica a la que se
/// entrega salvo por el icono en cada segmento. Es la que partía «Sistem/a» a
/// 390 px.
///
/// No es una copia decorativa: es la referencia que hace medible, sea cual sea
/// la tipografía activa, cuánto ancho devuelve quitar el icono.
class _IconLabelledThemeModeSelector extends StatelessWidget {
  const _IconLabelledThemeModeSelector();

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
          value: ThemeMode.light,
          label: Text('Claro'),
          icon: Icon(Icons.light_mode),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          label: Text('Oscuro'),
          icon: Icon(Icons.dark_mode),
        ),
        ButtonSegment(
          value: ThemeMode.system,
          label: Text('Sistema'),
          icon: Icon(Icons.settings_brightness),
        ),
      ],
      selected: const {ThemeMode.light},
      onSelectionChanged: (_) {},
    );
  }
}

/// `hasCustomLogo` sólo se puede activar cargando ajustes de empresa reales, y
/// esta prueba no habla con la red: se fija el estado del logo por encima del
/// servicio, que es lo único que la pantalla consulta.
class _LogoAppearanceService extends AppearanceService {
  _LogoAppearanceService({required this.logoUrl});

  final String? logoUrl;

  @override
  String? get companyLogoUrl => logoUrl;

  @override
  bool get hasCustomLogo => logoUrl != null;
}
