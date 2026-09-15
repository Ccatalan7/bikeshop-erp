import 'package:flutter/foundation.dart';

import '../../../shared/services/authority_scoped_cache.dart';
import 'ai_assistant_destination.dart';

/// Raised when a shared service returned rows that could not be proven to
/// belong to the turn's authority.
class AIAssistantSourceUnavailable implements Exception {
  const AIAssistantSourceUnavailable(this.source, this.reason);

  final String source;
  final String reason;

  @override
  String toString() => 'AI source "$source" unavailable: $reason';
}

/// The one authority a turn may answer from.
///
/// An unresolved authority is not representable. Every row is checked against
/// this key before it reaches a prompt, tool result or card. A source that
/// cannot be proven is unavailable; it is never silently filtered or degraded
/// into zero results.
@immutable
class AIAssistantTurnAuthority {
  const AIAssistantTurnAuthority(
    this.scope, {
    this.role = 'unknown',
    this.permissions = const <String>{},
  });

  final ErpAuthorityScopeKey scope;
  final String role;
  final Set<String> permissions;

  String get tenantId => scope.tenantId;

  List<T> verifyRows<T>(
    String source,
    Iterable<T> rows,
    String? Function(T row) tenantOf,
  ) {
    final expected = scope.tenantId;
    final verified = <T>[];

    for (final row in rows) {
      final rowTenant = tenantOf(row)?.trim();
      if (rowTenant == null || rowTenant.isEmpty) {
        throw AIAssistantSourceUnavailable(source, 'a row carries no tenant');
      }
      if (rowTenant != expected) {
        throw AIAssistantSourceUnavailable(
          source,
          'a row belongs to another tenant',
        );
      }
      verified.add(row);
    }
    return verified;
  }

  void requireServiceScope(String source, ErpAuthorityScopeKey? serviceScope) {
    if (serviceScope == null) {
      throw AIAssistantSourceUnavailable(source, 'service has no bound scope');
    }
    if (serviceScope != scope) {
      throw AIAssistantSourceUnavailable(
        source,
        'service is bound to another authority',
      );
    }
  }
}

/// A closed server-owned command admitted by an assistant approval card.
///
/// The model may prepare one of these commands, but it never supplies the
/// payload at approval time. The exact proposal is already frozen behind
/// [AIAssistantApprovalRef.id].
enum AIAssistantApprovalAction {
  createTask,
  updateDiagnosis,
  addWorkshopItem,
}

/// The operator decision sent to the approval endpoint.
enum AIAssistantApprovalDecision {
  approve,
  discard,
}

/// Server-owned lifecycle of one exact approval preview.
enum AIAssistantApprovalState {
  pending,
  approved,
  discarded,
  expired;

  bool get isTerminal => this != AIAssistantApprovalState.pending;
}

/// Opaque approval identity attached only to a governed preview card.
@immutable
class AIAssistantApprovalRef {
  const AIAssistantApprovalRef({
    required this.id,
    required this.action,
    required this.expiresAt,
    required this.state,
  });

  final String id;
  final AIAssistantApprovalAction action;
  final DateTime expiresAt;
  final AIAssistantApprovalState state;

  AIAssistantApprovalRef withState(AIAssistantApprovalState nextState) =>
      AIAssistantApprovalRef(
        id: id,
        action: action,
        expiresAt: expiresAt,
        state: nextState,
      );
}

enum AIAssistantInventoryAvailability {
  any,
  inStock,
  lowStock,
  outOfStock,
}

/// One exact server-projected inventory result set.
///
/// [entityIds] son las filas que la búsqueda pudo entregar, y **viajan siempre**.
/// Con [hasMore] en false son la selección completa; con true son las primeras
/// de más. Antes llegaban nulas al truncarse y el cliente caía a buscar [query]
/// como texto: la frase sólo funciona a través de la traducción de ficha que
/// hace el servidor, así que mientras más acertaba la búsqueda, más vacía salía
/// la lista. Una tarjeta guardada por la versión anterior sí puede traerlas
/// nulas.
/// A truncated result intentionally carries no ID list so the client cannot
/// pretend that the first page is the full catalog result.
@immutable
class AIAssistantInventoryListRef {
  const AIAssistantInventoryListRef({
    required this.query,
    required this.availability,
    required this.resultCount,
    required this.hasMore,
    required this.entityIds,
    required this.autoOpen,
  });

