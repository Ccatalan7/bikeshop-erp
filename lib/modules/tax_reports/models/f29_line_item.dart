/// Represents a single line item in the F29 declaration
/// For detailed tracking of each IVA/tax component
class F29LineItem {
  final String id;
  final String f29Id;
  final String tenantId;
  final int lineNumber; // Official F29 line number
  final String lineCode; // e.g., "IVA_DEBITO_VENTAS", "IVA_CREDITO_COMPRAS"
  final String description;
  final double amount;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  F29LineItem({
    required this.id,
    required this.f29Id,
    required this.tenantId,
    required this.lineNumber,
    required this.lineCode,
    required this.description,
    required this.amount,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory F29LineItem.fromJson(Map<String, dynamic> json) {
    return F29LineItem(
      id: json['id'] as String,
      f29Id: json['f29_id'] as String,
      tenantId: json['tenant_id'] as String,
      lineNumber: json['line_number'] as int,
      lineCode: json['line_code'] as String,
      description: json['description'] as String,
      amount: (json['amount'] as num).toDouble(),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'f29_id': f29Id,
      'tenant_id': tenantId,
      'line_number': lineNumber,
      'line_code': lineCode,
      'description': description,
      'amount': amount,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  F29LineItem copyWith({
    String? id,
    String? f29Id,
    String? tenantId,
    int? lineNumber,
    String? lineCode,
    String? description,
    double? amount,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return F29LineItem(
      id: id ?? this.id,
      f29Id: f29Id ?? this.f29Id,
      tenantId: tenantId ?? this.tenantId,
      lineNumber: lineNumber ?? this.lineNumber,
      lineCode: lineCode ?? this.lineCode,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Standard F29 line codes for reference
class F29LineCodes {
  static const String ivaDebitoVentas = 'IVA_DEBITO_VENTAS'; // Line 3
  static const String ivaDebitoExportaciones =
      'IVA_DEBITO_EXPORTACIONES'; // Line 5
  static const String ivaDebitoActivosFijos =
      'IVA_DEBITO_ACTIVOS_FIJOS'; // Line 7
  static const String ivaDebitoTotal = 'IVA_DEBITO_TOTAL'; // Line 15

  static const String ivaCreditoCompras = 'IVA_CREDITO_COMPRAS'; // Line 30
  static const String ivaCreditoImportaciones =
      'IVA_CREDITO_IMPORTACIONES'; // Line 31
  static const String ivaCreditoActivosFijos =
      'IVA_CREDITO_ACTIVOS_FIJOS'; // Line 32
  static const String ivaCreditoTotal = 'IVA_CREDITO_TOTAL'; // Line 40

  static const String ivaRemanente = 'IVA_REMANENTE'; // Line 35
  static const String ivaNeto = 'IVA_NETO'; // Line 43

  static const String ppmVentasNetas = 'PPM_VENTAS_NETAS'; // Line 50
  static const String ppmMonto = 'PPM_MONTO'; // Line 54

  static const String retencionSegunda =
      'RETENCION_SEGUNDA_CATEGORIA'; // Line 72
  static const String retencionHonorarios = 'RETENCION_HONORARIOS'; // Line 74
  static const String retencionArrendamiento =
      'RETENCION_ARRENDAMIENTO'; // Line 76

  static Map<String, String> get lineDescriptions => {
        ivaDebitoVentas: 'IVA Débito - Ventas',
        ivaDebitoExportaciones: 'IVA Débito - Exportaciones',
        ivaDebitoActivosFijos: 'IVA Débito - Activos Fijos',
        ivaDebitoTotal: 'Total IVA Débito',
        ivaCreditoCompras: 'IVA Crédito - Compras',
        ivaCreditoImportaciones: 'IVA Crédito - Importaciones',
        ivaCreditoActivosFijos: 'IVA Crédito - Activos Fijos',
        ivaCreditoTotal: 'Total IVA Crédito',
        ivaRemanente: 'Remanente IVA Crédito Mes Anterior',
        ivaNeto: 'IVA Neto a Pagar',
        ppmVentasNetas: 'PPM - Ventas Netas',
        ppmMonto: 'PPM - Monto a Pagar',
        retencionSegunda: 'Retención 2da Categoría (Empleados)',
        retencionHonorarios: 'Retención Honorarios (10%)',
        retencionArrendamiento: 'Retención Arrendamiento',
      };
}
