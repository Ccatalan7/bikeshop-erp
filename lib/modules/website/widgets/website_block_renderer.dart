import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../public_store/theme/public_store_theme.dart';
import '../../../shared/models/product.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/website_block_type.dart';

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
    final type = parseWebsiteBlockType(blockType);

    switch (type) {
      case WebsiteBlockType.hero:
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
      case WebsiteBlockType.carousel:
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
      case WebsiteBlockType.products:
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
      case WebsiteBlockType.services:
        return _buildServices(
          context: context,
          data: data,
          primaryColor: primaryColor,
          previewMode: previewMode,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case WebsiteBlockType.about:
        return _buildAbout(
          context: context,
          data: data,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case WebsiteBlockType.cta:
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
      case WebsiteBlockType.features:
        return _buildFeatures(
          context: context,
          data: data,
          primaryColor: primaryColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case WebsiteBlockType.testimonials:
        return _buildTestimonials(
          context: context,
          data: data,
          primaryColor: primaryColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
          previewMode: previewMode,
        );
      case WebsiteBlockType.pricing:
        return _buildPricing(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
          previewMode: previewMode,
          onNavigate: onNavigate,
        );
      case WebsiteBlockType.gallery:
        return _buildGallery(
          context: context,
          data: data,
          primaryColor: primaryColor,
          previewMode: previewMode,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case WebsiteBlockType.contact:
        return _buildContact(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
          previewMode: previewMode,
          onNavigate: onNavigate,
        );
      case WebsiteBlockType.faq:
        return _buildFaq(
          context: context,
          data: data,
          primaryColor: primaryColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case WebsiteBlockType.stats:
        return _buildStats(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
        );
      case WebsiteBlockType.team:
        return _buildTeam(
          context: context,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          headingFont: headingFont,
          bodyFont: bodyFont,
          previewMode: previewMode,
        );
      case WebsiteBlockType.footer:
        return const SizedBox(height: 64);
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

    final resolvedHeading =
        (theme.textTheme.displayLarge ?? const TextStyle()).copyWith(
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
        .where((product) => product.isActive && product.isPublished)
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
              childAspectRatio: 0.68,
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
    final title = (data['title'] ?? 'Visita nuestra tienda').toString().trim();
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
                      final route = buttonLink.isNotEmpty
                          ? buttonLink
                          : '/tienda/productos';
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

  static Widget _buildFeatures({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    String? headingFont,
    String? bodyFont,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? '¿Por qué elegirnos?').toString();
    final featuresRaw = data['features'];
    final features = (featuresRaw is List)
        ? featuresRaw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Text(
            title.isEmpty ? 'Características' : title,
            style: theme.textTheme.displaySmall?.copyWith(
              fontFamily: headingFont,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          if (features.isEmpty)
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
                  headingFont: headingFont,
                  bodyFont: bodyFont,
                ),
                _buildFeatureCard(
                  context,
                  icon: Icons.pedal_bike,
                  title: 'Variedad de productos',
                  description: 'Catálogo actualizado con las mejores marcas.',
                  primaryColor: primaryColor,
                  headingFont: headingFont,
                  bodyFont: bodyFont,
                ),
                _buildFeatureCard(
                  context,
                  icon: Icons.support_agent,
                  title: 'Acompañamiento experto',
                  description: 'Te ayudamos a elegir la bicicleta perfecta.',
                  primaryColor: primaryColor,
                  headingFont: headingFont,
                  bodyFont: bodyFont,
                ),
              ],
            )
          else
            Wrap(
              spacing: 24,
              runSpacing: 24,
              alignment: WrapAlignment.center,
              children: features.map((item) {
                final rawIcon = item['icon']?.toString();
                final icon = _getIconFromString(rawIcon);
                return _buildFeatureCard(
                  context,
                  icon: icon,
                  title: item['title']?.toString() ?? 'Título',
                  description: item['description']?.toString() ?? 'Descripción',
                  primaryColor: primaryColor,
                  headingFont: headingFont,
                  bodyFont: bodyFont,
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  static Widget _buildTestimonials({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    String? headingFont,
    String? bodyFont,
    bool previewMode = false,
  }) {
    final theme = Theme.of(context);
    final rawTitle = (data['title'] ?? 'Testimonios').toString().trim();
    final title = rawTitle.isEmpty ? 'Testimonios' : rawTitle;
    final rawTestimonials = data['testimonials'];

    var testimonials = <Map<String, dynamic>>[];
    if (rawTestimonials is List) {
      testimonials = rawTestimonials
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (testimonials.isEmpty && previewMode) {
      testimonials = [
        {
          'name': 'Carolina M.',
          'role': 'Ciclista urbana',
          'comment':
              '“Me ayudaron a dejar mi bicicleta como nueva y fueron súper rápidos.”',
          'rating': 5,
        },
        {
          'name': 'Luis P.',
          'role': 'Mountain biker',
          'comment':
              '“Excelente servicio y atención. Siempre tienen repuestos de calidad.”',
          'rating': 5,
        },
        {
          'name': 'Paula G.',
          'role': 'Cicloturista',
          'comment':
              '“El equipo es muy dedicado y se nota la pasión por el ciclismo.”',
          'rating': 4,
        },
      ];
    }

    if (testimonials.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.25),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: headingFont,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: testimonials
                    .map(
                      (item) => SizedBox(
                        width: 320,
                        child: _buildTestimonialCard(
                          context: context,
                          testimonial: item,
                          primaryColor: primaryColor,
                          bodyFont: bodyFont,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildPricing({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    String? headingFont,
    String? bodyFont,
    bool previewMode = false,
    void Function(String route)? onNavigate,
  }) {
    final theme = Theme.of(context);
    final rawTitle = (data['title'] ?? 'Planes y Precios').toString().trim();
    final title = rawTitle.isEmpty ? 'Planes y Precios' : rawTitle;
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final rawPlans = data['plans'];

    var plans = <Map<String, dynamic>>[];
    if (rawPlans is List) {
      plans = rawPlans
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (plans.isEmpty && previewMode) {
      plans = [
        {
          'name': 'Mantención Básica',
          'price': '29.990',
          'features': [
            'Revisión de frenos',
            'Ajuste de cambios',
            'Limpieza básica',
          ],
          'ctaText': 'Reservar',
          'ctaLink': '/tienda/productos',
        },
        {
          'name': 'Full Service',
          'price': '59.990',
          'features': [
            'Incluye plan básico',
            'Lubricación completa',
            'Ajuste integral',
          ],
          'ctaText': 'Agendar',
          'ctaLink': '/tienda/productos',
          'highlighted': true,
        },
        {
          'name': 'Elite Racing',
          'price': '89.990',
          'features': [
            'Servicio avanzado de suspensión',
            'Lavado premium',
            'Entrega prioritaria',
          ],
          'ctaText': 'Contactar',
          'ctaLink': '/tienda/productos',
        },
      ];
    }

    if (plans.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.15),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: headingFont,
                ),
                textAlign: TextAlign.center,
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: bodyFont,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 40),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: plans
                    .map(
                      (plan) => SizedBox(
                        width: 320,
                        child: _buildPricingPlanCard(
                          context: context,
                          plan: plan,
                          primaryColor: primaryColor,
                          accentColor: accentColor,
                          bodyFont: bodyFont,
                          previewMode: previewMode,
                          onNavigate: onNavigate,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildTestimonialCard({
    required BuildContext context,
    required Map<String, dynamic> testimonial,
    required Color primaryColor,
    String? bodyFont,
  }) {
    final theme = Theme.of(context);
    final name = (testimonial['name'] ?? 'Cliente').toString().trim();
    final role = (testimonial['role'] ?? '').toString().trim();
    final comment = (testimonial['comment'] ?? '').toString().trim();
    final ratingRaw = testimonial['rating'];

    int rating = 5;
    if (ratingRaw is num) {
      rating = ratingRaw.clamp(1, 5).round();
    } else if (ratingRaw is String) {
      final parsed = int.tryParse(ratingRaw);
      if (parsed != null) {
        rating = parsed.clamp(1, 5);
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.format_quote,
              color: primaryColor,
              size: 32,
            ),
            const SizedBox(height: 16),
            Text(
              comment.isEmpty
                  ? 'Agrega testimonios reales desde el editor.'
                  : comment,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFamily: bodyFont,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                ...List.generate(5, (index) {
                  final filled = index < rating;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      filled ? Icons.star : Icons.star_border,
                      color: filled
                          ? primaryColor
                          : theme.colorScheme.onSurfaceVariant,
                      size: 18,
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              name.isEmpty ? 'Cliente' : name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: bodyFont,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (role.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                role,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: bodyFont,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _buildPricingPlanCard({
    required BuildContext context,
    required Map<String, dynamic> plan,
    required Color primaryColor,
    required Color accentColor,
    String? bodyFont,
    bool previewMode = false,
    void Function(String route)? onNavigate,
  }) {
    final theme = Theme.of(context);
    final name = (plan['name'] ?? 'Plan').toString().trim();
    final priceRaw = (plan['price'] ?? '0').toString().trim();
    final featuresRaw = plan['features'];
    final ctaText = (plan['ctaText'] ?? 'Seleccionar').toString().trim();
    final ctaLink = (plan['ctaLink'] ?? '').toString().trim();
    final isHighlighted =
        plan['highlighted'] == true || plan['isFeatured'] == true;

    final features = <String>[];
    if (featuresRaw is List) {
      features
        ..clear()
        ..addAll(featuresRaw
            .where((item) => item != null)
            .map((item) => item.toString())
            .where((item) => item.isNotEmpty));
    }

    final hasCurrency = RegExp(r'[A-Za-z\$]').hasMatch(priceRaw);
    final priceLabel = priceRaw.isEmpty
        ? 'CLP 0'
        : hasCurrency
            ? priceRaw
            : 'CLP $priceRaw';

    final cardColor = isHighlighted
        ? accentColor.withOpacity(0.12)
        : theme.colorScheme.surface;
    final borderColor = isHighlighted ? accentColor : theme.dividerColor;

    return Card(
      color: cardColor,
      elevation: isHighlighted ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isHighlighted) ...[
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Más popular',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              name.isEmpty ? 'Plan' : name,
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: bodyFont,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              priceLabel,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontFamily: bodyFont,
                color: primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            if (features.isEmpty)
              Text(
                'Agrega beneficios desde el editor.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: bodyFont,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...features.map(
                (feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle, color: primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feature,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: bodyFont,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: previewMode || ctaLink.isEmpty
                  ? null
                  : () => onNavigate?.call(ctaLink),
              style: ElevatedButton.styleFrom(
                backgroundColor: isHighlighted ? accentColor : primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(ctaText.isEmpty ? 'Seleccionar' : ctaText),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildGallery({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    bool previewMode = false,
    String? headingFont,
    String? bodyFont,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? 'Galería').toString().trim();
    final layout = (data['layout'] ?? 'grid').toString();
    final rawImages = data['images'];

    var images = <Map<String, dynamic>>[];
    if (rawImages is List) {
      images = rawImages
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (images.isEmpty) {
      images = [
        {
          'imageUrl':
              'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=900&q=60',
          'caption': 'Agrega fotos reales desde el editor.',
        },
        {
          'imageUrl':
              'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=900&q=60',
          'caption': 'Esta es una imagen de ejemplo.',
        },
        {
          'imageUrl':
              'https://images.unsplash.com/photo-1489515217757-5fd1be406fef?auto=format&fit=crop&w=900&q=60',
          'caption': 'Sustituye las imágenes para personalizar tu galería.',
        },
      ];
    }

    final useMasonry = layout == 'masonry';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title.isEmpty ? 'Galería' : title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: headingFont,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 900
                      ? 3
                      : constraints.maxWidth >= 600
                          ? 2
                          : 1;
                  final itemWidth =
                      (constraints.maxWidth - (16 * (columns - 1))) / columns;

                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: images.asMap().entries.map((entry) {
                      final index = entry.key;
                      final image = entry.value;
                      final imageUrl =
                          (image['imageUrl'] ?? '').toString().trim();
                      final caption =
                          (image['caption'] ?? '').toString().trim();
                      final aspectRatio = useMasonry
                          ? (index % 3 == 0
                              ? 1.2
                              : index % 3 == 1
                                  ? 0.8
                                  : 1.0)
                          : 1.0;

                      return SizedBox(
                        width: itemWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: aspectRatio,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  color: theme.colorScheme.surfaceVariant,
                                  child: imageUrl.isEmpty
                                      ? Center(
                                          child: Icon(
                                            Icons.image_outlined,
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        )
                                      : Image.network(
                                          imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            return Center(
                                              child: Icon(
                                                Icons.broken_image,
                                                color: theme.colorScheme.error,
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ),
                            ),
                            if (caption.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                caption,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: bodyFont,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              if (!previewMode)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    'Optimiza tus imágenes antes de subirlas para mejorar el rendimiento.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildFaq({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    String? headingFont,
    String? bodyFont,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? 'Preguntas frecuentes').toString().trim();
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final rawItems = data['items'];

    var items = <Map<String, dynamic>>[];
    if (rawItems is List) {
      items = rawItems
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (items.isEmpty) {
      items = [
        {
          'question': '¿Cómo agendo una mantención?',
          'answer':
              'Puedes agendar directamente desde el botón “Reservar” del sitio o escribirnos por WhatsApp.',
        },
        {
          'question': '¿Trabajan con bicicletas eléctricas?',
          'answer':
              'Sí, contamos con técnicos certificados y repuestos para e-bikes.',
        },
      ];
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title.isEmpty ? 'Preguntas frecuentes' : title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: headingFont,
                ),
                textAlign: TextAlign.center,
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: bodyFont,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              ...items.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Theme(
                    data: theme.copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      iconColor: primaryColor,
                      collapsedIconColor: primaryColor,
                      title: Text(
                        (item['question'] ?? 'Pregunta').toString(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: headingFont,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      childrenPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      children: [
                        Text(
                          (item['answer'] ?? 'Agrega una respuesta clara.')
                              .toString(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: bodyFont,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildStats({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    String? headingFont,
    String? bodyFont,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? 'Resultados').toString().trim();
    final rawMetrics = data['metrics'];

    var metrics = <Map<String, dynamic>>[];
    if (rawMetrics is List) {
      metrics = rawMetrics
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (metrics.isEmpty) {
      metrics = [
        {
          'label': 'Bicis reparadas',
          'value': '1200',
          'suffix': '+',
        },
        {
          'label': 'Clientes felices',
          'value': '980',
          'suffix': '+',
        },
        {
          'label': 'Años de experiencia',
          'value': '10',
        },
      ];
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title.isEmpty ? 'Indicadores' : title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: headingFont,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: metrics.map((metric) {
                  final label = (metric['label'] ?? 'Indicador').toString();
                  final value = (metric['value'] ?? '0').toString();
                  final suffix = (metric['suffix'] ?? '').toString();
                  return Container(
                    width: 220,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 32),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: primaryColor.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$value$suffix',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontFamily: headingFont,
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          label,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontFamily: bodyFont,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
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

  static Widget _buildContact({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    String? headingFont,
    String? bodyFont,
    bool previewMode = false,
    void Function(String route)? onNavigate,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? 'Contáctanos').toString().trim();
    final subtitle = (data['subtitle'] ?? '').toString().trim();
    final phone = (data['phone'] ?? '').toString().trim();
    final email = (data['email'] ?? '').toString().trim();
    final address = (data['address'] ?? '').toString().trim();
    final mapUrl = (data['mapUrl'] ?? '').toString().trim();
    final showForm = data['showForm'] != false;
    final showMap = data['showMap'] == true;

    final contactItems = <Widget>[];
    if (phone.isNotEmpty) {
      contactItems.add(
        _buildContactDetail(
          icon: Icons.phone,
          label: 'Teléfono',
          value: phone,
          theme: theme,
          bodyFont: bodyFont,
        ),
      );
    }
    if (email.isNotEmpty) {
      contactItems.add(
        _buildContactDetail(
          icon: Icons.email_outlined,
          label: 'Correo',
          value: email,
          theme: theme,
          bodyFont: bodyFont,
        ),
      );
    }
    if (address.isNotEmpty) {
      contactItems.add(
        _buildContactDetail(
          icon: Icons.location_on_outlined,
          label: 'Dirección',
          value: address,
          theme: theme,
          bodyFont: bodyFont,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title.isEmpty ? 'Contáctanos' : title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: headingFont,
                ),
                textAlign: TextAlign.center,
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: bodyFont,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 36),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Información de contacto',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontFamily: headingFont,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (contactItems.isEmpty)
                              Text(
                                'Completa tus datos de contacto desde el editor.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            else
                              ...contactItems,
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (showForm)
                    SizedBox(
                      width: 360,
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Envíanos un mensaje',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontFamily: headingFont,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildDisabledTextField(theme, 'Nombre'),
                              const SizedBox(height: 12),
                              _buildDisabledTextField(
                                  theme, 'Correo electrónico'),
                              const SizedBox(height: 12),
                              _buildDisabledTextField(theme, 'Mensaje',
                                  maxLines: 4),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: previewMode ? () {} : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Enviar consulta'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (showMap)
                    SizedBox(
                      width: 360,
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Cómo llegar',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontFamily: headingFont,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                height: 200,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: theme.colorScheme.surfaceVariant,
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.map_outlined,
                                    size: 64,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (mapUrl.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                TextButton.icon(
                                  onPressed: previewMode
                                      ? () {}
                                      : (mapUrl.startsWith('/')
                                          ? () => onNavigate?.call(mapUrl)
                                          : null),
                                  icon: const Icon(Icons.arrow_outward),
                                  label: const Text('Abrir mapa'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: accentColor,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildContactDetail({
    required IconData icon,
    required String label,
    required String value,
    required ThemeData theme,
    String? bodyFont,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFamily: bodyFont,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: bodyFont,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildDisabledTextField(ThemeData theme, String label,
      {int maxLines = 1}) {
    return TextField(
      enabled: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      maxLines: maxLines,
    );
  }

  static Widget _buildTeam({
    required BuildContext context,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    String? headingFont,
    String? bodyFont,
    bool previewMode = false,
  }) {
    final theme = Theme.of(context);
    final title = (data['title'] ?? 'Nuestro equipo').toString().trim();
    final description = (data['description'] ?? '').toString().trim();
    final rawMembers = data['members'];

    var members = <Map<String, dynamic>>[];
    if (rawMembers is List) {
      members = rawMembers
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (members.isEmpty) {
      members = [
        {
          'name': 'Nombre del integrante',
          'role': 'Cargo',
          'bio': 'Usa el editor para agregar información de tu equipo.',
          'avatarUrl': '',
        },
        {
          'name': 'Integrante 2',
          'role': 'Cargo',
          'bio':
              'Cada integrante puede incluir redes sociales y una breve bio.',
          'avatarUrl': '',
        },
      ];
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title.isEmpty ? 'Nuestro equipo' : title,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontFamily: headingFont,
                ),
                textAlign: TextAlign.center,
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  description,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontFamily: bodyFont,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 40),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: members.map((member) {
                  final name = (member['name'] ?? 'Integrante').toString();
                  final role = (member['role'] ?? '').toString();
                  final bio = (member['bio'] ?? '').toString();
                  final avatarUrl =
                      (member['avatarUrl'] ?? '').toString().trim();
                  final instagram =
                      (member['instagram'] ?? '').toString().trim();
                  final linkedin = (member['linkedin'] ?? '').toString().trim();

                  return SizedBox(
                    width: 300,
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: accentColor.withOpacity(0.12),
                              backgroundImage: avatarUrl.isNotEmpty
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: avatarUrl.isEmpty
                                  ? Icon(
                                      Icons.person,
                                      size: 48,
                                      color: accentColor,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontFamily: headingFont,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (role.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                role,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: bodyFont,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            if (bio.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                bio,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFamily: bodyFont,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            if (instagram.isNotEmpty || linkedin.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (instagram.isNotEmpty)
                                      IconButton(
                                        tooltip: 'Instagram',
                                        onPressed: () {},
                                        icon: const Icon(
                                            Icons.camera_alt_outlined),
                                        color: accentColor,
                                      ),
                                    if (linkedin.isNotEmpty)
                                      IconButton(
                                        tooltip: 'LinkedIn',
                                        onPressed: () {},
                                        icon: const Icon(Icons.work_outline),
                                        color: accentColor,
                                      ),
                                  ],
                                ),
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
        ),
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
    String? headingFont,
    String? bodyFont,
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
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: headingFont,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: bodyFont,
                    ),
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
      case 'verified':
        return Icons.verified;
      case 'pedal_bike':
        return Icons.pedal_bike;
      case 'support_agent':
        return Icons.support_agent;
      case 'favorite':
        return Icons.favorite;
      case 'star':
        return Icons.star;
      case 'links':
        return Icons.link;
      case 'instagram':
        return Icons.camera_alt_outlined;
      case 'strava':
        return Icons.timeline;
      case 'facebook':
        return Icons.thumb_up_alt_outlined;
      case 'phone':
        return Icons.phone;
      case 'mail':
        return Icons.mail_outline;
      case 'location':
        return Icons.location_on_outlined;
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
    _interval =
        Duration(seconds: _parseInterval(widget.data['intervalSeconds']));
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

    final headingStyle =
        (theme.textTheme.displayLarge ?? const TextStyle()).copyWith(
      fontFamily:
          widget.headingFont?.isNotEmpty == true ? widget.headingFont : null,
      fontSize: widget.headingSize,
      color: Colors.white,
    );

    final subtitleStyle =
        (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
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
                              final route = ctaLink.isNotEmpty
                                  ? ctaLink
                                  : '/tienda/productos';
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
        final scaleAnimation =
            Tween<double>(begin: 0.95, end: 1).animate(animation);
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

  Widget _buildArrowButton(
      {required IconData icon, required VoidCallback onTap}) {
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
