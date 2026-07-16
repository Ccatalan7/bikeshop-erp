import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/spreadsheets/models/spreadsheet_model.dart';
import 'package:vinabike_erp/modules/spreadsheets/services/spreadsheet_service.dart';

void main() {
  group('SpreadsheetModel workbook snapshots', () {
    final workbook = <String, dynamic>{
      'id': 'workbook-1',
      'sheets': <String, dynamic>{
        'sheet-1': <String, dynamic>{'name': 'Sheet 1'},
      },
    };

    test('parses JSONB maps and encoded JSON objects', () {
      final fromMap = SpreadsheetModel.fromJson({
        'tenant_id': 'tenant-1',
        'workbook_data': workbook,
      });
      final fromString = SpreadsheetModel.fromJson({
        'tenant_id': 'tenant-1',
        'workbook_data': jsonEncode(workbook),
      });

      expect(fromMap.workbookData, workbook);
      expect(fromString.workbookData, workbook);
      expect(fromMap.toJson()['workbook_data'], workbook);
    });

    test('treats malformed or non-object workbook data as absent', () {
      final malformed = SpreadsheetModel.fromJson({
        'tenant_id': 'tenant-1',
        'workbook_data': '{not-json',
      });
      final listValue = SpreadsheetModel.fromJson({
        'tenant_id': 'tenant-1',
        'workbook_data': <dynamic>[],
      });

      expect(malformed.workbookData, isNull);
      expect(listValue.workbookData, isNull);
    });

    test('copyWith preserves, replaces, and explicitly clears workbook data',
        () {
      final original = SpreadsheetModel(
        tenantId: 'tenant-1',
        workbookData: workbook,
      );
      final replacement = <String, dynamic>{'id': 'workbook-2'};

      expect(original.copyWith(name: 'Renamed').workbookData, workbook);
      expect(
        original.copyWith(workbookData: replacement).workbookData,
        replacement,
      );
      expect(original.copyWith(workbookData: null).workbookData, isNull);
    });
  });

  group('SpreadsheetService failure handling', () {
    test('fetchSpreadsheets propagates failures and preserves prior state',
        () async {
      var shouldFail = false;
      final service = _serviceWithHandler((request) async {
        if (!shouldFail) {
          return _jsonResponse(
            200,
            [
              {
                'id': 'sheet-1',
                'tenant_id': 'tenant-1',
                'name': 'Existing sheet',
              },
            ],
          );
        }
        return _postgrestError();
      });

      await service.fetchSpreadsheets();
      shouldFail = true;

      await expectLater(
        service.fetchSpreadsheets(),
        throwsA(isA<PostgrestException>()),
      );
      expect(service.spreadsheets, hasLength(1));
      expect(service.spreadsheets.single.name, 'Existing sheet');
    });

    test('loadCells propagates a backend failure instead of returning empty',
        () async {
      final service = _serviceWithHandler((request) async {
        return _postgrestError();
      });

      await expectLater(
        service.loadCells('sheet-1'),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('classifies a missing workbook snapshot column as a schema rollout',
        () async {
      final service = _serviceWithHandler((request) async {
        return _jsonResponse(
          400,
          {
            'message':
                "Could not find the 'workbook_data' column of 'spreadsheets' in the schema cache",
            'code': 'PGRST204',
            'details': null,
            'hint': null,
          },
        );
      });

      await expectLater(
        service.saveWorkbookData('sheet-1', const <String, dynamic>{}),
        throwsA(
          isA<SpreadsheetSnapshotSchemaException>().having(
            (error) => error.cause.code,
            'PostgREST cause code',
            'PGRST204',
          ),
        ),
      );
    });

    test('partial save failure propagates and leaves every cell dirty',
        () async {
      final methods = <String>[];
      final service = _serviceWithHandler((request) async {
        methods.add(request.method);
        if (request.method == 'POST') {
          return http.Response('', 201);
        }
        return _postgrestError();
      });
      final valueCell =
          CellData(rawValue: '10', displayValue: '10', dirty: true);
      final clearedCell = CellData(dirty: true);

      await expectLater(
        service.saveCells(
          'sheet-1',
          {'0,0': valueCell, '1,1': clearedCell},
        ),
        throwsA(isA<PostgrestException>()),
      );

      expect(methods, ['POST', 'DELETE']);
      expect(valueCell.dirty, isTrue);
      expect(clearedCell.dirty, isTrue);
    });
  });

  group('SpreadsheetService safe saves', () {
    test('creates an imported workbook atomically with one insert', () async {
      late http.Request insertRequest;
      final service = _serviceWithHandler((request) async {
        insertRequest = request;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return _jsonResponse(201, {
          ...body,
          'tenant_id': 'tenant-1',
        });
      });
      final workbook = <String, dynamic>{
        'id': 'pending-import',
        'name': 'old-name',
        'appVersion': '0.25.1',
        'sheetOrder': <String>['sheet-1'],
        'sheets': <String, dynamic>{
          'sheet-1': <String, dynamic>{
            'id': 'sheet-1',
            'name': 'Ventas',
          },
        },
      };

      final created = await service.createSpreadsheet(
        name: 'Importada',
        workbookData: workbook,
        rowCount: 42,
        colCount: 12,
      );

      expect(insertRequest.method, 'POST');
      final body = jsonDecode(insertRequest.body) as Map<String, dynamic>;
      expect(body['id'], isA<String>().having((id) => id.length, 'length', 36));
      expect(body['name'], 'Importada');
      expect(body['row_count'], 42);
      expect(body['col_count'], 12);
      expect(body['workbook_data']['id'], body['id']);
      expect(body['workbook_data']['name'], 'Importada');
      expect(created.id, body['id']);
      expect(created.workbookData?['id'], body['id']);
      expect(service.spreadsheets.single.id, body['id']);
      expect(workbook['id'], 'pending-import');
    });

    test('saves workbook JSON and refreshes the ordered local cache', () async {
      final requests = <http.Request>[];
      final service = _serviceWithHandler((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return _jsonResponse(
            200,
            [
              {
                'id': 'sheet-1',
                'tenant_id': 'tenant-1',
                'name': 'First',
              },
              {
                'id': 'sheet-2',
                'tenant_id': 'tenant-1',
                'name': 'Second',
              },
            ],
          );
        }
        return http.Response('', 204);
      });
      await service.fetchSpreadsheets();
      final workbook = <String, dynamic>{
        'id': 'workbook-2',
        'sheets': <String, dynamic>{},
      };

      await service.saveWorkbookData('sheet-2', workbook);

      expect(requests, hasLength(2));
      final updateRequest = requests.last;
      expect(updateRequest.method, 'PATCH');
      expect(updateRequest.url.queryParameters['id'], 'eq.sheet-2');
      final requestBody =
          jsonDecode(updateRequest.body) as Map<String, dynamic>;
      expect(requestBody['workbook_data'], workbook);
      expect(requestBody['updated_at'], isA<String>());
      expect(service.spreadsheets.first.id, 'sheet-2');
      expect(service.spreadsheets.first.workbookData, workbook);
      expect(service.spreadsheets.first.updatedAt, isNotNull);
    });

    test('deletes cleared coordinates in one spreadsheet-scoped request',
        () async {
      final requests = <http.Request>[];
      final service = _serviceWithHandler((request) async {
        requests.add(request);
        return http.Response('', 204);
      });
      final first = CellData(dirty: true);
      final second = CellData(dirty: true);

      await service.saveCells(
        'sheet-1',
        {'2,3': first, '4,5': second},
      );

      expect(requests, hasLength(2));
      final deleteRequest = requests.first;
      expect(deleteRequest.method, 'DELETE');
      expect(
        deleteRequest.url.queryParameters['spreadsheet_id'],
        'eq.sheet-1',
      );
      expect(
        deleteRequest.url.queryParameters['or'],
        '(and(row_index.eq.2,col_index.eq.3),'
        'and(row_index.eq.4,col_index.eq.5))',
      );
      expect(requests.last.method, 'PATCH');
      expect(requests.last.url.queryParameters['id'], 'eq.sheet-1');
      expect(jsonDecode(requests.last.body), contains('updated_at'));
      expect(first.dirty, isFalse);
      expect(second.dirty, isFalse);
    });

    test('keeps a cell dirty when it changes during an in-flight save',
        () async {
      final requestStarted = Completer<void>();
      final response = Completer<http.Response>();
      final service = _serviceWithHandler((request) async {
        if (request.method == 'POST') {
          requestStarted.complete();
          return response.future;
        }
        return http.Response('', 204);
      });
      final cell =
          CellData(rawValue: 'before', displayValue: 'before', dirty: true);

      final save = service.saveCells('sheet-1', {'0,0': cell});
      await requestStarted.future;
      cell
        ..rawValue = 'after'
        ..displayValue = 'after'
        ..dirty = true;
      response.complete(http.Response('', 201));
      await save;

      expect(cell.dirty, isTrue);
    });

    test('rejects malformed coordinates without cleaning caller data',
        () async {
      var requested = false;
      final service = _serviceWithHandler((request) async {
        requested = true;
        return http.Response('', 201);
      });
      final cell = CellData(rawValue: 'value', dirty: true);

      await expectLater(
        service.saveCells('sheet-1', {'A1': cell}),
        throwsA(isA<FormatException>()),
      );

      expect(requested, isFalse);
      expect(cell.dirty, isTrue);
    });
  });
}

SpreadsheetService _serviceWithHandler(
  Future<http.Response> Function(http.Request request) handler,
) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-key',
    httpClient: MockClient((request) async {
      final response = await handler(request);
      return http.Response.bytes(
        response.bodyBytes,
        response.statusCode,
        headers: response.headers,
        request: request,
        reasonPhrase: response.reasonPhrase,
      );
    }),
  );
  addTearDown(client.dispose);
  return SpreadsheetService(supabase: client);
}

http.Response _jsonResponse(int statusCode, Object body) => http.Response(
      jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );

http.Response _postgrestError() => _jsonResponse(
      500,
      {
        'message': 'simulated database failure',
        'code': 'XX000',
        'details': null,
        'hint': null,
      },
    );
