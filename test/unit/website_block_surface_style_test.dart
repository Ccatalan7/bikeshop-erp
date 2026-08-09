import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_block_surface_style.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';

void main() {
  group('WebsiteBlockSurfaceStyle storage bridge', () {
    test('map style remains the shared base for old-client round trips', () {
      final data = <String, dynamic>{
        'style': <String, dynamic>{
          'paddingTop': 40,
          'backgroundColor': '#112233',
        },
      };

      final desktop = WebsiteBlockSurfaceStyle.resolve(
        data: data,
        viewport: WebsiteViewport.desktop,
      );

      expect(desktop.baseMapKey, WebsiteBlockSurfaceFields.legacyMapKey);
      expect(desktop.paddingTop.value, 40);
      expect(desktop.backgroundColor, const Color(0xFF112233));
      expect(data.containsKey('surfacePaddingTop'), isFalse);
    });

    test('Button scalar style is never interpreted or replaced as a surface',
        () {
      final data = <String, dynamic>{
        'style': 'filled',
        'surfaceStyle': <String, dynamic>{
          'paddingTop': 18,
          'borderWidth': 2,
        },
      };

      final resolved = WebsiteBlockSurfaceStyle.resolve(
        data: data,
        viewport: WebsiteViewport.desktop,
      );

      expect(resolved.baseMapKey, WebsiteBlockSurfaceFields.scalarSafeMapKey);
      expect(resolved.paddingTop.value, 18);
      expect(resolved.borderWidth, 2);
      expect(data['style'], 'filled');
    });

    test('atomic shared map preserves unknown values and its source', () {
      final nested = <String, dynamic>{'owner': 'legacy'};
      final data = <String, dynamic>{
        'style': <String, dynamic>{
          'paddingTop': 40,
          'unknownFutureKey': nested,
        },
      };

      final next = WebsiteBlockSurfaceFields.sharedMapWithValues(
        data: data,
        values: const <WebsiteBlockFieldSchema, Object?>{
          WebsiteBlockSurfaceFields.paddingTop: 55,
          WebsiteBlockSurfaceFields.borderColor: '#112233',
        },
      );

      expect(next['paddingTop'], 55);
      expect(next['borderColor'], '#112233');
      expect(next['unknownFutureKey'], <String, dynamic>{'owner': 'legacy'});
      expect(next['unknownFutureKey'], isNot(same(nested)));
      expect((data['style'] as Map)['paddingTop'], 40);
      expect((data['style'] as Map).containsKey('borderColor'), isFalse);
    });

    test('atomic shared map targets surfaceStyle when style is scalar', () {
      final data = <String, dynamic>{
        'style': 'filled',
        'surfaceStyle': <String, dynamic>{'paddingLeft': 12},
      };

      final next = WebsiteBlockSurfaceFields.sharedMapWithValues(
        data: data,
        values: const <WebsiteBlockFieldSchema, Object?>{
          WebsiteBlockSurfaceFields.paddingLeft: 24,
        },
      );

      expect(WebsiteBlockSurfaceFields.baseMapKey(data), 'surfaceStyle');
      expect(next, <String, dynamic>{'paddingLeft': 24});
      expect(data['style'], 'filled');
    });

    test(
        'namespaced override wins and reset inherits the latest old-client base',
        () {
      var data = <String, dynamic>{
        'style': <String, dynamic>{'paddingTop': 40},
        'responsive': <String, dynamic>{
          'version': 2,
          'mobile': <String, dynamic>{'surfacePaddingTop': 12},
        },
      };

      WebsiteBlockSurfaceStyle resolve() => WebsiteBlockSurfaceStyle.resolve(
            data: data,
            viewport: WebsiteViewport.mobile,
          );

      expect(resolve().paddingTop.value, 12);
      expect(resolve().paddingTop.shared, 40);
      expect(resolve().paddingTop.isOverride, isTrue);

      // Simulate an older client editing the compatible shared map.
      data = <String, dynamic>{
        ...data,
        'style': <String, dynamic>{'paddingTop': 64},
      };
      expect(resolve().paddingTop.value, 12);
      expect(resolve().paddingTop.shared, 64);

      // The new client resets only the namespaced override. The newer base is
      // immediately inherited; no migration or alias mirror is required.
      data = WebsiteResponsiveDataCodec.clearOverride(
        data: data,
        propertyKey: WebsiteBlockSurfaceFields.paddingTop.key,
        viewport: WebsiteViewport.mobile,
        policies: <String, WebsiteResponsivePropertyPolicy>{
          WebsiteBlockSurfaceFields.paddingTop.key:
              WebsiteResponsivePropertyPolicy.responsiveOptional,
        },
      );
      expect(resolve().paddingTop.value, 64);
      expect(resolve().paddingTop.isOverride, isFalse);
    });

    test('shared-only decoration ignores a rogue responsive branch', () {
      final data = <String, dynamic>{
        'style': <String, dynamic>{'backgroundColor': '#112233'},
        'responsive': <String, dynamic>{
          'version': 2,
          'mobile': <String, dynamic>{
            'surfaceBackgroundColor': '#FFFFFF',
          },
        },
      };

      final mobile = WebsiteBlockSurfaceStyle.resolve(
        data: data,
        viewport: WebsiteViewport.mobile,
      );

      expect(mobile.backgroundColor, const Color(0xFF112233));
    });

    test('legacy dashed and dotted borders render solid without rewriting data',
        () {
      for (final legacy in <String>['dashed', 'dotted']) {
        final data = <String, dynamic>{
          'style': <String, dynamic>{
            'borderWidth': 2,
            'borderStyle': legacy,
          },
        };
        final resolved = WebsiteBlockSurfaceStyle.resolve(
          data: data,
          viewport: WebsiteViewport.desktop,
        );

        expect(resolved.borderStyle, 'solid');
        expect(resolved.decoration().border!.top.style, BorderStyle.solid);
        expect((data['style'] as Map)['borderStyle'], legacy);
      }
    });

    test('explicit none suppresses a positive-width border', () {
      final resolved = WebsiteBlockSurfaceStyle.resolve(
        data: const <String, dynamic>{
          'style': <String, dynamic>{
            'borderWidth': 2,
            'borderStyle': 'none',
          },
        },
        viewport: WebsiteViewport.desktop,
      );

      expect(resolved.borderStyle, 'none');
      expect(resolved.paintsBorder, isFalse);
      expect(resolved.decoration().border, isNull);
    });

    test('t19 publishes closed surface scales and exact F-05 depths', () {
      expect(
        WebsiteBlockSurfaceFields.verticalPaddingChoices,
        <double>[0, 32, 48, 64],
      );
      expect(
        WebsiteBlockSurfaceFields.horizontalPaddingChoices,
        <double>[0, 16, 24, 32],
      );
      expect(WebsiteBlockSurfaceFields.borderWidthChoices, <double>[0, 1]);
      expect(
        WebsiteBlockSurfaceFields.borderRadiusChoices,
        <double>[0, 4, 10, 14],
      );

      for (final preset in <String>['raised', 'popover', 'overlay']) {
        final values = WebsiteBlockSurfaceFields.depthChoices[preset]!;
        final resolved = WebsiteBlockSurfaceStyle.resolve(
          data: <String, dynamic>{
            'style': Map<String, Object?>.from(values),
          },
          viewport: WebsiteViewport.desktop,
        );
        expect(resolved.depthPreset, preset);
      }
    });

    test('transparent surface paints neither a fallback color nor gradient',
        () {
      final resolved = WebsiteBlockSurfaceStyle.resolve(
        data: const <String, dynamic>{
          'style': <String, dynamic>{
            'backgroundType': 'transparent',
            'backgroundColor': '#FF112233',
            'gradientColor1': '#FF445566',
            'gradientColor2': '#FF778899',
          },
        },
        viewport: WebsiteViewport.desktop,
      );

      expect(resolved.backgroundType, 'transparent');
      expect(resolved.decoration().color, isNull);
      expect(resolved.decoration().gradient, isNull);
    });

    test('partial responsive padding uses the block fallback for other sides',
        () {
      final data = <String, dynamic>{
        'style': <String, dynamic>{'paddingTop': 40},
        'responsive': <String, dynamic>{
          'version': 2,
          'tablet': <String, dynamic>{'surfacePaddingRight': 10},
          'mobile': <String, dynamic>{'surfacePaddingTop': 8},
        },
      };
      const fallback = EdgeInsets.fromLTRB(24, 64, 24, 64);

      final phone = WebsiteBlockSurfaceStyle.forLogicalWidth(
        data: data,
        logicalWidth: 390,
      );
      final tablet = WebsiteBlockSurfaceStyle.forLogicalWidth(
        data: data,
        logicalWidth: 834,
      );
      final desktop = WebsiteBlockSurfaceStyle.forLogicalWidth(
        data: data,
        logicalWidth: 1440,
      );

      expect(phone.viewport, WebsiteViewport.mobile);
      expect(phone.paddingWithFallback(fallback),
          const EdgeInsets.fromLTRB(24, 8, 24, 64));
      expect(tablet.viewport, WebsiteViewport.tablet);
      expect(tablet.paddingWithFallback(fallback),
          const EdgeInsets.fromLTRB(24, 40, 10, 64));
      expect(desktop.viewport, WebsiteViewport.desktop);
      expect(desktop.paddingWithFallback(fallback),
          const EdgeInsets.fromLTRB(24, 40, 24, 64));
    });

    test('authored padding attribution is independent for every side', () {
      final data = <String, dynamic>{
        'style': <String, dynamic>{'paddingTop': 40},
        'responsive': <String, dynamic>{
          'version': 2,
          'mobile': <String, dynamic>{'surfacePaddingRight': 10},
        },
      };

      final mobile = WebsiteBlockSurfaceStyle.resolve(
        data: data,
        viewport: WebsiteViewport.mobile,
      );
      final desktop = WebsiteBlockSurfaceStyle.resolve(
        data: data,
        viewport: WebsiteViewport.desktop,
      );

      expect(
        mobile.isPaddingAuthored(WebsiteBlockSurfaceFields.paddingTop),
        isTrue,
      );
      expect(
        mobile.isPaddingAuthored(WebsiteBlockSurfaceFields.paddingRight),
        isTrue,
      );
      expect(
        mobile.isPaddingAuthored(WebsiteBlockSurfaceFields.paddingBottom),
        isFalse,
      );
      expect(
        mobile.isPaddingAuthored(WebsiteBlockSurfaceFields.paddingLeft),
        isFalse,
      );
      expect(
        desktop.isPaddingAuthored(WebsiteBlockSurfaceFields.paddingRight),
        isFalse,
        reason: 'a mobile override must not erase desktop content insets',
      );

      final invalid = WebsiteBlockSurfaceStyle.resolve(
        data: const <String, dynamic>{
          'style': <String, dynamic>{'paddingLeft': 'not-a-number'},
          'responsive': <String, dynamic>{
            'version': 2,
            'mobile': <String, dynamic>{'surfacePaddingBottom': null},
          },
        },
        viewport: WebsiteViewport.mobile,
      );
      expect(
        invalid.isPaddingAuthored(WebsiteBlockSurfaceFields.paddingLeft),
        isFalse,
      );
      expect(
        invalid.isPaddingAuthored(WebsiteBlockSurfaceFields.paddingBottom),
        isFalse,
        reason: 'invalid persisted values fail closed to the content default',
      );
    });
  });
}
