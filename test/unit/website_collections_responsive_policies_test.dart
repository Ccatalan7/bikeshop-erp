import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_projection.dart';

/// El lote de colecciones: Galería, Testimonios, Google Reviews, Equipo y FAQ.
///
/// Matriz derivada del schema y del consumer real, no de lo que sería
/// técnicamente posible. Sólo Galería tiene propiedades de presentación que el
/// renderer lee distinto por viewport (`layout` y la imagen de cada item); las
/// otras cuatro terminan enteramente compartidas, cada una con su razón
/// afirmada abajo. Esta ronda no introduce ningún valor visual: reutiliza
/// `ResponsiveFieldShell` y `ResponsiveMediaField`, ya trazados a
/// `Website Builder Responsive Authoring` `handoff-t10` en los lotes previos.
void main() {
  Map<String, WebsiteBlockFieldSchema> flatFieldsOf(WebsiteBlockType type) {
    final result = <String, WebsiteBlockFieldSchema>{};
    void walk(Iterable<WebsiteBlockFieldSchema> fields, String prefix) {
      for (final field in fields) {
        result['$prefix${field.key}'] = field;
        walk(field.itemFields, '$prefix${field.key}.');
      }
    }

    walk(WebsiteBlockRegistry.definitionFor(type).fields, '');
    return result;
  }

  WebsiteBlockFieldSchema fieldOf(WebsiteBlockType type, String path) {
    final field = flatFieldsOf(type)[path];
    expect(field, isNotNull, reason: '$type no declara $path');
    return field!;
  }

  const batch = <WebsiteBlockType>[
    WebsiteBlockType.gallery,
    WebsiteBlockType.testimonials,
    WebsiteBlockType.googleReviews,
    WebsiteBlockType.team,
    WebsiteBlockType.faq,
  ];

  String sourceOf(String path) => File(path).readAsStringSync();

  final gallerySource = sourceOf(
      'lib/modules/website/widgets/website_gallery_block_content.dart');
  final testimonialsSource = sourceOf(
    'lib/modules/website/widgets/website_testimonials_block_content.dart',
  );
  final teamSource =
      sourceOf('lib/modules/website/widgets/website_team_block_content.dart');
  final faqSource =
      sourceOf('lib/modules/website/widgets/website_faq_block_content.dart');
  final reviewsSource =
      sourceOf('lib/modules/website/widgets/google_reviews_carousel.dart');
  final rendererSource =
      sourceOf('lib/modules/website/widgets/website_block_renderer.dart');

  group('A · matriz exacta de las cinco familias', () {
    test('Galería: el diseño y la imagen del item, nada más', () {
      final fields = flatFieldsOf(WebsiteBlockType.gallery);
      expect(
        fields.keys.toSet(),
        <String>{
          'title',
          'layout',
          'images',
          'images.imageUrl',
          'images.caption'
        },
        reason: 'el schema declara sólo lo que el editor expone',
      );

      // `layout` cambia la proporción del tile en los tres viewports.
      final layout = fieldOf(WebsiteBlockType.gallery, 'layout');
      expect(
        layout.responsivePolicy,
        WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(
        layout.resolvedPropertyFamily,
        WebsiteResponsivePropertyFamily.geometry,
      );
      expect(layout.canResetResponsiveOverride, isTrue);
      expect(
        gallerySource,
        contains("masonry: layout == 'masonry'"),
        reason: 'sin este consumer, `layout` sería un control decorativo',
      );

      // La imagen del item: art direction del mismo sujeto.
      final image = fieldOf(WebsiteBlockType.gallery, 'images.imageUrl');
      expect(
        image.responsivePolicy,
        WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(
        image.resolvedPropertyFamily,
        WebsiteResponsivePropertyFamily.media,
      );
      expect(image.hasFocalPointControl, isTrue);
      expect(
        image.authoringSurfaces,
        containsAll(const <WebsiteAuthoringSurface>{
          WebsiteAuthoringSurface.inline,
          WebsiteAuthoringSurface.contextSheet,
          WebsiteAuthoringSurface.inspector,
        }),
        reason: 'la galería se edita inline y desde el host compacto',
      );
      expect(
        image.legacyResponsiveAliases,
        isEmpty,
        reason: 'la galería nunca guardó un alias móvil: no se inventa uno',
      );

      // Copy, identidad de la colección y alt siguen compartidos.
      for (final path in const <String>['title', 'images', 'images.caption']) {
        expect(
          fieldOf(WebsiteBlockType.gallery, path).responsivePolicy,
          WebsiteResponsivePropertyPolicy.sharedOnly,
          reason: path,
        );
      }
      expect(image.altTextKey, 'altText');
      expect(
        fields.containsKey('images.altText'),
        isFalse,
        reason: 'el alt lo posee el media field, no un input duplicado',
      );

      // Y el encuadre por viewport, que el renderer ya lee por item.
      final matrix = WebsiteBlockRegistry.responsivePolicyMatrix()[
          WebsiteBlockType.gallery]!;
      expect(
        matrix['images.focalPointX'],
        WebsiteResponsivePropertyPolicy.perViewportGeometry,
      );
      expect(
        matrix['images.focalPointY'],
        WebsiteResponsivePropertyPolicy.perViewportGeometry,
      );
      expect(
        matrix['images.altText'],
        WebsiteResponsivePropertyPolicy.sharedOnly,
      );
      expect(gallerySource, contains('_resolveFocalAlignment(image)'));
    });

    test('Testimonios: cero propiedades responsive, y por qué', () {
      final fields = flatFieldsOf(WebsiteBlockType.testimonials);
      expect(
        fields.keys.toSet(),
        <String>{
          'title',
          'testimonials',
          'testimonials.name',
          'testimonials.role',
          'testimonials.comment',
          'testimonials.rating',
        },
      );
      for (final entry in fields.entries) {
        expect(
          entry.value.allowsViewportOverride,
          isFalse,
          reason: '${entry.key}: es contenido del cliente, no presentación',
        );
      }
      // El renderer no lee ninguna propiedad de composición: el ancho de la
      // tarjeta sale del ancho disponible.
      expect(testimonialsSource, contains('final compact = availableWidth'));
      expect(
        testimonialsSource,
        isNot(contains("data['layout']")),
        reason: 'si apareciera un layout, habría que migrarlo en su ronda',
      );
    });

    test('FAQ: cero propiedades responsive, y por qué', () {
      final fields = flatFieldsOf(WebsiteBlockType.faq);
      expect(
        fields.keys.toSet(),
        <String>{
          'title',
          'subtitle',
          'items',
          'items.question',
          'items.answer',
        },
      );
      for (final entry in fields.entries) {
        expect(
          entry.value.allowsViewportOverride,
          isFalse,
          reason: '${entry.key}: pregunta y respuesta son contenido indexable',
        );
      }
      // El único ajuste por ancho ya lo calcula el renderer.
      expect(faqSource, contains('final titleSize = isCompact'));
    });

    test('Equipo: la foto quedó compartida con razón verdadera', () {
      final fields = flatFieldsOf(WebsiteBlockType.team);
      expect(
        fields.keys.toSet(),
        <String>{
          'title',
          'description',
          'members',
          'members.name',
          'members.role',
          'members.bio',
          'members.avatarUrl',
          'members.instagram',
          'members.linkedin',
        },
      );
      for (final entry in fields.entries) {
        expect(
          entry.value.allowsViewportOverride,
          isFalse,
          reason: entry.key,
        );
      }

      // El candidato evaluado: el marco de la foto es idéntico en los tres
      // viewports, así que no hay reencuadre que ofrecer ni art direction que
      // justificar; un asset por viewport sólo cambiaría de sujeto.
      final avatar = fieldOf(WebsiteBlockType.team, 'members.avatarUrl');
      expect(avatar.resolvedMediaRole, WebsiteMediaRole.avatar);
      expect(avatar.hasFocalPointControl, isFalse);
      expect(avatar.canResetResponsiveOverride, isFalse);
      expect(teamSource, contains('dimension: 96'));
      expect(teamSource, contains('alignment: Alignment.center'));
      expect(
        teamSource,
        isNot(contains('focalPointX')),
        reason: 'el avatar no encuadra: no puede prometer un foco por viewport',
      );
      // Y su alt sigue siendo uno solo, del schema.
      expect(avatar.altTextKey, 'avatarAltText');
      expect(
        WebsiteBlockRegistry.responsivePolicyMatrix()[WebsiteBlockType.team]![
            'members.avatarAltText'],
        WebsiteResponsivePropertyPolicy.sharedOnly,
      );
    });

    test('Google Reviews: filtros de negocio, no presentación', () {
      final fields = flatFieldsOf(WebsiteBlockType.googleReviews);
      expect(fields.keys.toSet(), <String>{'title', 'minRating', 'maxItems'});
      for (final entry in fields.entries) {
        expect(
          entry.value.allowsViewportOverride,
          isFalse,
          reason: '${entry.key}: la verdad de Google no varía por dispositivo',
        );
      }
      // El carrusel no tiene composición por dispositivo que personalizar.
      expect(reviewsSource, contains('width: 320'));
      expect(reviewsSource, contains('height: 280'));
      // Y el rating agregado se lee del negocio, o se calcula de la lista
      // completa: filtrar cards no puede inflar la nota.
      expect(reviewsSource, contains('_averageRating(_sourceReviews())'));
    });

    test('ninguna colección del lote se volvió responsive entera', () {
      for (final (type, key) in const <(WebsiteBlockType, String)>[
        (WebsiteBlockType.gallery, 'images'),
        (WebsiteBlockType.testimonials, 'testimonials'),
        (WebsiteBlockType.team, 'members'),
        (WebsiteBlockType.faq, 'items'),
      ]) {
        final field = fieldOf(type, key);
        expect(field.type, WebsiteBlockFieldType.repeater);
        expect(field.allowsViewportOverride, isFalse, reason: '$type.$key');
      }
    });

    test('el lote no habilitó display copy', () {
      for (final type in batch) {
        for (final entry in flatFieldsOf(type).entries) {
          expect(
            entry.value.responsivePolicy,
            isNot(WebsiteResponsivePropertyPolicy.responsiveDisplayCopy),
            reason: '$type.${entry.key}',
          );
        }
      }
    });

    test('los aliases legacy de las colecciones siguen declarados', () {
      // Migrar la política no puede perder los documentos guardados con la
      // clave antigua de la colección.
      expect(
        fieldOf(WebsiteBlockType.testimonials, 'testimonials').migrationAliases,
        contains('items'),
      );
      expect(
        fieldOf(WebsiteBlockType.team, 'members').migrationAliases,
        containsAll(const <String>['team', 'items']),
      );
      expect(
        fieldOf(WebsiteBlockType.testimonials, 'testimonials.comment')
            .migrationAliases,
        containsAll(const <String>['quote', 'text']),
      );
      expect(
        fieldOf(WebsiteBlockType.team, 'members.avatarUrl').migrationAliases,
        contains('image'),
      );
    });
  });

  group('B · deuda declarada, no capacidad fingida', () {
    test('minRating y maxItems tienen consumer real y siguen compartidos', () {
      // Se editan, se guardan y ahora el carrusel los aplica a las reseñas
      // reales. Siguen `sharedOnly` porque son filtros de negocio: la tienda
      // no puede mostrar reseñas distintas según el dispositivo.
      for (final key in const <String>['minRating', 'maxItems']) {
        expect(
          reviewsSource,
          contains("data['$key']"),
          reason: '$key sin consumer volvería a ser un control falso',
        );
        expect(
          flatFieldsOf(WebsiteBlockType.googleReviews)[key]!.responsivePolicy,
          WebsiteResponsivePropertyPolicy.sharedOnly,
          reason: '$key es filtro de negocio, no presentación',
        );
      }
      // Y el cableado sigue entrando por la misma inyección de verdad Google.
      expect(rendererSource,
          contains("service.getSetting('google_reviews_data')"));
    });

    test('el título declara formato y el consumer lo pinta', () {
      final title = fieldOf(WebsiteBlockType.googleReviews, 'title');
      expect(title.supportsFormatting, isTrue);
      expect(title.resolvedFormattingKey, 'titleFormatting');
      expect(
        reviewsSource,
        contains("_resolveFormatting(data['titleFormatting'])"),
        reason: 'declararlo sin pintarlo es otra capacidad falsa',
      );
      expect(reviewsSource, contains('titleFormatting.applyTo('));
      // Y sigue compartido: el formato del título no varía por dispositivo.
      expect(
        title.responsivePolicy,
        WebsiteResponsivePropertyPolicy.sharedOnly,
      );
    });

    test('el color de fondo de Google Reviews no se inventó como capacidad',
        () {
      // El carrusel sí lo lee, pero el schema nunca lo expuso. Declararlo aquí
      // agregaría un control nuevo al inspector, que no es lo que migra este
      // lote.
      expect(reviewsSource, contains("_parseColor(data['backgroundColor'])"));
      expect(
        flatFieldsOf(WebsiteBlockType.googleReviews)
            .containsKey('backgroundColor'),
        isFalse,
      );
    });

    test('el carrusel ya no fabrica reseñas de muestra', () {
      // Con la fuente vacía el bloque dibujaba cuatro personas inventadas con
      // fotos de `randomuser`. Eso es contenido falso en la tienda del dueño,
      // y aquí queda cerrado por guard estático además del test de widget.
      for (final invented in const <String>[
        'randomuser',
        'Carlos Rivera',
        'Maria José Soto',
        'Felipe Andrés',
        'Return Mocks',
      ]) {
        expect(
          reviewsSource,
          isNot(contains(invented)),
          reason: 'la tienda no publica gente que no existe',
        );
      }
      // La fuente visible es sólo la real.
      expect(reviewsSource, contains("data['reviews']"));
      expect(
        flatFieldsOf(WebsiteBlockType.googleReviews).containsKey('reviews'),
        isFalse,
        reason: 'la lista sincronizada no es un campo del editor',
      );
    });
  });

  group('C · projection por viewport, sin cascada ni contaminación', () {
    Map<String, dynamic> projected(
      WebsiteBlockType type,
      Map<String, dynamic> document,
      WebsiteViewport viewport,
    ) =>
        WebsiteResponsiveBlockProjection.project(
          type: type,
          data: document,
          viewport: viewport,
        );

    test('Galería: layout y la imagen de un item resuelven por viewport', () {
      final document = <String, dynamic>{
        'title': 'Nuestro taller',
        'layout': 'masonry',
        'images': <Map<String, dynamic>>[
          {
            'id': 'img-a',
            'imageUrl': 'https://cdn/taller.webp',
            'altText': 'Mecánico ajustando una transmisión',
            'caption': 'Puesta a punto',
            'focalPointX': 0.5,
            'responsive': <String, dynamic>{
              'mobile': <String, dynamic>{
                'imageUrl': 'https://cdn/taller-vertical.webp',
                'focalPointX': 0.75,
              },
            },
          },
          {
            'id': 'img-b',
            'imageUrl': 'https://cdn/ruta.webp',
            'caption': 'Salida de ruta',
          },
        ],
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{'layout': 'grid'},
        },
      };

      List<Map<String, dynamic>> images(WebsiteViewport viewport) =>
          (projected(WebsiteBlockType.gallery, document, viewport)['images']
                  as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList(growable: false);

      expect(
        projected(WebsiteBlockType.gallery, document, WebsiteViewport.desktop)[
            'layout'],
        'masonry',
      );
      expect(
        projected(WebsiteBlockType.gallery, document, WebsiteViewport.tablet)[
            'layout'],
        'masonry',
        reason: 'tablet hereda de la base, nunca de móvil',
      );
      expect(
        projected(WebsiteBlockType.gallery, document, WebsiteViewport.mobile)[
            'layout'],
        'grid',
      );

      expect(
        images(WebsiteViewport.mobile)[0]['imageUrl'],
        'https://cdn/taller-vertical.webp',
      );
      expect(images(WebsiteViewport.mobile)[0]['focalPointX'], 0.75);
      expect(
        images(WebsiteViewport.tablet)[0]['imageUrl'],
        'https://cdn/taller.webp',
      );
      expect(images(WebsiteViewport.tablet)[0]['focalPointX'], 0.5);
      // El hermano no se contamina.
      expect(
        images(WebsiteViewport.mobile)[1]['imageUrl'],
        'https://cdn/ruta.webp',
      );
      expect(
          images(WebsiteViewport.mobile)[1].containsKey('responsive'), isFalse);
      // Alt y leyenda son los mismos en los tres.
      for (final viewport in WebsiteViewport.values) {
        expect(
          images(viewport)[0]['altText'],
          'Mecánico ajustando una transmisión',
          reason: '$viewport',
        );
        expect(images(viewport)[0]['caption'], 'Puesta a punto');
        expect(
          projected(WebsiteBlockType.gallery, document, viewport)['title'],
          'Nuestro taller',
        );
      }
    });

    test('un override plantado sobre una clave compartida no cambia la tienda',
        () {
      // Un documento heredado —o un error— puede traer un `responsive` sobre
      // contenido. La proyección tiene que ignorarlo: si lo respetara, la
      // política sería decorativa.
      final testimonials = <String, dynamic>{
        'title': 'Lo que dicen',
        'testimonials': <Map<String, dynamic>>[
          {
            'name': 'Carla',
            'comment': 'Quedó impecable',
            'rating': 5,
            'responsive': <String, dynamic>{
              'mobile': <String, dynamic>{
                'comment': 'Otro testimonio',
                'rating': 3,
              },
            },
          },
        ],
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{'title': 'Título móvil'},
        },
      };
      final faq = <String, dynamic>{
        'title': 'Preguntas',
        'items': <Map<String, dynamic>>[
          {
            'question': '¿Cuánto demora?',
            'answer': 'Entre 24 y 48 horas.',
            'responsive': <String, dynamic>{
              'mobile': <String, dynamic>{'answer': 'Rápido'},
            },
          },
        ],
      };
      final team = <String, dynamic>{
        'members': <Map<String, dynamic>>[
          {
            'name': 'Daniela Torres',
            'avatarUrl': 'https://cdn/daniela.webp',
            'avatarAltText': 'Daniela en el taller',
            'responsive': <String, dynamic>{
              'mobile': <String, dynamic>{
                'avatarUrl': 'https://cdn/otra-persona.webp',
              },
            },
          },
        ],
      };
      final reviews = <String, dynamic>{
        'title': 'Reseñas',
        'minRating': 4,
        'maxItems': 8,
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{'minRating': 1, 'maxItems': 2},
        },
      };

      for (final viewport in WebsiteViewport.values) {
        final item = (projected(WebsiteBlockType.testimonials, testimonials,
                viewport)['testimonials'] as List)
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .single;
        expect(item['comment'], 'Quedó impecable', reason: '$viewport');
        expect(item['rating'], 5, reason: '$viewport');
        expect(
          projected(
              WebsiteBlockType.testimonials, testimonials, viewport)['title'],
          'Lo que dicen',
          reason: '$viewport',
        );

        final question =
            (projected(WebsiteBlockType.faq, faq, viewport)['items'] as List)
                .map((raw) => Map<String, dynamic>.from(raw as Map))
                .single;
        expect(question['answer'], 'Entre 24 y 48 horas.', reason: '$viewport');

        final member =
            (projected(WebsiteBlockType.team, team, viewport)['members']
                    as List)
                .map((raw) => Map<String, dynamic>.from(raw as Map))
                .single;
        expect(
          member['avatarUrl'],
          'https://cdn/daniela.webp',
          reason: '$viewport: la foto no cambia de persona por dispositivo',
        );
        expect(member['avatarAltText'], 'Daniela en el taller');

        final review =
            projected(WebsiteBlockType.googleReviews, reviews, viewport);
        expect(review['minRating'], 4, reason: '$viewport');
        expect(review['maxItems'], 8, reason: '$viewport');
      }
    });

    test('las listas vacías y los alias de colección sobreviven la proyección',
        () {
      final emptyGallery = <String, dynamic>{
        'title': 'Galería',
        'images': <Map<String, dynamic>>[],
      };
      for (final viewport in WebsiteViewport.values) {
        expect(
          projected(WebsiteBlockType.gallery, emptyGallery, viewport)['images'],
          isEmpty,
          reason: '$viewport',
        );
      }

      // Documento antiguo: la colección vive bajo el alias.
      final legacyTeam = <String, dynamic>{
        'title': 'Equipo',
        'team': <Map<String, dynamic>>[
          {'name': 'Pablo Fuentes', 'role': 'Mecánico Senior'},
        ],
      };
      for (final viewport in WebsiteViewport.values) {
        final members =
            (projected(WebsiteBlockType.team, legacyTeam, viewport)['members']
                    as List)
                .map((raw) => Map<String, dynamic>.from(raw as Map))
                .toList(growable: false);
        expect(members.single['name'], 'Pablo Fuentes', reason: '$viewport');
      }

      final legacyTestimonials = <String, dynamic>{
        'items': <Map<String, dynamic>>[
          {'name': 'Carla', 'quote': 'Quedó impecable'},
        ],
      };
      for (final viewport in WebsiteViewport.values) {
        final list = (projected(WebsiteBlockType.testimonials,
                legacyTestimonials, viewport)['testimonials'] as List)
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .toList(growable: false);
        expect(list.single['quote'], 'Quedó impecable', reason: '$viewport');
      }
    });
  });
}
