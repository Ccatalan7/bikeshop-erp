import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/product_identity_trace.dart';

void main() {
  test('trace ids are stable by row revision and change with evidence revision',
      () {
    final first = ProductIdentityTrace.idFor(
      scope: 'ocr',
      rowKey: 'row-7',
      revision: '2',
    );
    final replay = ProductIdentityTrace.idFor(
      scope: 'ocr',
      rowKey: 'row-7',
      revision: '2',
    );
    final edited = ProductIdentityTrace.idFor(
      scope: 'ocr',
      rowKey: 'row-7',
      revision: '3',
    );

    expect(replay, first);
    expect(edited, isNot(first));
    expect(first, hasLength(20));
  });

  test('redacts forbidden source, prompt, image, URL and credential fields',
      () {
    final events = <Map<String, Object?>>[];

    ProductIdentityTrace.emit(
      traceId: 'trace-1',
      event: 'test',
      sink: events.add,
      data: <String, Object?>{
        'product_id': 'product-1',
        'sku': 'AE0001',
        'raw_title': 'do not log this title',
        'prompt': 'do not log this prompt',
        'image_url': 'https://signed.example/token',
        'inline_data': 'base64-secret',
        'authorization': 'Bearer secret',
        'nested': <String, Object?>{
          'candidate_id': 'candidate-1',
          'access_token': 'secret',
        },
      },
    );

    expect(events, hasLength(1));
    final event = events.single;
    expect(event['event'], 'test');
    expect(event['trace_id'], 'trace-1');
    expect(event['product_id'], 'product-1');
    expect(event['sku'], 'AE0001');
    expect(event.containsKey('raw_title'), isFalse);
    expect(event.containsKey('prompt'), isFalse);
    expect(event.containsKey('image_url'), isFalse);
    expect(event.containsKey('inline_data'), isFalse);
    expect(event.containsKey('authorization'), isFalse);
    expect(event['nested'], <String, Object?>{
      'candidate_id': 'candidate-1',
    });
  });
}
