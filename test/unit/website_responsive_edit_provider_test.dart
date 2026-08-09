import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_block_public_visibility.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_field_state.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_save_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebsiteEditModeProvider responsive authoring', () {
    test('preview viewport and write scope are explicit independent state', () {
      final provider = _provider();
      addTearDown(provider.dispose);

      expect(provider.previewViewport, WebsiteViewport.desktop);
      expect(provider.writeScope, WebsiteWriteScope.shared);
      expect(provider.hasPageDraftChanges, isFalse);

      provider.setDevicePreviewMode(DevicePreviewMode.mobile);
      provider.setWriteScope(WebsiteWriteScope.viewport);

      expect(provider.previewViewport, WebsiteViewport.mobile);
      expect(provider.writeScope, WebsiteWriteScope.viewport);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(provider.canUndo, isFalse);

      provider.setDevicePreviewMode(DevicePreviewMode.desktop);
      expect(provider.previewViewport, WebsiteViewport.desktop);
      expect(provider.writeScope, WebsiteWriteScope.shared);
      expect(provider.hasPageDraftChanges, isFalse);
    });

    test('set and clear flow through history and return to a clean baseline',
        () {
      final provider = _provider()
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..setWriteScope(WebsiteWriteScope.viewport);
      addTearDown(provider.dispose);

      final changed = provider.setBlockResponsiveProperty(
        'hero-1',
        'focalPointX',
        0.75,
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );

      expect(changed, isTrue);
      expect(provider.hasPageDraftChanges, isTrue);
      expect(provider.canUndo, isTrue);
      expect(
        provider
            .resolveBlockProperty<double>(
              'hero-1',
              'focalPointX',
              decode: _double,
            )
            .value,
        0.75,
      );
      expect(
        provider
            .resolveBlockProperty<double>(
              'hero-1',
              'focalPointX',
              viewport: WebsiteViewport.tablet,
              decode: _double,
            )
            .value,
        0.5,
        reason: 'Mobile never cascades into tablet.',
      );

      final cleared = provider.clearBlockResponsiveOverride(
        'hero-1',
        'focalPointX',
        policies: const {
          'focalPointX': WebsiteResponsivePropertyPolicy.responsiveOptional,
        },
      );

      expect(cleared, isTrue);
      expect(provider.getBlockData('hero-1'), _baseHeroData);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(provider.hasUnsavedChanges, isFalse);

      provider.undo();
      expect(provider.hasPageDraftChanges, isTrue);
      expect(
        provider.hasBlockResponsiveOverride('hero-1', 'focalPointX'),
        isTrue,
      );

      provider.redo();
      expect(provider.getBlockData('hero-1'), _baseHeroData);
      expect(provider.hasPageDraftChanges, isFalse);
    });

    test('redundant override is a no-op with no history or dirty state', () {
      final provider = _provider()
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..setWriteScope(WebsiteWriteScope.viewport);
      addTearDown(provider.dispose);

      final changed = provider.setBlockResponsiveProperty(
        'hero-1',
        'focalPointX',
        0.5,
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );

      expect(changed, isFalse);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(provider.canUndo, isFalse);
      expect(provider.getBlockData('hero-1'), _baseHeroData);
    });

    test('reset removes a legacy mobile alias in the same history entry', () {
      final provider = _providerWithData({
        ..._baseHeroData,
        'imageUrl': 'shared.jpg',
        'mobileImageUrl': 'legacy-mobile.jpg',
      })
        ..setDevicePreviewMode(DevicePreviewMode.mobile);
      addTearDown(provider.dispose);

      expect(
        provider
            .resolveBlockProperty<String>(
              'hero-1',
              'imageUrl',
              decode: _string,
              readLegacyOverride:
                  WebsiteLegacyResponsiveAdapters.mobileAlias<String>(
                'mobileImageUrl',
                _string,
              ),
            )
            .isLegacyOverride,
        isTrue,
      );

      expect(
        provider.clearBlockResponsiveOverride(
          'hero-1',
          'imageUrl',
          policies: const {
            'imageUrl': WebsiteResponsivePropertyPolicy.responsiveOptional,
          },
          legacyPropertyKeys: const ['mobileImageUrl'],
        ),
        isTrue,
      );
      expect(
        provider.getBlockData('hero-1').containsKey('mobileImageUrl'),
        isFalse,
      );
      expect(provider.canUndo, isTrue);

      provider.undo();
      expect(
        provider.getBlockData('hero-1')['mobileImageUrl'],
        'legacy-mobile.jpg',
      );
    });

    test('focal coordinates write and undo as one root transaction', () {
      final provider = _provider()
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..setWriteScope(WebsiteWriteScope.viewport);
      addTearDown(provider.dispose);

      expect(
        provider.setBlockResponsiveProperties(
          'hero-1',
          const {'focalPointX': 0.2, 'focalPointY': 0.8},
          policies: const {
            'focalPointX': WebsiteResponsivePropertyPolicy.perViewportGeometry,
            'focalPointY': WebsiteResponsivePropertyPolicy.perViewportGeometry,
          },
        ),
        isTrue,
      );
      final responsive = provider.getBlockData('hero-1')['responsive'] as Map;
      expect(responsive['mobile'], {'focalPointX': 0.2, 'focalPointY': 0.8});

      provider.undo();
      expect(provider.getBlockData('hero-1'), _baseHeroData);
      expect(provider.canUndo, isFalse);
    });

    test('shared-only property writes base even under a mobile default', () {
      final provider = _provider()
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..setWriteScope(WebsiteWriteScope.viewport);
      addTearDown(provider.dispose);

      provider.setBlockResponsiveProperty(
        'hero-1',
        'altText',
        'Bicicleta en sendero',
        policy: WebsiteResponsivePropertyPolicy.sharedOnly,
      );

      final data = provider.getBlockData('hero-1');
      expect(data['altText'], 'Bicicleta en sendero');
      expect(data.containsKey('responsive'), isFalse);
      expect(provider.hasPageDraftChanges, isTrue);
    });

    test(
        'each field owns its write scope independently from the global default',
        () {
      final provider = _provider()
        ..setDevicePreviewMode(DevicePreviewMode.mobile);
      addTearDown(provider.dispose);

      expect(provider.writeScope, WebsiteWriteScope.shared);
      provider.setFieldWriteScope(
        blockId: 'hero-1',
        propertyKey: 'focalPointX',
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
        scope: WebsiteWriteScope.viewport,
      );

      expect(
        provider.fieldWriteScope(
          blockId: 'hero-1',
          propertyKey: 'focalPointX',
          policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
        ),
        WebsiteWriteScope.viewport,
      );
      expect(
        provider.fieldWriteScope(
          blockId: 'hero-1',
          propertyKey: 'altText',
          policy: WebsiteResponsivePropertyPolicy.sharedOnly,
        ),
        WebsiteWriteScope.shared,
      );
      expect(provider.hasPageDraftChanges, isFalse);
      expect(provider.canUndo, isFalse);

      provider.setBlockResponsiveProperty(
        'hero-1',
        'focalPointX',
        0.82,
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      expect(
        provider
            .resolveBlockProperty<double>(
              'hero-1',
              'focalPointX',
              decode: _double,
            )
            .value,
        0.82,
      );
      expect(
        (provider.getBlockData('hero-1')['responsive'] as Map)['mobile'],
        {'focalPointX': 0.82},
      );
    });

    test('field state uses per-field scope and reset returns to shared', () {
      const focalSchema = WebsiteBlockFieldSchema(
        key: 'focalPointX',
        label: 'Foco',
        type: WebsiteBlockFieldType.number,
        responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      final provider = _provider()
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..setFieldWriteScope(
          blockId: 'hero-1',
          propertyKey: 'focalPointX',
          policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          scope: WebsiteWriteScope.viewport,
        );
      addTearDown(provider.dispose);

      var state = provider.responsiveFieldState<double>(
        blockId: 'hero-1',
        schema: focalSchema,
        decode: _double,
      );
      expect(state.status, WebsiteResponsiveFieldStatus.inherited);
      expect(state.effectiveWriteScope, WebsiteWriteScope.viewport);
      expect(state.canCustomize, isTrue);

      provider.setBlockResponsiveProperty(
        'hero-1',
        'focalPointX',
        0.7,
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      state = provider.responsiveFieldState<double>(
        blockId: 'hero-1',
        schema: focalSchema,
        decode: _double,
      );
      expect(state.status, WebsiteResponsiveFieldStatus.overridden);
      expect(state.canReset, isTrue);

      provider.clearBlockResponsiveOverride(
        'hero-1',
        'focalPointX',
        policies: const {
          'focalPointX': WebsiteResponsivePropertyPolicy.responsiveOptional,
        },
      );
      state = provider.responsiveFieldState<double>(
        blockId: 'hero-1',
        schema: focalSchema,
        decode: _double,
      );
      expect(state.status, WebsiteResponsiveFieldStatus.inherited);
      expect(state.effectiveWriteScope, WebsiteWriteScope.shared);
      expect(provider.hasPageDraftChanges, isFalse);
    });

    test('desktop and shared-only fields cannot retain a viewport scope', () {
      final provider = _provider();
      addTearDown(provider.dispose);

      provider.setFieldWriteScope(
        blockId: 'hero-1',
        propertyKey: 'focalPointX',
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
        scope: WebsiteWriteScope.viewport,
      );
      provider.setFieldWriteScope(
        blockId: 'hero-1',
        propertyKey: 'altText',
        policy: WebsiteResponsivePropertyPolicy.sharedOnly,
        scope: WebsiteWriteScope.viewport,
      );

      expect(
        provider.fieldWriteScope(
          blockId: 'hero-1',
          propertyKey: 'focalPointX',
          policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
        ),
        WebsiteWriteScope.shared,
      );
      expect(
        provider.fieldWriteScope(
          blockId: 'hero-1',
          propertyKey: 'altText',
          policy: WebsiteResponsivePropertyPolicy.sharedOnly,
        ),
        WebsiteWriteScope.shared,
      );
      expect(provider.hasPageDraftChanges, isFalse);
    });

    test('carousel slide override is isolated, undoable and resets to its base',
        () {
      final provider = _carouselProvider()
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..setRepeaterFieldWriteScope(
          blockId: 'carousel-1',
          collectionKeys: const ['slides'],
          itemIndex: 0,
          propertyKey: 'imageUrl',
          policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          scope: WebsiteWriteScope.viewport,
        );
      addTearDown(provider.dispose);

      final changed = provider.setBlockRepeaterItemResponsiveProperty(
        'carousel-1',
        collectionKeys: const ['slides'],
        itemIndex: 0,
        propertyKey: 'imageUrl',
        value: 'mobile-a.jpg',
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );

      expect(changed, isTrue);
      expect(provider.hasPageDraftChanges, isTrue);
      expect(provider.canUndo, isTrue);
      expect(
        provider
            .resolveBlockRepeaterItemProperty<String>(
              'carousel-1',
              collectionKeys: const ['slides'],
              itemIndex: 0,
              propertyKey: 'imageUrl',
              decode: _string,
            )
            .value,
        'mobile-a.jpg',
      );
      expect(
        provider
            .resolveBlockRepeaterItemProperty<String>(
              'carousel-1',
              collectionKeys: const ['slides'],
              itemIndex: 1,
              propertyKey: 'imageUrl',
              decode: _string,
            )
            .value,
        'shared-b.jpg',
        reason: 'A slide override cannot leak to a neighbouring slide.',
      );
      expect(
        provider
            .resolveBlockRepeaterItemProperty<String>(
              'carousel-1',
              collectionKeys: const ['slides'],
              itemIndex: 0,
              propertyKey: 'imageUrl',
              viewport: WebsiteViewport.tablet,
              decode: _string,
            )
            .value,
        'shared-a.jpg',
        reason: 'Mobile never cascades into tablet inside a repeater.',
      );

      final slides = provider.getBlockData('carousel-1')['slides'] as List;
      expect((slides[0] as Map)['responsive'], {
        'version': 2,
        'mobile': {'imageUrl': 'mobile-a.jpg'},
      });
      expect((slides[1] as Map).containsKey('responsive'), isFalse);

      expect(
        provider.clearBlockRepeaterItemResponsiveOverride(
          'carousel-1',
          collectionKeys: const ['slides'],
          itemIndex: 0,
          propertyKey: 'imageUrl',
          policies: const {
            'imageUrl': WebsiteResponsivePropertyPolicy.responsiveOptional,
          },
        ),
        isTrue,
      );
      expect(provider.getBlockData('carousel-1'), _baseCarouselData);
      expect(provider.hasPageDraftChanges, isFalse);

      provider.undo();
      expect(
        provider
            .resolveBlockRepeaterItemProperty<String>(
              'carousel-1',
              collectionKeys: const ['slides'],
              itemIndex: 0,
              propertyKey: 'imageUrl',
              decode: _string,
            )
            .value,
        'mobile-a.jpg',
      );
      provider.redo();
      expect(provider.getBlockData('carousel-1'), _baseCarouselData);
    });

    test('each carousel slide owns an independent transient write scope', () {
      const imageSchema = WebsiteBlockFieldSchema(
        key: 'imageUrl',
        label: 'Imagen',
        type: WebsiteBlockFieldType.image,
        responsivePolicy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      final provider = _carouselProvider()
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..setRepeaterFieldWriteScope(
          blockId: 'carousel-1',
          collectionKeys: const ['slides'],
          itemIndex: 1,
          propertyKey: 'imageUrl',
          policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
          scope: WebsiteWriteScope.viewport,
        );
      addTearDown(provider.dispose);

      final first = provider.responsiveRepeaterFieldState<String>(
        blockId: 'carousel-1',
        collectionKeys: const ['slides'],
        itemIndex: 0,
        schema: imageSchema,
        decode: _string,
      );
      final second = provider.responsiveRepeaterFieldState<String>(
        blockId: 'carousel-1',
        collectionKeys: const ['slides'],
        itemIndex: 1,
        schema: imageSchema,
        decode: _string,
      );

      expect(first.effectiveWriteScope, WebsiteWriteScope.shared);
      expect(second.effectiveWriteScope, WebsiteWriteScope.viewport);
      expect(first.resolved.value, 'shared-a.jpg');
      expect(second.resolved.value, 'shared-b.jpg');
      expect(provider.hasPageDraftChanges, isFalse);
    });

    test('carousel reset removes only the selected slide legacy alias', () {
      final provider = _carouselProviderWithLegacyMobileImage()
        ..setDevicePreviewMode(DevicePreviewMode.mobile);
      addTearDown(provider.dispose);

      expect(
        provider.clearBlockRepeaterItemResponsiveOverride(
          'carousel-1',
          collectionKeys: const ['slides'],
          itemIndex: 0,
          propertyKey: 'imageUrl',
          policies: const {
            'imageUrl': WebsiteResponsivePropertyPolicy.responsiveOptional,
          },
          legacyPropertyKeys: const ['mobileImageUrl'],
        ),
        isTrue,
      );

      final slides = provider.getBlockData('carousel-1')['slides'] as List;
      expect((slides[0] as Map).containsKey('mobileImageUrl'), isFalse);
      expect((slides[1] as Map)['mobileImageUrl'], 'legacy-b.jpg');
    });

    test('focal coordinates write and clear as one repeater transaction', () {
      final provider = _carouselProvider()
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..setWriteScope(WebsiteWriteScope.viewport);
      addTearDown(provider.dispose);
      const policies = {
        'focalPointX': WebsiteResponsivePropertyPolicy.perViewportGeometry,
        'focalPointY': WebsiteResponsivePropertyPolicy.perViewportGeometry,
      };

      expect(
        provider.setBlockRepeaterItemResponsiveProperties(
          'carousel-1',
          collectionKeys: const ['slides'],
          itemIndex: 1,
          values: const {'focalPointX': 0.3, 'focalPointY': 0.7},
          policies: policies,
        ),
        isTrue,
      );
      var slides = provider.getBlockData('carousel-1')['slides'] as List;
      expect((slides[1] as Map)['responsive'], {
        'version': 2,
        'mobile': {'focalPointX': 0.3, 'focalPointY': 0.7},
      });

      expect(
        provider.clearBlockRepeaterItemResponsiveOverrides(
          'carousel-1',
          collectionKeys: const ['slides'],
          itemIndex: 1,
          propertyKeys: const ['focalPointX', 'focalPointY'],
          policies: policies,
        ),
        isTrue,
      );
      slides = provider.getBlockData('carousel-1')['slides'] as List;
      expect((slides[1] as Map).containsKey('responsive'), isFalse);

      provider.undo();
      slides = provider.getBlockData('carousel-1')['slides'] as List;
      expect((slides[1] as Map)['responsive'], {
        'version': 2,
        'mobile': {'focalPointX': 0.3, 'focalPointY': 0.7},
      });
    });

    test('stable repeater identity wins over a stale carousel index', () {
      final provider = _carouselProvider()
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..setWriteScope(WebsiteWriteScope.viewport);
      addTearDown(provider.dispose);

      expect(
        provider.setBlockRepeaterItemResponsiveProperty(
          'carousel-1',
          collectionKeys: const ['slides'],
          itemIndex: 0,
          identityKey: 'id',
          identityValue: 'slide-b',
          propertyKey: 'imageUrl',
          value: 'mobile-b.jpg',
          policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
        ),
        isTrue,
      );

      final slides = provider.getBlockData('carousel-1')['slides'] as List;
      expect((slides[0] as Map).containsKey('responsive'), isFalse);
      expect((slides[1] as Map)['responsive'], {
        'version': 2,
        'mobile': {'imageUrl': 'mobile-b.jpg'},
      });
    });

    test('repeater shared-only metadata never creates a viewport override', () {
      final provider = _carouselProvider()
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..setWriteScope(WebsiteWriteScope.viewport);
      addTearDown(provider.dispose);

      expect(
        provider.setBlockRepeaterItemResponsiveProperty(
          'carousel-1',
          collectionKeys: const ['slides'],
          itemIndex: 0,
          propertyKey: 'altText',
          value: 'Ciclista descendiendo',
          policy: WebsiteResponsivePropertyPolicy.sharedOnly,
        ),
        isTrue,
      );

      final slide =
          (provider.getBlockData('carousel-1')['slides'] as List)[0] as Map;
      expect(slide['altText'], 'Ciclista descendiendo');
      expect(slide.containsKey('responsive'), isFalse);
    });

    test('legacy alias renders without mutating or dirtying the document', () {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const <Map<String, dynamic>>[
            {
              'id': 'hero-1',
              'block_type': 'hero',
              'block_data': {
                'focalPointX': 0.5,
                'mobileFocalPointX': 0.8,
              },
              'order_index': 0,
            },
          ],
          const <String, dynamic>{},
        )
        ..setDevicePreviewMode(DevicePreviewMode.mobile);
      addTearDown(provider.dispose);

      final value = provider.resolveBlockProperty<double>(
        'hero-1',
        'focalPointX',
        decode: _double,
        readLegacyOverride: WebsiteLegacyResponsiveAdapters.mobileAlias<double>(
          'mobileFocalPointX',
          _double,
        ),
      );

      expect(value.value, 0.8);
      expect(value.isLegacyOverride, isTrue);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(provider.canUndo, isFalse);
      expect(
          provider.getBlockData('hero-1').containsKey('responsive'), isFalse);
    });

    test('save command captures canonical responsive data unchanged', () {
      final provider = _provider()
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..setWriteScope(WebsiteWriteScope.viewport);
      addTearDown(provider.dispose);

      provider.setBlockResponsiveProperty(
        'hero-1',
        'focalPointX',
        0.75,
        policy: WebsiteResponsivePropertyPolicy.responsiveOptional,
      );
      final command = WebsiteEditorSaveCommand.capture(
        tenantId: 'tenant-a',
        document: provider,
      );

      final data = command.blocks.single['block_data'] as Map;
      expect(data['responsive'], {
        'version': 2,
        'mobile': {'focalPointX': 0.75},
      });
    });

    test(
        'durable recovery keeps the server baseline, restores context and remains undoable',
        () {
      const lease = WebsiteEditorCapabilitySnapshot(
        identity: 'user-a',
        activeTenantId: 'tenant-a',
        storefrontTenantId: 'tenant-a',
        hasAuthority: true,
        authorityEpoch: 4,
      );
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      expect(provider.adoptEditorEntryLease(0, lease), isTrue);
      provider.openEditorDocument(
        const <Map<String, dynamic>>[
          {
            'id': 'hero-1',
            'block_type': 'hero',
            'block_data': _baseHeroData,
            'order_index': 0,
          },
        ],
        const <String, dynamic>{},
        mode: WebsiteEditorMode.edit,
        pageId: 'page-a',
        pageSlug: 'inicio',
      );

      final changed = provider.restoreDurablePageDraft(
        authority: lease,
        recoveredBlocks: const [
          {
            'id': 'hero-1',
            'block_type': 'hero',
            'block_data': {
              'title': 'Recovered',
              'focalPointX': 0.5,
              'altText': 'Bicicleta',
              'responsive': {
                'version': 2,
                'mobile': {'focalPointX': 0.8},
              },
            },
            'order_index': 0,
          },
        ],
        recoveredViewport: WebsiteViewport.mobile,
        recoveredWriteScope: WebsiteWriteScope.viewport,
        recoveredSelectedBlockId: 'hero-1',
        pageId: 'page-a',
        pageSlug: 'inicio',
      );

      expect(changed, isTrue);
      expect(provider.previewViewport, WebsiteViewport.mobile);
      expect(provider.writeScope, WebsiteWriteScope.viewport);
      expect(provider.selectedBlockId, 'hero-1');
      expect(provider.hasPageDraftChanges, isTrue);
      expect(provider.canUndo, isTrue);
      expect(
          provider.pageDraftBaselineBlocks.single['block_data'], _baseHeroData);

      provider.undo();
      expect(provider.getBlockData('hero-1'), _baseHeroData);
      expect(provider.hasPageDraftChanges, isFalse);
      provider.redo();
      expect(provider.getBlockData('hero-1')['title'], 'Recovered');
      expect(provider.hasPageDraftChanges, isTrue);

      provider.discardActivePageDraft();
      expect(provider.getBlockData('hero-1'), _baseHeroData);
      expect(provider.hasPageDraftChanges, isFalse);
    });

    test('durable recovery refuses another authority, page or live draft', () {
      const lease = WebsiteEditorCapabilitySnapshot(
        identity: 'user-a',
        activeTenantId: 'tenant-a',
        storefrontTenantId: 'tenant-a',
        hasAuthority: true,
        authorityEpoch: 4,
      );
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      provider.adoptEditorEntryLease(0, lease);
      provider.openEditorDocument(
        const <Map<String, dynamic>>[
          {
            'id': 'hero-1',
            'block_type': 'hero',
            'block_data': _baseHeroData,
          },
        ],
        const {},
        mode: WebsiteEditorMode.edit,
        pageId: 'page-a',
      );

      expect(
        () => provider.restoreDurablePageDraft(
          authority: const WebsiteEditorCapabilitySnapshot(
            identity: 'user-b',
            activeTenantId: 'tenant-a',
            storefrontTenantId: 'tenant-a',
            hasAuthority: true,
            authorityEpoch: 4,
          ),
          recoveredBlocks: const [],
          recoveredViewport: WebsiteViewport.mobile,
          recoveredWriteScope: WebsiteWriteScope.viewport,
          pageId: 'page-a',
        ),
        throwsA(isA<WebsiteEditorAuthorityException>()),
      );
      expect(
        () => provider.restoreDurablePageDraft(
          authority: lease,
          recoveredBlocks: const [],
          recoveredViewport: WebsiteViewport.mobile,
          recoveredWriteScope: WebsiteWriteScope.viewport,
          pageId: 'page-b',
        ),
        throwsStateError,
      );

      provider.updateBlockData('hero-1', 'title', 'New in-memory draft');
      expect(
        () => provider.restoreDurablePageDraft(
          authority: lease,
          recoveredBlocks: const [],
          recoveredViewport: WebsiteViewport.mobile,
          recoveredWriteScope: WebsiteWriteScope.viewport,
          pageId: 'page-a',
        ),
        throwsStateError,
      );
      expect(provider.getBlockData('hero-1')['title'], 'New in-memory draft');
    });

    test('visibility migration is explicit, versioned and one history step',
        () {
      final provider = _providerWithData(<String, dynamic>{
        ..._baseHeroData,
        'visibility': <String, dynamic>{
          'desktop': true,
          'tablet': false,
          'mobile': true,
        },
        'responsive': <String, dynamic>{
          'version': 2,
          'mobile': <String, dynamic>{'focalPointX': .7},
        },
      });
      addTearDown(provider.dispose);

      final blocked = provider.updateBlockResponsiveVisibility(
        'hero-1',
        'mobile',
        false,
      );

      expect(
        blocked,
        WebsiteVisibilityUpdateOutcome.requiresMigrationConfirmation,
      );
      expect(provider.canUndo, isFalse);

      final applied = provider.updateBlockResponsiveVisibility(
        'hero-1',
        'mobile',
        false,
        confirmLegacyMigration: true,
      );

      expect(applied, WebsiteVisibilityUpdateOutcome.applied);
      expect(
        provider.getBlockData('hero-1')['visibility'],
        <String, dynamic>{
          'version': 2,
          'desktop': true,
          'tablet': false,
          'mobile': false,
        },
      );
      expect(provider.canUndo, isTrue);
      provider.undo();
      expect(
        provider.getBlockData('hero-1')['visibility'],
        <String, dynamic>{
          'desktop': true,
          'tablet': false,
          'mobile': true,
        },
      );
      expect(provider.canUndo, isFalse);
    });

    test('uniform legacy visibility can migrate without a confirmation', () {
      final provider = _providerWithData(<String, dynamic>{
        ..._baseHeroData,
        'visibility': <String, dynamic>{
          'desktop': true,
          'tablet': true,
          'mobile': true,
        },
      });
      addTearDown(provider.dispose);

      final outcome = provider.updateBlockResponsiveVisibility(
        'hero-1',
        'mobile',
        false,
      );

      expect(outcome, WebsiteVisibilityUpdateOutcome.applied);
      expect(
        provider.getBlockData('hero-1')['visibility'],
        <String, dynamic>{
          'version': 2,
          'desktop': true,
          'tablet': true,
          'mobile': false,
        },
      );
      expect(provider.canUndo, isTrue);
    });
  });

  group('la selección sobrevive a una excursión a Vista previa', () {
    test('Edit -> Preview -> Edit conserva el bloque seleccionado', () {
      final provider = _threeBlockProvider()..selectBlock('block-2');
      addTearDown(provider.dispose);

      provider.setMode(WebsiteEditorMode.preview);
      // Ni el dock ni el inspector existen en Preview: los monta su propia
      // compuerta de Edit. Por eso el valor puede quedarse, y por eso el
      // borrador durable —que captura este mismo campo en cada
      // notificación— no recibe null por pasar por Vista previa.
      expect(provider.selectedBlockId, 'block-2');

      provider.setMode(WebsiteEditorMode.edit);
      expect(provider.selectedBlockId, 'block-2');
      expect(provider.mode, WebsiteEditorMode.edit);
    });

    test('el comando de ruta (web) recorre el mismo camino', () {
      final provider = _threeBlockProvider()
        ..adoptEditorEntryLease(0, _grantedLease)
        ..selectBlock('block-3');
      addTearDown(provider.dispose);

      provider.applyRouteModeCommand(WebsiteEditorMode.preview);
      expect(provider.selectedBlockId, 'block-3');

      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      expect(provider.selectedBlockId, 'block-3');
    });

    test('una selección colgante se resuelve a null al volver a Edit', () {
      final provider = _threeBlockProvider()..selectBlock('block-2');
      addTearDown(provider.dispose);

      provider.setMode(WebsiteEditorMode.preview);
      // El documento cambió mientras el operador miraba la vista previa.
      provider.openEditorDocument(
        const <Map<String, dynamic>>[
          {'id': 'block-9', 'block_type': 'hero', 'block_data': {}},
        ],
        const <String, dynamic>{},
        mode: WebsiteEditorMode.preview,
      );
      provider.setMode(WebsiteEditorMode.edit);

      expect(provider.selectedBlockId, isNull);
    });

    test('cerrar el editor sigue limpiando la selección', () {
      final provider = _threeBlockProvider()..selectBlock('block-2');
      addTearDown(provider.dispose);

      provider.setMode(WebsiteEditorMode.preview);
      provider.closeEditor();

      expect(provider.selectedBlockId, isNull);
      expect(provider.mode, WebsiteEditorMode.public);
    });
  });

  group('reveal: una operación que mueve un bloque pide verlo', () {
    test('mover abajo y mover arriba emiten una petición cada uno', () {
      final provider = _threeBlockProvider()..selectBlock('block-1');
      addTearDown(provider.dispose);

      expect(provider.blockRevealRequest, isNull);

      provider.moveBlockDown('block-1');
      final first = provider.blockRevealRequest;
      expect(first?.blockId, 'block-1');

      provider.moveBlockUp('block-1');
      final second = provider.blockRevealRequest;
      expect(second?.blockId, 'block-1');
      // Dos operaciones son dos peticiones: la revisión es lo que el lienzo
      // compara, no el id.
      expect(second!.revision, greaterThan(first!.revision));
    });

    test('un movimiento imposible no pide nada', () {
      final provider = _threeBlockProvider();
      addTearDown(provider.dispose);

      provider.moveBlockUp('block-1');
      expect(provider.blockRevealRequest, isNull);

      provider.moveBlockDown('block-3');
      expect(provider.blockRevealRequest, isNull);
    });

    test('reorderBlocks pide por el bloque arrastrado', () {
      final provider = _threeBlockProvider();
      addTearDown(provider.dispose);

      provider.reorderBlocks(0, 3);
      expect(provider.blockRevealRequest?.blockId, 'block-1');
      expect(provider.blocks.last['id'], 'block-1');
    });

    test('seleccionar NO pide reveal', () {
      final provider = _threeBlockProvider();
      addTearDown(provider.dispose);

      provider.selectBlock('block-2');
      provider.selectBlock('block-3');

      expect(provider.blockRevealRequest, isNull);
    });

    test('deshacer y rehacer revelan el bloque seleccionado', () {
      final provider = _threeBlockProvider()..selectBlock('block-1');
      addTearDown(provider.dispose);

      provider.moveBlockDown('block-1');
      final afterMove = provider.blockRevealRequest!.revision;

      provider.undo();
      final afterUndo = provider.blockRevealRequest!;
      expect(afterUndo.blockId, 'block-1');
      expect(afterUndo.revision, greaterThan(afterMove));
      expect(provider.blocks.first['id'], 'block-1');

      provider.redo();
      final afterRedo = provider.blockRevealRequest!;
      expect(afterRedo.blockId, 'block-1');
      expect(afterRedo.revision, greaterThan(afterUndo.revision));
    });

    test('deshacer sin selección no pide nada nuevo', () {
      final provider = _threeBlockProvider();
      addTearDown(provider.dispose);

      provider.moveBlockDown('block-1');
      final afterMove = provider.blockRevealRequest!.revision;

      provider.undo();
      expect(provider.blockRevealRequest!.revision, afterMove);
    });

    test('abrir otro documento descarta una petición pendiente', () {
      final provider = _threeBlockProvider();
      addTearDown(provider.dispose);

      provider.moveBlockDown('block-1');
      expect(provider.blockRevealRequest, isNotNull);

      provider.openEditorDocument(
        const <Map<String, dynamic>>[
          {'id': 'other-1', 'block_type': 'hero', 'block_data': {}},
        ],
        const <String, dynamic>{},
        mode: WebsiteEditorMode.edit,
        pageId: 'page-b',
      );

      expect(provider.blockRevealRequest, isNull);
    });
  });
}

