class ConversationContextHint {
  final String? customerId;
  final String? customerName;
  final String? phone;
  final String? primaryContextType;
  final String? primaryContextId;
  final String? jobId;
  final String? jobNumber;
  final String? jobStatus;
  final String? jobStatusColor;
  final String? bikeId;
  final String? bikeName;
  final String? invoiceId;
  final String? invoiceNumber;
  final String? invoiceStatus;
  final double? invoiceBalance;
  final double? invoiceTotal;

  const ConversationContextHint({
    this.customerId,
    this.customerName,
    this.phone,
    this.primaryContextType,
    this.primaryContextId,
    this.jobId,
    this.jobNumber,
    this.jobStatus,
    this.jobStatusColor,
    this.bikeId,
    this.bikeName,
    this.invoiceId,
    this.invoiceNumber,
    this.invoiceStatus,
    this.invoiceBalance,
    this.invoiceTotal,
  });

  factory ConversationContextHint.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ConversationContextHint();

    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    return ConversationContextHint(
      customerId: json['customer_id']?.toString(),
      customerName: json['customer_name']?.toString(),
      phone: json['phone']?.toString(),
      primaryContextType: json['primary_context_type']?.toString(),
      primaryContextId: json['primary_context_id']?.toString(),
      jobId: json['job_id']?.toString(),
      jobNumber: json['job_number']?.toString(),
      jobStatus: json['job_status']?.toString(),
      jobStatusColor: json['job_status_color']?.toString(),
      bikeId: json['bike_id']?.toString(),
      bikeName: json['bike_name']?.toString(),
      invoiceId: json['invoice_id']?.toString(),
      invoiceNumber: json['invoice_number']?.toString(),
      invoiceStatus: json['invoice_status']?.toString(),
      invoiceBalance: parseDouble(json['invoice_balance']),
      invoiceTotal: parseDouble(json['invoice_total']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (customerId != null) 'customer_id': customerId,
      if (customerName != null) 'customer_name': customerName,
      if (phone != null) 'phone': phone,
      if (primaryContextType != null)
        'primary_context_type': primaryContextType,
      if (primaryContextId != null) 'primary_context_id': primaryContextId,
      if (jobId != null) 'job_id': jobId,
      if (jobNumber != null) 'job_number': jobNumber,
      if (jobStatus != null) 'job_status': jobStatus,
      if (jobStatusColor != null) 'job_status_color': jobStatusColor,
      if (bikeId != null) 'bike_id': bikeId,
      if (bikeName != null) 'bike_name': bikeName,
      if (invoiceId != null) 'invoice_id': invoiceId,
      if (invoiceNumber != null) 'invoice_number': invoiceNumber,
      if (invoiceStatus != null) 'invoice_status': invoiceStatus,
      if (invoiceBalance != null) 'invoice_balance': invoiceBalance,
      if (invoiceTotal != null) 'invoice_total': invoiceTotal,
    };
  }

  bool get hasCustomer => customerId != null && customerId!.isNotEmpty;
  bool get hasJob => jobId != null && jobId!.isNotEmpty;
  bool get hasInvoice => invoiceId != null && invoiceId!.isNotEmpty;
  bool get hasOperationalContext => hasJob || hasInvoice;

  String? get customerLabel {
    final name = customerName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final phoneValue = phone?.trim();
    if (phoneValue != null && phoneValue.isNotEmpty) return phoneValue;
    return null;
  }

  String? get jobLabel {
    final number = jobNumber?.trim();
    if (number != null && number.isNotEmpty) return 'Trabajo $number';
    return hasJob ? 'Trabajo activo' : null;
  }

  String? get invoiceLabel {
    final number = invoiceNumber?.trim();
    if (number != null && number.isNotEmpty) return 'Factura $number';
    return hasInvoice ? 'Factura vinculada' : null;
  }

  String? get effectiveContextType {
    if (primaryContextType != null && primaryContextType!.isNotEmpty) {
      return primaryContextType;
    }
    if (hasJob) return 'job';
    if (hasInvoice) return 'invoice';
    if (hasCustomer) return 'customer';
    return null;
  }

  String? get effectiveContextId {
    if (primaryContextId != null && primaryContextId!.isNotEmpty) {
      return primaryContextId;
    }
    if (hasJob) return jobId;
    if (hasInvoice) return invoiceId;
    if (hasCustomer) return customerId;
    return null;
  }
}
