import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_field_state.dart';

void main() {
  group('WebsiteResponsiveFieldState', () {
    test('desktop is common and never offers a viewport override', () {
      final state = WebsiteResponsiveFieldState<double>.resolve(
        schema: _responsiveField,
        context: const WebsiteAuthoringContext(
          hostClass: WebsiteAuthoringHostClass.desktop,
          previewViewport: WebsiteViewport.desktop,
          writeScope: WebsiteWriteScope.viewport,
        ),
        resolved: const WebsiteResolvedResponsiveValue<double>(
          shared: 0.5,
          value: 0.5,
          viewport: WebsiteViewport.desktop,
          isOverride: false,
          isLegacyOverride: false,
        ),
      );

      expect(state.status, WebsiteResponsiveFieldStatus.common);
      expect(state.statusLabel, 'Común');
      expect(state.effectiveWriteScope, WebsiteWriteScope.shared);
      expect(state.canCustomize, isFalse);
      expect(state.canReset, isFalse);
    });

    test('mobile inheritance, override and reset are unambiguous', () {
      const context = WebsiteAuthoringContext(
        hostClass: WebsiteAuthoringHostClass.phone,
        previewViewport: WebsiteViewport.mobile,
        writeScope: WebsiteWriteScope.viewport,
      );
      final inherited = WebsiteResponsiveFieldState<double>.resolve(
        schema: _responsiveField,
        context: context,
        resolved: const WebsiteResolvedResponsiveValue<double>(
          shared: 0.5,
          value: 0.5,
          viewport: WebsiteViewport.mobile,
          isOverride: false,
          isLegacyOverride: false,
        ),
      );
      final overridden = WebsiteResponsiveFieldState<double>.resolve(
        schema: _responsiveField,
        context: context,
        resolved: const WebsiteResolvedResponsiveValue<double>(
          shared: 0.5,
          value: 0.8,
          viewport: WebsiteViewport.mobile,
          isOverride: true,
          isLegacyOverride: false,
        ),
      );

      expect(inherited.status, WebsiteResponsiveFieldStatus.inherited);
      expect(inherited.canCustomize, isTrue);
      expect(inherited.canReset, isFalse);
      expect(overridden.statusLabel, 'Personalizado para Móvil');
      expect(overridden.canCustomize, isFalse);
      expect(overridden.canReset, isTrue);
    });

    test('legacy and unavailable states expose a reason without color', () {
      const context = WebsiteAuthoringContext(
        hostClass: WebsiteAuthoringHostClass.desktop,
        previewViewport: WebsiteViewport.mobile,
        writeScope: WebsiteWriteScope.viewport,
      );
      final legacy = WebsiteResponsiveFieldState<double>.resolve(
        schema: _responsiveField,
        context: context,
        resolved: const WebsiteResolvedResponsiveValue<double>(
          shared: 0.5,
          value: 0.7,
          viewport: WebsiteViewport.mobile,
          isOverride: true,
          isLegacyOverride: true,
        ),
      );
      final unavailable = WebsiteResponsiveFieldState<double>.resolve(
        schema: _responsiveField,
        context: context,
        resolved: const WebsiteResolvedResponsiveValue<double>(
          shared: 0.5,
          value: 0.5,
          viewport: WebsiteViewport.mobile,
          isOverride: false,
          isLegacyOverride: false,
        ),
        unavailableReason: 'Requiere revisar el documento Canvas.',
      );

      expect(legacy.statusLabel, 'Configuración móvil anterior');
      expect(legacy.canCustomize, isFalse);
      expect(unavailable.status, WebsiteResponsiveFieldStatus.unavailable);
      expect(
        unavailable.semanticSummary,
        contains('Requiere revisar el documento Canvas.'),
      );
    });

    test('shared-only fields remain common on a phone host', () {
      final state = WebsiteResponsiveFieldState<String>.resolve(
        schema: _sharedField,
        context: const WebsiteAuthoringContext(
          hostClass: WebsiteAuthoringHostClass.phone,
          previewViewport: WebsiteViewport.mobile,
          writeScope: WebsiteWriteScope.viewport,
        ),
        resolved: const WebsiteResolvedResponsiveValue<String>(
          shared: '/productos',
          value: '/productos',
          viewport: WebsiteViewport.mobile,
          isOverride: false,
          isLegacyOverride: false,
        ),
      );

      expect(state.status, WebsiteResponsiveFieldStatus.sharedOnly);
      expect(state.statusLabel, 'Siempre común');
      expect(state.effectiveWriteScope, WebsiteWriteScope.shared);
      expect(state.canCustomize, isFalse);
    });
  });
}

const _responsiveField = WebsiteBlockFieldSchema(
  key: 'focalPointX',
  label: 'Encuadre',
  type: WebsiteBlockFieldType.number,
  responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
  propertyFamily: WebsiteResponsivePropertyFamily.media,
);

const _sharedField = WebsiteBlockFieldSchema(
  key: 'ctaLink',
  label: 'Destino',
  type: WebsiteBlockFieldType.link,
);
