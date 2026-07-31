import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_statement_capture_cleanup.dart';

void main() {
  test('deletes an existing camera capture', () async {
    final dir = await Directory.systemTemp.createTemp('payroll-capture');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final capture = File('${dir.path}/capture.jpg');
    await capture.writeAsBytes(const [1, 2, 3]);

    await cleanupPayrollStatementCameraCapture(capture.path);

    expect(await capture.exists(), isFalse);
  });

  test('a missing path or file is a silent no-op', () async {
    await cleanupPayrollStatementCameraCapture(null);
    await cleanupPayrollStatementCameraCapture('   ');
    await cleanupPayrollStatementCameraCapture(
      '${Directory.systemTemp.path}/payroll-capture-inexistente.jpg',
    );
  });

  test(
    'a filesystem failure never aborts the flow that owns the bytes',
    () async {
      // A capture inside a read-only directory makes delete fail with a real
      // FileSystemException; the cleanup must swallow it because the picker
      // already holds the bytes in memory.
      final dir = await Directory.systemTemp.createTemp('payroll-capture-ro');
      final capture = File('${dir.path}/capture.jpg');
      await capture.writeAsBytes(const [1, 2, 3]);
      await Process.run('chmod', ['555', dir.path]);
      addTearDown(() async {
        await Process.run('chmod', ['755', dir.path]);
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      await expectLater(
        cleanupPayrollStatementCameraCapture(capture.path),
        completes,
      );
      expect(await capture.exists(), isTrue);
    },
    skip: Platform.isWindows
        ? 'read-only directory semantics are POSIX-specific'
        : false,
  );
}
