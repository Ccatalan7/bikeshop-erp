import 'dart:async';

import 'package:test/test.dart';
import 'package:vinabike_storefront_html/storefront_html.dart';

void main() {
  test('reads take their turn in arrival order', () async {
    final gate = DatabaseGate(limit: 2);
    final started = <int>[];
    final finish = [for (var i = 0; i < 5; i++) Completer<void>()];
    final runs = [
      for (var i = 0; i < 5; i++)
        gate.run(() async {
          started.add(i);
          await finish[i].future;
          return i;
        }),
    ];
    await pumpEventQueue();
    expect(started, [0, 1]);
    expect(gate.running, 2);

    finish[1].complete();
    await pumpEventQueue();
    expect(started, [0, 1, 2]);

    for (final done in finish) {
      if (!done.isCompleted) done.complete();
    }
    expect(await Future.wait(runs), [0, 1, 2, 3, 4]);
    expect(gate.running, 0);
  });

  test('a read that fails gives its place to the next', () async {
    final gate = DatabaseGate(limit: 1);
    final failing = gate.run<int>(() async => throw StateError('500'));
    final next = gate.run(() async => 7);
    await expectLater(failing, throwsStateError);
    expect(await next, 7);
    expect(gate.running, 0);
  });

  test('a read that waits too long gives up and keeps no place', () async {
    final gate = DatabaseGate(
      limit: 1,
      maxWait: const Duration(milliseconds: 30),
    );
    final hold = Completer<void>();
    final holding = gate.run(() => hold.future);
    await expectLater(gate.run(() async => 1), throwsA(isA<DatabaseBusy>()));

    hold.complete();
    await holding;
    expect(gate.running, 0);
    // The place it never took is free for the next one.
    expect(await gate.run(() async => 2), 2);
    expect(gate.running, 0);
  });
}
