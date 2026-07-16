import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/spreadsheets/models/spreadsheet_model.dart';
import 'package:vinabike_erp/modules/spreadsheets/services/univer_workbook_adapter.dart';

void main() {
  test('keeps a persisted Univer snapshot and normalizes its identity', () {
    final persisted = <String, dynamic>{
      'id': 'old-id',
      'name': 'Old name',
      'appVersion': UniverWorkbookAdapter.engineVersion,
      'sheetOrder': <String>['custom-sheet'],
      'sheets': <String, dynamic>{
        'custom-sheet': <String, dynamic>{
          'id': 'custom-sheet',
          'name': 'Budget',
        },
      },
    };
    final sheet = SpreadsheetModel(
      id: 'sheet-id',
      tenantId: 'tenant-id',
      name: 'Current name',
      workbookData: persisted,
    );

    final snapshot = UniverWorkbookAdapter.createSnapshot(
      spreadsheet: sheet,
      legacyCells: const [],
    );

    expect(snapshot['id'], 'sheet-id');
    expect(snapshot['name'], 'Current name');
    expect(snapshot['locale'], 'esES');
    expect(snapshot['sheetOrder'], <String>['custom-sheet']);
    expect(persisted['id'], 'old-id');
  });

  test('rejects incomplete persisted workbook structures', () {
    expect(
      UniverWorkbookAdapter.isValidSnapshot(<String, dynamic>{
        'appVersion': UniverWorkbookAdapter.engineVersion,
        'sheetOrder': <String>['missing-sheet'],
        'sheets': <String, dynamic>{},
      }),
      isFalse,
    );
    expect(
      UniverWorkbookAdapter.isValidSnapshot(<String, dynamic>{
        'sheetOrder': <String>['sheet-1'],
        'sheets': <String, dynamic>{
          'sheet-1': <String, dynamic>{'id': 'sheet-1'},
        },
      }),
      isFalse,
    );
  });

  test('migrates legacy values, formulas, and basic formatting', () {
    final sheet = SpreadsheetModel(
      id: 'sheet-id',
      tenantId: 'tenant-id',
      name: 'Test',
      rowCount: 40,
      colCount: 10,
    );
    final snapshot = UniverWorkbookAdapter.createSnapshot(
      spreadsheet: sheet,
      legacyCells: [
        CellModel(
          spreadsheetId: 'sheet-id',
          row: 0,
          col: 0,
          rawValue: '10,5',
          bold: true,
        ),
        CellModel(
          spreadsheetId: 'sheet-id',
          row: 1,
          col: 1,
          rawValue: '=SI(A1>0;SUMA(A1:A2);0)',
          italic: true,
          textAlign: 'right',
        ),
      ],
    );

    final workbookSheets = snapshot['sheets'] as Map<String, dynamic>;
    final firstSheet = workbookSheets['sheet-1'] as Map<String, dynamic>;
    final cells = firstSheet['cellData'] as Map<String, dynamic>;
    final a1 =
        (cells['0'] as Map<String, dynamic>)['0'] as Map<String, dynamic>;
    final b2 =
        (cells['1'] as Map<String, dynamic>)['1'] as Map<String, dynamic>;

    expect(firstSheet['rowCount'], 100);
    expect(firstSheet['columnCount'], 26);
    expect(snapshot['locale'], 'esES');
    expect(a1, containsPair('v', 10.5));
    expect(a1['s'], containsPair('bl', 1));
    expect(b2['f'], '=IF(A1>0,SUM(A1:A2),0)');
    expect(b2['s'], containsPair('it', 1));
    expect(b2['s'], containsPair('ht', 3));
  });
}
