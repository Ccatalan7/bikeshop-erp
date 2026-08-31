import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_legacy_login_policy.dart';

/// La excepción de transporte legacy: estrecha, y que no se amplíe sola.
///
/// **El caso real, medido en el portal.** `portal.rburgos.cl` enlaza su ingreso
/// en las dos variantes —`http://portal.rburgos.cl/login/` y
/// `https://portal.rburgos.cl/login/`—, las dos responden 200 sin redirigirse
/// entre sí, y **las dos sirven el mismo formulario**, cuyo `action` apunta a
/// otro host por HTTP: `http://www.rburgos.cl/sitio/aplicaciones/
/// valida_ingreso.asp`. Lo legacy es el destino, no la página. Reescribir el
/// destino a HTTPS no sirve: ese endpoint resetea la conexión.
///
/// Lo que estas pruebas defienden no es que RBX funcione —eso lo demuestra la
/// app— sino que **el permiso no alcance a nada más**: ni a otra página del
/// mismo portal, ni a otro destino desde la página declarada.

const _paginaSegura = 'https://portal.rburgos.cl/login/';
const _paginaLegacy = 'http://portal.rburgos.cl/login/';
const _destino = 'http://www.rburgos.cl/sitio/aplicaciones/valida_ingreso.asp';

const _rbx = SupplierLegacyLoginTransport(
  canonicalOrigin: 'https://portal.rburgos.cl',
  pageUrls: <String>[_paginaSegura, _paginaLegacy],
  actionUrl: _destino,
);

const _declaracion = <String, Object?>{
  'page_urls': <String>[_paginaSegura, _paginaLegacy],
  'action_url': _destino,
};

String? _autoriza({
  String? loadedUrl = _paginaSegura,
  String? formAction = _destino,
  SupplierLegacyLoginTransport? transport = _rbx,
}) =>
    supplierLegacyLoginCanonicalOrigin(
      loadedUrl: loadedUrl,
      formAction: formAction,
      transport: transport,
    );

SupplierLegacyLoginTransport _conPaginas(List<String> paginas) =>
    SupplierLegacyLoginTransport(
      canonicalOrigin: 'https://portal.rburgos.cl',
      pageUrls: paginas,
      actionUrl: _destino,
    );

