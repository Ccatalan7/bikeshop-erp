import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/shared/models/notification_digest.dart';
import 'package:vinabike_erp/shared/widgets/notifications_panel.dart';

const _triggerKey = ValueKey<String>('notification-period-trigger');
const _popoverKey = ValueKey<String>('notification-date-range-popover');

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets(
    'custom calendar stays attached below the period trigger',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpPanel(tester, panelWidth: 500, panelHeight: 800);
      await _openCustomCalendar(tester);

      expect(tester.takeException(), isNull);
      final triggerRect = tester.getRect(find.byKey(_triggerKey));
      final popoverRect = tester.getRect(find.byKey(_popoverKey));

      expect(popoverRect.top, closeTo(triggerRect.bottom + 8, 0.5));
      final attachedToLeft = (popoverRect.left - triggerRect.left).abs() <= 0.5;
      final attachedToRight =
          (popoverRect.right - triggerRect.right).abs() <= 0.5;
      expect(attachedToLeft || attachedToRight, isTrue);
      expect(popoverRect.left, greaterThanOrEqualTo(12));
      expect(popoverRect.right, lessThanOrEqualTo(988));

      final previousMonthButton = find.byTooltip('Mes anterior');
      expect(previousMonthButton, findsOneWidget);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(previousMonthButton));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
    },
  );

  testWidgets(
    'custom calendar uses the transformed trigger bounds at 80 percent zoom',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(760, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpPanel(
        tester,
        panelWidth: 300,
        panelHeight: 700,
        scale: 0.8,
      );
      await _openCustomCalendar(tester);

      expect(tester.takeException(), isNull);
      final triggerRect = tester.getRect(find.byKey(_triggerKey));
      final popoverRect = tester.getRect(find.byKey(_popoverKey));

      expect(popoverRect.right, closeTo(triggerRect.right, 0.5));
      expect(popoverRect.left, greaterThanOrEqualTo(12));
      expect(popoverRect.right, lessThanOrEqualTo(748));
      expect(popoverRect.top, closeTo(triggerRect.bottom + 8, 0.5));
    },
  );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required double panelWidth,
  required double panelHeight,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ChatProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topRight,
              child: SizedBox(
                width: panelWidth,
                height: panelHeight,
                child: const NotificationsToolbarPanel(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _openCustomCalendar(WidgetTester tester) async {
  await tester.tap(find.byKey(_triggerKey));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(
    find.widgetWithText(
      PopupMenuItem<NotificationDigestPeriod>,
      'Personalizado…',
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
