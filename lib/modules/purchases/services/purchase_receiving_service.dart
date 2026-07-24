import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/purchase_invoice.dart';
import '../models/purchase_receipt.dart';

class PurchaseReceivingService {
  PurchaseReceivingService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<PurchaseReceiptControlMode> getControlMode() async {
    try {
      final row = await _client
          .from('purchase_receipt_control_settings')
          .select('control_mode')
          .maybeSingle();
      return PurchaseReceiptControlModeX.fromDatabase(row?['control_mode']);
    } on PostgrestException catch (error) {
      if (PurchaseReceivingBackendCompatibility.isSchemaUnavailable(error)) {
        return PurchaseReceiptControlMode.disabled;
      }
      rethrow;
    }
  }

  Future<Map<int, int>> getPreviouslyReceivedByLine(String invoiceId) async {
    final rows = await _client
        .from('purchase_receipt_lines')
        .select(
            'source_line_index,accepted_quantity,purchase_receipts!inner(status)')
        .eq('purchase_invoice_id', invoiceId)
        .eq('purchase_receipts.status', 'posted');
    final totals = <int, int>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final index = (row['source_line_index'] as num).toInt();
      final accepted = (row['accepted_quantity'] as num?)?.toInt() ?? 0;
      totals[index] = (totals[index] ?? 0) + accepted;
    }
    return totals;
  }

  Future<Map<int, int>> getNonPhysicalResolutionsByLine(
    String invoiceId,
  ) async {
    try {
      final rows = await _client
          .from('purchase_receipt_resolution_allocation_view')
          .select('source_line_index,resolved_quantity')
          .eq('purchase_invoice_id', invoiceId)
          .inFilter('outcome', const ['credit_note', 'documented_loss']).eq(
              'is_effective', true);
      final totals = <int, int>{};
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final index = (row['source_line_index'] as num).toInt();
        final quantity = (row['resolved_quantity'] as num?)?.toInt() ?? 0;
        totals[index] = (totals[index] ?? 0) + quantity;
      }
      return totals;
    } on PostgrestException catch (error) {
      if (PurchaseReceivingBackendCompatibility.isResolutionSchemaUnavailable(
          error)) {
        return const {};
      }
      rethrow;
    }
  }

  Future<Map<String, String>> getProductImageUrls(
    Iterable<String> productIds,
  ) async {
    final ids = productIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const {};

    final images = <String, String>{};
    for (var start = 0; start < ids.length; start += 100) {
      final end = start + 100 < ids.length ? start + 100 : ids.length;
      final rows = await _client
          .from('products')
          .select('id,image_url,image_url_optimized')
          .inFilter('id', ids.sublist(start, end));
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final optimized = row['image_url_optimized']?.toString().trim();
        final original = row['image_url']?.toString().trim();
        final resolved = optimized?.isNotEmpty == true ? optimized : original;
        if (resolved?.isNotEmpty == true) images[id] = resolved!;
      }
    }
    return images;
  }

  Future<PurchaseReceiptFulfillment> getFulfillment(
    PurchaseInvoice invoice,
  ) async {
    final invoiceId = invoice.id;
    if (invoiceId == null || invoiceId.isEmpty) {
      return _deriveFulfillment(invoice, const []);
    }
    final result = await getFulfillments([invoice]);
    return result[invoiceId] ?? _deriveFulfillment(invoice, const []);
  }

  Future<Map<String, PurchaseReceiptFulfillment>> getFulfillments(
    Iterable<PurchaseInvoice> invoices,
  ) async {
    final invoiceList = invoices
        .where((invoice) => invoice.id?.isNotEmpty ?? false)
        .toList(growable: false);
    if (invoiceList.isEmpty) return const {};

    final invoiceIds =
        invoiceList.map((invoice) => invoice.id!).toList(growable: false);
    final rows = <dynamic>[];
    final resolutionRows = <dynamic>[];
    for (var start = 0; start < invoiceIds.length; start += 100) {
      final end =
          start + 100 < invoiceIds.length ? start + 100 : invoiceIds.length;
      final batch = await _client
          .from('purchase_receipt_lines')
          .select(
            'purchase_invoice_id,source_line_index,accepted_quantity,'
            'damaged_quantity,rejected_quantity,shortage_quantity,'
            'purchase_receipts!inner(id,status,received_at)',
          )
          .inFilter(
            'purchase_invoice_id',
            invoiceIds.sublist(start, end),
          )
          .eq('purchase_receipts.status', 'posted');
      rows.addAll(batch);
      try {
        final resolutions = await _client
            .from('purchase_receipt_resolution_allocation_view')
            .select(
              'purchase_invoice_id,source_line_index,outcome,'
              'resolved_quantity,is_effective',
            )
            .inFilter(
              'purchase_invoice_id',
              invoiceIds.sublist(start, end),
            )
            .inFilter('outcome', const [
          'credit_note',
          'documented_loss',
          'later_delivery',
        ]).eq('is_effective', true);
        resolutionRows.addAll(resolutions);
      } on PostgrestException catch (error) {
        if (!PurchaseReceivingBackendCompatibility
            .isResolutionSchemaUnavailable(error)) {
          rethrow;
        }
      }
    }

    final rowsByInvoice = <String, List<Map<String, dynamic>>>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final invoiceId = row['purchase_invoice_id']?.toString();
      if (invoiceId == null || invoiceId.isEmpty) continue;
      rowsByInvoice.putIfAbsent(invoiceId, () => []).add(row);
    }

    final resolutionsByInvoice = <String, List<Map<String, dynamic>>>{};
    for (final raw in resolutionRows) {
      final row = Map<String, dynamic>.from(raw);
      final invoiceId = row['purchase_invoice_id']?.toString();
      if (invoiceId == null || invoiceId.isEmpty) continue;
      resolutionsByInvoice.putIfAbsent(invoiceId, () => []).add(row);
    }

    return {
      for (final invoice in invoiceList)
        invoice.id!: _deriveFulfillment(
          invoice,
          rowsByInvoice[invoice.id!] ?? const [],
          resolutionsByInvoice[invoice.id!] ?? const [],
        ),
    };
  }

  Future<List<PurchaseReceiptRecord>> getHistory(String invoiceId) async {
    final headers = await _client
        .from('purchase_receipts')
        .select(
            'id,receipt_number,status,received_at,delivery_reference,location_label,void_reason')
        .eq('purchase_invoice_id', invoiceId)
        .order('received_at', ascending: false);
    if (headers.isEmpty) return const [];

    final ids = headers.map((row) => row['id'].toString()).toList();
    final lines = await _client
        .from('purchase_receipt_lines')
        .select(
            'receipt_id,accepted_quantity,damaged_quantity,rejected_quantity,shortage_quantity')
        .inFilter('receipt_id', ids);
    final accepted = <String, int>{};
    final discrepancies = <String, int>{};
    for (final row in lines) {
      final id = row['receipt_id'].toString();
      accepted[id] = (accepted[id] ?? 0) +
          ((row['accepted_quantity'] as num?)?.round() ?? 0);
      discrepancies[id] = (discrepancies[id] ?? 0) +
          ((row['damaged_quantity'] as num?)?.round() ?? 0) +
          ((row['rejected_quantity'] as num?)?.round() ?? 0) +
          ((row['shortage_quantity'] as num?)?.round() ?? 0);
    }

    return headers.map((row) {
      final id = row['id'].toString();
      return PurchaseReceiptRecord(
        id: id,
        number: row['receipt_number']?.toString() ?? '',
        status: row['status']?.toString() ?? '',
        receivedAt: DateTime.parse(row['received_at'].toString()),
        acceptedQuantity: accepted[id] ?? 0,
        discrepancyQuantity: discrepancies[id] ?? 0,
        deliveryReference: row['delivery_reference']?.toString(),
        locationLabel: row['location_label']?.toString(),
        voidReason: row['void_reason']?.toString(),
      );
    }).toList(growable: false);
  }

  Future<PurchaseReceiptDetailRecord?> getReceiptDetail(
    String receiptId,
  ) async {
    final header = await _client
        .from('purchase_receipts')
        .select(
          'id,purchase_invoice_id,receipt_number,status,received_at,'
          'delivery_reference,location_label,notes,operation_id,created_by,'
          'created_at,void_operation_id,voided_at,voided_by,void_reason',
        )
        .eq('id', receiptId)
        .maybeSingle();
    if (header == null) return null;

    final rawLines = await _client
        .from('purchase_receipt_lines')
        .select(
          'id,source_line_index,product_id,product_name,product_sku,'
          'purchase_treatment,expected_quantity,previously_received_quantity,'
          'accepted_quantity,damaged_quantity,rejected_quantity,'
          'shortage_quantity,remaining_quantity,unit_cost,stock_movement_id,'
          'discrepancy_reason',
        )
        .eq('receipt_id', receiptId)
        .order('source_line_index');

    final lineIds = rawLines
        .map((line) => line['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final rawMovements = lineIds.isEmpty
        ? const <dynamic>[]
        : await _client
            .from('purchase_receipt_line_movements')
            .select(
              'receipt_line_id,product_id,stock_movement_id,'
              'movement_role,quantity',
            )
            .inFilter('receipt_line_id', lineIds);

    final movementsByLine = <String, List<PurchaseReceiptMovementRecord>>{};
    for (final raw in rawMovements) {
      final row = Map<String, dynamic>.from(raw);
      final lineId = row['receipt_line_id']?.toString();
      final productId = row['product_id']?.toString();
      final stockMovementId = row['stock_movement_id']?.toString();
      if (lineId == null ||
          lineId.isEmpty ||
          productId == null ||
          productId.isEmpty ||
          stockMovementId == null ||
          stockMovementId.isEmpty) {
        continue;
      }
      movementsByLine.putIfAbsent(lineId, () => []).add(
            PurchaseReceiptMovementRecord(
              productId: productId,
              stockMovementId: stockMovementId,
              role: row['movement_role']?.toString() ?? '',
              quantity: _integer(row['quantity']),
            ),
          );
    }

    final lines = rawLines.map((raw) {
      final row = Map<String, dynamic>.from(raw);
      final lineId = row['id']?.toString() ?? '';
      return PurchaseReceiptLineRecord(
        id: lineId,
        lineIndex: _integer(row['source_line_index']),
        productId: row['product_id']?.toString(),
        productName: row['product_name']?.toString() ?? 'Producto',
        productSku: row['product_sku']?.toString(),
        purchaseTreatment: row['purchase_treatment']?.toString() ?? 'inventory',
        expectedQuantity: _integer(row['expected_quantity']),
        previouslyReceivedQuantity:
            _integer(row['previously_received_quantity']),
        acceptedQuantity: _integer(row['accepted_quantity']),
        damagedQuantity: _integer(row['damaged_quantity']),
        rejectedQuantity: _integer(row['rejected_quantity']),
        shortageQuantity: _integer(row['shortage_quantity']),
        remainingQuantity: _integer(row['remaining_quantity']),
        unitCost: (row['unit_cost'] as num?)?.toDouble() ?? 0,
        stockMovementId: row['stock_movement_id']?.toString(),
        discrepancyReason: row['discrepancy_reason']?.toString(),
        movements: List.unmodifiable(movementsByLine[lineId] ?? const []),
      );
    }).toList(growable: false);

    final row = Map<String, dynamic>.from(header);
    return PurchaseReceiptDetailRecord(
      id: row['id']?.toString() ?? '',
      purchaseInvoiceId: row['purchase_invoice_id']?.toString() ?? '',
      number: row['receipt_number']?.toString() ?? '',
      status: row['status']?.toString() ?? '',
      receivedAt: _dateTime(row['received_at']),
      operationId: row['operation_id']?.toString() ?? '',
      createdAt: _dateTime(row['created_at']),
      lines: List.unmodifiable(lines),
      deliveryReference: row['delivery_reference']?.toString(),
      locationLabel: row['location_label']?.toString(),
      notes: row['notes']?.toString(),
      createdBy: row['created_by']?.toString(),
      voidOperationId: row['void_operation_id']?.toString(),
      voidedAt: _nullableDateTime(row['voided_at']),
      voidedBy: row['voided_by']?.toString(),
      voidReason: row['void_reason']?.toString(),
    );
  }

  Future<void> voidReceipt({
    required String receiptId,
    required String reason,
    required String idempotencyKey,
  }) async {
    await _client.rpc('void_purchase_goods_receipt', params: {
      'p_receipt_id': receiptId,
      'p_reason': reason.trim(),
      'p_idempotency_key': idempotencyKey,
    });
  }

  Future<PurchaseReceiptResult> createReceipt({
    required String invoiceId,
    required List<PurchaseReceiptLineDraft> lines,
    required DateTime receivedAt,
    required String idempotencyKey,
    String? deliveryReference,
    String? locationLabel,
    String? notes,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('La recepción necesita al menos una línea.');
    }
    for (final line in lines) {
      final error = line.validate();
      if (error != null) throw ArgumentError(error);
    }
    final response = await _client.rpc(
      'create_purchase_goods_receipt',
      params: {
        'p_purchase_invoice_id': invoiceId,
        'p_lines': lines.map((line) => line.toRpcJson()).toList(),
        'p_received_at': receivedAt.toUtc().toIso8601String(),
        'p_delivery_reference': _nullableText(deliveryReference),
        'p_location_label': _nullableText(locationLabel),
        'p_notes': _nullableText(notes),
        'p_idempotency_key': idempotencyKey,
      },
    );
    return PurchaseReceiptResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  String? _nullableText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  int _integer(Object? value) => (value as num?)?.round() ?? 0;

  DateTime _dateTime(Object? value) {
    return _nullableDateTime(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime? _nullableDateTime(Object? value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  PurchaseReceiptFulfillment _deriveFulfillment(
      PurchaseInvoice invoice, List<Map<String, dynamic>> rows,
      [List<Map<String, dynamic>> resolutionRows = const []]) {
    final acceptedByLine = <int, int>{};
    final differencesByLine = <int, int>{};
    final receiptIds = <String>{};
    DateTime? latestReceivedAt;
    final resolvedDifferencesByLine = <int, int>{};
    final nonPhysicalResolutionsByLine = <int, int>{};

    for (final row in rows) {
      final index = (row['source_line_index'] as num?)?.toInt();
      if (index == null) continue;
      acceptedByLine[index] = (acceptedByLine[index] ?? 0) +
          ((row['accepted_quantity'] as num?)?.toInt() ?? 0);
      differencesByLine[index] = (differencesByLine[index] ?? 0) +
          ((row['damaged_quantity'] as num?)?.toInt() ?? 0) +
          ((row['rejected_quantity'] as num?)?.toInt() ?? 0) +
          ((row['shortage_quantity'] as num?)?.toInt() ?? 0);

      final receipt = row['purchase_receipts'];
      if (receipt is Map) {
        final id = receipt['id']?.toString();
        if (id != null && id.isNotEmpty) receiptIds.add(id);
        final receivedAt = DateTime.tryParse(
          receipt['received_at']?.toString() ?? '',
        );
        if (receivedAt != null &&
            (latestReceivedAt == null ||
                receivedAt.isAfter(latestReceivedAt))) {
          latestReceivedAt = receivedAt;
        }
      }
    }

    for (final row in resolutionRows) {
      final index = (row['source_line_index'] as num?)?.toInt();
      if (index == null) continue;
      final resolved = (row['resolved_quantity'] as num?)?.toInt() ?? 0;
      resolvedDifferencesByLine[index] =
          (resolvedDifferencesByLine[index] ?? 0) + resolved;
      final outcome = row['outcome']?.toString();
      if (outcome == 'credit_note' || outcome == 'documented_loss') {
        nonPhysicalResolutionsByLine[index] =
            (nonPhysicalResolutionsByLine[index] ?? 0) + resolved;
      }
    }

    final legacyReceived = rows.isEmpty &&
        (invoice.status == PurchaseInvoiceStatus.received ||
            invoice.receivedDate != null);
    return PurchaseReceiptFulfillment.derive(
      expectedQuantities: invoice.items
          .map((item) => item.quantity.round())
          .toList(growable: false),
      acceptedByLine: acceptedByLine,
      differencesByLine: differencesByLine,
      resolvedDifferencesByLine: resolvedDifferencesByLine,
      nonPhysicalResolutionsByLine: nonPhysicalResolutionsByLine,
      receiptCount: receiptIds.length,
      latestReceivedAt: latestReceivedAt,
      legacyReceived: legacyReceived,
    );
  }
}

class PurchaseReceivingBackendCompatibility {
  const PurchaseReceivingBackendCompatibility._();

  static bool isSchemaUnavailable(PostgrestException error) {
    return error.code == '42P01' || error.code == 'PGRST205';
  }

  static bool isResolutionSchemaUnavailable(PostgrestException error) {
    return error.code == '42P01' || error.code == 'PGRST205';
  }
}