void main() {
  group('la declaración se busca por el origen canónico candidato', () {
    Future<SupplierLegacyLoginTransport?> buscar(
      String? loadedUrl, {
      Map<String, Object?>? declarado,
      void Function(String)? onOrigen,
    }) =>
        findSupplierLegacyLoginTransport(
          loadedUrl: loadedUrl,
          readDeclaration: (origen) async {
            onOrigen?.call(origen);
            return declarado;
          },
        );

    test('pregunta por https del mismo host, incluso desde la página http',
        () async {
      String? preguntado;
      await buscar(
        _paginaLegacy,
        declarado: _declaracion,
        onOrigen: (origen) => preguntado = origen,
      );
      expect(preguntado, 'https://portal.rburgos.cl');
    });

    test('sin registro no hay excepción', () async {
      expect(await buscar(_paginaSegura), isNull);
    });

    test('la página HTTPS declarada sí encuentra su transporte', () async {
      // **El caso que estaba roto.** El formulario legacy se sirve también por
      // HTTPS, y ésa es la URL que abre el runner. Cortar por el esquema de la
      // página dejaba la excepción inalcanzable justo en el camino normal.
      final encontrado = await buscar(_paginaSegura, declarado: _declaracion);
      expect(encontrado, isNotNull);
      expect(encontrado!.pageUrls, contains(_paginaSegura));
    });

    test('otra página del mismo portal declarado no obtiene el permiso',
        () async {
      // El permiso es de una URL, no de un host: si bastara el host, cualquier
      // otra página del portal habría podido mandar la credencial al destino
      // legacy.
      expect(
        await buscar(
          'https://portal.rburgos.cl/carro/',
          declarado: _declaracion,
        ),
        isNull,
      );
    });

    test('un esquema que no es web no consulta nada', () async {
      var consultas = 0;
      expect(
        await buscar('file:///login/', onOrigen: (_) => consultas++),
        isNull,
      );
      expect(consultas, 0);
    });
  });

  group('el par declarado autoriza, y devuelve el origen canónico', () {
    test('la credencial se resuelve contra HTTPS, nunca contra el inseguro',
        () {
      // Lo que devuelve es el origen registrado: tenant, proveedor, kind, key y
      // versión del secreto se buscan igual que siempre.
      expect(_autoriza(), 'https://portal.rburgos.cl');
      expect(_autoriza(loadedUrl: _paginaLegacy), 'https://portal.rburgos.cl');
    });

    test('y el envío automático queda autorizado con la misma condición', () {
      // Rellenar sin enviar dejaría la sesión a medias, y el envío automático
      // es el comportamiento que el dueño configuró para este portal.
      expect(
        supplierLegacyLoginMaySubmit(
          loadedUrl: _paginaSegura,
          formAction: _destino,
          transport: _rbx,
        ),
        isTrue,
      );
    });

    test('la ruta se compara exacta, sin normalizar la barra final', () {
      // `valida_ingreso.asp` y `valida_ingreso.asp/` son destinos distintos, y
      // el contrato promete extremos exactos. Tolerar la barra abría una
      // diferencia que nadie declaró.
      expect(_autoriza(loadedUrl: 'https://portal.rburgos.cl/login'), isNull);
      expect(_autoriza(formAction: '$_destino/'), isNull);
    });

    test('el esquema de la página también se compara exacto', () {
      // Declarar la HTTPS no autoriza la HTTP por parecido: cada variante que
      // de verdad se usa se declara.
      expect(
        _autoriza(
          loadedUrl: _paginaLegacy,
          transport: _conPaginas(const <String>[_paginaSegura]),
        ),
        isNull,
      );
      expect(
        _autoriza(
          loadedUrl: _paginaSegura,
          transport: _conPaginas(const <String>[_paginaLegacy]),
        ),
        isNull,
      );
    });
  });

  group('una autorización de media pieza no autoriza', () {
    test('sin destino declarado no hay excepción', () {
      expect(
        SupplierLegacyLoginTransport.fromProbe(
          canonicalOrigin: 'https://portal.rburgos.cl',
          declaration: const <String, Object?>{
            'page_urls': <String>[_paginaSegura],
          },
        ),
        isNull,
      );
    });

    test('sin ninguna página declarada tampoco', () {
      for (final declaracion in const <Map<String, Object?>>[
        <String, Object?>{'action_url': _destino},
        <String, Object?>{'page_urls': <String>[], 'action_url': _destino},
        <String, Object?>{'page_urls': _paginaSegura, 'action_url': _destino},
        <String, Object?>{
          'page_urls': <String>['  '],
          'action_url': _destino,
        },
      ]) {
        expect(
          SupplierLegacyLoginTransport.fromProbe(
            canonicalOrigin: 'https://portal.rburgos.cl',
            declaration: declaracion,
          ),
          isNull,
          reason: '$declaracion',
        );
      }
    });

    test('sin declaración, la política no existe', () {
      expect(_autoriza(transport: null), isNull);
    });

    test('la página correcta con OTRO destino se rechaza', () {
      // **El punto de todo.** Si sólo se mirara la página, el secreto podría
      // irse a cualquier parte.
      expect(
          _autoriza(formAction: 'http://evil.cl/valida_ingreso.asp'), isNull);
      expect(
        _autoriza(
          formAction: 'http://www.rburgos.cl/sitio/aplicaciones/otra.asp',
        ),
        isNull,
      );
    });

    test('ni siquiera un destino HTTPS distinto del declarado pasa', () {
      // La declaración no es «página segura → cualquier destino seguro»: es un
      // par cerrado. Un `action` HTTPS no declarado no es el par.
      expect(
        _autoriza(formAction: 'https://www.rburgos.cl/otra.asp'),
        isNull,
      );
    });

    test('el destino correcto en OTRA página se rechaza', () {
      expect(_autoriza(loadedUrl: 'https://portal.rburgos.cl/otra/'), isNull);
      expect(_autoriza(loadedUrl: 'https://evil.cl/login/'), isNull);
    });
  });

  group('el permiso no se amplía a otro host, ruta, esquema ni puerto', () {
    test('un subdominio parecido no es el host declarado', () {
      expect(_autoriza(loadedUrl: 'https://portal.rburgos.cl.evil.cl/login/'),
          isNull);
      expect(
          _autoriza(loadedUrl: 'https://sub.portal.rburgos.cl/login/'), isNull);
    });

    test('un puerto explícito distinto es otro servicio', () {
      expect(_autoriza(loadedUrl: 'https://portal.rburgos.cl:8443/login/'),
          isNull);
      expect(
          _autoriza(loadedUrl: 'http://portal.rburgos.cl:8080/login/'), isNull);
    });

    test('una query o un fragmento no son el formulario declarado', () {
      expect(
        _autoriza(loadedUrl: 'https://portal.rburgos.cl/login/?next=evil'),
        isNull,
      );
      expect(
          _autoriza(loadedUrl: 'https://portal.rburgos.cl/login/#x'), isNull);
    });

    test('una credencial incrustada en la URL se rechaza', () {
      expect(
        _autoriza(loadedUrl: 'https://a:b@portal.rburgos.cl/login/'),
        isNull,
      );
    });

    test('otros esquemas quedan fuera por no ser este transporte', () {
      for (final url in const <String>[
        'file:///login/',
        'data:text/html,<form>',
        'about:blank',
      ]) {
        expect(_autoriza(loadedUrl: url), isNull, reason: url);
      }
    });

    test('un binding torcido no habilita nada', () {
      // Si el origen registrado no es HTTPS, la excepción no nace: se degrada
      // un portal registrado, no se inventa uno.
      expect(
        _autoriza(
          transport: const SupplierLegacyLoginTransport(
            canonicalOrigin: 'http://portal.rburgos.cl',
            pageUrls: <String>[_paginaSegura],
            actionUrl: _destino,
          ),
        ),
        isNull,
      );
    });

    test('una declaración torcida tampoco autoriza', () {
      // **Los dos lados se validan.** Rechazar query, fragmento o credencial
      // incrustada sólo en el candidato dejaba que una declaración mal escrita
      // perdiera esos componentes al comparar y autorizara de más.
      for (final torcida in <SupplierLegacyLoginTransport>[
        _conPaginas(const <String>['https://portal.rburgos.cl/login/?x=1']),
        const SupplierLegacyLoginTransport(
          canonicalOrigin: 'https://portal.rburgos.cl',
          pageUrls: <String>[_paginaSegura],
          actionUrl: 'http://a:b@www.rburgos.cl/sitio/aplicaciones/v.asp',
        ),
        const SupplierLegacyLoginTransport(
          canonicalOrigin: 'https://portal.rburgos.cl',
          pageUrls: <String>[_paginaSegura],
          actionUrl: '$_destino#x',
        ),
        const SupplierLegacyLoginTransport(
          canonicalOrigin: 'https://portal.rburgos.cl',
          pageUrls: <String>[_paginaSegura],
          actionUrl: 'https://www.rburgos.cl/sitio/aplicaciones/v.asp',
        ),
      ]) {
        expect(
          _autoriza(transport: torcida),
          isNull,
          reason: 'declarado: ${torcida.pageUrls} → ${torcida.actionUrl}',
        );
      }
    });

    test('una página podrida no contamina a las buenas, ni al revés', () {
      // Una lista con una entrada inválida no autoriza esa entrada, y tampoco
      // invalida la que sí está bien escrita.
      final mixta = _conPaginas(const <String>[
        'javascript:alert(1)',
        _paginaSegura,
      ]);
      expect(_autoriza(transport: mixta), 'https://portal.rburgos.cl');
      expect(
        _autoriza(loadedUrl: 'javascript:alert(1)', transport: mixta),
        isNull,
      );
    });

    test('el binding tiene que ser un ORIGEN, no una URL cualquiera', () {
      for (final origen in const <String>[
        'https://portal.rburgos.cl/login/',
        'https://a:b@portal.rburgos.cl',
        'https://portal.rburgos.cl?x=1',
        'https://portal.rburgos.cl#x',
      ]) {
        expect(
          _autoriza(
            transport: SupplierLegacyLoginTransport(
              canonicalOrigin: origen,
              pageUrls: const <String>[_paginaSegura],
              actionUrl: _destino,
            ),
          ),
          isNull,
          reason: origen,
        );
      }
    });

    test('la página declarada tiene que ser del host del binding', () {
      // Una declaración que apunte a un host ajeno al registrado no puede
      // prestarle la credencial de ese proveedor.
      expect(
        _autoriza(
          loadedUrl: 'https://otro.cl/login/',
          transport: _conPaginas(const <String>['https://otro.cl/login/']),
        ),
        isNull,
      );
    });
  });
}
