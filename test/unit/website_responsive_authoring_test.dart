import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';

void main() {
  group('WebsiteViewport', () {
    test('classifies the canonical logical canvas boundaries', () {
      expect(WebsiteViewport.fromLogicalWidth(0), WebsiteViewport.mobile);
      expect(WebsiteViewport.fromLogicalWidth(599.999), WebsiteViewport.mobile);
      expect(WebsiteViewport.fromLogicalWidth(600), WebsiteViewport.tablet);
      expect(WebsiteViewport.fromLogicalWidth(899.999), WebsiteViewport.tablet);
      expect(WebsiteViewport.fromLogicalWidth(900), WebsiteViewport.desktop);
    });

    test('legacy documents retain 640/1024 until versioned migration', () {
      const legacy = <String, dynamic>{};
      const canonical = <String, dynamic>{
        'responsive': {
          'version': 2,
          'mobile': {'focalPointX': 0.7},
        },
      };

      expect(WebsiteResponsiveDataCodec.usesCanonicalSchema(legacy), isFalse);
      expect(
        WebsiteResponsiveDataCodec.usesCanonicalSchema(canonical),
        isTrue,
      );
      expect(
        WebsiteResponsiveDataCodec.viewportForDocumentWidth(legacy, 620),
        WebsiteViewport.mobile,
      );
      expect(
        WebsiteResponsiveDataCodec.viewportForDocumentWidth(canonical, 620),
        WebsiteViewport.tablet,
      );
      expect(
        WebsiteResponsiveDataCodec.viewportForDocumentWidth(legacy, 1000),
        WebsiteViewport.tablet,
      );
      expect(
        WebsiteResponsiveDataCodec.viewportForDocumentWidth(canonical, 1000),
        WebsiteViewport.desktop,
      );
    });
  });

  group('WebsiteAuthoringContext', () {
    test('keeps host, viewport and write scope independent', () {
      const context = WebsiteAuthoringContext(
        hostClass: WebsiteAuthoringHostClass.phone,
        previewViewport: WebsiteViewport.mobile,
        writeScope: WebsiteWriteScope.viewport,
      );

      expect(
        context.effectiveWriteScope(
          WebsiteResponsivePropertyPolicy.responsiveOptional,
        ),
        WebsiteWriteScope.viewport,
      );
      expect(
        context.effectiveWriteScope(
          WebsiteResponsivePropertyPolicy.sharedOnly,
        ),
        WebsiteWriteScope.shared,
      );

      final desktop = context.copyWith(
        previewViewport: WebsiteViewport.desktop,
      );
      expect(desktop.hostClass, WebsiteAuthoringHostClass.phone);
      expect(desktop.previewViewport, WebsiteViewport.desktop);
      expect(desktop.writeScope, WebsiteWriteScope.shared);
    });
  });

  group('WebsiteResponsiveDataCodec', () {
    const policies = <String, WebsiteResponsivePropertyPolicy>{
      'focalPointX': WebsiteResponsivePropertyPolicy.responsiveOptional,
      'altText': WebsiteResponsivePropertyPolicy.sharedOnly,
      'headline': WebsiteResponsivePropertyPolicy.responsiveDisplayCopy,
    };

    test('resolves override current or shared without viewport cascade', () {
      const data = <String, dynamic>{
        'focalPointX': 0.25,
        'responsive': {
          'version': 2,
          'tablet': {'focalPointX': 0.4},
        },
      };

      final tablet = WebsiteResponsiveDataCodec.resolve<double>(
        data: data,
        propertyKey: 'focalPointX',
        viewport: WebsiteViewport.tablet,
        decode: _double,
      );
      final mobile = WebsiteResponsiveDataCodec.resolve<double>(
        data: data,
        propertyKey: 'focalPointX',
        viewport: WebsiteViewport.mobile,
        decode: _double,
      );

      expect(tablet.value, 0.4);
      expect(tablet.isOverride, isTrue);
      expect(mobile.value, 0.25);
      expect(mobile.isInherited, isTrue);
      expect(mobile.isOverride, isFalse);
    });

    test('desktop viewport writes the base and never creates an override', () {
      final next = WebsiteResponsiveDataCodec.setForViewport(
        data: const {'focalPointX': 0.25},
        propertyKey: 'focalPointX',
        value: 0.8,
        viewport: WebsiteViewport.desktop,
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );

      expect(next['focalPointX'], 0.8);
      expect(next.containsKey('responsive'), isFalse);
    });

    test('shared-only writes ignore viewport scope', () {
      final next = WebsiteResponsiveDataCodec.setForViewport(
        data: const {'altText': 'Bicicleta'},
        propertyKey: 'altText',
        value: 'Bicicleta de montaña',
        viewport: WebsiteViewport.mobile,
        policy: WebsiteResponsivePropertyPolicy.sharedOnly,
      );

      expect(next['altText'], 'Bicicleta de montaña');
      expect(next.containsKey('responsive'), isFalse);
    });

    test('equal override normalizes away and reset restores deep equality', () {
      const original = <String, dynamic>{
        'focalPointX': 0.5,
        'metadata': {
          'nested': [1, 2, 3],
        },
      };

      final customized = WebsiteResponsiveDataCodec.setForViewport(
        data: original,
        propertyKey: 'focalPointX',
        value: 0.75,
        viewport: WebsiteViewport.mobile,
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(
        WebsiteResponsiveDataCodec.hasOverride(
          customized,
          'focalPointX',
          WebsiteViewport.mobile,
        ),
        isTrue,
      );

      final reset = WebsiteResponsiveDataCodec.clearOverride(
        data: customized,
        propertyKey: 'focalPointX',
        viewport: WebsiteViewport.mobile,
        policies: policies,
      );
      expect(websiteResponsiveDeepEquals(reset, original), isTrue);

      final redundant = WebsiteResponsiveDataCodec.setForViewport(
        data: original,
        propertyKey: 'focalPointX',
        value: 0.5,
        viewport: WebsiteViewport.mobile,
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(websiteResponsiveDeepEquals(redundant, original), isTrue);
    });

    test('changing shared removes overrides that became redundant', () {
      const data = <String, dynamic>{
        'focalPointX': 0.5,
        'responsive': {
          'version': 2,
          'mobile': {'focalPointX': 0.75},
          'tablet': {'focalPointX': 0.6},
        },
      };

      final next = WebsiteResponsiveDataCodec.setShared(
        data: data,
        propertyKey: 'focalPointX',
        value: 0.75,
        policies: policies,
      );
      final responsive = next['responsive'] as Map;
      expect(responsive.containsKey('mobile'), isFalse);
      expect((responsive['tablet'] as Map)['focalPointX'], 0.6);
    });

    test('normalization removes empty, desktop, unknown and transient owners',
        () {
      final next = WebsiteResponsiveDataCodec.normalize(
        const <String, dynamic>{
          'focalPointX': 0.5,
          'altText': 'Bicicleta',
          'responsive': {
            'version': 99,
            'desktop': {'focalPointX': 0.2},
            'tablet': <String, dynamic>{},
            'mobile': {
              'focalPointX': 0.8,
              'altText': 'Duplicado',
              'activeElementId': 'transient',
              'headline': 'Copy no autorizado',
            },
            'unknown': {'x': 1},
          },
        },
        policies: policies,
        transientPropertyKeys: const {'activeElementId'},
      );

      expect(next['responsive'], {
        'version': 2,
        'mobile': {'focalPointX': 0.8},
      });
    });

    test('display copy fails closed until its field is explicitly allowed', () {
      expect(
        () => WebsiteResponsiveDataCodec.setForViewport(
          data: const {'headline': 'Común'},
          propertyKey: 'headline',
          value: 'Móvil',
          viewport: WebsiteViewport.mobile,
          policy: WebsiteResponsivePropertyPolicy.responsiveDisplayCopy,
        ),
        throwsStateError,
      );

      final approved = WebsiteResponsiveDataCodec.setForViewport(
        data: const {'headline': 'Común'},
        propertyKey: 'headline',
        value: 'Móvil',
        viewport: WebsiteViewport.mobile,
        policy: WebsiteResponsivePropertyPolicy.responsiveDisplayCopy,
        displayCopyWhitelist: const {'headline'},
      );
      expect(
        ((approved['responsive'] as Map)['mobile'] as Map)['headline'],
        'Móvil',
      );
    });

    test('codec deep-copies nested responsive values', () {
      final mutable = <String, dynamic>{
        'rows': [
          {'x': 1},
        ],
      };
      final next = WebsiteResponsiveDataCodec.setForViewport(
        data: const {'layout': <String, dynamic>{}},
        propertyKey: 'layout',
        value: mutable,
        viewport: WebsiteViewport.mobile,
        policy: WebsiteResponsivePropertyPolicy.perViewportGeometry,
      );

      ((mutable['rows'] as List).single as Map)['x'] = 99;
      final stored =
          ((next['responsive'] as Map)['mobile'] as Map)['layout'] as Map;
      expect(((stored['rows'] as List).single as Map)['x'], 1);
    });

    test('canonical override wins over legacy alias and legacy never cascades',
        () {
      const data = <String, dynamic>{
        'focalPointX': 0.3,
        'mobileFocalPointX': 0.7,
        'responsive': {
          'version': 2,
          'mobile': {'focalPointX': 0.9},
        },
      };
      final reader = WebsiteLegacyResponsiveAdapters.mobileAlias<double>(
        'mobileFocalPointX',
        _double,
      );

      final mobile = WebsiteResponsiveDataCodec.resolve<double>(
        data: data,
        propertyKey: 'focalPointX',
        viewport: WebsiteViewport.mobile,
        decode: _double,
        readLegacyOverride: reader,
      );
      final tablet = WebsiteResponsiveDataCodec.resolve<double>(
        data: data,
        propertyKey: 'focalPointX',
        viewport: WebsiteViewport.tablet,
        decode: _double,
        readLegacyOverride: reader,
      );

      expect(mobile.value, 0.9);
      expect(mobile.isLegacyOverride, isFalse);
      expect(tablet.value, 0.3);
      expect(tablet.isInherited, isTrue);
    });
  });
}

double? _double(Object? value) => (value as num?)?.toDouble();
