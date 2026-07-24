String buildMailMessageRoute({
  required String providerId,
  required String messageId,
}) {
  return Uri(
    path: '/mail',
    queryParameters: {
      'providerId': providerId,
      'messageId': messageId,
    },
  ).toString();
}

String buildStoredFileRoute(String fileId) {
  return Uri(
    path: '/storage',
    queryParameters: {'file': fileId},
  ).toString();
}

/// Adds a one-use navigation identity to concrete notification destinations.
///
/// A user may close a modal/preview or select another row while the URL still
/// points at the prior notification target. GoRouter treats navigation to that
/// identical URI as a no-op, so concrete destinations receive a fresh request
/// identity on every click. Aggregate module routes remain stable.
String withNotificationOpenRequest(
  String route, {
  String? requestId,
}) {
  final uri = Uri.tryParse(route);
  if (uri == null || uri.hasScheme || !_hasConcreteNotificationTarget(uri)) {
    return route;
  }

  return uri.replace(
    queryParameters: {
      ...uri.queryParameters,
      'openRequest':
          requestId ?? DateTime.now().microsecondsSinceEpoch.toString(),
    },
  ).toString();
}

String resolveErpNotificationRoute(Map<String, dynamic> row) {
  final type = _text(row['type']);
  final entityType = _text(row['entity_type']);
  final data = row['data'] is Map
      ? Map<String, dynamic>.from(row['data'] as Map)
      : const <String, dynamic>{};
  final storedRoute = _text(row['route']);

  // Meta interaction URLs go through the dedicated trusted-host validator at
  // navigation time. Keep their exact stored destination intact here.
  if (type.startsWith('meta_') && storedRoute.isNotEmpty) {
    return storedRoute;
  }

  final entityId = _firstText([
    row['entity_id'],
    switch (type) {
      'mechanic_job_created' => data['job_id'],
      'sales_payment_received' => data['payment_id'],
      'online_order_created' => data['order_id'],
      'whatsapp_catalog_approved' => data['product_id'],
      _ => null,
    },
  ]);

  if ((type == 'mechanic_job_created' || entityType == 'mechanic_job') &&
      entityId != null) {
    return '/taller/pegas/${Uri.encodeComponent(entityId)}';
  }

  if ((type == 'sales_payment_received' || entityType == 'sales_payment') &&
      entityId != null) {
    return Uri(
      path: '/sales/payments',
      queryParameters: {'paymentId': entityId},
    ).toString();
  }

  if ((type == 'online_order_created' || entityType == 'online_order') &&
      entityId != null) {
    return Uri(
      path: '/website/orders',
      queryParameters: {'order': entityId},
    ).toString();
  }

  if ((type == 'whatsapp_catalog_approved' || entityType == 'product') &&
      entityId != null) {
    return '/inventory/products/${Uri.encodeComponent(entityId)}/edit';
  }

  final providerId = _firstText([
    data['provider_id'],
    data['provider'],
  ]);
  final messageId = _firstText([
    data['message_id'],
    entityType == 'mail_message' ? entityId : null,
  ]);
  if (providerId != null && messageId != null) {
    return buildMailMessageRoute(
      providerId: providerId,
      messageId: messageId,
    );
  }

  final conversationId = _firstText([
    data['conversation_id'],
    entityType == 'conversation' ? entityId : null,
  ]);
  if (conversationId != null) {
    return Uri(
      path: '/chat',
      queryParameters: {'conversation': conversationId},
    ).toString();
  }

  final fileId = _firstText([
    data['file_id'],
    entityType == 'app_file' ? entityId : null,
  ]);
  if (fileId != null) return buildStoredFileRoute(fileId);

  return storedRoute.isEmpty ? '/' : storedRoute;
}

bool _hasConcreteNotificationTarget(Uri uri) {
  const identityKeys = {
    'attendanceId',
    'conversation',
    'file',
    'messageId',
    'order',
    'paymentId',
  };
  if (uri.queryParameters.keys.any(identityKeys.contains)) return true;
  if (RegExp(r'^/taller/pegas/[^/]+$').hasMatch(uri.path)) return true;
  return RegExp(r'^/inventory/products/[^/]+/edit$').hasMatch(uri.path);
}

String _text(Object? value) => value?.toString().trim() ?? '';

String? _firstText(Iterable<Object?> values) {
  for (final value in values) {
    final text = _text(value);
    if (text.isNotEmpty) return text;
  }
  return null;
}
