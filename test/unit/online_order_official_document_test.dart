import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/online_order_official_document.dart';

void main() {
  group('OnlineOrderOfficialDocument', () {
    test('recognizes a verified Mercado Pago voucher valid as boleta', () {
      final document = OnlineOrderOfficialDocument.fromJson(
        _voucherJson(),
      );

      expect(document.isMercadoPagoVoucherValidAsBoleta, isTrue);
      expect(document.isOfficialChileanDte, isFalse);
      expect(
        document.displayLabel,
        'Voucher Mercado Pago válido como boleta',
      );
      expect(document.referenceLabel, 'Operación mp-payment-42');
      expect(
        document.verifiedArtifactUri,
        Uri.parse('https://documents.example.test/voucher.pdf?signature=safe'),
      );
    });

    test('labels an issued electronic boleta as a Chilean DTE', () {
      final document = OnlineOrderOfficialDocument.fromJson({
        ..._voucherJson(),
        'document_kind': 'tax_document',
        'provider': 'sii_provider',
        'provider_document_id': 'dte-88',
        'payment_operation_id': null,
        'fiscal_validity': 'official_chilean_dte',
        'document_type': 'boleta_electronica',
        'folio': '1234',
        'status': 'issued',
      });

      expect(document.isMercadoPagoVoucherValidAsBoleta, isFalse);
      expect(document.isOfficialChileanDte, isTrue);
      expect(document.isBoletaElectronica, isTrue);
      expect(document.displayLabel, 'Boleta electrónica (DTE)');
      expect(document.referenceLabel, 'Folio 1234');
      expect(document.verifiedArtifactUri, isNotNull);
    });

    test('opens a Mercado Pago receipt without presenting it as fiscal', () {
      final document = OnlineOrderOfficialDocument.fromJson({
        ..._voucherJson(),
        'document_kind': 'mercadopago_payment_voucher',
        'fiscal_validity': 'not_a_tax_document',
      });

      expect(document.isMercadoPagoPaymentReceipt, isTrue);
      expect(document.hasVerifiedFiscalShape, isFalse);
      expect(
        document.displayLabel,
        'Comprobante de pago Mercado Pago (no tributario)',
      );
      expect(document.verifiedArtifactUri, isNotNull);
    });

    test('fails closed for non-HTTPS, credentialed or unhashed artifacts', () {
      for (final override in <Map<String, Object?>>[
        {'artifact_url': 'http://documents.example.test/voucher.pdf'},
        {
          'artifact_url':
              'https://token:secret@documents.example.test/voucher.pdf',
        },
        {'artifact_url': 'https://documents.example.test/a bad voucher.pdf'},
        {'artifact_sha256': 'not-a-sha256'},
        {'status': 'pending'},
      ]) {
        final document = OnlineOrderOfficialDocument.fromJson({
          ..._voucherJson(),
          ...override,
        });
        expect(
          document.verifiedArtifactUri,
          isNull,
          reason:
              'Unsafe evidence must not create an actionable URL: $override',
        );
      }
    });
  });
}

Map<String, Object?> _voucherJson() => {
      'id': 'document-1',
      'order_id': 'order-1',
      'document_kind': 'payment_voucher',
      'provider': 'mercadopago',
      'provider_document_id': 'voucher-42',
      'payment_operation_id': 'mp-payment-42',
      'fiscal_validity': 'voucher_valid_as_boleta',
      'document_type': null,
      'folio': null,
      'amount': 12990,
      'currency': 'CLP',
      'issued_at': '2026-07-18T18:00:00.000Z',
      'artifact_url':
          'https://documents.example.test/voucher.pdf?signature=safe',
      'artifact_sha256': List.filled(64, 'a').join(),
      'status': 'approved',
      'recorded_at': '2026-07-18T18:00:02.000Z',
    };
