import 'payment_method.dart';

class PaymentTerminalTerm {
  const PaymentTerminalTerm({
    this.id,
    required this.instrument,
    this.paymentMethodId,
    this.paymentMethodCode,
    this.paymentMethodName,
    required this.commissionRateBps,
    this.commissionVatBps = 1900,
    this.minimumCommissionUf = 0,
    required this.settlementBusinessDays,
    this.bookingGraceBusinessDays = 2,
    this.amountToleranceClp = 1000,
    required this.effectiveFrom,
    this.effectiveTo,
    this.sourceNote,
    this.sourceUrl,
  });

  final String? id;
  final PaymentCardInstrument instrument;
  final String? paymentMethodId;
  final String? paymentMethodCode;
  final String? paymentMethodName;
  final int commissionRateBps;
  final int commissionVatBps;
  final double minimumCommissionUf;
  final int settlementBusinessDays;
  final int bookingGraceBusinessDays;
  final int amountToleranceClp;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final String? sourceNote;
  final String? sourceUrl;

  double get commissionPercent => commissionRateBps / 100;
  double get commissionVatPercent => commissionVatBps / 100;

  factory PaymentTerminalTerm.fromJson(Map<String, dynamic> json) {
    return PaymentTerminalTerm(
      id: json['id']?.toString(),
      instrument: PaymentCardInstrument.fromDatabase(json['instrument']),
      paymentMethodId: json['payment_method_id']?.toString(),
      paymentMethodCode: json['payment_method_code']?.toString(),
      paymentMethodName: json['payment_method_name']?.toString(),
      commissionRateBps: (json['commission_rate_bps'] as num?)?.toInt() ?? 0,
      commissionVatBps: (json['commission_vat_bps'] as num?)?.toInt() ?? 1900,
      minimumCommissionUf:
          double.tryParse(json['minimum_commission_uf']?.toString() ?? '') ?? 0,
      settlementBusinessDays:
          (json['settlement_business_days'] as num?)?.toInt() ?? 0,
      bookingGraceBusinessDays:
          (json['booking_grace_business_days'] as num?)?.toInt() ?? 2,
      amountToleranceClp:
          (json['amount_tolerance_clp'] as num?)?.toInt() ?? 1000,
      effectiveFrom: _date(json['effective_from']) ?? DateTime.now(),
      effectiveTo: _date(json['effective_to']),
      sourceNote: json['source_note']?.toString(),
      sourceUrl: json['source_url']?.toString(),
    );
  }

  Map<String, dynamic> toRpcJson() => <String, dynamic>{
        'instrument': instrument.name,
        if (paymentMethodId?.isNotEmpty == true)
          'payment_method_id': paymentMethodId,
        'commission_rate_bps': commissionRateBps,
        'commission_vat_bps': commissionVatBps,
        'minimum_commission_uf': minimumCommissionUf,
        'settlement_business_days': settlementBusinessDays,
        'booking_grace_business_days': bookingGraceBusinessDays,
        'amount_tolerance_clp': amountToleranceClp,
        'effective_from': _civilDate(effectiveFrom),
        if (sourceNote?.trim().isNotEmpty == true)
          'source_note': sourceNote!.trim(),
        if (sourceUrl?.trim().isNotEmpty == true)
          'source_url': sourceUrl!.trim(),
      };

