import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_person_avatar.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const identities = <(String, String)>[
    ('employee-1', 'E1'),
    ('employee-2', 'E2'),
    ('employee-3', 'E3'),
    ('employee-4', 'E4'),
  ];

  for (final preset in AppearancePresets.all) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${preset.code}/${brightness.name}: cuatro identidades conservan cuatro '
        'fills y tinta con contraste AA',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.resolve(
                preset: preset,
                brightness: brightness,
              ),
              home: Scaffold(
                body: Row(
                  children: <Widget>[
                    for (final identity in identities)
                      PayrollPersonAvatar(
                        key: ValueKey<String>('avatar-${identity.$1}'),
                        personId: identity.$1,
                        initials: identity.$2,
                      ),
                  ],
                ),
              ),
            ),
          );
          await tester.pump();

          final fills = <Color>{};
          for (final identity in identities) {
            final avatar = find.byKey(
              ValueKey<String>('avatar-${identity.$1}'),
            );
            final container = tester.widget<Container>(
              find.descendant(
                of: avatar,
                matching: find.byType(Container),
              ),
            );
            final text = tester.widget<Text>(
              find.descendant(of: avatar, matching: find.byType(Text)),
            );
            final decoration = container.decoration! as BoxDecoration;
            final fill = decoration.color!;
            final ink = text.style!.color!;
            fills.add(fill);

            expect(
              _contrastRatio(ink, fill),
              greaterThanOrEqualTo(4.5),
              reason:
                  '${identity.$1} debe conservar contraste AA sobre su fill '
                  'en ${preset.code}/${brightness.name}.',
            );
          }

          expect(
            fills,
            hasLength(identities.length),
            reason: 'Las cuatro identidades no pueden colapsar al mismo tono.',
          );
        },
      );
    }
  }
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter =
      firstLuminance >= secondLuminance ? firstLuminance : secondLuminance;
  final darker =
      firstLuminance < secondLuminance ? firstLuminance : secondLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
