import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/main_layout.dart';
import '../themes/app_theme.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = AppTheme.isMobile(context);
    final theme = Theme.of(context);
    
    return MainLayout(
      title: 'Dashboard',
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Header - Mobile responsive
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.primaryColor,
                    theme.primaryColor.withOpacity(0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bienvenido a Vinabike ERP',
                    style: TextStyle(
                      fontSize: isMobile ? 20 : 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: isMobile ? 4 : 8),
                  Text(
                    'Sistema completo de gestión para tu tienda de bicicletas',
                    style: TextStyle(
                      fontSize: isMobile ? 13 : 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: isMobile ? 16 : 32),
            
            // Quick Stats - Mobile responsive grid
            isMobile
                ? Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              context,
                              'Cuentas',
                              '46',
                              Icons.account_balance,
                              Colors.blue,
                              isMobile,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              context,
                              'Productos',
                              '120',
                              Icons.inventory,
                              Colors.green,
                              isMobile,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              context,
                              'Clientes',
                              '85',
                              Icons.people,
                              Colors.orange,
                              isMobile,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              context,
                              'Proveedores',
                              '25',
                              Icons.business,
                              Colors.purple,
                              isMobile,
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          context,
                          'Cuentas Contables',
                          '46',
                          Icons.account_balance,
                          Colors.blue,
                          isMobile,
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
                          isMobile,
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
                          isMobile,
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
                          isMobile,
                        ),
                      ),
                    ],
                  ),
            
            SizedBox(height: isMobile ? 20 : 32),
            
            // Module Cards Section
            Text(
              'Módulos Principales',
              style: TextStyle(
                fontSize: isMobile ? 18 : 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Core Modules Grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: _getCrossAxisCount(context),
              crossAxisSpacing: isMobile ? 12 : 16,
              mainAxisSpacing: isMobile ? 12 : 16,
              childAspectRatio: isMobile ? 1.1 : 1.2,
              children: [
                _buildModuleCard(
                  context,
                  'Contabilidad',
                  'Plan de cuentas y asientos contables',
                  Icons.account_balance,
                  Colors.blue,
                  () => context.go('/accounting/accounts'),
                  isMobile,
                ),
                _buildModuleCard(
                  context,
                  'Clientes',
                  'Gestión de clientes y CRM',
                  Icons.people,
                  Colors.orange,
                  () => context.go('/crm/customers'),
                  isMobile,
                ),
                _buildModuleCard(
                  context,
                  'Inventario',
                  'Control de stock y productos',
                  Icons.inventory,
                  Colors.green,
                  () => context.go('/inventory/products'),
                  isMobile,
                ),
                _buildModuleCard(
                  context,
                  'Ventas',
                  'Facturación y punto de venta',
                  Icons.point_of_sale,
                  Colors.teal,
                  () => context.go('/sales/invoices'),
                  isMobile,
                ),
                _buildModuleCard(
                  context,
                  'Compras',
                  'Proveedores y órdenes de compra',
                  Icons.shopping_cart,
                  Colors.indigo,
                  () => context.go('/purchases/suppliers'),
                  isMobile,
                ),
                _buildModuleCard(
                  context,
                  'POS',
                  'Punto de venta rápido',
                  Icons.store,
                  Colors.red,
                  () => context.go('/pos'),
                  isMobile,
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
    bool isMobile,
  ) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: isMobile ? 20 : 24),
              Text(
                value,
                style: TextStyle(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 4 : 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: isMobile ? 11 : 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
    bool isMobile,
  ) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: isMobile ? 48 : 56,
                height: isMobile ? 48 : 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: isMobile ? 24 : 28,
                ),
              ),
              SizedBox(height: isMobile ? 8 : 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: isMobile ? 2 : 4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: isMobile ? 11 : 12,
                ),
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