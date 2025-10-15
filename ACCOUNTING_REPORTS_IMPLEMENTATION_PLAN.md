# 📊 Plan de Implementación: Reportes Contables Profesionales

**Objetivo**: Implementar reportes contables profesionales y auditables para el mercado chileno, cumpliendo con estándares IFRS y normativas locales.

---

## 📋 Alcance Inicial

### Reportes a Implementar (Fase 1)

1. **Estado de Resultados** (Income Statement / P&L)
   - Ingresos Operacionales
   - Costo de Ventas
   - Margen Bruto
   - Gastos Operacionales
   - Resultado Operacional
   - Ingresos/Gastos No Operacionales
   - Resultado Antes de Impuestos
   - Impuestos
   - Resultado Neto

2. **Balance General** (Balance Sheet)
   - **ACTIVOS**
     - Activos Circulantes (Caja, Bancos, Cuentas por Cobrar, Inventario, IVA Crédito Fiscal)
     - Activos Fijos (Maquinaria, Vehículos, Depreciación)
     - Otros Activos
   - **PASIVOS**
     - Pasivos Circulantes (Proveedores, IVA Débito Fiscal, Préstamos CP)
     - Pasivos Largo Plazo
   - **PATRIMONIO**
     - Capital
     - Utilidades Retenidas
     - Resultado del Ejercicio
   - **Ecuación Fundamental**: Activos = Pasivos + Patrimonio

---

## 🏗️ Arquitectura de la Solución

### 1. Capa de Datos (Database Layer)

**Archivo**: `supabase/sql/core_schema.sql`

#### Funciones SQL a Crear:

```sql
-- 1. Obtener balance de cuenta por período
CREATE OR REPLACE FUNCTION get_account_balance(
  p_account_id UUID,
  p_start_date TIMESTAMP,
  p_end_date TIMESTAMP
) RETURNS NUMERIC;

-- 2. Obtener balances por tipo de cuenta
CREATE OR REPLACE FUNCTION get_balances_by_type(
  p_account_type TEXT, -- 'asset', 'liability', 'equity', 'income', 'expense'
  p_start_date TIMESTAMP,
  p_end_date TIMESTAMP
) RETURNS TABLE (
  account_id UUID,
  account_code TEXT,
  account_name TEXT,
  account_category TEXT,
  debit_total NUMERIC,
  credit_total NUMERIC,
  balance NUMERIC
);

-- 3. Obtener balance de prueba (Trial Balance)
CREATE OR REPLACE FUNCTION get_trial_balance(
  p_start_date TIMESTAMP,
  p_end_date TIMESTAMP
) RETURNS TABLE (
  account_code TEXT,
  account_name TEXT,
  account_type TEXT,
  debit_total NUMERIC,
  credit_total NUMERIC,
  balance NUMERIC
);

-- 4. Calcular resultado del ejercicio
CREATE OR REPLACE FUNCTION calculate_net_income(
  p_start_date TIMESTAMP,
  p_end_date TIMESTAMP
) RETURNS NUMERIC;
```

**Características**:
- Rendimiento optimizado con índices en `journal_lines.entry_id` y `journal_entries.entry_date`
- Manejo correcto de débitos/créditos según tipo de cuenta
- Filtrado por rango de fechas
- Agrupación por categoría de cuenta

---

### 2. Capa de Modelos (Flutter Models)

**Archivos a Crear**:

#### `lib/modules/accounting/models/financial_report.dart`

```dart
// Modelo base para reportes financieros
abstract class FinancialReport {
  final DateTime startDate;
  final DateTime endDate;
  final String companyName;
  final DateTime generatedAt;
  
  const FinancialReport({
    required this.startDate,
    required this.endDate,
    required this.companyName,
    required this.generatedAt,
  });
}

// Línea de reporte con jerarquía
class ReportLine {
  final String code;
  final String name;
  final double amount;
  final int level; // 0=total, 1=subtotal, 2=cuenta, 3=subcuenta
  final bool isBold;
  final bool showAmount;
  final String? parentCode;
  
  const ReportLine({
    required this.code,
    required this.name,
    required this.amount,
    this.level = 2,
    this.isBold = false,
    this.showAmount = true,
    this.parentCode,
  });
  
  bool get isTotal => level == 0;
  bool get isSubtotal => level == 1;
}
```