  final String query;
  final AIAssistantInventoryAvailability availability;
  final int resultCount;
  final bool hasMore;
  final List<String>? entityIds;
  final bool autoOpen;
}

enum AIAssistantSupplyNeedProfile {
  balanced,
  profitability,
  urgentLocal,
}

@immutable
class AIAssistantSupplyNeedTechnicalPredicate {
  const AIAssistantSupplyNeedTechnicalPredicate({
    required this.field,
    required this.operator,
    required this.values,
  });

  final String field;
  final String operator;
  final List<Object> values;

  Map<String, Object?> toJson() => <String, Object?>{
        'field': field,
        'operator': operator,
        'values': values,
      };
}

enum AIAssistantSupplyNeedClarificationInputKind {
  singleChoice,
  text,
  number,
}

@immutable
class AIAssistantSupplyNeedClarificationOption {
  const AIAssistantSupplyNeedClarificationOption({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{
        'value': value,
        'label': label,
      };
}

/// One model-authored question for a material ambiguity in the operator's
/// request. These prompts are deliberately category-agnostic: the model may
/// ask for the next missing fact, but the client never encodes a product-
/// specific decision tree.
@immutable
class AIAssistantSupplyNeedClarificationPrompt {
  const AIAssistantSupplyNeedClarificationPrompt({
    required this.id,
    required this.question,
    required this.inputKind,
    required this.options,
    required this.unit,
    required this.allowUnknown,
  });

  final String id;
  final String question;
  final AIAssistantSupplyNeedClarificationInputKind inputKind;
  final List<AIAssistantSupplyNeedClarificationOption> options;
  final String? unit;
  final bool allowUnknown;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'question': question,
        'inputKind': switch (inputKind) {
          AIAssistantSupplyNeedClarificationInputKind.singleChoice =>
            'single_choice',
          AIAssistantSupplyNeedClarificationInputKind.text => 'text',
          AIAssistantSupplyNeedClarificationInputKind.number => 'number',
        },
        'options': options.map((option) => option.toJson()).toList(
              growable: false,
            ),
        'unit': unit,
        'allowUnknown': allowUnknown,
      };
}

/// Objetivo comercial que la IA leyó en la petición, **sin marca**.
///
/// Tres claves, y las tres son las que el esquema de `prepare_supply_request`
/// declara: gama, techo de costo aterrizado neto por unidad y piso de margen
/// bruto. `preferredBrandId` **no** viaja: ninguna herramienta acuña
/// referencias de marca todavía, así que el modelo no puede nombrarla y
/// declararla acá sólo produciría referencias que nunca resuelven.
///
/// La moneda es del servidor y no aparece: el techo se guarda en la moneda de
/// la revisión que lo fijó, y el cliente nunca la escribe.
@immutable
class AIAssistantSupplyNeedCommercialTarget {
  const AIAssistantSupplyNeedCommercialTarget({
    this.gama,
    this.maxLandedUnitCostNet,
    this.minGrossMarginRatio,
  });

  final String? gama;
  final double? maxLandedUnitCostNet;
  final double? minGrossMarginRatio;

  /// Un objetivo con las tres claves vacías **no es un objetivo**: la base lo
  /// rechaza («Empty commercial target»), así que no se manda.
  bool get isEmpty =>
      gama == null &&
      maxLandedUnitCostNet == null &&
      minGrossMarginRatio == null;

  Map<String, Object?> toCommandJson() => <String, Object?>{
        if (gama != null) 'gama': gama,
        if (maxLandedUnitCostNet != null)
          'maxLandedUnitCostNet': maxLandedUnitCostNet,
        if (minGrossMarginRatio != null)
          'minGrossMarginRatio': minGrossMarginRatio,
      };
}

@immutable
class AIAssistantSupplyNeedDraftLine {
  const AIAssistantSupplyNeedDraftLine({
    required this.lineRef,
    required this.description,
    required this.productId,
    required this.productName,
    required this.productSku,
    required this.identityState,
    required this.quantity,
    required this.unit,
    required this.technicalPredicates,
    required this.preference,
    required this.clarification,
    required this.clarificationRequired,
    this.categoryId,
    this.categoryPath,
    this.technicalFamily,
    this.commercialTarget,
    this.clarificationPrompts = const [],
  });

