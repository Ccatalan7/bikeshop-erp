import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/staff_alert_push.dart';

void main() {
  // El push de la NOM-00048 tal como lo arma `payroll_voucher_push.ts`.
  Map<String, dynamic> payrollPush({
    String? kind = 'payroll_voucher',
    String? route = '/hr/payroll?voucher=7b94dcd4-7ff2-448e-8431-ebd0b5e29d99',
    String? title = 'Nómina lista para pagar',
    String? body =
        'Semana 46 · 09 – 15 nov · Braulio, Rodrigo (efectivo) y Vicente. '
            'La hizo Vicente.',
    String? voucherId = '7b94dcd4-7ff2-448e-8431-ebd0b5e29d99',
  }) {
    return <String, dynamic>{
      if (kind != null) 'kind': kind,
      if (route != null) 'route': route,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (voucherId != null) 'voucher_id': voucherId,
    };
  }

  test('a payroll push is presented with the app open and opens its week', () {
    final alert = StaffAlertPush.fromPushData(payrollPush());

    expect(alert, isNotNull);
    expect(alert!.kind, 'payroll_voucher');
    expect(alert.title, 'Nómina lista para pagar');
    expect(alert.body, startsWith('Semana 46 · 09 – 15 nov'));
    expect(
      alert.route,
      '/hr/payroll?voucher=7b94dcd4-7ff2-448e-8431-ebd0b5e29d99',
    );
    expect(
      alert.presentationKey,
      'push:payroll_voucher:7b94dcd4-7ff2-448e-8431-ebd0b5e29d99',
    );
  });

  test('orders, quotes and chats keep their own path', () {
    for (final kind in [
      'online_order',
      'customer_quote',
      'conversation_read'
    ]) {
      expect(
        StaffAlertPush.fromPushData(payrollPush(kind: kind)),
        isNull,
        reason: kind,
      );
    }
    expect(
      StaffAlertPush.fromPushData(<String, dynamic>{
        'conversation_id': 'c-1',
        'route': '/chat?conversation=c-1',
        'title': 'Nuevo mensaje',
      }),
      isNull,
    );
  });

  test('a payroll alert only opens payroll inside the ERP', () {
    for (final route in [
      'https://example.invalid/hr/payroll',
      '//example.invalid/hr/payroll',
      '/hr/employees',
      '/hr/payroll/reconcile',
      '',
    ]) {
      expect(
        StaffAlertPush.fromPushData(payrollPush(route: route)),
        isNull,
        reason: route,
      );
    }
    expect(StaffAlertPush.fromPushData(payrollPush(route: null)), isNull);
  });

  test('the text falls back to the notification, and needs a title', () {
    final fromNotification = StaffAlertPush.fromPushData(
      payrollPush(title: null, body: '  '),
      notificationTitle: 'Nómina lista para pagar',
      notificationBody: 'Semana 47 · 16 – 22 nov · Vicente.',
    );
    expect(fromNotification?.title, 'Nómina lista para pagar');
    expect(fromNotification?.body, 'Semana 47 · 16 – 22 nov · Vicente.');

    expect(StaffAlertPush.fromPushData(payrollPush(title: ' ')), isNull);
  });

  test('without the voucher id the route keeps one alert per payroll', () {
    final alert = StaffAlertPush.fromPushData(payrollPush(voucherId: null));
    expect(
      alert?.presentationKey,
      'push:payroll_voucher:/hr/payroll?voucher=7b94dcd4-7ff2-448e-8431-ebd0b5e29d99',
    );
  });
}
