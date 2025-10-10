import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/main_layout.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Dashboard',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).primaryColor,
                    Theme.of(context).primaryColor.withOpacity(0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
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
                  SizedBox(height: 8),
                  Text(
                    'Sistema completo de gestión para tu tienda de bicicletas',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Quick Stats
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    context,
                    'Cuentas Contables',
                    '46',
                    Icons.account_balance,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    context,
                    'Productos',
                    '120',
                    Icons.inventory,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    context,
                    'Clientes',
                    '85',
                    Icons.people,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    context,
                    'Proveedores',
                    '25',
                    Icons.business,
                    Colors.purple,
                  ),
                ),
              ],
            ),
            
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
                  () => context.go('/crm/customers'),
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
              ],
            ),
            
            const SizedBox(height: 32),
            
            // Quick Actions Section
            const Text(
              'Acciones Rápidas',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Quick Action Buttons
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildQuickActionButton(
                  context,
                  'Nueva Venta',
                  Icons.add_shopping_cart,
                  Colors.green,
                  () => context.push('/sales/invoices/new'),
                ),
                _buildQuickActionButton(
                  context,
                  'Nuevo Cliente',
                  Icons.person_add,
                  Colors.blue,
                  () => context.push('/crm/customers/new'),
                ),
                _buildQuickActionButton(
                  context,
                  'Nuevo Producto',
                  Icons.add_box,
                  Colors.orange,
                  () => context.push('/inventory/products/new'),
                ),
                _buildQuickActionButton(
                  context,
                  'Asiento Manual',
                  Icons.edit_note,
                  Colors.purple,
                  () => context.push('/accounting/journal-entries/new'),
                ),
                _buildQuickActionButton(
                  context,
                  'Nueva Compra',
                  Icons.add_business,
                  Colors.indigo,
                  () => context.push('/purchases/suppliers/new'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
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

  Widget _buildQuickActionButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
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