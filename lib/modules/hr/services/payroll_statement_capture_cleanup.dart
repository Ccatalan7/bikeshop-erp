import 'payroll_statement_capture_cleanup_stub.dart'
    if (dart.library.io) 'payroll_statement_capture_cleanup_io.dart'
    as implementation;

Future<void> cleanupPayrollStatementCameraCapture(String? sourcePath) {
  return implementation.cleanupPayrollStatementCameraCapture(sourcePath);
}
