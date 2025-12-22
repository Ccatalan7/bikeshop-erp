import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/shared/services/barcode_scanner_service.dart';
import 'package:vinabike_erp/shared/widgets/scanner_bridge_scope.dart';
import 'package:vinabike_erp/shared/services/remote_scanner_service.dart';
import 'package:vinabike_erp/modules/settings/models/barcode_scan_event.dart';

// Mock Services
class MockBarcodeScannerService extends BarcodeScannerService {
  final List<String> scannedCodes = [];

  @override
  void processKeyEvent(RawKeyEvent event) {
    // Basic simulation of the service logic for testing
    if (event is RawKeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (scannedCodes.isNotEmpty) return; // simple buffer flush logic mock
        return;
      }
      // We mark that we processed a key
      scannedCodes.add(event.character ?? '');
    }
  }
}

class MockRemoteScannerService implements RemoteScannerService {
  @override
  Stream<BarcodeScanEvent> get scanStream => const Stream.empty();

  @override
  bool get isListening => false;

  @override
  Future<void> startListening() async {}

  @override
  Future<String> getDeviceId() async => "test-device";

  @override
  Future<void> resetDeviceId() async {}

  @override
  Future<void> sendScan(BarcodeScanEvent event, String targetDeviceId) async {}

  @override
  Future<void> stopListening() async {}

  @override
  void dispose() {}
}

void main() {
  testWidgets('ScannerBridgeScope ignores keys when TextField is focused',
      (WidgetTester tester) async {
    final barcodeService = MockBarcodeScannerService();
    // We need to inject the mock service.
    // Note: The real ScannerBridgeScope reads services from Provider.

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BarcodeScannerService>.value(
              value: barcodeService),
          Provider<RemoteScannerService>(
              create: (_) => MockRemoteScannerService()),
        ],
        child: MaterialApp(
          home: ScannerBridgeScope(
            child: Scaffold(
              body: Column(children: [
                const TextField(key: Key('input')),
                const Text('Outside'),
              ]),
            ),
          ),
        ),
      ),
    );

    // 1. Focus the text field
    await tester.tap(find.byKey(const Key('input')));
    await tester.pump();

    // 2. Simulate typing "a"
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();

    // 3. Verify MockService did NOT receive the key
    expect(barcodeService.scannedCodes, isEmpty,
        reason: 'Service should NOT receive keys when TextField is focused');

    // 4. Unfocus (tap outside) -> Wait, raw keyboard listener is global-ish in scope but
    // ScannerBridgeScope wraps the child.
    // Let's trying creating a focus node for a non-text widget
    final FocusNode buttonFocus = FocusNode();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<BarcodeScannerService>.value(
              value: barcodeService),
          Provider<RemoteScannerService>(
              create: (_) => MockRemoteScannerService()),
        ],
        child: MaterialApp(
          home: ScannerBridgeScope(
            child: Scaffold(
              body: Column(children: [
                const TextField(key: Key('input')),
                RawKeyboardListener(
                    focusNode: buttonFocus,
                    onKey: (_) {},
                    child: Container(
                        key: const Key('button'),
                        width: 50,
                        height: 50,
                        color: Colors.blue)),
              ]),
            ),
          ),
        ),
      ),
    );

    buttonFocus.requestFocus();
    await tester.pump();

    // 5. Simulate typing "b"
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();

    // 6. Verify MockService DID receive the key (since not editing text)
    // Note: In real app, we want it to receive keys when NOT editing text.
    // However, the test logic in ScannerBridgeScope is:
    // context.read<BarcodeScannerService>().processKeyEvent(event);
    // So if we bypassed the return, it should be called.

    // Actually, verifying the *Reverse* logic is harder without a specialized mock that records calls.
    // But the primary goal is determining if TextField keys are ignored.

    expect(barcodeService.scannedCodes.contains('b'), isTrue,
        reason: 'Service SHOULD receive keys when TextField is NOT focused');
  });
}
