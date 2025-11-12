// Invoice Parser API Service Client
// Calls the Python FastAPI service to parse invoices

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'invoice_parser_service.dart';

class InvoiceParserApiService {
  final String baseUrl;

  InvoiceParserApiService({this.baseUrl = 'http://localhost:8000'});

  /// Check if the API service is available
  Future<bool> isServiceAvailable() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/health')).timeout(
        const Duration(seconds: 2),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('⚠️ Invoice parser API not available: $e');
      return false;
    }
  }

  /// Parse invoice PDF using the API service
  /// Returns ParsedInvoice or null if parsing fails
  Future<ParsedInvoice?> parseInvoiceFromBytes(
    Uint8List pdfBytes,
    String filename,
  ) async {
    try {
      print('📤 Sending PDF to parser API ($filename, ${pdfBytes.length} bytes)');

      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/parse-invoice'),
      );

      request.files.add(http.MultipartFile.fromBytes(
        'file',
        pdfBytes,
        filename: filename,
      ));

      // Send request
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 10),
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          final invoiceData = data['data'];
          print('✅ API parsing successful');

          // Convert to ParsedInvoice
          final lineItems = (invoiceData['lineItems'] as List<dynamic>?)
                  ?.map((item) => ParsedLineItem(
                        description:
                            '[${item['code']}] ${item['description']}'.trim(),
                        quantity: (item['quantity'] as num?)?.toDouble(),
                        unitPrice: (item['unitPrice'] as num?)?.toDouble(),
                        total: (item['total'] as num?)?.toDouble(),
                      ))
                  .toList() ??
              [];

          return ParsedInvoice(
            rut: invoiceData['rut'] as String?,
            invoiceNumber: invoiceData['invoiceNumber'] as String?,
            date: invoiceData['date'] != null
                ? DateTime.parse(invoiceData['date'])
                : null,
            total: (invoiceData['total'] as num?)?.toDouble(),
            supplierName: invoiceData['supplier'] as String?,
            lineItems: lineItems,
            rawText: data['rawText'] as String? ?? '',
          );
        } else {
          print('❌ API returned error: ${data['error']}');
        }
      } else {
        print('❌ API request failed: ${response.statusCode}');
        print('Response: ${response.body}');
      }
    } catch (e) {
      print('❌ Error calling parser API: $e');
    }

    return null;
  }
}
