import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/shared/services/auth_service.dart';

/// **Arranque en frío sin sesión: la app tiene que llegar al login.**
///
/// Defecto reproducido el 2026-08-03 en un Simulador de iPhone 17 Pro recién
/// creado, con red comprobada (`curl` a Supabase, 200 en 0,66 s): la app se
/// quedaba en «Cargando…» **indefinidamente** —6+ minutos, proceso vivo y
/// spinner girando— y nunca mostraba la pantalla de login.
///
/// La causa no era la red ni el arranque lento. `gotrue` abre la suscripción
/// emitiendo `AuthChangeEvent.initialSession`; el listener apagaba
/// `isInitializing` con ese evento pero **no notificaba**, porque
/// `initialSession` no está en la lista de eventos «significativos». El árbol
/// nunca se reconstruía, y `main.dart` sigue pintando «Cargando…» mientras esa
/// bandera esté arriba. En escritorio no se veía: ahí ya hay sesión guardada y
/// la bandera se apaga antes del primer build.
///
/// Estas pruebas fijan las dos mitades: que terminar de inicializar **avisa**,
/// y que el refresco de token **sigue sin avisar** —que es lo que el filtro
/// original protegía y no se puede perder al arreglar esto—.
void main() {
  group('arranque: terminar de inicializar siempre avisa', () {
    test('initialSession sin sesión avisa cuando veníamos inicializando', () {
      expect(
        AuthService.shouldNotifyAuthListeners(
          event: AuthChangeEvent.initialSession,
          wasInitializing: true,
        ),
        isTrue,
        reason: 'sin esto la app se queda en «Cargando…» y no llega al login',
      );
    });

    test('initialSession NO es significativo por sí solo', () {
      // Se afirma la causa, no sólo el síntoma: si algún día `initialSession`
      // entrara en la lista de significativos, esta prueba lo delata y el
      // arreglo de arriba deja de ser el que sostiene el arranque.
      expect(
        AuthService.authEventIsSignificant(AuthChangeEvent.initialSession),
        isFalse,
      );
    });

    test('cualquier evento que termine la inicialización avisa', () {
      for (final event in AuthChangeEvent.values) {
        expect(
          AuthService.shouldNotifyAuthListeners(
            event: event,
            wasInitializing: true,
          ),
          isTrue,
          reason: '$event dejó la app colgada en «Cargando…»',
        );
      }
    });
  });

  group('ya inicializada: el filtro que protege los formularios sigue', () {
    test('tokenRefreshed NO avisa', () {
      expect(
        AuthService.shouldNotifyAuthListeners(
          event: AuthChangeEvent.tokenRefreshed,
          wasInitializing: false,
        ),
        isFalse,
        reason: 'reconstruir por un refresco destruye un formulario a medias',
      );
    });

    test('initialSession tampoco avisa una vez inicializada', () {
      expect(
        AuthService.shouldNotifyAuthListeners(
          event: AuthChangeEvent.initialSession,
          wasInitializing: false,
        ),
        isFalse,
      );
    });

    test('entrar, salir, recuperar y actualizar SÍ avisan', () {
      for (final event in <AuthChangeEvent>[
        AuthChangeEvent.signedIn,
        AuthChangeEvent.signedOut,
        AuthChangeEvent.passwordRecovery,
        AuthChangeEvent.userUpdated,
      ]) {
        expect(
          AuthService.shouldNotifyAuthListeners(
            event: event,
            wasInitializing: false,
          ),
          isTrue,
          reason: '$event es un cambio real de sesión',
        );
      }
    });
  });
}
