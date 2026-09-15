import 'dart:convert';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/widgets/ocr_upload_widget.dart';

void main() {
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==');

  testWidgets('a dropped image retains its bytes and filename locally',
      (tester) async {
    final result = await tester.runAsync(() => readOcrProductImageDrop([
          DropItemFile.fromData(png, name: 'motor.png', path: '/tmp/motor.png'),
        ]));
    expect(result!.name, 'motor.png');
    expect(result.bytes, png);
  });

  testWidgets('non-image bytes cannot replace the product image',
      (tester) async {
    await tester.runAsync(() async {
      await expectLater(
          readOcrProductImageDrop([
            DropItemFile.fromData(utf8.encode('not an image'),
                name: 'fake.png'),
          ]),
          throwsA(isA<FormatException>()));
    });
  });

  testWidgets('a product drop accepts one image, not an ambiguous batch',
      (tester) async {
    for (final count in [0, 2]) {
      await expectLater(
          readOcrProductImageDrop([
            for (var i = 0; i < count; i++)
              DropItemFile.fromData(png, name: '$i.png'),
          ]),
          throwsA(isA<FormatException>()));
    }
  });
}
