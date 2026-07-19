import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/online_order_official_document.dart';

/// Read-only access to the append-only official-document ledger.
///
/// Recording, replacing and emailing fiscal evidence remain server-owned.
class OnlineOrderOfficialDocumentService {
  OnlineOrderOfficialDocumentService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<OnlineOrderOfficialDocument>> listForOrder(String orderId) async {
    final rawDocuments = await _client
        .from('online_order_official_documents')
        .select(
          'id,order_id,document_kind,provider,provider_document_id,'
          'payment_operation_id,fiscal_validity,document_type,folio,amount,'
          'currency,issued_at,artifact_url,artifact_sha256,status,recorded_at',
        )
        .eq('order_id', orderId)
        .order('issued_at', ascending: false);

    return List<Map<String, dynamic>>.from(rawDocuments)
        .map(OnlineOrderOfficialDocument.fromJson)
        .toList(growable: false);
  }
}
