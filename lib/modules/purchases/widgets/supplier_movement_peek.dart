import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/services/payment_method_service.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../../accounting/models/expense.dart';
import '../../accounting/models/expense_payment.dart';
import '../../accounting/services/expense_service.dart';
import '../models/purchase_credit_note.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_payment.dart';
import '../models/supplier_foundation.dart';
import '../services/purchase_credit_note_service.dart';
import '../services/purchase_receiving_service.dart';
import '../services/purchase_service.dart';
import 'purchase_visual_language.dart';

/// Lo que lee la vista de un movimiento. Sólo lectura: cambiar algo se hace
/// en la página del registro, con su «Abrir …».
abstract interface class SupplierMovementPeekSource {
  Future<PurchaseInvoice?> purchaseDocument(String id);

  Future<List<PurchasePayment>> purchaseDocumentPayments(String invoiceId);

  Future<PurchasePayment?> purchasePayment(String id);

  Future<PurchaseCreditNoteRecord?> purchaseCreditNote({
    required String invoiceId,
    required String noteId,
  });

  Future<List<PurchaseCreditNoteLineRecord>> purchaseCreditNoteLines(
    String noteId,
  );

  Future<Expense?> expense(String id);

  Future<List<ExpensePayment>> expensePayments(String expenseId);

  /// El nombre del método de pago, o null si no se encuentra.
  Future<String?> paymentMethodName(String? methodId);

  /// La foto de cada producto, por id (la optimizada, si hay).
  Future<Map<String, String>> productImages(Iterable<String> productIds);
}

/// Las mismas lecturas que usan las páginas de cada registro.
class CanonicalSupplierMovementPeekSource
    implements SupplierMovementPeekSource {
  CanonicalSupplierMovementPeekSource({
    required PurchaseService purchases,
    required ExpenseService expenses,
    required PaymentMethodService paymentMethods,
    PurchaseCreditNoteService? creditNotes,
    PurchaseReceivingService? receiving,
  })  : _purchases = purchases,
        _expenses = expenses,
        _paymentMethods = paymentMethods,
        _creditNotes = creditNotes ?? PurchaseCreditNoteService(),
        _receiving = receiving ?? PurchaseReceivingService();

  final PurchaseService _purchases;
  final ExpenseService _expenses;
  final PaymentMethodService _paymentMethods;
  final PurchaseCreditNoteService _creditNotes;
  final PurchaseReceivingService _receiving;

  /// La misma lectura de la recepción: `products` del tenant, por id.
  @override
  Future<Map<String, String>> productImages(Iterable<String> productIds) =>
      _receiving.getProductImageUrls(productIds);

  @override
  Future<PurchaseInvoice?> purchaseDocument(String id) =>
      _purchases.fetchPurchaseInvoice(id, refresh: true);

  @override
  Future<List<PurchasePayment>> purchaseDocumentPayments(String invoiceId) =>
      _purchases.getPaymentsForInvoice(invoiceId);

  @override
  Future<PurchasePayment?> purchasePayment(String id) =>
      _purchases.fetchPurchasePayment(id, refresh: true);

  @override
  Future<PurchaseCreditNoteRecord?> purchaseCreditNote({
    required String invoiceId,
    required String noteId,
  }) async {
    for (final note in await _creditNotes.getHistory(invoiceId)) {
      if (note.id == noteId) return note;
    }
    return null;
  }

  @override
  Future<List<PurchaseCreditNoteLineRecord>> purchaseCreditNoteLines(
    String noteId,
  ) =>
      _creditNotes.getLines(noteId);

  @override
  Future<Expense?> expense(String id) => _expenses.getExpense(id);

  @override
  Future<List<ExpensePayment>> expensePayments(String expenseId) async {
    final rows = await _expenses.fetchPaymentsForExpenses([expenseId]);
    return [for (final row in rows) ExpensePayment.fromJson(row)]
      ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
  }

  @override
  Future<String?> paymentMethodName(String? methodId) async {
    final id = methodId?.trim();
    if (id == null || id.isEmpty) return null;
    await _paymentMethods.loadPaymentMethods();
    await _paymentMethods.loadReferencedPaymentMethods([id]);
    return _paymentMethods.getPaymentMethodById(id)?.name;
  }
}

/// Un movimiento de la ficha de un proveedor, leído encima de ella: la
/// compra con sus líneas y sus pagos, el pago y lo que pagó, la nota de
/// crédito y lo que corrige, el gasto y sus pagos. Lo relacionado se abre en
/// la misma vista, con «volver»; sólo «Abrir …» sale a la página del registro.
///
/// El dueño, 2026-11-03, mirando los movimientos de TeknoBike: «que uno pueda
/// abrir esos movimientos, sin navegar afuera». El host es `showRecordPeek`.
class SupplierMovementPeek extends StatefulWidget {
  const SupplierMovementPeek({
    super.key,
    required this.activity,
    required this.source,
    required this.onClose,
    required this.onOpenRoute,
  });

  final SupplierEconomicActivity activity;
  final SupplierMovementPeekSource source;
  final VoidCallback onClose;

