import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/pages/mechanic_job_form_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BikeRecordSnapshot buildSnapshot() {
    final bike = Bike(
      id: 'bike-1',
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      brand: 'Polygon',
      model: 'Siskiu T8',
      color: 'Rojo vino',
      wheelSize: '27.5',
    );
    final profile = BikeProfile(
      id: 'profile-1',
      tenantId: 'tenant-1',
      bikeId: 'bike-1',
      summarySnapshot: const {
        'identityLine': 'Polygon Siskiu T8',
      },
      lastConfirmedAt: DateTime(2026, 7, 25),
    );

    return BikeRecordSnapshot(
      bike: bike,
      profile: profile,
      identityTitle: 'Polygon Siskiu T8',
      identitySubtitle: 'Rojo vino • Aro 27.5',
      intakeLines: const [
        'Uso principal: Trail',
      ],
      technicalLines: const [
        'Plataforma: MTB hardtail',
        'Suspension: Suspension delantera',
        'Frenos: Disco hidraulico',
        'Transmision: 1x12',
        'Valvula: Presta',
      ],
      notesLines: const [],
      warnings: const [
        'Falta confirmar tipo de freno',
        'Falta confirmar velocidad de transmision',
      ],
      lastConfirmedAt: DateTime(2026, 7, 25),
      hasStructuredProfile: true,
      isProfileComplete: false,
    );
  }

  Future<void> pumpContext(
    WidgetTester tester, {
    required double width,
    double textScale = 1.3,
    VoidCallback? onOpenProfile,
    VoidCallback? onEditProfile,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 824));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 824),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: MechanicJobBikeContextCard(
                  snapshot: buildSnapshot(),
                  isLoading: false,
                  loadFailed: false,
                  onRetry: () {},
                  onOpenProfile: onOpenProfile ?? () {},
                  onEditProfile: onEditProfile ?? () {},
                  editActionLabel: 'Editar ficha',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final width in [384.0, 599.0, 600.0, 899.0]) {
    testWidgets(
      'phone and tablet context stays compact and expands in place at $width',
      (tester) async {
        var openCount = 0;
        var editCount = 0;
        await pumpContext(
          tester,
          width: width,
          onOpenProfile: () => openCount += 1,
          onEditProfile: () => editCount += 1,
        );

        final card =
            find.byKey(const ValueKey('mechanic-job-bike-context-card'));
        final disclosure =
            find.byKey(const ValueKey('mechanic-job-bike-context-disclosure'));
        expect(card, findsOneWidget);
        expect(disclosure, findsOneWidget);
        expect(tester.getSize(disclosure).height, greaterThanOrEqualTo(48));
        expect(
          tester.getSize(card).height,
          lessThan(210),
          reason:
              'The collapsed bicycle context must leave the job workbench in '
              'the compact first read.',
        );
        expect(find.text('Polygon Siskiu T8'), findsOneWidget);
        expect(find.text('Falta confirmar tipo de freno'), findsOneWidget);
        expect(find.text('+1 pendiente'), findsOneWidget);
        expect(
          find.byKey(
            const ValueKey('mechanic-job-bike-context-highlight-text'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(
            const ValueKey('mechanic-job-bike-context-open-profile'),
          ),
          findsNothing,
        );

        var semantics = tester.widget<Semantics>(disclosure);
        expect(semantics.properties.button, isTrue);
        expect(semantics.properties.expanded, isFalse);
        expect(
          semantics.properties.label,
          contains('Ver contexto'),
        );
        expect(
          semantics.properties.label,
          contains('Falta confirmar tipo de freno'),
        );

        await tester.tap(disclosure);
        await tester.pump();

        expect(
          find.byKey(
            const ValueKey('mechanic-job-bike-context-highlight-text'),
          ),
          findsOneWidget,
        );
        expect(
          find.text('Falta confirmar velocidad de transmision'),
          findsOneWidget,
        );
        final openProfile = find.byKey(
          const ValueKey('mechanic-job-bike-context-open-profile'),
        );
        final editProfile = find.byKey(
          const ValueKey('mechanic-job-bike-context-edit-profile'),
        );
        expect(openProfile, findsOneWidget);
        expect(editProfile, findsOneWidget);
        expect(
          tester.getSize(openProfile).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getSize(editProfile).height,
          greaterThanOrEqualTo(48),
        );

        semantics = tester.widget<Semantics>(disclosure);
        expect(semantics.properties.expanded, isTrue);
        expect(semantics.properties.label, contains('Ocultar contexto'));

        await tester.ensureVisible(openProfile);
        await tester.tap(openProfile);
        await tester.pump();
        await tester.ensureVisible(editProfile);
        await tester.tap(editProfile);
        await tester.pump();
        expect(openCount, 1);
        expect(editCount, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [900.0, 1440.0]) {
    testWidgets(
      'desktop keeps the expanded context presentation at $width',
      (tester) async {
        await pumpContext(tester, width: width);

        expect(
          find.byKey(
            const ValueKey('mechanic-job-bike-context-disclosure'),
          ),
          findsNothing,
        );
        expect(find.text('Plataforma: MTB hardtail'), findsOneWidget);
        expect(find.text('Suspension: Suspension delantera'), findsOneWidget);
        expect(find.text('Frenos: Disco hidraulico'), findsOneWidget);
        expect(find.text('Transmision: 1x12'), findsOneWidget);
        expect(find.text('Valvula: Presta'), findsOneWidget);
        expect(find.text('Falta confirmar tipo de freno'), findsOneWidget);
        expect(find.text('Ver perfil completo'), findsNothing);
        expect(find.text('Editar ficha'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
