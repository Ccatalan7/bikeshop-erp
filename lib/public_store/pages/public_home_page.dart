import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/website/models/website_models.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/widgets/website_block_renderer.dart';
import '../../shared/models/product.dart';
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

  static const List<String> _responsiveBreakpoints = [
    'desktop',
    'tablet',
    'mobile'
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _currentBreakpoint(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 640) {
      return 'mobile';
    }
    if (width < 1024) {
      return 'tablet';
    }
    return 'desktop';
  }

  bool? _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' ||
          normalized == '1' ||
          normalized == 'si' ||
          normalized == 'sí') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return null;
  }

  Map<String, bool> _normalizeBlockVisibility(dynamic raw) {
    final visibility = {
      for (final breakpoint in _responsiveBreakpoints) breakpoint: true,
    };

    dynamic source = raw;

    if (source is String) {
      final trimmed = source.trim();
      if (trimmed.isEmpty) {
        source = null;
      } else {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) {
            source = decoded;
          }
        } catch (_) {
          source = null;
        }
      }
    }

    if (source is Map) {
      source.forEach((key, value) {
        final keyString = key.toString();
        if (!visibility.containsKey(keyString)) {
          return;
        }
        final parsed = _toBool(value);
        if (parsed != null) {
          visibility[keyString] = parsed;
        }
      });
    }

    return visibility;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final websiteService = context.read<WebsiteService>();

      if (websiteService.settings.isEmpty) {
        await websiteService.loadSettings();
      }

      await websiteService.loadBlocks();

      await websiteService.loadBanners();
      _banners =
          websiteService.banners.where((banner) => banner.active).toList();

      await websiteService.loadFeaturedProducts();
      final featuredEntries =
          websiteService.featuredProducts.where((fp) => fp.active).toList();

      _featuredProducts = await _fetchFeaturedProducts(featuredEntries);
    } catch (error) {
      debugPrint('[PublicHomePage] Error loading data: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<List<Product>> _fetchFeaturedProducts(
    List<FeaturedProduct> featuredEntries,
  ) async {
    if (featuredEntries.isEmpty) {
      return const [];
    }

    final productIds =
        featuredEntries.map((entry) => entry.productId).toSet().toList();

    try {
      final response = await Supabase.instance.client
          .from('products')
          .select()
      .inFilter('id', productIds)
      .eq('show_on_website', true)
      .eq('is_active', true);

      final productsById = <String, Product>{};
      for (final row in response as List<dynamic>) {
        try {
          final map = Map<String, dynamic>.from(row as Map);
          final product = _productFromMap(map);
          productsById[product.id] = product;
        } catch (error) {
          debugPrint('[PublicHomePage] Failed to parse product: $error');
        }
      }

      final orderedProducts = <Product>[];
      for (final entry in featuredEntries
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex))) {
        final product = productsById[entry.productId];
        if (product != null) {
          orderedProducts.add(product);
        }
      }

      return orderedProducts.take(8).toList();
    } catch (error) {
      debugPrint(
          '[PublicHomePage] Error fetching featured product details: $error');
      return const [];
    }
  }

  Product _productFromMap(Map<String, dynamic> json) {
    final price = (json['price'] as num?)?.toDouble() ?? 0.0;
    final cost = (json['cost'] as num?)?.toDouble() ?? 0.0;
    final stockQuantity =
        json['inventory_qty'] as int? ?? json['stock_quantity'] as int? ?? 0;
    final minStock =
        json['min_stock_level'] as int? ?? json['min_stock'] as int? ?? 0;
    final maxStock =
        json['max_stock_level'] as int? ?? json['max_stock'] as int? ?? 0;
    final categoryValue = (json['category'] as String?) ?? 'other';

    final productTypeValue = (json['product_type'] as String?)?.toLowerCase();

    return Product(
      id: json['id']?.toString() ?? '',
      name: (json['name'] as String?) ?? 'Sin nombre',
      sku: (json['sku'] as String?) ?? '',
      barcode: json['barcode'] as String?,
      price: price,
      cost: cost,
      stockQuantity: stockQuantity,
      minStockLevel: minStock,
      maxStockLevel: maxStock > 0 ? maxStock : 100,
      imageUrl: json['image_url'] as String?,
      imageUrls: (json['image_urls'] as List?)?.cast<String>() ?? const [],
      description: json['description'] as String?,
      category: ProductCategory.values.firstWhere(
        (c) => c.name == categoryValue,
        orElse: () => ProductCategory.other,
      ),
      categoryId: json['category_id']?.toString(),
      categoryName: json['category_name'] as String?,
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      specifications:
          Map<String, String>.from(json['specifications'] as Map? ?? {}),
      tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      unit: ProductUnit.values.firstWhere(
        (u) => u.name == json['unit'],
        orElse: () => ProductUnit.unit,
      ),
      weight: (json['weight'] as num?)?.toDouble() ?? 0.0,
      trackStock: json['track_stock'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
      productType: ProductType.values.firstWhere(
        (t) => t.name == productTypeValue,
        orElse: () => ProductType.product,
      ),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    try {
      final dynamic dynamicValue = value;
      final result = dynamicValue.toDate();
      if (result is DateTime) {
        return result;
      }
    } catch (_) {
      // Ignore conversion errors and fallback below.
    }
    return DateTime.now();
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
    final headingFont = websiteService.getSetting('theme_heading_font', '');
    final bodyFont = websiteService.getSetting('theme_body_font', '');
    final headingSize = _resolveDouble(
      websiteService.getSetting('theme_heading_size', ''),
      48.0,
      min: 24.0,
      max: 72.0,
    );
    final bodySize = _resolveDouble(
      websiteService.getSetting('theme_body_size', ''),
      16.0,
      min: 12.0,
      max: 24.0,
    );
    final textColor = _resolveColor(
      websiteService.getSetting('theme_text_color', ''),
      PublicStoreTheme.textPrimary,
    );
    final sectionSpacing = _resolveDouble(
      websiteService.getSetting('theme_section_spacing', ''),
      64.0,
      min: 32.0,
      max: 128.0,
    );
    final containerPadding = _resolveDouble(
      websiteService.getSetting('theme_container_padding', ''),
      24.0,
      min: 16.0,
      max: 64.0,
    );

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentBreakpoint = _currentBreakpoint(context);

    final visibleBlocks = List<Map<String, dynamic>>.from(
      websiteService.blocks.where((block) {
        final isGloballyVisible = block['is_visible'] ?? true;
        if (!isGloballyVisible) {
          return false;
        }

        final data = Map<String, dynamic>.from(block['block_data'] ?? {});
        final visibility = _normalizeBlockVisibility(data['visibility']);
        return visibility[currentBreakpoint] ?? true;
      }),
    )..sort(
        (a, b) => (a['order_index'] ?? 0).compareTo(b['order_index'] ?? 0),
      );

    if (visibleBlocks.isNotEmpty) {
      return SingleChildScrollView(
        child: Column(
          children: [
            for (final block in visibleBlocks)
              _buildBlockFromData(
                block,
                primaryColor,
                accentColor,
                headingFont: headingFont,
                bodyFont: bodyFont,
                headingSize: headingSize,
                bodySize: bodySize,
                textColor: textColor,
                sectionSpacing: sectionSpacing,
                containerPadding: containerPadding,
              ),
            SizedBox(height: sectionSpacing),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(
                bodyColor: textColor,
                displayColor: textColor,
              ),
        ),
        child: Column(
          children: [
            _buildHeroSection(primaryColor, accentColor),
            SizedBox(height: sectionSpacing),
            _buildFeaturedProductsSection(primaryColor, accentColor),
            SizedBox(height: sectionSpacing),
            _buildCategoriesSection(primaryColor),
            SizedBox(height: sectionSpacing),
            _buildWhyChooseUsSection(primaryColor),
            SizedBox(height: sectionSpacing),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockFromData(
    Map<String, dynamic> blockData,
    Color primaryColor,
    Color accentColor, {
    required String headingFont,
    required String bodyFont,
    required double headingSize,
    required double bodySize,
    required Color textColor,
    required double sectionSpacing,
    required double containerPadding,
  }) {
    final blockType = (blockData['block_type'] ?? '').toString();
    final data = Map<String, dynamic>.from(blockData['block_data'] ?? {});
    data.remove('visibility');
    final resolvedHeadingFont = headingFont.isNotEmpty ? headingFont : null;
    final resolvedBodyFont = bodyFont.isNotEmpty ? bodyFont : null;

    final baseTheme = Theme.of(context);
    final themedText = baseTheme.textTheme.apply(
      bodyColor: textColor,
      displayColor: textColor,
    );

    final horizontalPadding = containerPadding.clamp(0.0, 200.0).toDouble();
    final verticalPadding = (sectionSpacing / 2).clamp(0.0, 200.0).toDouble();

    final content = WebsiteBlockRenderer.build(
      context: context,
      blockType: blockType,
      data: data,
      primaryColor: primaryColor,
      accentColor: accentColor,
      featuredProducts: blockType == 'products' ? _featuredProducts : null,
      previewMode: false,
      headingFont: resolvedHeadingFont,
      bodyFont: resolvedBodyFont,
      headingSize: headingSize,
      bodySize: bodySize,
      onNavigate: (route) => context.go(route),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        verticalPadding,
        horizontalPadding,
        verticalPadding,
      ),
      child: Theme(
        data: baseTheme.copyWith(textTheme: themedText),
        child: content,
      ),
    );
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
              childAspectRatio: 0.68,
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

  double _resolveDouble(
    String raw,
    double fallback, {
    double? min,
    double? max,
  }) {
    final value = raw.trim();
    if (value.isEmpty) {
      return fallback;
    }

    final parsed = double.tryParse(value);
    if (parsed == null) {
      return fallback;
    }

    var result = parsed;
    if (min != null && result < min) {
      result = min;
    }
    if (max != null && result > max) {
      result = max;
    }
    return result;
  }
}
