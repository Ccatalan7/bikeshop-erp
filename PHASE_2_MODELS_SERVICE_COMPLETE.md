# ✅ Phase 2 Complete: Flutter Models & Service Layer

**Status**: Models and service ready for UI implementation

---

## 📦 What Was Created

I've created **4 model files** and **1 service file** that transform SQL data into structured Dart objects ready for display.

---

## 📁 Files Created

### 1. `lib/modules/accounting/models/report_line.dart`

**Purpose**: Represents a single line in any financial report

**Key Features**:
- ✅ Hierarchical levels (0=total, 1=subtotal, 2=account, 3=subaccount)
- ✅ Bold/normal formatting control
- ✅ Show/hide amount control
- ✅ Parent-child relationships
- ✅ Factory methods for common line types

**Factory Methods**:
```dart
// Create a total line
ReportLine.total(name: 'TOTAL ACTIVOS', amount: 50000000);

// Create a subtotal line
ReportLine.subtotal(name: 'Activos Circulantes', amount: 25000000);

// Create an account line
ReportLine.account(
  code: '1101',
  name: 'Caja General',
  amount: 5000000,
);

// Create a blank separator
ReportLine.blank();
```

**Usage Example**:
```dart
final line = ReportLine.account(
  code: '1101',
  name: 'Caja General',
  amount: 5000000,
  category: 'currentAsset',
);

print(line.isAccount); // true
print(line.isBold);    // false
print(line.level);     // 2
```

---

### 2. `lib/modules/accounting/models/financial_report.dart`

**Purpose**: Base class for all financial reports + utilities

**Key Features**:
- ✅ Common properties (dates, company name, generated timestamp)
- ✅ Period description formatting (e.g., "Octubre 2025", "Q3 2025")
- ✅ Subtitle generation ("Al 31/12/2025" or "Del 01/10/2025 al 31/10/2025")
- ✅ Report type enum
- ✅ Period preset enum with date range calculation

**Report Types**:
```dart
enum ReportType {
  incomeStatement,  // Estado de Resultados
  balanceSheet,     // Balance General
  trialBalance,     // Balance de Comprobación
  cashFlow,         // Flujo de Efectivo (future)
}
```

**Period Presets**:
```dart
enum ReportPeriod {
  currentMonth,     // Mes Actual
  lastMonth,        // Mes Anterior
  currentQuarter,   // Trimestre Actual
  lastQuarter,      // Trimestre Anterior
  currentYear,      // Año Actual
  lastYear,         // Año Anterior
  yearToDate,       // Año a la Fecha
  custom,           // Personalizado
}

// Get date range for a preset
final range = ReportPeriod.currentMonth.getDateRange();
print(range.start); // 2025-10-01 00:00:00
print(range.end);   // 2025-10-31 23:59:59
```

**Usage Example**:
```dart
// Any report can use these utilities
class MyReport extends FinancialReport {
  @override
  String get title => 'Mi Reporte';
  
  @override
  List<ReportLine> get allLines => [];
}

final report = MyReport(
  startDate: DateTime(2025, 10, 1),
  endDate: DateTime(2025, 10, 31),
  companyName: 'Vinabike',
  generatedAt: DateTime.now(),
);

print(report.subtitle);         // "Del 01/10/2025 al 31/10/2025"
print(report.periodDescription); // "Octubre 2025"
```

---

### 3. `lib/modules/accounting/models/income_statement.dart`

**Purpose**: Income Statement (Estado de Resultados) model

**Structure**:
```
INGRESOS OPERACIONALES              $50,000,000
  4100 - Ventas de Productos          45,000,000
  4200 - Servicios                     5,000,000

COSTO DE VENTAS                    ($20,000,000)
  5100 - Costo de Productos          (18,000,000)
  5200 - Materiales                   (2,000,000)

UTILIDAD BRUTA                      $30,000,000

GASTOS OPERACIONALES               ($15,000,000)
  ...

UTILIDAD OPERACIONAL                $15,000,000

GASTOS FINANCIEROS                  ($1,000,000)
  ...

UTILIDAD ANTES DE IMPUESTOS         $14,000,000

IMPUESTOS                           ($3,780,000)
  8100 - Impuesto a la Renta          (3,780,000)

UTILIDAD NETA                       $10,220,000
```

**Properties**:
- ✅ Revenue sections (operatingIncome, nonOperatingIncome)
- ✅ Expense sections (costOfSales, operatingExpenses, financialExpenses, taxes)
- ✅ Calculated totals (grossProfit, operatingProfit, profitBeforeTax, netIncome)
- ✅ Financial ratios (grossMargin, operatingMargin, netMargin)

**Calculated Metrics**:
```dart
final statement = IncomeStatement(...);

print(statement.grossMargin);      // 60.0% (Gross Profit / Revenue)
print(statement.operatingMargin);  // 30.0% (Operating Profit / Revenue)
print(statement.netMargin);        // 20.44% (Net Income / Total Revenue)
print(statement.isProfitable);     // true (Net Income > 0)
```

