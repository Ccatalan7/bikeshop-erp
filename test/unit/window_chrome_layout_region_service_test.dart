import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/shared/services/window_chrome_layout_region_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    WindowChromeLayoutRegionService.channelName,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('initial read and newer callbacks publish validated geometry', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(
        call.method,
        WindowChromeLayoutRegionService.getCurrentMetricsMethod,
      );
      return <String, Object>{
        'width': 451.0,
        'height': 958.0,
        'left': 0.0,
        'right': 0.0,
        'revision': 1,
      };
    });
    final service = WindowChromeLayoutRegionService(
      channel: channel,
      supportedOverride: true,
    );
    addTearDown(service.dispose);
    var notifications = 0;
    service.addListener(() => notifications++);

    await service.start();
    expect(service.snapshot.viewSize, const Size(451, 958));
    expect(service.snapshot.margins, EdgeInsets.zero);
    expect(notifications, 1);

    await service.handlePlatformCall(
      const MethodCall(
        WindowChromeLayoutRegionService.metricsChangedMethod,
        <String, Object>{
          'width': 451.0,
          'height': 958.0,
          'left': 80.0,
          'right': 12.0,
          'revision': 2,
        },
      ),
    );
    expect(
      service.snapshot.margins,
      const EdgeInsets.only(left: 80, right: 12),
    );
    expect(notifications, 2);

    // A delayed native callback cannot rewind a resized window.
    await service.handlePlatformCall(
      const MethodCall(
        WindowChromeLayoutRegionService.metricsChangedMethod,
        <String, Object>{
          'width': 451.0,
          'height': 958.0,
          'left': 4.0,
          'right': 4.0,
          'revision': 1,
        },
      ),
    );
    expect(service.snapshot.revision, 2);
    expect(notifications, 2);
  });

  test('invalid payloads and a missing native host fail closed', () async {
    final missing = WindowChromeLayoutRegionService(
      channel: channel,
      supportedOverride: true,
    );
    addTearDown(missing.dispose);
    await missing.start();
    expect(missing.snapshot, WindowChromeLayoutSnapshot.zero);

    expect(
      WindowChromeLayoutSnapshot.tryParse(<String, Object>{
        'width': 451.0,
        'height': 958.0,
        'left': -1.0,
        'right': 0.0,
        'revision': 1,
      }),
      isNull,
    );
    expect(
      WindowChromeLayoutSnapshot.tryParse(<String, Object>{
        'width': double.nan,
        'height': 958.0,
        'left': 0.0,
        'right': 0.0,
        'revision': 1,
      }),
      isNull,
    );
  });
}
