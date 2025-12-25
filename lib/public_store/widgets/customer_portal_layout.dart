import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/customer_account_service.dart';
import 'customer_chat_panel.dart';
import 'premium_dashboard_widgets.dart';

class CustomerPortalLayout extends StatelessWidget {
  final String title;
  final Widget child;
  final bool showBackButton;
  final Widget? headerAction;
  final bool overrideLayout;
  final Widget? rightSidebarContent;

  final String? backPath;

  const CustomerPortalLayout({
    super.key,
    required this.title,
    required this.child,
    this.showBackButton = true,
    this.headerAction,
    this.overrideLayout = false,
    this.backPath,
    this.rightSidebarContent,
  });

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<CustomerAccountService>();
    final profile = accountService.customerProfile;
    final name = profile?['name']?.split(' ')[0] ?? 'Usuario';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;
        if (isDesktop) {
          return _buildDesktopLayout(context, name, initial);
        } else {
          return _buildMobileLayout(context);
        }
      },
    );
  }

  Widget _buildDesktopLayout(
      BuildContext context, String name, String initial) {
    if (overrideLayout) {
      return SizedBox(
        height: MediaQuery.of(context).size.height -
            80, // Approximate header height adjustment
        child: child,
      );
    }

    return SizedBox(
      height:
          MediaQuery.of(context).size.height - 80, // Account for store header
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
                  height: 80,
                  color: Colors.grey.shade200,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                  width: double.infinity,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      if (showBackButton)
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.black87),
                          onPressed: () =>
                              context.go(backPath ?? '/tienda/cuenta'),
                        ),
                      if (showBackButton) const SizedBox(width: 8),
                      Text(
                        title,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                      ),
                      if (headerAction != null) ...[
                        const Spacer(),
                        headerAction!,
                      ],
                    ],
                  ),
                ),

                // BODY CONTENT (White Background)
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // RIGHT COLUMN (Unified Sidebar Container) - NO SCROLL
          Container(
            width: 400,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              border: Border(left: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
                                  child: Text(initial,
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
                                const Icon(Icons.arrow_drop_down,
                                    color: Colors.black54),
                              ],
                            ),
                          ),
                          onSelected: (value) async {
                            if (value == 'logout') {
                              final accountService =
                                  context.read<CustomerAccountService>();
                              await accountService.signOut();
                              if (context.mounted) context.go('/');
                            } else if (value == 'profile') {
                              context.go('/tienda/cuenta/perfil');
                            } else if (value == 'orders') {
                              context.go('/tienda/cuenta/pedidos');
                            } else if (value == 'addresses') {
                              context.go('/tienda/cuenta/direcciones');
                            } else if (value == 'chat') {
                              context.go('/tienda/cuenta/chats');
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'profile',
                              child: Row(
                                children: [
                                  Icon(Icons.person_outline),
                                  SizedBox(width: 12),
                                  Text('Mi Perfil'),
                                ],
                              ),
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

                  // ANIMATED SIDEBAR CONTENT SWITCHER
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 600),
                    reverseDuration: const Duration(milliseconds: 400),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      // Full slide from right + fade for dramatic effect
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(1.0, 0), // Full slide from right
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        )),
                        child: FadeTransition(
                          opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: const Interval(0.0, 0.7),
                            ),
                          ),
                          child: child,
                        ),
                      );
                    },
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    child: rightSidebarContent != null
                        ? Container(
                            key: const ValueKey('custom-sidebar'),
                            child: rightSidebarContent,
                          )
                        : Column(
                            key: const ValueKey('default-sidebar'),
                            children: [
                              // Default Sidebar Cards
                              Container(
                                height: 400,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4))
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child:
                                    const CustomerChatPanel(compactMode: true),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4))
                                  ],
                                ),
                                padding: const EdgeInsets.all(20),
                                child: const QuickReorderWidget(),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4))
                                  ],
                                ),
                                padding: const EdgeInsets.all(20),
                                child: const RecommendationsWidget(),
                              ),
                            ],
                          ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    if (overrideLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Minimal Header
          Container(
              padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top,
                  bottom: 12,
                  left: 8,
                  right: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  if (showBackButton)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.go(backPath ?? '/tienda/cuenta'),
                    ),
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18))),
                  if (headerAction != null) headerAction!,
                ],
              )),
          // Content fills the rest
          Expanded(child: child),
        ],
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mobile Header
          Container(
            color: Colors.grey.shade50,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              bottom: 16,
            ),
            child: Row(
              children: [
                if (showBackButton)
                  InkWell(
                    onTap: () => context.go(backPath ?? '/tienda/cuenta'),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back,
                          size: 20, color: Colors.black87),
                    ),
                  ),
                if (showBackButton) const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                if (headerAction != null) headerAction!,
              ],
            ),
          ),

          // Content Container
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),

          // Bottom Spacing
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
