import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/utils/message_receipt_refresh_coalescer.dart';

void main() {
  test('coalesces duplicate receipt events into one targeted batch', () async {
    final batches = <MessageReceiptRefreshBatch>[];
    final coalescer = MessageReceiptRefreshCoalescer(
      delay: const Duration(milliseconds: 15),
      onRefresh: (batch) async => batches.add(batch),
    );

    coalescer.schedule(conversationId: 'c1', messageId: 'm1');
    coalescer.schedule(conversationId: 'c1', messageId: 'm1');
    coalescer.schedule(conversationId: 'c1', messageId: 'm2');
    coalescer.schedule(conversationId: 'c2', messageId: 'm3');

    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(batches, hasLength(1));
    expect(batches.single.keys, containsAll(['c1', 'c2']));
    expect(batches.single['c1'], {'m1', 'm2'});
    expect(batches.single['c2'], {'m3'});
    coalescer.dispose();
  });

  test('retains receipt events arriving while a refresh is in flight',
      () async {
    final firstRefresh = Completer<void>();
    final batches = <MessageReceiptRefreshBatch>[];
    final coalescer = MessageReceiptRefreshCoalescer(
      delay: const Duration(milliseconds: 10),
      onRefresh: (batch) {
        batches.add(batch);
        return batches.length == 1 ? firstRefresh.future : Future.value();
      },
    );

    coalescer.schedule(conversationId: 'c1', messageId: 'm1');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(batches, hasLength(1));

    coalescer.schedule(conversationId: 'c1', messageId: 'm2');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(batches, hasLength(1));

    firstRefresh.complete();
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(batches, hasLength(2));
    expect(batches.last['c1'], {'m2'});
    coalescer.dispose();
  });

  test('dispose cancels a pending refresh', () async {
    var calls = 0;
    final coalescer = MessageReceiptRefreshCoalescer(
      delay: const Duration(milliseconds: 10),
      onRefresh: (_) async {
        calls += 1;
      },
    );
    coalescer.schedule(conversationId: 'c1', messageId: 'm1');
    coalescer.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(calls, 0);
  });
}
