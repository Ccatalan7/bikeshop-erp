import 'package:flutter/material.dart';

import '../../services/right_toolbar_service.dart';
import '../../utils/bike_finder_search.dart';
import '../../widgets/toolbar_tool_presentation.dart';
import '../../widgets/main_layout.dart';
import 'global_search_entry.dart';

/// Rutas de creación que **existen en el router** y no están en la barra
/// lateral, porque el menú lleva a la lista y se crea desde adentro.
///
/// No es un registro paralelo de navegación: cada una es una ruta que ya
/// existe. Están acá porque «nuevo producto» es una de las cosas que más se
/// piden y hasta ahora había que pasar por la lista para pedirla.
const List<({String title, String module, String route, IconData icon})>
    _routerOnlyActions = [
  (
    title: 'Nuevo producto',
    module: 'Inventario',
    route: '/inventory/products/new',
    icon: Icons.add_box_outlined,
  ),
  (
    title: 'Nuevo proveedor',
    module: 'Compras',
    route: '/purchases/suppliers/new',
    icon: Icons.add_business_outlined,
  ),
  (
    title: 'Nuevo gasto',
    module: 'Contabilidad',
    route: '/accounting/expenses/new',
    icon: Icons.add_card_outlined,
  ),
];

/// Cómo se llama, en el menú de este ERP, el lugar donde se abren los paneles
/// del rail derecho.
const String _toolsModuleLabel = 'Herramientas';

Set<String> _words(String value) => normalizeBikeFinderSearch(value)
    .split(RegExp(r'[^a-z0-9]+'))
    .where((word) => word.isNotEmpty)
    .toSet();

/// Un ítem del menú cuyo título empieza por un verbo de crear **hace** algo.
///
/// La barra lateral ya mezcla las dos cosas: `Lista de clientes` lleva y
/// `Nuevo cliente` crea. El buscador las separa porque son intenciones
/// distintas, y esa distinción es la que decide el orden cuando alguien
/// escribe «clientes».
final RegExp _createTitle = RegExp(r'^(nuevo|nueva)\b');

/// Convierte el **único modelo de navegación** del ERP en filas del índice.
///
/// Toma los módulos ya resueltos —con el orden del usuario, sus permisos y sus
/// badges— en vez de recorrer el router: lo que el buscador ofrece es
/// exactamente lo que ese usuario puede abrir desde el menú, ni más ni menos.
List<GlobalSearchEntry> buildGlobalSearchMenuEntries({
  required List<AppDestinationModule> modules,
  required List<AppDestinationModule> fixedModules,
}) {
  final entries = <GlobalSearchEntry>[
    GlobalSearchEntry(
      kind: GlobalSearchKind.menu,
      id: 'menu:/dashboard',
      title: 'Inicio',
      subtitle: 'Panel principal',
      route: '/dashboard',
      icon: Icons.dashboard_outlined,
      fields: const <BikeFinderSearchField>[
        BikeFinderSearchField('Inicio', weight: 130),
        BikeFinderSearchField('Panel principal dashboard', weight: 80),
      ],
    ),
  ];

  final seen = <String>{'menu:/dashboard'};

  /// [module] es lo que se **muestra** bajo el título; [searchContext], lo que
  /// además se puede escribir para encontrarlo. Casi siempre coinciden — y
  /// cuando no, es porque la etiqueta de origen no sirve para leer.
  void add({
    required String title,
    required String module,
    required String route,
    required IconData icon,
    String? searchContext,
    ToolbarTool? tool,
    bool isModuleFrontDoor = false,
  }) {
    final isAction = _createTitle.hasMatch(normalizeBikeFinderSearch(title));
    final kind = isAction ? GlobalSearchKind.action : GlobalSearchKind.menu;
    final id = '${isAction ? 'action' : 'menu'}:$route';
    if (!seen.add(id)) return;

    entries.add(
      GlobalSearchEntry(
        kind: kind,
        id: id,
        title: title,
        subtitle: module,
        route: route,
        icon: icon,
        toolbarTool: tool,
        moduleWords: _words(module),
        isModuleFrontDoor: isModuleFrontDoor,
        fields: <BikeFinderSearchField>[
          BikeFinderSearchField(title, weight: 130),
          // El módulo pesa poco a propósito: es contexto, no nombre. Cuando
          // pesaba 90, «clientes» contestaba `Nuevo cliente` —cuyo módulo se
          // llama «Clientes»— antes que `Lista de clientes`.
          BikeFinderSearchField(module, weight: 65),
          if (searchContext != null && searchContext != module)
            BikeFinderSearchField(searchContext, weight: 60),
          // **Cómo se llama la cosa por dentro.** La ruta y la clave técnica
          // dicen lo que el rótulo a veces calla: `/taller/pegas` trae «taller»
          // y «pegas», que es como se pide en el taller aunque la pantalla se
          // llame «Trabajos»; `ToolbarTool.notifications` trae
          // «notifications», que es lo que alguien escribe buscando el
          // «Resumen diario». No es una tabla de sinónimos —nadie la escribió y
          // no envejece—: es vocabulario que el producto ya tenía. Pesa poco
          // para que jamás le gane a un título de verdad.
          BikeFinderSearchField(
            <String>[route, if (tool != null) tool.name].join(' '),
            weight: 55,
          ),
        ],
      ),
    );
  }

  for (final module in [...modules, ...fixedModules]) {
    var isFirst = true;
    for (final item in module.items) {
      if (item.isHeader) continue;
      add(
        title: item.title,
        module: module.title,
        route: module.resolveRoute?.call(item.route) ?? item.route,
        icon: item.icon,
        isModuleFrontDoor: isFirst,
      );
      isFirst = false;
    }
  }

  // Las herramientas del rail derecho son destinos como cualquier otro. Se
  // leen de su catálogo canónico —`toolbarToolPresentationCatalog`, el mismo
  // que pinta el rail y el lanzador compacto— para que el buscador no tenga una
  // segunda lista que se desincronice.
  for (final entry in toolbarToolPresentationCatalog.entries) {
    final presentation = entry.value;
    add(
      title: presentation.title,
      // **Qué hace, no en qué cajón quedó.** `ToolbarToolGroup` ordena iconos
      // en una columna; de rótulo en una lista no distingue nada —dos
      // `Proveedores`, «Comunicación» y «Compras»— y «Herramientas» tampoco,
      // porque ubica en vez de explicar. La frase que sí sirve es la que usaría
      // un empleado: esta bandeja es el WhatsApp de los proveedores. Vive en el
      // catálogo canónico, así que es la misma frase en todas partes.
      module: presentation.description ??
          (presentation.opensPanel
              ? _toolsModuleLabel
              : presentation.group.label),
      // Lo que no se muestra igual se puede escribir: quien piense
      // «comunicación» o «herramientas» también llega.
      searchContext: <String>[
        presentation.group.label,
        if (presentation.opensPanel) _toolsModuleLabel,
      ].join(' '),
      route: presentation.route ?? 'tool:${entry.key.name}',
      icon: presentation.icon,
      tool: presentation.opensPanel ? entry.key : null,
    );
  }

  for (final action in _routerOnlyActions) {
    add(
      title: action.title,
      module: action.module,
      route: action.route,
      icon: action.icon,
    );
  }

  return List<GlobalSearchEntry>.unmodifiable(_disambiguated(entries));
}

