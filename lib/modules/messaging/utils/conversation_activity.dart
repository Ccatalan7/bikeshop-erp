import 'package:flutter/foundation.dart';

import '../models/conversation.dart';

class ConversationActivity {
  static const activeOnlyPreferenceKey = 'messaging_show_only_active_chats';
  static final ValueNotifier<bool> showOnlyActiveChats = ValueNotifier(true);

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
