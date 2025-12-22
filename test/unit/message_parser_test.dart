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
  });
}