#### `lib/modules/accounting/models/income_statement.dart`

```dart
class IncomeStatement extends FinancialReport {
  final List<ReportLine> operatingIncome;      // Ingresos Operacionales
  final List<ReportLine> costOfSales;          // Costo de Ventas
  final double grossProfit;                     // Utilidad Bruta
  final List<ReportLine> operatingExpenses;    // Gastos Operacionales
  final double operatingIncome;                 // Resultado Operacional
  final List<ReportLine> nonOperatingIncome;   // Ingresos No Operacionales
  final List<ReportLine> financialExpenses;    // Gastos Financieros
  final double incomeBeforeTax;                 // Resultado Antes de Impuestos
  final List<ReportLine> taxes;                 // Impuestos
  final double netIncome;                       // Resultado Neto
  
  // Métricas adicionales
  double get grossMargin => grossProfit / totalRevenue;
  double get operatingMargin => operatingIncome / totalRevenue;
  double get netMargin => netIncome / totalRevenue;
}
```

#### `lib/modules/accounting/models/balance_sheet.dart`

```dart
class BalanceSheet extends FinancialReport {
  // ACTIVOS
  final List<ReportLine> currentAssets;        // Activos Circulantes
  final double totalCurrentAssets;
  final List<ReportLine> fixedAssets;          // Activos Fijos
  final double totalFixedAssets;
  final List<ReportLine> otherAssets;          // Otros Activos
  final double totalAssets;                     // Total Activos
  
  // PASIVOS
  final List<ReportLine> currentLiabilities;   // Pasivos Circulantes
  final double totalCurrentLiabilities;
  final List<ReportLine> longTermLiabilities;  // Pasivos Largo Plazo
  final double totalLiabilities;                // Total Pasivos
  
  // PATRIMONIO
  final List<ReportLine> equity;               // Capital y Utilidades Retenidas
  final double totalEquity;                     // Total Patrimonio
  
  // Validación
  bool get isBalanced => (totalAssets - (totalLiabilities + totalEquity)).abs() < 0.01;
  
  // Métricas financieras
  double get currentRatio => totalCurrentAssets / totalCurrentLiabilities;
  double get debtToEquityRatio => totalLiabilities / totalEquity;
  double get workingCapital => totalCurrentAssets - totalCurrentLiabilities;
}
```

---

### 3. Capa de Servicios (Business Logic)

**Archivos a Crear**:

#### `lib/modules/accounting/services/financial_reports_service.dart`

```dart
class FinancialReportsService extends ChangeNotifier {
  final DatabaseService _databaseService;
  final ChartOfAccountsService _chartOfAccountsService;
  
  // Generar Estado de Resultados
  Future<IncomeStatement> generateIncomeStatement({
    required DateTime startDate,
    required DateTime endDate,
    bool includeSubaccounts = true,
  }) async {
    // 1. Obtener balances por tipo de cuenta
    // 2. Agrupar por categoría (operatingIncome, costOfSales, etc.)
    // 3. Calcular subtotales y totales
    // 4. Retornar modelo estructurado
  }
  
  // Generar Balance General
  Future<BalanceSheet> generateBalanceSheet({
    required DateTime asOfDate,
    bool includeSubaccounts = true,
  }) async {
    // 1. Obtener saldos acumulados hasta la fecha
    // 2. Agrupar por tipo (asset, liability, equity)
    // 3. Validar ecuación contable
    // 4. Retornar modelo estructurado
  }
  
  // Balance de Comprobación (Trial Balance)
  Future<List<ReportLine>> generateTrialBalance({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    // Todas las cuentas con débitos, créditos y saldos
  }
  
  // Comparativo entre períodos
  Future<Map<String, dynamic>> generateComparative({
    required DateTime period1Start,
    required DateTime period1End,
    required DateTime period2Start,
    required DateTime period2End,
    required ReportType reportType,
  }) async {
    // Genera dos reportes y calcula variaciones
  }
}
```

---

### 4. Capa de Presentación (UI Pages)

