import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    testWidgets('enters text through the real editable pipeline',
        (tester) async {
      const prompt = 'Organiza mañana: cámaras 29 y garantías.';
      final controller = TextEditingController();
      final changes = <String>[];
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              key: const ValueKey<String>('agent-editable'),
              controller: controller,
              onChanged: changes.add,
            ),
          ),
        ),
      );

      final result = await enterTextAgentInputTargetForTesting(const {
        'key': 'agent-editable',
        'text': prompt,
      });
      await tester.pump();

      expect(result['ok'], isTrue);
      expect(controller.text, prompt);
      expect(
        controller.selection,
        const TextSelection.collapsed(offset: prompt.length),
      );
      expect(changes, [prompt]);
    });

    testWidgets('preserves input formatters and reports the actual value',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              key: const ValueKey<String>('digits-only'),
              controller: controller,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ),
        ),
      );

      final result = await enterTextAgentInputTargetForTesting(const {
        'key': 'digits-only',
        'text': 'PG-00490',
      });
      await tester.pump();

      expect(result['ok'], isTrue);
      expect(result['text'], '00490');
      expect(controller.text, '00490');
    });

    testWidgets('rejects readonly and non-editable targets without mutation',
        (tester) async {
      final controller = TextEditingController(text: 'original');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(
                  key: const ValueKey<String>('readonly'),
                  controller: controller,
                  readOnly: true,
                ),
                const SizedBox(
                  key: ValueKey<String>('not-editable'),
                  width: 40,
                  height: 40,
                ),
              ],
            ),
          ),
        ),
      );

      final readonly = await enterTextAgentInputTargetForTesting(const {
        'key': 'readonly',
        'text': 'changed',
      });
      final nonEditable = await enterTextAgentInputTargetForTesting(const {
        'key': 'not-editable',
        'text': 'changed',
      });

      expect(readonly['ok'], isFalse);
      expect(nonEditable['ok'], isFalse);
      expect(controller.text, 'original');
    });

    // 2026-10-13: `tap --label Cerrar` for a dialog that was already closed
    // hit «Cerrar Sesión» and signed the owner out of the debug app.
    testWidgets('a label taps only its whole text unless partial is asked',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(
                  onPressed: () {},
                  child: const Text('Cerrar Sesión'),
                ),
              ],
            ),
          ),
        ),
      );

      var dispatchedTaps = 0;
      Future<void> recordTap(Offset _) async {
        dispatchedTaps += 1;
      }

      expect(locateAgentInputTargetsForTesting(null, 'Cerrar'), isNotEmpty);
      final refused = await tapAgentInputTargetForTesting(
        const {'label': 'Cerrar'},
        tap: recordTap,
      );
      expect(refused['ok'], isFalse);
      expect(refused['error'].toString(), contains('Cerrar Sesión'));
      expect(dispatchedTaps, 0);

      final whole = await tapAgentInputTargetForTesting(
        const {'label': 'cerrar sesión'},
        tap: recordTap,
      );
      expect(whole['ok'], isTrue);
      expect(dispatchedTaps, 1);

      final partial = await tapAgentInputTargetForTesting(
        const {'label': 'Cerrar', 'partial': 'true'},
        tap: recordTap,
      );
      expect(partial['ok'], isTrue);
      expect(dispatchedTaps, 2);
    });

    testWidgets('the whole text wins over longer labels that contain it',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(onPressed: () {}, child: const Text('Cerrar')),
                FilledButton(
                  onPressed: () {},
                  child: const Text('Cerrar Sesión'),
                ),
              ],
            ),
          ),
        ),
      );

      Offset? tapped;
      final result = await tapAgentInputTargetForTesting(
        const {'label': 'Cerrar'},
        tap: (point) async => tapped = point,
      );
      expect(result['ok'], isTrue);
      expect(
        (result['tapped']! as Map<String, Object?>)['label'],
        'Cerrar',
      );
      expect(tapped, isNotNull);
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