/// A three-block page: the smallest document where a move is observable.
WebsiteEditModeProvider _threeBlockProvider() => WebsiteEditModeProvider()
  ..enterEditMode(
    const <Map<String, dynamic>>[
      {'id': 'block-1', 'block_type': 'hero', 'block_data': {}},
      {'id': 'block-2', 'block_type': 'about', 'block_data': {}},
      {'id': 'block-3', 'block_type': 'contact', 'block_data': {}},
    ],
    const <String, dynamic>{},
    pageId: 'page-a',
  );

const _grantedLease = WebsiteEditorCapabilitySnapshot(
  identity: 'user-a',
  activeTenantId: 'tenant-a',
  storefrontTenantId: 'tenant-a',
  hasAuthority: true,
  authorityEpoch: 1,
);

const _baseHeroData = <String, dynamic>{
  'title': 'Taller',
  'focalPointX': 0.5,
  'altText': 'Bicicleta',
};

const _baseCarouselData = <String, dynamic>{
  'slides': [
    {'id': 'slide-a', 'imageUrl': 'shared-a.jpg', 'altText': 'A'},
    {'id': 'slide-b', 'imageUrl': 'shared-b.jpg', 'altText': 'B'},
  ],
};

WebsiteEditModeProvider _provider() => WebsiteEditModeProvider()
  ..enterEditMode(
    const <Map<String, dynamic>>[
      {
        'id': 'hero-1',
        'block_type': 'hero',
        'block_data': _baseHeroData,
        'order_index': 0,
      },
    ],
    const <String, dynamic>{},
  );

