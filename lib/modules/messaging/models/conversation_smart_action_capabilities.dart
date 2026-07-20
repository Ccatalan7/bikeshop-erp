import 'conversation.dart';

/// Visibility contract for customer-facing interactive requests.
///
/// This is deliberately derived from immutable conversation capabilities and
/// operational context. UI surfaces can therefore hide invalid actions before
/// the user reaches their server-side validation, while the send command still
/// validates the canonical record as a second line of defence.
class ConversationSmartActionCapabilities {
  final bool isEligibleCustomerConversation;
  final bool supportsInteractiveTransport;
  final bool canRequestQuoteApproval;
  final bool canRequestPayment;
  final bool canRequestDeliveryConfirmation;
  final String? explanation;

  const ConversationSmartActionCapabilities({
    required this.isEligibleCustomerConversation,
    required this.supportsInteractiveTransport,
    required this.canRequestQuoteApproval,
    required this.canRequestPayment,
    required this.canRequestDeliveryConfirmation,
    required this.explanation,
  });

  factory ConversationSmartActionCapabilities.fromConversation(
    Conversation conversation,
  ) {
    final isEligibleCustomerConversation = conversation.isSupport &&
        conversation.isCustomerConversation &&
        !conversation.isInternal;

    if (!isEligibleCustomerConversation) {
      return const ConversationSmartActionCapabilities(
        isEligibleCustomerConversation: false,
        supportsInteractiveTransport: false,
        canRequestQuoteApproval: false,
        canRequestPayment: false,
        canRequestDeliveryConfirmation: false,
        explanation: null,
      );
    }

    if (!conversation.isWhatsApp) {
      return const ConversationSmartActionCapabilities(
        isEligibleCustomerConversation: true,
        supportsInteractiveTransport: false,
        canRequestQuoteApproval: false,
        canRequestPayment: false,
        canRequestDeliveryConfirmation: false,
        explanation:
            'Las solicitudes interactivas requieren abrir el WhatsApp del cliente.',
      );
    }

    final hint = conversation.contextHint;
    final hasJobContext =
        conversation.effectiveContextType == 'job' || hint?.hasJob == true;
    final hasInvoiceContext = conversation.effectiveContextType == 'invoice' ||
        hint?.hasInvoice == true;

    final explanation = switch ((hasJobContext, hasInvoiceContext)) {
      (false, false) =>
        'Vincula un trabajo para presupuesto o entrega, o una venta para solicitar pago.',
      (true, false) =>
        'La solicitud de pago aparecerá cuando exista una venta vinculada.',
      (false, true) =>
        'Presupuesto y entrega aparecerán cuando exista un trabajo vinculado.',
      _ => null,
    };

    return ConversationSmartActionCapabilities(
      isEligibleCustomerConversation: true,
      supportsInteractiveTransport: true,
      canRequestQuoteApproval: hasJobContext,
      canRequestPayment: hasInvoiceContext,
      canRequestDeliveryConfirmation: hasJobContext,
      explanation: explanation,
    );
  }

  bool get hasInteractiveActions =>
      canRequestQuoteApproval ||
      canRequestPayment ||
      canRequestDeliveryConfirmation;

  bool allows(String actionType) {
    return switch (actionType) {
      'approve_quote' => canRequestQuoteApproval,
      'pay_now' => canRequestPayment,
      'confirm_delivery' => canRequestDeliveryConfirmation,
      _ => false,
    };
  }
}