  /// Cierra la vista y abre la página del registro (`/purchases/<id>`…).
  final ValueChanged<String> onOpenRoute;

  /// Si el movimiento tiene un registro que leer: compras, pagos, notas de
  /// crédito, gastos y pagos de gastos.
  static bool canOpen(SupplierEconomicActivity activity) =>
      _PeekTarget.of(activity) != null;

  @override
  State<SupplierMovementPeek> createState() => _SupplierMovementPeekState();
}

class _SupplierMovementPeekState extends State<SupplierMovementPeek> {
  late final List<_PeekTarget> _stack = [_PeekTarget.of(widget.activity)!];
  final Map<String, Future<_PeekRecord>> _loads = {};

  Future<_PeekRecord> _future(_PeekTarget target) =>
      _loads.putIfAbsent(target.key, () => _load(target));

  void _open(_PeekTarget target) => setState(() => _stack.add(target));

  void _back() {
    if (_stack.length > 1) setState(_stack.removeLast);
  }

  void _retry(_PeekTarget target) => setState(() => _loads.remove(target.key));

  Future<T?> _quiet<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> _methodNames(Iterable<String?> ids) async {
    final names = <String, String>{};
    for (final id in {
      for (final value in ids)
        if (value != null && value.trim().isNotEmpty) value.trim(),
    }) {
      final name = await _quiet(() => widget.source.paymentMethodName(id));
      if (name != null && name.trim().isNotEmpty) names[id] = name.trim();
    }
    return names;
  }