**allLines Property**:
Returns complete list of formatted lines ready for display, including:
- Section headers (subtotals)
- Account details
- Blank separators
- Calculated totals
- Expenses shown as negatives

---

### 4. `lib/modules/accounting/models/balance_sheet.dart`

**Purpose**: Balance Sheet (Balance General) model

**Structure**:
```
ACTIVOS

Activos Circulantes                 $25,000,000
  1101 - Caja General                  5,000,000
  1110 - Banco                        10,000,000
  1130 - Cuentas por Cobrar            8,000,000
  1140 - Inventario                    2,000,000

Activos Fijos                       $15,000,000
  1210 - Maquinaria                   20,000,000
  1290 - Depreciación Acumulada       (5,000,000)

TOTAL ACTIVOS                       $40,000,000


PASIVOS

Pasivos Circulantes                 $10,000,000
  2110 - Proveedores                   8,000,000
  2160 - IVA Débito Fiscal             2,000,000

Pasivos Largo Plazo                  $5,000,000
  2210 - Préstamos Bancarios           5,000,000

TOTAL PASIVOS                       $15,000,000


PATRIMONIO

  3110 - Capital                      20,000,000
  3120 - Utilidades Retenidas          3,000,000
  3130 - Resultado del Ejercicio       2,000,000

TOTAL PATRIMONIO                    $25,000,000

TOTAL PASIVOS + PATRIMONIO          $40,000,000
```

**Properties**:
- ✅ Asset sections (currentAssets, fixedAssets, otherAssets)
- ✅ Liability sections (currentLiabilities, longTermLiabilities)
- ✅ Equity section
- ✅ Grand totals (totalAssets, totalLiabilities, totalEquity)

**Financial Ratios**:
```dart
final balanceSheet = BalanceSheet(...);

// Liquidity ratios
print(balanceSheet.currentRatio);      // 2.5 (Current Assets / Current Liabilities)
print(balanceSheet.quickRatio);        // 2.3 (excl. inventory)
print(balanceSheet.workingCapital);    // $15,000,000 (CA - CL)

// Leverage ratios
print(balanceSheet.debtToEquityRatio); // 0.6 (Liabilities / Equity)
print(balanceSheet.debtRatio);         // 0.375 (Liabilities / Assets)
print(balanceSheet.equityRatio);       // 0.625 (Equity / Assets)

// Profitability ratios (requires period net income)
print(balanceSheet.returnOnEquity);    // 40.88% (Net Income / Equity)
print(balanceSheet.returnOnAssets);    // 25.55% (Net Income / Assets)

// Validation
print(balanceSheet.isBalanced);        // true (Assets = Liabilities + Equity)
```

**Validation**:
- ✅ `isBalanced` - Checks if accounting equation holds (tolerance < $1 CLP)
- ✅ `accountingEquationDifference` - Shows exact difference

---

### 5. `lib/modules/accounting/services/financial_reports_service.dart`

**Purpose**: Service layer that calls SQL functions and builds report models

**Key Methods**:

#### `generateIncomeStatement(startDate, endDate)`
```dart
final service = FinancialReportsService(databaseService);

final incomeStatement = await service.generateIncomeStatement(
  startDate: DateTime(2025, 10, 1),
  endDate: DateTime(2025, 10, 31),
);

print(incomeStatement.netIncome);     // $10,220,000
print(incomeStatement.grossMargin);   // 60.0%
print(incomeStatement.allLines.length); // ~25 lines
```

**What it does**:
1. ✅ Calls `get_income_statement_data()` SQL function
2. ✅ Groups accounts by category (operatingIncome, costOfSales, etc.)
3. ✅ Calculates subtotals and totals
4. ✅ Computes margins and ratios
5. ✅ Returns structured `IncomeStatement` object

---

#### `generateBalanceSheet(asOfDate, periodStartDate)`
```dart
final balanceSheet = await service.generateBalanceSheet(
  asOfDate: DateTime(2025, 10, 31),
  periodStartDate: DateTime(2025, 10, 1), // Optional, for ROE/ROA
);

print(balanceSheet.totalAssets);     // $40,000,000
print(balanceSheet.isBalanced);      // true
print(balanceSheet.currentRatio);    // 2.5
```

**What it does**:
1. ✅ Calls `get_balance_sheet_data()` SQL function
2. ✅ Groups accounts by type (asset, liability, equity) and category
3. ✅ Calculates cumulative balances (from beginning of time to date)
4. ✅ Optionally calculates period net income for profitability ratios
5. ✅ Returns structured `BalanceSheet` object

---

#### `generateTrialBalance(startDate, endDate)`
```dart
final trialBalance = await service.generateTrialBalance(
  startDate: DateTime(2025, 10, 1),
  endDate: DateTime(2025, 10, 31),
);

// Returns List<ReportLine> with ALL accounts
for (final line in trialBalance) {
  print('${line.code} - ${line.name}: \$${line.amount}');
}
```

**What it does**:
1. ✅ Calls `get_trial_balance()` SQL function
2. ✅ Returns all accounts with activity in the period
3. ✅ Includes debits, credits, and balances

