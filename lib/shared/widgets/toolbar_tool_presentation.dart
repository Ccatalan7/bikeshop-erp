import 'package:flutter/material.dart';

import '../services/right_toolbar_service.dart';

/// Visual grouping used by both the desktop rail and compact tool launcher.
///
/// This catalog owns presentation only. Tool commands and mutable state remain
/// owned by [RightToolbarService], [RightToolbar], and each canonical panel.
enum ToolbarToolGroup {
  communication,
  workshop,
  operations,
  files,
  utilities,
}

extension ToolbarToolGroupPresentation on ToolbarToolGroup {
  String get label => switch (this) {
        ToolbarToolGroup.communication => 'Comunicación',
        ToolbarToolGroup.workshop => 'Taller',
        ToolbarToolGroup.operations => 'Operación',
        ToolbarToolGroup.files => 'Archivos',
        ToolbarToolGroup.utilities => 'Utilidades',
      };
}

@immutable
class ToolbarToolPresentation {
  const ToolbarToolPresentation({
    required this.title,
    required this.icon,
    required this.group,
    this.description,
    this.route,
  });

  final String title;
  final IconData icon;
  final ToolbarToolGroup group;

  /// Qué hace esta herramienta, en las palabras de la tienda.
  ///
  /// **Por qué vive acá y no en quien la muestra.** El rótulo de una lista
  /// tiene que decir *qué es* la cosa; el grupo del rail sólo dice en qué bloque
  /// de iconos quedó, y en el rail alcanza porque el icono ya la identifica. En
  /// una lista de resultados no alcanza: dos filas `Proveedores` —una de
  /// «Comunicación» y otra de «Compras»— no le dicen a un empleado cuál es
  /// cuál, y **«Herramientas» tampoco**, porque ubica en vez de explicar. La
  /// frase correcta es la que el empleado usaría: esta bandeja es el WhatsApp de
  /// los proveedores, así que eso es lo que dice.
  ///
  /// Está en el catálogo canónico, y no en el buscador, para que sea **una sola
  /// frase** por herramienta: la consume quien la muestre. `null` cuando el
  /// título ya se explica solo —una calculadora es una calculadora— porque
  /// repetirlo con otras palabras no aclara nada.
  final String? description;

  /// A route means this entry is an immediate navigation command, not a panel.
  final String? route;

  bool get opensPanel => route == null;
}

const Map<ToolbarTool, ToolbarToolPresentation> toolbarToolPresentationCatalog =
    {
  ToolbarTool.notifications: ToolbarToolPresentation(
    title: 'Resumen diario',
    description: 'Pendientes y avisos del día',
    icon: Icons.notifications_outlined,
    group: ToolbarToolGroup.communication,
  ),
  ToolbarTool.newJob: ToolbarToolPresentation(
    title: 'Nuevo Trabajo',
    description: 'Abrir una pega nueva',
    icon: Icons.build_circle_outlined,
    group: ToolbarToolGroup.workshop,
    route: '/taller/pegas/nueva',
  ),
  ToolbarTool.bikeFinder: ToolbarToolPresentation(
    title: 'Buscador de Bicicletas',
    description: 'Buscar una bici por dueño, marca o serie',
    icon: Icons.pedal_bike_outlined,
    group: ToolbarToolGroup.workshop,
  ),
  ToolbarTool.aiAssistant: ToolbarToolPresentation(
    title: 'Asistente IA',
    description: 'Preguntarle al asistente',
    icon: Icons.auto_awesome,
    group: ToolbarToolGroup.communication,
  ),
  ToolbarTool.messages: ToolbarToolPresentation(
    title: 'Mensajería',
    description: 'WhatsApp y chat con clientes',
    icon: Icons.chat_bubble_outline,
    group: ToolbarToolGroup.communication,
  ),
  ToolbarTool.supplierMessages: ToolbarToolPresentation(
    title: 'Proveedores',
    description: 'WhatsApp con proveedores',
    icon: Icons.storefront_outlined,
    group: ToolbarToolGroup.communication,
  ),
  ToolbarTool.storage: ToolbarToolPresentation(
    title: 'Archivos',
    description: 'Archivos del taller',
    icon: Icons.folder_open_outlined,
    group: ToolbarToolGroup.files,
  ),
  ToolbarTool.fileRunner: ToolbarToolPresentation(
    title: 'Ejecutar archivos',
    description: 'Abrir un archivo sin salir de la pantalla',
    icon: Icons.play_circle_outline,
    group: ToolbarToolGroup.files,
  ),
  ToolbarTool.kiosk: ToolbarToolPresentation(
    title: 'Kiosko RRHH',
    description: 'Marcar entrada y salida del personal',
    icon: Icons.badge_outlined,
    group: ToolbarToolGroup.workshop,
  ),
  ToolbarTool.quickSale: ToolbarToolPresentation(
    title: 'Venta Rápida',
    description: 'Cobrar sin salir de la pantalla',
    icon: Icons.flash_on,
    group: ToolbarToolGroup.operations,
  ),
  ToolbarTool.expenses: ToolbarToolPresentation(
    title: 'Gastos Rápidos',
    description: 'Anotar un gasto al vuelo',
    icon: Icons.receipt_long_outlined,
    group: ToolbarToolGroup.operations,
  ),
  ToolbarTool.purchases: ToolbarToolPresentation(
    title: 'Compras',
    description: 'Anotar algo que hay que comprar',
    icon: Icons.shopping_cart_outlined,
    group: ToolbarToolGroup.operations,
  ),
  ToolbarTool.tasks: ToolbarToolPresentation(
    title: 'Tareas',
    description: 'Lo asignado a mí y al equipo',
    icon: Icons.task_alt,
    group: ToolbarToolGroup.workshop,
  ),
  ToolbarTool.calculator: ToolbarToolPresentation(
    title: 'Calculadora',
    icon: Icons.calculate_outlined,
    group: ToolbarToolGroup.utilities,
  ),
  ToolbarTool.performance: ToolbarToolPresentation(
    title: 'DB Gauge',
    description: 'Rendimiento de la base de datos',
    icon: Icons.speed_outlined,
    group: ToolbarToolGroup.utilities,
  ),
};

extension ToolbarToolPresentationLookup on ToolbarTool {
  ToolbarToolPresentation get toolbarPresentation {
    final presentation = toolbarToolPresentationCatalog[this];
    assert(
      presentation != null,
      'ToolbarTool.$name is missing from toolbarToolPresentationCatalog.',
    );
    return presentation!;
  }
}

/// One permission and availability projection shared by the desktop rail and
/// compact tool launcher. A hidden tool must never reappear merely because the
/// shell crossed a responsive breakpoint.
List<ToolbarTool> resolveVisibleToolbarTools({
  required bool canManageHr,
  required bool performanceEnabled,
  required bool performancePinned,
}) {
  return ToolbarTool.values.where((tool) {
    if (tool == ToolbarTool.kiosk) return canManageHr;
    if (tool == ToolbarTool.performance) {
      return performanceEnabled && performancePinned;
    }
    return true;
  }).toList(growable: false);
}
