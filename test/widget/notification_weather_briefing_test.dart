import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/shared/services/weather_forecast_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/notifications_panel.dart';
import 'package:vinabike_erp/shared/widgets/weather/briefing_weather_section.dart';

const _weatherTabKey = ValueKey<String>('notification-weather-tab');

/// A forecast of the hours around the real clock: the briefing reads the
/// device's own time, so a fixed fixture would be «no weather» on any other
/// day.
Map<String, dynamic> _document() {
  final now = DateTime.now().toUtc();
  final start = DateTime.utc(now.year, now.month, now.day, now.hour)
      .subtract(const Duration(hours: 1));
  return {
    'status': 'ok',
    'place': {
      'name': 'Viña del Mar',
      'latitude': -33.0252,
      'longitude': -71.5623,
    },
    'source': {
      'checked_at': now.toIso8601String(),
      'expires_at': now.add(const Duration(minutes: 30)).toIso8601String(),
      'credits': [
        {'name': 'MET Norway', 'url': 'https://www.met.no/en'},
      ],
    },
    'observation': null,
    'shop_place': {'name': 'Viña del Mar'},
    'places': <Object>[],
    'wind_trusted': true,
    'steps': [
      for (var hour = 0; hour < 96; hour++)
        {
          'time': start.add(Duration(hours: hour)).toIso8601String(),
          'span_minutes': hour < 95 ? 60 : 0,
          'temperature': 14.0 + (hour % 24) / 3,
          'wind_speed': 3.0,
          'wind_from_direction': 225,
          'humidity': 70,
          'symbol': 'fair_day',
          'precipitation': 0,
        },
    ],
  };
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets(
    'the weather lives on its own tab, beside the periods',
    (tester) async {
      var reads = 0;
      final previous = WeatherForecastService.debugReplaceInstance(
        WeatherForecastService(
          fetcher: () async {
            reads++;
            return _document();
          },
          currentUserId: () => 'employee-1',
        ),
      );
      addTearDown(() => WeatherForecastService.debugReplaceInstance(previous));
      await tester.binding.setSurfaceSize(const Size(520, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ChatProvider(),
          child: MaterialApp(
            // The section's controls read the app's theme roles.
            theme: AppTheme.resolve(
              preset: AppearancePresets.vinabike,
              brightness: Brightness.light,
            ),
            home: const Scaffold(
              body: SizedBox(
                width: 420,
                height: 1500,
                child: NotificationsToolbarPanel(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      // The summary no longer carries it.
      expect(find.text('Ahora en el local'), findsOneWidget);
      expect(find.byType(BriefingWeatherSection), findsNothing);
      expect(reads, 0, reason: 'nobody is looking at the weather yet');

      await tester.tap(find.byKey(_weatherTabKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(reads, 1);
      // The shop's own place is the first of the places, and the one shown.
      expect(find.text('Viña del Mar'), findsOneWidget);
      expect(find.byType(BriefingWeatherSection), findsOneWidget);
      expect(find.text('Ahora en el local'), findsNothing);
      // Today hour by hour first, then the days ahead, one line each.
      expect(find.textContaining('Próximas '), findsOneWidget);
      expect(find.text('Día'), findsOneWidget);
      expect(find.text('Mín. / máx.'), findsOneWidget);
      expect(find.text('Lluvia'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // A period brings the summary back.
      await tester.tap(find.text('Hoy'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Ahora en el local'), findsOneWidget);
      expect(find.byType(BriefingWeatherSection), findsNothing);
    },
  );
}
