class ResetConfiguration {
  final String? id;
  final String? tenantId;
  final String name;
  final String? description;
  final bool deleteSales;
  final bool deletePurchases;
  final bool deleteInventory;
  final bool deleteStockMovements;
  final bool deleteCustomers;
  final bool deleteSuppliers;
  final bool deleteAccounting;
  final bool deleteEmployees;
  final bool deleteMechanic;
  final bool deleteEcommerce;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ResetConfiguration({
    this.id,
    this.tenantId,
    required this.name,
    this.description,
    this.deleteSales = false,
    this.deletePurchases = false,
    this.deleteInventory = false,
    this.deleteStockMovements = false,
    this.deleteCustomers = false,
    this.deleteSuppliers = false,
    this.deleteAccounting = false,
    this.deleteEmployees = false,
    this.deleteMechanic = false,
    this.deleteEcommerce = false,
    this.createdAt,
    this.updatedAt,
  });

  factory ResetConfiguration.fromJson(Map<String, dynamic> json) {
    return ResetConfiguration(
      id: json['id'] as String?,
      tenantId: json['tenant_id'] as String?,
      name: json['name'] as String,
      description: json['description'] as String?,
      deleteSales: json['delete_sales'] as bool? ?? false,
      deletePurchases: json['delete_purchases'] as bool? ?? false,
      deleteInventory: json['delete_inventory'] as bool? ?? false,
      deleteStockMovements: json['delete_stock_movements'] as bool? ?? false,
      deleteCustomers: json['delete_customers'] as bool? ?? false,
      deleteSuppliers: json['delete_suppliers'] as bool? ?? false,
      deleteAccounting: json['delete_accounting'] as bool? ?? false,
      deleteEmployees: json['delete_employees'] as bool? ?? false,
      deleteMechanic: json['delete_mechanic'] as bool? ?? false,
      deleteEcommerce: json['delete_ecommerce'] as bool? ?? false,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String) 
          : null,
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'] as String) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (tenantId != null) 'tenant_id': tenantId,
      'name': name,
      if (description != null) 'description': description,
      'delete_sales': deleteSales,
      'delete_purchases': deletePurchases,
      'delete_inventory': deleteInventory,
      'delete_stock_movements': deleteStockMovements,
      'delete_customers': deleteCustomers,
      'delete_suppliers': deleteSuppliers,
      'delete_accounting': deleteAccounting,
      'delete_employees': deleteEmployees,
      'delete_mechanic': deleteMechanic,
      'delete_ecommerce': deleteEcommerce,
    };
  }

  ResetConfiguration copyWith({
    String? id,
    String? tenantId,
    String? name,
    String? description,
    bool? deleteSales,
    bool? deletePurchases,
    bool? deleteInventory,
    bool? deleteStockMovements,
    bool? deleteCustomers,
    bool? deleteSuppliers,
    bool? deleteAccounting,
    bool? deleteEmployees,
    bool? deleteMechanic,
    bool? deleteEcommerce,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ResetConfiguration(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      description: description ?? this.description,
      deleteSales: deleteSales ?? this.deleteSales,
      deletePurchases: deletePurchases ?? this.deletePurchases,
      deleteInventory: deleteInventory ?? this.deleteInventory,
      deleteStockMovements: deleteStockMovements ?? this.deleteStockMovements,
      deleteCustomers: deleteCustomers ?? this.deleteCustomers,
      deleteSuppliers: deleteSuppliers ?? this.deleteSuppliers,
      deleteAccounting: deleteAccounting ?? this.deleteAccounting,
      deleteEmployees: deleteEmployees ?? this.deleteEmployees,
      deleteMechanic: deleteMechanic ?? this.deleteMechanic,
      deleteEcommerce: deleteEcommerce ?? this.deleteEcommerce,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Get a list of selected deletion categories for display
  List<String> getSelectedCategories() {
    final List<String> categories = [];
    if (deleteSales) categories.add('Facturas de venta y pagos');
    if (deletePurchases) categories.add('Facturas de compra y pagos');
    if (deleteInventory) categories.add('Productos e inventario');
    if (deleteStockMovements) categories.add('Movimientos de stock');
    if (deleteCustomers) categories.add('Clientes');
    if (deleteSuppliers) categories.add('Proveedores');
    if (deleteAccounting) categories.add('Asientos contables');
    if (deleteEmployees) categories.add('Empleados y contratos');
    if (deleteMechanic) categories.add('Órdenes de mantención');
    if (deleteEcommerce) categories.add('Tienda online');
    return categories;
  }

  /// Check if any category is selected
  bool get hasSelections =>
      deleteSales ||
      deletePurchases ||
      deleteInventory ||
      deleteStockMovements ||
      deleteCustomers ||
      deleteSuppliers ||
      deleteAccounting ||
      deleteEmployees ||
      deleteMechanic ||
      deleteEcommerce;
}
