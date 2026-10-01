import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Restaurar un respaldo del ERP (20260929030000): la base se niega si se
// perderían datos que el respaldo no guarda, y la app lo pregunta antes de
// ofrecer el botón. Esta guardia fija que el único camino de la app a
// `restore_backup_merge` pasa por su preflight pareado y lo omitido se muestra.
void main() {
  final page = File(
    'lib/modules/settings/pages/backup_management_page.dart',
  ).readAsStringSync();
  final service = File(
    'lib/shared/services/backup_service.dart',
  ).readAsStringSync();

  String body(String source, String signature) {
    final start = source.indexOf(signature);
    expect(start, isNonNegative, reason: 'falta $signature');
    final next = source.indexOf('\n  }\n', start);
    return source.substring(start, next);
  }

  test('restaurar se ofrece sólo después de preguntarle a la base', () {
    final confirm = body(page, 'Future<void> _confirmRestore(');
    expect(confirm, contains('BackupRestoreConfirmDialog('));
    expect(confirm, contains('_backupService.restorePreflight(backup.id)'));
    expect(confirm, contains('if (confirmed == true'));

    // `_restoreBackup` no tiene otro llamador que la confirmación.
    final calls = RegExp(r'_restoreBackup\(backup\)').allMatches(page).length;
    expect(calls, 1);

    expect(
      body(service, 'Future<RestorePreflight> restorePreflight('),
      contains("'restore_backup_merge_preflight'"),
    );
    expect(body(service, 'Future<BackupResult> restoreBackup('),
        contains("'restore_backup_merge'"));
  });

  test('una restauración hecha no se informa como fallida', () {
    final restore = body(service, 'Future<BackupResult> restoreBackup(');
    final success = restore.indexOf('if (result.success) {');
    expect(success, isNonNegative);
    final reload = restore.indexOf('await loadBackups();', success);
    // La recarga de la lista va en su propio try, después del éxito.
    expect(restore.substring(success, reload), contains('try {'));
  });

  test('lo que no volvió se muestra registro por registro', () {
    final restore = body(page, 'Future<void> _restoreBackup(');
    expect(restore, contains('result.omittedAttachments.isNotEmpty'));
    expect(restore, contains('BackupRestoreResultDialog('));

    final details = body(page, 'void _showBackupDetails(');
    expect(details, contains('backup.restoreReport'));
    expect(details, contains('OmittedAttachmentList('));
  });
}
