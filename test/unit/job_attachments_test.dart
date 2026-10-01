import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/services/job_attachments.dart';

void main() {
  test('un adjunto se guarda con su extensión: fotos y PDF, nada más', () {
    expect(jobAttachmentExtension('Presupuesto Shimano.PDF'), '.pdf');
    expect(jobAttachmentExtension('rueda.jpeg'), '.jpeg');
    expect(jobAttachmentExtension('IMG_2041.HEIC'), '.heic');
    expect(jobAttachmentExtension('captura.png'), '.png');
    // Antes todo quedaba como `.jpg`; lo que el bucket no acepta se dice
    // antes de subir.
    expect(jobAttachmentExtension('planilla.xlsx'), isNull);
    expect(jobAttachmentExtension('sin_extension'), isNull);
  });

  test('la bandeja real mira la cuenta y el taller activos', () {
    final outbox = File(
      'lib/modules/bikeshop/services/workshop_command_outbox.dart',
    ).readAsStringSync();
    final transport = outbox.substring(
      outbox.indexOf('class SupabaseWorkshopCommandTransport'),
    );
    expect(transport,
        contains('TenantService().currentTenantId == scope.tenantId'));
  });

  test('formulario y tabla suben por la bandeja y el comando del trabajo', () {
    final form = File('lib/modules/bikeshop/pages/mechanic_job_form_page.dart')
        .readAsStringSync();
    final table = File('lib/modules/bikeshop/pages/pegas_table_page.dart')
        .readAsStringSync();

    // Ninguno sube adjuntos del trabajo al bucket compartido sin taller.
    expect(form, isNot(contains("folder: 'mechanic_jobs/")));
    expect(table, isNot(contains("folder: 'mechanic_jobs/")));
    expect(form, contains('bikeshopService.uploadJobAttachment('));
    expect(table, contains('_bikeshopService.uploadJobAttachment('));

    // La tabla agrega por el comando, sólo `image_urls`; ya no reescribe la
    // fila completa desde su caché.
    expect(table, contains('_bikeshopService.addJobAttachments('));
    expect(table, isNot(contains('updateJob(job.copyWith(imageUrls')));

    // Un adjunto que no sube detiene el guardado del formulario, y se sube
    // antes del comando que lo lleva en su cabecera.
    final save =
        form.substring(form.indexOf('Future<void> _saveJob() async {'));
    expect(save, contains("'No se pudo guardar el adjunto"));
    expect(
      save.indexOf('bikeshopService.uploadJobAttachment('),
      allOf(
        isNonNegative,
        lessThan(
            save.indexOf('final lineSave = await _saveLinesWithBikeFacts(')),
      ),
    );
  });
}
