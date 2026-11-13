import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/shared/services/weather_forecast_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/weather/briefing_weather_section.dart';
import 'package:vinabike_erp/shared/widgets/weather/weather_glyph.dart';
import 'package:vinabike_erp/shared/widgets/weather/weather_meteogram.dart';

/// What the `weather-forecast` function answered for Viña del Mar on
/// 2026-11-12 at 23:20 UTC (20:20 at the shop): 19° measured at the aerodrome
/// at 20:00, a clear sky and no rain ahead.
final _now = DateTime.utc(2026, 11, 12, 23, 20);

Map<String, dynamic> _document() => jsonDecode(
      File('test/fixtures/weather/shop_weather_vina_del_mar_20261112.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;

/// The same forecast with rain from 02:00 to 05:00 UTC.
Map<String, dynamic> _rainyDocument() {
  final document = _document();
  final steps = (document['steps'] as List).cast<Map<String, dynamic>>();
  for (final step in steps) {
    final hour = DateTime.parse(step['time'] as String);
    if (hour.isBefore(DateTime.utc(2026, 11, 13, 2)) ||
        !hour.isBefore(DateTime.utc(2026, 11, 13, 5))) {
      continue;
    }
    step['precipitation'] = 1.6;
    step['symbol'] = 'rain';
  }
  return document;
}

class _Weather {
  _Weather(this.answer);

  Object? Function() answer;
  String? userId = 'employee-1';
  DateTime now = _now;
  int reads = 0;

  late final WeatherForecastService service = WeatherForecastService(
    fetcher: () async {
      reads++;
      return answer();
    },
    currentUserId: () => userId,
    clock: () => now,
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Weather weather, {
  double width = 388,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  DateTime? now,
  VoidCallback? onOpenIntegrations,
  bool detailed = false,
  WeatherForecastService? service,
}) async {
  tester.view.physicalSize = const Size(900, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: brightness,
      ),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: SingleChildScrollView(
                  child: BriefingWeatherSection(
                    now: now ?? weather.now,
                    detailed: detailed,
                    service: service ?? weather.service,
                    onOpenIntegrations: onOpenIntegrations,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // The read and the stored preferences answer in microtasks.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

/// The section opens on days; these tests look at the hours.
void _preferHours() => SharedPreferences.setMockInitialValues(
      {'briefing_weather_view': 'hours'},
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('opens on the days ahead unless the person chose hours', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final weather = _Weather(_document);
    await _pump(tester, weather);
    expect(
        find.bySemanticsLabel(RegExp(r'^Próximos \d días\.')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Próximas 24 horas')), findsNothing);
    semantics.dispose();
  });

  testWidgets('shows what was measured, the day ahead and its sources', (
    tester,
  ) async {
    _preferHours();
    final semantics = tester.ensureSemantics();
    final weather = _Weather(_document);
    await _pump(tester, weather);

    expect(weather.reads, 1);
    expect(find.text('Clima en Viña del Mar'), findsOneWidget);
    expect(find.text('19°'), findsOneWidget);
    expect(find.text('Despejado'), findsOneWidget);
    // 19° felt as 19°: the felt temperature would say nothing new.
    expect(find.textContaining('Sensación'), findsNothing);
    expect(find.text('Medido a las 20:00'), findsOneWidget);
    // The aerodrome's wind, not the model's (which the function withheld).
    expect(find.text('NO 11 km/h'), findsOneWidget);
    expect(find.text('Humedad 73 %'), findsOneWidget);
    // The fixture's own forecast: a drizzle in the small hours of Sunday.
    expect(
      find.text('Lluvia desde el domingo a las 2:00 (cerca de 1 mm)'),
      findsOneWidget,
    );
    expect(find.byType(WeatherMeteogram), findsOneWidget);
    expect(find.text('MET Norway'), findsOneWidget);
    expect(find.text('NOAA Aviation Weather Center'), findsOneWidget);
    expect(find.textContaining('Sin actualizar'), findsNothing);

    expect(
      find.bySemanticsLabel(RegExp(r'^Ahora 19°, despejado, viento del ')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
          RegExp(r'^Próximas 24 horas: entre .* sin lluvia\.$')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('answers from hand on the next ticks of the briefing', (
    tester,
  ) async {
    final weather = _Weather(_document);
    await _pump(tester, weather);
    expect(weather.reads, 1);

    weather.now = _now.add(const Duration(minutes: 1));
    await _pump(tester, weather);
    weather.now = _now.add(const Duration(minutes: 2));
    await _pump(tester, weather);
    expect(weather.reads, 1, reason: 'the server said 23:49');

    weather.now = DateTime.utc(2026, 11, 12, 23, 50);
    await _pump(tester, weather);
    expect(weather.reads, 2);
  });

  testWidgets('days replace hours, and the choice is remembered', (
    tester,
  ) async {
    _preferHours();
    final semantics = tester.ensureSemantics();
    final weather = _Weather(_document);
    await _pump(tester, weather);

    await tester.tap(find.text('Días'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.bySemanticsLabel(RegExp(r'^Próximos \d días\. viernes: ')),
        findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Próximas 24 horas')), findsNothing);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('briefing_weather_view'), 'days');

    // A briefing opened later starts where this one was left.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, weather);
    expect(
        find.bySemanticsLabel(RegExp(r'^Próximos \d días\.')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('folded, it keeps the temperature in its heading', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final weather = _Weather(_document);
    await _pump(tester, weather);

    await tester.tap(find.bySemanticsLabel('Ocultar el detalle del clima'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(WeatherMeteogram), findsNothing);
    expect(find.text('Despejado'), findsNothing);
    expect(find.text('19°'), findsOneWidget);
    expect(find.byType(WeatherGlyph), findsOneWidget);
    expect(
      find.bySemanticsLabel('Mostrar el clima. Ahora 19°, despejado'),
      findsOneWidget,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('briefing_weather_collapsed'), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, weather);
    expect(find.byType(WeatherMeteogram), findsNothing);

    await tester.tap(
      find.bySemanticsLabel('Mostrar el clima. Ahora 19°, despejado'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(WeatherMeteogram), findsOneWidget);
    expect(preferences.getBool('briefing_weather_collapsed'), isFalse);
    semantics.dispose();
  });

  testWidgets('rain ahead leads the section and is drawn on its hours', (
    tester,
  ) async {
    _preferHours();
    final semantics = tester.ensureSemantics();
    final weather = _Weather(_rainyDocument);
    await _pump(tester, weather);

    expect(find.textContaining('Lluvia desde las 23:00'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Próximas 24 horas: .* lluvia, 5 mm\.$')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('touching an hour reads it out, and again lets it go', (
    tester,
  ) async {
    _preferHours();
    final weather = _Weather(_rainyDocument);
    await _pump(tester, weather);
    final chart = tester.getRect(find.byType(WeatherMeteogram));

    // 02:00 UTC is 23:00 at the shop, three hours after the first point.
    final hour = Offset(
      chart.left + 12 + (chart.width - 24) * 3 / 24,
      chart.center.dy,
    );
    await tester.tapAt(hour);
    await tester.pump();
    expect(
      find.textContaining(RegExp(r'^23:00 · \d+° · Lluvia · 1,6 mm')),
      findsOneWidget,
    );
    expect(find.text('MET Norway'), findsNothing);

    await tester.tapAt(hour);
    await tester.pump();
    expect(find.textContaining('1,6 mm'), findsNothing);
    expect(find.text('MET Norway'), findsOneWidget);
  });

  testWidgets('a shop without a place on the map is sent to connect it', (
    tester,
  ) async {
    final weather = _Weather(() => {'status': 'location_missing'});
    var opened = 0;
    await _pump(tester, weather, onOpenIntegrations: () => opened++);

    expect(find.text('Clima'), findsOneWidget);
    expect(find.textContaining('ficha de Google'), findsOneWidget);
    expect(find.byType(WeatherMeteogram), findsNothing);
    await tester.tap(find.text('Conectar ficha'));
    expect(opened, 1);
  });

  testWidgets('a first read that fails says so and can be asked again', (
    tester,
  ) async {
    final weather = _Weather(() => throw StateError('offline'));
    await _pump(tester, weather);

    expect(find.text('No se pudo cargar el clima.'), findsOneWidget);
    expect(find.byType(WeatherMeteogram), findsNothing);

    weather.answer = _document;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(weather.reads, 2);
    expect(find.text('19°'), findsOneWidget);
    expect(find.text('No se pudo cargar el clima.'), findsNothing);
  });

  testWidgets('a forecast that could not be renewed keeps showing, dated', (
    tester,
  ) async {
    final weather = _Weather(_document);
    await _pump(tester, weather);

    weather.answer = () => throw StateError('offline');
    weather.now = DateTime.utc(2026, 11, 12, 23, 55);
    await _pump(tester, weather);
    expect(weather.reads, 2);
    expect(find.byType(WeatherMeteogram), findsOneWidget);
    expect(
        find.textContaining('Sin actualizar desde las 20:19'), findsOneWidget);

    weather.answer = _document;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(weather.reads, 3);
    expect(find.textContaining('Sin actualizar'), findsNothing);
  });

  testWidgets('with nobody signed in it takes no room and asks nothing', (
    tester,
  ) async {
    final weather = _Weather(_document)..userId = null;
    await _pump(tester, weather);

    expect(weather.reads, 0);
    expect(tester.getSize(find.byType(BriefingWeatherSection)).height, 0);
  });

  group('layout', () {
    for (final width in <double>[240, 288, 328, 348, 388, 568]) {
      for (final scale in <double>[1, 1.3]) {
        testWidgets('fits ${width.round()} px at text scale $scale', (
          tester,
        ) async {
          _preferHours();
          final weather = _Weather(_rainyDocument);
          await _pump(tester, weather, width: width, textScale: scale);
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('Días'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byType(WeatherMeteogram)).width,
            width,
          );
        });
      }
    }
  });

  testWidgets('a person adds a place, sees it on its own clock and removes it',
      (
    tester,
  ) async {
    final calls = <Map<String, dynamic>>[];
    var places = <Map<String, dynamic>>[];
    const seattle = {
      'id': 'place-1',
      'name': 'Seattle',
      'region': 'Washington, United States',
      'latitude': 47.6038,
      'longitude': -122.3301,
      'time_zone': 'America/Los_Angeles',
    };
    final service = WeatherForecastService(
      currentUserId: () => 'employee-1',
      clock: () => _now,
      invoke: (body) async {
        calls.add(body);
        final extras = {
          'places': places,
          'shop_place': {'name': 'Viña del Mar'},
        };
        switch (body['action']) {
          case 'search':
            return {
              'status': 'ok',
              'matches': [seattle],
            };
          case 'add_place':
            places = [seattle];
            return {
              'status': 'ok',
              'place': seattle,
              ...extras,
              'places': places
            };
          case 'remove_place':
            places = [];
            return {'status': 'ok', 'places': places};
        }
        final document = _document();
        if (body['place_id'] == 'place-1') {
          document['place'] = {
            ...seattle,
            'offsets': [
              {'from': '2026-11-12T00:00:00.000Z', 'minutes': -480},
            ],
          };
        }
        return {...document, ...extras};
      },
    );
    await _pump(tester, _Weather(_document), detailed: true, service: service);

    // The shop's own place is the first tab, and the one on screen.
    expect(find.text('Viña del Mar'), findsOneWidget);
    expect(find.textContaining('Hora local'), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('weather-place-add')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('weather-place-query')),
      'Seattle',
    );
    // Nothing is asked while the person types.
    expect(calls.where((call) => call['action'] == 'search'), isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Washington, United States'), findsOneWidget);

    await tester.tap(find.textContaining('Washington, United States'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 23:20 UTC is 15:20 in Seattle: every hour is read on its clock.
    expect(find.textContaining('Hora local 15:20'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('weather-place-query')),
        findsNothing);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('briefing_weather_place'), 'place-1');
    expect(
      calls.last,
      {'action': 'forecast', 'place_id': 'place-1'},
    );

    await tester.tap(find.byTooltip('Quitar Seattle'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Seattle'), findsNothing);
    expect(find.textContaining('Hora local'), findsNothing);
    expect(preferences.getString('briefing_weather_place'), isNull);
    expect(tester.takeException(), isNull);
  });

  group('on its own tab', () {
    testWidgets('lists every hour under the chart and cannot be folded', (
      tester,
    ) async {
      _preferHours();
      final semantics = tester.ensureSemantics();
      final weather = _Weather(_rainyDocument);
      await _pump(tester, weather, detailed: true);

      expect(
          find.bySemanticsLabel('Ocultar el detalle del clima'), findsNothing);
      expect(find.text('Hora'), findsOneWidget);
      // 02:00 UTC is 23:00 at the shop: the first of three wet hours.
      expect(
        find.bySemanticsLabel(
            RegExp(r'^A las 23:00, \d+°, lluvia, lluvia, 2 mm')),
        findsOneWidget,
      );
      expect(find.text('1,6 mm'), findsNWidgets(3));
      // The model's wind was withheld for this evening: no column, and why.
      expect(find.text('Viento'), findsNothing);
      expect(find.textContaining('El viento por hora no se muestra'),
          findsOneWidget);

      await tester.tap(find.text('Días'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Día'), findsOneWidget);
      expect(find.text('Mín. / máx.'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^viernes 13, ')), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    for (final width in <double>[240, 328, 388]) {
      testWidgets('fits ${width.round()} px with its tables', (tester) async {
        _preferHours();
        final weather = _Weather(_rainyDocument);
        await _pump(tester, weather, width: width, detailed: true);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Días'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.takeException(), isNull);
      });
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('draws with the theme\'s own tones in ${brightness.name}', (
      tester,
    ) async {
      final weather = _Weather(_rainyDocument);
      await _pump(tester, weather, brightness: brightness);
      expect(tester.takeException(), isNull);

      final context = tester.element(find.byType(WeatherMeteogram));
      final tones = WeatherGlyphColors.of(context);
      final scheme = Theme.of(context).colorScheme;
      // Each tone is told apart from the surface it is drawn on.
      for (final tone in [tones.sun, tones.cloud, tones.water]) {
        expect(_contrast(tone, scheme.surface), greaterThanOrEqualTo(3));
      }
    });
  }
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}