  final String lineRef;
  final String description;
  final String? productId;
  final String? productName;
  final String? productSku;
  final String identityState;

  /// Procedencia de categoría resuelta por el servidor.
  ///
  /// Con producto exacto la deriva de la ficha; sin producto, viene de la
  /// categoría que el modelo resolvió con el inspector. El cliente **no la
  /// edita ni la infiere**: la transporta desde la tarjeta cerrada hasta el
  /// comando durable, que la persiste en la revisión de interpretación.
  ///
  /// [technicalFamily] es derivada —su dueño es `category_tech_mappings`— y
  /// viaja sólo para poder rotularla; no se guarda.
  final String? categoryId;
  final String? categoryPath;
  final String? technicalFamily;
  final double quantity;
  final String unit;
  final List<AIAssistantSupplyNeedTechnicalPredicate> technicalPredicates;
  final String? preference;
  final String? clarification;
  final bool clarificationRequired;

  /// Objetivo comercial tipado de **esta** línea, cuando el operador lo dijo.
  ///
  /// Viaja desde la tarjeta cerrada hasta el comando durable, igual que la
  /// categoría resuelta: el cliente lo transporta y no lo inventa.
  final AIAssistantSupplyNeedCommercialTarget? commercialTarget;
  final List<AIAssistantSupplyNeedClarificationPrompt> clarificationPrompts;

  bool get hasConfirmedProduct =>
      identityState == 'confirmed' && productId != null && productName != null;

  /// Ajustes que **no** tocan la identidad de la línea.
  ///
  /// Cantidad y unidad no cambian qué es el producto, así que la procedencia
  /// —producto, categoría y predicados— sobrevive. Editar la descripción sí la
  /// cambia, y eso no se hace acá: se construye una línea nueva sin
  /// procedencia, porque conservar la anterior sería atribuirle al operador una
  /// identidad que ya no pidió.
  AIAssistantSupplyNeedDraftLine copyWith({
    double? quantity,
    String? unit,
  }) =>
      AIAssistantSupplyNeedDraftLine(
        lineRef: lineRef,
        description: description,
        productId: productId,
        productName: productName,
        productSku: productSku,
        identityState: identityState,
        categoryId: categoryId,
        categoryPath: categoryPath,
        technicalFamily: technicalFamily,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        technicalPredicates: technicalPredicates,
        preference: preference,
        clarification: clarification,
        clarificationRequired: clarificationRequired,
        commercialTarget: commercialTarget,
        clarificationPrompts: clarificationPrompts,
      );

  /// La línea reescrita a mano: descripción nueva, procedencia en blanco.
  ///
  /// Producto, categoría y predicados venían de interpretar **la frase
  /// anterior**. Si el operador la reescribe, arrastrarlos afirmaría algo que
  /// nadie dijo, y el ranking posterior heredaría una familia equivocada sin
  /// que nada lo delate.
  AIAssistantSupplyNeedDraftLine withRewrittenDescription({
    required String description,
    required double quantity,
    required String unit,
    required String clarification,
  }) =>
      AIAssistantSupplyNeedDraftLine(
        lineRef: lineRef,
        description: description,
        productId: null,
        productName: null,
        productSku: null,
        identityState: 'unresolved',
        categoryId: null,
        categoryPath: null,
        technicalFamily: null,
        quantity: quantity,
        unit: unit,
        technicalPredicates: const [],
        preference: null,
        clarification: clarification,
        clarificationRequired: true,
        // El objetivo salió de interpretar la frase anterior, igual que el
        // producto y la categoría. Si el operador la reescribe, arrastrarlo
        // afirmaría un techo o una gama que nadie volvió a pedir.
        commercialTarget: null,
      );