**Archivos a Crear**:

#### `lib/modules/accounting/pages/income_statement_page.dart`

**Características**:
- Selector de rango de fechas (mes actual por defecto)
- Selector de período comparativo (opcional)
- Tabla jerárquica con niveles expandibles:
  ```
  INGRESOS OPERACIONALES                    $50,000,000
    4100 - Ventas de Productos                45,000,000
    4200 - Servicios de Mantenimiento          5,000,000
  
  COSTO DE VENTAS                          ($20,000,000)
    5100 - Costo de Productos Vendidos      (18,000,000)
    5200 - Materiales de Servicio            (2,000,000)
  
  UTILIDAD BRUTA                            $30,000,000
  Margen Bruto: 60.0%
  
  GASTOS OPERACIONALES                     ($15,000,000)
    ...
  ```
- Indicadores clave (Margen Bruto, Margen Operacional, Margen Neto)
- Gráfico de pastel (Ingresos vs Gastos)
- Botones de exportación (PDF, Excel)

#### `lib/modules/accounting/pages/balance_sheet_page.dart`

**Características**:
- Selector de fecha (último día del mes actual por defecto)
- Selector de período comparativo
- Tabla en formato T (Activos a la izquierda, Pasivos+Patrimonio a la derecha):
  ```
  ACTIVOS                              PASIVOS Y PATRIMONIO
  
  Activos Circulantes    $25,000,000   Pasivos Circulantes     $10,000,000
    Caja                   5,000,000     Proveedores              8,000,000
    Bancos                10,000,000     IVA Débito Fiscal        2,000,000
    Cuentas por Cobrar     8,000,000   
    Inventarios            2,000,000   Pasivos Largo Plazo      $5,000,000
                                         Préstamos Bancarios      5,000,000
  Activos Fijos         $15,000,000   
    Maquinaria            20,000,000   TOTAL PASIVOS           $15,000,000
    Depreciación Acum.    (5,000,000)  
                                       Patrimonio              $25,000,000
                                         Capital                20,000,000
                                         Utilidades Retenidas    3,000,000
                                         Resultado del Ejercicio 2,000,000
  
  TOTAL ACTIVOS         $40,000,000   TOTAL PASIVOS + PATRIM. $40,000,000
  ```
- Indicadores financieros (Liquidez, Endeudamiento, Capital de Trabajo)
- Validación visual de ecuación contable
- Botones de exportación

#### `lib/modules/accounting/pages/financial_reports_hub_page.dart`

Hub central con acceso a todos los reportes:
- Estado de Resultados
- Balance General
- Balance de Comprobación
- Flujo de Efectivo (futuro)
- Razones Financieras (futuro)

---

### 5. Widgets Compartidos

**Archivos a Crear**:

#### `lib/modules/accounting/widgets/report_header_widget.dart`
- Nombre de la empresa
- Nombre del reporte
- Período del reporte
- Fecha de generación
- RUT de la empresa (si está configurado)

#### `lib/modules/accounting/widgets/report_line_widget.dart`
- Renderiza una línea con el nivel de indentación correcto
- Maneja estilos (bold, subtotales, totales)
- Formateo de moneda chilena

#### `lib/modules/accounting/widgets/date_range_selector.dart`
- Selector de rango de fechas
- Presets comunes (Mes actual, Trimestre, Año, Año fiscal)
- Comparación con período anterior

#### `lib/modules/accounting/widgets/report_export_button.dart`
- Exportar a PDF (usando `pdf` package)
- Exportar a Excel (usando `excel` package)
- Compartir por email

---

## 🎨 Diseño UI/UX

### Principios de Diseño

1. **Profesionalismo**:
   - Tipografía clara y legible (Roboto Mono para números)
   - Espaciado consistente
   - Alineación correcta (texto a la izquierda, números a la derecha)
   - Sin colores llamativos (tonos grises, negro, azul corporativo)

2. **Jerarquía Visual**:
   - **Totales**: Negrita, fondo gris claro, línea superior e inferior
   - **Subtotales**: Negrita, línea inferior
   - **Cuentas**: Texto normal, indentadas
   - **Subcuentas**: Texto más pequeño, doble indentación