  PaymentTerminalTerm copyWith({
    String? id,
    PaymentCardInstrument? instrument,
    String? paymentMethodId,
    String? paymentMethodCode,
    String? paymentMethodName,
    int? commissionRateBps,
    int? commissionVatBps,
    double? minimumCommissionUf,
    int? settlementBusinessDays,
    int? bookingGraceBusinessDays,
    int? amountToleranceClp,
    DateTime? effectiveFrom,
    DateTime? effectiveTo,
    String? sourceNote,
    String? sourceUrl,
  }) {
    return PaymentTerminalTerm(
      id: id ?? this.id,
      instrument: instrument ?? this.instrument,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      paymentMethodCode: paymentMethodCode ?? this.paymentMethodCode,
      paymentMethodName: paymentMethodName ?? this.paymentMethodName,
      commissionRateBps: commissionRateBps ?? this.commissionRateBps,
      commissionVatBps: commissionVatBps ?? this.commissionVatBps,
      minimumCommissionUf: minimumCommissionUf ?? this.minimumCommissionUf,
      settlementBusinessDays:
          settlementBusinessDays ?? this.settlementBusinessDays,
      bookingGraceBusinessDays:
          bookingGraceBusinessDays ?? this.bookingGraceBusinessDays,
      amountToleranceClp: amountToleranceClp ?? this.amountToleranceClp,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      effectiveTo: effectiveTo ?? this.effectiveTo,
      sourceNote: sourceNote ?? this.sourceNote,
      sourceUrl: sourceUrl ?? this.sourceUrl,
    );
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String _civilDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class PaymentTerminalProfile {
  PaymentTerminalProfile({
    this.id,
    required this.providerCode,
    required this.providerName,
    required this.terminalName,
    this.merchantReference,
    this.clearingAccountId,
    this.commissionExpenseAccountId,
    required this.settlementAccountId,
    required List<String> descriptorPatterns,
    this.isActive = true,
    this.updatedAt,
    required List<PaymentTerminalTerm> terms,
  })  : descriptorPatterns = List.unmodifiable(descriptorPatterns),
        terms = List.unmodifiable(terms);

  final String? id;
  final String providerCode;
  final String providerName;
  final String terminalName;
  final String? merchantReference;
  final String? clearingAccountId;
  final String? commissionExpenseAccountId;
  final String settlementAccountId;
  final List<String> descriptorPatterns;
  final bool isActive;
  final DateTime? updatedAt;
  final List<PaymentTerminalTerm> terms;

  factory PaymentTerminalProfile.fromJson(Map<String, dynamic> json) {
    final rawTerms = json['terms'];
    return PaymentTerminalProfile(
      id: json['id']?.toString(),
      providerCode: json['provider_code']?.toString() ?? '',
      providerName: json['provider_name']?.toString() ?? '',
      terminalName: json['terminal_name']?.toString() ?? '',
      merchantReference: json['merchant_reference']?.toString(),
      clearingAccountId: json['clearing_account_id']?.toString(),
      commissionExpenseAccountId:
          json['commission_expense_account_id']?.toString(),
      settlementAccountId: json['settlement_account_id']?.toString() ?? '',
      descriptorPatterns: (json['descriptor_patterns'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      isActive: json['is_active'] != false,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      terms: rawTerms is List
          ? rawTerms
              .whereType<Map>()
              .map((item) => PaymentTerminalTerm.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList(growable: false)
          : const [],
    );
  }

  PaymentTerminalTerm? termFor(PaymentCardInstrument instrument) {
    final matches = terms.where((term) => term.instrument == instrument);
    return matches.isEmpty ? null : matches.first;
  }

  Map<String, dynamic> toProfileRpcJson() => <String, dynamic>{
        if (id?.isNotEmpty == true) 'id': id,
        if (updatedAt != null)
          'expected_updated_at': updatedAt!.toIso8601String(),
        'provider_code': providerCode.trim().toLowerCase(),
        'provider_name': providerName.trim(),
        'terminal_name': terminalName.trim(),
        'merchant_reference': merchantReference?.trim(),
        if (clearingAccountId?.isNotEmpty == true)
          'clearing_account_id': clearingAccountId,
        if (commissionExpenseAccountId?.isNotEmpty == true)
          'commission_expense_account_id': commissionExpenseAccountId,
        'settlement_account_id': settlementAccountId,
        'descriptor_patterns': descriptorPatterns,
        'is_active': isActive,
      };
}
