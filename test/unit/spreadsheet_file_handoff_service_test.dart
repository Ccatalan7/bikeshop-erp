import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/spreadsheets/models/spreadsheet_model.dart';
import 'package:vinabike_erp/modules/spreadsheets/services/spreadsheet_service.dart';
import 'package:vinabike_erp/shared/services/spreadsheet_file_handoff_service.dart';

void main() {
  test('imports already-loaded attachment bytes through the shared handoff',
      () async {
    final store = _RecordingSpreadsheetStore();

    final result = await SpreadsheetFileHandoffService.instance.importBytes(
      bytes: Uint8List.fromList('Producto,Cantidad\nCadena,2'.codeUnits),
      fileName: 'Productos.csv',
      store: store,
    );

    expect(result.id, 'created-sheet');
    expect(store.createdName, 'Productos');
    expect(store.createdRowCount, 2);
    expect(store.createdColCount, 2);
    expect(store.createdWorkbook?['sheetOrder'], ['sheet-1']);
    expect(
      (((store.createdWorkbook?['sheets'] as Map<String, dynamic>)['sheet-1']
          as Map<String, dynamic>)['cellData'] as Map<String, dynamic>)['1'],
      {
        '0': {'v': 'Cadena', 't': 1},
        '1': {'v': 2, 't': 2},
      },
    );
  });
}

class _RecordingSpreadsheetStore implements SpreadsheetStore {
  String? createdName;
  Map<String, dynamic>? createdWorkbook;
  int? createdRowCount;
  int? createdColCount;

  @override
  List<SpreadsheetModel> get spreadsheets => const [];

  @override
  Future<SpreadsheetModel> createSpreadsheet({
    String? name,
    Map<String, dynamic>? workbookData,
    int? rowCount,
    int? colCount,
  }) async {
    createdName = name;
    createdWorkbook = workbookData;
    createdRowCount = rowCount;
    createdColCount = colCount;
    return SpreadsheetModel(
      id: 'created-sheet',
      tenantId: 'tenant-1',
      name: name ?? 'Planilla sin título',
      rowCount: rowCount ?? 100,
      colCount: colCount ?? 26,
      workbookData: workbookData,
    );
  }

  @override
  Future<void> deleteSpreadsheet(String id) async {}

  @override
  Future<void> fetchSpreadsheets() async {}

  @override
  Future<List<CellModel>> loadCells(String spreadsheetId) async => const [];

  @override
  Future<void> renameSpreadsheet(String id, String newName) async {}

  @override
  Future<void> saveCells(
    String spreadsheetId,
    Map<String, CellData> dirtyCells,
  ) async {}

  @override
  Future<void> saveWorkbookData(
    String id,
    Map<String, dynamic> data,
  ) async {}

  @override
  Future<void> updateSpreadsheetMetadata(
    String id, {
    String? name,
    int? rowCount,
    int? colCount,
  }) async {}
}
