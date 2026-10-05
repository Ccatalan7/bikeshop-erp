import 'dart:convert';

import 'package:test/test.dart';
import 'package:vinabike_public_core/public_store/models/public_business_hours.dart';

void main() {
  String places(List<(int, String, String)> periods) => jsonEncode({
    'periods': [
      for (final (day, open, close) in periods)
        {
          'open': {'day': day, 'time': open},
          'close': {'day': day, 'time': close},
        },
    ],
  });

  test('consecutive days with the same hours are one row', () {
    final rows = publicBusinessHourRows(
      places([
        for (var day = 1; day <= 5; day++) (day, '1030', '1900'),
        (6, '1030', '1530'),
      ]),
    );
    expect(rows, [
      (days: 'Lunes a Viernes', hours: '10:30 - 19:00', open: true),
      (days: 'Sábado', hours: '10:30 - 15:30', open: true),
      (days: 'Domingo', hours: 'Cerrado', open: false),
    ]);
  });

  test('every day alike is «Todos los días»; two spans are joined', () {
    expect(
      publicBusinessHourRows(
        places([
          for (var day = 0; day <= 6; day++) ...[
            (day, '0900', '1300'),
            (day, '1500', '1900'),
          ],
        ]),
      ),
      [
        (
          days: 'Todos los días',
          hours: '09:00 - 13:00 / 15:00 - 19:00',
          open: true,
        ),
      ],
    );
  });

  test('nothing readable lists nothing', () {
    expect(publicBusinessHourRows(''), isEmpty);
    expect(publicBusinessHourRows('no es json'), isEmpty);
  });
}
