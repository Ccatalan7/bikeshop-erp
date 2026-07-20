import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const jobsAsset = 'assets/manuals/manual_jobs_table.pdf';
  const websiteAsset = 'assets/manuals/manual_sitio_web_ventas_online.pdf';

  test('employee manuals are bundled PDFs generated from maintained sources',
      () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/manuals/'));

    for (final path in [jobsAsset, websiteAsset]) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path must ship with the ERP');
      expect(file.lengthSync(), greaterThan(10 * 1024));
      expect(ascii.decode(file.readAsBytesSync().take(4).toList()), '%PDF');
    }

    final generator =
        File('scripts/generate_user_manual_pdfs.py').readAsStringSync();
    expect(generator, contains('JOBS_TABLE_USER_GUIDE.md'));
    expect(generator, contains('WEBSITE_ONLINE_SALES_USER_GUIDE.md'));
  });

  test('both canonical modules open manuals in the shared internal preview',
      () {
    final viewer = File(
      'lib/shared/widgets/asset_pdf_preview_dialog.dart',
    ).readAsStringSync();
    final jobs = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    final website = File(
      'lib/modules/website/pages/website_management_page.dart',
    ).readAsStringSync();

    expect(viewer, contains('rootBundle.load(widget.assetPath)'));
    expect(viewer, contains('PdfPreview('));
    expect(viewer, contains('allowPrinting: false'));
    expect(viewer, contains('allowSharing: false'));

    expect(jobs, contains(jobsAsset));
    expect(jobs, contains("value: 'manual'"));
    expect(jobs, contains("tooltip: 'Manual de Jobs Table'"));
    expect(website, contains(websiteAsset));
    expect(website, contains("tooltip: 'Manual de sitio web y ventas'"));
  });

  test('manual sources cover the user-facing flows with visual diagrams', () {
    final jobs = File(
      'docs/user-guides/JOBS_TABLE_USER_GUIDE.md',
    ).readAsStringSync();
    final website = File(
      'docs/user-guides/WEBSITE_ONLINE_SALES_USER_GUIDE.md',
    ).readAsStringSync();

    expect(jobs, contains('```flow'));
    expect(jobs, contains('Presupuesto y cotización'));
    expect(jobs, contains('Lectura de tiempos y métricas'));
    expect(jobs, contains('Rutina recomendada'));
    expect(jobs, contains('Selector Estado'));
    expect(jobs, contains('ítems del trabajo'));
    expect(jobs, isNot(contains('número de serie')));
    expect(jobs, contains('`Cubierto` queda bloqueado'));
    expect(jobs, contains('REINTENTAR desde el mismo aviso'));
    expect(jobs, contains('copia al portapapeles, en formato CSV'));

    expect(website, contains('```flow'));
    expect(website, contains('Mercado Pago'));
    expect(website, contains('Correcciones y excepciones'));
    expect(website, contains('Emails y documentos'));
    expect(website, contains('Google Merchant'));
    expect(website, contains('sin descontar stock'));
    expect(website, contains('seguimiento no generan una reserva física'));
    expect(website, contains('no es boleta ni factura'));
    expect(website, contains('el ERP actual no la emite'));
    expect(website, contains('no ofrece una acción de sustitución'));
    expect(website, contains('**Listo para retiro**, seguido de'));
    expect(website, contains('**Enviado**, seguido de'));
  });

  test('canonical registries keep the in-product documentation contract', () {
    final surfaces = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();
    final workshop = File('BIKE_WORKSHOP_MASTER_SCHEMA.md').readAsStringSync();

    expect(surfaces, contains('bundled Jobs Table PDF'));
    expect(surfaces, contains('site-and-online-sales manual'));
    expect(workshop, contains('In-product Jobs Table guide'));
  });
}