3. **Responsividad**:
   - Desktop: Dos columnas para Balance General
   - Mobile: Una columna, modo acordeón
   - Tablet: Adaptativo según orientación

4. **Accesibilidad**:
   - Soporte para modo oscuro
   - Tamaño de fuente ajustable
   - Alto contraste

---

## 📊 Estándares Contables Chilenos

### Agrupaciones de Cuentas

**Estado de Resultados**:
```
INGRESOS OPERACIONALES (4100-4999)
  - Ventas de productos
  - Servicios
  - Otros ingresos operacionales

COSTO DE VENTAS (5100-5999)
  - Costo de productos vendidos
  - Materiales y suministros

GASTOS DE ADMINISTRACIÓN (6100-6299)
  - Sueldos y salarios
  - Arriendos
  - Servicios básicos
  - Depreciación

GASTOS DE VENTAS (6300-6499)
  - Comisiones
  - Marketing y publicidad
  - Transporte

GASTOS FINANCIEROS (6500-6699)
  - Intereses bancarios
  - Comisiones bancarias

OTROS INGRESOS/EGRESOS (6700-6999)
  - Ingresos por inversiones
  - Pérdidas extraordinarias

IMPUESTOS (8100-8999)
  - Impuesto a la renta (1ª categoría: 27% en Chile 2025)
```

**Balance General**:
```
ACTIVOS CIRCULANTES (1100-1199)
  1101 - Caja General
  1110 - Banco Estado Cuenta Corriente
  1130 - Cuentas por Cobrar Comerciales
  1140 - Inventario de Mercaderías
  2150 - IVA Crédito Fiscal (activo)

ACTIVOS FIJOS (1200-1299)
  1210 - Maquinaria y Equipos
  1220 - Vehículos
  1230 - Muebles y Útiles
  1290 - Depreciación Acumulada (contra-cuenta)

PASIVOS CIRCULANTES (2100-2199)
  2110 - Proveedores Nacionales
  2120 - Préstamos Bancarios Corto Plazo
  2140 - Remuneraciones por Pagar
  2160 - IVA Débito Fiscal (pasivo)

PASIVOS LARGO PLAZO (2200-2299)
  2210 - Préstamos Bancarios Largo Plazo

PATRIMONIO (3100-3999)
  3110 - Capital
  3120 - Utilidades Retenidas
  3130 - Resultado del Ejercicio
```

### Tratamiento del IVA

En Chile, el IVA (19%) se maneja como:
- **IVA Crédito Fiscal** (2150): Activo circulante - IVA pagado en compras
- **IVA Débito Fiscal** (2160): Pasivo circulante - IVA cobrado en ventas
- **Diferencia mensual**: Se paga al SII o se arrastra como crédito

**Importante**: Los reportes deben mostrar montos NETOS (sin IVA) en ingresos y gastos, con el IVA en cuentas separadas.

---

## 🚀 Plan de Implementación

### Fase 1: Fundamentos (Semana 1)

1. **Día 1-2**: Funciones SQL en `core_schema.sql`
   - `get_account_balance()`
   - `get_balances_by_type()`
   - `get_trial_balance()`
   - Pruebas unitarias con datos reales

2. **Día 3**: Modelos Flutter
   - `financial_report.dart` (modelo base)
   - `income_statement.dart`
   - `balance_sheet.dart`
   - `report_line.dart`

3. **Día 4-5**: Servicio de Reportes
   - `financial_reports_service.dart`
   - Lógica de agrupación y cálculo
   - Pruebas con datos de prueba

### Fase 2: UI Estado de Resultados (Semana 2)

1. **Día 1-2**: Widgets compartidos
   - `report_header_widget.dart`
   - `report_line_widget.dart`
   - `date_range_selector.dart`

2. **Día 3-4**: Página de Estado de Resultados
   - `income_statement_page.dart`
   - Tabla jerárquica
   - Indicadores clave
   - Modo comparativo

3. **Día 5**: Integración y pruebas
   - Agregar a menú de Contabilidad
   - Pruebas con datos reales
   - Ajustes de formato

### Fase 3: UI Balance General (Semana 3)

