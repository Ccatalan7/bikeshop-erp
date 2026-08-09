import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation_context_hint.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation_smart_action_capabilities.dart';

void main() {
  Conversation conversation({
    String type = 'support',
    String channel = 'whatsapp',
    String? counterpartyType = 'customer',
    String? contextType,
    String? contextId,
    ConversationContextHint? hint,
  }) {
    return Conversation(
      id: 'conversation-1',
      type: type,
      channel: channel,
      counterpartyType: counterpartyType,
      contextType: contextType,
      contextId: contextId,
      updatedAt: DateTime.utc(2026, 7, 19),
      participantIds: const [],
      contextHint: hint,
    );
  }

  group('operational context readers', () {
    test('supplier and purchase invoice are supported read-only contexts', () {
      expect(Conversation.supportsContextPanel('supplier'), isTrue);
      expect(Conversation.supportsContextPanel('purchase_invoice'), isTrue);

      final purchaseConversation = conversation(
        counterpartyType: 'supplier',
        hint: const ConversationContextHint(
          supplierId: 'supplier-1',
          purchaseInvoiceId: 'purchase-1',
        ),
      );

      expect(purchaseConversation.effectiveContextType, 'purchase_invoice');
      expect(purchaseConversation.effectiveContextId, 'purchase-1');
      expect(purchaseConversation.hasSupportedContextPanel, isTrue);
    });

    test('info manager surfaces derive neutral colors from the active theme',
        () {
      final source = File(
        'lib/modules/messaging/widgets/chat_window.dart',
      ).readAsStringSync();
      final managerSource = source.substring(
        source.indexOf('Widget _buildChatInfoPanel('),
        source.indexOf('List<_ChatAttachment> _collectChatAttachments('),
      );

      expect(managerSource, contains('surfaceContainerLowest'));
      expect(managerSource, contains('colorScheme.outlineVariant'));
      expect(managerSource, contains('colorScheme.onSurfaceVariant'));
      expect(managerSource, isNot(contains('Color(0xFFF8FAFC)')));
      expect(managerSource, isNot(contains('Color(0xFFE2E8F0)')));
    });

    test('context panel owns the canonical purchase and supplier routes', () {
      final source = File(
        'lib/modules/messaging/widgets/chat_context_panel.dart',
      ).readAsStringSync();

      expect(source, contains("route: '/purchases/\${purchase.id"));
      expect(source, contains("'/purchases/suppliers/\${supplier.id}'"));
      expect(
        source,
        isNot(contains("'/purchases/suppliers/\${supplier.id}/edit'")),
      );
      expect(source, contains('PurchaseInvoice purchase'));
      expect(source, contains('shared_supplier.Supplier supplier'));
    });
  });

  group('customer smart actions', () {
    test('supplier and internal conversations expose no customer actions', () {
      for (final candidate in [
        conversation(
          counterpartyType: 'supplier',
          contextType: 'purchase_invoice',
          contextId: 'purchase-1',
        ),
        conversation(
          type: 'internal',
          channel: 'internal',
          counterpartyType: 'internal',
          contextType: 'job',
          contextId: 'job-1',
        ),
      ]) {
        final capabilities =
            ConversationSmartActionCapabilities.fromConversation(candidate);
        expect(capabilities.isEligibleCustomerConversation, isFalse);
        expect(capabilities.hasInteractiveActions, isFalse);
      }
    });

    test('job context allows quotation and delivery, but not payment', () {
      final capabilities = ConversationSmartActionCapabilities.fromConversation(
        conversation(contextType: 'job', contextId: 'job-1'),
      );

      expect(capabilities.canRequestQuoteApproval, isTrue);
      expect(capabilities.canRequestDeliveryConfirmation, isTrue);
      expect(capabilities.canRequestPayment, isFalse);
      expect(capabilities.explanation, contains('venta vinculada'));
    });

    test('invoice context allows payment, but not workshop actions', () {
      final capabilities = ConversationSmartActionCapabilities.fromConversation(
        conversation(contextType: 'invoice', contextId: 'invoice-1'),
      );

      expect(capabilities.canRequestPayment, isTrue);
      expect(capabilities.canRequestQuoteApproval, isFalse);
      expect(capabilities.canRequestDeliveryConfirmation, isFalse);
      expect(capabilities.explanation, contains('trabajo vinculado'));
    });

    test('detected job plus invoice enables all valid customer requests', () {
      final capabilities = ConversationSmartActionCapabilities.fromConversation(
        conversation(
          contextType: 'job',
          contextId: 'job-1',
          hint: const ConversationContextHint(
            jobId: 'job-1',
            invoiceId: 'invoice-1',
          ),
        ),
      );

      expect(capabilities.hasInteractiveActions, isTrue);
      expect(capabilities.canRequestQuoteApproval, isTrue);
      expect(capabilities.canRequestPayment, isTrue);
      expect(capabilities.canRequestDeliveryConfirmation, isTrue);
      expect(capabilities.explanation, isNull);
    });

    test('non-WhatsApp channels never expose WhatsApp-only actions', () {
      for (final channel in [
        'website_portal',
        'instagram',
        'facebook_messenger',
      ]) {
        final capabilities =
            ConversationSmartActionCapabilities.fromConversation(
          conversation(
            channel: channel,
            contextType: 'job',
            contextId: 'job-1',
          ),
        );

        expect(capabilities.isEligibleCustomerConversation, isTrue);
        expect(capabilities.supportsInteractiveTransport, isFalse);
        expect(capabilities.hasInteractiveActions, isFalse);
        expect(
          capabilities.explanation,
          contains('requieren abrir el WhatsApp'),
        );
      }
    });

    test('shared chat UI gates rendering and sending with the same contract',
        () {
      final source = File(
        'lib/modules/messaging/widgets/chat_window.dart',
      ).readAsStringSync();

      expect(source, contains('smartActions.canRequestQuoteApproval'));
      expect(source, contains('smartActions.canRequestPayment'));
      expect(source, contains('smartActions.canRequestDeliveryConfirmation'));
      expect(source, contains('if (!smartActions.allows(actionType))'));
    });
  });
}
