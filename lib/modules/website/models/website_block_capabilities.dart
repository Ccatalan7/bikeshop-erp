import 'website_block_geometry.dart';
import 'website_block_type.dart';

enum WebsiteBlockControlMode {
  genericSchema,
  custom,
  hybrid,
  specialElement,
  fallbackRenderer,
}

enum WebsiteBlockSaveMode {
  staged,
  mixed,
  operationalImmediate,
  noContentConfig,
}

enum WebsiteEditorCapability {
  sidePanelEditing,
  inlineEditing,
  inlineText,
  formattedText,
  textOnly,
  linkAction,
  coverMedia,
  inlineMedia,
  repeater,
  structuredList,
  productData,
  themeTokens,
  responsiveVisibility,
  responsiveFocalPoint,
  animation,
  externalSync,
  specialElement,
}

enum WebsiteEditorGap {
  missingExplicitEditableRenderer,
  nonPersistedTextFormatting,
  missingTextStyleInspector,
  blockLocalTextToolbar,
  missingCoverMediaControl,
  missingInlineMediaControl,
  missingMediaMetadata,
  shallowRepeater,
  missingActionModel,
  mixedSaveSemantics,
  incompleteThemeConsumption,
  unsupportedFontRegistry,
  missingResponsiveOverrides,
}

class WebsiteBlockCapabilityProfile {
  const WebsiteBlockCapabilityProfile({
    required this.type,
    required this.controlMode,
    required this.saveMode,
    required this.hasExplicitEditableRenderer,
    required this.capabilities,
    this.heightBehavior = WebsitePageBlockHeightBehavior.minimum,
    this.usesSharedContentRendererInEdit = false,
    this.gaps = const <WebsiteEditorGap>{},
  });

  final WebsiteBlockType type;
  final WebsiteBlockControlMode controlMode;
  final WebsiteBlockSaveMode saveMode;
  final bool hasExplicitEditableRenderer;
  final Set<WebsiteEditorCapability> capabilities;
  final WebsitePageBlockHeightBehavior heightBehavior;
  final bool usesSharedContentRendererInEdit;
  final Set<WebsiteEditorGap> gaps;

  bool get usesLegacyDedicatedRenderer => hasExplicitEditableRenderer;

  bool get needsEditableRendererWork => usesLegacyDedicatedRenderer;

  bool get hasMixedSaveSemantics => saveMode == WebsiteBlockSaveMode.mixed;

  bool supports(WebsiteEditorCapability capability) =>
      capabilities.contains(capability);

  bool hasGap(WebsiteEditorGap gap) => gaps.contains(gap);
}

class WebsiteBlockCapabilityRegistry {
  const WebsiteBlockCapabilityRegistry._();