1. **Día 1-3**: Página de Balance General
   - `balance_sheet_page.dart`
   - Layout en formato T
   - Validación de ecuación contable
   - Indicadores financieros

2. **Día 4**: Balance de Comprobación
   - `trial_balance_page.dart`
   - Lista completa de cuentas
   - Totales de débitos/créditos

3. **Día 5**: Hub de reportes
   - `financial_reports_hub_page.dart`
   - Dashboard con acceso rápido
   - Integración con navegación

### Fase 4: Exportación y Refinamiento (Semana 4)

1. **Día 1-2**: Exportación a PDF
   - Template profesional
   - Logo de empresa
   - Formato Chilean GAAP

2. **Día 3**: Exportación a Excel
   - Formato con fórmulas
   - Múltiples hojas (comparativos)

3. **Día 4-5**: Refinamiento
   - Optimización de rendimiento
   - Caché de reportes
   - Pruebas de auditoría
   - Documentación

---

## 📦 Dependencias Necesarias

Agregar a `pubspec.yaml`:

```yaml
dependencies:
  # Existing dependencies...
  
  # For PDF generation
  pdf: ^3.10.0
  printing: ^5.11.0
  
  # For Excel generation
  excel: ^4.0.0
  
  # For charts (optional, for visual insights)
  fl_chart: ^0.65.0
  
  # For date range picking
  syncfusion_flutter_datepicker: ^24.1.41
```

---

## 🧪 Criterios de Validación

### Auditoría Chilena

1. **Trazabilidad**:
   - Cada monto debe rastrearse hasta asientos contables
   - Detalle de cuentas debe coincidir con mayor contable

2. **Ecuación Contable**:
   - Activos = Pasivos + Patrimonio (tolerancia < 0.01 CLP)
   - Ingresos - Gastos = Resultado Neto

3. **Formato**:
   - Montos en CLP con separador de miles
   - Negativos entre paréntesis: ($1.234.567)
   - Fechas en formato DD/MM/YYYY

4. **Contenido Mínimo**:
   - RUT de la empresa
   - Período del reporte
   - Fecha de generación
   - Firma digital (futuro)

### Pruebas de Aceptación

1. Generar Estado de Resultados para mes actual → Debe mostrar ingresos y gastos
2. Generar Balance General al 31/12/2024 → Ecuación debe balancear
3. Comparar dos períodos → Variaciones deben calcularse correctamente
4. Exportar a PDF → Formato profesional, listo para imprimir
5. Exportar a Excel → Números editables, fórmulas funcionales

---

## 📚 Recursos Adicionales

- **Normas Contables Chile**: [SVS - Superintendencia de Valores y Seguros](https://www.svs.cl)
- **IFRS en Chile**: Normas aplicables desde 2009
- **SII (Servicio de Impuestos Internos)**: Formatos oficiales
- **Colegio de Contadores de Chile**: Mejores prácticas

---

## 🎯 Entregables

Al finalizar la implementación:

1. ✅ **Funciones SQL** en `core_schema.sql` (testeadas)
2. ✅ **Modelos Flutter** completos y documentados
3. ✅ **Servicio de reportes** con lógica de negocio
4. ✅ **3 páginas UI**:
   - Estado de Resultados
   - Balance General
   - Hub de Reportes
5. ✅ **Exportación PDF/Excel** funcional
6. ✅ **Integración** en menú de Contabilidad
7. ✅ **Documentación** de usuario (cómo leer los reportes)
8. ✅ **Tests** unitarios y de integración

---

## 📈 Mejoras Futuras (Post-MVP)

- **Flujo de Efectivo** (Cash Flow Statement)
- **Análisis de Razones Financieras** (Ratios)
- **Presupuesto vs Real** (Budget Comparison)
- **Consolidación Multiempresa**
- **Reportes Personalizados** (Report Builder)
- **Alertas Contables** (descuadres, anomalías)
- **Integración con SII** (timbraje electrónico, F29)
- **Gráficos Interactivos** (tendencias, análisis histórico)

---

**¿Estás de acuerdo con este plan? ¿Quieres que empiece con la Fase 1 (funciones SQL)?**
