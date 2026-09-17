import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_engine.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_entry.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_query.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_usage.dart';
import 'package:vinabike_erp/shared/utils/bike_finder_search.dart';

/// Los identificadores de este archivo son los **formatos reales de
/// producción**, leídos el 2026-09-17: `FV-01035`, `PG-00570` y SKU de cinco
/// dígitos sin prefijo. Una fixture con formatos inventados prueba el
/// algoritmo y no el producto.
void main() {
  final now = DateTime.utc(2026, 9, 17, 12);

  GlobalSearchEntry menu(
    String title,
    String module,
    String route, {
    bool frontDoor = false,
    String? toolKey,
  }) {
    Set<String> words(String value) => normalizeBikeFinderSearch(value)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toSet();
    return GlobalSearchEntry(
      kind: GlobalSearchKind.menu,
      id: 'menu:$route',
      title: title,
      subtitle: module,
      route: route,
      moduleWords: words(module),
      isModuleFrontDoor: frontDoor,
      fields: [
        BikeFinderSearchField(title, weight: 130),
        BikeFinderSearchField(module, weight: 65),
        BikeFinderSearchField(
          <String>[route, if (toolKey != null) toolKey].join(' '),
          weight: 55,
        ),
      ],
    );
  }

  GlobalSearchEntry action(String title, String module, String route) {
    return GlobalSearchEntry(
      kind: GlobalSearchKind.action,
      id: 'action:$route',
      title: title,
      subtitle: module,
      route: route,
      fields: [
        BikeFinderSearchField(title, weight: 130),
        BikeFinderSearchField(module, weight: 90),
      ],
    );
  }

  final payroll = menu('Nóminas', 'RR.HH.', '/hr/payroll');
  final customersList = menu('Lista de clientes', 'Clientes', '/clientes');
  final newInvoice = action('Nueva factura', 'Ventas', '/sales/invoices/new');
  final newCustomer = action('Nuevo cliente', 'Clientes', '/clientes/nuevo');

  final felipe = GlobalSearchEntry(
    kind: GlobalSearchKind.customer,
    id: 'customer:c-1',
    title: 'Felipe Lizama',
    subtitle: '+56 9 3391 5497',
    identifier: '17.845.221-3',
    route: '/clientes/c-1',
    updatedAt: DateTime.utc(2026, 9, 10),
    fields: const [
      BikeFinderSearchField('Felipe Lizama', weight: 130),
      BikeFinderSearchField('17845221 3', weight: 128),
      BikeFinderSearchField('933915497', weight: 128),
    ],
  );

  final invoice = GlobalSearchEntry(
    kind: GlobalSearchKind.salesInvoice,
    id: 'sales_invoice:i-1',
    title: 'FV-01035',
    subtitle: 'Felipe Lizama · 12 sep 2026',
    identifier: 'FV-01035',
    route: '/sales/invoices/i-1',
    updatedAt: DateTime.utc(2026, 9, 12),
    fields: const [
      BikeFinderSearchField('FV-01035', weight: 140),
      BikeFinderSearchField('Felipe Lizama', weight: 110),
    ],
  );

  final job = GlobalSearchEntry(
    kind: GlobalSearchKind.job,
    id: 'mechanic_job:j-1',
    title: 'PG-01035',
    subtitle: 'Oxford South · Felipe Lizama',
    identifier: 'PG-01035',
    route: '/taller/pegas/j-1',
    updatedAt: DateTime.utc(2026, 9, 14),
    fields: const [
      BikeFinderSearchField('PG-01035', weight: 140),
      BikeFinderSearchField('Oxford South', weight: 110),
    ],
  );

  final chain = GlobalSearchEntry(
    kind: GlobalSearchKind.product,
    id: 'product:p-1',
    title: 'Cadena KMC X11 116L',
    subtitle: 'SKU 16448 · 7 en stock',
    identifier: '16448',
    route: '/inventory/products/p-1/edit',
    updatedAt: DateTime.utc(2026, 9, 1),
    fields: const [
      BikeFinderSearchField('Cadena KMC X11 116L', weight: 130),
      BikeFinderSearchField('16448', weight: 140),
    ],
  );

  // El caso que reportó el dueño: `pos` contestaba postizas antes que el módulo.
  final posModule = menu('Panel POS', 'POS', '/pos', frontDoor: true);

  // El módulo Taller, tal como lo publica el modelo de navegación: Trabajos es
  // su primera pantalla.
  final jobsList = menu('Trabajos', 'Taller', '/taller/pegas', frontDoor: true);
  final bikesList =
      menu('Bicicletas registradas', 'Taller', '/taller/bicicletas');
  final workshopCalendar = menu('Calendario', 'Taller', '/taller/calendario');

  // Una herramienta del rail: su rótulo no dice «notificaciones», su clave sí.
  final dailySummary = menu(
    'Resumen diario',
    'Comunicación',
    'tool:notifications',
    toolKey: 'notifications',
  );
  final postiza = GlobalSearchEntry(
    kind: GlobalSearchKind.product,
    id: 'product:p-2',
    title: 'Postiza Padro',
    subtitle: 'SKU NNV136 · Sin stock',
    identifier: 'NNV136',
    route: '/inventory/products/p-2/edit',
    updatedAt: DateTime.utc(2026, 9, 2),
    fields: const [
      BikeFinderSearchField('Postiza Padro', weight: 135),
      BikeFinderSearchField('NNV136', weight: 140),
    ],
  );

  final entries = <GlobalSearchEntry>[
    posModule,
    postiza,
    jobsList,
    bikesList,
    workshopCalendar,
    dailySummary,
    payroll,
    customersList,
    newInvoice,
    newCustomer,
    felipe,
    invoice,
    job,
    chain,
  ];

  GlobalSearchOutcome search(
    String input, {
    GlobalSearchUsage usage = GlobalSearchUsage.empty,
  }) {
    return rankGlobalSearch(
      query: GlobalSearchQuery.parse(input),
      entries: entries,
      usage: usage,
      now: now,
    );
  }

  String? firstId(String input) {
    final outcome = search(input);
    return outcome.isEmpty ? null : outcome.flattened.first.entry.id;
  }

  group('lo que el operador teclea', () {
    test('sin tilde y con un error encuentra el módulo', () {
      expect(firstId('nomina'), payroll.id);
      expect(firstId('nominas'), payroll.id);
      expect(firstId('nóminas'), payroll.id);
    });

    test('una sola letra no dispara la lista', () {
      expect(search('n').isEmpty, isTrue);
      expect(search('').isEmpty, isTrue);
    });

    test('el número suelto encuentra el documento de cualquier familia', () {
      final outcome = search('1035');
      final ids = outcome.flattened.map((result) => result.entry.id).toList();
      expect(ids, containsAll(<String>[invoice.id, job.id]));
    });

    test('el prefijo tecleado descarta la otra familia', () {
      expect(firstId('fv 1035'), invoice.id);
      expect(firstId('FV-01035'), invoice.id);
      expect(firstId('pg 1035'), job.id);
    });

    test('el SKU exacto gana al documento con el mismo número', () {
      expect(firstId('16448'), chain.id);
    });

    test('el RUT completo lleva al cliente', () {
      expect(firstId('17.845.221-3'), felipe.id);
      expect(firstId('178452213'), felipe.id);
    });

    test('el teléfono lleva al cliente', () {
      expect(firstId('933915497'), felipe.id);
    });

    test('un nombre gana al menú que lo contiene', () {
      expect(firstId('felipe'), felipe.id);
    });

    test('una palabra entera gana a ser el principio de otra más larga', () {
      // `pos` nombra el módulo POS. `Postiza` sólo empieza igual.
      expect(firstId('pos'), posModule.id);
    });

    test('la regla es nombrar, no el caso POS', () {
      // Mismo principio con otras palabras y otros destinos: si lo escrito es
      // una palabra del nombre, gana; si además son varias, también.
      expect(firstId('nominas'), payroll.id);
      expect(firstId('lista de clientes'), customersList.id);
    });

    test('un destino a medio escribir se ofrece mientras se escribe', () {
      // `posti` ya no nombra al módulo: nombra al producto.
      expect(firstId('posti'), postiza.id);
      // `po` es el principio del nombre de un destino y de ninguno mejor.
      expect(firstId('pan'), posModule.id);
    });

    test('nombrar no le gana a un identificador exacto', () {
      expect(firstId('16448'), chain.id);
      expect(firstId('nnv136'), postiza.id);
    });
  });

  group('nombrar el módulo, no la pantalla', () {
    test('«taller» aterriza en la puerta de entrada del módulo Taller', () {
      // Nadie escribió «taller significa trabajos»: Trabajos es, según el menú,
      // la primera pantalla de Taller.
      expect(firstId('taller'), jobsList.id);
    });

    test('el resto del módulo acompaña, no se dispersa', () {
      final ids = search('taller').flattened.map((r) => r.entry.id).toList();
      expect(ids.take(3),
          containsAll(<String>[bikesList.id, workshopCalendar.id]));
    });

    test('nombrar la pantalla sigue ganándole a nombrar el módulo', () {
      expect(firstId('calendario'), workshopCalendar.id);
    });
  });

  group('el vocabulario que el producto ya tiene', () {
    test('la palabra de la ruta encuentra la pantalla', () {
      // `pegas` no está en el título «Trabajos»; está en `/taller/pegas`.
      expect(firstId('pegas'), jobsList.id);
    });

    test('la clave técnica encuentra una herramienta sin ese rótulo', () {
      // «Resumen diario» no dice «notificaciones» por ninguna parte.
      expect(firstId('notifi'), dailySummary.id);
      expect(firstId('notificaciones'), dailySummary.id);
    });
  });

  group('aprender del uso, progresivamente', () {
    GlobalSearchUsage taught(String query, GlobalSearchEntry entry, int times) {
      var usage = GlobalSearchUsage.empty;
      for (var i = 0; i < times; i++) {
        usage = usage.recording(
          entry.id,
          now: now.subtract(Duration(minutes: times - i)),
          query: query,
        );
      }
      return usage;
    }

    test('elegir con una palabra enseña esa palabra', () {
      final usage = taught('cadena', chain, 2);
      expect(
        usage.choiceBonusFor('cadena', normalizedQuery: 'cadena', now: now),
        0,
        reason: 'el bono es del destino elegido, no de la palabra',
      );
      expect(
        usage.choiceBonusFor(chain.id, normalizedQuery: 'cadena', now: now),
        greaterThan(0),
      );
    });

    test('lo aprendido orienta ya mientras se escribe', () {
      final usage = taught('taller', bikesList, 3);
      final partial =
          usage.choiceBonusFor(bikesList.id, normalizedQuery: 'tall', now: now);
      final full = usage.choiceBonusFor(bikesList.id,
          normalizedQuery: 'taller', now: now);
      expect(partial, greaterThan(0));
      expect(full, greaterThan(partial));
    });

    test('una sola elección no tapa un nombre literal', () {
      final once = taught('pos', postiza, 1);
      expect(
        rankGlobalSearch(
          query: GlobalSearchQuery.parse('pos'),
          entries: entries,
          usage: once,
          now: now,
        ).flattened.first.entry.id,
        posModule.id,
      );
    });

    test('insistir sí cambia el resultado', () {
      final often = taught('pos', postiza, 4);
      expect(
        rankGlobalSearch(
          query: GlobalSearchQuery.parse('pos'),
          entries: entries,
          usage: often,
          now: now,
        ).flattened.first.entry.id,
        postiza.id,
      );
    });

    test('lo aprendido no tapa un identificador exacto', () {
      final often = taught('16448', postiza, 6);
      expect(
        rankGlobalSearch(
          query: GlobalSearchQuery.parse('16448'),
          entries: entries,
          usage: often,
          now: now,
        ).flattened.first.entry.id,
        chain.id,
      );
    });

    test('el vocabulario sobrevive al archivo y vence con el tiempo', () {
      final usage = taught('taller', jobsList, 2);
      final restored = GlobalSearchUsage.decode(usage.encode());
      expect(
        restored.choiceBonusFor(jobsList.id,
            normalizedQuery: 'taller', now: now),
        usage.choiceBonusFor(jobsList.id, normalizedQuery: 'taller', now: now),
      );

      final old = GlobalSearchUsage.empty.recording(
        jobsList.id,
        now: DateTime.utc(2026, 1, 1),
        query: 'taller',
      );
      expect(
        old.choiceBonusFor(jobsList.id, normalizedQuery: 'taller', now: now),
        0,
      );
      expect(old.pruned(now: now).choices, isEmpty);
    });
  });

  group('pedir hacer algo', () {
    test('«nueva factura» ejecuta en vez de navegar', () {
      expect(firstId('nueva factura'), newInvoice.id);
    });

    test('el verbo del taller también cuenta', () {
      expect(firstId('hacer una factura'), newInvoice.id);
      expect(firstId('crear cliente'), newCustomer.id);
    });

    test('«clientes» a secas sigue siendo navegar', () {
      expect(firstId('clientes'), customersList.id);
    });
  });

  group('orden y agrupación', () {
    test('el grupo se ordena por su mejor fila', () {
      final outcome = search('felipe');
      expect(outcome.groups.first.kind, GlobalSearchKind.customer);
    });

    test('dos consultas iguales dan exactamente el mismo orden', () {
      final first = search('felipe').flattened.map((r) => r.entry.id).toList();
      final second = search('felipe').flattened.map((r) => r.entry.id).toList();
      expect(first, second);
    });

    test('el grupo declara cuántas dejó fuera', () {
      final outcome = rankGlobalSearch(
        query: GlobalSearchQuery.parse('felipe'),
        entries: entries,
        now: now,
        groupLimit: 1,
      );
      final customers = outcome.groups
          .firstWhere((group) => group.kind == GlobalSearchKind.customer);
      expect(customers.results.length, 1);
    });
  });

  group('la costumbre desempata, no manda', () {
    test('un destino usado sube entre parecidos', () {
      final usage = GlobalSearchUsage.empty
          .recording(customersList.id,
              now: now.subtract(const Duration(hours: 2)))
          .recording(customersList.id,
              now: now.subtract(const Duration(hours: 1)));
      final outcome = search('clientes', usage: usage);
      expect(outcome.flattened.first.entry.id, customersList.id);
    });

    test('la costumbre no tapa un identificador exacto', () {
      var usage = GlobalSearchUsage.empty;
      for (var i = 0; i < 20; i++) {
        usage = usage.recording(customersList.id, now: now);
      }
      final outcome = search('16448', usage: usage);
      expect(outcome.flattened.first.entry.id, chain.id);
    });

    test('lo que no se abre hace meses deja de pesar', () {
      final usage = GlobalSearchUsage.empty.recording(
        payroll.id,
        now: DateTime.utc(2026, 1, 1),
      );
      expect(usage.bonusFor(payroll.id, now: now), 0);
      expect(usage.pruned(now: now).stats, isEmpty);
    });

    test('sobrevive un archivo corrupto', () {
      expect(GlobalSearchUsage.decode('{"x":').stats, isEmpty);
      expect(GlobalSearchUsage.decode(null).stats, isEmpty);
      final usage = GlobalSearchUsage.empty.recording('a', now: now);
      expect(GlobalSearchUsage.decode(usage.encode()).stats['a']?.count, 1);
    });
  });

  group('forma de la consulta', () {
    test('lee el documento de las tres maneras en que se escribe', () {
      expect(GlobalSearchQuery.parse('FV-01035').documentNumber, 1035);
      expect(GlobalSearchQuery.parse('fv 1035').documentPrefix, 'fv');
      expect(GlobalSearchQuery.parse('1035').documentPrefix, isNull);
      expect(GlobalSearchQuery.parse('1035').documentNumber, 1035);
    });

    test('un prefijo que no es nuestro no se inventa', () {
      expect(GlobalSearchQuery.parse('xx-1035').documentPrefix, isNull);
    });

    test('lee RUT y teléfono chilenos', () {
      expect(GlobalSearchQuery.parse('17.845.221-3').rut, '178452213');
      expect(GlobalSearchQuery.parse('+56 9 3391 5497').phone, '933915497');
      expect(GlobalSearchQuery.parse('933915497').phone, '933915497');
    });

    test('separa el verbo del sustantivo', () {
      expect(
          GlobalSearchQuery.parse('hacer una factura').createNoun, 'factura');
      expect(GlobalSearchQuery.parse('factura').createNoun, isNull);
    });
  });
}
