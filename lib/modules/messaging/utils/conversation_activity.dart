import 'package:flutter/foundation.dart';

import '../models/conversation.dart';

class ConversationActivity {
  static const activeOnlyPreferenceKey = 'messaging_show_only_active_chats';
  static final ValueNotifier<bool> showOnlyActiveChats = ValueNotifier(true);

  /// Supplier conversation lifecycle and purchase lifecycle are independent.
  ///
  /// A received purchase stops being active work, but it must not hide a
  /// WhatsApp thread that contains real message activity. Standalone open
  /// threads remain active as before; a completed purchase by itself does not
  /// revive an old empty binding.
  static bool hasActiveSupplierWork({
    required Conversation? conversation,
    required Iterable<String?> purchaseInvoiceStatuses,
  }) {
    var hasPurchaseInvoices = false;
    for (final status in purchaseInvoiceStatuses) {
      hasPurchaseInvoices = true;
      if (isActivePurchaseInvoiceStatus(status)) return true;
    }

    if (conversation == null ||
        isClosedConversationStatus(conversation.status)) {
      return false;
    }
    if (!hasPurchaseInvoices) return true;

    return conversation.unreadCount > 0 ||
        conversation.lastMessageId != null ||
        conversation.lastMessageSequence != null ||
        (conversation.lastMessageContent?.trim().isNotEmpty ?? false) ||
        (conversation.lastMessageType?.trim().isNotEmpty ?? false) ||
        (conversation.lastMessageDirection?.trim().isNotEmpty ?? false);
  }

  static bool isActiveConversation(Conversation conversation) {
    if (conversation.isInternal) return true;
    if (isClosedConversationStatus(conversation.status)) return false;

    final hint = conversation.contextHint;
    if (hint == null) return true;

    if (hint.hasPurchaseInvoice) {
      return isActivePurchaseInvoiceStatus(hint.purchaseInvoiceStatus);
    }
    if (hint.hasSupplier) return true;
    if (hint.hasJob) return isActiveJobStatus(hint.jobStatus);
    if (hint.hasInvoice) return isActiveSalesInvoiceStatus(hint.invoiceStatus);

    return true;
  }

  static bool isClosedConversationStatus(String? status) {
    final value = normalizeStatus(status);
    return value == 'resolved' || value == 'rejected' || value == 'closed';
  }

  static bool isActivePurchaseInvoiceStatus(String? status) {
    final value = normalizeStatus(status);
    return value == 'draft' ||
        value == 'borrador' ||
        value == 'sent' ||
        value == 'enviada' ||
        value == 'enviado' ||
        value == 'confirmed' ||
        value == 'confirmada' ||
        value == 'confirmado';
  }

  static bool isActiveSalesInvoiceStatus(String? status) {
    final value = normalizeStatus(status);
    if (value.isEmpty) return true;
    return value != 'paid' &&
        value != 'pagada' &&
        value != 'pagado' &&
        value != 'cancelled' &&
        value != 'canceled' &&
        value != 'cancelada' &&
        value != 'cancelado' &&
        value != 'anulada' &&
        value != 'anulado' &&
        value != 'delivered' &&
        value != 'entregada' &&
        value != 'entregado';
  }

  static bool isActiveJobStatus(String? status) {
    final value = normalizeStatus(status);
    if (value.isEmpty) return true;
    return value != 'delivered' &&
        value != 'entregada' &&
        value != 'entregado' &&
        value != 'cancelled' &&
        value != 'canceled' &&
        value != 'cancelada' &&
        value != 'cancelado' &&
        value != 'anulada' &&
        value != 'anulado';
  }

  static String normalizeStatus(String? status) {
    final value = status?.trim().toLowerCase() ?? '';
    return value
        .replaceAll(RegExp(r'[áàäâãåā]'), 'a')
        .replaceAll(RegExp(r'[éèëêē]'), 'e')
        .replaceAll(RegExp(r'[íìïîī]'), 'i')
        .replaceAll(RegExp(r'[óòöôõøō]'), 'o')
        .replaceAll(RegExp(r'[úùüûū]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[\s_-]+'), ' ');
  }
}