  Future<_PeekRecord> _load(_PeekTarget target) async {
    final source = widget.source;
    switch (target.kind) {
      case _PeekKind.purchaseDocument:
        final paymentsRead =
            _quiet(() => source.purchaseDocumentPayments(target.id));
        final invoice = await source.purchaseDocument(target.id);
        if (invoice == null) {
          throw const _PeekMissing('Este documento ya no está en el ERP.');
        }
        final imagesRead = _quiet(
          () => source.productImages([
            for (final item in invoice.items)
              if (item.productId.trim().isNotEmpty) item.productId.trim(),
          ]),
        );
        final payments = await paymentsRead ?? const <PurchasePayment>[];
        final names =
            await _methodNames(payments.map((p) => p.paymentMethodId));
        return _DocumentRecord(
          invoice,
          payments,
          names,
          await imagesRead ?? const <String, String>{},
        );
      case _PeekKind.purchasePayment:
        final payment = await source.purchasePayment(target.id);
        if (payment == null) {
          throw const _PeekMissing('Este pago ya no está activo.');
        }
        final invoiceRead =
            _quiet(() => source.purchaseDocument(payment.invoiceId));
        final method = await _quiet(
          () => source.paymentMethodName(payment.paymentMethodId),
        );
        return _PaymentRecord(payment, await invoiceRead, method);
      case _PeekKind.purchaseCreditNote:
        final invoiceId = target.parentId!;
        final linesRead =
            _quiet(() => source.purchaseCreditNoteLines(target.id));
        final invoiceRead = _quiet(() => source.purchaseDocument(invoiceId));
        final note = await source.purchaseCreditNote(
          invoiceId: invoiceId,
          noteId: target.id,
        );
        if (note == null) {
          throw const _PeekMissing('Esta nota de crédito ya no está.');
        }
        return _CreditNoteRecord(
          note,
          await linesRead ?? const <PurchaseCreditNoteLineRecord>[],
          invoiceId,
          await invoiceRead,
        );
      case _PeekKind.expense:
        final paymentsRead = _quiet(() => source.expensePayments(target.id));
        final expense = await source.expense(target.id);
        if (expense == null) {
          throw const _PeekMissing('Este gasto ya no está en el ERP.');
        }
        final payments = await paymentsRead ?? const <ExpensePayment>[];
        return _ExpenseRecord(
          expense,
          payments,
          await _methodNames(payments.map((p) => p.paymentMethodId)),
        );
      case _PeekKind.expensePayment:
        final expenseId = target.parentId!;
        final expenseRead = _quiet(() => source.expense(expenseId));
        final payments = await source.expensePayments(expenseId);
        final payment = payments.where((p) => p.id == target.id).firstOrNull;
        if (payment == null) {
          throw const _PeekMissing('Este pago ya no está activo.');
        }
        final method = await _quiet(
          () => source.paymentMethodName(payment.paymentMethodId),
        );
        return _ExpensePaymentRecord(payment, await expenseRead, method);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final target = _stack.last;
    return Material(
      key: const ValueKey('supplier-movement-peek'),
      color: tokens.surface,
      child: FutureBuilder<_PeekRecord>(
        key: ValueKey(target.key),
        future: _future(target),
        builder: (context, snapshot) {
          final record = snapshot.data;
          final summary = record == null
              ? _PeekSummary.loading(
                  target,
                  title: _stack.length == 1
                      ? widget.activity.documentNumber
                      : null,
                )
              : _PeekSummary.of(record, target);
          final Widget body;
          if (snapshot.hasError) {
            final error = snapshot.error;
            body = _PeekProblem(
              message: error is _PeekMissing
                  ? error.message
                  : 'No se pudo leer. Revisa la conexión e intenta otra vez.',
              onRetry: error is _PeekMissing ? null : () => _retry(target),
            );
          } else if (record == null) {
            body = Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tokens.act,
                ),
              ),
            );
          } else {
            body = _PeekBody(record: record, onOpen: _open);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PeekHeader(
                summary: summary,
                onBack: _stack.length > 1 ? _back : null,
                onClose: widget.onClose,
              ),
              Divider(height: 1, thickness: 1, color: tokens.border),
              Expanded(child: body),
              if (record != null && summary.route != null)
                _PeekFooter(
                  label: summary.openLabel,
                  onPressed: () => widget.onOpenRoute(summary.route!),
                ),
            ],
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Qué se lee

enum _PeekKind {
  purchaseDocument,
  purchasePayment,
  purchaseCreditNote,
  expense,
  expensePayment,
}

@immutable
class _PeekTarget {
  const _PeekTarget(this.kind, this.id, {this.parentId});

  final _PeekKind kind;
  final String id;

  /// El documento al que pertenece: lo que pagó un pago, lo que corrige una
  /// nota de crédito.
  final String? parentId;

  String get key => '${kind.name}:$id';

  /// `supplier_economic_read_model`: una compra o un gasto es su propio
  /// `source_document_id`; un pago o una nota de crédito es `event_id` y su
  /// documento, `source_document_id`.
  static _PeekTarget? of(SupplierEconomicActivity activity) {
    final id = activity.id.trim();
    final document = activity.sourceDocumentId?.trim() ?? '';
    _PeekTarget? record(_PeekKind kind) {
      final value = document.isNotEmpty ? document : id;
      return value.isEmpty ? null : _PeekTarget(kind, value);
    }

    _PeekTarget? child(_PeekKind kind) => id.isEmpty || document.isEmpty
        ? null
        : _PeekTarget(kind, id, parentId: document);

    return switch (activity.kind) {
      SupplierEconomicActivityKind.purchaseInvoice =>
        record(_PeekKind.purchaseDocument),
      SupplierEconomicActivityKind.purchasePayment =>
        child(_PeekKind.purchasePayment),
      SupplierEconomicActivityKind.purchaseCreditNote =>
        child(_PeekKind.purchaseCreditNote),
      SupplierEconomicActivityKind.expense => record(_PeekKind.expense),
      SupplierEconomicActivityKind.expensePayment =>
        child(_PeekKind.expensePayment),
      _ => null,
    };
  }
}

class _PeekMissing implements Exception {
  const _PeekMissing(this.message);

  final String message;
}

sealed class _PeekRecord {
  const _PeekRecord();
}

final class _DocumentRecord extends _PeekRecord {
  const _DocumentRecord(
    this.invoice,
    this.payments,
    this.methodNames,
    this.images,
  );

  final PurchaseInvoice invoice;
  final List<PurchasePayment> payments;
  final Map<String, String> methodNames;

  /// La foto de cada producto de sus líneas, por id.
  final Map<String, String> images;
}

final class _PaymentRecord extends _PeekRecord {
  const _PaymentRecord(this.payment, this.invoice, this.methodName);

  final PurchasePayment payment;
  final PurchaseInvoice? invoice;
  final String? methodName;
}

final class _CreditNoteRecord extends _PeekRecord {
  const _CreditNoteRecord(this.note, this.lines, this.invoiceId, this.invoice);

  final PurchaseCreditNoteRecord note;
  final List<PurchaseCreditNoteLineRecord> lines;
  final String invoiceId;
  final PurchaseInvoice? invoice;
}

final class _ExpenseRecord extends _PeekRecord {
  const _ExpenseRecord(this.expense, this.payments, this.methodNames);

  final Expense expense;
  final List<ExpensePayment> payments;
  final Map<String, String> methodNames;
}

final class _ExpensePaymentRecord extends _PeekRecord {
  const _ExpensePaymentRecord(this.payment, this.expense, this.methodName);

  final ExpensePayment payment;
  final Expense? expense;
  final String? methodName;
}

/// Lo que dice la cabecera y adónde lleva «Abrir …».
class _PeekSummary {
  const _PeekSummary({
    required this.overline,
    required this.icon,
    required this.title,
    required this.openLabel,
    this.meta,
    this.badge,
    this.route,
  });

  factory _PeekSummary.loading(_PeekTarget target, {String? title}) {
    final (overline, icon) = _kindLook(target.kind);
    return _PeekSummary(
      overline: overline,
      icon: icon,
      title: title?.trim().isNotEmpty == true ? title!.trim() : '…',
      openLabel: '',
    );
  }

  factory _PeekSummary.of(_PeekRecord record, _PeekTarget target) {
    final (overline, icon) = _kindLook(target.kind);
    switch (record) {
      case _DocumentRecord(:final invoice):
        final title = _documentNumber(invoice);
        final internal = invoice.invoiceNumber.trim();
        return _PeekSummary(
          overline: overline,
          icon: icon,
          title: title,
          meta: [
            _date(invoice.date),
            if (invoice.dueDate != null) 'vence ${_date(invoice.dueDate!)}',
            if (internal.isNotEmpty && internal != title) internal,
            if (invoice.sourceDocumentKindLabel?.trim().isNotEmpty == true)
              invoice.sourceDocumentKindLabel!.trim(),
          ].join(' · '),
          badge: (invoice.status.displayName, _documentTone(invoice.status)),
          openLabel: 'Abrir documento',
          route: '/purchases/${invoice.id ?? target.id}',
        );
      case _PaymentRecord(:final payment, :final methodName):
        return _PeekSummary(
          overline: overline,
          icon: icon,
          title: _money(payment.amount),
          meta: [
            _date(payment.date),
            methodName ?? 'Método sin nombre',
            if (payment.reference?.trim().isNotEmpty == true)
              'ref. ${payment.reference!.trim()}',
          ].join(' · '),
          openLabel: 'Abrir pago',
          route: '/purchases/payments/${payment.id ?? target.id}',
        );
      case _CreditNoteRecord(:final note, :final invoiceId):
        return _PeekSummary(
          overline: overline,
          icon: icon,
          title: note.number.trim().isEmpty ? 'Sin número' : note.number,
          meta: [
            _date(note.issueDate),
            if (note.supplierNumber?.trim().isNotEmpty == true)
              'folio del proveedor ${note.supplierNumber!.trim()}',
          ].join(' · '),
          badge: _creditNoteBadge(note.status),
          openLabel: 'Abrir la compra que corrige',
          route: '/purchases/$invoiceId',
        );
      case _ExpenseRecord(:final expense):
        final title = _expenseNumber(expense);
        final internal = expense.expenseNumber.trim();
        return _PeekSummary(
          overline: overline,
          icon: icon,
          title: title,
          meta: [
            _date(expense.issueDate),
            _expenseDocumentLabel(expense.documentType),
            if (expense.category?.name.trim().isNotEmpty == true)
              expense.category!.name.trim(),
            if (internal.isNotEmpty && internal != title) internal,
          ].join(' · '),
          badge: _expenseBadge(expense),
          openLabel: 'Abrir gasto',
          route: '/accounting/expenses/${expense.id ?? target.id}',
        );
      case _ExpensePaymentRecord(:final payment, :final methodName):
        return _PeekSummary(
          overline: overline,
          icon: icon,
          title: _money(payment.amount),
          meta: [
            _date(payment.paymentDate),
            methodName ?? 'Método sin nombre',
            if (payment.reference?.trim().isNotEmpty == true)
              'ref. ${payment.reference!.trim()}',
          ].join(' · '),
          openLabel: 'Abrir gasto',
          route: '/accounting/expenses/${payment.expenseId}',
        );
    }
  }

  final String overline;
  final IconData icon;
  final String title;
  final String? meta;
  final (String, VbStatusTone)? badge;
  final String openLabel;
  final String? route;
}

(String, IconData) _kindLook(_PeekKind kind) => switch (kind) {
      _PeekKind.purchaseDocument => (
          'Documento de compra',
          Icons.receipt_long_outlined
        ),
      _PeekKind.purchasePayment => ('Pago de compra', Icons.payments_outlined),
      _PeekKind.purchaseCreditNote => (
          'Nota de crédito de compra',
          Icons.assignment_return_outlined
        ),
      _PeekKind.expense => ('Gasto', Icons.request_quote_outlined),
      _PeekKind.expensePayment => ('Pago de gasto', Icons.payments_outlined),
    };

// -----------------------------------------------------------------------------
// Cómo se ve

class _PeekType {
  _PeekType(PurchaseTokens tokens)
      : title = GoogleFonts.poppins(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          height: 1.25,
          color: tokens.ink,
        ),
        group = GoogleFonts.poppins(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: tokens.ink,
        ),
        body = GoogleFonts.ibmPlexSans(
          fontSize: 12.5,
          height: 1.45,
          color: tokens.ink,
        ),
        bodyStrong = GoogleFonts.ibmPlexSans(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: tokens.ink,
        ),
        bodyMuted = GoogleFonts.ibmPlexSans(
          fontSize: 12,
          height: 1.45,
          color: tokens.inkMuted,
        ),
        overline = GoogleFonts.ibmPlexMono(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: tokens.inkFaint,
        ),
        meta = GoogleFonts.ibmPlexMono(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: tokens.inkFaint,
        ).copyWith(fontFeatures: PurchaseType.tabular),
        figure = GoogleFonts.ibmPlexMono(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: tokens.ink,
        ).copyWith(fontFeatures: PurchaseType.tabular),
        amount = GoogleFonts.ibmPlexMono(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: tokens.ink,
        ).copyWith(fontFeatures: PurchaseType.tabular),
        amountMuted = GoogleFonts.ibmPlexMono(
          fontSize: 12.5,
          color: tokens.inkMuted,
        ).copyWith(fontFeatures: PurchaseType.tabular);

  final TextStyle title;
  final TextStyle group;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle bodyMuted;
  final TextStyle overline;
  final TextStyle meta;
  final TextStyle figure;
  final TextStyle amount;
  final TextStyle amountMuted;
}

class _PeekHeader extends StatelessWidget {
  const _PeekHeader({
    required this.summary,
    required this.onBack,
    required this.onClose,
  });

  final _PeekSummary summary;
  final VoidCallback? onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _PeekType(tokens);
    final badge = summary.badge;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: IconButton(
                key: const ValueKey('supplier-movement-peek-back'),
                tooltip: 'Volver',
                onPressed: onBack,
                icon: Icon(Icons.arrow_back, size: 20, color: tokens.inkMuted),
              ),
            ),
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(top: 2, left: 4),
            decoration: BoxDecoration(
              color: tokens.actSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.actBorder),
            ),
            child: Icon(summary.icon, size: 20, color: tokens.act),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary.overline.toUpperCase(), style: type.overline),
                const SizedBox(height: 3),
                Semantics(
                  header: true,
                  child: Text(
                    summary.title,
                    style: type.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (summary.meta?.isNotEmpty == true) ...[
                  const SizedBox(height: 3),
                  Text(summary.meta!, style: type.bodyMuted),
                ],
                if (badge != null) ...[
                  const SizedBox(height: 8),
                  VbStatusBadge(label: badge.$1, tone: badge.$2, dense: true),
                ],
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('supplier-movement-peek-close'),
            tooltip: 'Cerrar',
            onPressed: onClose,
            icon: Icon(Icons.close, size: 20, color: tokens.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _PeekFooter extends StatelessWidget {
  const _PeekFooter({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        child: FilledButton.icon(
          key: const ValueKey('supplier-movement-peek-open'),
          onPressed: onPressed,
          icon: const Icon(Icons.open_in_new, size: 17),
          label: Text(label),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            backgroundColor: tokens.act,
            foregroundColor: tokens.onAct,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PeekProblem extends StatelessWidget {
  const _PeekProblem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final type = _PeekType(PurchaseTokens.of(context));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: type.bodyMuted, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// El cuerpo de cada registro, con la misma anatomía: las cifras en una
/// franja hundida, las líneas, lo relacionado (que se abre aquí mismo) y las
/// notas.
class _PeekBody extends StatelessWidget {
  const _PeekBody({required this.record, required this.onOpen});

  final _PeekRecord record;
  final ValueChanged<_PeekTarget> onOpen;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final warning = roles.warning.accent;
    final children = switch (record) {
      _DocumentRecord(
        :final invoice,
        :final payments,
        :final methodNames,
        :final images,
      ) =>
        [
          _PeekFigures(figures: [
            _Figure('Total', _money(invoice.total)),
            // Lo que una nota de crédito le restó: sin esta cifra, un total
            // de 146.976 con 140.549 pagados y saldo 0 no cuadra a la vista.
            if (invoice.creditedAmount > 0)
              _Figure('Crédito', '−${_money(invoice.creditedAmount)}'),
            _Figure('Pagado', _money(invoice.paidAmount)),
            _Figure(
              'Saldo',
              _money(invoice.balance),
              color: invoice.balance > 0 ? warning : null,
            ),
          ]),
          if (invoice.items.isNotEmpty)
            _PeekLines(
              title: 'Líneas',
              withPhotos: true,
              lines: [
                for (final item in invoice.items)
                  _Line(
                    photoUrl: images[item.productId.trim()],
                    title: item.productName?.trim().isNotEmpty == true
                        ? item.productName!.trim()
                        : item.description?.trim().isNotEmpty == true
                            ? item.description!.trim()
                            : 'Línea sin producto',
                    detail: [
                      '${_quantity(item.quantity)} × ${_money(item.unitCost)}',
                      if (item.productSku?.trim().isNotEmpty == true)
                        'SKU ${item.productSku!.trim()}',
                    ].join(' · '),
                    amount: _money(item.netAmountClamped),
                  ),
              ],
            ),
          _PeekTotals(rows: [
            ('Neto', _money(invoice.subtotal), false),
            if (invoice.discountAmount > 0)
              ('Descuento', '−${_money(invoice.discountAmount)}', false),
            ('IVA', _money(invoice.ivaAmount), false),
            ('Total', _money(invoice.total), true),
          ]),
          _PeekRelated(
            title: 'Pagos',
            empty: invoice.status == PurchaseInvoiceStatus.cancelled
                ? null
                : 'Sin pagos registrados.',
            rows: [
              for (final payment in payments)
                if (payment.id != null)
                  _Related(
                    id: payment.id!,
                    icon: Icons.payments_outlined,
                    title: methodNames[payment.paymentMethodId] ?? 'Pago',
                    detail: [
                      _date(payment.date),
                      if (payment.reference?.trim().isNotEmpty == true)
                        'ref. ${payment.reference!.trim()}',
                    ].join(' · '),
                    amount: _money(payment.amount),
                    target: _PeekTarget(
                      _PeekKind.purchasePayment,
                      payment.id!,
                      parentId: payment.invoiceId,
                    ),
                  ),
            ],
            onOpen: onOpen,
          ),
          if (invoice.notes?.trim().isNotEmpty == true)
            _PeekNote(title: 'Notas', text: invoice.notes!.trim()),
        ],
      _PaymentRecord(:final payment, :final invoice) => [
          _PeekFigures(figures: [
            _Figure('Monto', _money(payment.amount)),
            if (invoice != null)
              _Figure(
                'Saldo del documento',
                _money(invoice.balance),
                color: invoice.balance > 0 ? warning : null,
              ),
          ]),
          _PeekRelated(
            title: 'Pagó',
            rows: [
              _Related(
                id: payment.invoiceId,
                icon: Icons.receipt_long_outlined,
                title: invoice == null
                    ? 'Documento de compra'
                    : 'Documento de compra ${_documentNumber(invoice)}',
                detail: invoice == null
                    ? 'No se pudo leer el documento'
                    : '${_date(invoice.date)} · total ${_money(invoice.total)}',
                amount: invoice?.status.displayName,
                target: _PeekTarget(
                  _PeekKind.purchaseDocument,
                  payment.invoiceId,
                ),
              ),
            ],
            onOpen: onOpen,
          ),
          if (payment.notes?.trim().isNotEmpty == true)
            _PeekNote(title: 'Notas', text: payment.notes!.trim()),
        ],
      _CreditNoteRecord(
        :final note,
        :final lines,
        :final invoiceId,
        :final invoice
      ) =>
        [
          _PeekFigures(figures: [
            _Figure('Acredita', _money(note.totalAmount.toDouble())),
            _Figure('Devuelto', _money(note.refundedAmount.toDouble())),
            _Figure(
              'Por devolver',
              _money(note.availableToRefund.toDouble()),
              color: note.availableToRefund > 0 ? warning : null,
            ),
          ]),
          if (lines.isNotEmpty)
            _PeekLines(
              title: 'Líneas',
              lines: [
                for (final line in lines)
                  _Line(
                    title: line.productName.trim().isEmpty
                        ? 'Línea sin producto'
                        : line.productName.trim(),
                    detail: [
                      '${line.quantity} ${line.quantity == 1 ? 'unidad' : 'unidades'}',
                      if (line.productSku?.trim().isNotEmpty == true)
                        'SKU ${line.productSku!.trim()}',
                    ].join(' · '),
                    amount: _money(line.totalAmount.toDouble()),
                  ),
              ],
            ),
          if (note.reason.trim().isNotEmpty)
            _PeekNote(title: 'Motivo', text: note.reason.trim()),
          _PeekRelated(
            title: 'Corrige',
            rows: [
              _Related(
                id: invoiceId,
                icon: Icons.receipt_long_outlined,
                title: invoice == null
                    ? 'Documento de compra'
                    : 'Documento de compra ${_documentNumber(invoice)}',
                detail: invoice == null
                    ? 'No se pudo leer el documento'
                    : '${_date(invoice.date)} · total ${_money(invoice.total)}',
                amount: invoice?.status.displayName,
                target: _PeekTarget(_PeekKind.purchaseDocument, invoiceId),
              ),
            ],
            onOpen: onOpen,
          ),
        ],
      _ExpenseRecord(:final expense, :final payments, :final methodNames) => [
          _PeekFigures(figures: [
            _Figure('Total', _money(expense.totalAmount)),
            _Figure('Pagado', _money(expense.amountPaid)),
            _Figure(
              'Saldo',
              _money(expense.balance),
              color: expense.balance > 0 ? warning : null,
            ),
          ]),
          if (expense.lines.isNotEmpty)
            _PeekLines(
              title: 'Líneas',
              lines: [
                for (final line in expense.lines)
                  _Line(
                    title: line.description?.trim().isNotEmpty == true
                        ? line.description!.trim()
                        : line.accountName.trim().isNotEmpty
                            ? line.accountName.trim()
                            : 'Línea sin descripción',
                    detail: [
                      if (line.description?.trim().isNotEmpty == true)
                        line.accountName,
                      if (line.quantity != 1)
                        '${_quantity(line.quantity)} × ${_money(line.unitPrice)}',
                    ].join(' · '),
                    amount: _money(line.total),
                  ),
              ],
            ),
          _PeekTotals(rows: [
            ('Neto', _money(expense.subtotal), false),
            ('IVA', _money(expense.taxAmount), false),
            ('Total', _money(expense.totalAmount), true),
          ]),
          _PeekRelated(
            title: 'Pagos',
            empty: 'Sin pagos registrados.',
            rows: [
              for (final payment in payments)
                if (payment.id != null)
                  _Related(
                    id: payment.id!,
                    icon: Icons.payments_outlined,
                    title: methodNames[payment.paymentMethodId] ?? 'Pago',
                    detail: [
                      _date(payment.paymentDate),
                      if (payment.reference?.trim().isNotEmpty == true)
                        'ref. ${payment.reference!.trim()}',
                    ].join(' · '),
                    amount: _money(payment.amount),
                    target: _PeekTarget(
                      _PeekKind.expensePayment,
                      payment.id!,
                      parentId: payment.expenseId,
                    ),
                  ),
            ],
            onOpen: onOpen,
          ),
          if (expense.notes?.trim().isNotEmpty == true)
            _PeekNote(title: 'Notas', text: expense.notes!.trim()),
        ],
      _ExpensePaymentRecord(:final payment, :final expense) => [
          _PeekFigures(figures: [
            _Figure('Monto', _money(payment.amount)),
            if (expense != null)
              _Figure(
                'Saldo del gasto',
                _money(expense.balance),
                color: expense.balance > 0 ? warning : null,
              ),
          ]),
          _PeekRelated(
            title: 'Pagó',
            rows: [
              _Related(
                id: payment.expenseId,
                icon: Icons.request_quote_outlined,
                title: expense == null
                    ? 'Gasto'
                    : 'Gasto ${_expenseNumber(expense)}',
                detail: expense == null
                    ? 'No se pudo leer el gasto'
                    : '${_date(expense.issueDate)} · total ${_money(expense.totalAmount)}',
                amount: null,
                target: _PeekTarget(_PeekKind.expense, payment.expenseId),
              ),
            ],
            onOpen: onOpen,
          ),
          if (payment.notes?.trim().isNotEmpty == true)
            _PeekNote(title: 'Notas', text: payment.notes!.trim()),
        ],
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: 18),
          children[index],
        ],
      ],
    );
  }
}

class _Figure {
  const _Figure(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;
}

class _PeekFigures extends StatelessWidget {
  const _PeekFigures({required this.figures});

  final List<_Figure> figures;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _PeekType(tokens);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tokens.sunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < figures.length; index++) ...[
            if (index > 0) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    figures[index].label.toUpperCase(),
                    style: type.overline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      figures[index].value,
                      style: figures[index].color == null
                          ? type.figure
                          : type.figure.copyWith(color: figures[index].color),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Line {
  const _Line({
    required this.title,
    required this.detail,
    this.amount,
    this.photoUrl,
  });

  final String title;
  final String detail;
  final String? amount;
  final String? photoUrl;
}

/// Las líneas del documento; más de ocho se pliegan, como un grupo largo de
/// la ficha.
class _PeekLines extends StatefulWidget {
  const _PeekLines({
    required this.title,
    required this.lines,
    this.withPhotos = false,
  });

  final String title;
  final List<_Line> lines;

  /// Las líneas de productos llevan su foto (o su lugar, sin foto), para que
  /// la columna de nombres quede pareja.
  final bool withPhotos;

  @override
  State<_PeekLines> createState() => _PeekLinesState();
}

class _PeekLinesState extends State<_PeekLines> {
  static const _folded = 8;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _PeekType(tokens);
    final lines = widget.lines;
    final shown =
        _expanded || lines.length <= _folded + 2 ? lines.length : _folded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupTitle(title: widget.title, count: lines.length),
        for (var index = 0; index < shown; index++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              border: index == 0
                  ? null
                  : Border(top: BorderSide(color: tokens.hair)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.withPhotos) ...[
                  _LinePhoto(
                    url: lines[index].photoUrl,
                    label: lines[index].title,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lines[index].title,
                        style: type.bodyStrong,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (lines[index].detail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(lines[index].detail, style: type.meta),
                      ],
                    ],
                  ),
                ),
                if (lines[index].amount != null) ...[
                  const SizedBox(width: 12),
                  Text(lines[index].amount!, style: type.amount),
                ],
              ],
            ),
          ),
        if (shown < lines.length)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = true),
              child: Text('Ver las ${lines.length - shown} restantes'),
            ),
          ),
      ],
    );
  }
}

