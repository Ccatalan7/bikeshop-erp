import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_projection.dart';

/// The simple-elements batch: Text, Button and Divider.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` `handoff-t10/spec.json`
/// `property_policy_matrix` — `layout.*` and `typography.size` are
/// `responsiveOptional`, `text.value` and `cta.destination` are `sharedOnly`.
/// No visual value is introduced by this round.
void main() {
  Map<String, WebsiteBlockFieldSchema> fieldsOf(WebsiteBlockType type) {
    return <String, WebsiteBlockFieldSchema>{
      for (final field in WebsiteBlockRegistry.definitionFor(type).fields)
        field.key: field,
    };
  }

  WebsiteBlockFieldSchema fieldOf(WebsiteBlockType type, String key) {
    final field = fieldsOf(type)[key];
    expect(field, isNotNull, reason: '$type no declara $key');
    return field!;
  }

  group('1 · matriz exacta del lote simple', () {
    test('Divider migra sus TRES propiedades, con familia correcta', () {
      const expected = <String, WebsiteResponsivePropertyFamily>{
        'thickness': WebsiteResponsivePropertyFamily.geometry,
        'widthPct': WebsiteResponsivePropertyFamily.geometry,
        'color': WebsiteResponsivePropertyFamily.color,
      };

      final fields = fieldsOf(WebsiteBlockType.divider);
      expect(
        fields.keys.toSet(),
        expected.keys.toSet(),
        reason: 'el lote no agrega ni quita campos al separador',
      );

      for (final entry in expected.entries) {
        final field = fieldOf(WebsiteBlockType.divider, entry.key);
        expect(
          field.responsivePolicy,
          WebsiteResponsivePropertyPolicy.responsiveOptional,
          reason: entry.key,
        );
        expect(field.allowsViewportOverride, isTrue, reason: entry.key);
        expect(field.canResetResponsiveOverride, isTrue, reason: entry.key);
        expect(field.resolvedPropertyFamily, entry.value, reason: entry.key);
      }
    });

    test('el separador no adquirió defaults, aliases ni campos nuevos', () {
      final definition =
          WebsiteBlockRegistry.definitionFor(WebsiteBlockType.divider);
      expect(definition.defaultData, <String, dynamic>{
        'widthPct': 1.0,
        'thickness': 1,
        'color': '#E5E7EB',
      });
      for (final field in definition.fields) {
        expect(field.migrationAliases, isEmpty, reason: field.key);
        expect(field.legacyResponsiveAliases, isEmpty, reason: field.key);
      }
      expect(fieldOf(WebsiteBlockType.divider, 'thickness').defaultValue, 1);
      expect(fieldOf(WebsiteBlockType.divider, 'widthPct').defaultValue, 1.0);
      expect(
        fieldOf(WebsiteBlockType.divider, 'color').defaultValue,
        '#E5E7EB',
      );
    });

    test('Text y Button conservan exactamente su línea base', () {
      for (final (type, key) in const <(WebsiteBlockType, String)>[
        (WebsiteBlockType.text, 'preset'),
        (WebsiteBlockType.text, 'maxWidth'),
        (WebsiteBlockType.button, 'style'),
      ]) {
        expect(
          fieldOf(type, key).responsivePolicy,
          WebsiteResponsivePropertyPolicy.responsiveOptional,
          reason: '$type.$key',
        );
      }
      // Y su contenido y su destino siguen compartidos.
      for (final (type, key) in const <(WebsiteBlockType, String)>[
        (WebsiteBlockType.text, 'text'),
        (WebsiteBlockType.button, 'label'),
        (WebsiteBlockType.button, 'link'),
      ]) {
        expect(
          fieldOf(type, key).responsivePolicy,
          WebsiteResponsivePropertyPolicy.sharedOnly,
          reason: '$type.$key',
        );
      }
    });

    test('el lote no tiene copy ni destinos que migrar', () {
      for (final type in const [
        WebsiteBlockType.text,
        WebsiteBlockType.button,
        WebsiteBlockType.divider,
      ]) {
        for (final field in WebsiteBlockRegistry.definitionFor(type).fields) {
          if (!field.allowsViewportOverride) continue;
          expect(
            field.type,
            isNot(WebsiteBlockFieldType.link),
            reason: '$type.${field.key} es un destino',
          );
          expect(
            field.resolvedPropertyFamily,
            isNot(WebsiteResponsivePropertyFamily.content),
            reason: '$type.${field.key} es contenido',
          );
          expect(
            field.responsivePolicy,
            isNot(WebsiteResponsivePropertyPolicy.responsiveDisplayCopy),
            reason: '$type.${field.key}',
          );
        }
      }
    });
  });

  group('4 · projection del separador, sin cascada', () {
    Map<String, dynamic> projected(
      Map<String, dynamic> data,
      WebsiteViewport viewport,
    ) {
      return WebsiteResponsiveBlockProjection.project(
        type: WebsiteBlockType.divider,
        data: data,
        viewport: viewport,
      );
    }

    test('cada viewport resuelve su propio override sobre la base', () {
      final document = <String, dynamic>{
        'thickness': 1,
        'widthPct': 1.0,
        'color': '#E5E7EB',
        'responsive': <String, dynamic>{
          'mobile': <String, dynamic>{'thickness': 4, 'widthPct': 0.6},
          'tablet': <String, dynamic>{'color': '#111111'},
        },
      };

      // Escritorio es la base.
      expect(projected(document, WebsiteViewport.desktop)['thickness'], 1);
      expect(projected(document, WebsiteViewport.desktop)['widthPct'], 1.0);
      expect(
        projected(document, WebsiteViewport.desktop)['color'],
        '#E5E7EB',
      );

      // Móvil toma los suyos y hereda el color de la base.
      final mobile = projected(document, WebsiteViewport.mobile);
      expect(mobile['thickness'], 4);
      expect(mobile['widthPct'], 0.6);
      expect(mobile['color'], '#E5E7EB');

      // Tablet toma el suyo y NO hereda nada de móvil.
      final tablet = projected(document, WebsiteViewport.tablet);
      expect(tablet['color'], '#111111');
      expect(tablet['thickness'], 1, reason: 'tablet no hereda de móvil');
      expect(tablet['widthPct'], 1.0, reason: 'tablet no hereda de móvil');
    });

    test('un documento sin overrides proyecta la base en los tres', () {
      final document = <String, dynamic>{
        'thickness': 2,
        'widthPct': 0.8,
        'color': '#000000',
      };
      for (final viewport in WebsiteViewport.values) {
        final result = projected(document, viewport);
        expect(result['thickness'], 2, reason: viewport.name);
        expect(result['widthPct'], 0.8, reason: viewport.name);
        expect(result['color'], '#000000', reason: viewport.name);
      }
    });
  });
}
