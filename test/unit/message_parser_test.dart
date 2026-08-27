import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/utils/message_parser.dart';

void main() {
  group('MessageParser', () {
    test('parses #JOB-123', () {
      final segments = MessageParser.parse('Check #JOB-123');
      expect(segments.length, 2);
      expect(segments[0], isA<TextSegment>());
      expect((segments[0] as TextSegment).text, 'Check ');
      expect(segments[1], isA<ReferenceSegment>());
      expect((segments[1] as ReferenceSegment).type, RefType.job);
      expect((segments[1] as ReferenceSegment).id, '123');
    });

    test('parses #JOB123 (no hyphen)', () {
      final segments = MessageParser.parse('Check #JOB123');
      expect(segments.length, 2);
      expect(segments[1], isA<ReferenceSegment>());
      expect((segments[1] as ReferenceSegment).id, '123');
    });

    test('parses #INV-ABC', () {
      final segments = MessageParser.parse('Inv #INV-ABC');
      expect(segments[1], isA<ReferenceSegment>());
      expect((segments[1] as ReferenceSegment).type, RefType.invoice);
      expect((segments[1] as ReferenceSegment).id, 'ABC');
    });

    test('ignores #INVALID', () {
      final segments = MessageParser.parse('Check #INVALID');
      expect(segments.length, 1);
      expect(segments[0], isA<TextSegment>());
    });

    test('ignores #JOB (no ID)', () {
      final segments = MessageParser.parse('Check #JOB');
      expect(segments.length, 1);
      expect(segments[0], isA<TextSegment>());
    });

    test('parses #TASK references with a task id', () {
      final segments = MessageParser.parse(
        'Quedó lista #TASK-7c2f0a1e-0000-4000-8000-000000000001, avísame',
      );

      final refs = segments.whereType<ReferenceSegment>().toList();
      expect(refs, hasLength(1));
      expect(refs.single.type, RefType.task);
      expect(refs.single.id, '7c2f0a1e-0000-4000-8000-000000000001');
    });

    test('parses shared Vinabike route links', () {
      final segments = MessageParser.parse(
        'Mira vinabike://app/open?route=%2Fsales%2Finvoices&title=Facturas',
      );

      expect(segments.length, 2);
      expect(segments[0], isA<TextSegment>());
      expect(segments[1], isA<AppRouteLinkSegment>());
      expect((segments[1] as AppRouteLinkSegment).route, '/sales/invoices');
    });

    test('parses ERP web route links', () {
      final segments = MessageParser.parse(
        'Mira https://erp.vinabike.cl/inventory/products?view=table',
      );

      expect(segments.length, 2);
      expect(segments[1], isA<AppRouteLinkSegment>());
      expect(
        (segments[1] as AppRouteLinkSegment).route,
        '/inventory/products?view=table',
      );
    });
  });
}
