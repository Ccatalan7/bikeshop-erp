import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/spreadsheets/services/spreadsheet_file_exporter.dart';
import 'package:vinabike_erp/modules/spreadsheets/services/spreadsheet_file_importer.dart';

void main() {
  group('SpreadsheetFileImporter XLSX', () {
    test('preserves sheets, values, formulas, styles, merges, and dimensions',
        () {
      final excel = Excel.createExcel();
      excel.rename('Sheet1', 'Ventas');
      final sales = excel['Ventas'];
      sales.updateCell(
        CellIndex.indexByString('A1'),
        TextCellValue('Producto'),
        cellStyle: CellStyle(
          bold: true,
          fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
          backgroundColorHex: ExcelColor.fromHexString('FF0F766E'),
          horizontalAlign: HorizontalAlign.Center,
          textWrapping: TextWrapping.WrapText,
          leftBorder: Border(
            borderStyle: BorderStyle.Thin,
            borderColorHex: ExcelColor.fromHexString('FF000000'),
          ),
        ),
      );
      sales.updateCell(
        CellIndex.indexByString('A2'),
        TextCellValue('Cadena'),
      );
      sales.updateCell(
        CellIndex.indexByString('B2'),
        const DoubleCellValue(12500.5),
        cellStyle: CellStyle(numberFormat: NumFormat.standard_4),
      );
      sales.updateCell(
        CellIndex.indexByString('B3'),
        const FormulaCellValue('=SUM(B2:B2)'),
      );
      sales.merge(
        CellIndex.indexByString('A4'),
        CellIndex.indexByString('B4'),
        customValue: TextCellValue('Total'),
      );
      sales.setColumnWidth(0, 18);
      sales.setRowHeight(0, 30);
      sales.cell(CellIndex.indexByString('Z1000')).cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString('FFF1F5F9'),
      );

      final summary = excel['Resumen'];
      summary.updateCell(
        CellIndex.indexByString('A1'),
        const BoolCellValue(true),
      );

      final encoded = excel.encode();
      expect(encoded, isNotNull);

      final imported = SpreadsheetFileImporter.decode(
        bytes: Uint8List.fromList(encoded!),
        fileName: 'ventas-julio.xlsx',
      );
      final snapshot = imported.workbookData;
      final sheets = snapshot['sheets'] as Map<String, dynamic>;
      final salesSnapshot = sheets['sheet-1'] as Map<String, dynamic>;
      final summarySnapshot = sheets['sheet-2'] as Map<String, dynamic>;
      final salesCells = salesSnapshot['cellData'] as Map<String, dynamic>;
      final header = (salesCells['0'] as Map<String, dynamic>)['0']
          as Map<String, dynamic>;
      final amount = (salesCells['1'] as Map<String, dynamic>)['1']
          as Map<String, dynamic>;
      final formula = (salesCells['2'] as Map<String, dynamic>)['1']
          as Map<String, dynamic>;

      expect(imported.name, 'ventas-julio');
      expect(imported.rowCount, 4);
      expect(imported.colCount, 2);
      expect(snapshot['sheetOrder'], ['sheet-1', 'sheet-2']);
      expect(salesSnapshot['name'], 'Ventas');
      expect(summarySnapshot['name'], 'Resumen');
      expect(header['v'], 'Producto');
      expect(header['t'], 1);
      expect(header['s'], containsPair('bl', 1));
      expect(header['s'], containsPair('tb', 3));
      expect(
        (header['s'] as Map<String, dynamic>)['bg'],
        {'rgb': '#0F766E'},
      );
      expect(amount['v'], 12500.5);
      expect(
        (amount['s'] as Map<String, dynamic>)['n'],
        {'pattern': '#,##0.00'},
      );
      expect(formula['f'], '=SUM(B2:B2)');
      expect(salesCells, isNot(contains('999')));
      expect(salesSnapshot['mergeData'], [
        {
          'startRow': 3,
          'endRow': 3,
          'startColumn': 0,
          'endColumn': 1,
        },
      ]);
      expect(
        ((salesSnapshot['columnData'] as Map<String, dynamic>)['0']
            as Map<String, dynamic>)['w'],
        131,
      );
      expect(
        ((salesSnapshot['rowData'] as Map<String, dynamic>)['0']
            as Map<String, dynamic>)['h'],
        40,
      );
      expect(
        ((summarySnapshot['cellData'] as Map<String, dynamic>)['0']
            as Map<String, dynamic>)['0'],
        {'v': true, 't': 3},
      );
    });
  });

  group('SpreadsheetFileImporter CSV', () {
    test('detects semicolon delimiters and parses numeric values', () {
      final imported = SpreadsheetFileImporter.decode(
        bytes: Uint8List.fromList(
          'Producto;Cantidad;Precio\nCadena;2;12500,5'.codeUnits,
        ),
        fileName: 'inventario.csv',
      );
      final sheet = (imported.workbookData['sheets']
          as Map<String, dynamic>)['sheet-1'] as Map<String, dynamic>;
      final cells = sheet['cellData'] as Map<String, dynamic>;

      expect(imported.name, 'inventario');
      expect(imported.rowCount, 2);
      expect(imported.colCount, 3);
      expect(
        (cells['1'] as Map<String, dynamic>)['1'],
        {'v': 2, 't': 2},
      );
      // A decimal comma inside a semicolon CSV remains text because the CSV
      // package intentionally does not reinterpret locale-specific numbers.
      expect(
        (cells['1'] as Map<String, dynamic>)['2'],
        {'v': '12500,5', 't': 1},
      );
    });

    test('rejects the legacy binary XLS format with a useful explanation', () {
      expect(
        () => SpreadsheetFileImporter.decode(
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'legacy.xls',
        ),
        throwsA(
          isA<UnsupportedSpreadsheetFileException>().having(
            (error) => error.toString(),
            'message',
            contains('Convierte el archivo a .xlsx'),
          ),
        ),
      );
    });
  });

  group('SpreadsheetFileExporter', () {
    test('round-trips edited XLSX values, formulas, sheets, and merges', () {
      final source = Excel.createExcel();
      source.rename('Sheet1', 'Productos');
      final products = source['Productos'];
      products.updateCell(
        CellIndex.indexByString('A1'),
        TextCellValue('Producto'),
        cellStyle: CellStyle(bold: true),
      );
      products.updateCell(
        CellIndex.indexByString('A2'),
        TextCellValue('Cadena'),
      );
      products.updateCell(
        CellIndex.indexByString('B2'),
        const DoubleCellValue(12500),
      );
      products.merge(
        CellIndex.indexByString('A3'),
        CellIndex.indexByString('B3'),
        customValue: TextCellValue('Total'),
      );
      source['Resumen'].updateCell(
        CellIndex.indexByString('A1'),
        const BoolCellValue(true),
      );

      final imported = SpreadsheetFileImporter.decode(
        bytes: Uint8List.fromList(source.encode()!),
        fileName: 'productos.xlsx',
      );
      final productsSnapshot =
          (imported.workbookData['sheets'] as Map)['sheet-1'] as Map;
      final cells = productsSnapshot['cellData'] as Map;
      (cells['1'] as Map)['0'] = <String, dynamic>{
        'v': 'Cadena editada',
        't': 1,
      };
      cells['3'] = <String, dynamic>{
        '1': <String, dynamic>{'f': '=SUM(B2:B2)'},
      };

      final encoded = SpreadsheetFileExporter.encode(
        workbookData: imported.workbookData,
        fileName: 'productos.xlsx',
      );
      final reopened = SpreadsheetFileImporter.decode(
        bytes: encoded,
        fileName: 'productos.xlsx',
      );
      final reopenedSheets = reopened.workbookData['sheets'] as Map;
      final reopenedProducts = reopenedSheets['sheet-1'] as Map;
      final reopenedCells = reopenedProducts['cellData'] as Map;

      expect(reopened.workbookData['sheetOrder'], ['sheet-1', 'sheet-2']);
      expect(reopenedProducts['name'], 'Productos');
      expect((reopenedSheets['sheet-2'] as Map)['name'], 'Resumen');
      expect((reopenedCells['1'] as Map)['0'],
          containsPair('v', 'Cadena editada'));
      expect(
          (reopenedCells['3'] as Map)['1'], containsPair('f', '=SUM(B2:B2)'));
      expect((reopenedCells['0'] as Map)['0']['s'], containsPair('bl', 1));
      expect(reopenedProducts['mergeData'], [
        {
          'startRow': 2,
          'endRow': 2,
          'startColumn': 0,
          'endColumn': 1,
        },
      ]);
    });

    test('encodes the first worksheet as CSV', () {
      final imported = SpreadsheetFileImporter.decode(
        bytes: Uint8List.fromList('Producto,Cantidad\nCadena,2'.codeUnits),
        fileName: 'productos.csv',
      );
      final encoded = SpreadsheetFileExporter.encode(
        workbookData: imported.workbookData,
        fileName: 'productos.csv',
      );

      expect(String.fromCharCodes(encoded), contains('Producto,Cantidad'));
      expect(String.fromCharCodes(encoded), contains('Cadena,2'));
    });
  });
}
