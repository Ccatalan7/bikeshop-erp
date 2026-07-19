import '../models/online_order_official_document.dart';
import '../models/order_communication.dart';
import 'online_order_official_document_service.dart';
import 'order_communication_service.dart';

class OnlineOrderEvidence {
  const OnlineOrderEvidence({
    required this.communications,
    required this.officialDocuments,
  });

  final List<OrderCommunication> communications;
  final List<OnlineOrderOfficialDocument> officialDocuments;
}

abstract interface class OrderEvidenceReader {
  Future<OnlineOrderEvidence> loadForOrder(String orderId);
}

/// One bounded, read-only load for the order inspector's evidence surface.
class OrderEvidenceService implements OrderEvidenceReader {
  OrderEvidenceService({
    OrderCommunicationService? communicationService,
    OnlineOrderOfficialDocumentService? officialDocumentService,
  })  : _communicationService =
            communicationService ?? OrderCommunicationService(),
        _officialDocumentService =
            officialDocumentService ?? OnlineOrderOfficialDocumentService();

  final OrderCommunicationService _communicationService;
  final OnlineOrderOfficialDocumentService _officialDocumentService;

  @override
  Future<OnlineOrderEvidence> loadForOrder(String orderId) async {
    final communicationsFuture = _communicationService.listForOrder(orderId);
    final officialDocumentsFuture =
        _officialDocumentService.listForOrder(orderId);

    return OnlineOrderEvidence(
      communications: await communicationsFuture,
      officialDocuments: await officialDocumentsFuture,
    );
  }
}