/// La foto del producto de una línea. Las fotos del catálogo son sobre fondo
/// blanco, así que la placa es blanca también en oscuro: una banda oscura
/// alrededor de una foto blanca se lee como un marco roto. Sin foto, el lugar
/// queda hundido con el ícono de producto.
class _LinePhoto extends StatelessWidget {
  const _LinePhoto({required this.url, required this.label});

  static const double size = 44;

  final String? url;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final source = url?.trim() ?? '';
    final placeholder = Icon(
      Icons.inventory_2_outlined,
      size: 18,
      color: tokens.inkFaint,
    );
    return Semantics(
      container: source.isNotEmpty,
      image: source.isNotEmpty,
      label: source.isNotEmpty ? 'Foto de $label' : null,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: source.isNotEmpty ? Colors.white : tokens.sunken,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: source.isEmpty
            ? placeholder
            : Padding(
                padding: const EdgeInsets.all(2),
                child: Image.network(
                  source,
                  fit: BoxFit.contain,
                  cacheWidth: (size * 3).round(),
                  errorBuilder: (_, __, ___) => placeholder,
                ),
              ),
      ),
    );
  }
}

class _PeekTotals extends StatelessWidget {
  const _PeekTotals({required this.rows});

  final List<(String, String, bool)> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _PeekType(tokens);
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderStrong)),
      ),
      child: Column(
        children: [
          for (final (label, value, strong) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: strong ? type.bodyStrong : type.bodyMuted,
                    ),
                  ),
                  Text(value, style: strong ? type.amount : type.amountMuted),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Related {
  const _Related({
    required this.id,
    required this.icon,
    required this.title,
    required this.detail,
    required this.amount,
    required this.target,
  });

  final String id;
  final IconData icon;
  final String title;
  final String detail;
  final String? amount;
  final _PeekTarget target;
}

/// Lo relacionado se abre en esta misma vista: un pago y su documento, una
/// nota de crédito y lo que corrige.
class _PeekRelated extends StatelessWidget {
  const _PeekRelated({
    required this.title,
    required this.rows,
    required this.onOpen,
    this.empty,
  });

  final String title;
  final List<_Related> rows;
  final ValueChanged<_PeekTarget> onOpen;

  /// Qué decir sin filas; null no muestra el grupo.
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _PeekType(tokens);
    if (rows.isEmpty && empty == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupTitle(title: title, count: rows.length > 1 ? rows.length : null),
        if (rows.isEmpty)
          Text(empty!, style: type.bodyMuted)
        else
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const SizedBox(height: 6),
            _RelatedRow(row: rows[index], onOpen: onOpen),
          ],
      ],
    );
  }
}

