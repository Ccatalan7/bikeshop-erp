import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../theme/public_store_theme.dart';
import '../../shared/services/inventory_service.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/models/website_models.dart';
import '../../shared/models/product.dart';
import '../../shared/utils/chilean_utils.dart';

class PublicHomePage extends StatefulWidget {
  const PublicHomePage({super.key});

  @override
  State<PublicHomePage> createState() => _PublicHomePageState();
}

class _PublicHomePageState extends State<PublicHomePage> {
  List<WebsiteBanner> _banners = [];
  List<Product> _featuredProducts = [];
  bool _isLoading = true;

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

      // Load active banners
      await websiteService.loadBanners();
      _banners = websiteService.banners.where((b) => b.active).toList();

      // Load featured products
      await websiteService.loadFeaturedProducts();
      final featuredProductIds = websiteService.featuredProducts;
      
      final allProducts = await inventoryService.getProducts();
      
      _featuredProducts = allProducts
          .where((p) => featuredProductIds.any((fp) => fp.productId == p.id))
          .take(8)
          .toList();

    } catch (e) {
      debugPrint('[PublicHomePage] Error loading data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // Hero Section
          _buildHeroSection(),

          const SizedBox(height: 64),

          // Featured Products Section
          _buildFeaturedProductsSection(),

          const SizedBox(height: 64),

          // Categories Section
          _buildCategoriesSection(),

          const SizedBox(height: 64),

          // Why Choose Us Section
          _buildWhyChooseUsSection(),

          const SizedBox(height: 64),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    if (_banners.isEmpty) {
      // Default hero if no banners
      return Container(
        height: 500,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              PublicStoreTheme.primaryBlue,
              PublicStoreTheme.primaryBlue.withOpacity(0.8),
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
                  backgroundColor: Colors.white,
                  foregroundColor: PublicStoreTheme.primaryBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                ),
                child: const Text('VER PRODUCTOS'),
              ),
            ],
          ),
        ),
      );
    }

    // Use first active banner
    final banner = _banners.first;
    final hasImage = banner.imageUrl != null && banner.imageUrl!.isNotEmpty;

    return Container(
      height: 500,
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
                  PublicStoreTheme.primaryBlue,
                  PublicStoreTheme.primaryBlue.withOpacity(0.8),
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
              Colors.black.withOpacity(0.4),
              Colors.black.withOpacity(0.6),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                banner.title,
                style: Theme.of(context).textTheme.displayLarge,
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
                    if (banner.ctaLink != null && banner.ctaLink!.isNotEmpty) {
                      context.go(banner.ctaLink!);
                    } else {
                      context.go('/tienda/productos');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: PublicStoreTheme.primaryBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
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

  Widget _buildFeaturedProductsSection() {
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
              return _buildProductCard(_featuredProducts[index]);
            },
          ),
          
          const SizedBox(height: 32),
          
          Center(
            child: OutlinedButton(
              onPressed: () => context.go('/tienda/productos'),
              child: const Text('VER TODOS LOS PRODUCTOS'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    return InkWell(
      onTap: () => context.go('/tienda/producto/${product.id}'),
      child: Card(
        elevation: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
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
            
            // Product Info
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
                      color: PublicStoreTheme.primaryBlue,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesSection() {
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
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                            color: PublicStoreTheme.primaryBlue,
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

  Widget _buildWhyChooseUsSection() {
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
          
          Row(
            children: [
              Expanded(
                child: _buildFeatureCard(
                  Icons.local_shipping_outlined,
                  'Envío Rápido',
                  'Envíos a todo Chile en 24-48 horas',
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildFeatureCard(
                  Icons.verified_user_outlined,
                  'Productos Originales',
                  'Garantía de autenticidad en todos nuestros productos',
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildFeatureCard(
                  Icons.support_agent_outlined,
                  'Atención Personalizada',
                  'Asesoramiento experto para encontrar lo que necesitas',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(IconData icon, String title, String description) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              icon,
              size: 48,
              color: PublicStoreTheme.primaryBlue,
            ),
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
    );
  }
}