WebsiteEditModeProvider _providerWithData(Map<String, dynamic> data) =>
    WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[
          {
            'id': 'hero-1',
            'block_type': 'hero',
            'block_data': data,
            'order_index': 0,
          },
        ],
        const <String, dynamic>{},
      );

WebsiteEditModeProvider _carouselProvider() => WebsiteEditModeProvider()
  ..enterEditMode(
    const <Map<String, dynamic>>[
      {
        'id': 'carousel-1',
        'block_type': 'carousel',
        'block_data': _baseCarouselData,
        'order_index': 0,
      },
    ],
    const <String, dynamic>{},
  );

WebsiteEditModeProvider _carouselProviderWithLegacyMobileImage() =>
    WebsiteEditModeProvider()
      ..enterEditMode(
        const <Map<String, dynamic>>[
          {
            'id': 'carousel-1',
            'block_type': 'carousel',
            'block_data': {
              'slides': [
                {
                  'id': 'slide-a',
                  'imageUrl': 'shared-a.jpg',
                  'mobileImageUrl': 'legacy-a.jpg',
                },
                {
                  'id': 'slide-b',
                  'imageUrl': 'shared-b.jpg',
                  'mobileImageUrl': 'legacy-b.jpg',
                },
              ],
            },
            'order_index': 0,
          },
        ],
        const <String, dynamic>{},
      );

double? _double(Object? value) => (value as num?)?.toDouble();
String? _string(Object? value) => value?.toString();
