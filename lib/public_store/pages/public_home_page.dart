import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../modules/website/models/website_models.dart';
import '../../modules/website/services/website_service.dart';
import '../../shared/models/product.dart';
import '../../shared/services/inventory_service.dart';
import '../../shared/utils/chilean_utils.dart';
import '../theme/public_store_theme.dart';

class PublicHomePage extends StatefulWidget {
  const PublicHomePage({super.key});

  @override
  State<PublicHomePage> createState() => _PublicHomePageState();
}

class _PublicHomePageState extends State<PublicHomePage> {
  bool _isLoading = true;
  List<WebsiteBanner> _banners = [];
  List<Product> _featuredProducts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final websiteService = context.read<WebsiteService>();
      final inventoryService = context.read<InventoryService>();

      if (websiteService.settings.isEmpty) {
        await websiteService.loadSettings();
      }

      await websiteService.loadBlocks();

      await websiteService.loadBanners();
      _banners =
          websiteService.banners.where((banner) => banner.active).toList();

      await websiteService.loadFeaturedProducts();
      final featuredProductIds = websiteService.featuredProducts;
      final allProducts = await inventoryService.getProducts();

      _featuredProducts = allProducts
          .where((product) =>
              featuredProductIds.any((fp) => fp.productId == product.id))
          .take(8)
          .toList();
    } catch (error) {
      debugPrint('[PublicHomePage] Error loading data: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final websiteService = context.watch<WebsiteService>();
    final primaryColor = _resolveColor(
      websiteService.getSetting('theme_primary_color', ''),
      PublicStoreTheme.primaryBlue,
    );
    final accentColor = _resolveColor(
      websiteService.getSetting('theme_accent_color', ''),
      PublicStoreTheme.accentGreen,
    );

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final visibleBlocks = List<Map<String, dynamic>>.from(
      websiteService.blocks.where((block) => block['is_visible'] ?? true),
    )..sort(
        (a, b) => (a['order_index'] ?? 0).compareTo(b['order_index'] ?? 0),
      );

    if (visibleBlocks.isNotEmpty) {
      return SingleChildScrollView(
        child: Column(
          children: [
            for (final block in visibleBlocks) ...[
              _buildBlockFromData(block, primaryColor, accentColor),
              const SizedBox(height: 48),
            ],
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeroSection(primaryColor, accentColor),
          const SizedBox(height: 64),
          _buildFeaturedProductsSection(primaryColor, accentColor),
          const SizedBox(height: 64),
          _buildCategoriesSection(primaryColor),
          const SizedBox(height: 64),
          _buildWhyChooseUsSection(primaryColor),
          const SizedBox(height: 64),
        ],
      ),
    );
  }

  Widget _buildBlockFromData(
    Map<String, dynamic> blockData,
    Color primaryColor,
    Color accentColor,
  ) {
    final blockType = blockData['block_type'] ?? '';
    final data = Map<String, dynamic>.from(blockData['block_data'] ?? {});

    switch (blockType) {
      case 'hero':
        return _buildHeroBlock(data, primaryColor, accentColor);
      case 'products':
        return _buildProductsBlock(data, primaryColor, accentColor);
      case 'services':
        return _buildServicesBlock(data, primaryColor);
      case 'about':
        return _buildAboutBlock(data);
      case 'testimonials':
        return _buildTestimonialsBlock(data);
      case 'features':
        return _buildFeaturesBlock(data, primaryColor, accentColor);
      case 'cta':
        return _buildCtaBlock(data, primaryColor, accentColor);
      case 'gallery':
        return _buildGalleryBlock(data);
      case 'contact':
        return _buildContactBlock(data);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildHeroSection(Color primaryColor, Color accentColor) {
    if (_banners.isEmpty) {
      return Container(
        height: 480,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              primaryColor,
              accentColor.withOpacity(0.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'SERVICIOS Y PRODUCTOS DE BICICLETA',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: Colors.white,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Todo lo que necesitas para tu bicicleta en Viña del Mar',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white70,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => context.go('/tienda/productos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                ),
                child: const Text('VER PRODUCTOS'),
              ),
            ],
          ),
        ),
      );
    }

    final banner = _banners.first;
    final hasImage = banner.imageUrl != null && banner.imageUrl!.isNotEmpty;

    return Container(
      height: 480,
      width: double.infinity,
      decoration: BoxDecoration(
        image: hasImage
            ? DecorationImage(
                image: NetworkImage(banner.imageUrl!),
                fit: BoxFit.cover,
              )
            : null,
        gradient: !hasImage
            ? LinearGradient(
                colors: [
                  primaryColor,
                  accentColor.withOpacity(0.85),
                ],
              )
            : null,
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.35),
              Colors.black.withOpacity(0.65),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                banner.title,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: Colors.white,
                    ),
                textAlign: TextAlign.center,
              ),
              if (banner.subtitle != null && banner.subtitle!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  banner.subtitle!,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white70,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (banner.ctaText != null && banner.ctaText!.isNotEmpty) ...[
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    final link =
                        banner.ctaLink != null && banner.ctaLink!.isNotEmpty
                            ? banner.ctaLink!
                            : '/tienda/productos';
                    context.go(link);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 20,
                    ),
                  ),
                  child: Text(banner.ctaText!.toUpperCase()),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturedProductsSection(Color primaryColor, Color accentColor) {
    if (_featuredProducts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 1200),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Productos Destacados',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Descubre nuestras mejores ofertas',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: PublicStoreTheme.textSecondary,
                ),
          ),
          const SizedBox(height: 32),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.75,
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
            ),
            itemCount: _featuredProducts.length,
            itemBuilder: (context, index) {
              return _buildProductCard(
                _featuredProducts[index],
                primaryColor,
                accentColor,
              );
            },
          ),
          const SizedBox(height: 32),
          Center(
            child: OutlinedButton(
              onPressed: () => context.go('/tienda/productos'),
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryColor,
                side: BorderSide(color: primaryColor, width: 1.5),
                padding:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
              ),
              child: const Text('VER TODOS LOS PRODUCTOS'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(
    Product product,
    Color primaryColor,
    Color accentColor,
  ) {
    return InkWell(
      onTap: () => context.go('/tienda/producto/${product.id}'),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: PublicStoreTheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: product.imageUrl != null
                    ? ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: Image.network(
                          product.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.image_not_supported,
                                size: 48,
                                color: PublicStoreTheme.textMuted,
                              ),
                            );
                          },
                        ),
                      )
                    : const Center(
                        child: Icon(
                          Icons.pedal_bike,
                          size: 64,
                          color: PublicStoreTheme.textMuted,
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ChileanUtils.formatCurrency(product.price),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (product.stockQuantity > 0)
                    Text(
                      'Stock disponible',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: PublicStoreTheme.success,
                          ),
                    )
                  else
                    Text(
                      'Sin stock',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: PublicStoreTheme.error,
                          ),
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () =>
                        context.go('/tienda/producto/${product.id}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 42),
                    ),
                    child: const Text('VER DETALLE'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesSection(Color primaryColor) {
    final categories = [
      {'name': 'Bicicletas', 'icon': Icons.pedal_bike},
      {'name': 'Accesorios', 'icon': Icons.settings},
      {'name': 'Repuestos', 'icon': Icons.build},
      {'name': 'Ropa', 'icon': Icons.checkroom},
    ];

    return Container(
      width: double.infinity,
      color: PublicStoreTheme.surface,
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              Text(
                'Explora por Categoría',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 48),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: categories.map((category) {
                  return InkWell(
                    onTap: () => context.go('/tienda/productos'),
                    child: Column(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: PublicStoreTheme.cardShadow,
                          ),
                          child: Icon(
                            category['icon'] as IconData,
                            size: 48,
                            color: primaryColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          category['name'] as String,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWhyChooseUsSection(Color primaryColor) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1200),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Text(
            '¿Por qué elegirnos?',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 48),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: [
              _buildFeatureCard(
                Icons.local_shipping_outlined,
                'Envío Rápido',
                'Envíos a todo Chile en 24-48 horas',
                primaryColor,
              ),
              _buildFeatureCard(
                Icons.verified_user_outlined,
                'Productos Originales',
                'Garantía de autenticidad en todos nuestros productos',
                primaryColor,
              ),
              _buildFeatureCard(
                Icons.support_agent_outlined,
                'Atención Personalizada',
                'Asesoramiento experto para encontrar lo que necesitas',
                primaryColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(
    IconData icon,
    String title,
    String description,
    Color primaryColor,
  ) {
    return SizedBox(
      width: 320,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(icon, size: 48, color: primaryColor),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBlock(
    Map<String, dynamic> data,
    Color primaryColor,
    Color accentColor,
  ) {
    final title = (data['title'] ?? 'Bienvenido') as String;
    final subtitle = (data['subtitle'] ?? '') as String;
    final ctaText =
        (data['ctaText'] ?? data['buttonText'] ?? 'Ver más').toString();
    final ctaLink =
        (data['ctaLink'] ?? data['buttonLink'] ?? '/tienda/productos')
            .toString();
    final imageUrl = data['imageUrl'];
    final showOverlay = (data['showOverlay'] ?? true) as bool;
    final overlayOpacity =
        ((data['overlayOpacity'] ?? 0.5) as num).clamp(0.0, 1.0).toDouble();

    final hasImage = imageUrl != null && imageUrl.toString().isNotEmpty;

    return Container(
      height: 480,
      width: double.infinity,
      decoration: BoxDecoration(
        image: hasImage
            ? DecorationImage(
                image: NetworkImage(imageUrl.toString()),
                fit: BoxFit.cover,
              )
            : null,
        gradient: !hasImage
            ? LinearGradient(
                colors: [
                  primaryColor,
                  accentColor.withOpacity(0.85),
                ],
              )
            : null,
      ),
      child: Container(
        decoration: showOverlay
            ? BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(overlayOpacity * 0.75),
                    Colors.black.withOpacity(overlayOpacity),
                  ],
                ),
              )
            : null,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: Colors.white,
                    ),
                textAlign: TextAlign.center,
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white70,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => context
                    .go(ctaLink.isNotEmpty ? ctaLink : '/tienda/productos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                ),
                child: Text(ctaText),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductsBlock(
    Map<String, dynamic> data,
    Color primaryColor,
    Color accentColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: _buildFeaturedProductsSection(primaryColor, accentColor),
    );
  }

  Widget _buildServicesBlock(Map<String, dynamic> data, Color primaryColor) {
    final title = data['title'] ?? 'Nuestros Servicios';
    final services = data['services'] as List? ?? [];

    if (services.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: services.map((service) {
              final serviceData = service as Map<String, dynamic>;
              return SizedBox(
                width: 300,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          _getIconData(serviceData['icon'] ?? 'star'),
                          size: 48,
                          color: primaryColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          serviceData['title'] ?? '',
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          serviceData['description'] ?? '',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutBlock(Map<String, dynamic> data) {
    final title = data['title'] ?? 'Sobre Nosotros';
    final content = data['content'] ?? '';

    if (content.toString().isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            content,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTestimonialsBlock(Map<String, dynamic> data) {
    return const SizedBox(height: 64);
  }

  Widget _buildFeaturesBlock(
    Map<String, dynamic> data,
    Color primaryColor,
    Color accentColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: _buildWhyChooseUsSection(primaryColor),
    );
  }

  Widget _buildCtaBlock(
    Map<String, dynamic> data,
    Color primaryColor,
    Color accentColor,
  ) {
    final title = data['title'] ?? 'Visita nuestra tienda';
    final buttonText =
        (data['buttonText'] ?? data['ctaText'] ?? 'Ver productos').toString();
    final buttonLink =
        (data['buttonLink'] ?? data['ctaLink'] ?? '/tienda/productos')
            .toString();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64),
      width: double.infinity,
      color: primaryColor,
      child: Center(
        child: Column(
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => context.go(
                buttonLink.isNotEmpty ? buttonLink : '/tienda/productos',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
              ),
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryBlock(Map<String, dynamic> data) {
    return const SizedBox(height: 64);
  }

  Widget _buildContactBlock(Map<String, dynamic> data) {
    return const SizedBox(height: 64);
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'directions_bike':
        return Icons.directions_bike;
      case 'build':
        return Icons.build;
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'star':
        return Icons.star;
      case 'favorite':
        return Icons.favorite;
      case 'support_agent':
        return Icons.support_agent;
      default:
        return Icons.star;
    }
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
