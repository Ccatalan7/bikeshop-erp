import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/workshop_status_filter_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shows a touch-safe exclusion toggle only for selected statuses',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      for (final width in <double>[384, 599, 600, 899, 900, 1440]) {
        await _pumpHeader(tester, width: width, canClear: true);

        final operator = find.byKey(WorkshopStatusFilterHeader.operatorKey);
        final clear = find.byKey(WorkshopStatusFilterHeader.clearKey);

        expect(operator, findsOneWidget);
        expect(clear, findsOneWidget);
        expect(find.text('Es'), findsNothing);
        expect(find.text('No es'), findsNothing);
        expect(find.text('Excluir los estados elegidos'), findsOneWidget);
        expect(
          tester.getSize(operator).height,
          greaterThanOrEqualTo(48),
          reason: '$width px must preserve the operator touch target',
        );
        expect(
          tester.getSize(clear).height,
          greaterThanOrEqualTo(48),
          reason: '$width px must preserve the clear touch target',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '$width px must not overflow',
        );
      }

      await _pumpHeader(tester, width: 384);
      expect(
        find.byKey(WorkshopStatusFilterHeader.operatorKey),
        findsNothing,
      );
    },
  );

  testWidgets(
    'uses the caller-owned include/exclude value and preserves it on rebuild',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(384, 824);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final excludeMode = ValueNotifier<bool>(false);
      addTearDown(excludeMode.dispose);
      final changes = <bool>[];

      await _pumpHeader(
        tester,
        width: 384,
        textScale: 1.3,
        excludeMode: excludeMode,
        canClear: true,
        onChanged: (value) {
          changes.add(value);
          excludeMode.value = value;
        },
      );

      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('Excluir los estados elegidos')),
        findsOneWidget,
      );
      semantics.dispose();

      await tester.tap(
        find.byKey(WorkshopStatusFilterHeader.operatorKey),
      );
      await tester.pump();

      expect(changes, [true]);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(WorkshopStatusFilterHeader.operatorKey),
            )
            .value,
        isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpHeader(
        tester,
        width: 384,
        textScale: 1.3,
        excludeMode: excludeMode,
        canClear: true,
        onChanged: (value) {
          changes.add(value);
          excludeMode.value = value;
        },
      );

      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(WorkshopStatusFilterHeader.operatorKey),
            )
            .value,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clears selected statuses through the caller-owned command',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    var clearRequests = 0;

    await _pumpHeader(
      tester,
      width: 384,
      canClear: true,
      onClear: () => clearRequests += 1,
    );
    await tester.tap(find.byKey(WorkshopStatusFilterHeader.clearKey));
    await tester.pump();

    expect(clearRequests, 1);
  });

  testWidgets(
    'fits the real desktop popover content width at large text scale',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await _pumpHeader(
        tester,
        width: 1440,
        contentWidth: 296,
        textScale: 2,
        canClear: true,
      );

      final operator = find.byKey(WorkshopStatusFilterHeader.operatorKey);
      final clear = find.byKey(WorkshopStatusFilterHeader.clearKey);
      expect(tester.getSize(operator).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(clear).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpHeader(
  WidgetTester tester, {
  required double width,
  double? contentWidth,
  double textScale = 1.3,
  ValueNotifier<bool>? excludeMode,
  ValueChanged<bool>? onChanged,
  bool canClear = false,
  VoidCallback? onClear,
}) async {
  tester.view.physicalSize = Size(width, 824);
  final owner = excludeMode ?? ValueNotifier<bool>(false);
  final ownsNotifier = excludeMode == null;

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: contentWidth,
              child: ValueListenableBuilder<bool>(
                valueListenable: owner,
                builder: (context, value, _) {
                  return WorkshopStatusFilterHeader(
                    excludeMode: value,
                    canClear: canClear,
                    onExcludeModeChanged: onChanged ??
                        (next) {
                          owner.value = next;
                        },
                    onClear: onClear ?? () {},
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  if (ownsNotifier) {
    addTearDown(owner.dispose);
  }
}
