import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/dev/agent_input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('agent input target safety', () {
    testWidgets('ambiguous and invalid indexes dispatch zero taps',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                _TestButton(targetKey: 'duplicate'),
                _TestButton(targetKey: 'duplicate'),
              ],
            ),
          ),
        ),
      );

      final matches = locateAgentInputTargetsForTesting('duplicate', null);
      expect(matches, hasLength(2));

      var dispatchedTaps = 0;
      Future<void> recordTap(Offset _) async {
        dispatchedTaps += 1;
      }

      for (final index in <String?>[null, '', 'abc', '-1', '2']) {
        final params = <String, String>{'key': 'duplicate'};
        if (index != null) params['index'] = index;

        final result = await tapAgentInputTargetForTesting(
          params,
          tap: recordTap,
        );

        expect(result['ok'], isFalse, reason: 'index=$index');
        expect(dispatchedTaps, 0, reason: 'index=$index');
      }

      final result = await tapAgentInputTargetForTesting(
        const {'key': 'duplicate', 'index': '1'},
        tap: recordTap,
      );

      expect(result['ok'], isTrue);
      expect(dispatchedTaps, 1);
    });

    testWidgets('returns a visible enabled target', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: _TestButton(targetKey: 'visible')),
          ),
        ),
      );

      final matches = locateAgentInputTargetsForTesting('visible', null);

      expect(matches, hasLength(1));
      expect(matches.single['key'], 'visible');
      expect(matches.single['centerX'], isA<double>());
      expect(matches.single['centerY'], isA<double>());
    });

    testWidgets('rejects offstage targets', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Offstage(
              offstage: true,
              child: _TestButton(targetKey: 'offstage'),
            ),
          ),
        ),
      );

      expect(locateAgentInputTargetsForTesting('offstage', null), isEmpty);
    });

    testWidgets('rejects targets under IgnorePointer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IgnorePointer(
              child: Center(
                child: _TestButton(targetKey: 'ignored'),
              ),
            ),
          ),
        ),
      );

      expect(locateAgentInputTargetsForTesting('ignored', null), isEmpty);
    });

    testWidgets('rejects a target covered by another hit-test winner',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                const Center(
                  child: _TestButton(targetKey: 'covered'),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const SizedBox.expand(),
                ),
              ],
            ),
          ),
        ),
      );

      expect(locateAgentInputTargetsForTesting('covered', null), isEmpty);
    });

    testWidgets('rejects targets outside the logical viewport', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 5000,
                  top: 5000,
                  child: _TestButton(targetKey: 'outside'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(locateAgentInputTargetsForTesting('outside', null), isEmpty);
    });

    testWidgets('rejects disabled controls', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: _TestButton(
                targetKey: 'disabled',
                enabled: false,
              ),
            ),
          ),
        ),
      );

      expect(locateAgentInputTargetsForTesting('disabled', null), isEmpty);
    });
  });
}

class _TestButton extends StatelessWidget {
  const _TestButton({
    required this.targetKey,
    this.enabled = true,
  });

  final String targetKey;
  final bool enabled;

  @override
  Widget build(BuildContext context) => FilledButton(
        key: ValueKey<String>(targetKey),
        onPressed: enabled ? () {} : null,
        child: Text(targetKey),
      );
}
