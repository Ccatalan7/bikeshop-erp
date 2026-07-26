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
    this.route,
  });

  final String title;
  final IconData icon;
  final ToolbarToolGroup group;

  /// A route means this entry is an immediate navigation command, not a panel.
  final String? route;

  bool get opensPanel => route == null;
}

const Map<ToolbarTool, ToolbarToolPresentation> toolbarToolPresentationCatalog =
    {
  ToolbarTool.notifications: ToolbarToolPresentation(
    title: 'Resumen diario',
    icon: Icons.notifications_outlined,
    group: ToolbarToolGroup.communication,
  ),
  ToolbarTool.newJob: ToolbarToolPresentation(
    title: 'Nuevo Trabajo',
    icon: Icons.build_circle_outlined,
    group: ToolbarToolGroup.workshop,
    route: '/taller/pegas/nueva',
  ),
  ToolbarTool.bikeFinder: ToolbarToolPresentation(
    title: 'Buscador de Bicicletas',
    icon: Icons.pedal_bike_outlined,
    group: ToolbarToolGroup.workshop,
  ),
  ToolbarTool.aiAssistant: ToolbarToolPresentation(
    title: 'Asistente IA',
    icon: Icons.auto_awesome,
    group: ToolbarToolGroup.communication,
  ),
  ToolbarTool.messages: ToolbarToolPresentation(
    title: 'Mensajería',
    icon: Icons.chat_bubble_outline,
    group: ToolbarToolGroup.communication,
  ),
  ToolbarTool.supplierMessages: ToolbarToolPresentation(
    title: 'Proveedores',
    icon: Icons.storefront_outlined,
    group: ToolbarToolGroup.communication,
  ),
  ToolbarTool.storage: ToolbarToolPresentation(
    title: 'Archivos',
    icon: Icons.folder_open_outlined,
    group: ToolbarToolGroup.files,
  ),
  ToolbarTool.fileRunner: ToolbarToolPresentation(
    title: 'Ejecutar archivos',
    icon: Icons.play_circle_outline,
    group: ToolbarToolGroup.files,
  ),
  ToolbarTool.kiosk: ToolbarToolPresentation(
    title: 'Kiosko RRHH',
    icon: Icons.badge_outlined,
    group: ToolbarToolGroup.workshop,
  ),
  ToolbarTool.quickSale: ToolbarToolPresentation(
    title: 'Venta Rápida',
    icon: Icons.flash_on,
    group: ToolbarToolGroup.operations,
  ),
  ToolbarTool.expenses: ToolbarToolPresentation(
    title: 'Gastos Rápidos',
    icon: Icons.receipt_long_outlined,
    group: ToolbarToolGroup.operations,
  ),
  ToolbarTool.purchases: ToolbarToolPresentation(
    title: 'Compras',
    icon: Icons.shopping_cart_outlined,
    group: ToolbarToolGroup.operations,
  ),
  ToolbarTool.tasks: ToolbarToolPresentation(
    title: 'Tareas',
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
