import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vinabike_erp/modules/accounting/widgets/accounting_dashboard_section.dart';

import '../widgets/main_layout.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _showWelcomeBanner = true;

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Dashboard',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Header (dismissible)
            if (_showWelcomeBanner)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF1565C0),
                      Color(0xFF1976D2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bienvenido a Vinabike ERP',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sistema completo de gestión para tu tienda de bicicletas',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      top: -8,
                      right: -8,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: 'Cerrar',
                        onPressed: () {
                          setState(() {
                            _showWelcomeBanner = false;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),

            if (_showWelcomeBanner) const SizedBox(height: 32),

            const AccountingDashboardSection(),

            const SizedBox(height: 32),

            // Module Cards Section
            const Text(
              'Módulos Principales',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Core Modules Grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: _getCrossAxisCount(context),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.2,
              children: [
                _buildModuleCard(
                  context,
                  'Contabilidad',
                  'Plan de cuentas y asientos contables',
                  Icons.account_balance,
                  Colors.blue,
                  () => context.go('/accounting/accounts'),
                ),
                _buildModuleCard(
                  context,
                  'Clientes',
                  'Gestión de clientes y CRM',
                  Icons.people,
                  Colors.orange,
                  () => context.go('/clientes'),
                ),
                _buildModuleCard(
                  context,
                  'Inventario',
                  'Control de stock y productos',
                  Icons.inventory,
                  Colors.green,
                  () => context.go('/inventory/products'),
                ),
                _buildModuleCard(
                  context,
                  'Ventas',
                  'Facturación y punto de venta',
                  Icons.point_of_sale,
                  Colors.teal,
                  () => context.go('/sales/invoices'),
                ),
                _buildModuleCard(
                  context,
                  'Compras',
                  'Proveedores y órdenes de compra',
                  Icons.shopping_cart,
                  Colors.indigo,
                  () => context.go('/purchases/suppliers'),
                ),
                _buildModuleCard(
                  context,
                  'POS',
                  'Punto de venta rápido',
                  Icons.store,
                  Colors.red,
                  () => context.go('/pos'),
                ),
                _buildModuleCard(
                  context,
                  'Sitio Web',
                  'Gestión de tienda online',
                  Icons.language,
                  const Color(0xFF4CAF50), // Green for web/online
                  () => context.go('/website'),
                ),
                _buildModuleCard(
                  context,
                  'Taller',
                  'Gestión de bicicletas y reparaciones',
                  Icons.build,
                  Colors.purple,
                  () => context.go('/taller/pegas'),
                ),
                // Workspace Demo (for testing)
                _buildModuleCard(
                  context,
                  'Workspace Demo',
                  'Test TradingView-style tabs',
                  Icons.tab,
                  Colors.deepOrange,
                  () => context.go('/workspace-demo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleCard(
    BuildContext context,
    String title,
    String description,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 4;
    if (width > 800) return 3;
    if (width > 600) return 2;
    return 1;
  }
}
