import 'tax_treatment.dart';

enum PaymentMethodUsageScope {
  inbound,
  outbound,
  both;

  static PaymentMethodUsageScope fromDatabase(Object? value) {
    return switch (value?.toString()) {
      'inbound' => PaymentMethodUsageScope.inbound,
      'outbound' => PaymentMethodUsageScope.outbound,
      _ => PaymentMethodUsageScope.both,
    };
  }
}

enum PaymentSettlementProvider {
  none,
  transbank,
  mercadoPago,
  other;

  static PaymentSettlementProvider fromDatabase(Object? value) {
    return switch (value?.toString()) {
      'transbank' => PaymentSettlementProvider.transbank,
      'mercadopago' => PaymentSettlementProvider.mercadoPago,
      'other' => PaymentSettlementProvider.other,
      _ => PaymentSettlementProvider.none,
    };
  }

  String get databaseValue => switch (this) {
        PaymentSettlementProvider.mercadoPago => 'mercadopago',
        _ => name,
      };
}

enum PaymentCardInstrument {
  unknown,
  debit,
  credit,
  prepaid;

  static PaymentCardInstrument fromDatabase(Object? value) {
    return switch (value?.toString()) {
      'debit' => PaymentCardInstrument.debit,
      'credit' => PaymentCardInstrument.credit,
      'prepaid' => PaymentCardInstrument.prepaid,
      _ => PaymentCardInstrument.unknown,
    };
  }
}

/// Payment method model matching payment_methods table in core_schema.sql
class PaymentMethod {
  final String id; // uuid
  final String tenantId; // uuid - MULTI-TENANT ISOLATION
  final String code;
  final String name; // 'Efectivo', 'Transferencia Bancaria', etc.
  final String accountId; // uuid - references accounts(id)
  final bool requiresReference; // true if reference field is mandatory
  final TaxTreatment
      defaultTaxTreatment; // Tax treatment for this payment method
  final String? icon; // optional icon name
  final int sortOrder; // display order
  final bool isActive; // whether this method is currently available
  final PaymentMethodUsageScope usageScope;
  final PaymentSettlementProvider settlementProvider;
  final PaymentCardInstrument paymentInstrument;
  final String? terminalProfileId;
  final DateTime createdAt;
  final DateTime updatedAt;

  PaymentMethod({
    required this.id,
    required this.tenantId,
    required this.code,
    required this.name,
    required this.accountId,
    this.requiresReference = false,
    this.defaultTaxTreatment = TaxTreatment.noTax,
    this.icon,
    this.sortOrder = 0,
    this.isActive = true,
    this.usageScope = PaymentMethodUsageScope.both,
    this.settlementProvider = PaymentSettlementProvider.none,
    this.paymentInstrument = PaymentCardInstrument.unknown,
    this.terminalProfileId,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      accountId: json['account_id']?.toString() ?? '',
      requiresReference: json['requires_reference'] == true,
      defaultTaxTreatment: TaxTreatment.fromString(
        json['default_tax_treatment']?.toString(),
      ),
      icon: json['icon']?.toString(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] ?? true,
      usageScope: PaymentMethodUsageScope.fromDatabase(json['usage_scope']),
      settlementProvider:
          PaymentSettlementProvider.fromDatabase(json['settlement_provider']),
      paymentInstrument:
          PaymentCardInstrument.fromDatabase(json['payment_instrument']),
      terminalProfileId: json['terminal_profile_id']?.toString(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'code': code,
      'name': name,
      'account_id': accountId,
      'requires_reference': requiresReference,
      'default_tax_treatment': defaultTaxTreatment.name,
      'icon': icon,
      'sort_order': sortOrder,
      'is_active': isActive,
      'usage_scope': usageScope.name,
      'settlement_provider': settlementProvider.databaseValue,
      'payment_instrument': paymentInstrument.name,
      'terminal_profile_id': terminalProfileId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  PaymentMethod copyWith({
    String? id,
    String? tenantId,
    String? code,
    String? name,
    String? accountId,
    bool? requiresReference,
    TaxTreatment? defaultTaxTreatment,
    String? icon,
    int? sortOrder,
    bool? isActive,
    PaymentMethodUsageScope? usageScope,
    PaymentSettlementProvider? settlementProvider,
    PaymentCardInstrument? paymentInstrument,
    String? terminalProfileId,
    bool clearTerminalProfile = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PaymentMethod(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      code: code ?? this.code,
      name: name ?? this.name,
      accountId: accountId ?? this.accountId,
      requiresReference: requiresReference ?? this.requiresReference,
      defaultTaxTreatment: defaultTaxTreatment ?? this.defaultTaxTreatment,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      usageScope: usageScope ?? this.usageScope,
      settlementProvider: settlementProvider ?? this.settlementProvider,
      paymentInstrument: paymentInstrument ?? this.paymentInstrument,
      terminalProfileId: clearTerminalProfile
          ? null
          : terminalProfileId ?? this.terminalProfileId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get supportsInbound =>
      usageScope == PaymentMethodUsageScope.inbound ||
      usageScope == PaymentMethodUsageScope.both;

  bool get supportsOutbound =>
      usageScope == PaymentMethodUsageScope.outbound ||
      usageScope == PaymentMethodUsageScope.both;

  bool get isCardInstrument =>
      paymentInstrument != PaymentCardInstrument.unknown ||
      code.toLowerCase() == 'card' ||
      code.toLowerCase().startsWith('card_');

  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return DateTime.now();
  }
}
