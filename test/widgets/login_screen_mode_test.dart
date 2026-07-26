import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/screens/login_screen.dart';

void main() {
  testWidgets('switching from signup clears stale field validation state',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen()),
    );

    expect(
      find.byKey(const ValueKey('existing-account-google-login')),
      findsOneWidget,
    );

    final registerToggle = find.text('¿No tienes cuenta? Regístrate');
    await tester.ensureVisible(registerToggle);
    await tester.tap(registerToggle);
    await tester.pump();
    expect(find.byKey(const ValueKey('signup-shop-name')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('existing-account-google-login')),
      findsNothing,
    );

    final createAccount = find.text('Crear Cuenta');
    await tester.ensureVisible(createAccount);
    await tester.tap(createAccount);
    await tester.pump();
    expect(
      find.text('Por favor ingrese el nombre de su tienda'),
      findsOneWidget,
    );

    final loginToggle = find.text('¿Ya tienes cuenta? Inicia sesión');
    await tester.ensureVisible(loginToggle);
    await tester.tap(loginToggle);
    await tester.pump();

    expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('signup-shop-name')), findsNothing);
    expect(
      find.byKey(const ValueKey('existing-account-google-login')),
      findsOneWidget,
    );
    expect(
      find.text('Por favor ingrese el nombre de su tienda'),
      findsNothing,
    );
  });
}
