import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_entry.dart';
import 'package:vinabike_erp/shared/services/global_search/global_search_menu_source.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/widgets/expandable_menu_item.dart';
import 'package:vinabike_erp/shared/widgets/main_layout.dart';

/// Lo que se prueba acá es **lo que el operador lee**, no cómo se construye.
///
/// La segunda línea de un resultado existe para decir por qué esta fila no es
/// la otra. Si repite una taxonomía escrita para otra pantalla, no lo dice.
void main() {
  const purchases = AppDestinationModule(
    key: 'purchases',
    title: 'Compras',
    icon: Icons.shopping_cart_outlined,
    activeIcon: Icons.shopping_cart,
    items: <MenuSubItem>[
      MenuSubItem(
        icon: Icons.storefront_outlined,
        title: 'Proveedores',
        route: '/purchases/suppliers',
      ),
    ],
  );

  const workshop = AppDestinationModule(
    key: 'workshop',
    title: 'Taller',
    icon: Icons.pedal_bike_outlined,
    activeIcon: Icons.pedal_bike,
    items: <MenuSubItem>[
      MenuSubItem(
        icon: Icons.build_outlined,
        title: 'Trabajos',
        route: '/taller/pegas',
      ),
      MenuSubItem(
        icon: Icons.pedal_bike,
        title: 'Bicicletas registradas',
        route: '/taller/bicicletas',
      ),
    ],
  );

  List<GlobalSearchEntry> build() => buildGlobalSearchMenuEntries(
        modules: const <AppDestinationModule>[purchases, workshop],
        fixedModules: const <AppDestinationModule>[],
      );

  GlobalSearchEntry find(String id) =>
      build().firstWhere((entry) => entry.id == id);

  test('un panel del rail dice qué hace, no en qué cajón quedó', () {
    // `ToolbarToolGroup.communication` se llama «Comunicación» y agrupa iconos
    // en el rail; de segunda línea no distingue nada. «Herramientas» tampoco:
    // ubica en vez de explicar. Esta bandeja es el WhatsApp de proveedores.
    final panel = find('menu:tool:supplierMessages');
    expect(panel.subtitle, 'WhatsApp con proveedores');
    expect(panel.toolbarTool, ToolbarTool.supplierMessages);
  });

  test('«whatsapp» encuentra las dos bandejas', () {
    final haystacks = <String, String>{
      for (final entry in build()) entry.id: entry.haystack,
    };
    expect(haystacks['menu:tool:supplierMessages'], contains('whatsapp'));
    expect(haystacks['menu:tool:messages'], contains('whatsapp'));
  });

  test('lo que no se muestra igual se puede escribir', () {
    final panel = find('menu:tool:supplierMessages');
    expect(panel.haystack, contains('comunicacion'));
    expect(panel.haystack, contains('herramientas'));
  });

  test('dos destinos que se leerían igual dejan de leerse igual', () {
    final entries = build();
    final labels = entries
        .map((entry) => '${entry.title}|${entry.subtitle}')
        .toList(growable: false);
    expect(
      labels.length,
      labels.toSet().length,
      reason: 'ninguna fila puede ser indistinguible de otra',
    );
  });

  test('la primera pantalla del módulo queda marcada como su puerta', () {
    expect(find('menu:/taller/pegas').isModuleFrontDoor, isTrue);
    expect(find('menu:/taller/bicicletas').isModuleFrontDoor, isFalse);
    expect(find('menu:/taller/pegas').moduleWords, contains('taller'));
  });

  test('la ruta entra al texto buscable', () {
    // «pegas» no está en el título «Trabajos»; está en la ruta.
    expect(find('menu:/taller/pegas').haystack, contains('pegas'));
  });

  test('las herramientas del rail son destinos indexados', () {
    final ids = build().map((entry) => entry.id).toSet();
    expect(ids, contains('menu:tool:tasks'));
    expect(ids, contains('menu:tool:calculator'));
    expect(ids, contains('menu:tool:notifications'));
  });
}
