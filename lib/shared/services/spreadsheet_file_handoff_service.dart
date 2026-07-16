import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../modules/spreadsheets/models/spreadsheet_model.dart';
import '../../modules/spreadsheets/services/spreadsheet_file_exporter.dart';
import '../../modules/spreadsheets/services/spreadsheet_file_importer.dart';
import '../../modules/spreadsheets/services/spreadsheet_service.dart';
import '../../modules/storage/models/app_stored_file.dart';
import '../../modules/storage/services/app_file_storage_service.dart';

enum SpreadsheetFileImportStage { decoding, saving }

/// Shared Archivos-to-Planillas workflow used by every UI entry point.
class SpreadsheetFileHandoffService {
  SpreadsheetFileHandoffService._();

  static final instance = SpreadsheetFileHandoffService._();
  static const _backgroundDecodeThresholdBytes = 256 * 1024;

  AppFileStorageService get _fileStorage => AppFileStorageService.instance;

  bool supports(AppStoredFile file) =>
      SpreadsheetFileImporter.supportsExtension(file.extension);

  bool supportsFileName(String fileName) =>
      SpreadsheetFileImporter.supportsExtension(_extensionOf(fileName));

  Future<List<AppStoredFile>> listImportableFiles({int limit = 240}) async {
    final files = await _fileStorage.listFiles(limit: limit);
    return files.where(supports).toList(growable: false);
  }

  Future<SpreadsheetModel> importStoredFile({
    required AppStoredFile file,
    required SpreadsheetStore store,
  }) async {
    if (!supports(file)) {
      throw UnsupportedSpreadsheetFileException(file.extension);
    }

    final bytes = await _fileStorage.downloadFile(file);
    return importBytes(
      bytes: bytes,
      fileName: file.fileName,
      store: store,
    );
  }

  Future<SpreadsheetModel> importBytes({
    required Uint8List bytes,
    required String fileName,
    required SpreadsheetStore store,
    ValueChanged<SpreadsheetFileImportStage>? onStageChanged,
  }) async {
    final imported = await decodeBytes(
      bytes: bytes,
      fileName: fileName,
      onStageChanged: onStageChanged,
    );
    onStageChanged?.call(SpreadsheetFileImportStage.saving);

    // One insert owns the metadata and the complete workbook snapshot. A
    // failed insert cannot leave a blank half-imported workbook behind.
    return store.createSpreadsheet(
      name: imported.name,
      workbookData: imported.workbookData,
      rowCount: imported.rowCount,
      colCount: imported.colCount,
    );
  }

  /// Decodes XLSX/CSV bytes without creating a Planillas database record.
  ///
  /// The docked file runner uses this to mount the same Univer engine directly
  /// beside the active ERP module.
  Future<ImportedSpreadsheetWorkbook> decodeBytes({
    required Uint8List bytes,
    required String fileName,
    ValueChanged<SpreadsheetFileImportStage>? onStageChanged,
  }) async {
    final extension = _extensionOf(fileName);
    if (!SpreadsheetFileImporter.supportsExtension(extension)) {
      throw UnsupportedSpreadsheetFileException(extension);
    }

    final request = _StoredSpreadsheetDecodeRequest(
      bytes: bytes,
      fileName: fileName,
    );
    onStageChanged?.call(SpreadsheetFileImportStage.decoding);
    final String encodedImport;
    final decodeWatch = Stopwatch()..start();
    if (extension == 'csv' &&
        bytes.lengthInBytes <= _backgroundDecodeThresholdBytes) {
      // Compact CSV parsing is bounded and avoids paying isolate startup cost.
      await Future<void>.delayed(Duration.zero);
      encodedImport = _decodeStoredSpreadsheetToJson(request);
    } else {
      // XLSX decoding includes ZIP and XML parsing. Keep it off the UI isolate
      // even for compact files so native desktop remains responsive.
      encodedImport = await compute(
        _decodeStoredSpreadsheetToJson,
        request,
      );
    }
    _debugLogImport(
      'Decoded $fileName in ${decodeWatch.elapsedMilliseconds} ms',
    );
    final payload = jsonDecode(encodedImport);
    if (payload is! Map || payload['workbookData'] is! Map) {
      throw const FormatException(
        'El archivo no produjo una planilla válida.',
      );
    }
    final workbookData = Map<String, dynamic>.from(
      payload['workbookData'] as Map,
    );
    return ImportedSpreadsheetWorkbook(
      name: payload['name'] as String,
      workbookData: workbookData,
      rowCount: payload['rowCount'] as int,
      colCount: payload['colCount'] as int,
    );
  }

  /// Encodes a live Univer snapshot back into the original XLSX/CSV format.
  Future<Uint8List> encodeBytes({
    required Map<String, dynamic> workbookData,
    required String fileName,
  }) {
    return compute(
      _encodeStoredSpreadsheet,
      _StoredSpreadsheetEncodeRequest(
        workbookData: workbookData,
        fileName: fileName,
      ),
    );
  }

  String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }
}

void _debugLogImport(String message) {
  assert(() {
    debugPrint('[SpreadsheetImport] $message');
    return true;
  }());
}

class _StoredSpreadsheetDecodeRequest {
  const _StoredSpreadsheetDecodeRequest({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
}

class _StoredSpreadsheetEncodeRequest {
  const _StoredSpreadsheetEncodeRequest({
    required this.workbookData,
    required this.fileName,
  });

  final Map<String, dynamic> workbookData;
  final String fileName;
}

String _decodeStoredSpreadsheetToJson(
  _StoredSpreadsheetDecodeRequest request,
) {
  final imported = SpreadsheetFileImporter.decode(
    bytes: request.bytes,
    fileName: request.fileName,
  );

  // Returning tens of thousands of mutable cell maps from a worker isolate
  // forces Dart to recursively copy the whole object graph. Real supplier
  // workbooks made that handoff take minutes. A JSON string is immutable and
  // crosses the isolate boundary cheaply; the UI isolate only decodes it once.
  return jsonEncode(<String, dynamic>{
    'name': imported.name,
    'rowCount': imported.rowCount,
    'colCount': imported.colCount,
    'workbookData': imported.workbookData,
  });
}

Uint8List _encodeStoredSpreadsheet(
  _StoredSpreadsheetEncodeRequest request,
) {
  return SpreadsheetFileExporter.encode(
    workbookData: request.workbookData,
    fileName: request.fileName,
  );
}