class _RelatedRow extends StatelessWidget {
  const _RelatedRow({required this.row, required this.onOpen});

  final _Related row;
  final ValueChanged<_PeekTarget> onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _PeekType(tokens);
    final radius = BorderRadius.circular(8);
    return Semantics(
      button: true,
      label: 'Ver ${row.title}',
      excludeSemantics: true,
      child: Material(
        color: tokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('supplier-movement-peek-related-${row.id}'),
          onTap: () => onOpen(row.target),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
              child: Row(
                children: [
                  Icon(row.icon, size: 18, color: tokens.inkMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          row.title,
                          style: type.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (row.detail.isNotEmpty)
                          Text(row.detail, style: type.meta),
                      ],
                    ),
                  ),
                  if (row.amount != null) ...[
                    const SizedBox(width: 10),
                    Text(row.amount!, style: type.amount),
                  ],
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right, size: 20, color: tokens.inkFaint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PeekNote extends StatelessWidget {
  const _PeekNote({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final type = _PeekType(tokens);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupTitle(title: title),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: tokens.sunken,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tokens.border),
          ),
          child: Text(text, style: type.body),
        ),
      ],
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final type = _PeekType(PurchaseTokens.of(context));
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title, style: type.group),
          if (count != null) ...[
            const SizedBox(width: 8),
            Text('$count', style: type.meta),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Palabras y cifras

String _documentNumber(PurchaseInvoice invoice) {
  final supplier = invoice.supplierInvoiceNumber?.trim() ?? '';
  if (supplier.isNotEmpty) return supplier;
  final internal = invoice.invoiceNumber.trim();
  return internal.isEmpty ? 'Sin folio' : internal;
}

String _expenseNumber(Expense expense) {
  final document = expense.documentNumber?.trim() ?? '';
  if (document.isNotEmpty) return document;
  final internal = expense.expenseNumber.trim();
  return internal.isEmpty ? 'Sin número' : internal;
}

VbStatusTone _documentTone(PurchaseInvoiceStatus status) => switch (status) {
      PurchaseInvoiceStatus.draft => VbStatusTone.neutral,
      PurchaseInvoiceStatus.sent ||
      PurchaseInvoiceStatus.confirmed ||
      PurchaseInvoiceStatus.received =>
        VbStatusTone.info,
      PurchaseInvoiceStatus.paid => VbStatusTone.success,
      PurchaseInvoiceStatus.cancelled => VbStatusTone.danger,
    };

(String, VbStatusTone) _creditNoteBadge(String status) => switch (status) {
      'posted' => ('Contabilizada', VbStatusTone.success),
      'voided' => ('Anulada', VbStatusTone.danger),
      'draft' => ('Borrador', VbStatusTone.neutral),
      _ => (status, VbStatusTone.neutral),
    };

(String, VbStatusTone) _expenseBadge(Expense expense) {
  if (expense.postingStatus == ExpensePostingStatus.draft) {
    return ('Borrador', VbStatusTone.neutral);
  }
  if (expense.postingStatus == ExpensePostingStatus.voided) {
    return ('Anulado', VbStatusTone.danger);
  }
  return switch (expense.paymentStatus) {
    ExpensePaymentStatus.pending => ('Pendiente de pago', VbStatusTone.warning),
    ExpensePaymentStatus.scheduled => ('Pago programado', VbStatusTone.info),
    ExpensePaymentStatus.partial => ('Pago parcial', VbStatusTone.warning),
    ExpensePaymentStatus.paid => ('Pagado', VbStatusTone.success),
    ExpensePaymentStatus.voided => ('Anulado', VbStatusTone.danger),
  };
}

String _expenseDocumentLabel(ExpenseDocumentType type) => switch (type) {
      ExpenseDocumentType.invoice => 'Factura',
      ExpenseDocumentType.receipt => 'Boleta',
      ExpenseDocumentType.ticket => 'Ticket',
      ExpenseDocumentType.reimbursement => 'Reembolso',
      ExpenseDocumentType.other => 'Otro documento',
    };

String _money(double amount) => PurchaseMoney.format(amount, 'CLP');

String _quantity(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(2).replaceAll('.', ',');

/// Como la tabla de movimientos: la fecha tal como la guarda el documento.
String _date(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year}';
}
