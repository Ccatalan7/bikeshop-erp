import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../support/library_source.dart';

void main() {
  const routedPages = <String>[
    'website_management_page.dart',
    'page_management_page.dart',
    'navigation_management_page.dart',
    'website_destination_management_page.dart',
    'featured_products_page.dart',
    'product_website_visibility_page.dart',
    'online_orders_page.dart',
    'website_settings_page.dart',
    'integrations_page.dart',
    'seo_settings_page.dart',
  ];

  test('all routed website administration pages share the canonical shell', () {
    for (final fileName in routedPages) {
      final source =
          File('lib/modules/website/pages/$fileName').readAsStringSync();
      expect(
        source,
        contains('WebsiteAdminShell('),
        reason: '$fileName must remain inside the website administration shell',
      );
    }
  });

  test('website dashboard keeps its grouped administration hierarchy', () {
    final source = File(
      'lib/modules/website/pages/website_management_page.dart',
    ).readAsStringSync();

    expect(source, contains("'Contenido y estructura'"));
    expect(source, contains("'Catálogo y ventas'"));
    expect(source, contains("'Configuración y alcance'"));
    expect(source, contains("'Tu vitrina digital, lista para vender'"));
    expect(source, isNot(contains('GridView.count')));
    expect(source, isNot(contains('_buildManagementCard')));
  });

  test('destination audit no longer owns a competing app scaffold', () {
    final source = File(
      'lib/modules/website/pages/website_destination_management_page.dart',
    ).readAsStringSync();

    expect(source, contains('WebsiteAdminShell('));
    expect(source, isNot(contains('return Scaffold(')));
    expect(source, isNot(contains('AppBar(')));
  });

  test('online orders keeps sortable operations and exact destinations', () {
    final source = File(
      'lib/modules/website/pages/online_orders_page.dart',
    ).readAsStringSync();

    expect(source, contains("'Email',"));
    expect(source, contains('SystemMouseCursors.resizeColumn'));
    expect(source, contains('onHorizontalDragUpdate'));
    expect(source, contains('_compareOrders'));
    expect(source, contains('ListView.builder'));
    expect(source, isNot(contains('ListView.separated')));
    expect(source, contains('_showOrderInspector'));
    expect(source, contains('OrderEvidenceSection('));
    expect(source, contains('openBrowserWorkspace('));
    expect(source, contains('InteractiveTableField('));
    expect(source, contains('OperationalStatusBadge('));
    expect(source, contains('OnlineOrderWorkflowPolicy.legalNextStatuses'));
    expect(source, contains('showModernContextMenu<String>'));
    expect(source, contains('showOnlineOrderCorrectionDialog'));
    expect(source, contains("value: 'correction'"));
    expect(
        source,
        contains(
            "'/sales/invoices/\$invoiceId/edit?returnTo=/website/orders'"));
    expect(source, contains("value: 'ready_for_pickup'"));
    expect(source, contains("tooltip: 'Guía operativa'"));
    expect(source, isNot(contains('Card(')));
    expect(source, isNot(contains('_buildOrderRow')));
  });

  test('online-order evidence is read-only and keeps fiscal labels honest', () {
    final widget = File(
      'lib/modules/website/widgets/order_evidence_section.dart',
    ).readAsStringSync();
    final documentService = File(
      'lib/modules/website/services/online_order_official_document_service.dart',
    ).readAsStringSync();
    final documentModel = File(
      'lib/modules/website/models/online_order_official_document.dart',
    ).readAsStringSync();
    final communicationService = File(
      'lib/modules/website/services/order_communication_service.dart',
    ).readAsStringSync();

    expect(documentModel, contains('Voucher Mercado Pago válido como boleta'));
    expect(widget, contains('Respaldo interno · no tributario'));
    expect(widget, contains('verifiedArtifactUri'));
    expect(widget, isNot(contains('Reenviar')));
    expect(widget, isNot(contains('Card(')));
    expect(widget, isNot(contains('Chip(')));
    for (final source in [documentService, communicationService]) {
      expect(source, contains('.select('));
      expect(source, isNot(contains('.insert(')));
      expect(source, isNot(contains('.update(')));
      expect(source, isNot(contains(".rpc(")));
    }
  });

  test('jobs and online orders consume the same operational table primitives',
      () {
    final jobs = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    final orders = File(
      'lib/modules/website/pages/online_orders_page.dart',
    ).readAsStringSync();

    for (final source in [jobs, orders]) {
      expect(source, contains('OperationalStatusBadge('));
      expect(source, contains('InteractiveTableField('));
    }
    expect(jobs, isNot(contains('class _InteractiveTableField')));
    expect(orders, isNot(contains('_statusChipPalette')));
  });

  test('online order mutations use the optimistic lifecycle commands', () {
    final model = File(
      'lib/modules/website/models/website_models.dart',
    ).readAsStringSync();
    final service = readLibrarySource('lib/modules/website/services/website_service.dart');
    final orders = File(
      'lib/modules/website/pages/online_orders_page.dart',
    ).readAsStringSync();

    expect(model, contains("json['version']"));
    expect(service, contains("'transition_online_order_status'"));
    expect(service, contains("'update_online_order_internal_notes'"));
    expect(service, contains("'p_expected_version': expectedVersion"));
    expect(
      service,
      contains("'online_order_payment_processing_status_view'"),
    );
    expect(
      service,
      contains("'process_mercadopago_payment_observation'"),
    );
    expect(service, contains("'request_online_order_correction'"));
    expect(service, contains("'apply_online_order_correction'"));
    expect(service, contains("'mercadopago-refund-payment'"));
    expect(service, isNot(contains(".from('online_orders').update")));
    expect(service, isNot(contains("rpc('cancel_online_order'")));
    expect(service, contains('_orders = ordersWithProducts;'));
    expect(service, contains('ordersEnrichmentWarning'));
    expect(orders, contains('websiteService.ordersEnrichmentWarning'));
    expect(orders, contains('websiteService.ordersLoadError'));
    expect(orders, contains('expectedVersion: order.version'));
    expect(orders, contains('hasPaymentProcessingAttention'));
    expect(orders, contains('Reintentar procesamiento'));
  });

  test('online correction UI separates physical and financial dispositions',
      () {
    final dialog = File(
      'lib/modules/website/widgets/online_order_correction_dialog.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260718210000_add_online_order_correction_workflow.sql',
    ).readAsStringSync();

    expect(dialog, contains("value: 'restock'"));
    expect(dialog, contains("value: 'quarantine'"));
    expect(dialog, contains("value: 'scrap'"));
    expect(dialog, contains("value: 'financial_only'"));
    expect(dialog, contains('Mercado Pago se reembolsa primero'));
    expect(migration, contains('public.create_sales_return('));
    expect(migration, contains('public.create_sales_credit_note('));
    expect(migration, contains('public.create_sales_customer_refund('));
    expect(migration, contains('authorize_online_order_refund_execution'));
    expect(migration, contains('Provider refund success is terminal'));
    expect(migration, contains('cancel_before_fulfillment'));
    expect(migration, contains('enqueue_partial_online_order_refund_email'));
    expect(
      migration,
      contains('prevent_void_of_online_order_correction_artifact'),
    );
    expect(migration, contains("provider_state <> 'succeeded'"));
  });

  test('canonical surface registry covers the administration hub and routes',
      () {
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(registry, contains('Website administration hub'));
    expect(registry, contains('Website administration pages'));
    expect(registry, contains('WebsiteAdminShell'));
    expect(registry, contains('/website/integrations'));
    expect(registry, contains('/website/seo'));
  });
}