/// Garantiza que dos filas que se leen igual no queden leyéndose igual.
///
/// La segunda línea de un resultado existe para **decir por qué esta fila no es
/// la otra**. Cuando dos destinos comparten título y contexto, deja de cumplir
/// esa función y la lista afirma haber encontrado dos cosas mostrando una sola
/// dos veces. En ese caso —y sólo en ése— se le agrega lo que de verdad las
/// distingue, que es de dónde salen.
List<GlobalSearchEntry> _disambiguated(List<GlobalSearchEntry> entries) {
  final seenLabels = <String, int>{};
  for (final entry in entries) {
    final label = _readableLabel(entry);
    seenLabels[label] = (seenLabels[label] ?? 0) + 1;
  }
  if (!seenLabels.values.any((count) => count > 1)) return entries;

  return <GlobalSearchEntry>[
    for (final entry in entries)
      if ((seenLabels[_readableLabel(entry)] ?? 0) > 1)
        GlobalSearchEntry(
          kind: entry.kind,
          id: entry.id,
          title: entry.title,
          subtitle: <String>[
            if (entry.subtitle != null && entry.subtitle!.isNotEmpty)
              entry.subtitle!,
            _originHint(entry),
          ].join(' · '),
          identifier: entry.identifier,
          route: entry.route,
          icon: entry.icon,
          updatedAt: entry.updatedAt,
          toolbarTool: entry.toolbarTool,
          moduleWords: entry.moduleWords,
          isModuleFrontDoor: entry.isModuleFrontDoor,
          fields: entry.fields,
        )
      else
        entry,
  ];
}

String _readableLabel(GlobalSearchEntry entry) =>
    '${normalizeBikeFinderSearch(entry.title)}|'
    '${normalizeBikeFinderSearch(entry.subtitle ?? '')}';

/// De dónde sale este destino, dicho corto: el primer tramo de su ruta, o el
/// hecho de ser un panel.
String _originHint(GlobalSearchEntry entry) {
  if (entry.toolbarTool != null) return 'panel';
  final segments = entry.route
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  return segments.isEmpty ? entry.route : segments.first;
}
