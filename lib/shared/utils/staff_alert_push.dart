/// A push that is the only alert of its event inside the ERP.
///
/// Una nómina guardada suena en el teléfono de quien la paga (2026-11-21,
/// `push-notification` › `payroll_voucher_push.ts`). A diferencia de un pedido
/// web o una cotización, no deja un aviso durable en `erp_notifications`: el
/// índice único de esa tabla admite una fila por registro, y una fila para
/// todo el taller se la mostraría también a quien la guardó. Con la app en
/// primer plano, Android entrega el push a `onMessage` y no lo muestra; sin
/// esta regla, el shell lo ignoraba por no traer `conversation_id` y el dueño
/// no veía nada si justo tenía la app abierta.
class StaffAlertPush {
  const StaffAlertPush({
    required this.kind,
    required this.title,
    required this.body,
    required this.route,
    required this.presentationKey,
  });

  /// `kind` of the push, as `push-notification` sends it.
  final String kind;
  final String title;
  final String body;

  /// The ERP route the alert opens. Always inside the kind's own module.
  final String route;

  /// One presentation per record, whichever path sees it first.
  final String presentationKey;

  /// The kinds whose only alert is the push, with the module each may open.
  /// Web orders and quotes are not here: their durable ERP notification
  /// already shows with the app open, and listing them would announce them
  /// twice.
  static const Map<String, String> pushOnlyKindRoutes = <String, String>{
    'payroll_voucher': '/hr/payroll',
  };

  /// The alert carried by [data], or null when the push is not one of
  /// [pushOnlyKindRoutes] or does not say what to show or where to go.
  static StaffAlertPush? fromPushData(
    Map<String, dynamic> data, {
    String? notificationTitle,
    String? notificationBody,
  }) {
    final kind = _text(data['kind']);
    final modulePath = pushOnlyKindRoutes[kind];
    if (modulePath == null) return null;

    final route = _text(data['route']);
    final uri = Uri.tryParse(route);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
    if (uri.path != modulePath) return null;

    final title = _text(data['title']).isNotEmpty
        ? _text(data['title'])
        : _text(notificationTitle);
    if (title.isEmpty) return null;
    final body = _text(data['body']).isNotEmpty
        ? _text(data['body'])
        : _text(notificationBody);

    final recordId = _text(data['voucher_id']);
    return StaffAlertPush(
      kind: kind,
      title: title,
      body: body,
      route: route,
      presentationKey: 'push:$kind:${recordId.isEmpty ? route : recordId}',
    );
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';
}
