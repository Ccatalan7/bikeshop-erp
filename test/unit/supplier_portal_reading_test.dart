import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_portal_reading.dart';

/// Las sondas reales, tal como quedaron configuradas tras reconocer los dos
/// portales el 2026-08-23. Las pruebas usan páginas reales abreviadas.
const rbx = SupplierPortalProbe(
  searchUrlTemplate:
      'http://www.rburgos.cl/sitio/aplicaciones/cat_cod_cf.asp'
      '?url=cat_cod_cf.asp&url1=cat_cod_sf.asp'
      '&Clasificacion2={code}&folio=0&paginaabsoluta=1',
  loggedOutPattern: 'INGRESA CON TUS DATOS|RUT CLIENTE|valida_ingreso',
  notFoundPattern: 'No hay ning[uú]n producto que mostrar',
  pricePattern: r'\$\s*([0-9][0-9.]*)',
);

const mkr = SupplierPortalProbe(
  searchUrlTemplate: 'https://mkr.cl/store/category/todos?q={code}&stock=1',
  loggedOutPattern: 'ACCESO CLIENTES|INGRESAR AL CATÁLOGO|RUT EMPRESA',
  notFoundPattern: 'Sin resultados|No encontramos productos para',
  pricePattern: r'\$\s*([0-9][0-9.]*)',
  stockPattern: r'Stock:\s*([0-9]+)',
  outOfStockPattern: r'Stock:\s*0\b',
);

SupplierPortalObservation observe(
  String code,
  String body, {
  bool password = false,
}) =>
    SupplierPortalObservation(
      code: code,
      url: 'https://ejemplo',
      bodyText: body,
      hasPasswordField: password,
    );

void main() {
  test('el código va codificado en la URL', () {
    // Un código con espacio o `&` rompería la consulta y devolvería la página
    // de otro producto sin avisar.
    expect(
      mkr.urlForCode('P 2341&x'),
      'https://mkr.cl/store/category/todos?q=P+2341%26x&stock=1',
    );
  });

  test('sin sesión nunca se informa un cero', () {
    // Es el error que haría comprar de más: el portal deslogueado responde
    // «sin resultados» y contarlo como falta de stock es inventar una compra.
    final leido = readSupplierPortal(
      observe('P2341', 'ACCESO CLIENTES · Ingresa con tu RUT EMPRESA'),
      mkr,
    );
    expect(leido.status, SupplierAvailabilityStatus.sessionExpired);
    expect(leido.stockQuantity, isNull);
    expect(leido.priceNet, isNull);
    expect(leido.carriesNumbers, isFalse);
  });

  test('un formulario de contraseña basta para saber que no hay sesión', () {
    final leido = readSupplierPortal(
      observe('P2341', 'Cod: P2341 · Stock: 36 · \$ 6.195', password: true),
      mkr,
    );
    expect(leido.status, SupplierAvailabilityStatus.sessionExpired);
  });

  test('MKR: lee la cantidad y el precio CON descuento', () {
    // La ficha muestra dos precios: «Antes $8.850» y «$6.195». Tomar el
    // primero informaría un precio 43% más alto que el real.
    final leido = readSupplierPortal(
      observe(
        'P2341',
        'Pedales VP 535 Urbano Cod: P2341 · Stock: 36 Antes \$ 8.850 \$ 6.195',
      ),
      mkr,
    );
    expect(leido.status, SupplierAvailabilityStatus.available);
    expect(leido.stockQuantity, 36);
    expect(leido.priceNet, 6195);
  });

  test('MKR: un cero LEÍDO sí es un cero demostrado', () {
    // Es el caso que el dueño corrigió: N1010 existe y está en cero. Con
    // `&stock=1` el portal lo muestra y lo dice.
    final leido = readSupplierPortal(
      observe(
        'N1010',
        'SIN STOCK Neumático Vuelta Semi Slick CB588 700x38c Negro '
            'Cod: N1010 · Stock: 0 No Disponible',
      ),
      mkr,
    );
    expect(leido.status, SupplierAvailabilityStatus.outOfStock);
    expect(leido.stockQuantity, 0);
  });

  test('«no encontrado» no lleva números y no afirma que no lo venda', () {
    final leido = readSupplierPortal(
      observe('N1010', 'Sin resultados · No encontramos productos para N1010'),
      mkr,
    );
    expect(leido.status, SupplierAvailabilityStatus.notFound);
    expect(leido.stockQuantity, isNull);
    expect(leido.priceNet, isNull);
  });

  test('RBX: sin cantidad publicada informa presencia y precio, no cero', () {
    // Nula no es cero. RBX no publica unidades, y decir «hay cero» con eso
    // sería inventar.
    final leido = readSupplierPortal(
      observe(
        '13166',
        '13166 CAMARA 29 X 1.75/2.20 V/AUTO 48mm EN CAJA ORNATE CHINA \$2.240',
      ),
      rbx,
    );
    expect(leido.status, SupplierAvailabilityStatus.available);
    expect(leido.priceNet, 2240);
    expect(leido.stockQuantity, isNull);
  });

  test('RBX: la firma de vacío es la del propio portal', () {
    final leido = readSupplierPortal(
      observe('99999999', 'No hay ningún producto que mostrar en su búsqueda'),
      rbx,
    );
    expect(leido.status, SupplierAvailabilityStatus.notFound);
  });

  test('el código se busca como palabra, no como trozo', () {
    // «1128» dentro de «11285» respondería por un producto que no es el que se
    // preguntó, con su precio y todo.
    final leido = readSupplierPortal(
      observe('1128', '11285 CAMARA 27,5 X 1.50/2.20 RBX CHINA \$2.350'),
      rbx,
    );
    expect(leido.status, SupplierAvailabilityStatus.notFound);
  });

  test('una página que la sonda no supo leer no se llama disponible', () {
    final leido = readSupplierPortal(
      observe('13166', 'Resultado 13166 pero sin precio ni cantidad legibles'),
      rbx,
    );
    expect(leido.status, SupplierAvailabilityStatus.unreadable);
    expect(leido.carriesNumbers, isFalse);
  });

  test('una expresión mal escrita no da por cierta una condición', () {
    // La configuración es editable en producción: un paréntesis suelto no
    // puede hacer pasar por «sin sesión» una página que sí la tenía.
    const rota = SupplierPortalProbe(
      searchUrlTemplate: 'https://x/{code}',
      loggedOutPattern: '((((',
      pricePattern: r'\$\s*([0-9][0-9.]*)',
    );
    final leido = readSupplierPortal(observe('9', '9 producto \$1.000'), rota);
    expect(leido.status, SupplierAvailabilityStatus.available);
    expect(leido.priceNet, 1000);
  });
}
