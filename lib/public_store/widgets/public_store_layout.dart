import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../theme/public_store_theme.dart';
import '../providers/cart_provider.dart';
import 'floating_whatsapp_button.dart';

class PublicStoreLayout extends StatelessWidget {
  final Widget child;

  const PublicStoreLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      child,
                      _buildFooter(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Floating WhatsApp Button
          const Positioned(
            bottom: 24,
            right: 24,
            child: FloatingWhatsAppButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cart = context.watch<CartProvider>();
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: PublicStoreTheme.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top Bar (Announcements)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: PublicStoreTheme.primaryBlue,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.local_shipping_outlined,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Envíos a todo Chile',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 24),
                const Icon(
                  Icons.store_outlined,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Retiro en tienda',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          
          // Main Header
          Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                // Logo
                InkWell(
                  onTap: () => context.go('/tienda'),
                  child: Row(
                    children: [
                      // Use your logo here
                      Text(
                        'VINABIKE',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: PublicStoreTheme.primaryBlue,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 48),
                
                // Navigation Links
                Expanded(
                  child: Row(
                    children: [
                      _buildNavLink(context, 'Inicio', '/tienda'),
                      const SizedBox(width: 24),
                      _buildNavLink(context, 'Productos', '/tienda/productos'),
                      const SizedBox(width: 24),
                      _buildNavLink(context, 'Contacto', '/tienda/contacto'),
                    ],
                  ),
                ),
                
                // Actions
                Row(
                  children: [
                    // Search Button
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () {
                        // Open search dialog
                        context.go('/tienda/productos');
                      },
                      tooltip: 'Buscar',
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // Cart Button
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.shopping_cart_outlined),
                          onPressed: () => context.go('/tienda/carrito'),
                          tooltip: 'Carrito',
                        ),
                        if (cart.itemCount > 0)
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: PublicStoreTheme.error,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 20,
                                minHeight: 20,
                              ),
                              child: Text(
                                '${cart.itemCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavLink(BuildContext context, String label, String path) {
    final isActive = GoRouterState.of(context).matchedLocation == path;
    
    return InkWell(
      onTap: () => context.go(path),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? PublicStoreTheme.primaryBlue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? PublicStoreTheme.primaryBlue : PublicStoreTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      width: double.infinity,
      color: PublicStoreTheme.textPrimary,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Column 1: About
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VINABIKE',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Todo lo que necesitas para tu bicicleta en Viña del Mar',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.mail_outline, color: Colors.white70),
                              onPressed: () {
                                // Open email
                              },
                              tooltip: 'Email',
                            ),
                            IconButton(
                              icon: const Icon(Icons.phone_outlined, color: Colors.white70),
                              onPressed: () {
                                // Open phone
                              },
                              tooltip: 'Teléfono',
                            ),
                            IconButton(
                              icon: const Icon(Icons.facebook_outlined, color: Colors.white70),
                              onPressed: () {
                                // Open Facebook
                              },
                              tooltip: 'Facebook',
                            ),
                            IconButton(
                              icon: const Icon(Icons.camera_alt_outlined, color: Colors.white70),
                              onPressed: () {
                                // Open Instagram
                              },
                              tooltip: 'Instagram',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Column 2: Links
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enlaces',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildFooterLink(context, 'Inicio', '/tienda'),
                        _buildFooterLink(context, 'Productos', '/tienda/productos'),
                        _buildFooterLink(context, 'Servicios', '/tienda/servicios'),
                        _buildFooterLink(context, 'Contacto', '/tienda/contacto'),
                      ],
                    ),
                  ),
                  
                  // Column 3: Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Información',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildFooterLink(context, 'Sobre Nosotros', '/tienda/nosotros'),
                        _buildFooterLink(context, 'Términos y Condiciones', '/tienda/terminos'),
                        _buildFooterLink(context, 'Política de Privacidad', '/tienda/privacidad'),
                        _buildFooterLink(context, 'Preguntas Frecuentes', '/tienda/faq'),
                      ],
                    ),
                  ),
                  
                  // Column 4: Contact
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contacto',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on_outlined, color: Colors.white70, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Álvarez 32, Local 17\nViña del Mar, Chile',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined, color: Colors.white70, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '+56 9 XXXX XXXX',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.email_outlined, color: Colors.white70, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'info@vinabike.cl',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 48),
              const Divider(color: Colors.white24),
              const SizedBox(height: 24),
              
              // Copyright
              Text(
                '© ${DateTime.now().year} Vinabike. Todos los derechos reservados.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooterLink(BuildContext context, String label, String path) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => context.go(path),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}