  static const Map<WebsiteBlockType, WebsiteBlockCapabilityProfile> _profiles =
      <WebsiteBlockType, WebsiteBlockCapabilityProfile>{
    WebsiteBlockType.hero: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.hero,
      controlMode: WebsiteBlockControlMode.hybrid,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      heightBehavior: WebsitePageBlockHeightBehavior.exact,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.formattedText,
        WebsiteEditorCapability.linkAction,
        WebsiteEditorCapability.coverMedia,
        WebsiteEditorCapability.responsiveFocalPoint,
      },
      gaps: <WebsiteEditorGap>{},
    ),
    WebsiteBlockType.carousel: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.carousel,
      controlMode: WebsiteBlockControlMode.custom,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      heightBehavior: WebsitePageBlockHeightBehavior.exact,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.formattedText,
        WebsiteEditorCapability.linkAction,
        WebsiteEditorCapability.coverMedia,
        WebsiteEditorCapability.repeater,
        WebsiteEditorCapability.responsiveFocalPoint,
        WebsiteEditorCapability.animation,
      },
      gaps: <WebsiteEditorGap>{
        WebsiteEditorGap.shallowRepeater,
      },
    ),
    WebsiteBlockType.canvas: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.canvas,
      controlMode: WebsiteBlockControlMode.custom,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      heightBehavior: WebsitePageBlockHeightBehavior.exact,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.linkAction,
        WebsiteEditorCapability.coverMedia,
        WebsiteEditorCapability.inlineMedia,
        WebsiteEditorCapability.responsiveFocalPoint,
        WebsiteEditorCapability.structuredList,
        WebsiteEditorCapability.animation,
      },
      gaps: <WebsiteEditorGap>{
        WebsiteEditorGap.blockLocalTextToolbar,
        WebsiteEditorGap.nonPersistedTextFormatting,
        WebsiteEditorGap.missingTextStyleInspector,
        WebsiteEditorGap.missingResponsiveOverrides,
      },
    ),
    WebsiteBlockType.text: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.text,
      controlMode: WebsiteBlockControlMode.hybrid,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      heightBehavior: WebsitePageBlockHeightBehavior.intrinsic,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.formattedText,
      },
      gaps: <WebsiteEditorGap>{},
    ),
    WebsiteBlockType.button: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.button,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      heightBehavior: WebsitePageBlockHeightBehavior.intrinsic,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.textOnly,
        WebsiteEditorCapability.linkAction,
      },
      gaps: <WebsiteEditorGap>{},
    ),
    WebsiteBlockType.divider: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.divider,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      heightBehavior: WebsitePageBlockHeightBehavior.intrinsic,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.themeTokens,
      },
    ),
    WebsiteBlockType.products: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.products,
      controlMode: WebsiteBlockControlMode.custom,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.productData,
        WebsiteEditorCapability.linkAction,
        WebsiteEditorCapability.themeTokens,
      },
    ),
    WebsiteBlockType.services: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.services,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.repeater,
      },
      gaps: <WebsiteEditorGap>{WebsiteEditorGap.missingActionModel},
    ),
    WebsiteBlockType.about: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.about,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.formattedText,
        WebsiteEditorCapability.inlineMedia,
      },
      gaps: <WebsiteEditorGap>{},
    ),
    WebsiteBlockType.testimonials: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.testimonials,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.repeater,
      },
      gaps: <WebsiteEditorGap>{WebsiteEditorGap.shallowRepeater},
    ),
    WebsiteBlockType.features: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.features,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.repeater,
      },
      gaps: <WebsiteEditorGap>{WebsiteEditorGap.missingActionModel},
    ),
    WebsiteBlockType.cta: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.cta,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.formattedText,
        WebsiteEditorCapability.linkAction,
        WebsiteEditorCapability.coverMedia,
        WebsiteEditorCapability.responsiveFocalPoint,
      },
      gaps: <WebsiteEditorGap>{},
    ),
    WebsiteBlockType.gallery: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.gallery,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.inlineMedia,
        WebsiteEditorCapability.repeater,
      },
      gaps: <WebsiteEditorGap>{
        WebsiteEditorGap.shallowRepeater,
      },
    ),
    WebsiteBlockType.contact: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.contact,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.linkAction,
      },
      gaps: <WebsiteEditorGap>{},
    ),
    WebsiteBlockType.faq: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.faq,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.repeater,
      },
      gaps: <WebsiteEditorGap>{WebsiteEditorGap.shallowRepeater},
    ),
    WebsiteBlockType.pricing: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.pricing,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.repeater,
        WebsiteEditorCapability.linkAction,
      },
      gaps: <WebsiteEditorGap>{WebsiteEditorGap.shallowRepeater},
    ),
    WebsiteBlockType.team: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.team,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.inlineMedia,
        WebsiteEditorCapability.repeater,
      },
      gaps: <WebsiteEditorGap>{WebsiteEditorGap.shallowRepeater},
    ),
    WebsiteBlockType.stats: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.stats,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.repeater,
        WebsiteEditorCapability.animation,
      },
      gaps: <WebsiteEditorGap>{WebsiteEditorGap.missingActionModel},
    ),
    WebsiteBlockType.footer: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.footer,
      controlMode: WebsiteBlockControlMode.specialElement,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      heightBehavior: WebsitePageBlockHeightBehavior.intrinsic,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.structuredList,
        WebsiteEditorCapability.linkAction,
        WebsiteEditorCapability.specialElement,
      },
      gaps: <WebsiteEditorGap>{
        WebsiteEditorGap.shallowRepeater,
      },
    ),
    WebsiteBlockType.categoryGrid: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.categoryGrid,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.linkAction,
        WebsiteEditorCapability.coverMedia,
        WebsiteEditorCapability.repeater,
      },
      gaps: <WebsiteEditorGap>{
        WebsiteEditorGap.nonPersistedTextFormatting,
      },
    ),
    WebsiteBlockType.videoBanner: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.videoBanner,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      heightBehavior: WebsitePageBlockHeightBehavior.exact,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.linkAction,
        WebsiteEditorCapability.coverMedia,
      },
    ),
    WebsiteBlockType.partnersBanner: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.partnersBanner,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.repeater,
        WebsiteEditorCapability.coverMedia,
        WebsiteEditorCapability.responsiveFocalPoint,
      },
      gaps: <WebsiteEditorGap>{
        WebsiteEditorGap.nonPersistedTextFormatting,
      },
    ),
    WebsiteBlockType.brandLogos: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.brandLogos,
      controlMode: WebsiteBlockControlMode.genericSchema,
      saveMode: WebsiteBlockSaveMode.staged,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.inlineText,
        WebsiteEditorCapability.inlineMedia,
        WebsiteEditorCapability.linkAction,
        WebsiteEditorCapability.repeater,
      },
    ),
    WebsiteBlockType.googleReviews: WebsiteBlockCapabilityProfile(
      type: WebsiteBlockType.googleReviews,
      controlMode: WebsiteBlockControlMode.custom,
      saveMode: WebsiteBlockSaveMode.operationalImmediate,
      hasExplicitEditableRenderer: false,
      usesSharedContentRendererInEdit: true,
      capabilities: <WebsiteEditorCapability>{
        WebsiteEditorCapability.sidePanelEditing,
        WebsiteEditorCapability.externalSync,
        WebsiteEditorCapability.repeater,
      },
      gaps: <WebsiteEditorGap>{
        WebsiteEditorGap.incompleteThemeConsumption,
      },
    ),
  };

  static Iterable<WebsiteBlockCapabilityProfile> get all =>
      WebsiteBlockType.values.map(profileFor);

  static WebsiteBlockCapabilityProfile profileFor(WebsiteBlockType type) {
    final profile = _profiles[type];
    if (profile == null) {
      throw StateError('Missing website block capability profile for $type');
    }
    return profile;
  }

  static List<WebsiteBlockType> missingProfileTypes() => WebsiteBlockType.values
      .where((type) => !_profiles.containsKey(type))
      .toList();

  static List<WebsiteBlockType> typesWithoutExplicitEditableRenderer() => all
      .where((profile) => !profile.hasExplicitEditableRenderer)
      .map((profile) => profile.type)
      .toList();

  static List<WebsiteBlockType> blockTypesNeedingRendererWork() => all
      .where((profile) => profile.needsEditableRendererWork)
      .map((profile) => profile.type)
      .toList();

  static List<WebsiteBlockType> typesUsingSharedContentRendererInEdit() => all
      .where((profile) => profile.usesSharedContentRendererInEdit)
      .map((profile) => profile.type)
      .toList();

  static List<WebsiteBlockType> typesUsingLegacyDedicatedRenderer() => all
      .where((profile) => profile.usesLegacyDedicatedRenderer)
      .map((profile) => profile.type)
      .toList();

  static List<WebsiteBlockType> typesWithMixedSaveSemantics() => all
      .where((profile) => profile.hasMixedSaveSemantics)
      .map((profile) => profile.type)
      .toList();
}
