class F29Declaration {
  final String id;
  final String tenantId;
  final int periodMonth;
  final int periodYear;
  final String status; // draft, submitted, paid

  // IVA Section
  final double ivaDebitoVentas;
  final double ivaDebitoExportaciones;
  final double ivaDebitoActivosFijos;
  final double ivaDebitoTotal;
  final double ivaCreditoCompras;
  final double ivaCreditoImportaciones;
  final double ivaCreditoActivosFijos;
  final double ivaCreditoTotal;
  final double ivaRemanenteMesAnterior;
  final double ivaRemanenteMesSiguiente;
  final double ivaNeto;

  // PPM Section
  final double ppmVentasNetas;
  final double ppmTasaPorcentaje;
  final double ppmMonto;
  final double ppmRemanente;

  // Retenciones
  final double retencionSegundaCategoria;
  final double retencionHonorarios;
  final double retencionArrendamiento;

  // Otros Impuestos
  final double impuestoAdicional;
  final double impuestoEspecifico;

  // Totals
  final double totalAPagar;
  final double totalAFavor;

  // Filing tracking
  final String? folioNumber;
  final DateTime? filedAt;
  final DateTime? paidAt;
  final String? paymentReference;
  final DateTime? dueDate;

  // Metadata
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  F29Declaration({
    required this.id,
    required this.tenantId,
    required this.periodMonth,
    required this.periodYear,
    required this.status,
    this.ivaDebitoVentas = 0,
    this.ivaDebitoExportaciones = 0,
    this.ivaDebitoActivosFijos = 0,
    this.ivaDebitoTotal = 0,
    this.ivaCreditoCompras = 0,
    this.ivaCreditoImportaciones = 0,
    this.ivaCreditoActivosFijos = 0,
    this.ivaCreditoTotal = 0,
    this.ivaRemanenteMesAnterior = 0,
    this.ivaRemanenteMesSiguiente = 0,
    this.ivaNeto = 0,
    this.ppmVentasNetas = 0,
    this.ppmTasaPorcentaje = 1.0,
    this.ppmMonto = 0,
    this.ppmRemanente = 0,
    this.retencionSegundaCategoria = 0,
    this.retencionHonorarios = 0,
    this.retencionArrendamiento = 0,
    this.impuestoAdicional = 0,
    this.impuestoEspecifico = 0,
    this.totalAPagar = 0,
    this.totalAFavor = 0,
    this.folioNumber,
    this.filedAt,
    this.paidAt,
    this.paymentReference,
    this.dueDate,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory F29Declaration.fromJson(Map<String, dynamic> json) {
    return F29Declaration(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      periodMonth: json['period_month'] as int,
      periodYear: json['period_year'] as int,
      status: json['status'] as String,
      ivaDebitoVentas: (json['iva_debito_ventas'] as num?)?.toDouble() ?? 0,
      ivaDebitoExportaciones:
          (json['iva_debito_exportaciones'] as num?)?.toDouble() ?? 0,
      ivaDebitoActivosFijos:
          (json['iva_debito_activos_fijos'] as num?)?.toDouble() ?? 0,
      ivaDebitoTotal: (json['iva_debito_total'] as num?)?.toDouble() ?? 0,
      ivaCreditoCompras: (json['iva_credito_compras'] as num?)?.toDouble() ?? 0,
      ivaCreditoImportaciones:
          (json['iva_credito_importaciones'] as num?)?.toDouble() ?? 0,
      ivaCreditoActivosFijos:
          (json['iva_credito_activos_fijos'] as num?)?.toDouble() ?? 0,
      ivaCreditoTotal: (json['iva_credito_total'] as num?)?.toDouble() ?? 0,
      ivaRemanenteMesAnterior:
          (json['iva_remanente_mes_anterior'] as num?)?.toDouble() ?? 0,
      ivaRemanenteMesSiguiente:
          (json['iva_remanente_mes_siguiente'] as num?)?.toDouble() ?? 0,
      ivaNeto: (json['iva_neto'] as num?)?.toDouble() ?? 0,
      ppmVentasNetas: (json['ppm_ventas_netas'] as num?)?.toDouble() ?? 0,
      ppmTasaPorcentaje:
          (json['ppm_tasa_porcentaje'] as num?)?.toDouble() ?? 1.0,
      ppmMonto: (json['ppm_monto'] as num?)?.toDouble() ?? 0,
      ppmRemanente: (json['ppm_remanente'] as num?)?.toDouble() ?? 0,
      retencionSegundaCategoria:
          (json['retencion_segunda_categoria'] as num?)?.toDouble() ?? 0,
      retencionHonorarios:
          (json['retencion_honorarios'] as num?)?.toDouble() ?? 0,
      retencionArrendamiento:
          (json['retencion_arrendamiento'] as num?)?.toDouble() ?? 0,
      impuestoAdicional: (json['impuesto_adicional'] as num?)?.toDouble() ?? 0,
      impuestoEspecifico:
          (json['impuesto_especifico'] as num?)?.toDouble() ?? 0,
      totalAPagar: (json['total_a_pagar'] as num?)?.toDouble() ?? 0,
      totalAFavor: (json['total_a_favor'] as num?)?.toDouble() ?? 0,
      folioNumber: json['folio_number'] as String?,
      filedAt: json['filed_at'] != null
          ? DateTime.parse(json['filed_at'] as String)
          : null,
      paidAt: json['paid_at'] != null
          ? DateTime.parse(json['paid_at'] as String)
          : null,
      paymentReference: json['payment_reference'] as String?,
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'] as String)
          : null,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'period_month': periodMonth,
      'period_year': periodYear,
      'status': status,
      'iva_debito_ventas': ivaDebitoVentas,
      'iva_debito_exportaciones': ivaDebitoExportaciones,
      'iva_debito_activos_fijos': ivaDebitoActivosFijos,
      'iva_debito_total': ivaDebitoTotal,
      'iva_credito_compras': ivaCreditoCompras,
      'iva_credito_importaciones': ivaCreditoImportaciones,
      'iva_credito_activos_fijos': ivaCreditoActivosFijos,
      'iva_credito_total': ivaCreditoTotal,
      'iva_remanente_mes_anterior': ivaRemanenteMesAnterior,
      'iva_remanente_mes_siguiente': ivaRemanenteMesSiguiente,
      'iva_neto': ivaNeto,
      'ppm_ventas_netas': ppmVentasNetas,
      'ppm_tasa_porcentaje': ppmTasaPorcentaje,
      'ppm_monto': ppmMonto,
      'ppm_remanente': ppmRemanente,
      'retencion_segunda_categoria': retencionSegundaCategoria,
      'retencion_honorarios': retencionHonorarios,
      'retencion_arrendamiento': retencionArrendamiento,
      'impuesto_adicional': impuestoAdicional,
      'impuesto_especifico': impuestoEspecifico,
      'total_a_pagar': totalAPagar,
      'total_a_favor': totalAFavor,
      'folio_number': folioNumber,
      'filed_at': filedAt?.toIso8601String(),
      'paid_at': paidAt?.toIso8601String(),
      'payment_reference': paymentReference,
      'due_date': dueDate?.toIso8601String(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get periodDisplay => '$periodMonth/$periodYear';

  String get monthName {
    const months = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre'
    ];
    return months[periodMonth - 1];
  }

  String get statusDisplay {
    switch (status) {
      case 'draft':
        return 'Borrador';
      case 'submitted':
        return 'Presentado';
      case 'paid':
        return 'Pagado';
      default:
        return status;
    }
  }

  bool get isDraft => status == 'draft';
  bool get isSubmitted => status == 'submitted';
  bool get isPaid => status == 'paid';

  bool get hasBalance => ivaNeto != 0 || ppmMonto > 0;
  bool get hasDebt => totalAPagar > 0;
  bool get hasCredit => totalAFavor > 0;

  F29Declaration copyWith({
    String? id,
    String? tenantId,
    int? periodMonth,
    int? periodYear,
    String? status,
    double? ivaDebitoVentas,
    double? ivaDebitoExportaciones,
    double? ivaDebitoActivosFijos,
    double? ivaDebitoTotal,
    double? ivaCreditoCompras,
    double? ivaCreditoImportaciones,
    double? ivaCreditoActivosFijos,
    double? ivaCreditoTotal,
    double? ivaRemanenteMesAnterior,
    double? ivaRemanenteMesSiguiente,
    double? ivaNeto,
    double? ppmVentasNetas,
    double? ppmTasaPorcentaje,
    double? ppmMonto,
    double? ppmRemanente,
    double? retencionSegundaCategoria,
    double? retencionHonorarios,
    double? retencionArrendamiento,
    double? impuestoAdicional,
    double? impuestoEspecifico,
    double? totalAPagar,
    double? totalAFavor,
    String? folioNumber,
    DateTime? filedAt,
    DateTime? paidAt,
    String? paymentReference,
    DateTime? dueDate,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return F29Declaration(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      periodMonth: periodMonth ?? this.periodMonth,
      periodYear: periodYear ?? this.periodYear,
      status: status ?? this.status,
      ivaDebitoVentas: ivaDebitoVentas ?? this.ivaDebitoVentas,
      ivaDebitoExportaciones:
          ivaDebitoExportaciones ?? this.ivaDebitoExportaciones,
      ivaDebitoActivosFijos:
          ivaDebitoActivosFijos ?? this.ivaDebitoActivosFijos,
      ivaDebitoTotal: ivaDebitoTotal ?? this.ivaDebitoTotal,
      ivaCreditoCompras: ivaCreditoCompras ?? this.ivaCreditoCompras,
      ivaCreditoImportaciones:
          ivaCreditoImportaciones ?? this.ivaCreditoImportaciones,
      ivaCreditoActivosFijos:
          ivaCreditoActivosFijos ?? this.ivaCreditoActivosFijos,
      ivaCreditoTotal: ivaCreditoTotal ?? this.ivaCreditoTotal,
      ivaRemanenteMesAnterior:
          ivaRemanenteMesAnterior ?? this.ivaRemanenteMesAnterior,
      ivaRemanenteMesSiguiente:
          ivaRemanenteMesSiguiente ?? this.ivaRemanenteMesSiguiente,
      ivaNeto: ivaNeto ?? this.ivaNeto,
      ppmVentasNetas: ppmVentasNetas ?? this.ppmVentasNetas,
      ppmTasaPorcentaje: ppmTasaPorcentaje ?? this.ppmTasaPorcentaje,
      ppmMonto: ppmMonto ?? this.ppmMonto,
      ppmRemanente: ppmRemanente ?? this.ppmRemanente,
      retencionSegundaCategoria:
          retencionSegundaCategoria ?? this.retencionSegundaCategoria,
      retencionHonorarios: retencionHonorarios ?? this.retencionHonorarios,
      retencionArrendamiento:
          retencionArrendamiento ?? this.retencionArrendamiento,
      impuestoAdicional: impuestoAdicional ?? this.impuestoAdicional,
      impuestoEspecifico: impuestoEspecifico ?? this.impuestoEspecifico,
      totalAPagar: totalAPagar ?? this.totalAPagar,
      totalAFavor: totalAFavor ?? this.totalAFavor,
      folioNumber: folioNumber ?? this.folioNumber,
      filedAt: filedAt ?? this.filedAt,
      paidAt: paidAt ?? this.paidAt,
      paymentReference: paymentReference ?? this.paymentReference,
      dueDate: dueDate ?? this.dueDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
