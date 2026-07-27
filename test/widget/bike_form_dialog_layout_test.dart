import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/bikeshop/pages/bike_form_dialog.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/shared/widgets/branded_loading.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets(
    'technical navigator yields map height when desktop preview is constrained',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 380,
                height: 500,
                child: Column(
                  children: [
                    SizedBox(height: 90),
                    SizedBox(height: 14),
                    BikeTechnicalNavigatorController(
                      fitControllerToAvailableHeight: true,
                      child: ColoredBox(
                        key: Key('technical-map'),
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 12),
                    // Models the extra wrapped metadata row that appears after
                    // the mechanic confirms a front brake type.
                    SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final mapSize = tester.getSize(find.byKey(const Key('technical-map')));
      expect(mapSize.height, lessThan(380));
      expect(mapSize.width, mapSize.height);
    },
  );

  testWidgets(
    'phone bike editor uses the available width without action overflow',
    (tester) async {
      tester.view.physicalSize = const Size(384, 824);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      final bike = Bike(
        id: 'bike-1',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        brandId: 'brand-1',
        modelId: 'model-1',
        brand: 'Polygon',
        model: 'Siskiu T8',
        wheelSize: '29"',
      );
      final service = _BikeFormLayoutService(bike);
      addTearDown(service.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<BikeshopService>.value(
          value: service,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: BikeFormDialog(
              customerId: bike.customerId,
              bike: bike,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surface = find.byKey(const ValueKey('bike-form-dialog-surface'));
      final actions = find.byKey(const ValueKey('bike-form-mobile-actions'));
      expect(surface, findsOneWidget);
      expect(actions, findsOneWidget);
      expect(
        tester.getSize(surface).width,
        greaterThanOrEqualTo(368),
      );
      expect(
        tester.getSize(actions).width,
        lessThanOrEqualTo(tester.getSize(surface).width),
      );

      final moreActions = find.byTooltip('Más acciones de bicicleta');
      final semanticMoreActions =
          find.bySemanticsLabel('Más acciones de bicicleta');
      final next = find.widgetWithText(FilledButton, 'Siguiente');
      final cancel = find.widgetWithText(TextButton, 'Cancelar');
      expect(moreActions, findsOneWidget);
      expect(semanticMoreActions, findsOneWidget);
      expect(next, findsOneWidget);
      expect(cancel, findsOneWidget);
      expect(tester.getSize(moreActions).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(next).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(cancel).height, greaterThanOrEqualTo(48));

      await tester.tap(moreActions);
      await tester.pumpAndSettle();
      expect(find.text('Guardar rápido'), findsOneWidget);
      expect(find.text('Eliminar bicicleta'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'delayed bike references keep field-sized semantic placeholders',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      for (final testCase in const <({Size viewport, double textScale})>[
        (viewport: Size(384, 824), textScale: 1.3),
        (viewport: Size(599, 900), textScale: 1.3),
        (viewport: Size(600, 900), textScale: 1.3),
        (viewport: Size(899, 900), textScale: 1.3),
        (viewport: Size(900, 900), textScale: 1.3),
        (viewport: Size(1440, 900), textScale: 1.3),
      ]) {
        final viewport = testCase.viewport;
        tester.view.physicalSize = viewport;
        final bike = Bike(
          id: 'bike-${viewport.width.toInt()}',
          tenantId: 'tenant-1',
          customerId: 'customer-1',
          brandId: 'brand-1',
          modelId: 'model-1',
          brand: 'Polygon',
          model: 'Siskiu T8',
          wheelSize: '29"',
        );
        final service = _DelayedBikeReferenceService(bike);

        await tester.pumpWidget(
          ChangeNotifierProvider<BikeshopService>.value(
            value: service,
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(testCase.textScale),
                ),
                child: child!,
              ),
              home: BikeFormDialog(
                customerId: bike.customerId,
              ),
            ),
          ),
        );
        await tester.pump();

        final brandLoading =
            find.byKey(const ValueKey('bike-brand-field-loading'));
        expect(
          brandLoading,
          findsOneWidget,
          reason: 'Brand loading must stay bounded at ${viewport.width}px.',
        );
        expect(
          find.bySemanticsLabel('Cargando marcas de bicicleta'),
          findsOneWidget,
        );
        expect(tester.getSize(brandLoading).height, 56);
        expect(find.byType(BrandedLoading), findsNothing);

        service.completeBrands();
        await tester.pumpAndSettle();

        final brandField = find.widgetWithText(TextFormField, 'Marca *');
        expect(brandField, findsOneWidget);
        await tester.enterText(brandField, 'Poly');
        await tester.pump();
        final brandOption = find.text('Polygon');
        expect(brandOption, findsOneWidget);
        await tester.tap(brandOption);
        await tester.pump();

        final modelLoading =
            find.byKey(const ValueKey('bike-model-field-loading'));
        expect(
          brandLoading,
          findsNothing,
          reason: 'The brand field must settle before model loading begins.',
        );
        expect(
          modelLoading,
          findsOneWidget,
          reason: 'Model loading must stay bounded at ${viewport.width}px.',
        );
        expect(
          find.bySemanticsLabel('Cargando modelos de bicicleta'),
          findsOneWidget,
        );
        expect(tester.getSize(modelLoading).height, 56);
        expect(find.byType(BrandedLoading), findsNothing);
        final delayedLayoutException = tester.takeException();
        expect(
          delayedLayoutException,
          isNull,
          reason: 'Delayed reference fields overflowed at ${viewport.width}px.',
        );

        service.completeModels();
        await tester.pumpAndSettle();
        expect(brandLoading, findsNothing);
        expect(modelLoading, findsNothing);
        expect(find.text('Polygon'), findsAtLeastNWidgets(1));
        expect(
          find.widgetWithText(TextFormField, 'Modelo *'),
          findsOneWidget,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Loaded reference fields overflowed at ${viewport.width}px.',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      }
      semantics.dispose();
    },
  );

  testWidgets(
    'section navigation recomposes at phone tablet and desktop boundaries',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();

      for (final viewport in const <Size>[
        Size(384, 824),
        Size(599, 900),
        Size(600, 900),
        Size(899, 900),
        Size(900, 900),
        Size(1440, 900),
      ]) {
        tester.view.physicalSize = viewport;
        final bike = Bike(
          id: 'bike-nav-${viewport.width.toInt()}',
          tenantId: 'tenant-1',
          customerId: 'customer-1',
          brandId: 'brand-1',
          modelId: 'model-1',
          brand: 'Polygon',
          model: 'Siskiu T8',
          wheelSize: '29"',
        );
        final service = _BikeFormLayoutService(bike);

        await tester.pumpWidget(
          ChangeNotifierProvider<BikeshopService>.value(
            value: service,
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.3),
                ),
                child: child!,
              ),
              home: BikeFormDialog(
                key: ValueKey('editor-${viewport.width}'),
                customerId: bike.customerId,
                bike: bike,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        if (viewport.width < 600) {
          final picker = find.byKey(const ValueKey('bike-form-step-picker'));
          expect(picker, findsOneWidget);
          expect(
            tester.getSize(picker).height,
            greaterThanOrEqualTo(56),
          );
          expect(
            find.byKey(const ValueKey('bike-form-step-tab-0')),
            findsNothing,
          );

          await tester.tap(picker);
          await tester.pumpAndSettle();
          for (var index = 0; index < 4; index++) {
            final option = find.byKey(ValueKey('bike-form-step-option-$index'));
            expect(option, findsOneWidget);
            expect(
              tester.getSize(option).height,
              greaterThanOrEqualTo(56),
            );
          }
          await tester.tap(
            find.byKey(const ValueKey('bike-form-step-option-2')),
          );
          await tester.pumpAndSettle();
        } else {
          expect(
            find.byKey(const ValueKey('bike-form-step-picker')),
            findsNothing,
          );
          for (var index = 0; index < 4; index++) {
            final tab = find.byKey(ValueKey('bike-form-step-tab-$index'));
            expect(tab, findsOneWidget);
            expect(
              tester.getSize(tab).height,
              greaterThanOrEqualTo(48),
            );
          }
          await tester.tap(
            find.byKey(const ValueKey('bike-form-step-tab-2')),
          );
          if (viewport.width < 900) {
            await tester.pumpAndSettle();
          } else {
            // The shared technical map has a deliberate repeating pulse.
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
          }
        }

        expect(
          find.text('Línea base técnica'),
          findsOneWidget,
          reason:
              'The technical section did not activate at ${viewport.width}px.',
        );
        if (viewport.width < 900) {
          final systemPicker =
              find.byKey(const ValueKey('bike-technical-system-picker'));
          final mapDisclosure =
              find.byKey(const ValueKey('bike-technical-map-disclosure'));
          expect(systemPicker, findsOneWidget);
          expect(mapDisclosure, findsOneWidget);
          expect(
            tester.getSize(systemPicker).height,
            greaterThanOrEqualTo(64),
          );
          expect(
            tester.getSize(mapDisclosure).height,
            greaterThanOrEqualTo(56),
          );
          expect(find.text('Mapa técnico'), findsNothing);
        } else {
          expect(
            find.byKey(const ValueKey('bike-technical-system-picker')),
            findsNothing,
          );
          expect(find.text('Mapa técnico'), findsOneWidget);
        }
        expect(
          tester.takeException(),
          isNull,
          reason:
              'Bike editor overflowed at ${viewport.width}x${viewport.height}.',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        service.dispose();
      }
      semantics.dispose();
    },
  );

  testWidgets(
    'embedded phone editor keeps an explicit return control on later sections',
    (tester) async {
      tester.view.physicalSize = const Size(384, 824);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bike = Bike(
        id: 'bike-inline-return',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        brandId: 'brand-1',
        modelId: 'model-1',
        brand: 'Polygon',
        model: 'Siskiu T8',
      );
      final service = _BikeFormLayoutService(bike);
      var cancelCalls = 0;
      addTearDown(service.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<BikeshopService>.value(
          value: service,
          child: MaterialApp(
            home: Scaffold(
              body: BikeFormDialog(
                customerId: bike.customerId,
                bike: bike,
                isEmbedded: true,
                onCanceled: () => cancelCalls++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('bike-form-step-picker')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('bike-form-step-option-2')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ficha Técnica'), findsWidgets);

      final exit = find.byKey(const ValueKey('bike-form-compact-exit'));
      expect(exit, findsOneWidget);
      expect(find.byTooltip('Volver a trabajos'), findsOneWidget);
      expect(tester.getSize(exit), const Size(48, 48));

      await tester.tap(exit);
      await tester.pump();
      expect(cancelCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop preview collapses an absent photo but preserves real media',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bikeWithoutPhoto = Bike(
        id: 'bike-without-photo',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        brandId: 'brand-1',
        modelId: 'model-1',
        brand: 'Polygon',
        model: 'Siskiu T8',
      );
      final emptyService = _BikeFormLayoutService(bikeWithoutPhoto);

      await tester.pumpWidget(
        ChangeNotifierProvider<BikeshopService>.value(
          value: emptyService,
          child: MaterialApp(
            home: BikeFormDialog(
              customerId: bikeWithoutPhoto.customerId,
              bike: bikeWithoutPhoto,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final emptyPreview =
          find.byKey(const ValueKey('bike-preview-empty-state'));
      expect(emptyPreview, findsOneWidget);
      expect(
        tester.getSize(emptyPreview).height,
        inInclusiveRange(148, 176),
      );
      expect(
        find.byKey(const ValueKey('bike-preview-media')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      emptyService.dispose();

      final bikeWithPhoto = Bike(
        id: 'bike-with-photo',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        brandId: 'brand-1',
        modelId: 'model-1',
        brand: 'Polygon',
        model: 'Siskiu T8',
        imageUrl: 'https://example.invalid/bike.jpg',
      );
      final mediaService = _BikeFormLayoutService(bikeWithPhoto);

      await tester.pumpWidget(
        ChangeNotifierProvider<BikeshopService>.value(
          value: mediaService,
          child: MaterialApp(
            home: BikeFormDialog(
              key: const ValueKey('bike-with-media-editor'),
              customerId: bikeWithPhoto.customerId,
              bike: bikeWithPhoto,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('bike-preview-media')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      mediaService.dispose();
    },
  );

  testWidgets(
    'catalog assistance is neutral and quick add uses a keyboard-safe sheet',
    (tester) async {
      tester.view.physicalSize = const Size(384, 824);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.view.viewInsets = FakeViewPadding.zero);

      const neutralSurface = Color(0xffeeeef1);
      const loudPrimaryContainer = Color(0xff8fc8ff);
      final colorScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xff403f46),
      ).copyWith(
        surfaceContainerLow: neutralSurface,
        primaryContainer: loudPrimaryContainer,
      );
      final bike = Bike(
        id: 'bike-catalog-sheet',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        brandId: 'brand-1',
        modelId: 'model-1',
        brand: 'Polygon',
        model: 'Siskiu T8',
      );
      final service = _BikeFormLayoutService(bike);
      addTearDown(service.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<BikeshopService>.value(
          value: service,
          child: MaterialApp(
            theme: ThemeData(colorScheme: colorScheme),
            home: BikeFormDialog(
              customerId: bike.customerId,
              bike: bike,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final catalog = find.byKey(const ValueKey('bike-catalog-assistance'));
      expect(catalog, findsOneWidget);
      expect(tester.widget<Material>(catalog).color, neutralSurface);
      expect(
        tester.widget<Material>(catalog).color,
        isNot(loudPrimaryContainer),
      );

      final addBrand = find.byTooltip('Agregar nueva marca');
      expect(addBrand, findsOneWidget);
      await tester.ensureVisible(addBrand);
      await tester.tap(addBrand);
      await tester.pumpAndSettle();

      final sheet = find.byKey(const ValueKey('bike-reference-name-sheet'));
      final createButton = find.descendant(
        of: sheet,
        matching: find.widgetWithText(FilledButton, 'Crear'),
      );
      expect(sheet, findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.byKey(const ValueKey('bike-reference-name-field')),
        findsOneWidget,
      );
      expect(createButton, findsOneWidget);
      expect(
        tester.getSize(createButton).height,
        greaterThanOrEqualTo(48),
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(
        tester.getBottomRight(createButton).dy,
        lessThanOrEqualTo(524),
      );
      expect(tester.takeException(), isNull);

      final cancelButton = find.descendant(
        of: sheet,
        matching: find.widgetWithText(TextButton, 'Cancelar'),
      );
      await tester.tap(cancelButton);
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
    },
  );
}

class _BikeFormLayoutService extends ChangeNotifier implements BikeshopService {
  _BikeFormLayoutService(this.bike);

  final Bike bike;

  @override
  Future<BikeAggregate> getBikeAggregate(String bikeId) async =>
      BikeAggregate(bike: bike, profile: null);

  @override
  Future<List<BikeBrand>> getBikeBrands({bool activeOnly = true}) async => [
        BikeBrand(
          id: 'brand-1',
          tenantId: bike.tenantId,
          name: 'Polygon',
        ),
      ];

  @override
  Future<BikeBrand?> getBikeBrandById(String id) async => BikeBrand(
        id: 'brand-1',
        tenantId: bike.tenantId,
        name: 'Polygon',
      );

  @override
  Future<List<BikeModel>> getBikeModels({
    String? brandId,
    bool activeOnly = true,
  }) async =>
      [
        BikeModel(
          id: 'model-1',
          tenantId: bike.tenantId,
          brandId: 'brand-1',
          name: 'Siskiu T8',
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedBikeReferenceService extends ChangeNotifier
    implements BikeshopService {
  _DelayedBikeReferenceService(this.bike);

  final Bike bike;
  final Completer<List<BikeBrand>> _brands = Completer<List<BikeBrand>>();
  final Completer<List<BikeModel>> _models = Completer<List<BikeModel>>();

  void completeBrands() {
    _brands.complete([
      BikeBrand(
        id: 'brand-1',
        tenantId: bike.tenantId,
        name: 'Polygon',
      ),
    ]);
  }

  void completeModels() {
    _models.complete([
      BikeModel(
        id: 'model-1',
        tenantId: bike.tenantId,
        brandId: 'brand-1',
        name: 'Siskiu T8',
      ),
    ]);
  }

  @override
  Future<BikeAggregate> getBikeAggregate(String bikeId) async =>
      BikeAggregate(bike: bike, profile: null);

  @override
  Future<List<BikeBrand>> getBikeBrands({bool activeOnly = true}) =>
      _brands.future;

  @override
  Future<BikeBrand?> getBikeBrandById(String id) async => null;

  @override
  Future<List<BikeModel>> getBikeModels({
    String? brandId,
    bool activeOnly = true,
  }) =>
      _models.future;

  @override
  Future<BikeModel?> getBikeModelById(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
