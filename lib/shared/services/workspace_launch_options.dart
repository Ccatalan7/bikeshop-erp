import 'package:flutter/material.dart';

/// Destino con el que se puede abrir un espacio de trabajo nuevo.
///
/// Vive aquí, y no dentro de la barra de pestañas de escritorio, porque el
/// catálogo es el mismo en toda la aplicación: escritorio lo ofrece en un
/// popover anclado al botón «+» y compacto en una hoja inferior. Dos listas
/// paralelas se habrían separado en el primer módulo nuevo.
@immutable
class WorkspaceLaunchOption {
  const WorkspaceLaunchOption(this.icon, this.title, this.route);

  final IconData icon;
  final String title;
  final String route;
}

/// Destinos ofrecidos al abrir un espacio de trabajo nuevo, en el orden en que
/// se presentan.
const List<WorkspaceLaunchOption> workspaceLaunchOptions =
    <WorkspaceLaunchOption>[
  WorkspaceLaunchOption(Icons.dashboard, 'Dashboard', '/dashboard'),
  WorkspaceLaunchOption(
    Icons.language,
    'Navegador web',
    '/tools/web?url=https%3A%2F%2Fwww.google.com&name=Navegador%20web',
  ),
  WorkspaceLaunchOption(Icons.shopping_bag, 'Productos', '/inventory/products'),
  WorkspaceLaunchOption(Icons.receipt, 'Ventas', '/sales/invoices'),
  WorkspaceLaunchOption(Icons.people, 'Clientes', '/clientes'),
  WorkspaceLaunchOption(
    Icons.shopping_cart,
    'Compras',
    '/purchases/suppliers',
  ),
  WorkspaceLaunchOption(Icons.point_of_sale, 'POS', '/pos'),
  WorkspaceLaunchOption(Icons.build, 'Taller', '/taller/pegas'),
  WorkspaceLaunchOption(
    Icons.account_balance,
    'Contabilidad',
    '/accounting/accounts',
  ),
];