---

#### `verifyAccountingEquation(asOfDate)`
```dart
final verification = await service.verifyAccountingEquation(
  asOfDate: DateTime(2025, 10, 31),
);

print(verification['is_balanced']);      // true
print(verification['total_assets']);     // 40000000.0
print(verification['total_liabilities']); // 15000000.0
print(verification['total_equity']);     // 25000000.0
print(verification['difference']);       // 0.0 (should be < 1.00)
```

**What it does**:
1. ✅ Calls `verify_accounting_equation()` SQL function
2. ✅ Returns validation results
3. ✅ Used for debugging and audit trail

---

## 🔄 Service Integration

### Register in Provider

The service needs to be registered in `main.dart`:

```dart
// Add to providers list
ChangeNotifierProvider(
  create: (context) => FinancialReportsService(
    context.read<DatabaseService>(),
  ),
),
```

### Usage in Pages

```dart
// In a widget/page
final reportsService = Provider.of<FinancialReportsService>(context, listen: false);

// Generate report
final statement = await reportsService.generateIncomeStatement(
  startDate: selectedStartDate,
  endDate: selectedEndDate,
);

// Display
setState(() {
  _incomeStatement = statement;
});
```

---

## 🧪 Testing the Models

### Test Script (run in Flutter)

```dart
// Test Income Statement
final service = FinancialReportsService(databaseService);

final statement = await service.generateIncomeStatement(
  startDate: DateTime(2025, 10, 1),
  endDate: DateTime(2025, 10, 31),
);

print('=== INCOME STATEMENT ===');
print('Period: ${statement.periodDescription}');
print('Revenue: \$${statement.totalRevenue.toStringAsFixed(2)}');
print('Expenses: \$${statement.totalExpenses.toStringAsFixed(2)}');
print('Net Income: \$${statement.netIncome.toStringAsFixed(2)}');
print('Gross Margin: ${statement.grossMargin.toStringAsFixed(2)}%');
print('Net Margin: ${statement.netMargin.toStringAsFixed(2)}%');
print('Profitable: ${statement.isProfitable}');

// Test Balance Sheet
final balanceSheet = await service.generateBalanceSheet(
  asOfDate: DateTime(2025, 10, 31),
);

print('\n=== BALANCE SHEET ===');
print('As of: ${balanceSheet.subtitle}');
print('Assets: \$${balanceSheet.totalAssets.toStringAsFixed(2)}');
print('Liabilities: \$${balanceSheet.totalLiabilities.toStringAsFixed(2)}');
print('Equity: \$${balanceSheet.totalEquity.toStringAsFixed(2)}');
print('Balanced: ${balanceSheet.isBalanced}');
print('Current Ratio: ${balanceSheet.currentRatio.toStringAsFixed(2)}');
print('Debt/Equity: ${balanceSheet.debtToEquityRatio.toStringAsFixed(2)}');

// Test all lines
print('\n=== REPORT LINES ===');
for (final line in statement.allLines.take(10)) {
  final indent = '  ' * line.level;
  final bold = line.isBold ? '**' : '';
  print('$indent$bold${line.name}$bold: \$${line.amount.toStringAsFixed(2)}');
}
```

---

## 📊 Data Flow

### Income Statement Flow:
```
User selects date range
    ↓
FinancialReportsService.generateIncomeStatement()
    ↓
Calls SQL: get_income_statement_data(start, end)
    ↓
SQL returns: List<Map> with categories and amounts
    ↓
Service groups by category
    ↓
Service calculates subtotals, totals, margins
    ↓
Returns IncomeStatement object
    ↓
UI displays using incomeStatement.allLines
```

### Balance Sheet Flow:
```
User selects as-of date
    ↓
FinancialReportsService.generateBalanceSheet()
    ↓
Calls SQL: get_balance_sheet_data(asOfDate)
    ↓
SQL returns: List<Map> with cumulative balances
    ↓
Service groups by type and category
    ↓
Service calculates totals and ratios
    ↓
Returns BalanceSheet object
    ↓
UI displays using balanceSheet.allLines
```

---

## ✅ Checklist

- [x] ReportLine model with hierarchical levels
- [x] FinancialReport base class with utilities
- [x] IncomeStatement model with calculations
- [x] BalanceSheet model with financial ratios
- [x] FinancialReportsService with SQL integration
- [x] Period presets for quick date selection
- [x] Chilean date formatting (DD/MM/YYYY)
- [x] Negative amounts for expenses
- [x] Accounting equation validation
- [x] Company name configuration
- [x] Comprehensive documentation

**Ready for UI implementation!** 🎉

---

## 🚀 Next Step: Phase 3 (UI Pages)

Now we'll create:
1. **Income Statement Page** - Display with date selector and export
2. **Balance Sheet Page** - T-format layout with financial ratios
3. **Financial Reports Hub** - Dashboard with quick access
4. **Shared Widgets** - Header, line display, date range selector

**Would you like me to proceed with Phase 3 (UI implementation)?**
