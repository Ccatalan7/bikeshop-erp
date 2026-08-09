import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../block_marketplace/block_marketplace_loader.dart';
import 'website_block_capabilities.dart';
import 'website_block_definition.dart';
import 'website_block_type.dart';
import 'website_responsive_authoring.dart';

/// Canonical data contract for the Website Builder Products block.
///
/// Historical documents used `selectedProducts`, while the registry-created
/// document used `productIds`. Reading only either key made a manual collection
/// disappear depending on how the block had been created. The resolver keeps
/// both generations readable without dropping IDs; explicit selection writes
/// publish one normalized ordered list to the canonical key and its legacy
/// compatibility mirror atomically.
@immutable
class WebsiteProductsBlockContract {
  const WebsiteProductsBlockContract({
    required this.title,
    required this.subtitle,
    required this.productSource,
    required this.categoryId,
    required this.productIds,
    required this.layout,
    required this.itemsPerRow,
    required this.maxProducts,
    required this.showPrice,
    required this.showSku,
    required this.showBrand,
    required this.showViewAll,
  });

  static const String productIdsKey = 'productIds';
  static const String legacySelectedProductsKey = 'selectedProducts';

  final String title;
  final String subtitle;
  final String productSource;
  final String? categoryId;
  final List<String> productIds;
  final String layout;
  final int itemsPerRow;
  final int maxProducts;
  final bool showPrice;
  final bool showSku;
  final bool showBrand;
  final bool showViewAll;

  factory WebsiteProductsBlockContract.fromData(Map<String, dynamic> data) {
    final rawSource = data['productSource']?.toString().trim();
    final productSource = const <String>{
      'featured',
      'category',
      'manual',
      'newest',
    }.contains(rawSource)
        ? rawSource!
        : 'featured';
    final rawLayout = data['layout']?.toString().trim();
    final layout = rawLayout == 'carousel' ? 'carousel' : 'grid';
    final rawCategoryId = data['categoryId']?.toString().trim();

    return WebsiteProductsBlockContract(
      title: data['title']?.toString() ?? 'Productos Destacados',
      subtitle: data['subtitle']?.toString() ?? '',
      productSource: productSource,
      categoryId:
          rawCategoryId == null || rawCategoryId.isEmpty ? null : rawCategoryId,
      productIds: resolveProductIds(data),
      layout: layout,
      itemsPerRow:
          _boundedInt(data['itemsPerRow'], fallback: 3, min: 2, max: 4),
      maxProducts:
          _boundedInt(data['maxProducts'], fallback: 8, min: 4, max: 16),
      showPrice: data['showPrice'] is bool ? data['showPrice'] as bool : true,
      showSku: data['showSku'] is bool ? data['showSku'] as bool : false,
      showBrand: data['showBrand'] is bool ? data['showBrand'] as bool : false,
      showViewAll:
          data['showViewAll'] is bool ? data['showViewAll'] as bool : true,
    );
  }

  /// Resolves both persisted generations in stable order and without loss.
  ///
  /// Canonical IDs lead; legacy-only IDs are appended. Blank, null and
  /// duplicate representations are discarded, and numeric UUID-era payloads
  /// remain readable through their string representation.
  static List<String> resolveProductIds(Map<String, dynamic> data) {
    final result = <String>[];
    final seen = <String>{};

    void append(dynamic raw) {
      if (raw is! List) return;
      for (final value in raw) {
        if (value == null) continue;
        final id = value.toString().trim();
        if (id.isEmpty || !seen.add(id)) continue;
        result.add(id);
      }
    }

    append(data[productIdsKey]);
    append(data[legacySelectedProductsKey]);
    return List<String>.unmodifiable(result);
  }

  /// Atomic persisted representation used by the inspector selection command.
  static Map<String, dynamic> selectionWrite(Iterable<Object?> ids) {
    final normalized = resolveProductIds(<String, dynamic>{
      productIdsKey: ids.toList(growable: false),
    });
    return <String, dynamic>{
      productIdsKey: normalized,
      // Compatibility mirror for documents and clients created before the
      // registry key became canonical. It is never read as a second owner.
      legacySelectedProductsKey: normalized,
    };
  }

  String get selectionFingerprint => productIds.join('\u001f');

  static int _boundedInt(
    dynamic raw, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final value =
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    return (value ?? fallback).clamp(min, max);
  }
}

/// Central catalogue of website block definitions used across the editor and
/// the public storefront. This enables declarative registration of block
/// metadata, default payloads, and generic field schemas for quick wins while
/// still allowing bespoke editors for complex layouts.
class WebsiteBlockRegistry {
  WebsiteBlockRegistry._();

  static final Map<WebsiteBlockType, WebsiteBlockDefinition> _definitions = {};

