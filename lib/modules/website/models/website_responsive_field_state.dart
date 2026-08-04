import 'website_block_definition.dart';
import 'website_responsive_authoring.dart';

enum WebsiteResponsiveFieldStatus {
  common,
  inherited,
  overridden,
  sharedOnly,
  legacyConflict,
  unavailable,
}

/// Immutable presentation contract shared by inspector and inline controls.
///
/// It contains no widget styling and no serialized keys beyond the canonical
/// field schema. The same state can therefore drive desktop inspector, phone
/// dock/sheet and accessibility labels without each surface reinterpreting
/// inheritance.
class WebsiteResponsiveFieldState<T> {
  const WebsiteResponsiveFieldState({
    required this.schema,
    required this.context,
    required this.resolved,
    required this.status,
    required this.effectiveWriteScope,
    required this.canCustomize,
    required this.canReset,
    this.unavailableReason,
  });

  factory WebsiteResponsiveFieldState.resolve({
    required WebsiteBlockFieldSchema schema,
    required WebsiteAuthoringContext context,
    required WebsiteResolvedResponsiveValue<T> resolved,
    String? unavailableReason,
  }) {
    final effectiveScope = context.effectiveWriteScope(
      schema.responsivePolicy,
    );
    final unavailable = unavailableReason?.trim().isNotEmpty == true;

    late final WebsiteResponsiveFieldStatus status;
    if (unavailable) {
      status = WebsiteResponsiveFieldStatus.unavailable;
    } else if (!schema.allowsViewportOverride) {
      status = WebsiteResponsiveFieldStatus.sharedOnly;
    } else if (resolved.isLegacyOverride) {
      status = WebsiteResponsiveFieldStatus.legacyConflict;
    } else if (resolved.isOverride) {
      status = WebsiteResponsiveFieldStatus.overridden;
    } else if (context.previewViewport == WebsiteViewport.desktop) {
      status = WebsiteResponsiveFieldStatus.common;
    } else {
      status = WebsiteResponsiveFieldStatus.inherited;
    }

    return WebsiteResponsiveFieldState<T>(
      schema: schema,
      context: context,
      resolved: resolved,
      status: status,
      effectiveWriteScope: effectiveScope,
      canCustomize: !unavailable &&
          schema.allowsViewportOverride &&
          context.previewViewport.supportsOverride &&
          !resolved.isOverride,
      canReset: !unavailable &&
          schema.canResetResponsiveOverride &&
          context.previewViewport.supportsOverride &&
          resolved.isOverride,
      unavailableReason: unavailableReason,
    );
  }

  final WebsiteBlockFieldSchema schema;
  final WebsiteAuthoringContext context;
  final WebsiteResolvedResponsiveValue<T> resolved;
  final WebsiteResponsiveFieldStatus status;
  final WebsiteWriteScope effectiveWriteScope;
  final bool canCustomize;
  final bool canReset;
  final String? unavailableReason;

  String get statusLabel => switch (status) {
        WebsiteResponsiveFieldStatus.common => 'Común',
        WebsiteResponsiveFieldStatus.inherited => 'Heredado',
        WebsiteResponsiveFieldStatus.overridden =>
          'Personalizado para ${context.previewViewport.label}',
        WebsiteResponsiveFieldStatus.sharedOnly => 'Siempre común',
        WebsiteResponsiveFieldStatus.legacyConflict =>
          'Configuración móvil anterior',
        WebsiteResponsiveFieldStatus.unavailable => 'No disponible',
      };

  String get semanticSummary {
    final scope = switch (effectiveWriteScope) {
      WebsiteWriteScope.shared => 'los valores comunes',
      WebsiteWriteScope.viewport =>
        'la vista ${context.previewViewport.label.toLowerCase()}',
    };
    final reason = unavailableReason?.trim();
    if (reason != null && reason.isNotEmpty) {
      return '${schema.label}: $statusLabel. $reason';
    }
    return '${schema.label}: $statusLabel. Los cambios afectan $scope.';
  }
}

extension WebsiteViewportCopy on WebsiteViewport {
  String get label => switch (this) {
        WebsiteViewport.desktop => 'Escritorio',
        WebsiteViewport.tablet => 'Tablet',
        WebsiteViewport.mobile => 'Móvil',
      };
}
