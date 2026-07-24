import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/payment_method_service.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_payment.dart';
import '../services/purchase_service.dart';
import '../widgets/purchase_payment_detail_view.dart';

class PurchasePaymentDetailPage extends StatefulWidget {
  const PurchasePaymentDetailPage({super.key, required this.paymentId});

  final String paymentId;

  @override
  State<PurchasePaymentDetailPage> createState() =>
      _PurchasePaymentDetailPageState();
}

class _PurchasePaymentDetailPageState extends State<PurchasePaymentDetailPage> {
  PurchasePayment? _payment;
  PurchaseInvoice? _invoice;
  String _methodName = 'Sin método';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final purchases = context.read<PurchaseService>();
      final methods = context.read<PaymentMethodService>();
      final payment = await purchases.fetchPurchasePayment(
        widget.paymentId,
        refresh: true,
      );
      if (payment == null) {
        throw StateError('El pago no existe o ya no está activo.');
      }

      final invoice = await purchases.fetchPurchaseInvoice(
        payment.invoiceId,
        refresh: true,
      );
      if (invoice == null) {
        throw StateError('No se encontró la factura vinculada al pago.');
      }

      await methods.loadPaymentMethods();
      await methods.loadReferencedPaymentMethods([payment.paymentMethodId]);
      if (!mounted) return;
      setState(() {
        _payment = payment;
        _invoice = invoice;
        _methodName =
            methods.getPaymentMethodById(payment.paymentMethodId)?.name ??
                'Método histórico';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Exception: ', '');
      });
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/purchases/payments');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: _loading
          ? const Center(child: BrandedLoading())
          : _payment == null || _invoice == null
              ? _buildFailure()
              : PurchasePaymentDetailView(
                  payment: _payment!,
                  invoice: _invoice!,
                  paymentMethodName: _methodName,
                  onClose: _close,
                  onRefresh: _load,
                ),
    );
  }

  Widget _buildFailure() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              size: 54,
              color: Color(0xFF64748B),
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'No se pudo cargar el pago.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              children: [
                OutlinedButton(
                  onPressed: _close,
                  child: const Text('Volver a pagos'),
                ),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
