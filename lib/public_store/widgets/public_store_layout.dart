import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/cart_provider.dart';
import '../theme/public_store_theme.dart';
import 'floating_whatsapp_button.dart';
import '../../modules/website/pages/odoo_style_editor_page.dart';
import '../../modules/website/services/website_service.dart';

class PublicStoreLayout extends StatefulWidget {
  final Widget child;
  final bool showEditorButton;

  const PublicStoreLayout({
    super.key,
    required this.child,
    this.showEditorButton = true,
  });

  @override
  State<PublicStoreLayout> createState() => _PublicStoreLayoutState();
}

class _PublicStoreLayoutState extends State<PublicStoreLayout> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = context.read<WebsiteService>();
      if (service.settings.isEmpty) {
        service.loadSettings();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final isLoggedIn = supabase.auth.currentUser != null;
    final websiteService = context.watch<WebsiteService>();

    final storeName = websiteService.getSetting('store_name', 'VINABIKE');
    final storeDescription = websiteService.getSetting(
      'store_description',
      'Todo lo que necesitas para tu bicicleta en Viña del Mar',
    );
    final contactEmail =
        websiteService.getSetting('contact_email', 'contacto@vinabike.cl');
    final contactPhone =
        websiteService.getSetting('contact_phone', '+56 9 XXXX XXXX');
    final contactAddress = websiteService.getSetting(
      'contact_address',
      'Álvarez 32, Local 17\nViña del Mar, Chile',
    );
    final facebookHandle = websiteService.getSetting('facebook', '');
    final instagramHandle = websiteService.getSetting('instagram', '');
    final twitterHandle = websiteService.getSetting('twitter', '');
    final youtubeHandle =
        websiteService.getSetting('youtube', '@vinabikechannel');
    final whatsappRaw = websiteService.getSetting('whatsapp', '');
    final whatsappNumber = _sanitizePhone(whatsappRaw);
    final hasWhatsApp = whatsappNumber.isNotEmpty;

    final primaryColor = _resolveColor(
      websiteService.getSetting('theme_primary_color', ''),
      PublicStoreTheme.primaryBlue,
    );
    final accentColor = _resolveColor(
      websiteService.getSetting('theme_accent_color', ''),
      PublicStoreTheme.accentGreen,
    );
    final backgroundColor = _resolveColor(
      websiteService.getSetting('theme_background_color', ''),
      Colors.white,
    );

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(
                context: context,
                storeName: storeName,
                storeDescription: storeDescription,
                contactPhone: contactPhone,
                contactEmail: contactEmail,
                primaryColor: primaryColor,
                accentColor: accentColor,
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      widget.child,
                      _buildFooter(
                        context: context,
                        storeName: storeName,
                        storeDescription: storeDescription,
                        contactEmail: contactEmail,
                        contactPhone: contactPhone,
                        contactAddress: contactAddress,
                        facebookHandle: facebookHandle,
                        instagramHandle: instagramHandle,
                        twitterHandle: twitterHandle,
                        youtubeHandle: youtubeHandle,
                        primaryColor: primaryColor,
                        accentColor: accentColor,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (hasWhatsApp)
            Positioned(
              bottom: 24,
              right: 24,
              child: FloatingWhatsAppButton(
                phoneNumber: whatsappNumber,
                message:
                    'Hola! Me gustaría consultar sobre ${storeName.isNotEmpty ? storeName : 'sus productos'}.',
                backgroundColor: accentColor,
              ),
            ),
          if (isLoggedIn && widget.showEditorButton)
            Positioned(
              bottom: 24,
              right: hasWhatsApp ? 104 : 24,
              child: FloatingActionButton.extended(
                onPressed: () {
                  Navigator.of(context)
                      .push(
                    MaterialPageRoute(
                      builder: (context) => const OdooStyleEditorPage(),
                    ),
                  )
                      .then((_) {
                    if (!mounted) return;
                    final service = context.read<WebsiteService>();
                    service.loadBlocks();
                    service.loadSettings();
                    service.loadBanners();
                    service.loadFeaturedProducts();
                  });
                },
                backgroundColor: accentColor,
                icon: const Icon(Icons.edit, color: Colors.white),
                label: const Text(
                  'Editar Sitio',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                tooltip: 'Abrir editor visual',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader({
    required BuildContext context,
    required String storeName,
    required String storeDescription,
    required String contactPhone,
    required String contactEmail,
    required Color primaryColor,
    required Color accentColor,
  }) {
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: primaryColor,
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 24,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_shipping_outlined,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Envíos a todo Chile',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.support_agent_outlined,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      contactPhone.isNotEmpty
                          ? 'Contáctanos: $contactPhone'
                          : 'Atención personalizada',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
                if (contactEmail.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mail_outline,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        contactEmail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                InkWell(
                  onTap: () => context.go('/tienda'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        storeName.isNotEmpty
                            ? storeName.toUpperCase()
                            : 'VINABIKE',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                      ),
                      if (storeDescription.isNotEmpty)
                        Text(
                          storeDescription,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: PublicStoreTheme.textSecondary,
                                  ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 48),
                Expanded(
                  child: Row(
                    children: [
                      _buildNavLink(context, 'Inicio', '/tienda', primaryColor),
                      const SizedBox(width: 24),
                      _buildNavLink(context, 'Productos', '/tienda/productos',
                          primaryColor),
                      const SizedBox(width: 24),
                      _buildNavLink(context, 'Contacto', '/tienda/contacto',
                          primaryColor),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.search),
                      color: primaryColor,
                      onPressed: () => context.go('/tienda/productos'),
                      tooltip: 'Buscar',
                    ),
                    const SizedBox(width: 8),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.shopping_cart_outlined),
                          color: primaryColor,
                          onPressed: () => context.go('/tienda/carrito'),
                          tooltip: 'Carrito',
                        ),
                        if (cart.itemCount > 0)
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: accentColor,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                  minWidth: 20, minHeight: 20),
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

  Widget _buildFooter({
    required BuildContext context,
    required String storeName,
    required String storeDescription,
    required String contactEmail,
    required String contactPhone,
    required String contactAddress,
    required String facebookHandle,
    required String instagramHandle,
    required String twitterHandle,
    required String youtubeHandle,
    required Color primaryColor,
    required Color accentColor,
  }) {
    final facebookUrl =
        _buildSocialUrl(facebookHandle, 'https://facebook.com/');
    final instagramUrl =
        _buildSocialUrl(instagramHandle, 'https://instagram.com/');
    final twitterUrl = _buildSocialUrl(twitterHandle, 'https://twitter.com/');
    final youtubeUrl = _buildSocialUrl(youtubeHandle, 'https://youtube.com/');

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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          storeName.isNotEmpty ? storeName : 'VINABIKE',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          storeDescription.isNotEmpty
                              ? storeDescription
                              : 'Todo lo que necesitas para tu bicicleta en Viña del Mar',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.white70,
                                  ),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.mail_outline,
                                  color: Colors.white70),
                              onPressed: contactEmail.isEmpty
                                  ? null
                                  : () => _launchUri(Uri(
                                      scheme: 'mailto', path: contactEmail)),
                              tooltip: 'Email',
                            ),
                            IconButton(
                              icon: const Icon(Icons.phone_outlined,
                                  color: Colors.white70),
                              onPressed: contactPhone.isEmpty
                                  ? null
                                  : () => _launchUri(
                                      Uri(scheme: 'tel', path: contactPhone)),
                              tooltip: 'Teléfono',
                            ),
                            IconButton(
                              icon: const Icon(Icons.facebook_outlined,
                                  color: Colors.white70),
                              onPressed: facebookUrl == null
                                  ? null
                                  : () => _launchUri(Uri.parse(facebookUrl)),
                              tooltip: 'Facebook',
                            ),
                            IconButton(
                              icon: const Icon(Icons.camera_alt_outlined,
                                  color: Colors.white70),
                              onPressed: instagramUrl == null
                                  ? null
                                  : () => _launchUri(Uri.parse(instagramUrl)),
                              tooltip: 'Instagram',
                            ),
                            IconButton(
                              icon: const Icon(Icons.alternate_email,
                                  color: Colors.white70),
                              onPressed: twitterUrl == null
                                  ? null
                                  : () => _launchUri(Uri.parse(twitterUrl)),
                              tooltip: 'Twitter',
                            ),
                            IconButton(
                              icon: const Icon(Icons.play_circle_outline,
                                  color: Colors.white70),
                              onPressed: youtubeUrl == null
                                  ? null
                                  : () => _launchUri(Uri.parse(youtubeUrl)),
                              tooltip: 'YouTube',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Enlaces',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        _buildFooterLink(
                            context, 'Inicio', '/tienda', primaryColor),
                        _buildFooterLink(context, 'Productos',
                            '/tienda/productos', primaryColor),
                        _buildFooterLink(context, 'Servicios',
                            '/tienda/servicios', primaryColor),
                        _buildFooterLink(context, 'Contacto',
                            '/tienda/contacto', primaryColor),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Información',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        _buildFooterLink(context, 'Sobre Nosotros',
                            '/tienda/nosotros', primaryColor),
                        _buildFooterLink(context, 'Términos y Condiciones',
                            '/tienda/terminos', primaryColor),
                        _buildFooterLink(context, 'Política de Privacidad',
                            '/tienda/privacidad', primaryColor),
                        _buildFooterLink(context, 'Preguntas Frecuentes',
                            '/tienda/faq', primaryColor),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contacto',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on_outlined,
                                color: Colors.white70, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                contactAddress.isNotEmpty
                                    ? contactAddress
                                    : 'Álvarez 32, Local 17\nViña del Mar, Chile',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.white70,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined,
                                color: Colors.white70, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              contactPhone.isNotEmpty
                                  ? contactPhone
                                  : '+56 9 XXXX XXXX',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.white70,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.email_outlined,
                                color: Colors.white70, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              contactEmail.isNotEmpty
                                  ? contactEmail
                                  : 'contacto@vinabike.cl',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
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
              Text(
                '© ${DateTime.now().year} ${storeName.isNotEmpty ? storeName : 'Vinabike'}. Todos los derechos reservados.',
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

  Widget _buildNavLink(
    BuildContext context,
    String label,
    String path,
    Color primaryColor,
  ) {
    final isActive = GoRouterState.of(context).matchedLocation == path;

    return InkWell(
      onTap: () => context.go(path),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? primaryColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? primaryColor : PublicStoreTheme.textPrimary,
              ),
        ),
      ),
    );
  }

  Widget _buildFooterLink(
    BuildContext context,
    String label,
    String path,
    Color primaryColor,
  ) {
    final isActive = GoRouterState.of(context).matchedLocation == path;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => context.go(path),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white70,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
        ),
      ),
    );
  }

  Future<void> _launchUri(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  String? _buildSocialUrl(String handle, String baseUrl) {
    final trimmed = handle.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('http')) {
      return trimmed;
    }
    return '$baseUrl${trimmed.replaceAll('@', '')}';
  }

  String _sanitizePhone(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return '';
    }
    if (digits.startsWith('56')) {
      return digits;
    }
    if (digits.length == 9 && digits.startsWith('9')) {
      return '56$digits';
    }
    if (digits.length == 8) {
      return '56$digits';
    }
    return digits;
  }

  Color _resolveColor(String raw, Color fallback) {
    final value = raw.trim();
    if (value.isEmpty) return fallback;

    Color? parsed;
    int? intValue;

    String cleaned = value.toLowerCase();
    if (cleaned.startsWith('color(')) {
      final inside = cleaned.replaceAll(RegExp(r'color\(|\)'), '');
      intValue = int.tryParse(inside);
    }

    intValue ??= int.tryParse(cleaned);
    if (intValue == null && cleaned.startsWith('0x')) {
      intValue = int.tryParse(cleaned);
    }
    if (intValue == null) {
      cleaned = cleaned.replaceAll('#', '');
      intValue = int.tryParse(cleaned, radix: 16);
      if (intValue != null && cleaned.length <= 6) {
        intValue = 0xFF000000 | intValue;
      }
    }

    if (intValue != null) {
      parsed = Color(intValue);
    }

    return parsed ?? fallback;
  }
}
