import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../public_store/theme/public_store_theme.dart';
import '../../../shared/models/product.dart';
import '../../../shared/utils/chilean_utils.dart';

/// Renders website blocks using the same widgets as the public store so the
/// editor preview can stay in sync with the live site.
class WebsiteBlockRenderer {
  const WebsiteBlockRenderer._();

  static Widget build({
    required BuildContext context,
    required String blockType,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    List<Product>? featuredProducts,
    bool previewMode = false,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
    void Function(String route)? onNavigate,
  }) {
    switch (blockType) {
      case 'hero':
        return _buildHero(
          context: context,
          data: data,
          accentColor: accentColor,
          primaryColor: primaryColor,
          previewMode: previewMode,
          headingFont: headingFont,
          bodyFont: bodyFont,
          headingSize: headingSize,
          bodySize: bodySize,
          onNavigate: onNavigate,
        );
      case 'carousel':
        return _buildCarousel(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          previewMode: previewMode,
          headingFont: headingFont,
          bodyFont: bodyFont,
          headingSize: headingSize,
          bodySize: bodySize,
          onNavigate: onNavigate,
        );
      case 'products':
        return _buildProducts(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          featuredProducts: featuredProducts,
          previewMode: previewMode,
          bodyFont: bodyFont,
          onNavigate: onNavigate,
        );
      case 'services':
        return _buildServices(
          context: context,
          data: data,
          primaryColor: primaryColor,
          previewMode: previewMode,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case 'about':
        return _buildAbout(
          context: context,
          data: data,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case 'cta':
        return _buildCta(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          previewMode: previewMode,
          headingFont: headingFont,
          bodyFont: bodyFont,
          onNavigate: onNavigate,
        );
      case 'features':
        return _buildFeatures(context, primaryColor);
      case 'testimonials':
      case 'gallery':
      case 'contact':
        return const SizedBox(height: 64);
      default:
        return Container(
          padding: const EdgeInsets.all(64),
          child: Center(
            child: Text(
              blockType.toUpperCase(),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: PublicStoreTheme.textMuted),
            ),
          ),
        );
    }
  }

  static Widget _buildHero({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    bool previewMode = false,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
    void Function(String route)? onNavigate,
  }) {
    final theme = Theme.of(context);

    final title = (data['title'] ?? 'Bienvenido').toString().trim();
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final ctaText =
        (data['ctaText'] ?? data['buttonText'] ?? 'Ver más').toString().trim();
    final ctaLink =
        (data['ctaLink'] ?? data['buttonLink'] ?? '/tienda/productos')
            .toString()
            .trim();
    final imageUrl = data['imageUrl'];
    final showOverlay = (data['showOverlay'] ?? true) == true;
    final overlayOpacity =
        ((data['overlayOpacity'] ?? 0.5) as num).clamp(0.0, 1.0).toDouble();
    final hasImage = imageUrl != null && imageUrl.toString().isNotEmpty;

    final resolvedHeading = (theme.textTheme.displayLarge ?? const TextStyle())
        .copyWith(
      fontFamily: headingFont?.isNotEmpty == true ? headingFont : null,
      fontSize: headingSize,
      color: Colors.white,
    );

    final resolvedSubtitle =
        (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
      fontFamily: bodyFont?.isNotEmpty == true ? bodyFont : null,
      fontSize: bodySize != null ? bodySize * 1.2 : null,
      color: Colors.white70,
    );

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
              Text(title.isEmpty ? 'Título' : title,
                  style: resolvedHeading, textAlign: TextAlign.center),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(subtitle,
                    style: resolvedSubtitle, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: previewMode
                    ? () {}
                    : () {
                        final route =
                            ctaLink.isNotEmpty ? ctaLink : '/tienda/productos';
                        if (onNavigate != null) {
                          onNavigate(route);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                ),
                child: Text(ctaText.isEmpty ? 'Ver más' : ctaText),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildCarousel({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    bool previewMode = false,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
    void Function(String route)? onNavigate,
  }) {
    return _CarouselBanner(
      data: data,
      primaryColor: primaryColor,
      accentColor: accentColor,
      previewMode: previewMode,
      headingFont: headingFont,
      bodyFont: bodyFont,
      headingSize: headingSize,
      bodySize: bodySize,
      onNavigate: onNavigate,
    );
  }

  static Widget _buildProducts({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    List<Product>? featuredProducts,
    bool previewMode = false,
    String? bodyFont,
    void Function(String route)? onNavigate,
  }) {
    final theme = Theme.of(context);

    final rawTitle =
        (data['title'] ?? 'Productos Destacados').toString().trim();
    final title = rawTitle.isEmpty ? 'Productos Destacados' : rawTitle;

    int itemsPerRow = 4;
    final rawItemsPerRow = data['itemsPerRow'];
    if (rawItemsPerRow is int) {
      itemsPerRow = rawItemsPerRow;
    } else if (rawItemsPerRow is num) {
      itemsPerRow = rawItemsPerRow.toInt();
    } else if (rawItemsPerRow is String) {
      final parsed = int.tryParse(rawItemsPerRow);
      if (parsed != null) {
        itemsPerRow = parsed;
      }
    }
    itemsPerRow = itemsPerRow.clamp(2, 4);

    final products = (featuredProducts ?? [])
        .where((product) => product.isActive)
        .toList();

    final resolvedProducts = products.isNotEmpty
        ? products
        : _buildSampleProducts(max(itemsPerRow * 2, 4));

    return Container(
      constraints: const BoxConstraints(maxWidth: 1200),
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.displaySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Descubre nuestras mejores ofertas',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: PublicStoreTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: itemsPerRow,
              childAspectRatio: 0.75,
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
            ),
            itemCount: resolvedProducts.length,
            itemBuilder: (context, index) {
              final product = resolvedProducts[index];
              return _buildProductCard(
                context: context,
                product: product,
                primaryColor: primaryColor,
                accentColor: accentColor,
                bodyFont: bodyFont,
                previewMode: previewMode,
                onNavigate: onNavigate,
              );
            },
          ),
          const SizedBox(height: 32),
          Center(
            child: OutlinedButton(
              onPressed: previewMode
                  ? () {}
                  : () {
                      if (onNavigate != null) {
                        onNavigate('/tienda/productos');
                      }
                    },
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

  static Widget _buildServices({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    bool previewMode = false,
    String? headingFont,
    String? bodyFont,
  }) {
    final theme = Theme.of(context);
    final rawTitle = (data['title'] ?? 'Nuestros Servicios').toString().trim();
    final title = rawTitle.isEmpty ? 'Nuestros Servicios' : rawTitle;
    final rawServices = data['services'];

    List<Map<String, dynamic>> services = [];
    if (rawServices is List) {
      services = rawServices
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (services.isEmpty && previewMode) {
      services = [
        {
          'title': 'Servicio integral',
          'description': 'Mantenimiento completo de bicicletas',
          'icon': 'build',
        },
        {
          'title': 'Venta especializada',
          'description': 'Catálogo premium de bicicletas y accesorios',
          'icon': 'directions_bike',
        },
        {
          'title': 'Soporte experto',
          'description': 'Asesoría profesional para ciclistas',
          'icon': 'support_agent',
        },
      ];
    }

    if (services.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        children: [
          Text(
            title,
            style: theme.textTheme.displaySmall?.copyWith(
              fontFamily: headingFont,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: services.map((service) {
              final iconName = service['icon']?.toString();
              final serviceTitle = (service['title'] ?? 'Servicio').toString();
              final description =
                  (service['description'] ?? '').toString().trim();

              return SizedBox(
                width: 300,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          _getIconFromString(iconName),
                          size: 48,
                          color: primaryColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          serviceTitle,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontFamily: headingFont,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            description,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: bodyFont,
                              color: PublicStoreTheme.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
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

  static Widget _buildAbout({
    required BuildContext context,
    required Map<String, dynamic> data,
    String? headingFont,
    String? bodyFont,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? 'Sobre Nosotros').toString().trim();
    final content = (data['content'] ?? '').toString().trim();

    if (content.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        children: [
          Text(
            title.isEmpty ? 'Sobre Nosotros' : title,
            style: theme.textTheme.displaySmall?.copyWith(
              fontFamily: headingFont,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            content,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontFamily: bodyFont,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  static Widget _buildCta({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    bool previewMode = false,
    String? headingFont,
    String? bodyFont,
    void Function(String route)? onNavigate,
  }) {
    final theme = Theme.of(context);
    final title =
        (data['title'] ?? 'Visita nuestra tienda').toString().trim();
    final buttonText =
        (data['buttonText'] ?? data['ctaText'] ?? 'Ver productos')
            .toString()
            .trim();
    final buttonLink =
        (data['buttonLink'] ?? data['ctaLink'] ?? '/tienda/productos')
            .toString()
            .trim();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64),
      width: double.infinity,
      color: primaryColor,
      child: Center(
        child: Column(
          children: [
            Text(
              title.isEmpty ? 'Visita nuestra tienda' : title,
              style: theme.textTheme.displaySmall?.copyWith(
                fontFamily: headingFont,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: previewMode
                  ? () {}
                  : () {
                      final route =
                          buttonLink.isNotEmpty ? buttonLink : '/tienda/productos';
                      if (onNavigate != null) {
                        onNavigate(route);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
              ),
              child: Text(
                buttonText.isEmpty ? 'Ver productos' : buttonText,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: bodyFont,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildFeatures(BuildContext context, Color primaryColor) {
    // The public site currently reuses the "Why choose us" section. Keep the
    // same helper here for consistency.
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Text(
            '¿Por qué elegirnos?',
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: [
              _buildFeatureCard(
                context,
                icon: Icons.verified,
                title: 'Servicio certificado',
                description: 'Técnicos con amplia experiencia en bicicletas.',
                primaryColor: primaryColor,
              ),
              _buildFeatureCard(
                context,
                icon: Icons.pedal_bike,
                title: 'Variedad de productos',
                description: 'Catálogo actualizado con las mejores marcas.',
                primaryColor: primaryColor,
              ),
              _buildFeatureCard(
                context,
                icon: Icons.support_agent,
                title: 'Acompañamiento experto',
                description: 'Te ayudamos a elegir la bicicleta perfecta.',
                primaryColor: primaryColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _buildProductCard({
    required BuildContext context,
    required Product product,
    required Color primaryColor,
    required Color accentColor,
    String? bodyFont,
    bool previewMode = false,
    void Function(String route)? onNavigate,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: previewMode
          ? () {}
          : () {
              if (onNavigate != null) {
                onNavigate('/tienda/producto/${product.id}');
              }
            },
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
                child: product.imageUrl != null && product.imageUrl!.isNotEmpty
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
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: bodyFont,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ChileanUtils.formatCurrency(product.price),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontFamily: bodyFont,
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    product.stockQuantity > 0
                        ? 'Stock disponible'
                        : 'Sin stock',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: bodyFont,
                      color: product.stockQuantity > 0
                          ? PublicStoreTheme.success
                          : PublicStoreTheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: previewMode
                        ? () {}
                        : () {
                            if (onNavigate != null) {
                              onNavigate('/tienda/producto/${product.id}');
                            }
                          },
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

  static Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color primaryColor,
  }) {
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

  static List<Product> _buildSampleProducts(int count) {
    return List.generate(count, (index) {
      final now = DateTime.now();
      return Product(
        id: 'preview-product-$index',
        name: 'Producto ${index + 1}',
        sku: 'PREVIEW-${index + 1}',
        price: 99990,
        cost: 65000,
        stockQuantity: index.isEven ? 8 : 0,
        imageUrl: null,
        imageUrls: const [],
        description: 'Producto de demostración',
        category: ProductCategory.other,
        categoryId: null,
        categoryName: 'Demo',
        brand: 'Vinabike',
        model: 'Preview',
        specifications: const {},
        tags: const [],
        unit: ProductUnit.unit,
        weight: 0,
        trackStock: true,
        isActive: true,
        productType: ProductType.product,
        createdAt: now,
        updatedAt: now,
      );
    });
  }

  static IconData _getIconFromString(String? iconName) {
    switch (iconName) {
      case 'directions_bike':
        return Icons.directions_bike;
      case 'build':
        return Icons.build;
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'support_agent':
        return Icons.support_agent;
      case 'favorite':
        return Icons.favorite;
      case 'star':
        return Icons.star;
      default:
        return Icons.star;
    }
  }
}

enum _CarouselAnimation { slide, fade, zoom }

class _CarouselBanner extends StatefulWidget {
  const _CarouselBanner({
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    required this.previewMode,
    this.headingFont,
    this.bodyFont,
    this.headingSize,
    this.bodySize,
    this.onNavigate,
  });

  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;
  final bool previewMode;
  final String? headingFont;
  final String? bodyFont;
  final double? headingSize;
  final double? bodySize;
  final void Function(String route)? onNavigate;

  @override
  State<_CarouselBanner> createState() => _CarouselBannerState();
}

class _CarouselBannerState extends State<_CarouselBanner> {
  late List<Map<String, dynamic>> _slides;
  int _currentIndex = 0;
  late bool _autoPlay;
  late bool _showIndicators;
  late bool _showArrows;
  late Duration _interval;
  late _CarouselAnimation _animation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refreshConfiguration(resetIndex: true);
  }

  @override
  void didUpdateWidget(covariant _CarouselBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    setState(_refreshConfiguration);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refreshConfiguration({bool resetIndex = false}) {
    _slides = _parseSlides(widget.data);
    if (_slides.isEmpty) {
      _slides = _defaultSlides();
    }

    if (resetIndex || _currentIndex >= _slides.length) {
      _currentIndex = 0;
    }

    _autoPlay = (widget.data['autoPlay'] ?? true) == true;
    _showIndicators = (widget.data['showIndicators'] ?? true) == true;
    _showArrows = (widget.data['showArrows'] ?? true) == true;
    _interval = Duration(seconds: _parseInterval(widget.data['intervalSeconds']));
    _animation = _parseAnimation(widget.data['animation']);

    _restartTimer();
  }

  @override
  Widget build(BuildContext context) {
    if (_slides.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 480,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: _buildTransition,
            child: _buildSlide(context, _slides[_currentIndex], _currentIndex),
          ),
          if (_showIndicators && _slides.length > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (index) {
                  final isActive = index == _currentIndex;
                  return GestureDetector(
                    onTap: () => _goToSlide(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 28 : 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isActive
                            ? widget.accentColor
                            : Colors.white.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }),
              ),
            ),
          if (_showArrows && _slides.length > 1) ...[
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: _buildArrowButton(
                  icon: Icons.chevron_left,
                  onTap: _previousSlide,
                ),
              ),
            ),
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: _buildArrowButton(
                  icon: Icons.chevron_right,
                  onTap: _nextSlide,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSlide(
    BuildContext context,
    Map<String, dynamic> slide,
    int index,
  ) {
    final theme = Theme.of(context);
    final title = (slide['title'] ?? 'Título').toString().trim();
    final subtitle = (slide['subtitle'] ?? '').toString().trim();
    final ctaText = (slide['ctaText'] ?? 'Ver más').toString().trim();
    final ctaLink = (slide['ctaLink'] ?? '/tienda/productos').toString().trim();
    final imageUrl = slide['imageUrl'];
    final showOverlay = (slide['showOverlay'] ?? true) == true;

    double overlayOpacity = 0.55;
    final rawOverlay = slide['overlayOpacity'];
    if (rawOverlay is num) {
      overlayOpacity = rawOverlay.toDouble();
    } else if (rawOverlay is String) {
      overlayOpacity = double.tryParse(rawOverlay) ?? 0.55;
    }
    overlayOpacity = overlayOpacity.clamp(0.0, 1.0);

    final hasImage = imageUrl != null && imageUrl.toString().isNotEmpty;

    final headingStyle = (theme.textTheme.displayLarge ?? const TextStyle()).copyWith(
      fontFamily: widget.headingFont?.isNotEmpty == true ? widget.headingFont : null,
      fontSize: widget.headingSize,
      color: Colors.white,
    );

    final subtitleStyle = (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
      fontFamily: widget.bodyFont?.isNotEmpty == true ? widget.bodyFont : null,
      fontSize: widget.bodySize != null ? widget.bodySize! * 1.2 : null,
      color: Colors.white70,
    );

    return Container(
      key: ValueKey<int>(index),
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
                  widget.primaryColor,
                  widget.accentColor.withOpacity(0.85),
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
                    Colors.black.withOpacity(overlayOpacity * 0.7),
                    Colors.black.withOpacity(overlayOpacity),
                  ],
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title.isEmpty ? 'Título' : title,
                    style: headingStyle,
                    textAlign: TextAlign.center,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      subtitle,
                      style: subtitleStyle,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 32),
                  if (ctaText.isNotEmpty)
                    ElevatedButton(
                      onPressed: widget.previewMode
                          ? () {}
                          : () {
                              final route =
                                  ctaLink.isNotEmpty ? ctaLink : '/tienda/productos';
                              if (widget.onNavigate != null) {
                                widget.onNavigate!(route);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 20,
                        ),
                      ),
                      child: Text(
                        ctaText,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: widget.bodyFont,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransition(Widget child, Animation<double> animation) {
    switch (_animation) {
      case _CarouselAnimation.fade:
        return FadeTransition(opacity: animation, child: child);
      case _CarouselAnimation.zoom:
        final scaleAnimation = Tween<double>(begin: 0.95, end: 1).animate(animation);
        return ScaleTransition(scale: scaleAnimation, child: child);
      case _CarouselAnimation.slide:
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.15, 0),
          end: Offset.zero,
        ).animate(animation);
        return ClipRect(
          child: SlideTransition(
            position: offsetAnimation,
            child: child,
          ),
        );
    }
  }

  Widget _buildArrowButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }

  void _nextSlide() {
    if (!mounted || _slides.length <= 1) return;
    setState(() {
      _currentIndex = (_currentIndex + 1) % _slides.length;
    });
  }

  void _previousSlide() {
    if (!mounted || _slides.length <= 1) return;
    setState(() {
      _currentIndex = (_currentIndex - 1 + _slides.length) % _slides.length;
    });
    _restartTimer();
  }

  void _goToSlide(int index) {
    if (!mounted || index < 0 || index >= _slides.length) return;
    setState(() {
      _currentIndex = index;
    });
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (!_autoPlay || _slides.length <= 1) {
      return;
    }
    _timer = Timer.periodic(_interval, (_) => _nextSlide());
  }

  List<Map<String, dynamic>> _parseSlides(Map<String, dynamic> data) {
    final rawSlides = data['slides'];
    if (rawSlides is List) {
      return rawSlides
          .whereType<Map>()
          .map((slide) => Map<String, dynamic>.from(slide))
          .toList();
    }
    return [];
  }

  List<Map<String, dynamic>> _defaultSlides() {
    return [
      {
        'title': 'Descubre la tienda',
        'subtitle': 'Todo lo que necesitas para tu bicicleta en un solo lugar',
        'ctaText': 'Ver catálogo',
        'ctaLink': '/tienda/productos',
        'imageUrl': null,
        'showOverlay': true,
        'overlayOpacity': 0.55,
      },
      {
        'title': 'Servicio técnico certificado',
        'subtitle': 'Agenda tu mantención sin salir de casa',
        'ctaText': 'Agendar ahora',
        'ctaLink': '/tienda/servicios',
        'imageUrl': null,
        'showOverlay': true,
        'overlayOpacity': 0.55,
      },
    ];
  }

  int _parseInterval(dynamic value) {
    if (value is num) {
      return max(1, value.toInt());
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return max(1, parsed);
      }
    }
    return 5;
  }

  _CarouselAnimation _parseAnimation(dynamic value) {
    final raw = value?.toString().toLowerCase();
    switch (raw) {
      case 'fade':
        return _CarouselAnimation.fade;
      case 'zoom':
        return _CarouselAnimation.zoom;
      default:
        return _CarouselAnimation.slide;
    }
  }
}
