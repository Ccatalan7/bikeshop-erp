import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/customer_account_service.dart';
import '../providers/public_store_tenant_provider.dart';
import '../widgets/premium_dashboard_widgets.dart';
import '../widgets/customer_chat_panel.dart';
import '../../shared/widgets/safe_layout_builder.dart';

class CustomerDashboardPage extends StatefulWidget {
  const CustomerDashboardPage({super.key});

  @override
  State<CustomerDashboardPage> createState() => _CustomerDashboardPageState();
}

class _CustomerDashboardPageState extends State<CustomerDashboardPage>
    with AutomaticKeepAliveClientMixin {
  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final accountService = context.read<CustomerAccountService>();
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      accountService.setTenantId(tenantProvider.tenantId);

      if (accountService.isAuthenticated) {
        accountService.loadBikes();
        accountService.loadServiceHistory();
        accountService.loadOrders();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final accountService = context.watch<CustomerAccountService>();
    final profile = accountService.customerProfile;
    final name = profile?['name']?.split(' ')[0] ?? 'Usuario';

    final activeServices = accountService.serviceHistory
        .where((s) => !['ENTREGADO', 'CANCELADO'].contains(s['status']))
        .toList();
    final activeService =
        activeServices.isNotEmpty ? activeServices.first : null;
    final bikes = accountService.bikes;
    final orders = accountService.orders;
    final services = accountService.serviceHistory;

    return Container(
      color: Colors.white,
      child: MediaQueryLayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 900;
          if (isDesktop) {
            return _buildDesktopLayout(
                context, name, activeService, bikes, orders, services);
          } else {
            return _buildMobileLayout(
                context, name, activeService, bikes, orders, services);
          }
        },
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    String name,
    Map<String, dynamic>? activeService,
    List<dynamic> bikes,
    List<dynamic> orders,
    List<dynamic> services,
  ) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LEFT COLUMN (Main Content + Header Part)
          Expanded(
            flex: 2,
            child: Column(
              children: [
                // HEADER ROW (Grey Background)
                Container(
                  height: 80, // Strict height for alignment
                  color: Colors.grey.shade200,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0), // ALL 8px
                  width: double.infinity,
                  alignment: Alignment.centerLeft, // Center text vertically
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Bienvenido, $name',
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                      ),
                    ],
                  ),
                ),

                // BODY CONTENT (White Background) - Wrap in Expanded for scrolling
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8), // ALL 8px
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Dashboard Widgets
                          LiveJobTracker(activeService: activeService),
                          const SizedBox(height: 8), // ALL 8px
                          GarageGrid(bikes: bikes),
                          const SizedBox(height: 8), // ALL 8px
                          RecentActivity(orders: orders, services: services),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // RIGHT COLUMN (Unified Sidebar Container)
          // Wraps from bottom to top, containing the "Header" (Profile)
          Container(
            width: 400, // Fixed width for sidebar
            height: double.infinity, // Stretch to match IntrinsicHeight
            constraints:
                BoxConstraints(minHeight: MediaQuery.of(context).size.height),
            decoration: BoxDecoration(
              color: Colors.grey.shade200, // The "Container" background
              border: Border(left: BorderSide(color: Colors.grey.shade300)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  8, 0, 8, 8), // No top padding for header alignment
              child: Column(
                children: [
                  // PROFILE CARD (User information + Dropdown)
                  Container(
                    height: 80,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        PopupMenuButton<String>(
                          tooltip: 'Opciones de Cuenta',
                          offset: const Offset(0, 50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(30),
                                border:
                                    Border.all(color: Colors.grey.shade300)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Colors.black,
                                  child: Text(name[0].toUpperCase(),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                const Text('Mi Cuenta',
                                    style: TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                const SizedBox(width: 4),
                                Icon(Icons.keyboard_arrow_down,
                                    size: 18, color: Colors.grey[600]),
                              ],
                            ),
                          ),
                          onSelected: (value) async {
                            switch (value) {
                              case 'profile':
                                context.go('/tienda/cuenta/perfil');
                                break;
                              case 'orders':
                                context.go('/tienda/cuenta/pedidos');
                                break;
                              case 'addresses':
                                context.go('/tienda/cuenta/direcciones');
                                break;
                              case 'chat':
                                context.go('/tienda/cuenta/chats');
                                break;
                              case 'logout':
                                final accountService =
                                    context.read<CustomerAccountService>();
                                await accountService.signOut();
                                if (context.mounted) context.go('/');
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'profile',
                              child: Row(children: [
                                Icon(Icons.person_outline),
                                SizedBox(width: 12),
                                Text('Mi Perfil')
                              ]),
                            ),
                            const PopupMenuItem(
                              value: 'orders',
                              child: Row(children: [
                                Icon(Icons.shopping_bag_outlined),
                                SizedBox(width: 12),
                                Text('Mis Pedidos')
                              ]),
                            ),
                            const PopupMenuItem(
                              value: 'addresses',
                              child: Row(children: [
                                Icon(Icons.location_on_outlined),
                                SizedBox(width: 12),
                                Text('Mis Direcciones')
                              ]),
                            ),
                            const PopupMenuItem(
                              value: 'chat',
                              child: Row(children: [
                                Icon(Icons.chat_bubble_outline),
                                SizedBox(width: 12),
                                Text('Ayuda y Soporte')
                              ]),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'logout',
                              child: Row(children: [
                                Icon(Icons.logout, color: Colors.red),
                                SizedBox(width: 12),
                                Text('Cerrar Sesión',
                                    style: TextStyle(color: Colors.red))
                              ]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 0),

                  // Chat Card

                  // NO GAP HERE - Chat starts at Y=80 (aligned with header bottom)

                  // SIDEBAR CARDS

                  // Chat Card
                  Container(
                    height: 400,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: const CustomerChatPanel(compactMode: true),
                  ),

                  const SizedBox(height: 8), // ALL 8px

                  // Quick Reorder Card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: _buildQuickReorder(),
                  ),

                  const SizedBox(height: 8), // ALL 8px

                  // Recommendations Card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: _buildRecommendations(),
                  ),

                  const SizedBox(height: 8), // ALL 8px
                  Text('Semelle footer',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    String name,
    Map<String, dynamic>? activeService,
    List<dynamic> bikes,
    List<dynamic> orders,
    List<dynamic> services,
  ) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Hola, $name',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                PopupMenuButton<String>(
                  offset: const Offset(0, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.black,
                    child: Text(name[0].toUpperCase(),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                  onSelected: (value) async {
                    switch (value) {
                      case 'profile':
                        context.go('/tienda/cuenta/perfil');
                        break;
                      case 'orders':
                        context.go('/tienda/cuenta/pedidos');
                        break;
                      case 'addresses':
                        context.go('/tienda/cuenta/direcciones');
                        break;
                      case 'chat':
                        context.go('/tienda/cuenta/chats');
                        break;
                      case 'logout':
                        final accountService =
                            context.read<CustomerAccountService>();
                        await accountService.signOut();
                        if (context.mounted) context.go('/');
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'profile',
                      child: Row(children: [
                        Icon(Icons.person_outline),
                        SizedBox(width: 12),
                        Text('Mi Perfil')
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'orders',
                      child: Row(children: [
                        Icon(Icons.shopping_bag_outlined),
                        SizedBox(width: 12),
                        Text('Mis Pedidos')
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'addresses',
                      child: Row(children: [
                        Icon(Icons.location_on_outlined),
                        SizedBox(width: 12),
                        Text('Mis Direcciones')
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'chat',
                      child: Row(children: [
                        Icon(Icons.chat_bubble_outline),
                        SizedBox(width: 12),
                        Text('Ayuda y Soporte')
                      ]),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'logout',
                      child: Row(children: [
                        Icon(Icons.logout, color: Colors.red),
                        SizedBox(width: 12),
                        Text('Cerrar Sesión',
                            style: TextStyle(color: Colors.red))
                      ]),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            LiveJobTracker(activeService: activeService),
            const SizedBox(height: 16),
            GarageGrid(bikes: bikes),
            const SizedBox(height: 16),
            RecentActivity(orders: orders, services: services),
            const SizedBox(height: 16),

            // Mobile Sidebar (Stacked Cards)
            Container(
                height: 340,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200)),
                clipBehavior: Clip.antiAlias,
                child: const CustomerChatPanel(compactMode: true)),
            const SizedBox(height: 12),
            Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200)),
                padding: const EdgeInsets.all(16),
                child: _buildQuickReorder()),
            const SizedBox(height: 12),
            Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200)),
                padding: const EdgeInsets.all(16),
                child: _buildRecommendations()),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickReorder() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Reordenar Rápido',
                style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            TextButton(
              onPressed: () => context.go('/tienda'),
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero, minimumSize: Size.zero),
              child: Text('Ver todo',
                  style: TextStyle(color: Colors.blue[600], fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildReorderItem(name: 'Lubricante Cadena', price: '\$18.000'),
        const SizedBox(height: 12),
        _buildReorderItem(name: 'Cámaras (Pack)', price: '\$12.500'),
      ],
    );
  }

  Widget _buildReorderItem({required String name, required String price}) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.shopping_bag_outlined,
              color: Colors.grey[500], size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              const SizedBox(height: 2),
              Text(price,
                  style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ],
          ),
        ),
        Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
      ],
    );
  }

  Widget _buildRecommendations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recomendado para Ti',
            style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        const SizedBox(height: 16),
        SizedBox(
          height: 90,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildProductThumbnail('Lubricante', isNew: false),
              _buildProductThumbnail('Cámaras', isNew: true),
              _buildProductThumbnail('Pastillas', isNew: true),
              _buildProductThumbnail('Sellante', isNew: false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductThumbnail(String name, {bool isNew = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.shopping_bag_outlined,
                    color: Colors.grey[400], size: 24),
              ),
              if (isNew)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('NEW',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 56,
            child: Text(name,
                style: TextStyle(color: Colors.grey[600], fontSize: 10),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
