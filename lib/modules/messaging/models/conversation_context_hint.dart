class ConversationContextHint {
  final String? customerId;
  final String? customerName;
  final String? customerImageUrl;
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
  final String? supplierId;
  final String? supplierName;
  final String? supplierPhone;
  final String? purchaseInvoiceId;
  final String? purchaseInvoiceNumber;
  final String? purchaseInvoiceStatus;
  final double? purchaseInvoiceBalance;
  final double? purchaseInvoiceTotal;

  const ConversationContextHint({
    this.customerId,
    this.customerName,
    this.customerImageUrl,
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
    this.supplierId,
    this.supplierName,
    this.supplierPhone,
    this.purchaseInvoiceId,
    this.purchaseInvoiceNumber,
    this.purchaseInvoiceStatus,
    this.purchaseInvoiceBalance,
    this.purchaseInvoiceTotal,
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
      customerImageUrl: json['customer_image_url']?.toString(),
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
      supplierId: json['supplier_id']?.toString(),
      supplierName: json['supplier_name']?.toString(),
      supplierPhone: json['supplier_phone']?.toString(),
      purchaseInvoiceId: json['purchase_invoice_id']?.toString(),
      purchaseInvoiceNumber: json['purchase_invoice_number']?.toString(),
      purchaseInvoiceStatus: json['purchase_invoice_status']?.toString(),
      purchaseInvoiceBalance: parseDouble(json['purchase_invoice_balance']),
      purchaseInvoiceTotal: parseDouble(json['purchase_invoice_total']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (customerId != null) 'customer_id': customerId,
      if (customerName != null) 'customer_name': customerName,
      if (customerImageUrl != null) 'customer_image_url': customerImageUrl,
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
      if (supplierId != null) 'supplier_id': supplierId,
      if (supplierName != null) 'supplier_name': supplierName,
      if (supplierPhone != null) 'supplier_phone': supplierPhone,
      if (purchaseInvoiceId != null) 'purchase_invoice_id': purchaseInvoiceId,
      if (purchaseInvoiceNumber != null)
        'purchase_invoice_number': purchaseInvoiceNumber,
      if (purchaseInvoiceStatus != null)
        'purchase_invoice_status': purchaseInvoiceStatus,
      if (purchaseInvoiceBalance != null)
        'purchase_invoice_balance': purchaseInvoiceBalance,
      if (purchaseInvoiceTotal != null)
        'purchase_invoice_total': purchaseInvoiceTotal,
    };
  }

  bool get hasCustomer => customerId != null && customerId!.isNotEmpty;
  bool get hasSupplier => supplierId != null && supplierId!.isNotEmpty;
  bool get hasJob => jobId != null && jobId!.isNotEmpty;
  bool get hasInvoice => invoiceId != null && invoiceId!.isNotEmpty;
  bool get hasPurchaseInvoice =>
      purchaseInvoiceId != null && purchaseInvoiceId!.isNotEmpty;
  bool get hasOperationalContext =>
      hasJob || hasInvoice || hasPurchaseInvoice || hasSupplier;

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

  String? get supplierLabel {
    final name = supplierName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final phoneValue = supplierPhone?.trim() ?? phone?.trim();
    if (phoneValue != null && phoneValue.isNotEmpty) return phoneValue;
    return null;
  }

  String? get purchaseInvoiceLabel {
    final number = purchaseInvoiceNumber?.trim();
    if (number != null && number.isNotEmpty) return 'Compra $number';
    return hasPurchaseInvoice ? 'Compra vinculada' : null;
  }

  String? get effectiveContextType {
    if (primaryContextType != null && primaryContextType!.isNotEmpty) {
      return primaryContextType;
    }
    if (hasJob) return 'job';
    if (hasInvoice) return 'invoice';
    if (hasPurchaseInvoice) return 'purchase_invoice';
    if (hasSupplier) return 'supplier';
    if (hasCustomer) return 'customer';
    return null;
  }

  String? get effectiveContextId {
    if (primaryContextId != null && primaryContextId!.isNotEmpty) {
      return primaryContextId;
    }
    if (hasJob) return jobId;
    if (hasInvoice) return invoiceId;
    if (hasPurchaseInvoice) return purchaseInvoiceId;
    if (hasSupplier) return supplierId;
    if (hasCustomer) return customerId;
    return null;
  }
}
