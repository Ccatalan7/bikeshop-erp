import 'package:flutter/material.dart';

import '../../../shared/services/return_navigation.dart';
import '../../../shared/widgets/main_layout.dart';
import '../widgets/customer_quote_detail_view.dart';

/// Ruta propia de una cotización (`/sales/quotes/:id`): la abre la bandeja en
/// el teléfono, un aviso del ERP o un enlace. Cierra hacia quien la abrió.
class CustomerQuoteDetailPage extends StatelessWidget {
  const CustomerQuoteDetailPage({super.key, required this.quoteId});

  final String quoteId;

  @override
  Widget build(BuildContext context) {
    void close() =>
        ReturnNavigation.close(context, fallbackRoute: '/sales/quotes');
    return MainLayout(
      title: 'Cotización',
      onBackPressed: close,
      child: CustomerQuoteDetailView(quoteId: quoteId, onClose: close),
    );
  }
}