  static final Map<WebsiteBlockType, WebsiteBlockDefinition>
      _fallbackDefinitions = {
    WebsiteBlockType.hero: const WebsiteBlockDefinition(
      type: WebsiteBlockType.hero,
      title: 'Hero / Banner',
      description:
          'Encabezado destacado con imagen de fondo, título, subtítulo y botón.',
      defaultData: {
        'title': 'Tu tienda de bicicletas favorita',
        'subtitle': 'Reparamos, equipamos y acompañamos tu próxima aventura',
        // Prefer the newer keys used by the public renderer, while keeping
        // legacy keys compatible via normalization.
        'ctaText': 'Ver Catálogo',
        'ctaLink': '/productos',
        'imageUrl': null,
        'showOverlay': true,
        'overlayOpacity': 0.5,
        'isFullScreen': false,
        'alignment': 'center',
        // New blocks start on the canonical shared authority. Legacy mobile
        // aliases remain read-only compatibility inputs for existing pages.
        'focalPointX': 0.5,
        'focalPointY': 0.5,
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título',
          type: WebsiteBlockFieldType.text,
          textRole: WebsiteTextRole.heading,
          supportsFormatting: true,
        ),
        WebsiteBlockFieldSchema(
          key: 'subtitle',
          label: 'Subtítulo',
          type: WebsiteBlockFieldType.textarea,
          textRole: WebsiteTextRole.paragraph,
          supportsFormatting: true,
        ),
        WebsiteBlockFieldSchema(
          key: 'ctaText',
          label: 'Texto del botón',
          type: WebsiteBlockFieldType.text,
          textRole: WebsiteTextRole.buttonLabel,
          migrationAliases: ['buttonText'],
        ),
        WebsiteBlockFieldSchema(
          key: 'ctaLink',
          label: 'Enlace del botón',
          type: WebsiteBlockFieldType.link,
          defaultValue: '/productos',
          actionRole: WebsiteActionRole.primary,
          actionLabelKey: 'ctaText',
          actionVariantKey: 'actionVariant',
          migrationAliases: ['buttonLink'],
        ),
        WebsiteBlockFieldSchema(
          key: 'isFullScreen',
          label: 'Pantalla completa',
          type: WebsiteBlockFieldType.toggle,
          defaultValue: false,
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.geometry,
        ),
        WebsiteBlockFieldSchema(
          key: 'alignment',
          label: 'Alineación',
          type: WebsiteBlockFieldType.select,
          defaultValue: 'center',
          options: [
            WebsiteBlockFieldOption(value: 'left', label: 'Izquierda'),
            WebsiteBlockFieldOption(value: 'center', label: 'Centro'),
            WebsiteBlockFieldOption(value: 'right', label: 'Derecha'),
          ],
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.geometry,
        ),
        WebsiteBlockFieldSchema(
          key: 'imageUrl',
          label: 'Imagen de fondo',
          type: WebsiteBlockFieldType.image,
          mediaRole: WebsiteMediaRole.cover,
          supportsFocalPoint: true,
          supportsAltText: true,
          altTextKey: 'imageAltText',
          migrationAliases: ['backgroundImage'],
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.media,
          authoringSurfaces: {
            WebsiteAuthoringSurface.inline,
            WebsiteAuthoringSurface.contextSheet,
            WebsiteAuthoringSurface.inspector,
          },
          legacyResponsiveAliases: ['mobileImageUrl'],
        ),
        WebsiteBlockFieldSchema(
          key: 'showOverlay',
          label: 'Mostrar overlay',
          type: WebsiteBlockFieldType.toggle,
          defaultValue: true,
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.color,
        ),
        WebsiteBlockFieldSchema(
          key: 'overlayOpacity',
          label: 'Opacidad overlay',
          type: WebsiteBlockFieldType.number,
          min: 0,
          max: 1,
          step: 0.1,
          defaultValue: 0.5,
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.color,
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'subtitle'],
        ),
        WebsiteBlockControlSection(
          id: 'cta',
          label: 'Botón',
          fieldKeys: ['ctaText', 'ctaLink'],
        ),
        WebsiteBlockControlSection(
          id: 'layout',
          label: 'Layout',
          fieldKeys: ['isFullScreen', 'alignment', 'imageUrl'],
        ),
        WebsiteBlockControlSection(
          id: 'style',
          label: 'Estilo',
          fieldKeys: ['showOverlay', 'overlayOpacity'],
        ),
      ],
    ),
    WebsiteBlockType.carousel: const WebsiteBlockDefinition(
      type: WebsiteBlockType.carousel,
      title: 'Carrusel Hero',
      description:
          'Presenta varias diapositivas con título, subtítulo y botón.',
      defaultData: {
        'slides': [
          {
            'title': 'Servicio técnico certificado',
            'subtitle': 'Agendamos y ejecutamos mantenciones completas',
            'buttonText': 'Agendar ahora',
            'imageUrl': null,
          },
          {
            'title': 'Bicicletas urbanas',
            'subtitle': 'Modelos livianos para moverte por la ciudad',
            'buttonText': 'Ver bicicletas',
            'imageUrl': null,
          },
        ],
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'slides',
          label: 'Slides',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Slide',
          minItems: 1,
          propertyFamily: WebsiteResponsivePropertyFamily.collection,
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'title',
              label: 'Título',
              type: WebsiteBlockFieldType.text,
              textRole: WebsiteTextRole.heading,
              supportsFormatting: true,
              formattingKey: 'titleFormatting',
            ),
            WebsiteBlockFieldSchema(
              key: 'subtitle',
              label: 'Subtítulo',
              type: WebsiteBlockFieldType.textarea,
              textRole: WebsiteTextRole.paragraph,
              supportsFormatting: true,
              formattingKey: 'subtitleFormatting',
            ),
            WebsiteBlockFieldSchema(
              key: 'ctaText',
              label: 'Texto del botón',
              type: WebsiteBlockFieldType.text,
              textRole: WebsiteTextRole.buttonLabel,
              migrationAliases: ['buttonText'],
            ),
            WebsiteBlockFieldSchema(
              key: 'ctaLink',
              label: 'Enlace del botón',
              type: WebsiteBlockFieldType.link,
              actionRole: WebsiteActionRole.primary,
              actionLabelKey: 'ctaText',
              actionVariantKey: 'actionVariant',
              migrationAliases: ['buttonLink'],
            ),
            WebsiteBlockFieldSchema(
              key: 'imageUrl',
              label: 'Imagen de fondo',
              type: WebsiteBlockFieldType.image,
              mediaRole: WebsiteMediaRole.cover,
              supportsFocalPoint: true,
              supportsAltText: true,
              altTextKey: 'altText',
              responsivePolicy:
                  WebsiteResponsivePropertyPolicy.responsiveOptional,
              propertyFamily: WebsiteResponsivePropertyFamily.media,
              authoringSurfaces: {
                WebsiteAuthoringSurface.inline,
                WebsiteAuthoringSurface.contextSheet,
                WebsiteAuthoringSurface.inspector,
              },
              legacyResponsiveAliases: ['mobileImageUrl'],
            ),
            WebsiteBlockFieldSchema(
              key: 'showOverlay',
              label: 'Mostrar overlay',
              type: WebsiteBlockFieldType.toggle,
              defaultValue: true,
              responsivePolicy:
                  WebsiteResponsivePropertyPolicy.responsiveOptional,
              propertyFamily: WebsiteResponsivePropertyFamily.color,
            ),
            WebsiteBlockFieldSchema(
              key: 'overlayOpacity',
              label: 'Opacidad overlay',
              type: WebsiteBlockFieldType.number,
              min: 0,
              max: 1,
              step: 0.05,
              defaultValue: 0.55,
              responsivePolicy:
                  WebsiteResponsivePropertyPolicy.responsiveOptional,
              propertyFamily: WebsiteResponsivePropertyFamily.color,
            ),
          ],
        ),
      ],
      usesCustomEditor: true,
    ),

    // =====================================================================
    // SIMPLE STRUCTURE / ELEMENT BLOCKS
    // =====================================================================
    WebsiteBlockType.canvas: const WebsiteBlockDefinition(
      type: WebsiteBlockType.canvas,
      title: 'Canvas',
      description:
          'Sección de diseño libre con elementos arrastrables (tipo Wix).',
      defaultData: {
        'canvasResponsiveVersion': 2,
        'blockHeight': 420.0,
        'heightMode': 'fixed',
        'vhPct': 0.7,
        'fullBleed': false,
        'backgroundColor': '#FFFFFF',
        'backgroundImageUrl': '',
        'backgroundImageAltText': '',
        'backgroundVideoUrl': '',
        'backgroundYoutubeId': '',
        'backgroundFit': 'cover',
        'focalPointX': 0.5,
        'focalPointY': 0.5,
        'overlayEnabled': false,
        'overlayOpacity': 0.35,
        'overlayColor': '#000000',
        'showGrid': true,
        'gridSize': 8.0,
        'snap': true,
        'snapDistance': 6.0,
        'constrainElementsToSafeArea': true,
        'elements': <Map<String, dynamic>>[],
      },
      usesCustomEditor: true,
    ),
    WebsiteBlockType.text: const WebsiteBlockDefinition(
      type: WebsiteBlockType.text,
      title: 'Texto',
      description: 'Sección simple de texto con editor inline.',
      defaultData: {
        'text': 'Escribe tu texto aquí',
        'preset': 'paragraph',
        'maxWidth': 800,
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'text',
          label: 'Texto',
          type: WebsiteBlockFieldType.textarea,
          group: 'content',
          textRole: WebsiteTextRole.paragraph,
          supportsFormatting: true,
          migrationAliases: ['description'],
          formattingKey: 'formatting',
        ),
        WebsiteBlockFieldSchema(
          key: 'preset',
          label: 'Preset',
          type: WebsiteBlockFieldType.select,
          defaultValue: 'paragraph',
          options: [
            WebsiteBlockFieldOption(value: 'heading', label: 'Título'),
            WebsiteBlockFieldOption(value: 'subheading', label: 'Subtítulo'),
            WebsiteBlockFieldOption(value: 'paragraph', label: 'Párrafo'),
            WebsiteBlockFieldOption(value: 'caption', label: 'Texto pequeño'),
          ],
          group: 'layout',
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.typography,
        ),
        WebsiteBlockFieldSchema(
          key: 'maxWidth',
          label: 'Ancho máximo (px)',
          type: WebsiteBlockFieldType.number,
          min: 200,
          max: 1200,
          step: 10,
          defaultValue: 800,
          group: 'layout',
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.geometry,
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['text'],
        ),
        WebsiteBlockControlSection(
          id: 'layout',
          label: 'Diseño',
          fieldKeys: ['preset', 'maxWidth'],
        ),
      ],
    ),
    WebsiteBlockType.button: const WebsiteBlockDefinition(
      type: WebsiteBlockType.button,
      title: 'Botón',
      description: 'Botón con enlace (CTA).',
      defaultData: {
        'label': 'Haz clic aquí',
        'link': '/productos',
        'style': 'filled',
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'label',
          label: 'Texto',
          type: WebsiteBlockFieldType.text,
          defaultValue: 'Haz clic aquí',
          group: 'content',
          textRole: WebsiteTextRole.buttonLabel,
        ),
        WebsiteBlockFieldSchema(
          key: 'link',
          label: 'Enlace',
          type: WebsiteBlockFieldType.link,
          defaultValue: '/productos',
          group: 'content',
          actionRole: WebsiteActionRole.primary,
          actionLabelKey: 'label',
          actionVariantKey: 'style',
        ),
        WebsiteBlockFieldSchema(
          key: 'style',
          label: 'Estilo',
          type: WebsiteBlockFieldType.select,
          defaultValue: 'filled',
          options: [
            WebsiteBlockFieldOption(value: 'filled', label: 'Relleno'),
            WebsiteBlockFieldOption(value: 'outline', label: 'Borde'),
            WebsiteBlockFieldOption(value: 'text', label: 'Texto'),
          ],
          group: 'design',
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.action,
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['label', 'link'],
        ),
        WebsiteBlockControlSection(
          id: 'design',
          label: 'Diseño',
          fieldKeys: ['style'],
        ),
      ],
    ),
    WebsiteBlockType.divider: const WebsiteBlockDefinition(
      type: WebsiteBlockType.divider,
      title: 'Separador',
      description: 'Línea divisoria para separar secciones.',
      defaultData: {
        'widthPct': 1.0,
        'thickness': 1,
        'color': '#E5E7EB',
      },
      fields: [
        // A divider is pure presentation: it carries no copy, no destination
        // and no business data, so all three of its properties may differ per
        // viewport. A hairline that reads correctly on a 1440 canvas is often
        // too heavy at 390, and the width percentage is geometry by
        // definition.
        WebsiteBlockFieldSchema(
          key: 'thickness',
          label: 'Grosor',
          type: WebsiteBlockFieldType.number,
          min: 0,
          max: 12,
          step: 1,
          defaultValue: 1,
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.geometry,
        ),
        WebsiteBlockFieldSchema(
          key: 'widthPct',
          label: 'Ancho (%)',
          type: WebsiteBlockFieldType.number,
          min: 0.1,
          max: 1.0,
          step: 0.05,
          defaultValue: 1.0,
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.geometry,
        ),
        WebsiteBlockFieldSchema(
          key: 'color',
          label: 'Color',
          type: WebsiteBlockFieldType.color,
          defaultValue: '#E5E7EB',
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.color,
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'appearance',
          label: 'Apariencia',
          fieldKeys: ['thickness', 'widthPct', 'color'],
        ),
      ],
    ),
    WebsiteBlockType.products: const WebsiteBlockDefinition(
      type: WebsiteBlockType.products,
      title: 'Productos Destacados',
      description: 'Lista productos seleccionados desde tu inventario.',
      defaultData: {
        'title': 'Productos Destacados',
        'subtitle': '',
        'productSource': 'featured',
        'layout': 'grid',
        'itemsPerRow': 3,
        'maxProducts': 8,
        'showPrice': true,
        'showSku': false,
        'showBrand': false,
        'productIds': <String>[],
        'showViewAll': true,
        'viewAllText': 'Ver todos los productos',
        'viewAllLink': '/productos',
        'actions': [
          {
            'type': 'navigate',
            'label': 'Ver todos los productos',
            'to': '/productos',
            'variant': 'outline',
          }
        ],
      },
      // Only the presentation properties that a renderer actually consumes are
      // declared. Everything else this block owns — catalogue source, category,
      // selected ids, maxProducts, the "view all" copy and destination — is
      // business identity and stays shared, edited by the custom controls.
      fields: [
        WebsiteBlockFieldSchema(
          key: 'layout',
          label: 'Diseño',
          type: WebsiteBlockFieldType.select,
          defaultValue: 'grid',
          options: [
            WebsiteBlockFieldOption(value: 'grid', label: 'Cuadrícula'),
            WebsiteBlockFieldOption(value: 'carousel', label: 'Carrusel'),
          ],
          group: 'layout',
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.geometry,
        ),
        // SHARED on purpose. The storefront computes the column count itself:
        // phone/tablet grids use their safe automatic density while Desktop
        // honours this base. A per-viewport override would still be a control
        // the renderer cannot honour, so the inspector states that explicitly.
        WebsiteBlockFieldSchema(
          key: 'itemsPerRow',
          label: 'Productos por fila',
          type: WebsiteBlockFieldType.number,
          min: 2,
          max: 4,
          step: 1,
          defaultValue: 3,
          group: 'layout',
          propertyFamily: WebsiteResponsivePropertyFamily.geometry,
        ),
        WebsiteBlockFieldSchema(
          key: 'showPrice',
          label: 'Mostrar precios',
          type: WebsiteBlockFieldType.toggle,
          defaultValue: true,
          group: 'display',
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.visibility,
        ),
        WebsiteBlockFieldSchema(
          key: 'showSku',
          label: 'Mostrar SKU',
          type: WebsiteBlockFieldType.toggle,
          defaultValue: false,
          group: 'display',
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.visibility,
        ),
        WebsiteBlockFieldSchema(
          key: 'showBrand',
          label: 'Mostrar marca',
          type: WebsiteBlockFieldType.toggle,
          defaultValue: false,
          group: 'display',
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.visibility,
        ),
        WebsiteBlockFieldSchema(
          key: 'showViewAll',
          label: 'Mostrar botón "Ver todos"',
          type: WebsiteBlockFieldType.toggle,
          defaultValue: true,
          group: 'layout',
          // Presentation of the action; its label and destination stay shared.
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.action,
        ),
      ],
      usesCustomEditor: true,
    ),
    // Servicios es deliberadamente auto-layout: el renderer elige lista
    // compacta bajo 600 y filas de escritorio sobre ese ancho, sin leer
    // ninguna propiedad persistida para hacerlo. No hay nada que personalizar
    // por viewport, y no se inventa una propiedad para fingir que sí. Ícono,
    // título y descripción de cada servicio son contenido. Matriz:
    // `website_content_responsive_policies_test.dart`.
    WebsiteBlockType.services: const WebsiteBlockDefinition(
      type: WebsiteBlockType.services,
      title: 'Servicios',
      description: 'Describe servicios clave con iconos, títulos y detalle.',
      defaultData: {
        'title': 'Nuestros Servicios',
        'services': <Map<String, dynamic>>[],
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título de la sección',
          type: WebsiteBlockFieldType.text,
          group: 'content',
        ),
        WebsiteBlockFieldSchema(
          key: 'services',
          label: 'Servicios',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Servicio',
          migrationAliases: ['items'],
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'icon',
              label: 'Ícono',
              type: WebsiteBlockFieldType.select,
              defaultValue: 'build',
              options: [
                WebsiteBlockFieldOption(value: 'build', label: 'Herramientas'),
                WebsiteBlockFieldOption(
                    value: 'support_agent', label: 'Soporte'),
                WebsiteBlockFieldOption(value: 'shopping_bag', label: 'Tienda'),
                WebsiteBlockFieldOption(
                    value: 'directions_bike', label: 'Bicicleta'),
                WebsiteBlockFieldOption(value: 'favorite', label: 'Favorito'),
              ],
            ),
            WebsiteBlockFieldSchema(
              key: 'title',
              label: 'Título',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Servicio',
              textRole: WebsiteTextRole.heading,
              supportsFormatting: true,
            ),
            WebsiteBlockFieldSchema(
              key: 'description',
              label: 'Descripción',
              type: WebsiteBlockFieldType.textarea,
              defaultValue: 'Describe el servicio',
              textRole: WebsiteTextRole.paragraph,
              supportsFormatting: true,
            ),
          ],
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'services'],
        ),
      ],
    ),
    WebsiteBlockType.about: const WebsiteBlockDefinition(
      type: WebsiteBlockType.about,
      title: 'Sobre Nosotros',
      description:
          'Bloque de texto/imágenes orientado a presentar la historia del taller.',
      defaultData: {
        'title': 'Somos Vinabike',
        'content':
            'Llevamos más de 10 años reparando bicicletas y asesorando ciclistas en Chile.',
        'imagePosition': 'right',
        'imageUrl': null,
      },
      usesCustomEditor: false,
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título',
          type: WebsiteBlockFieldType.text,
          defaultValue: 'Somos Vinabike',
          group: 'content',
          textRole: WebsiteTextRole.heading,
          supportsFormatting: true,
        ),
        WebsiteBlockFieldSchema(
          key: 'content',
          label: 'Contenido',
          type: WebsiteBlockFieldType.textarea,
          defaultValue:
              'Llevamos más de 10 años reparando bicicletas y asesorando ciclistas en Chile.',
          group: 'content',
          textRole: WebsiteTextRole.paragraph,
          supportsFormatting: true,
        ),
        // Art direction real: el marco de esta imagen cambia de 4:3 en
        // escritorio a 16:9 en tablet y 3:2 en móvil, así que un recorte
        // centrado que funciona en uno corta mal en otro. Se permite otro
        // asset del MISMO sujeto y, sobre todo, su reencuadre por viewport,
        // que el renderer compartido resuelve en la alineación de la imagen.
        // El texto alternativo de abajo sigue compartido: un sujeto, una
        // descripción.
        WebsiteBlockFieldSchema(
          key: 'imageUrl',
          label: 'Imagen',
          type: WebsiteBlockFieldType.image,
          group: 'media',
          mediaRole: WebsiteMediaRole.inline,
          supportsFocalPoint: true,
          supportsAltText: true,
          altTextKey: 'imageAltText',
          migrationAliases: ['image'],
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.media,
          authoringSurfaces: {
            WebsiteAuthoringSurface.inline,
            WebsiteAuthoringSurface.contextSheet,
            WebsiteAuthoringSurface.inspector,
          },
        ),
        // COMPARTIDA a propósito. Sólo la composición horizontal la honra, y
        // esa composición existe únicamente desde 900 px, donde Escritorio ES
        // la base: bajo ese ancho el bloque apila y la imagen va siempre
        // primero. Un override de tablet o móvil no podría cambiar nada, así
        // que el inspector dice «siempre común» en vez de ofrecerlo.
        WebsiteBlockFieldSchema(
          key: 'imagePosition',
          label: 'Posición de la imagen',
          type: WebsiteBlockFieldType.select,
          defaultValue: 'right',
          options: [
            WebsiteBlockFieldOption(value: 'left', label: 'Izquierda'),
            WebsiteBlockFieldOption(value: 'right', label: 'Derecha'),
          ],
          group: 'layout',
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'content'],
        ),
        WebsiteBlockControlSection(
          id: 'media',
          label: 'Medios',
          fieldKeys: ['imageUrl'],
        ),
        WebsiteBlockControlSection(
          id: 'layout',
          label: 'Diseño',
          fieldKeys: ['imagePosition'],
        ),
      ],
    ),
    // Testimonios no declara ninguna propiedad responsive, y no es un olvido:
    // su renderer calcula el ancho de tarjeta desde el ancho disponible y no
    // lee ninguna otra propiedad de presentación. Nombre, rol, comentario y
    // valoración son contenido del cliente. Un override aquí sería un control
    // que no cambia nada en la tienda. Matriz: `website_collections_
    // responsive_policies_test.dart`.
    WebsiteBlockType.testimonials: const WebsiteBlockDefinition(
      type: WebsiteBlockType.testimonials,
      title: 'Testimonios',
      description: 'Destaca comentarios de clientes para generar confianza.',
      defaultData: {
        'title': 'Lo que dicen nuestros clientes',
        'testimonials': <Map<String, dynamic>>[],
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título',
          type: WebsiteBlockFieldType.text,
          group: 'content',
        ),
        WebsiteBlockFieldSchema(
          key: 'testimonials',
          label: 'Testimonios',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Testimonio',
          migrationAliases: ['items'],
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'name',
              label: 'Nombre',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Nombre',
              textRole: WebsiteTextRole.heading,
              supportsFormatting: true,
            ),
            WebsiteBlockFieldSchema(
              key: 'role',
              label: 'Rol',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Cliente',
              textRole: WebsiteTextRole.caption,
              supportsFormatting: true,
            ),
            WebsiteBlockFieldSchema(
              key: 'comment',
              label: 'Comentario',
              type: WebsiteBlockFieldType.textarea,
              defaultValue: 'Escribe el testimonio',
              textRole: WebsiteTextRole.paragraph,
              supportsFormatting: true,
              migrationAliases: ['quote', 'text'],
            ),
            WebsiteBlockFieldSchema(
              key: 'rating',
              label: 'Valoración',
              type: WebsiteBlockFieldType.number,
              min: 1,
              max: 5,
              step: 1,
              defaultValue: 5,
            ),
          ],
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'testimonials'],
        ),
      ],
    ),
    WebsiteBlockType.features: const WebsiteBlockDefinition(
      type: WebsiteBlockType.features,
      title: 'Características',
      description:
          'Lista atributos destacados, diferenciales o garantías del negocio.',
      defaultData: {
        'title': 'Por qué elegirnos',
        'layout': 'grid',
        'features': <Map<String, dynamic>>[],
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título principal',
          type: WebsiteBlockFieldType.text,
          defaultValue: 'Por qué elegirnos',
          group: 'content',
        ),
        // El renderer monta dos árboles distintos con este valor —cuadrícula
        // o lista— y lo lee igual en los tres anchos, así que un override es
        // una composición realmente distinta y no un control decorativo. Las
        // columnas de la cuadrícula las sigue calculando el propio renderer
        // por ancho: eso no se declara.
        WebsiteBlockFieldSchema(
          key: 'layout',
          label: 'Diseño',
          type: WebsiteBlockFieldType.select,
          defaultValue: 'grid',
          options: [
            WebsiteBlockFieldOption(value: 'grid', label: 'Cuadrícula'),
            WebsiteBlockFieldOption(value: 'list', label: 'Lista'),
          ],
          group: 'layout',
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.geometry,
        ),
        WebsiteBlockFieldSchema(
          key: 'features',
          label: 'Características',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Característica',
          migrationAliases: ['items'],
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'icon',
              label: 'Ícono',
              type: WebsiteBlockFieldType.select,
              defaultValue: 'verified',
              options: [
                WebsiteBlockFieldOption(
                    value: 'verified', label: 'Certificado'),
                WebsiteBlockFieldOption(
                    value: 'pedal_bike', label: 'Bicicleta'),
                WebsiteBlockFieldOption(
                    value: 'support_agent', label: 'Soporte'),
                WebsiteBlockFieldOption(value: 'build', label: 'Taller'),
                WebsiteBlockFieldOption(
                    value: 'shopping_bag', label: 'Compras'),
                WebsiteBlockFieldOption(value: 'favorite', label: 'Favorito'),
                WebsiteBlockFieldOption(value: 'star', label: 'Estrella'),
              ],
            ),
            WebsiteBlockFieldSchema(
              key: 'title',
              label: 'Título',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Ventaja',
              textRole: WebsiteTextRole.heading,
              supportsFormatting: true,
            ),
            WebsiteBlockFieldSchema(
              key: 'description',
              label: 'Descripción',
              type: WebsiteBlockFieldType.textarea,
              defaultValue: 'Describe la característica',
              textRole: WebsiteTextRole.paragraph,
              supportsFormatting: true,
            ),
          ],
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'features'],
        ),
        WebsiteBlockControlSection(
          id: 'layout',
          label: 'Diseño',
          fieldKeys: ['layout'],
        ),
      ],
    ),
    WebsiteBlockType.cta: const WebsiteBlockDefinition(
      type: WebsiteBlockType.cta,
      title: 'Llamado a la Acción',
      description: 'Invita a tus visitantes a realizar la siguiente acción.',
      defaultData: {
        'title': 'Agenda tu mantención hoy',
        'subtitle': 'Estamos listos para ayudarte con tu bicicleta',
        'buttonText': 'Agendar',
        'buttonLink': '/contacto',
        'actions': [
          {
            'type': 'navigate',
            'label': 'Agendar',
            'to': '/contacto',
          }
        ],
        'backgroundImage': null,
        'overlayColor': '#000000',
        'overlayOpacity': 0.5,
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título',
          type: WebsiteBlockFieldType.text,
          defaultValue: 'Agenda tu mantención hoy',
          textRole: WebsiteTextRole.heading,
          supportsFormatting: true,
        ),
        WebsiteBlockFieldSchema(
          key: 'subtitle',
          label: 'Subtítulo',
          type: WebsiteBlockFieldType.textarea,
          defaultValue: 'Estamos listos para ayudarte',
          textRole: WebsiteTextRole.paragraph,
          supportsFormatting: true,
        ),
        WebsiteBlockFieldSchema(
          key: 'buttonText',
          label: 'Texto del botón',
          type: WebsiteBlockFieldType.text,
          defaultValue: 'Agendar',
          textRole: WebsiteTextRole.buttonLabel,
          migrationAliases: ['ctaText'],
        ),
        WebsiteBlockFieldSchema(
          key: 'buttonLink',
          label: 'Enlace del botón',
          type: WebsiteBlockFieldType.link,
          defaultValue: '/contacto',
          actionRole: WebsiteActionRole.primary,
          actionLabelKey: 'buttonText',
          actionVariantKey: 'actionVariant',
          migrationAliases: ['ctaLink'],
        ),
        WebsiteBlockFieldSchema(
          key: 'backgroundImage',
          label: 'Imagen de fondo',
          type: WebsiteBlockFieldType.image,
          mediaRole: WebsiteMediaRole.cover,
          supportsFocalPoint: true,
          supportsAltText: true,
          altTextKey: 'backgroundImageAltText',
          migrationAliases: ['imageUrl'],
          // Art direction of the SAME subject; the alt text below stays
          // shared because one subject has one description.
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.media,
          authoringSurfaces: {
            WebsiteAuthoringSurface.inline,
            WebsiteAuthoringSurface.contextSheet,
            WebsiteAuthoringSurface.inspector,
          },
        ),
        WebsiteBlockFieldSchema(
          key: 'overlayColor',
          label: 'Color de superposición',
          type: WebsiteBlockFieldType.color,
          defaultValue: '#000000',
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.color,
        ),
        WebsiteBlockFieldSchema(
          key: 'overlayOpacity',
          label: 'Opacidad de superposición',
          type: WebsiteBlockFieldType.number,
          min: 0,
          max: 1,
          step: 0.05,
          defaultValue: 0.5,
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.color,
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'subtitle', 'buttonText', 'buttonLink'],
        ),
        WebsiteBlockControlSection(
          id: 'design',
          label: 'Diseño',
          fieldKeys: ['backgroundImage', 'overlayColor', 'overlayOpacity'],
        ),
      ],
    ),
    WebsiteBlockType.gallery: const WebsiteBlockDefinition(
      type: WebsiteBlockType.gallery,
      title: 'Galería',
      description:
          'Muestra fotografías del taller, eventos o productos destacados.',
      defaultData: {
        'title': 'Galería',
        'layout': 'grid',
        'images': <Map<String, dynamic>>[],
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título',
          type: WebsiteBlockFieldType.text,
        ),
        // El renderer decide la proporción de cada tile con este valor —
        // mosaico alterna 1.2 / 0.8 / 1.0 y cuadrícula es 1.0— en los tres
        // viewports, así que un override cambia la composición visible. Las
        // columnas las calcula el propio renderer por ancho y no se declaran.
        WebsiteBlockFieldSchema(
          key: 'layout',
          label: 'Diseño',
          type: WebsiteBlockFieldType.select,
          defaultValue: 'grid',
          options: [
            WebsiteBlockFieldOption(value: 'grid', label: 'Cuadrícula'),
            WebsiteBlockFieldOption(value: 'masonry', label: 'Mosaico'),
          ],
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.geometry,
        ),
        WebsiteBlockFieldSchema(
          key: 'images',
          label: 'Imágenes',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Imagen',
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'imageUrl',
              label: 'Imagen',
              type: WebsiteBlockFieldType.image,
              mediaRole: WebsiteMediaRole.galleryItem,
              supportsFocalPoint: true,
              supportsAltText: true,
              altTextKey: 'altText',
              // Art direction de la MISMA foto, por item: el tile pasa de un
              // tercio del ancho en escritorio a la pantalla completa en
              // móvil, y con `layout` personalizado también cambia su
              // proporción. El alt de abajo sigue compartido: un sujeto, una
              // descripción.
              responsivePolicy:
                  WebsiteResponsivePropertyPolicy.responsiveOptional,
              propertyFamily: WebsiteResponsivePropertyFamily.media,
              authoringSurfaces: {
                WebsiteAuthoringSurface.inline,
                WebsiteAuthoringSurface.contextSheet,
                WebsiteAuthoringSurface.inspector,
              },
            ),
            WebsiteBlockFieldSchema(
              key: 'caption',
              label: 'Leyenda',
              type: WebsiteBlockFieldType.text,
              textRole: WebsiteTextRole.caption,
              supportsFormatting: true,
            ),
          ],
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'images'],
        ),
        WebsiteBlockControlSection(
          id: 'layout',
          label: 'Diseño',
          fieldKeys: ['layout'],
        ),
      ],
    ),
    // Contacto cierra compartido. La composición ya es automática —el propio
    // renderer elige escritorio, media o compacta desde el ancho disponible— y
    // los dos interruptores que quedan no son presentación: `showForm` y
    // `showMap` deciden si existe una vía de contacto, y el renderer los honra
    // igual en los tres anchos. Ocultar el formulario sólo en el teléfono es
    // una decisión de negocio del dueño, no un ajuste de composición; si algún
    // día se quiere, entra como `responsiveVisibility` con esa decisión
    // tomada, no por conveniencia técnica.
    WebsiteBlockType.contact: const WebsiteBlockDefinition(
      type: WebsiteBlockType.contact,
      title: 'Contacto',
      description: 'Entrega información de contacto y formulario de consulta.',
      defaultData: {
        'title': 'Contáctanos',
        'subtitle': 'Resolvemos dudas y agendamos servicios en menos de 24h.',
        'showForm': true,
        'showMap': false,
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título',
          type: WebsiteBlockFieldType.text,
        ),
        WebsiteBlockFieldSchema(
          key: 'subtitle',
          label: 'Subtítulo',
          type: WebsiteBlockFieldType.text,
        ),
        WebsiteBlockFieldSchema(
          key: 'showForm',
          label: 'Mostrar formulario',
          type: WebsiteBlockFieldType.toggle,
          defaultValue: true,
        ),
        WebsiteBlockFieldSchema(
          key: 'showMap',
          label: 'Mostrar mapa',
          type: WebsiteBlockFieldType.toggle,
          defaultValue: false,
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'subtitle'],
        ),
        WebsiteBlockControlSection(
          id: 'opciones',
          label: 'Opciones',
          fieldKeys: ['showForm', 'showMap'],
        ),
      ],
    ),
    // FAQ tampoco declara propiedades responsive: el tamaño del título ya lo
    // deriva el renderer del ancho útil, y pregunta y respuesta son contenido
    // indexable que debe ser el mismo en los tres dispositivos.
    WebsiteBlockType.faq: const WebsiteBlockDefinition(
      type: WebsiteBlockType.faq,
      title: 'Preguntas Frecuentes',
      description:
          'Listado de dudas habituales con respuestas claras y editables.',
      defaultData: {
        'title': 'Preguntas Frecuentes',
        'subtitle': 'Respondemos lo que más nos consultan',
        'items': [
          {
            'question': '¿Cuánto se demora una mantención?',
            'answer':
                'Depende del nivel de servicio, pero normalmente entre 24 y 48 horas.',
          },
          {
            'question': '¿Trabajan con bicicletas eléctricas?',
            'answer': 'Sí, contamos con técnicos certificados en e-bikes.',
          },
        ],
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título principal',
          type: WebsiteBlockFieldType.text,
        ),
        WebsiteBlockFieldSchema(
          key: 'subtitle',
          label: 'Subtítulo',
          type: WebsiteBlockFieldType.text,
        ),
        WebsiteBlockFieldSchema(
          key: 'items',
          label: 'Preguntas frecuentes',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Pregunta',
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'question',
              label: 'Pregunta',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Nueva pregunta',
              textRole: WebsiteTextRole.heading,
              supportsFormatting: true,
            ),
            WebsiteBlockFieldSchema(
              key: 'answer',
              label: 'Respuesta',
              type: WebsiteBlockFieldType.textarea,
              defaultValue: 'Respuesta detallada',
              textRole: WebsiteTextRole.paragraph,
              supportsFormatting: true,
            ),
          ],
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'subtitle', 'items'],
        ),
      ],
    ),
    // Planes y Precios cierra compartido. La composición es automática —un
    // `Wrap` cuyo ancho de tarjeta sale del ancho disponible— y todo lo demás
    // es negocio: precio, beneficios, copy y destino del botón. `highlighted`
    // se evaluó como candidato y se descartó: el renderer lo honra idéntico en
    // los tres anchos, así que destacar un plan distinto según el dispositivo
    // sería una decisión comercial disfrazada de presentación. Matriz:
    // `website_conversion_responsive_policies_test.dart`.
    WebsiteBlockType.pricing: const WebsiteBlockDefinition(
      type: WebsiteBlockType.pricing,
      title: 'Planes y Precios',
      description:
          'Comparador de planes con precios, beneficios y llamado a la acción.',
      defaultData: {
        'title': 'Planes de Servicio',
        'subtitle':
            'Elige el plan que mejor se ajuste a tus necesidades y presupuesto.',
        'plans': [
          {
            'name': 'Mantención Básica',
            'price': '29.990',
            'features': [
              'Revisión de frenos',
              'Ajuste de cambios',
              'Limpieza básica',
            ],
            'ctaText': 'Reservar',
            'ctaLink': '/productos',
          },
          {
            'name': 'Full Service',
            'price': '59.990',
            'features': [
              'Incluye plan básico',
              'Lubricación completa',
              'Ajuste integral',
            ],
            'ctaText': 'Reservar',
            'ctaLink': '/productos',
          },
        ],
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título',
          type: WebsiteBlockFieldType.text,
        ),
        WebsiteBlockFieldSchema(
          key: 'subtitle',
          label: 'Subtítulo',
          type: WebsiteBlockFieldType.text,
        ),
        WebsiteBlockFieldSchema(
          key: 'plans',
          label: 'Planes',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Plan',
          migrationAliases: ['items'],
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'name',
              label: 'Nombre',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Nuevo plan',
              textRole: WebsiteTextRole.heading,
              supportsFormatting: true,
            ),
            WebsiteBlockFieldSchema(
              key: 'price',
              label: 'Precio',
              type: WebsiteBlockFieldType.text,
              defaultValue: '0',
              textRole: WebsiteTextRole.heading,
              supportsFormatting: true,
            ),
            WebsiteBlockFieldSchema(
              key: 'ctaText',
              label: 'Texto del botón',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Reservar',
              textRole: WebsiteTextRole.buttonLabel,
              migrationAliases: ['buttonText'],
            ),
            WebsiteBlockFieldSchema(
              key: 'ctaLink',
              label: 'Enlace del botón',
              type: WebsiteBlockFieldType.link,
              defaultValue: '/productos',
              actionRole: WebsiteActionRole.primary,
              actionLabelKey: 'ctaText',
              actionVariantKey: 'actionVariant',
              migrationAliases: ['buttonLink'],
            ),
            WebsiteBlockFieldSchema(
              key: 'features',
              label: 'Beneficios',
              type: WebsiteBlockFieldType.chips,
              defaultValue: <String>[],
            ),
            WebsiteBlockFieldSchema(
              key: 'highlighted',
              label: 'Destacar plan',
              type: WebsiteBlockFieldType.toggle,
              defaultValue: false,
              migrationAliases: ['isFeatured'],
            ),
          ],
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'subtitle', 'plans'],
        ),
      ],
    ),

    // =====================================================================
    // MODERN BLOCKS
    // =====================================================================
    WebsiteBlockType.categoryGrid: const WebsiteBlockDefinition(
      type: WebsiteBlockType.categoryGrid,
      title: 'Categorías',
      description:
          'Cuadrícula de categorías con imagen, título y enlace (ideal para destacar líneas).',
      defaultData: {
        'title': 'Explora por categoría',
        'categories': [
          {
            'title': 'MTB',
            'subtitle': 'Trail, Enduro, Downhill',
            'imageUrl': null,
            'link': '/productos',
          },
          {
            'title': 'Ruta',
            'subtitle': 'Carretera y endurance',
            'imageUrl': null,
            'link': '/productos',
          },
        ],
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título',
          type: WebsiteBlockFieldType.text,
          textRole: WebsiteTextRole.heading,
          supportsFormatting: true,
        ),
        // The renderer has always read a block-level subtitle; the schema
        // simply never exposed it, so the editor could not reach a value the
        // storefront was already printing. This declares the existing
        // contract — no renderer or business semantics change.
        WebsiteBlockFieldSchema(
          key: 'subtitle',
          label: 'Subtítulo',
          type: WebsiteBlockFieldType.textarea,
          textRole: WebsiteTextRole.paragraph,
        ),
        WebsiteBlockFieldSchema(
          key: 'categories',
          label: 'Categorías',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Categoría',
          minItems: 1,
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'title',
              label: 'Título',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Categoría',
              textRole: WebsiteTextRole.heading,
            ),
            WebsiteBlockFieldSchema(
              key: 'subtitle',
              label: 'Subtítulo',
              type: WebsiteBlockFieldType.text,
              defaultValue: '',
              textRole: WebsiteTextRole.paragraph,
            ),
            WebsiteBlockFieldSchema(
              key: 'imageUrl',
              label: 'Imagen',
              type: WebsiteBlockFieldType.image,
              mediaRole: WebsiteMediaRole.cover,
              supportsFocalPoint: true,
              supportsAltText: true,
              altTextKey: 'altText',
              // Art direction of the same category, per item. The alt text
              // below stays shared: one subject, one description.
              responsivePolicy:
                  WebsiteResponsivePropertyPolicy.responsiveOptional,
              propertyFamily: WebsiteResponsivePropertyFamily.media,
              authoringSurfaces: {
                WebsiteAuthoringSurface.inline,
                WebsiteAuthoringSurface.contextSheet,
                WebsiteAuthoringSurface.inspector,
              },
            ),
            WebsiteBlockFieldSchema(
              key: 'link',
              label: 'Enlace',
              type: WebsiteBlockFieldType.link,
              defaultValue: '/productos',
              actionRole: WebsiteActionRole.card,
              migrationAliases: ['ctaLink'],
            ),
          ],
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'subtitle', 'categories'],
        ),
      ],
    ),
    WebsiteBlockType.videoBanner: const WebsiteBlockDefinition(
      type: WebsiteBlockType.videoBanner,
      title: 'Video Banner',
      description: 'Banner con video (web) o imagen fallback.',
      defaultData: {
        'title': 'Vive la experiencia',
        'subtitle': 'Equipamiento, servicio y comunidad ciclista',
        'imageUrl': null,
        'videoUrl': '',
        'videoFileUrl': '',
        'showCta': true,
        'ctaText': 'Ver productos',
        'ctaLink': '/productos',
        'actions': [
          {
            'type': 'navigate',
            'label': 'Ver productos',
            'to': '/productos',
          }
        ],
        'overlayOpacity': 0.5,
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título',
          type: WebsiteBlockFieldType.text,
          textRole: WebsiteTextRole.heading,
          supportsFormatting: true,
        ),
        WebsiteBlockFieldSchema(
          key: 'subtitle',
          label: 'Subtítulo',
          type: WebsiteBlockFieldType.textarea,
          textRole: WebsiteTextRole.paragraph,
          supportsFormatting: true,
        ),
        WebsiteBlockFieldSchema(
          key: 'imageUrl',
          label: 'Imagen de fondo',
          type: WebsiteBlockFieldType.image,
          helpText: 'Se usa como fallback en móvil o si el video no carga.',
          mediaRole: WebsiteMediaRole.cover,
          supportsFocalPoint: true,
          supportsAltText: true,
          altTextKey: 'imageAltText',
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.media,
          authoringSurfaces: {
            WebsiteAuthoringSurface.inline,
            WebsiteAuthoringSurface.contextSheet,
            WebsiteAuthoringSurface.inspector,
          },
        ),
        // The two video sources stay SHARED. A video is the block's subject,
        // not its presentation: a per-viewport source would be a second piece
        // of content, and the fallback image above already covers the case the
        // help text describes.
        WebsiteBlockFieldSchema(
          key: 'videoUrl',
          label: 'URL de YouTube',
          type: WebsiteBlockFieldType.text,
          helpText:
              'Si ingresas un YouTube URL, se limpiará el archivo de video.',
        ),
        WebsiteBlockFieldSchema(
          key: 'videoFileUrl',
          label: 'Archivo de video',
          type: WebsiteBlockFieldType.video,
          helpText:
              'Sube un MP4/WebM. Al subir un archivo, se limpiará el YouTube URL.',
        ),
        WebsiteBlockFieldSchema(
          key: 'showCta',
          label: 'Mostrar botón',
          type: WebsiteBlockFieldType.toggle,
          defaultValue: true,
          // Presentation of the action, not the action: whether the button is
          // shown may differ per viewport, while its label and destination
          // below stay shared.
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.action,
        ),
        WebsiteBlockFieldSchema(
          key: 'ctaText',
          label: 'Texto del botón',
          type: WebsiteBlockFieldType.text,
          textRole: WebsiteTextRole.buttonLabel,
        ),
        WebsiteBlockFieldSchema(
          key: 'ctaLink',
          label: 'Enlace del botón',
          type: WebsiteBlockFieldType.link,
          defaultValue: '/productos',
          actionRole: WebsiteActionRole.primary,
          actionLabelKey: 'ctaText',
          actionVariantKey: 'actionVariant',
        ),
        WebsiteBlockFieldSchema(
          key: 'overlayOpacity',
          label: 'Opacidad overlay',
          type: WebsiteBlockFieldType.number,
          min: 0,
          max: 1,
          step: 0.1,
          defaultValue: 0.5,
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.color,
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'subtitle', 'imageUrl'],
        ),
        WebsiteBlockControlSection(
          id: 'video',
          label: 'Video',
          fieldKeys: ['videoUrl', 'videoFileUrl'],
        ),
        WebsiteBlockControlSection(
          id: 'cta',
          label: 'Botón',
          fieldKeys: ['showCta', 'ctaText', 'ctaLink'],
        ),
        WebsiteBlockControlSection(
          id: 'style',
          label: 'Estilo',
          fieldKeys: ['overlayOpacity'],
        ),
      ],
    ),
    WebsiteBlockType.partnersBanner: const WebsiteBlockDefinition(
      type: WebsiteBlockType.partnersBanner,
      title: 'Partners',
      description: 'Banner de partners/sucursales con texto simple.',
      defaultData: {
        'title': 'Partners',
        'imageUrl': null,
        'items': [
          {'label': 'Envíos a Chile continental'},
          {'label': 'Marcas líderes'},
          {'label': 'Servicio técnico certificado'},
        ],
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título',
          type: WebsiteBlockFieldType.text,
          textRole: WebsiteTextRole.heading,
          supportsFormatting: true,
        ),
        WebsiteBlockFieldSchema(
          key: 'items',
          label: 'Mensajes',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Mensaje',
          minItems: 1,
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'label',
              label: 'Texto',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Nuevo mensaje',
            ),
          ],
        ),
        WebsiteBlockFieldSchema(
          key: 'imageUrl',
          label: 'Imagen de fondo',
          type: WebsiteBlockFieldType.image,
          mediaRole: WebsiteMediaRole.cover,
          supportsFocalPoint: true,
          supportsAltText: true,
          altTextKey: 'imageAltText',
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.media,
          authoringSurfaces: {
            WebsiteAuthoringSurface.inline,
            WebsiteAuthoringSurface.contextSheet,
            WebsiteAuthoringSurface.inspector,
          },
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'items'],
        ),
        WebsiteBlockControlSection(
          id: 'media',
          label: 'Fondo',
          fieldKeys: ['imageUrl'],
        ),
      ],
    ),
    WebsiteBlockType.brandLogos: const WebsiteBlockDefinition(
      type: WebsiteBlockType.brandLogos,
      title: 'Logos de Marcas',
      description: 'Carrusel/cuadrícula de logos de marcas.',
      defaultData: {
        'title': 'Marcas',
        'logoSize': 'medium',
        'brands': <Map<String, dynamic>>[],
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título',
          type: WebsiteBlockFieldType.text,
          textRole: WebsiteTextRole.heading,
          supportsFormatting: true,
        ),
        WebsiteBlockFieldSchema(
          key: 'logoSize',
          label: 'Tamaño de logos',
          type: WebsiteBlockFieldType.select,
          defaultValue: 'medium',
          options: [
            WebsiteBlockFieldOption(value: 'small', label: 'Pequeño'),
            WebsiteBlockFieldOption(value: 'medium', label: 'Mediano'),
            WebsiteBlockFieldOption(value: 'large', label: 'Grande'),
            WebsiteBlockFieldOption(value: 'xlarge', label: 'Extra grande'),
          ],
          // How big the row of logos reads is geometry, and a size that works
          // on a wide canvas is often wrong at 390. The brands themselves —
          // name, logo, link — stay shared: a logo identifies the brand, it is
          // not art direction.
          responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          propertyFamily: WebsiteResponsivePropertyFamily.geometry,
        ),
        WebsiteBlockFieldSchema(
          key: 'brands',
          label: 'Marcas',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Marca',
          minItems: 1,
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'name',
              label: 'Nombre',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Marca',
            ),
            WebsiteBlockFieldSchema(
              key: 'imageUrl',
              label: 'Logo',
              type: WebsiteBlockFieldType.image,
              mediaRole: WebsiteMediaRole.logo,
              supportsAltText: true,
              altTextKey: 'altText',
            ),
            WebsiteBlockFieldSchema(
              key: 'link',
              label: 'Enlace',
              type: WebsiteBlockFieldType.link,
              actionRole: WebsiteActionRole.card,
            ),
          ],
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'brands'],
        ),
        WebsiteBlockControlSection(
          id: 'layout',
          label: 'Diseño',
          fieldKeys: ['logoSize'],
        ),
      ],
    ),
    // Google Reviews queda entero compartido. `minRating` y `maxItems` son
    // filtros del negocio sobre una fuente externa —no presentación—: el
    // carrusel los aplica a las reseñas reales, y el resultado tiene que ser
    // el mismo en los tres dispositivos. El bloque tampoco tiene propiedad de
    // composición por dispositivo: tarjeta de 320 y alto de 280 fijos.
    WebsiteBlockType.googleReviews: const WebsiteBlockDefinition(
      type: WebsiteBlockType.googleReviews,
      title: 'Google Reviews',
      description: 'Carrusel de reseñas desde Google Business Profile.',
      defaultData: {
        'title': 'Reseñas',
        'minRating': 4,
        'maxItems': 8,
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título',
          type: WebsiteBlockFieldType.text,
          textRole: WebsiteTextRole.heading,
          supportsFormatting: true,
          formattingKey: 'titleFormatting',
        ),
        WebsiteBlockFieldSchema(
          key: 'minRating',
          label: 'Calificación mínima',
          type: WebsiteBlockFieldType.number,
          min: 1,
          max: 5,
          step: 1,
          defaultValue: 4,
        ),
        WebsiteBlockFieldSchema(
          key: 'maxItems',
          label: 'Máximo de reseñas',
          type: WebsiteBlockFieldType.number,
          min: 1,
          max: 20,
          step: 1,
          defaultValue: 8,
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          description:
              'La conexión y sincronización se administran en Google. Aquí sólo se edita la presentación del bloque.',
          fieldKeys: ['title', 'minRating', 'maxItems'],
        ),
      ],
    ),
    // Equipo se revisó como candidato a media responsive y se descartó con
    // razón verdadera: la foto se dibuja en un círculo de 96 px con
    // `BoxFit.cover` y alineación central en escritorio, tablet y móvil, así
    // que no hay reencuadre que resolver; un asset por viewport sólo podría
    // cambiar de sujeto, y el alt de la persona es compartido. Sigue
    // compartida hasta que el marco cambie por dispositivo.
    WebsiteBlockType.team: const WebsiteBlockDefinition(
      type: WebsiteBlockType.team,
      title: 'Equipo',
      description:
          'Presenta a los mecánicos y especialistas del taller con su rol.',
      defaultData: {
        'title': 'Nuestro Equipo',
        'description': '',
        'members': [
          {
            'name': 'Daniela Torres',
            'role': 'Jefa de taller',
            'bio':
                'Especialista en bike fitting y suspensiones con 8 años de experiencia.',
            'avatarUrl': null,
          },
          {
            'name': 'Pablo Fuentes',
            'role': 'Mecánico Senior',
            'bio':
                'Experto en transmisión y sistemas hidráulicos. Apasionado por el gravel.',
            'avatarUrl': null,
          },
        ],
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título',
          type: WebsiteBlockFieldType.text,
        ),
        WebsiteBlockFieldSchema(
          key: 'description',
          label: 'Descripción',
          type: WebsiteBlockFieldType.textarea,
          migrationAliases: ['subtitle'],
          textRole: WebsiteTextRole.paragraph,
          supportsFormatting: true,
        ),
        WebsiteBlockFieldSchema(
          key: 'members',
          label: 'Integrantes',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Integrante',
          migrationAliases: ['team', 'items'],
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'name',
              label: 'Nombre',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Integrante',
              textRole: WebsiteTextRole.heading,
              supportsFormatting: true,
            ),
            WebsiteBlockFieldSchema(
              key: 'role',
              label: 'Rol',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Cargo',
              textRole: WebsiteTextRole.caption,
              supportsFormatting: true,
            ),
            WebsiteBlockFieldSchema(
              key: 'bio',
              label: 'Descripción',
              type: WebsiteBlockFieldType.textarea,
              defaultValue: 'Resumen profesional',
              textRole: WebsiteTextRole.paragraph,
              supportsFormatting: true,
            ),
            WebsiteBlockFieldSchema(
              key: 'avatarUrl',
              label: 'Foto',
              type: WebsiteBlockFieldType.image,
              mediaRole: WebsiteMediaRole.avatar,
              supportsAltText: true,
              altTextKey: 'avatarAltText',
              migrationAliases: ['image'],
            ),
            WebsiteBlockFieldSchema(
              key: 'instagram',
              label: 'Instagram',
              type: WebsiteBlockFieldType.link,
              actionRole: WebsiteActionRole.card,
            ),
            WebsiteBlockFieldSchema(
              key: 'linkedin',
              label: 'LinkedIn',
              type: WebsiteBlockFieldType.link,
              actionRole: WebsiteActionRole.card,
            ),
          ],
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'description', 'members'],
        ),
      ],
    ),
    // Indicadores también es auto-layout: el `Wrap` deriva el ancho de cada
    // tarjeta del ancho disponible —una columna bajo 600— y no persiste
    // ninguna propiedad de composición. Etiqueta, valor, sufijo e ícono son el
    // dato del logro; personalizarlos por dispositivo sería publicar tres
    // cifras distintas.
    WebsiteBlockType.stats: const WebsiteBlockDefinition(
      type: WebsiteBlockType.stats,
      title: 'Indicadores',
      description:
          'Muestra logros del taller: bicis reparadas, clientes felices, etc.',
      defaultData: {
        'title': 'Resultados que nos respaldan',
        'metrics': [
          {
            'label': 'Bicis reparadas',
            'value': '1.200+',
          },
          {
            'label': 'Clientes felices',
            'value': '980+',
          },
          {
            'label': 'Años en el mercado',
            'value': '10',
          },
        ],
      },
      fields: [
        WebsiteBlockFieldSchema(
          key: 'title',
          label: 'Título',
          type: WebsiteBlockFieldType.text,
        ),
        WebsiteBlockFieldSchema(
          key: 'metrics',
          label: 'Indicadores',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Indicador',
          migrationAliases: ['stats', 'items'],
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'label',
              label: 'Etiqueta',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Métrica',
              textRole: WebsiteTextRole.caption,
              supportsFormatting: true,
            ),
            WebsiteBlockFieldSchema(
              key: 'value',
              label: 'Valor',
              type: WebsiteBlockFieldType.text,
              defaultValue: '0',
              textRole: WebsiteTextRole.heading,
              supportsFormatting: true,
            ),
            WebsiteBlockFieldSchema(
              key: 'suffix',
              label: 'Sufijo',
              type: WebsiteBlockFieldType.text,
              defaultValue: '',
              textRole: WebsiteTextRole.heading,
              supportsFormatting: true,
            ),
            WebsiteBlockFieldSchema(
              key: 'icon',
              label: 'Ícono',
              type: WebsiteBlockFieldType.select,
              options: [
                WebsiteBlockFieldOption(
                    value: 'military_tech', label: 'Medalla'),
                WebsiteBlockFieldOption(value: 'emoji_events', label: 'Trofeo'),
                WebsiteBlockFieldOption(
                    value: 'directions_bike', label: 'Bicicleta'),
                WebsiteBlockFieldOption(value: 'insights', label: 'Insights'),
              ],
            ),
          ],
        ),
      ],
      controlSections: [
        WebsiteBlockControlSection(
          id: 'content',
          label: 'Contenido',
          fieldKeys: ['title', 'metrics'],
        ),
      ],
    ),
    // El footer de la tienda NO es este bloque. El pie real es chrome del
    // sitio: lo compone `PublicStoreLayout` desde los settings del sitio
    // (pending→saved) y `WebsiteNavigation`, y elige su versión de escritorio
    // o de teléfono sólo por ancho. Este tipo de bloque existe en el registro
    // como cierre de página y su renderer sólo reserva alto; sus campos no
    // llegan a la tienda. Por eso queda entero compartido: declarar aquí una
    // propiedad responsive crearía un segundo dueño del pie y una superficie
    // persistida que nadie dibuja. Contratos:
    // `website_conversion_responsive_policies_test.dart`.
    WebsiteBlockType.footer: WebsiteBlockDefinition(
      type: WebsiteBlockType.footer,
      title: 'Footer',
      description:
          'Cierra la página con datos de contacto, links rápidos y redes sociales.',
      defaultData: {
        'companyName': 'Vinabike',
        'copyright':
            '© ${DateTime.now().year} Vinabike. Todos los derechos reservados.',
        'columns': [
          {
            'title': 'Contacto',
            'items': [
              {'label': '+56 9 1234 5678', 'link': 'tel:+56912345678'},
              {
                'label': 'contacto@vinabike.cl',
                'link': 'mailto:contacto@vinabike.cl'
              },
              {'label': 'Santiago, Chile', 'link': ''},
            ],
          },
          {
            'title': 'Servicios',
            'items': [
              {'label': 'Mantenciones', 'link': '/servicios'},
              {'label': 'Bike fitting', 'link': '/servicios'},
              {'label': 'Venta de repuestos', 'link': '/productos'},
            ],
          },
          {
            'title': 'Redes sociales',
            'items': [
              {'label': 'Instagram', 'link': 'https://instagram.com'},
              {'label': 'Strava', 'link': 'https://strava.com'},
              {'label': 'Facebook', 'link': 'https://facebook.com'},
            ],
          },
        ],
      },
      fields: const [
        WebsiteBlockFieldSchema(
          key: 'companyName',
          label: 'Nombre de la empresa',
          type: WebsiteBlockFieldType.text,
          defaultValue: 'Vinabike',
        ),
        WebsiteBlockFieldSchema(
          key: 'copyright',
          label: 'Texto de copyright',
          type: WebsiteBlockFieldType.text,
          defaultValue: '© 2025 Vinabike. Todos los derechos reservados.',
        ),
        WebsiteBlockFieldSchema(
          key: 'columns',
          label: 'Columnas',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Columna',
          minItems: 1,
          maxItems: 4,
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'title',
              label: 'Título de la columna',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Sección',
            ),
            WebsiteBlockFieldSchema(
              key: 'items',
              label: 'Enlaces',
              type: WebsiteBlockFieldType.repeater,
              itemLabel: 'Enlace',
              itemFields: [
                WebsiteBlockFieldSchema(
                  key: 'label',
                  label: 'Texto',
                  type: WebsiteBlockFieldType.text,
                  defaultValue: 'Link',
                ),
                WebsiteBlockFieldSchema(
                  key: 'link',
                  label: 'Destino',
                  type: WebsiteBlockFieldType.link,
                  defaultValue: '',
                  actionRole: WebsiteActionRole.navigation,
                ),
              ],
            ),
          ],
        ),
      ],
      controlSections: const [
        WebsiteBlockControlSection(
          id: 'branding',
          label: 'Marca',
          fieldKeys: ['companyName', 'copyright'],
        ),
        WebsiteBlockControlSection(
          id: 'columns',
          label: 'Columnas de enlaces',
          fieldKeys: ['columns'],
        ),
      ],
    ),
  };

  static bool _marketplaceLoaded = false;

  static Future<void> ensureInitialized({AssetBundle? bundle}) async {
    debugPrint(
        '[WebsiteBlockRegistry] ensureInitialized called, _marketplaceLoaded=$_marketplaceLoaded');
    if (_marketplaceLoaded) {
      debugPrint('[WebsiteBlockRegistry] Already initialized, returning');
      return;
    }

    // Set loaded immediately to prevent multiple attempts
    _marketplaceLoaded = true;
    debugPrint('[WebsiteBlockRegistry] Starting marketplace load...');

    try {
      // Add timeout to prevent hanging
      final definitions =
          await BlockMarketplaceLoader.loadDefinitions(bundle: bundle)
              .timeout(const Duration(seconds: 3), onTimeout: () {
        debugPrint(
            '[WebsiteBlockRegistry] Marketplace load timed out, using fallback');
        return <WebsiteBlockDefinition>[];
      });

      debugPrint(
          '[WebsiteBlockRegistry] Loaded ${definitions.length} definitions');
      if (definitions.isNotEmpty) {
        _definitions
          ..clear()
          ..addEntries(
            definitions.map(
              (definition) => MapEntry(definition.type, definition),
            ),
          );
      }
    } catch (error, stackTrace) {
      debugPrint('[WebsiteBlockRegistry] Marketplace load failed: $error');
      debugPrint('$stackTrace');
    } finally {
      if (_definitions.isEmpty) {
        debugPrint(
          '[WebsiteBlockRegistry] Falling back to baked-in block definitions.',
        );
        _definitions.addAll(_fallbackDefinitions);
      }
      debugPrint('[WebsiteBlockRegistry] ensureInitialized complete');
    }
  }

  static List<WebsiteBlockDefinition> all() {
    return WebsiteBlockType.values.map(definitionFor).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  static WebsiteBlockDefinition definitionFor(WebsiteBlockType type) {
    final marketplace = _definitions[type];
    final fallback = _fallbackDefinitions[type];

    if (marketplace == null && fallback != null) return fallback;
    if (fallback == null && marketplace != null) return marketplace;
    if (marketplace != null && fallback != null) {
      return WebsiteBlockDefinition(
        type: type,
        title: marketplace.title,
        description: marketplace.description,
        defaultData: {
          ...marketplace.defaultData,
          ...fallback.defaultData,
        },
        // The baked-in schema is the canonical capability contract. Marketplace
        // metadata may enrich labels/discovery, but cannot remove editor controls.
        fields:
            fallback.fields.isNotEmpty ? fallback.fields : marketplace.fields,
        usesCustomEditor:
            fallback.usesCustomEditor || marketplace.usesCustomEditor,
        previewBadge: marketplace.previewBadge ?? fallback.previewBadge,
        category: marketplace.category,
        tags: {...fallback.tags, ...marketplace.tags}.toList(),
        version: marketplace.version > fallback.version
            ? marketplace.version
            : fallback.version,
        supportsResponsive:
            fallback.supportsResponsive && marketplace.supportsResponsive,
        controlSections: fallback.controlSections.isNotEmpty
            ? fallback.controlSections
            : marketplace.controlSections,
      );
    }

    return WebsiteBlockDefinition(
      type: type,
      title: type.name,
      description: 'Bloque sin definición registrada',
      defaultData: const {},
      usesCustomEditor: true,
    );
  }

  static WebsiteBlockCapabilityProfile capabilitiesFor(WebsiteBlockType type) =>
      WebsiteBlockCapabilityRegistry.profileFor(type);

  /// Resolves one schema field by its owner path.
  ///
  /// Custom editors use the same registry metadata as generic controls instead
  /// of recreating a local field contract. Repeater items are addressed with a
  /// dotted path such as `slides.imageUrl`; collection indexes and persisted
  /// item identities deliberately do not belong to the schema path.
  static WebsiteBlockFieldSchema? fieldForPath(
    WebsiteBlockType type,
    String path,
  ) {
    final segments = path
        .split('.')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) return null;

    Iterable<WebsiteBlockFieldSchema> candidates = definitionFor(type).fields;
    WebsiteBlockFieldSchema? resolved;
    for (final segment in segments) {
      resolved = null;
      for (final field in candidates) {
        if (field.key == segment) {
          resolved = field;
          break;
        }
      }
      if (resolved == null) return null;
      candidates = resolved.itemFields;
    }
    return resolved;
  }

  /// Registry-derived responsive capability matrix.
  ///
  /// Nested repeater fields use dotted schema paths. Custom editors still
  /// receive an entry (possibly empty), so the matrix remains total across the
  /// complete block catalogue instead of becoming a second hand-maintained
  /// list that can drift from [WebsiteBlockType.values].
  static Map<WebsiteBlockType, Map<String, WebsiteResponsivePropertyPolicy>>
      responsivePolicyMatrix() {
    return Map<WebsiteBlockType,
        Map<String, WebsiteResponsivePropertyPolicy>>.unmodifiable({
      for (final type in WebsiteBlockType.values)
        type: Map<String, WebsiteResponsivePropertyPolicy>.unmodifiable(
          _responsivePoliciesFor(definitionFor(type).fields),
        ),
    });
  }

  static Map<String, WebsiteResponsivePropertyPolicy> _responsivePoliciesFor(
    Iterable<WebsiteBlockFieldSchema> fields, {
    String prefix = '',
  }) {
    final result = <String, WebsiteResponsivePropertyPolicy>{};
    for (final field in fields) {
      final path = prefix.isEmpty ? field.key : '$prefix.${field.key}';
      result[path] = field.responsivePolicy;
      if (field.supportsFocalPoint) {
        result[prefix.isEmpty
                ? field.focalPointXKey
                : '$prefix.${field.focalPointXKey}'] =
            WebsiteResponsivePropertyPolicy.perViewportGeometry;
        result[prefix.isEmpty
                ? field.focalPointYKey
                : '$prefix.${field.focalPointYKey}'] =
            WebsiteResponsivePropertyPolicy.perViewportGeometry;
      }
      if (field.supportsAltText) {
        result[prefix.isEmpty
                ? field.altTextKey
                : '$prefix.${field.altTextKey}'] =
            WebsiteResponsivePropertyPolicy.sharedOnly;
      }
      result.addAll(
        _responsivePoliciesFor(field.itemFields, prefix: path),
      );
    }
    return result;
  }
}
