import '../../../shared/models/customer.dart';
import 'pos_cart_item.dart';
import 'payment_method.dart';

enum POSTransactionStatus {
  draft,
  completed,
  cancelled,
  refunded,
}

class POSTransaction {
  final String id;
  final String cashierId;
  final String? customerId;
  final Customer? customer;
  final List<POSCartItem> items;
  final List<POSPayment> payments;
  final double subtotal;
  final double taxAmount;
  final double discountAmount;
  final double total;
  final POSTransactionStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? receiptNumber;
  final String? journalEntryId; // Reference to accounting entry

  const POSTransaction({
    required this.id,
    required this.cashierId,
    this.customerId,
    this.customer,
    required this.items,
    required this.payments,
    required this.subtotal,
    required this.taxAmount,
    required this.discountAmount,
    required this.total,
    required this.status,
    this.notes,
    required this.createdAt,
    this.completedAt,
    this.receiptNumber,
    this.journalEntryId,
  });

  // JSON serialization
  factory POSTransaction.fromJson(Map<String, dynamic> json) {
    return POSTransaction(
      id: json['id'] ?? '',
      cashierId: json['cashier_id'] ?? '',
      customerId: json['customer_id'],
      customer: json['customer'] != null ? Customer.fromJson(json['customer']) : null,
      items: (json['items'] as List?)
          ?.map((item) => POSCartItem.fromJson(item))
          .toList() ?? [],
      payments: (json['payments'] as List?)
          ?.map((payment) => POSPayment.fromJson(payment))
          .toList() ?? [],
      subtotal: (json['subtotal'] ?? 0).toDouble(),
      taxAmount: (json['tax_amount'] ?? 0).toDouble(),
      discountAmount: (json['discount_amount'] ?? 0).toDouble(),
      total: (json['total'] ?? 0).toDouble(),
      status: POSTransactionStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => POSTransactionStatus.draft,
      ),
      notes: json['notes'],
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at']) : null,
      receiptNumber: json['receipt_number'],
      journalEntryId: json['journal_entry_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cashier_id': cashierId,
      'customer_id': customerId,
      'customer': customer?.toJson(),
      'items': items.map((item) => item.toJson()).toList(),
      'payments': payments.map((payment) => payment.toJson()).toList(),
      'subtotal': subtotal,
      'tax_amount': taxAmount,
      'discount_amount': discountAmount,
      'total': total,
      'status': status.toString().split('.').last,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'receipt_number': receiptNumber,
      'journal_entry_id': journalEntryId,
    };
  }

  // Helper methods
  POSTransaction copyWith({
    String? id,
    String? cashierId,
    String? customerId,
    Customer? customer,
    List<POSCartItem>? items,
    List<POSPayment>? payments,
    double? subtotal,
    double? taxAmount,
    double? discountAmount,
    double? total,
    POSTransactionStatus? status,
    String? notes,
    DateTime? createdAt,
    DateTime? completedAt,
    String? receiptNumber,
    String? journalEntryId,
  }) {
    return POSTransaction(
      id: id ?? this.id,
      cashierId: cashierId ?? this.cashierId,
      customerId: customerId ?? this.customerId,
      customer: customer ?? this.customer,
      items: items ?? this.items,
      payments: payments ?? this.payments,
      subtotal: subtotal ?? this.subtotal,
      taxAmount: taxAmount ?? this.taxAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      total: total ?? this.total,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      journalEntryId: journalEntryId ?? this.journalEntryId,
    );
  }

  // Calculated properties
  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);
  double get totalPaid => payments.fold(0.0, (sum, payment) => sum + payment.amount);
  double get changeAmount => totalPaid - total;
  bool get isFullyPaid => totalPaid >= total;
  bool get requiresChange => totalPaid > total;

  @override
  String toString() => 'POSTransaction(id: $id, total: \$${total.toStringAsFixed(0)}, status: $status)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is POSTransaction && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class POSPayment {
  final String id;
  final PaymentMethod method;
  final double amount;
  final String? reference; // Card transaction ID, voucher number, etc.
  final DateTime createdAt;

  const POSPayment({
    required this.id,
    required this.method,
    required this.amount,
    this.reference,
    required this.createdAt,
  });

  // JSON serialization
  factory POSPayment.fromJson(Map<String, dynamic> json) {
    return POSPayment(
      id: json['id'] ?? '',
      method: PaymentMethod.fromJson(json['method']),
      amount: (json['amount'] ?? 0).toDouble(),
      reference: json['reference'],
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'method': method.toJson(),
      'amount': amount,
      'reference': reference,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  String toString() => 'POSPayment(method: ${method.name}, amount: \$${amount.toStringAsFixed(0)})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is POSPayment && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}