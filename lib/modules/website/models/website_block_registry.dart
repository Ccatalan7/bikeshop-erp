import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../block_marketplace/block_marketplace_loader.dart';
import 'website_block_capabilities.dart';
import 'website_block_definition.dart';
import 'website_block_type.dart';

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
        // Mobile background focal point (0..1). Edited via a special control.
        'mobileFocalPointX': 0.5,
        'mobileFocalPointY': 0.5,
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
        ),
        WebsiteBlockFieldSchema(
          key: 'showOverlay',
          label: 'Mostrar overlay',
          type: WebsiteBlockFieldType.toggle,
          defaultValue: true,
        ),
        WebsiteBlockFieldSchema(
          key: 'overlayOpacity',
          label: 'Opacidad overlay',
          type: WebsiteBlockFieldType.number,
          min: 0,
          max: 1,
          step: 0.1,
          defaultValue: 0.5,
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
        'height': 420,
        'backgroundColor': '#FFFFFF',
        'backgroundImageUrl': '',
        'backgroundImageAltText': '',
        'focalPointX': 0.5,
        'focalPointY': 0.5,
        'mobileFocalPointX': 0.5,
        'mobileFocalPointY': 0.5,
        'constrainElementsToSafeArea': true,
        'elements': <Map<String, dynamic>>[],
        'activeElementId': null,
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
        WebsiteBlockFieldSchema(
          key: 'thickness',
          label: 'Grosor',
          type: WebsiteBlockFieldType.number,
          min: 0,
          max: 12,
          step: 1,
          defaultValue: 1,
        ),
        WebsiteBlockFieldSchema(
          key: 'widthPct',
          label: 'Ancho (%)',
          type: WebsiteBlockFieldType.number,
          min: 0.1,
          max: 1.0,
          step: 0.05,
          defaultValue: 1.0,
        ),
        WebsiteBlockFieldSchema(
          key: 'color',
          label: 'Color',
          type: WebsiteBlockFieldType.color,
          defaultValue: '#E5E7EB',
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
        'layout': 'grid',
        'showPrice': true,
        'showStock': false,
        'productIds': <int>[],
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
      usesCustomEditor: true,
    ),
    WebsiteBlockType.services: const WebsiteBlockDefinition(
      type: WebsiteBlockType.services,
      title: 'Servicios',
      description:
          'Describe servicios clave con iconos y llamadas a la acción.',
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
          minItems: 1,
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
            ),
            WebsiteBlockFieldSchema(
              key: 'description',
              label: 'Descripción',
              type: WebsiteBlockFieldType.textarea,
              defaultValue: 'Describe el servicio',
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
        WebsiteBlockFieldSchema(
          key: 'imageUrl',
          label: 'Imagen',
          type: WebsiteBlockFieldType.image,
          group: 'media',
          mediaRole: WebsiteMediaRole.inline,
          supportsAltText: true,
          altTextKey: 'imageAltText',
          migrationAliases: ['image'],
        ),
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
          minItems: 1,
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'name',
              label: 'Nombre',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Nombre',
            ),
            WebsiteBlockFieldSchema(
              key: 'role',
              label: 'Rol',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Cliente',
            ),
            WebsiteBlockFieldSchema(
              key: 'comment',
              label: 'Comentario',
              type: WebsiteBlockFieldType.textarea,
              defaultValue: 'Escribe el testimonio',
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
        ),
        WebsiteBlockFieldSchema(
          key: 'features',
          label: 'Características',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Característica',
          minItems: 1,
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
            ),
            WebsiteBlockFieldSchema(
              key: 'description',
              label: 'Descripción',
              type: WebsiteBlockFieldType.textarea,
              defaultValue: 'Describe la característica',
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
        ),
        WebsiteBlockFieldSchema(
          key: 'overlayColor',
          label: 'Color de superposición',
          type: WebsiteBlockFieldType.color,
          defaultValue: '#000000',
        ),
        WebsiteBlockFieldSchema(
          key: 'overlayOpacity',
          label: 'Opacidad de superposición',
          type: WebsiteBlockFieldType.number,
          min: 0,
          max: 1,
          step: 0.05,
          defaultValue: 0.5,
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
        WebsiteBlockFieldSchema(
          key: 'layout',
          label: 'Diseño',
          type: WebsiteBlockFieldType.select,
          defaultValue: 'grid',
          options: [
            WebsiteBlockFieldOption(value: 'grid', label: 'Cuadrícula'),
            WebsiteBlockFieldOption(value: 'masonry', label: 'Mosaico'),
          ],
        ),
        WebsiteBlockFieldSchema(
          key: 'images',
          label: 'Imágenes',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Imagen',
          minItems: 1,
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'imageUrl',
              label: 'Imagen',
              type: WebsiteBlockFieldType.image,
              mediaRole: WebsiteMediaRole.galleryItem,
              supportsFocalPoint: true,
              supportsAltText: true,
              altTextKey: 'altText',
            ),
            WebsiteBlockFieldSchema(
              key: 'caption',
              label: 'Leyenda',
              type: WebsiteBlockFieldType.text,
              textRole: WebsiteTextRole.caption,
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
          minItems: 1,
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'question',
              label: 'Pregunta',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Nueva pregunta',
            ),
            WebsiteBlockFieldSchema(
              key: 'answer',
              label: 'Respuesta',
              type: WebsiteBlockFieldType.textarea,
              defaultValue: 'Respuesta detallada',
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
          minItems: 1,
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'name',
              label: 'Nombre',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Nuevo plan',
            ),
            WebsiteBlockFieldSchema(
              key: 'price',
              label: 'Precio',
              type: WebsiteBlockFieldType.text,
              defaultValue: '0',
            ),
            WebsiteBlockFieldSchema(
              key: 'ctaText',
              label: 'Texto del botón',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Reservar',
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
          fieldKeys: ['title', 'categories'],
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
        ),
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
          {'label': 'Envíos a todo Chile'},
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
    WebsiteBlockType.googleReviews: const WebsiteBlockDefinition(
      type: WebsiteBlockType.googleReviews,
      title: 'Google Reviews',
      description: 'Carrusel de reseñas desde Google Business Profile.',
      defaultData: {
        'title': 'Reseñas',
        'minRating': 4,
        'maxItems': 8,
      },
      usesCustomEditor: true,
    ),
    WebsiteBlockType.team: const WebsiteBlockDefinition(
      type: WebsiteBlockType.team,
      title: 'Equipo',
      description:
          'Presenta a los mecánicos y especialistas del taller con su rol.',
      defaultData: {
        'title': 'Nuestro Equipo',
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
          key: 'members',
          label: 'Integrantes',
          type: WebsiteBlockFieldType.repeater,
          itemLabel: 'Integrante',
          minItems: 1,
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'name',
              label: 'Nombre',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Integrante',
            ),
            WebsiteBlockFieldSchema(
              key: 'role',
              label: 'Rol',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Cargo',
            ),
            WebsiteBlockFieldSchema(
              key: 'bio',
              label: 'Descripción',
              type: WebsiteBlockFieldType.textarea,
              defaultValue: 'Resumen profesional',
            ),
            WebsiteBlockFieldSchema(
              key: 'avatarUrl',
              label: 'Foto',
              type: WebsiteBlockFieldType.image,
              mediaRole: WebsiteMediaRole.avatar,
              supportsAltText: true,
              altTextKey: 'avatarAltText',
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
          fieldKeys: ['title', 'members'],
        ),
      ],
    ),
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
          minItems: 1,
          itemFields: [
            WebsiteBlockFieldSchema(
              key: 'label',
              label: 'Etiqueta',
              type: WebsiteBlockFieldType.text,
              defaultValue: 'Métrica',
            ),
            WebsiteBlockFieldSchema(
              key: 'value',
              label: 'Valor',
              type: WebsiteBlockFieldType.text,
              defaultValue: '0',
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
}
