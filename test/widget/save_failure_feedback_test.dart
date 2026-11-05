import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/network/transport_failure.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';
import 'package:vinabike_erp/shared/widgets/save_failure_feedback.dart';

/// Un guardado que quedó en el equipo no se anuncia como «error».
void main() {
  Future<BuildContext> pump(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: Builder(builder: (context) {
          captured = context;
          return const SizedBox.expand();
        }),
      ),
    ));
    return captured;
  }

  ErpConnectionException kept() => TransportFailure(
        uri: _uri,
        cause: 'SocketException: Failed host lookup',
        notSent: true,
      ).toClientException(kept: true, willResend: true);

  testWidgets('lo que quedó en el equipo dice qué va a pasar, sin «Error»',
      (tester) async {
    final context = await pump(tester);
    showSaveFailure(context, kept(), failed: 'Error guardando cliente');
    await tester.pump();
    expect(find.textContaining('Error guardando cliente'), findsNothing);
    expect(find.textContaining('se envía solo cuando vuelva internet'),
        findsOneWidget);
    final roles = Theme.of(context).extension<VinabikeThemeRoles>()!;
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.backgroundColor, roles.warning.container);
  });

  testWidgets('un fallo de verdad conserva su prefijo y el tono de peligro',
      (tester) async {
    final context = await pump(tester);
    showSaveFailure(context, Exception('RUT inválido'),
        failed: 'Error guardando cliente');
    await tester.pump();
    expect(find.textContaining('Error guardando cliente: Exception: RUT'),
        findsOneWidget);
    final roles = Theme.of(context).extension<VinabikeThemeRoles>()!;
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.backgroundColor, roles.danger.accent);
  });

  test('el texto es el mismo fuera de un aviso', () {
    expect(
      describeSaveFailure(kept(), failed: 'No se pudo cobrar'),
      startsWith('Sin conexión: quedó en este equipo'),
    );
    expect(
      describeSaveFailure(StateError('x'), failed: 'No se pudo cobrar'),
      'No se pudo cobrar: Bad state: x',
    );
  });
}

final _uri = Uri.parse('https://demo.supabase.co/rest/v1/customers');