  Map<String, Object?> toCommandJson() => <String, Object?>{
        'lineRef': lineRef,
        'description': description,
        'productId': productId,
        'categoryId': categoryId,
        'quantity': quantity,
        'unit': unit,
        'technicalPredicates': technicalPredicates
            .map((predicate) => predicate.toJson())
            .toList(growable: false),
        'preference': preference,
        'clarification': clarification,
        'clarificationRequired': clarificationRequired,
        // Ausente y vacío no son lo mismo: `create_supply_need_batch_v3`
        // normaliza un objeto y descarta un objetivo vacío, pero una clave con
        // un objeto sin claves útiles no aporta nada, así que no se envía.
        if (commercialTarget != null && !commercialTarget!.isEmpty)
          'commercialTarget': commercialTarget!.toCommandJson(),
      };
}

@immutable
class AIAssistantSupplyNeedDraft {
  const AIAssistantSupplyNeedDraft({
    required this.profile,
    required this.lines,
  });

  final AIAssistantSupplyNeedProfile profile;
  final List<AIAssistantSupplyNeedDraftLine> lines;

  AIAssistantSupplyNeedDraft copyWith({
    List<AIAssistantSupplyNeedDraftLine>? lines,
  }) =>
      AIAssistantSupplyNeedDraft(
        profile: profile,
        lines: lines ?? this.lines,
      );
}

/// A card the assistant offers after answering.
///
/// The card carries a closed [destination] and may carry one verified,
/// server-owned [entityRef]. It never carries a model-authored route. The
/// application remains the owner of every possible click.
@immutable

/// Una opción excluyente que el operador puede elegir en la tarjeta. Elegir
/// NO ejecuta nada: abre la revisión de lo que se hará —el texto exacto de un
/// mensaje, la línea que se agregará— y recién ahí se confirma.
@immutable
class AIAssistantCardOption {
  const AIAssistantCardOption({
    required this.id,
    required this.label,
    this.description,
  });

  final String id;
  final String label;

  /// Lo que el operador verá antes de confirmar. Para una plantilla de
  /// WhatsApp es el texto exacto que recibirá el cliente.
  final String? description;
}

class AIAssistantActionCard {
  const AIAssistantActionCard({
    required this.kind,
    required this.title,
    required this.destination,
    this.eyebrow,
    this.subtitle,
    this.description,
    this.chips = const <String>[],
    this.entityRef,
    this.approvalRef,
    this.inventoryListRef,
    this.supplyNeedDraft,
    this.options = const <AIAssistantCardOption>[],
    this.optionKind,
  });

  final String kind;
  final String title;
  final AIAssistantDestination destination;
  final String? eyebrow;
  final String? subtitle;
  final String? description;
  final List<String> chips;
  final AIAssistantEntityRef? entityRef;
  final AIAssistantApprovalRef? approvalRef;
  final AIAssistantInventoryListRef? inventoryListRef;
  final AIAssistantSupplyNeedDraft? supplyNeedDraft;

  /// Opciones excluyentes que el chat dibuja como controles.
  final List<AIAssistantCardOption> options;

  /// Qué família de acción representan, para saber qué revisión abrir.
  final String? optionKind;

  String get ctaLabel => supplyNeedDraft != null
      ? 'Revisar petición'
      : inventoryListRef != null
          ? 'Ver resultados'
          : entityRef?.detailCtaLabel ?? destination.ctaLabel;

  AIAssistantActionCard withApprovalState(
    AIAssistantApprovalState state,
  ) {
    final approval = approvalRef;
    if (approval == null) return this;
    return AIAssistantActionCard(
      kind: kind,
      title: title,
      destination: destination,
      eyebrow: eyebrow,
      subtitle: subtitle,
      description: description,
      chips: chips,
      entityRef: entityRef,
      approvalRef: approval.withState(state),
      inventoryListRef: inventoryListRef,
      supplyNeedDraft: supplyNeedDraft,
      options: options,
      optionKind: optionKind,
    );
  }
}

@immutable
class AIAssistantResponse {
  const AIAssistantResponse({
    required this.text,
    this.cards = const <AIAssistantActionCard>[],
  });

  final String text;
  final List<AIAssistantActionCard> cards;
}

/// Deterministic result of approve/discard. No model turn participates.
@immutable
class AIAssistantApprovalResolution {
  const AIAssistantApprovalResolution({
    required this.approvalId,
    required this.clientActionId,
    required this.state,
    required this.text,
    required this.cards,
  });

  final String approvalId;
  final String clientActionId;
  final AIAssistantApprovalState state;
  final String text;
  final List<AIAssistantActionCard> cards;
}
