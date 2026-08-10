import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../../inventory/services/inventory_service.dart';
import '../../purchases/models/purchase_invoice.dart';
import '../../purchases/services/purchase_service.dart';
import '../../sales/models/sales_models.dart';
import '../../sales/services/sales_service.dart';
import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_service.dart';
import '../../../shared/models/supplier.dart';
import '../../../shared/models/notification_digest.dart';
import '../../../shared/services/gemini_proxy_service.dart';
import '../../../shared/services/authority_scoped_cache.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/ai_agent_contracts.dart';
import '../models/ai_agent_audit_event.dart';
import '../models/ai_agent_tool.dart';
import '../models/ai_assistant_destination.dart';
import '../models/ai_assistant_turn_contracts.dart';
import '../models/ai_attention_report.dart';
import '../models/ai_inventory_reply.dart';
import '../providers/ai_agent_model_provider.dart';
import '../providers/gemini_ai_agent_model_provider.dart';
import 'ai_assistant_read_tool_catalog.dart';
import 'ai_assistant_turn_engine.dart';
import 'ai_business_read_tool_catalog.dart';
import 'ai_agent_audit_sink.dart';
import 'ai_attention_read_model.dart';
import 'ai_operational_read_tool_catalog.dart';
import 'ai_tool_registry.dart';
import 'in_memory_ai_agent_audit_sink.dart';

export '../models/ai_assistant_turn_contracts.dart';

String _newAIAgentId() => const Uuid().v4();

List<int> _newAIAuditHmacKey() {
  final random = math.Random.secure();
  return List<int>.unmodifiable(
    List<int>.generate(32, (_) => random.nextInt(256), growable: false),
  );
}

void _debugAi(String message) {
  if (!kReleaseMode) debugPrint(message);
}

class AIProductImageAnalysis {
  const AIProductImageAnalysis({
    required this.primaryType,
    required this.catalogTerms,
    required this.excludedTerms,
    required this.confidence,
    this.visualSummary,
    this.textConflict = false,
  });

  final String primaryType;
  final List<String> catalogTerms;
  final List<String> excludedTerms;
  final double confidence;
  final String? visualSummary;
  final bool textConflict;
}

class AIProductVisualComparison {
  const AIProductVisualComparison({
    required this.samePartScore,
    required this.shapeScore,
    required this.colorScore,
    required this.componentTypeMatch,
    required this.confidence,
    this.reason,
  });

  final double samePartScore;
  final double shapeScore;
  final double colorScore;
  final bool componentTypeMatch;
  final double confidence;
  final String? reason;
}

class _PreparedGeminiImage {
  const _PreparedGeminiImage({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;
}

/// Result of [AIAssistantService.cleanProductTitleFromImage]: a clean,
/// shop-friendly product name plus structured metadata derived from BOTH
/// the noisy supplier title (e.g. AliExpress) and the actual product photo.
class AICleanedProductName {
  const AICleanedProductName({
    required this.cleanedName,
    required this.componentType,
    this.brand,
    this.model,
    this.categoryName,
    this.confidence = 0.0,
    this.visualAnalysis,
  });

  /// Short, store-ready product name. Chilean Spanish vocabulary.
  /// Format: "<Component> <Brand?> <Model/Spec?>" — capped ~60 chars.
  final String cleanedName;

  /// Concrete component type (e.g. "postiza", "polea", "pastillas freno").
  /// Used to seed `categoryName` on the duplicate-matcher probe so the
  /// family detector classifies the row correctly.
  final String componentType;

  /// Brand visible in the photo / inferable from the title (e.g. "ZTTO").
  final String? brand;

  /// Model / part number visible in the photo (e.g. "001", "RD-M5100").
  final String? model;

  /// Suggested catalog category, mapped to local Chilean shop vocabulary.
  /// Examples: "Postizas", "Poleas", "Pastillas de freno", "Cassettes".
  final String? categoryName;

  /// 0-1 confidence in the cleaned result.
  final double confidence;

  /// What the same call saw in the photo, stated independently of the title.
  ///
  /// The title reading and the object reading used to be two separate Gemini
  /// calls on the same bytes — one to write the name, one to recognise the
  /// object — so every row paid twice and the two answers could disagree with
  /// nothing to reconcile them. They are one call now: the model is asked for
  /// both, and this block is the half that the identity engine and the category
  /// resolver are allowed to weigh against the words.
  final AIProductImageAnalysis? visualAnalysis;
}

/// One shortlisted catalog product offered to the adjudicator.
class AIProductMatchOption {
  const AIProductMatchOption({
    required this.id,
    required this.name,
    this.brand,
    this.category,
    this.note,
  });

  /// The catalog SKU. It is what the model must echo back to choose this row.
  final String id;
  final String name;
  final String? brand;
  final String? category;

  /// What the deterministic engine already concluded about this row, so the
  /// model sees the same evidence the operator does.
  final String? note;
}

/// Which product the model says the invoice line is.
class AIProductMatchDecision {
  const AIProductMatchDecision({
    required this.productId,
    required this.reason,
    required this.confidence,
  });

  /// `null` means «ninguno de estos», which is a real answer.
  final String? productId;
  final String? reason;
  final double confidence;

  bool get hasChoice => productId != null && productId!.isNotEmpty;
}

class _TireWidthRange {
  const _TireWidthRange({
    required this.minWidth,
    required this.maxWidth,
  });

  final double minWidth;
  final double maxWidth;

  double get span => maxWidth - minWidth;

  String get label => '${_format(minWidth)}-${_format(maxWidth)}';

  static String _format(double value) {
    final rounded = value.toStringAsFixed(3);
    return rounded
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

class _WidthComparisonCandidate {
  const _WidthComparisonCandidate({
    required this.product,
    required this.range,
    required this.stock,
  });

  final Map<String, dynamic> product;
  final _TireWidthRange range;
  final double stock;
}

class AIAssistantService extends ChangeNotifier
    implements AIAssistantTurnEngine {
  static const Duration _maxModelCallDuration = Duration(seconds: 35);
  static const Duration _maxAgentTurnDuration = Duration(seconds: 90);
  static const Duration _maxAuditRecordDuration = Duration(milliseconds: 100);
  static const Duration _defaultImageDownloadTimeout = Duration(seconds: 8);
  static const int _maxDownloadedImageBytes = 8 * 1024 * 1024;
  static const int _maxToolCallsPerTurn = 12;

  /// One engine per authority, never a process-wide singleton.
  ///
  /// This used to be `factory AIAssistantService() => _instance`, so every
  /// caller shared one chat history, one set of matched SKUs and one
  /// `_lastSearchResults`. A panel that looked brand new answered "tomé la
  /// búsqueda anterior" about a search made in someone else's session, and
  /// closing the panel cleared what the operator saw without clearing what the
  /// model remembered. The session boundary owns the lifetime now.
  AIAssistantService({
    AIAgentModelProvider? modelProvider,
    AIAgentAuditSink? auditSink,
    GeminiProxyService? geminiProxy,
    http.Client Function()? imageHttpClientFactory,
    Duration imageDownloadTimeout = _defaultImageDownloadTimeout,
    String Function()? idFactory,
    DateTime Function()? now,
  })  : _modelProvider = modelProvider ?? GeminiAIAgentModelProvider(),
        _auditSink = FailSafeAIAgentAuditSink(
          auditSink ?? InMemoryAIAgentAuditSink(),
        ),
        _imageHttpClientFactory =
            imageHttpClientFactory ?? (() => http.Client()),
        _imageDownloadTimeout = imageDownloadTimeout,
        _idFactory = idFactory ?? _newAIAgentId,
        _now = now ?? DateTime.now,
        _auditHmacKey = _newAIAuditHmacKey() {
    _geminiProxyInstance = geminiProxy;
    _sessionId = _idFactory();
  }

  final AIAgentModelProvider _modelProvider;
  final AIAgentAuditSink _auditSink;
  final http.Client Function() _imageHttpClientFactory;
  final Duration _imageDownloadTimeout;
  final String Function() _idFactory;
  final DateTime Function() _now;
  final List<int> _auditHmacKey;
  late String _sessionId;
  GeminiProxyService? _geminiProxyInstance;
  GeminiProxyService get _geminiProxy =>
      _geminiProxyInstance ??= GeminiProxyService();
  final List<AIAgentMessage> _history = <AIAgentMessage>[];
  bool _isLoading = false;
  int _turnSequence = 0;

  // `_lastSearchSkus` and the stock-filter indices lived here to hand a
  // pre-filtered selection to the inventory screen when the assistant drove
  // navigation. Nothing drives navigation any more, so both are gone rather
  // than kept as state nobody reads.
  List<Map<String, dynamic>> _lastSearchResults = [];
  String? _lastInventorySearchTerm;

  bool get isLoading => _isLoading;
  List<AIAgentMessage> get history =>
      List<AIAgentMessage>.unmodifiable(_history);
  bool get isGeminiConfigured => true;

  /// Kept as a compatibility hook for callers that eagerly initialized the
  /// former Gemini-specific declarations. Tool discovery now happens inside
  /// every authority-bound turn.
  void initialize() {}

  Future<String> generateOneShotText(
    String prompt, {
    String modelName = 'gemini-2.5-flash-lite',
  }) async {
    return _geminiProxy.generateText(prompt: prompt, model: modelName);
  }

  /// One catalog product the shortlist offered, as the model sees it.
  ///
  /// Only these rows may be chosen. The model never writes a SKU: it returns
  /// one of the ids it was handed, or nothing.
  static const int maxAdjudicationCandidates = 12;

  /// Picks which shortlisted product an invoice line actually is.
  ///
  /// The deterministic engine is better at what it does — cutting fifteen
  /// hundred products to a handful, and refusing the ones that physically
  /// cannot fit. What it cannot do is *know what a thing is* without a word
  /// for it in its dictionary, and supplier Spanish is bigger than any
  /// dictionary. This step closes that gap: given the line and the survivors,
  /// the model answers the question a person answers by looking.
  ///
  /// It is deliberately narrow:
  ///
  /// * it chooses among rows it was given, or returns none — it cannot invent;
  /// * it is asked only when the engine is not already certain;
  /// * it must say why, in the shop's words, and that reason is what the row
  ///   renders. No score, no percentage.
  Future<AIProductMatchDecision?> adjudicateProductMatch({
    required String invoiceTitle,
    String? supplierCode,
    String? invoiceBrand,
    required List<AIProductMatchOption> options,
    Uint8List? imageBytes,
    String modelName = 'gemini-2.5-flash',
  }) async {
    if (invoiceTitle.trim().isEmpty || options.isEmpty) return null;
    final bounded = options.take(maxAdjudicationCandidates).toList();
    final allowedIds = bounded.map((option) => option.id).toSet();

    final catalogLines = <String>[
      for (final option in bounded)
        '- id: ${option.id}\n'
            '  nombre: ${option.name}\n'
            '  marca: ${option.brand ?? 'sin marca'}\n'
            '  categoria: ${option.category ?? 'sin categoria'}'
            '${option.note == null ? '' : '\n  nota del motor: ${option.note}'}',
    ];

    final prompt = '''
Eres el maestro de bodega de una bicicleteria chilena. Te llega UNA linea de una
factura de proveedor y la lista de productos que ya existen en el catalogo y que
podrian ser esa misma pieza. Tu unica tarea es decir CUAL de ellos es el mismo
producto, o que ninguno lo es.

Linea de la factura:
  titulo: ${invoiceTitle.trim()}
  codigo del proveedor: ${supplierCode?.trim().isNotEmpty == true ? supplierCode!.trim() : 'sin codigo'}
  marca leida: ${invoiceBrand?.trim().isNotEmpty == true ? invoiceBrand!.trim() : 'sin marca'}

Candidatos del catalogo:
${catalogLines.join('\n')}

Responde SOLO JSON valido con esta forma exacta:
{"id": "<id de la lista o null>", "reason": "<por que, en una frase>", "confidence": 0.0}

Reglas duras:
- El id DEBE ser uno de los ids de la lista, tal cual. Si ninguno es el mismo
  producto, responde id: null. NUNCA inventes un id ni un producto.
- Es el MISMO producto solo si es la misma pieza: mismo tipo de objeto, misma
  medida decisiva y mismo fabricante cuando ambos lo declaran. Una pieza que
  sirve para lo mismo NO es la misma pieza.
- Un accesorio, un repuesto o una herramienta que se nombra parecido no es el
  producto. Una pinza de freno no es un alicate; un eslabon rapido no es un
  sticker; una extension de postiza no es una postiza.
- La variante importa: color, velocidades, diametro y lado (delantero/trasero)
  distintos significan otro producto.
- reason va en español de Chile, en una frase corta, nombrando la evidencia
  concreta que decidio (el modelo, la medida, la marca). Nada de porcentajes.
- confidence entre 0 y 1: que tan seguro estas de que es exactamente el mismo.
''';

    try {
      final parts = <Map<String, dynamic>>[
        {'text': prompt},
      ];
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final prepared = _prepareImageForGemini(imageBytes);
        parts.add({
          'inlineData': {
            'mimeType': prepared.mimeType,
            'data': base64Encode(prepared.bytes),
          },
        });
      }
      final response = await _geminiProxy.generateContent(
        model: modelName,
        contents: [
          {'role': 'user', 'parts': parts},
        ],
      );
      final jsonBlock = _extractJsonObject(response.text.trim());
      if (jsonBlock == null) return null;
      final decoded = jsonDecode(jsonBlock);
      if (decoded is! Map<String, dynamic>) return null;

      final rawId = decoded['id']?.toString().trim() ?? '';
      // A model that answers with an id nobody offered has not chosen a
      // product; it has written one. That is refused, not repaired.
      final id = allowedIds.contains(rawId) ? rawId : null;
      final reason = _normalizeImageAnalysisTerm(
        decoded['reason']?.toString(),
        maxWords: 24,
      );
      return AIProductMatchDecision(
        productId: id,
        reason: reason.isEmpty ? null : reason,
        confidence: _coerceAnalysisConfidence(decoded['confidence']),
      );
    } catch (_) {
      _debugAi('❌ [AI] Product match adjudication failed.');
      return null;
    }
  }

  Future<AIProductImageAnalysis?> analyzeProductImage(
    Uint8List imageBytes, {
    String? fileName,
    String? typedName,
    String? typedDescription,
    String modelName = 'gemini-2.5-flash',
  }) async {
    if (imageBytes.isEmpty) return null;
    final preparedImage = _prepareImageForGemini(imageBytes);

    final hintLines = <String>[];
    if (fileName != null && fileName.trim().isNotEmpty) {
      hintLines.add('file_name: ${fileName.trim()}');
    }
    if (typedName != null && typedName.trim().isNotEmpty) {
      hintLines.add('typed_name: ${typedName.trim()}');
    }
    if (typedDescription != null && typedDescription.trim().isNotEmpty) {
      hintLines.add('typed_description: ${typedDescription.trim()}');
    }

    final prompt = '''
Analiza esta foto de producto para un catalogo de bicicleteria.
Tu objetivo es identificar que tipo de producto aparece realmente en la imagen.
Usa el texto escrito solo como contexto debil. Si el texto contradice la foto, prioriza la foto.

Responde SOLO JSON valido con esta forma exacta:
{
  "primary_type": "cambio trasero",
  "catalog_terms": ["cambio trasero", "rear derailleur", "desviador", "shimano", "deore"],
  "excluded_terms": ["cadena", "cassette", "pinon"],
  "confidence": 0.93,
  "text_conflict": false,
  "visual_summary": "cambio trasero shimano deore negro 12v"
}

Reglas:
- todo en minusculas
- primary_type debe ser un sustantivo concreto y corto que podria aparecer en un titulo de producto
- catalog_terms debe tener entre 3 y 8 terminos cortos utiles para buscar este producto en un catalogo
- SI la marca, modelo o texto es VISIBLE en la foto (logo, etiqueta, texto impreso), INCLUYE la marca y modelo en catalog_terms
- NO inventes marcas o modelos que no sean claramente visibles en la imagen
- excluded_terms debe contener familias de producto claramente distintas cuando sea obvio
- confidence debe ser un numero entre 0 y 1
- no inventes especificaciones tecnicas invisibles, no escribas explicacion fuera del JSON
- si la imagen es ambigua, igual responde con la mejor hipotesis pero baja confidence

Contexto adicional:
${hintLines.isEmpty ? 'sin texto adicional' : hintLines.join('\n')}
''';

    try {
      final response = await _geminiProxy.generateContent(
        model: modelName,
        contents: [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
              {
                'inlineData': {
                  'mimeType': preparedImage.mimeType,
                  'data': base64Encode(preparedImage.bytes),
                },
              },
            ],
          },
        ],
      );

      final rawText = response.text.trim();
      if (rawText.isEmpty) return null;

      final jsonBlock = _extractJsonObject(rawText);
      if (jsonBlock == null) {
        _debugAi('⚠️ [AI] Product image analysis returned invalid output.');
        return null;
      }

      final decoded = jsonDecode(jsonBlock);
      if (decoded is! Map<String, dynamic>) return null;

      final primaryType = _normalizeImageAnalysisTerm(
        decoded['primary_type']?.toString(),
      );
      final catalogTerms =
          _normalizeImageAnalysisTerms(decoded['catalog_terms']);
      final excludedTerms =
          _normalizeImageAnalysisTerms(decoded['excluded_terms']);

      if (primaryType.isEmpty && catalogTerms.isEmpty) {
        return null;
      }

      final mergedTerms = {
        if (primaryType.isNotEmpty) primaryType,
        ...catalogTerms,
      }.toList(growable: false);

      return AIProductImageAnalysis(
        primaryType: primaryType,
        catalogTerms: mergedTerms,
        excludedTerms: excludedTerms,
        confidence: _coerceAnalysisConfidence(decoded['confidence']),
        visualSummary: _normalizeImageAnalysisTerm(
          decoded['visual_summary']?.toString(),
          maxWords: 12,
        ),
        textConflict: decoded['text_conflict'] == true,
      );
    } catch (_) {
      _debugAi('❌ [AI] Product image analysis failed.');
      return null;
    }
  }

  final Map<String, AIProductVisualComparison> _visualComparisonCache = {};

  Future<AIProductVisualComparison?> compareProductImagesForDuplicate({
    required Uint8List probeImageBytes,
    required Uint8List candidateImageBytes,
    String? probeName,
    String? candidateName,
    String? candidateBrand,
    String? candidateCategory,
    String modelName = 'gemini-2.5-flash',
  }) async {
    if (probeImageBytes.isEmpty || candidateImageBytes.isEmpty) return null;

    final cacheKey = [
      _imageBytesCacheKey(probeImageBytes),
      _imageBytesCacheKey(candidateImageBytes),
      probeName?.trim().toLowerCase() ?? '',
      candidateName?.trim().toLowerCase() ?? '',
    ].join('|');
    final cached = _visualComparisonCache[cacheKey];
    if (cached != null) return cached;

    final probeImage = _prepareImageForGemini(probeImageBytes);
    final candidateImage = _prepareImageForGemini(candidateImageBytes);
    final contextLines = <String>[
      if (probeName != null && probeName.trim().isNotEmpty)
        'producto_a_nombre: ${probeName.trim()}',
      if (candidateName != null && candidateName.trim().isNotEmpty)
        'producto_b_nombre: ${candidateName.trim()}',
      if (candidateBrand != null && candidateBrand.trim().isNotEmpty)
        'producto_b_marca: ${candidateBrand.trim()}',
      if (candidateCategory != null && candidateCategory.trim().isNotEmpty)
        'producto_b_categoria: ${candidateCategory.trim()}',
    ];

    final prompt = '''
Compara dos fotos de productos de bicicleteria para detectar duplicados.
Imagen A es el producto nuevo que estamos buscando. Imagen B es un producto
existente del catalogo.

Tu trabajo NO es comparar textos. Debes mirar las fotos y decidir si B parece
ser el MISMO repuesto/modelo fisico que A, especialmente para postizas / hanger
de cambio trasero.

Evalua con criterio visual real:
- silueta general, geometria, agujeros, ganchos, orejas, zonas de montaje
- color/material visible cuando ayuda (negro vs plateado importa)
- numero de piezas visibles (una pieza vs dos piezas no debe ser alta)
- ignora posicion, escala, recorte, rotacion o espejo de la foto
- no premies una pieza solo por ser "postiza"; si la forma no coincide, baja score
- si A y B son la misma postiza/modelo con foto distinta, same_part_score debe ser 0.90+
- si B es otra postiza/hanger de forma distinta, same_part_score normalmente 0.20-0.55
- si B ni siquiera parece el mismo tipo exacto, same_part_score debe ser bajo

Responde SOLO JSON valido con esta forma exacta:
{
  "same_part_score": 0.94,
  "shape_score": 0.96,
  "color_score": 0.88,
  "component_type_match": true,
  "confidence": 0.91,
  "reason": "misma postiza plateada con mismos agujeros y contorno"
}

Reglas:
- scores entre 0 y 1
- reason en espanol, maximo 16 palabras
- No escribas nada fuera del JSON.

Contexto debil (usar solo si no contradice la foto):
${contextLines.isEmpty ? 'sin texto adicional' : contextLines.join('\n')}
''';

    try {
      final response = await _geminiProxy.generateContent(
        model: modelName,
        contents: [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
              {'text': 'Imagen A - producto nuevo'},
              {
                'inlineData': {
                  'mimeType': probeImage.mimeType,
                  'data': base64Encode(probeImage.bytes),
                },
              },
              {'text': 'Imagen B - candidato del catalogo'},
              {
                'inlineData': {
                  'mimeType': candidateImage.mimeType,
                  'data': base64Encode(candidateImage.bytes),
                },
              },
            ],
          },
        ],
      );

      final rawText = response.text.trim();
      if (rawText.isEmpty) return null;
      final jsonBlock = _extractJsonObject(rawText);
      if (jsonBlock == null) {
        _debugAi('⚠️ [AI] Visual comparison returned invalid output.');
        return null;
      }

      final decoded = jsonDecode(jsonBlock);
      if (decoded is! Map<String, dynamic>) return null;
      final result = AIProductVisualComparison(
        samePartScore: _coerceAnalysisConfidence(decoded['same_part_score']),
        shapeScore: _coerceAnalysisConfidence(decoded['shape_score']),
        colorScore: _coerceAnalysisConfidence(decoded['color_score']),
        componentTypeMatch: decoded['component_type_match'] == true,
        confidence: _coerceAnalysisConfidence(decoded['confidence']),
        reason: _normalizeImageAnalysisTerm(
          decoded['reason']?.toString(),
          maxWords: 16,
        ),
      );

      _visualComparisonCache[cacheKey] = result;
      return result;
    } catch (_) {
      _debugAi('❌ [AI] Visual comparison failed.');
      return null;
    }
  }

  /// Cache for cleaned product names. Keyed by image hash + raw title so
  /// repeated rows in the same AliExpress invoice share one Gemini call.
  final Map<String, AICleanedProductName> _cleanedNameCache = {};
  final Map<String, Future<AICleanedProductName?>> _cleanedNameLoads = {};

  /// Generate a clean, shop-friendly product name + category + brand from a
  /// noisy supplier title (e.g. AliExpress) and the actual product photo.
  ///
  /// Returns `null` on error. Results are cached in-memory per session so
  /// the same image+title pair only costs one Gemini call.
  Future<AICleanedProductName?> cleanProductTitleFromImage({
    required String rawTitle,
    Uint8List? imageBytes,
    String? imageUrl,
    String? supplierName,
    String visionModel = 'gemini-2.5-flash',
  }) async {
    if (rawTitle.trim().isEmpty) return null;

    // PNG/JPEG headers are commonly identical across different product photos.
    // A prefix/length hash therefore leaked one row's classification into a
    // different row. Use the complete content digest and dedupe the in-flight
    // Future so parallel variants also share the same model call.
    final imageIdentity = imageBytes != null && imageBytes.isNotEmpty
        ? 'b:${crypto.sha256.convert(imageBytes)}'
        : (imageUrl?.trim().isNotEmpty ?? false)
            ? 'u:${imageUrl!.trim()}'
            : 'no-image';
    final cacheKey = [
      imageIdentity,
      rawTitle.trim().toLowerCase(),
      supplierName?.trim().toLowerCase() ?? '',
      visionModel,
    ].join('|');
    final cached = _cleanedNameCache[cacheKey];
    if (cached != null) return cached;
    final pending = _cleanedNameLoads[cacheKey];
    if (pending != null) return pending;

    final load = _cleanProductTitleFromImageUncached(
      rawTitle: rawTitle,
      imageBytes: imageBytes,
      imageUrl: imageUrl,
      supplierName: supplierName,
      visionModel: visionModel,
    );
    _cleanedNameLoads[cacheKey] = load;
    try {
      final result = await load;
      if (result != null) _cleanedNameCache[cacheKey] = result;
      return result;
    } finally {
      if (identical(_cleanedNameLoads[cacheKey], load)) {
        _cleanedNameLoads.remove(cacheKey);
      }
    }
  }

  Future<AICleanedProductName?> _cleanProductTitleFromImageUncached({
    required String rawTitle,
    Uint8List? imageBytes,
    String? imageUrl,
    String? supplierName,
    required String visionModel,
  }) async {
    // Make sure we have bytes if a URL was provided.
    Uint8List? bytes = imageBytes;
    if ((bytes == null || bytes.isEmpty) &&
        imageUrl != null &&
        imageUrl.trim().isNotEmpty) {
      bytes = await _downloadImageBytes(imageUrl.trim());
    }

    final hintLines = <String>[
      'titulo_crudo: ${rawTitle.trim()}',
      if (supplierName != null && supplierName.trim().isNotEmpty)
        'proveedor: ${supplierName.trim()}',
    ];

    final prompt = '''
Eres el catalogador de una bicicleteria chilena. Tu trabajo es convertir
titulos crudos y ruidosos de proveedores (AliExpress, eBay, etc.) en
nombres limpios y vendibles para el catalogo local de la tienda.

Recibiras el titulo crudo del proveedor y, cuando sea posible, una foto
real del producto. Si la foto y el titulo se contradicen, PRIORIZA la
foto.

Devuelve SOLO JSON valido con esta forma exacta:
{
  "cleaned_name": "Postiza ZTTO 001",
  "component_type": "postiza",
  "brand": "ZTTO",
  "model": "001",
  "category_name": "Postizas",
  "confidence": 0.92,
  "vision": {
    "primary_type": "postiza",
    "catalog_terms": ["postiza", "gancho de cambio", "ztto"],
    "excluded_terms": ["cadena", "cassette"],
    "confidence": 0.88
  }
}

Reglas duras:
- cleaned_name debe ser corto (<= 60 caracteres) y con formato:
  "<Componente en singular> <Marca opcional> <Modelo/Spec opcional>".
  Ejemplos buenos:
    * "Postiza ZTTO 001"
    * "Polea jockey ceramica 14T"
    * "Pastillas freno hidraulico Shimano B01S"
    * "Cassette Shimano HG200 9v 11-32T"
  Ejemplos malos (evitar): "ZTTO 001 Postiza para MTB Bicicleta de Montana
  Aluminio CNC Mecanizado de Alta Calidad Compatible con Shimano SRAM..."
- Usa vocabulario chileno de bicicleteria: postiza (no "gancho de cambio"),
  polea (no "rueda guia"), plato (no "chainring"), piola (no "cable"),
  pastilla (no "pad"), camara (no "tubo"), llanta (no "aro" cuando hablamos
  de la rueda completa), tripa/tubeless cuando aplica.
- IMPORTANTE: NO incluyas cantidad de empaque ni multiplicadores en el
  nombre. Quita expresiones como "Set 5", "5 pares", "100 unidades",
  "(50 unidades)", "pack 10", "x4", "4pcs", "kit 3". El nombre describe
  UNA unidad del producto. Si el producto es naturalmente plural
  ("Pastillas de freno", "Pernos"), conserva esa forma sin numeros.
- component_type debe ser un sustantivo singular en minusculas, util como
  filtro de categoria (ej: "postiza", "polea", "plato", "pastillas freno",
  "cassette", "cadena", "manilla", "desviador", "cambio trasero").
- En Chile, "potencia", "tee" y "stem" nombran el mismo componente. Usa
  SIEMPRE component_type "tee", cleaned_name comenzando por "Tee" y
  category_name "Tee" para cualquiera de esos sinonimos.
- Un adaptador Presta/FV/VF a Schrader/AV/VA es un "adaptador de valvula" y
  category_name "Adaptadores". NO es una valvula tubeless. Usa "Válvula
  Tubeless" solamente cuando el titulo o la foto indiquen tubeless de forma
  explicita.
- brand y model son opcionales; SOLO incluyelos si el FABRICANTE es claramente
  visible en la foto o explicitamente nombrado como marca en el titulo. Frases
  como "compatible con Shimano/SRAM", "para Shimano" o "works with Shimano"
  describen compatibilidad y JAMAS prueban la marca. Si el titulo dice IXF y
  luego "compatible con Shimano", brand debe ser "IXF", nunca "Shimano".
  NO inventes marca.
- category_name debe ser una categoria humana en plural ("Postizas",
  "Poleas", "Pastillas de freno", "Cassettes", "Cadenas", "Cambios
  traseros"). Sirve para sugerir la categoria de catalogo.
- confidence entre 0 y 1.
- vision describe SOLO lo que se ve en la FOTO, ignorando el titulo. Es la
  respuesta a "que objeto es esto", no a "de que habla el texto".
  * vision.primary_type: el objeto fisico, sustantivo corto y concreto.
  * vision.catalog_terms: 3 a 8 terminos cortos para buscarlo en un catalogo.
  * vision.excluded_terms: familias claramente distintas que la foto descarta.
  * vision.confidence entre 0 y 1; si NO hay foto o no se distingue el objeto,
    usa 0 y deja primary_type vacio. No adivines desde el titulo.
  * El titulo puede nombrar el SISTEMA al que sirve la pieza ("herradura de
    freno", "maza para freno de disco"). vision.primary_type debe ser la PIEZA
    que se ve, jamas el sistema nombrado en el texto.
- NO escribas nada fuera del JSON.

Contexto:
${hintLines.join('\n')}
''';

    try {
      final parts = <Map<String, dynamic>>[
        {'text': prompt},
      ];
      if (bytes != null && bytes.isNotEmpty) {
        final prepared = _prepareImageForGemini(bytes);
        parts.add({
          'inlineData': {
            'mimeType': prepared.mimeType,
            'data': base64Encode(prepared.bytes),
          },
        });
      }

      final response = await _geminiProxy.generateContent(
        model: visionModel,
        contents: [
          {'role': 'user', 'parts': parts},
        ],
      );

      final rawText = response.text.trim();
      if (rawText.isEmpty) return null;

      final jsonBlock = _extractJsonObject(rawText);
      if (jsonBlock == null) {
        _debugAi('⚠️ [AI] Clean product title returned invalid output.');
        return null;
      }

      final decoded = jsonDecode(jsonBlock);
      if (decoded is! Map<String, dynamic>) return null;

      String coerce(Object? v, {int max = 80}) {
        if (v == null) return '';
        var s = v.toString().trim();
        if (s.isEmpty) return '';
        s = s.replaceAll(RegExp(r'\s+'), ' ');
        if (s.length > max) s = s.substring(0, max).trim();
        return s;
      }

      final cleanedName = coerce(decoded['cleaned_name'], max: 80);
      final componentType =
          coerce(decoded['component_type'], max: 40).toLowerCase();
      final brand = coerce(decoded['brand'], max: 40);
      final model = coerce(decoded['model'], max: 40);
      final categoryName = coerce(decoded['category_name'], max: 60);
      final confidence = _coerceAnalysisConfidence(decoded['confidence']);

      if (cleanedName.isEmpty || componentType.isEmpty) return null;

      final result = AICleanedProductName(
        cleanedName: cleanedName,
        componentType: componentType,
        brand: brand.isEmpty ? null : brand,
        model: model.isEmpty ? null : model,
        categoryName: categoryName.isEmpty ? null : categoryName,
        confidence: confidence,
        visualAnalysis: _visualAnalysisFromCleanerBlock(
          decoded['vision'],
          hadImage: bytes != null && bytes.isNotEmpty,
        ),
      );

      return result;
    } catch (_) {
      _debugAi('❌ [AI] Clean product title failed.');
      return null;
    }
  }

  /// The photo half of a cleaner answer, or `null` when there is nothing to
  /// read. A block invented without an image is refused rather than trusted:
  /// with no picture, the model can only be paraphrasing the title, and the
  /// whole point of this evidence is that it is independent of it.
  AIProductImageAnalysis? _visualAnalysisFromCleanerBlock(
    Object? raw, {
    required bool hadImage,
  }) {
    if (!hadImage || raw is! Map) return null;
    final primaryType = _normalizeImageAnalysisTerm(
      raw['primary_type']?.toString(),
    );
    final catalogTerms = _normalizeImageAnalysisTerms(raw['catalog_terms']);
    if (primaryType.isEmpty && catalogTerms.isEmpty) return null;
    final confidence = _coerceAnalysisConfidence(raw['confidence']);
    if (confidence <= 0) return null;
    return AIProductImageAnalysis(
      primaryType: primaryType,
      catalogTerms: <String>{
        if (primaryType.isNotEmpty) primaryType,
        ...catalogTerms,
      }.toList(growable: false),
      excludedTerms: _normalizeImageAnalysisTerms(raw['excluded_terms']),
      confidence: confidence,
      visualSummary: _normalizeImageAnalysisTerm(
        raw['visual_summary']?.toString(),
        maxWords: 12,
      ),
    );
  }

  Future<Uint8List?> _downloadImageBytes(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }

    final client = _imageHttpClientFactory();
    try {
      return await _downloadImageBytesWithClient(client, uri)
          .timeout(_imageDownloadTimeout);
    } on TimeoutException {
      _debugAi('⚠️ [AI] Image download timed out.');
      return null;
    } catch (_) {
      _debugAi('❌ [AI] Image download failed.');
      return null;
    } finally {
      client.close();
    }
  }

  Future<Uint8List?> _downloadImageBytesWithClient(
    http.Client client,
    Uri uri,
  ) async {
    final response = await client.send(http.Request('GET', uri));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _debugAi('⚠️ [AI] Image download failed (${response.statusCode}).');
      return null;
    }

    final declaredLength =
        int.tryParse(response.headers['content-length']?.trim() ?? '');
    if (declaredLength != null && declaredLength > _maxDownloadedImageBytes) {
      _debugAi('⚠️ [AI] Image download exceeded the size limit.');
      return null;
    }

    final contentType = (response.headers['content-type'] ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    final hasPermittedContentType = contentType.isEmpty ||
        contentType.startsWith('image/') ||
        contentType == 'application/octet-stream';
    if (!hasPermittedContentType) {
      _debugAi('⚠️ [AI] Image download returned non-image content.');
      return null;
    }

    final body = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (body.length + chunk.length > _maxDownloadedImageBytes) {
        _debugAi('⚠️ [AI] Image download exceeded the size limit.');
        return null;
      }
      body.add(chunk);
    }

    final bytes = body.takeBytes();
    if (bytes.isEmpty) {
      _debugAi('⚠️ [AI] Image download was empty.');
      return null;
    }
    if (!_looksLikeDownloadedImage(bytes)) {
      _debugAi('⚠️ [AI] Image download returned non-image content.');
      return null;
    }
    return bytes;
  }

  bool _looksLikeDownloadedImage(Uint8List bytes) {
    if (bytes.lengthInBytes < 4) return false;
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    final isPng = bytes.lengthInBytes >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final isGif = bytes.lengthInBytes >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46;
    final isWebp = bytes.lengthInBytes >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return isJpeg || isPng || isGif || isWebp;
  }

  String _imageBytesCacheKey(Uint8List bytes) {
    var hash = 0;
    final stride = math.max(1, bytes.lengthInBytes ~/ 96);
    for (var index = 0; index < bytes.lengthInBytes; index += stride) {
      hash = (hash * 31 + bytes[index]) & 0x7fffffff;
    }
    return 'b:${bytes.lengthInBytes}:$hash';
  }

  @override
  Future<AIAssistantResponse> sendMessage(
    String message, {
    List<MechanicJob>? jobs,
    CustomerService? customerService,
    InventoryService? inventoryService,
    BikeshopService? bikeshopService,
    bool jobsAreCurrentView = false,
    String? jobSummaryScopeLabel,
    PurchaseService? purchaseService,
    SalesService? salesService,
    bool allowJobCacheFallback = true,
    bool visibleJobsSourceUnavailable = false,
    TaskService? taskService,
    required AIAssistantTurnAuthority authority,
  }) async {
    _isLoading = true;
    notifyListeners();
    final agentTurnStopwatch = Stopwatch()..start();

    try {
      final toolAuthority = AIToolAuthority(
        userId: authority.scope.userId,
        tenantId: authority.scope.tenantId,
        role: authority.role,
        permissions: authority.permissions,
      );
      final canReadOperations = toolAuthority.hasEveryPermission(
        const <String>{AIToolPermission.operationalRead},
      );

      // Ahead of the job summary and ahead of the model: the operational
      // briefing is answered from the read model or not at all.
      final horizon = detectAttentionHorizon(message);
      if (horizon != null && canReadOperations) {
        final report = await const AIAttentionReadModel()
            .build(
              horizon: horizon,
              authority: authority,
              bikeshopService: bikeshopService,
              taskService: taskService,
            )
            .timeout(_remainingAgentTurnBudget(agentTurnStopwatch));
        return _recordDeterministic(
          message,
          _attentionResponse(report),
        );
      }

      if (visibleJobsSourceUnavailable && canReadOperations) {
        // The caller published rows it could not vouch for. Answering "no
        // encontré trabajos" here would report a verified zero from a source
        // that was never read, so the engine declines the job path instead.
        final unavailable = _tryHandleJobSummaryUnavailable(message);
        if (unavailable != null) {
          return _recordDeterministic(message, unavailable);
        }
      }

      final jobSummaryResponse = canReadOperations
          ? await _tryHandleJobSummary(
              message,
              jobs: jobs,
              customerService: customerService,
              bikeshopService: bikeshopService,
              jobsAreCurrentView: jobsAreCurrentView,
              jobSummaryScopeLabel: jobSummaryScopeLabel,
              allowJobCacheFallback: allowJobCacheFallback,
              authority: authority,
            ).timeout(_remainingAgentTurnBudget(agentTurnStopwatch))
          : null;
      if (jobSummaryResponse != null) {
        return _recordDeterministic(message, jobSummaryResponse);
      }

      final entityCardResponse = await _tryHandleEntityCards(
        message,
        customerService: customerService,
        bikeshopService: bikeshopService,
        purchaseService: purchaseService,
        salesService: salesService,
        authority: authority,
      ).timeout(_remainingAgentTurnBudget(agentTurnStopwatch));
      if (entityCardResponse != null) {
        return _recordDeterministic(message, entityCardResponse);
      }

      final inventoryRefinement = canReadOperations
          ? _tryHandleInventoryRefinement(
              message,
              inventoryService: inventoryService,
            )
          : null;
      if (inventoryRefinement != null) {
        return _recordDeterministic(
          message,
          _textResponse(inventoryRefinement),
        );
      }

      final inventoryComparison =
          canReadOperations ? _tryHandleInventoryComparison(message) : null;
      if (inventoryComparison != null) {
        return _recordDeterministic(
          message,
          _textResponse(inventoryComparison),
        );
      }

      final directInventorySearch = canReadOperations
          ? await _tryHandleDirectInventorySearch(
              message,
              inventoryService: inventoryService,
              authority: authority,
            ).timeout(_remainingAgentTurnBudget(agentTurnStopwatch))
          : null;
      if (directInventorySearch != null) {
        return _recordDeterministic(message, directInventorySearch);
      }

      initialize();

      const toolPolicy = AIAssistantRuntimeToolPolicy();
      final toolRegistry = AIToolRegistry(
        policy: toolPolicy,
        registrations: <AIToolRegistration>[
          ...buildAIAssistantReadToolRegistrations(
            searchInventory: (query) => _toolSearchStock(
              query,
              inventoryService,
              authority,
            ),
            researchPublicWeb: _toolSearchInternet,
          ),
          ...buildAIOperationalReadToolRegistrations(
            listAttentionItems: (horizon, callbackAuthority) =>
                const AIAttentionReadModel().build(
              horizon: horizon,
              authority: _turnAuthorityFromTool(callbackAuthority),
              bikeshopService: bikeshopService,
              taskService: taskService,
              now: _now(),
            ),
          ),
          ...buildAIBusinessReadToolRegistrations(
            searchWorkshopJobs: (request, callbackAuthority) =>
                _toolSearchWorkshopJobs(
              request,
              callbackAuthority,
              customerService: customerService,
              bikeshopService: bikeshopService,
            ),
            searchTasks: (request, callbackAuthority) => _toolSearchTasks(
              request,
              callbackAuthority,
              taskService: taskService,
            ),
            searchCustomers: (request, callbackAuthority) =>
                _toolSearchCustomers(
              request,
              callbackAuthority,
              customerService: customerService,
            ),
            searchSuppliers: (request, callbackAuthority) =>
                _toolSearchSuppliers(
              request,
              callbackAuthority,
              purchaseService: purchaseService,
            ),
            searchSalesInvoices: (request, callbackAuthority) =>
                _toolSearchSalesInvoices(
              request,
              callbackAuthority,
              salesService: salesService,
            ),
            searchPurchaseInvoices: (request, callbackAuthority) =>
                _toolSearchPurchaseInvoices(
              request,
              callbackAuthority,
              purchaseService: purchaseService,
            ),
          ),
        ],
      );
      final modelTools = toolRegistry
          .advertisedToolsFor(toolAuthority)
          .map(
            (tool) => AIAgentModelTool(
              name: tool.name,
              description: tool.description,
              inputSchema: tool.inputSchema,
            ),
          )
          .toList(growable: false);

      final workingHistory = _boundedCanonicalHistory(_history);
      final systemPrompt = _buildSystemPrompt(
        canReadOperations
            ? jobs ?? const <MechanicJob>[]
            : const <MechanicJob>[],
      );
      workingHistory.add(AIAgentMessage.user(message));
      final turnId = 'turn-${++_turnSequence}';
      final clientRequestId = _idFactory();
      final runSessionIdHash = AIAgentAuditHash.sha256OfUtf8(_sessionId);
      var modelStep = 0;
      final toolCards = <AIAssistantActionCard>[];
      var response = await _completeModelTurn(
        request: AIAgentProviderRequest(
          turnId: '$turnId/model-${modelStep++}',
          modelRole: AIAgentModelRole.fast,
          instructions: systemPrompt,
          messages: List<AIAgentMessage>.unmodifiable(workingHistory),
          tools: modelTools,
        ),
        turnId: turnId,
        clientRequestId: clientRequestId,
        sessionIdHash: runSessionIdHash,
        timeout: _remainingAgentTurnBudget(agentTurnStopwatch),
      );

      // Handle Tool Calls (Recursively if needed)
      int maxTurns = 5;
      var totalToolCalls = 0;
      while (response.toolCalls.isNotEmpty && maxTurns > 0) {
        maxTurns--;
        final functionCalls = response.toolCalls;
        if (totalToolCalls + functionCalls.length > _maxToolCallsPerTurn) {
          const limitMessage =
              'Pude avanzar con las consultas, pero el turno llegó a su límite '
              'seguro de herramientas. Repite la parte que falta en una '
              'solicitud más acotada.';
          workingHistory.add(
            const AIAgentMessage.assistant(text: limitMessage),
          );
          _replaceCanonicalHistory(workingHistory);
          return _textResponse(limitMessage, cards: toolCards);
        }
        totalToolCalls += functionCalls.length;
        final functionResponses = <AIAgentToolOutput>[];
        Map<String, Object?>? inventorySearchResult;
        var turnLimitReached = false;

        workingHistory.add(
          AIAgentMessage.assistant(
            text: response.text,
            toolCalls: functionCalls,
          ),
        );

        for (final call in functionCalls) {
          final name = call.name;
          final args = call.arguments;

          Map<String, Object?> result;
          if (turnLimitReached) {
            final rejection = toolRegistry.rejectForTurnLimit(
              toolName: name,
              authority: toolAuthority,
            );
            result = <String, Object?>{
              'status': 'rejected',
              'errorCode': rejection.code.name,
              'message': rejection.message,
            };
            await _recordToolAudit(
              response: response,
              turnId: turnId,
              clientRequestId: clientRequestId,
              sessionIdHash: runSessionIdHash,
              call: call,
              receipt: rejection.receipt,
              input: args,
              output: null,
            );
          } else {
            try {
              final executionTimeout =
                  _remainingAgentTurnBudget(agentTurnStopwatch);
              final executionFuture = toolRegistry.execute(
                toolName: name,
                arguments: args,
                authority: toolAuthority,
                executionTimeout: executionTimeout,
              );
              final execution = await executionFuture;
              result = execution.data;
              await _recordToolAudit(
                response: response,
                turnId: turnId,
                clientRequestId: clientRequestId,
                sessionIdHash: runSessionIdHash,
                call: call,
                receipt: execution.receipt,
                input: args,
                output: result,
              );
              if (name == AIAssistantReadToolNames.searchInventory) {
                inventorySearchResult = result;
              }
              _appendUniqueToolCards(
                toolCards,
                _cardsForToolResult(name, result),
              );
            } on TimeoutException {
              turnLimitReached = true;
              final rejection = toolRegistry.rejectForTurnLimit(
                toolName: name,
                authority: toolAuthority,
              );
              result = <String, Object?>{
                'status': 'rejected',
                'errorCode': rejection.code.name,
                'message': rejection.message,
              };
              await _recordToolAudit(
                response: response,
                turnId: turnId,
                clientRequestId: clientRequestId,
                sessionIdHash: runSessionIdHash,
                call: call,
                receipt: rejection.receipt,
                input: args,
                output: null,
              );
            } on AIToolExecutionException catch (error) {
              if (error.code == AIToolFailureCode.timeout ||
                  error.code == AIToolFailureCode.turnLimitExceeded) {
                turnLimitReached = true;
              }
              result = <String, Object?>{
                'status': 'rejected',
                'errorCode': error.code.name,
                'message': error.message,
              };
              await _recordToolAudit(
                response: response,
                turnId: turnId,
                clientRequestId: clientRequestId,
                sessionIdHash: runSessionIdHash,
                call: call,
                receipt: error.receipt,
                input: args,
                output: null,
              );
            }
          }

          functionResponses.add(
            AIAgentToolOutput(
              callId: call.id,
              name: name,
              output: result,
            ),
          );
        }

        // The tool results close the call the model just made. They are
        // appended before anything can return, because a history whose last
        // model turn is a functionCall with no matching functionResponse is
        // malformed, and the next turn sends it back to Gemini exactly as it
        // was left.
        workingHistory.add(AIAgentMessage.tool(functionResponses));

        if (turnLimitReached) {
          const limitMessage =
              'Pude avanzar con las consultas, pero el turno llegó a su límite '
              'seguro de herramientas. Repite la parte que falta en una '
              'solicitud más acotada.';
          workingHistory.add(
            const AIAgentMessage.assistant(text: limitMessage),
          );
          _replaceCanonicalHistory(workingHistory);
          return _textResponse(limitMessage, cards: toolCards);
        }

        // No auto-navigation. A search used to move the operator's active
        // workspace on its own, which could replace an unrelated surface they
        // were working in. The reply offers a card; the click is theirs.
        final deterministicInventoryReply = _buildDeterministicInventoryReply(
          inventorySearchResult,
        );
        if (deterministicInventoryReply != null) {
          _replaceCanonicalHistory(<AIAgentMessage>[
            ...workingHistory,
            AIAgentMessage.assistant(text: deterministicInventoryReply),
          ]);
          return _cardResponse(
            deterministicInventoryReply,
            cards: <AIAssistantActionCard>[
              ...toolCards,
              ..._buildInventoryCardsFromSearchResult(inventorySearchResult),
            ],
          );
        }

        response = await _completeModelTurn(
          request: AIAgentProviderRequest(
            turnId: '$turnId/model-${modelStep++}',
            modelRole: AIAgentModelRole.fast,
            instructions: systemPrompt,
            messages: List<AIAgentMessage>.unmodifiable(workingHistory),
            tools: modelTools,
          ),
          turnId: turnId,
          clientRequestId: clientRequestId,
          sessionIdHash: runSessionIdHash,
          timeout: _remainingAgentTurnBudget(agentTurnStopwatch),
        );
      }

      if (response.toolCalls.isNotEmpty) {
        const limitMessage =
            'Pude avanzar con las consultas, pero el turno llegó a su límite '
            'seguro de herramientas. Repite la parte que falta en una solicitud '
            'más acotada.';
        workingHistory.add(
          const AIAgentMessage.assistant(text: limitMessage),
        );
        _replaceCanonicalHistory(workingHistory);
        return _textResponse(limitMessage, cards: toolCards);
      }

      final text = response.text.trim();

      if (text.isEmpty) {
        return _textResponse(
          'No pude generar una respuesta útil esta vez. Intenta reformular '
          'la solicitud.',
        );
      }

      workingHistory.add(AIAgentMessage.assistant(text: text));

      _replaceCanonicalHistory(workingHistory);

      return _textResponse(text, cards: toolCards);
    } on AIAssistantSourceUnavailable {
      // Never degraded into "no encontré nada": an empty answer and an
      // unverifiable one mean opposite things at the counter.
      _debugAi('⛔ [AI] An authority-bound source was unavailable.');
      return _recordDeterministic(
        message,
        _textResponse(
          'No pude responder eso con datos verificados de este taller. La '
          'fuente que necesitaba no se pudo confirmar, así que preferí no '
          'darte una cifra. Vuelve a intentarlo en unos segundos.',
        ),
      );
    } on TimeoutException {
      _debugAi('⚠️ [AI] The assistant turn reached its safe time limit.');
      return _recordDeterministic(
        message,
        _textResponse(
          'La consulta tomó más de lo seguro para un solo turno. Intenta de '
          'nuevo con una parte más acotada.',
        ),
      );
    } on GeminiProxyException catch (e) {
      _debugAi('⚠️ [AI] The configured model provider is unavailable.');
      return _textResponse(_friendlyGeminiErrorMessage(e));
    } catch (_) {
      _debugAi('⚠️ [AI] The assistant turn failed.');
      return _textResponse(
        'No pude procesar esa solicitud ahora. Intenta de nuevo en unos segundos.',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<AIAgentProviderTurn> _completeModelTurn({
    required AIAgentProviderRequest request,
    required String turnId,
    required String clientRequestId,
    required AIAgentAuditHash sessionIdHash,
    required Duration timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _modelProvider.complete(request).timeout(timeout);
      stopwatch.stop();
      await _safeRecordAudit(
        () => AIAgentAuditEvent(
          occurredAt: DateTime.now().toUtc(),
          kind: AIAgentAuditEventKind.modelInvocation,
          sessionIdHash: sessionIdHash,
          turnIdHash: AIAgentAuditHash.sha256OfUtf8(turnId),
          clientRequestIdHash: AIAgentAuditHash.sha256OfUtf8(clientRequestId),
          modelRole: request.modelRole,
          provider: response.provider,
          model: response.model,
          decision: AIAgentAuditDecision.notApplicable,
          status: AIAgentAuditStatus.succeeded,
          duration: stopwatch.elapsed,
          inputHash: AIAgentAuditHash.hmacSha256OfJson(
            key: _auditHmacKey,
            value: _providerRequestAuditPayload(request),
          ),
          outputHash: AIAgentAuditHash.hmacSha256OfJson(
            key: _auditHmacKey,
            value: _providerTurnAuditPayload(response),
          ),
        ),
      );
      return response;
    } on TimeoutException {
      stopwatch.stop();
      await _safeRecordAudit(
        () => AIAgentAuditEvent(
          occurredAt: DateTime.now().toUtc(),
          kind: AIAgentAuditEventKind.modelInvocation,
          sessionIdHash: sessionIdHash,
          turnIdHash: AIAgentAuditHash.sha256OfUtf8(turnId),
          clientRequestIdHash: AIAgentAuditHash.sha256OfUtf8(clientRequestId),
          modelRole: request.modelRole,
          provider: _modelProvider.providerId,
          model: 'unresolved',
          decision: AIAgentAuditDecision.notApplicable,
          status: AIAgentAuditStatus.timedOut,
          duration: stopwatch.elapsed,
          inputHash: AIAgentAuditHash.hmacSha256OfJson(
            key: _auditHmacKey,
            value: _providerRequestAuditPayload(request),
          ),
        ),
      );
      rethrow;
    } catch (_) {
      stopwatch.stop();
      await _safeRecordAudit(
        () => AIAgentAuditEvent(
          occurredAt: DateTime.now().toUtc(),
          kind: AIAgentAuditEventKind.modelInvocation,
          sessionIdHash: sessionIdHash,
          turnIdHash: AIAgentAuditHash.sha256OfUtf8(turnId),
          clientRequestIdHash: AIAgentAuditHash.sha256OfUtf8(clientRequestId),
          modelRole: request.modelRole,
          provider: _modelProvider.providerId,
          model: 'unresolved',
          decision: AIAgentAuditDecision.notApplicable,
          status: AIAgentAuditStatus.failed,
          duration: stopwatch.elapsed,
          inputHash: AIAgentAuditHash.hmacSha256OfJson(
            key: _auditHmacKey,
            value: _providerRequestAuditPayload(request),
          ),
        ),
      );
      rethrow;
    }
  }

  Future<void> _recordToolAudit({
    required AIAgentProviderTurn response,
    required String turnId,
    required String clientRequestId,
    required AIAgentAuditHash sessionIdHash,
    required AIAgentToolCall call,
    required AIToolReceipt receipt,
    required Map<String, Object?> input,
    required Map<String, Object?>? output,
  }) {
    final status = switch (receipt.status) {
      AIToolReceiptStatus.succeeded => AIAgentAuditStatus.succeeded,
      AIToolReceiptStatus.rejected => AIAgentAuditStatus.rejected,
      AIToolReceiptStatus.timedOut => AIAgentAuditStatus.timedOut,
      AIToolReceiptStatus.failed => AIAgentAuditStatus.failed,
    };
    final failureCode = receipt.failureCode;
    final isPolicyRejection = switch (failureCode) {
      AIToolFailureCode.approvalRequired ||
      AIToolFailureCode.unknownTool ||
      AIToolFailureCode.unauthorized ||
      AIToolFailureCode.invalidArguments ||
      AIToolFailureCode.idempotencyKeyRequired ||
      AIToolFailureCode.concurrentExecutionDenied ||
      AIToolFailureCode.turnLimitExceeded =>
        true,
      _ => false,
    };
    final decision = switch (failureCode) {
      AIToolFailureCode.approvalRequired =>
        AIAgentAuditDecision.approvalRequired,
      AIToolFailureCode.unknownTool ||
      AIToolFailureCode.unauthorized ||
      AIToolFailureCode.invalidArguments ||
      AIToolFailureCode.idempotencyKeyRequired ||
      AIToolFailureCode.concurrentExecutionDenied =>
        AIAgentAuditDecision.denied,
      _ => AIAgentAuditDecision.allowed,
    };

    return _safeRecordAudit(
      () => AIAgentAuditEvent(
        occurredAt: receipt.completedAt,
        kind: isPolicyRejection
            ? AIAgentAuditEventKind.toolPolicyDecision
            : AIAgentAuditEventKind.toolExecution,
        sessionIdHash: sessionIdHash,
        turnIdHash: AIAgentAuditHash.sha256OfUtf8(turnId),
        clientRequestIdHash: AIAgentAuditHash.sha256OfUtf8(clientRequestId),
        toolCallIdHash: AIAgentAuditHash.sha256OfUtf8(call.id),
        modelRole: AIAgentModelRole.fast,
        provider: response.provider,
        model: response.model,
        toolId: receipt.toolName,
        toolVersion: receipt.toolVersion,
        risk: receipt.risk,
        decision: decision,
        status: status,
        duration:
            receipt.duration.isNegative ? Duration.zero : receipt.duration,
        inputHash: AIAgentAuditHash.hmacSha256OfJson(
          key: _auditHmacKey,
          value: input,
        ),
        outputHash: output == null
            ? null
            : AIAgentAuditHash.hmacSha256OfJson(
                key: _auditHmacKey,
                value: output,
              ),
      ),
    );
  }

  Future<void> _safeRecordAudit(AIAgentAuditEvent Function() buildEvent) async {
    try {
      await _auditSink.record(buildEvent()).timeout(_maxAuditRecordDuration);
    } catch (_) {
      // Event construction and sinks are deliberately outside the critical
      // path. No exception or stack is retained because either may contain a
      // provider payload.
    }
  }

  Map<String, Object?> _providerRequestAuditPayload(
    AIAgentProviderRequest request,
  ) {
    return <String, Object?>{
      'modelRole': request.modelRole.name,
      'instructions': request.instructions,
      'messages': <Object?>[
        for (final message in request.messages)
          <String, Object?>{
            'role': message.role.name,
            'text': message.text,
            'toolCalls': <Object?>[
              for (final call in message.toolCalls)
                <String, Object?>{
                  'id': call.id,
                  'name': call.name,
                  'arguments': call.arguments,
                },
            ],
            'toolOutputs': <Object?>[
              for (final output in message.toolOutputs)
                <String, Object?>{
                  'callId': output.callId,
                  'name': output.name,
                  'output': output.output,
                },
            ],
          },
      ],
      'tools': <Object?>[
        for (final tool in request.tools)
          <String, Object?>{
            'name': tool.name,
            'description': tool.description,
            'inputSchema': tool.inputSchema,
          },
      ],
    };
  }

  Map<String, Object?> _providerTurnAuditPayload(AIAgentProviderTurn turn) {
    return <String, Object?>{
      'text': turn.text,
      'toolCalls': <Object?>[
        for (final call in turn.toolCalls)
          <String, Object?>{
            'id': call.id,
            'name': call.name,
            'arguments': call.arguments,
          },
      ],
      'finishReason': turn.finishReason,
    };
  }

  AIAssistantTurnAuthority _turnAuthorityFromTool(
    AIToolAuthority authority,
  ) {
    return AIAssistantTurnAuthority(
      ErpAuthorityScopeKey(
        userId: authority.userId,
        tenantId: authority.tenantId,
      ),
      role: authority.role,
      permissions: authority.permissions,
    );
  }

  Future<AIBusinessReadToolResult> _toolSearchWorkshopJobs(
    AIBusinessReadRequest request,
    AIToolAuthority toolAuthority, {
    required CustomerService? customerService,
    required BikeshopService? bikeshopService,
  }) async {
    if (bikeshopService == null) {
      return const AIBusinessReadToolResult.unavailable();
    }
    final authority = _turnAuthorityFromTool(toolAuthority);
    if (bikeshopService.hasJobsCache) {
      authority.requireServiceScope('taller', bikeshopService.authorityScope);
    }
    final loaded = bikeshopService.hasJobsCache
        ? bikeshopService.cachedJobs
        : await bikeshopService.getJobs();
    authority.requireServiceScope('taller', bikeshopService.authorityScope);
    final jobs = authority.verifyRows(
      'taller',
      loaded,
      (job) => job.tenantId,
    );

    final customerNames = <String, String>{};
    if (customerService != null) {
      final customers = await _loadCustomersForAi(customerService, authority);
      for (final customer in customers) {
        final id = customer.id;
        if (id != null) customerNames[id] = customer.name;
      }
    }

    final query = _businessQueryFilter(request.query);
    final matches = jobs.where((job) {
      return _matchesSearchAcrossFields(query, <String?>[
        _jobCardTitle(job),
        customerNames[job.customerId],
        _jobStatusLabel(job),
        job.status.name,
        job.priority.displayName,
        job.priority.name,
        job.clientRequest,
        job.diagnosis,
        job.workPerformed,
        job.assignedTechnicianName,
      ]);
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final items = <Map<String, Object?>>[
      for (final job in matches.take(request.limit))
        <String, Object?>{
          'jobNumber': _jobCardTitle(job),
          'customerName': customerNames[job.customerId],
          'status': _jobStatusLabel(job),
          'priority': job.priority.displayName,
          'arrivalDate': job.arrivalDate.toIso8601String(),
          'deliveryDeadline': job.deliveryDeadline?.toIso8601String(),
          'clientRequest': _boundedToolText(job.clientRequest),
          'assignedTechnicianName':
              _boundedToolText(job.assignedTechnicianName, maxLength: 120),
        },
    ];
    return _businessResult(items);
  }

  Future<AIBusinessReadToolResult> _toolSearchTasks(
    AIBusinessReadRequest request,
    AIToolAuthority toolAuthority, {
    required TaskService? taskService,
  }) async {
    if (taskService == null) {
      return const AIBusinessReadToolResult.unavailable();
    }
    final authority = _turnAuthorityFromTool(toolAuthority);
    final loadedScope = await taskService.fetchTasksForPreload();
    if (loadedScope == null) {
      return const AIBusinessReadToolResult.unavailable();
    }
    authority.requireServiceScope('tareas', taskService.authorityScope);
    final tasks = authority.verifyRows(
      'tareas',
      taskService.tasks,
      (task) => task.tenantId,
    );
    final query = _businessQueryFilter(request.query);
    final matches = tasks.where((task) {
      return _matchesSearchAcrossFields(query, <String?>[
        task.title,
        task.description,
        _taskStatusLabel(task.status),
        task.status.name,
        _taskPriorityLabel(task.priority),
        task.priority.name,
        task.assigneeName,
        _taskLinkedContext(task),
      ]);
    }).toList()
      ..sort((a, b) {
        final aDue = a.dueDate;
        final bDue = b.dueDate;
        if (aDue != null && bDue != null) return aDue.compareTo(bDue);
        if (aDue != null) return -1;
        if (bDue != null) return 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });

    final items = <Map<String, Object?>>[
      for (final task in matches.take(request.limit))
        <String, Object?>{
          'title': _boundedToolText(task.title, maxLength: 180),
          'status': _taskStatusLabel(task.status),
          'priority': _taskPriorityLabel(task.priority),
          'dueDate': task.dueDate?.toIso8601String(),
          'assigneeName': _boundedToolText(task.assigneeName, maxLength: 120),
          'linkedContext':
              _boundedToolText(_taskLinkedContext(task), maxLength: 160),
        },
    ];
    return _businessResult(items);
  }

  Future<AIBusinessReadToolResult> _toolSearchCustomers(
    AIBusinessReadRequest request,
    AIToolAuthority toolAuthority, {
    required CustomerService? customerService,
  }) async {
    if (customerService == null) {
      return const AIBusinessReadToolResult.unavailable();
    }
    final authority = _turnAuthorityFromTool(toolAuthority);
    final customers = await _loadCustomersForAi(customerService, authority);
    if (customers.isEmpty) {
      // CustomerService publishes no authority receipt. With zero rows there
      // is nothing to verify, so an empty result cannot be attributed to this
      // tenant yet.
      return const AIBusinessReadToolResult.unavailable();
    }
    final query = _businessQueryFilter(request.query);
    final matches = customers.where((customer) {
      return _matchesSearchAcrossFields(query, <String?>[
        customer.name,
        customer.rut,
        customer.email,
        customer.phone,
        customer.isActive ? 'activo' : 'inactivo',
      ]);
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final items = <Map<String, Object?>>[
      for (final customer in matches.take(request.limit))
        <String, Object?>{
          'name': _boundedToolText(customer.name, maxLength: 180),
          'isActive': customer.isActive,
          'updatedAt': customer.updatedAt.toIso8601String(),
        },
    ];
    return _businessResult(items);
  }

  Future<AIBusinessReadToolResult> _toolSearchSuppliers(
    AIBusinessReadRequest request,
    AIToolAuthority toolAuthority, {
    required PurchaseService? purchaseService,
  }) async {
    if (purchaseService == null) {
      return const AIBusinessReadToolResult.unavailable();
    }
    final authority = _turnAuthorityFromTool(toolAuthority);
    if (purchaseService.hasSuppliersCache) {
      authority.requireServiceScope(
        'proveedores',
        purchaseService.supplierAuthorityScope,
      );
    }
    final loaded = await purchaseService.getSuppliers();
    authority.requireServiceScope(
      'proveedores',
      purchaseService.supplierAuthorityScope,
    );
    final suppliers = authority.verifyRows(
      'proveedores',
      loaded,
      (supplier) => supplier.tenantId,
    );
    final query = _businessQueryFilter(request.query);
    final matches = suppliers.where((supplier) {
      return _matchesSearchAcrossFields(query, <String?>[
        supplier.name,
        supplier.rut,
        supplier.aliases.join(' '),
        supplier.isActive ? 'activo' : 'inactivo',
      ]);
    }).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final items = <Map<String, Object?>>[
      for (final supplier in matches.take(request.limit))
        <String, Object?>{
          'name': _boundedToolText(supplier.name, maxLength: 180),
          'isActive': supplier.isActive,
          'updatedAt': supplier.updatedAt.toIso8601String(),
        },
    ];
    return _businessResult(items);
  }

  Future<AIBusinessReadToolResult> _toolSearchSalesInvoices(
    AIBusinessReadRequest request,
    AIToolAuthority toolAuthority, {
    required SalesService? salesService,
  }) async {
    if (salesService == null) {
      return const AIBusinessReadToolResult.unavailable();
    }
    final authority = _turnAuthorityFromTool(toolAuthority);
    if (salesService.invoices.isEmpty) await salesService.loadInvoices();
    if (salesService.invoiceError != null) {
      return const AIBusinessReadToolResult.unavailable();
    }
    if (salesService.invoices.isEmpty) {
      // SalesService has no authority-bound load receipt. Do not turn an
      // unattributable empty cache into a verified business zero.
      return const AIBusinessReadToolResult.unavailable();
    }
    final invoices = authority.verifyRows(
      'facturas de venta',
      salesService.invoices,
      (invoice) => invoice.tenantId,
    );
    final query = _businessQueryFilter(request.query);
    final matches = invoices.where((invoice) {
      return _matchesSearchAcrossFields(query, <String?>[
        invoice.invoiceNumber,
        invoice.customerName,
        invoice.reference,
        _salesInvoiceStatusLabel(invoice.status),
        invoice.status.name,
        invoice.balance > 0.01 ? 'pendiente' : 'pagada',
      ]);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final items = <Map<String, Object?>>[
      for (final invoice in matches.take(request.limit))
        <String, Object?>{
          'invoiceNumber':
              _boundedToolText(invoice.invoiceNumber, maxLength: 80),
          'customerName':
              _boundedToolText(invoice.customerName, maxLength: 180),
          'status': _salesInvoiceStatusLabel(invoice.status),
          'date': invoice.date.toIso8601String(),
          'dueDate': invoice.dueDate?.toIso8601String(),
          'total': invoice.total,
          'balance': invoice.balance,
        },
    ];
    return _businessResult(items);
  }

  Future<AIBusinessReadToolResult> _toolSearchPurchaseInvoices(
    AIBusinessReadRequest request,
    AIToolAuthority toolAuthority, {
    required PurchaseService? purchaseService,
  }) async {
    if (purchaseService == null) {
      return const AIBusinessReadToolResult.unavailable();
    }
    final authority = _turnAuthorityFromTool(toolAuthority);
    final loaded = await purchaseService.getPurchaseInvoices();
    if (loaded.isEmpty) {
      // Purchase invoice reads do not yet publish an authority scope/receipt.
      return const AIBusinessReadToolResult.unavailable();
    }
    final invoices = authority.verifyRows(
      'facturas de compra',
      loaded,
      (invoice) => invoice.tenantId,
    );
    final query = _businessQueryFilter(request.query);
    final matches = invoices.where((invoice) {
      return _matchesSearchAcrossFields(query, <String?>[
        invoice.invoiceNumber,
        invoice.supplierName,
        invoice.reference,
        invoice.status.displayName,
        invoice.status.name,
        invoice.balance > 0.01 ? 'pendiente' : 'pagada',
      ]);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final items = <Map<String, Object?>>[
      for (final invoice in matches.take(request.limit))
        <String, Object?>{
          'invoiceNumber':
              _boundedToolText(invoice.invoiceNumber, maxLength: 80),
          'supplierName':
              _boundedToolText(invoice.supplierName, maxLength: 180),
          'status': invoice.status.displayName,
          'date': invoice.date.toIso8601String(),
          'dueDate': invoice.dueDate?.toIso8601String(),
          'total': invoice.total,
          'balance': invoice.balance,
        },
    ];
    return _businessResult(items);
  }

  AIBusinessReadToolResult _businessResult(
    List<Map<String, Object?>> items,
  ) {
    return items.isEmpty
        ? const AIBusinessReadToolResult.verifiedEmpty()
        : AIBusinessReadToolResult.success(items);
  }

  String _businessQueryFilter(String rawQuery) {
    const noise = <String>{
      'busca',
      'buscar',
      'muestra',
      'muestrame',
      'dame',
      'trae',
      'traeme',
      'todos',
      'todas',
      'ultimo',
      'ultima',
      'ultimos',
      'ultimas',
      'reciente',
      'recientes',
      'trabajo',
      'trabajos',
      'tarea',
      'tareas',
      'cliente',
      'clientes',
      'proveedor',
      'proveedores',
      'factura',
      'facturas',
      'venta',
      'ventas',
      'compra',
      'compras',
      'de',
      'del',
      'la',
      'las',
      'el',
      'los',
      'por',
      'para',
    };
    const singular = <String, String>{
      'pendientes': 'pendiente',
      'vencidas': 'vencida',
      'vencidos': 'vencido',
      'pagadas': 'pagada',
      'pagados': 'pagado',
      'activos': 'activo',
      'activas': 'activa',
      'inactivos': 'inactivo',
      'inactivas': 'inactiva',
      'completadas': 'completada',
      'completados': 'completado',
    };
    return _normalizeText(rawQuery)
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty && !noise.contains(token))
        .map((token) => singular[token] ?? token)
        .join(' ');
  }

  String? _boundedToolText(String? raw, {int maxLength = 240}) {
    final value = raw?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (value.isEmpty) return null;
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength - 1).trimRight()}…';
  }

  String _taskStatusLabel(TaskStatus status) => switch (status) {
        TaskStatus.pending => 'Pendiente',
        TaskStatus.inProgress => 'En curso',
        TaskStatus.completed => 'Completada',
        TaskStatus.cancelled => 'Cancelada',
      };

  String _taskPriorityLabel(TaskPriority priority) => switch (priority) {
        TaskPriority.low => 'Baja',
        TaskPriority.normal => 'Normal',
        TaskPriority.high => 'Alta',
        TaskPriority.urgent => 'Urgente',
      };

  String? _taskLinkedContext(TaskModel task) {
    for (final value in <String?>[
      task.linkedJobNumber,
      task.linkedSalesInvoiceNumber,
      task.linkedPurchaseInvoiceNumber,
      task.linkedCustomerName,
      task.linkedSupplierName,
    ]) {
      final normalized = value?.trim();
      if (normalized != null && normalized.isNotEmpty) return normalized;
    }
    return null;
  }

  List<AIAssistantActionCard> _cardsForToolResult(
    String toolName,
    Map<String, Object?> result,
  ) {
    final status = result['status'];
    final attentionResult =
        toolName == AIOperationalReadToolNames.listAttentionItems;
    if (status != 'success' && !(attentionResult && status == 'partial')) {
      return const [];
    }
    final rawItems = result['items'];
    if (rawItems is! List) return const [];
    final normalizedItems = rawItems
        .whereType<Map>()
        .map(
          (item) => item.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList(growable: false);
    if (attentionResult) return _attentionToolCards(normalizedItems);
    final items = normalizedItems.take(3).toList(growable: false);

    return switch (toolName) {
      AIBusinessReadToolNames.searchWorkshopJobs => <AIAssistantActionCard>[
          for (final item in items)
            AIAssistantActionCard(
              kind: 'job',
              eyebrow: 'Trabajo',
              title: _toolItemText(item, 'jobNumber', 'Trabajo'),
              subtitle: _joinToolCardParts(<String?>[
                _toolItemTextOrNull(item, 'customerName'),
                _toolItemTextOrNull(item, 'assignedTechnicianName'),
              ]),
              description: _toolItemTextOrNull(item, 'clientRequest'),
              destination: AIAssistantDestination.workshopJobs,
              chips: <String>[
                if (_toolItemTextOrNull(item, 'status') case final value?)
                  value,
                if (_toolItemTextOrNull(item, 'priority') case final value?)
                  value,
              ],
            ),
        ],
      AIBusinessReadToolNames.searchTasks => <AIAssistantActionCard>[
          for (final item in items)
            AIAssistantActionCard(
              kind: 'task',
              eyebrow: 'Tarea',
              title: _toolItemText(item, 'title', 'Tarea'),
              subtitle: _joinToolCardParts(<String?>[
                _toolItemTextOrNull(item, 'assigneeName'),
                _toolDateLabel(item['dueDate'], prefix: 'Vence'),
                _toolItemTextOrNull(item, 'linkedContext'),
              ]),
              destination: AIAssistantDestination.tasks,
              chips: <String>[
                if (_toolItemTextOrNull(item, 'status') case final value?)
                  value,
                if (_toolItemTextOrNull(item, 'priority') case final value?)
                  value,
              ],
            ),
        ],
      AIBusinessReadToolNames.searchCustomers => <AIAssistantActionCard>[
          for (final item in items)
            AIAssistantActionCard(
              kind: 'customer',
              eyebrow: 'Cliente',
              title: _toolItemText(item, 'name', 'Cliente'),
              destination: AIAssistantDestination.customers,
              chips: <String>[
                item['isActive'] == true ? 'Activo' : 'Inactivo',
              ],
            ),
        ],
      AIBusinessReadToolNames.searchSuppliers => <AIAssistantActionCard>[
          for (final item in items)
            AIAssistantActionCard(
              kind: 'supplier',
              eyebrow: 'Proveedor',
              title: _toolItemText(item, 'name', 'Proveedor'),
              destination: AIAssistantDestination.suppliers,
              chips: <String>[
                item['isActive'] == true ? 'Activo' : 'Inactivo',
              ],
            ),
        ],
      AIBusinessReadToolNames.searchSalesInvoices =>
        _invoiceToolCards(items, isPurchase: false),
      AIBusinessReadToolNames.searchPurchaseInvoices =>
        _invoiceToolCards(items, isPurchase: true),
      _ => const <AIAssistantActionCard>[],
    };
  }

  List<AIAssistantActionCard> _attentionToolCards(
    List<Map<String, Object?>> items,
  ) {
    final sources = items
        .map((item) => item['source']?.toString())
        .whereType<String>()
        .toSet();
    return <AIAssistantActionCard>[
      if (sources.contains(AIAttentionSource.workshop.name))
        const AIAssistantActionCard(
          kind: 'job',
          eyebrow: 'Taller',
          title: 'Revisar trabajos que requieren atención',
          destination: AIAssistantDestination.workshopJobs,
        ),
      if (sources.contains(AIAttentionSource.tasks.name))
        const AIAssistantActionCard(
          kind: 'task',
          eyebrow: 'Tareas',
          title: 'Revisar tareas que requieren atención',
          destination: AIAssistantDestination.tasks,
        ),
    ];
  }

  List<AIAssistantActionCard> _invoiceToolCards(
    List<Map<String, Object?>> items, {
    required bool isPurchase,
  }) {
    return <AIAssistantActionCard>[
      for (final item in items)
        AIAssistantActionCard(
          kind: isPurchase ? 'purchase_invoice' : 'sales_invoice',
          eyebrow: isPurchase ? 'Factura de compra' : 'Factura de venta',
          title: _toolItemText(item, 'invoiceNumber', 'Factura'),
          subtitle: _joinToolCardParts(<String?>[
            _toolItemTextOrNull(
              item,
              isPurchase ? 'supplierName' : 'customerName',
            ),
            _toolDateLabel(item['dueDate'], prefix: 'Vence'),
          ]),
          description: _joinToolCardParts(<String?>[
            _toolMoneyLabel(item['total'], prefix: 'Total'),
            _toolMoneyLabel(item['balance'], prefix: 'Saldo'),
          ]),
          destination: isPurchase
              ? AIAssistantDestination.purchases
              : AIAssistantDestination.salesInvoices,
          chips: <String>[
            if (_toolItemTextOrNull(item, 'status') case final value?) value,
          ],
        ),
    ];
  }

  String _toolItemText(
    Map<String, Object?> item,
    String key,
    String fallback,
  ) =>
      _toolItemTextOrNull(item, key) ?? fallback;

  String? _toolItemTextOrNull(Map<String, Object?> item, String key) {
    final value = item[key]?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? _joinToolCardParts(Iterable<String?> values) {
    final parts = values
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return parts.isEmpty ? null : parts.join(' • ');
  }

  String? _toolDateLabel(Object? raw, {required String prefix}) {
    final date = DateTime.tryParse(raw?.toString() ?? '');
    return date == null ? null : '$prefix ${ChileanUtils.formatDate(date)}';
  }

  String? _toolMoneyLabel(Object? raw, {required String prefix}) {
    return raw is num
        ? '$prefix ${ChileanUtils.formatCurrency(raw.toDouble())}'
        : null;
  }

  void _appendUniqueToolCards(
    List<AIAssistantActionCard> target,
    Iterable<AIAssistantActionCard> additions,
  ) {
    final seen = <String>{
      for (final card in target)
        '${card.destination.name}\u0000${card.kind}\u0000${card.title}',
    };
    for (final card in additions) {
      final key =
          '${card.destination.name}\u0000${card.kind}\u0000${card.title}';
      if (seen.add(key)) target.add(card);
      if (target.length >= 6) return;
    }
  }

  Duration _remainingAgentTurnBudget(Stopwatch stopwatch) {
    final remaining = _maxAgentTurnDuration - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('assistant turn limit');
    }
    return remaining < _maxModelCallDuration
        ? remaining
        : _maxModelCallDuration;
  }

  List<AIAgentMessage> _boundedCanonicalHistory(
    Iterable<AIAgentMessage> source,
  ) {
    const maxMessages = 48;
    const maxCharacters = 64 * 1024;
    final messages = source.toList(growable: false);
    if (messages.isEmpty) return <AIAgentMessage>[];

    var start = messages.length;
    var characters = 0;
    for (var index = messages.length - 1; index >= 0; index--) {
      final nextCharacters = _messageCharacterEstimate(messages[index]);
      if (messages.length - index > maxMessages ||
          characters + nextCharacters > maxCharacters) {
        break;
      }
      start = index;
      characters += nextCharacters;
    }

    // A canonical turn always begins with the user's message. Moving forward
    // avoids retaining an orphan assistant tool call or tool output when the
    // cap lands in the middle of an older turn.
    while (start < messages.length &&
        messages[start].role != AIAgentMessageRole.user) {
      start++;
    }
    if (start >= messages.length) return <AIAgentMessage>[];
    return List<AIAgentMessage>.from(messages.sublist(start));
  }

  int _messageCharacterEstimate(AIAgentMessage message) {
    var total = message.text.length + 16;
    for (final call in message.toolCalls) {
      total +=
          call.id.length + call.name.length + _safeJsonLength(call.arguments);
    }
    for (final output in message.toolOutputs) {
      total += output.callId.length +
          output.name.length +
          _safeJsonLength(output.output);
    }
    return total;
  }

  int _safeJsonLength(Map<String, Object?> value) {
    try {
      return jsonEncode(value).length;
    } catch (_) {
      return 1024;
    }
  }

  void _replaceCanonicalHistory(Iterable<AIAgentMessage> messages) {
    _history
      ..clear()
      ..addAll(_boundedCanonicalHistory(messages));
  }

  /// Records a turn that a deterministic handler answered without the model.
  ///
  /// These handlers used to return before touching [_history], so the model
  /// never learned that the operator had asked anything. That produced two
  /// divergent memories in one panel: the assistant could not recall a search
  /// it had just performed, and separately narrated searches from turns the
  /// operator could no longer see. Every produced turn is recorded here.
  AIAssistantResponse _recordDeterministic(
    String message,
    AIAssistantResponse response,
  ) {
    _replaceCanonicalHistory(<AIAgentMessage>[
      ..._history,
      AIAgentMessage.user(message),
      AIAgentMessage.assistant(text: response.text),
    ]);
    return response;
  }

  /// Declines the job path when the published rows could not be trusted.
  ///
  /// Returning a count here would report a verified zero from a source that
  /// was never read, which is exactly the failure the session boundary
  /// rejected the rows to avoid.
  AIAssistantResponse? _tryHandleJobSummaryUnavailable(String message) {
    if (!_looksLikeJobSummaryRequest(message)) {
      return null;
    }
    return _textResponse(
      'No puedo responder por los trabajos en este momento: la lista que '
      'tenías en pantalla no se pudo verificar como de este taller. Abre '
      'Taller para verla directamente.',
      cards: const [
        AIAssistantActionCard(
          kind: 'job',
          eyebrow: 'Fuente no disponible',
          title: 'Trabajos del taller',
          description: 'No se pudo verificar la lista visible.',
          destination: AIAssistantDestination.workshopJobs,
        ),
      ],
    );
  }

  AIAssistantResponse _textResponse(
    String text, {
    List<AIAssistantActionCard> cards = const [],
  }) {
    return AIAssistantResponse(text: text, cards: cards);
  }

  AIAssistantResponse _cardResponse(
    String text, {
    required List<AIAssistantActionCard> cards,
  }) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return AIAssistantResponse(text: compact, cards: cards);
  }

  String _friendlyGeminiErrorMessage(GeminiProxyException error) {
    if (error.isAuthenticationError) {
      return 'No pude autenticar la conexión del asistente. Vuelve a iniciar sesión e intenta otra vez.';
    }

    if (error.isConfigurationError) {
      return 'El asistente IA no está configurado en el servidor. Revisa los secrets de Gemini en Supabase.';
    }

    if (error.isTransient) {
      return 'Gemini está con alta demanda o respondió temporalmente no disponible. Ya intenté reintentar la solicitud; prueba de nuevo en unos segundos.';
    }

    return 'El asistente IA no pudo responder ahora. Intenta de nuevo en unos segundos.';
  }

  /// Which day an operational-briefing request is about, or null.
  ///
  /// Matched deterministically on normalised text — accents and case removed —
  /// because the model must not decide whether a question counts as a
  /// briefing. Tomorrow is checked first: "prioridades de mañana" also
  /// contains a today-shaped phrase.
  @visibleForTesting
  AIAttentionHorizon? detectAttentionHorizon(String message) {
    final normalized = _normalizeText(message);
    if (normalized.isEmpty) return null;

    const tomorrowPhrases = <String>[
      'ayudame a organizar el trabajo para manana',
      'organiza manana',
      'organizar manana',
      'planifica manana',
      'planificar manana',
      'prioridades de manana',
      'que hay para manana',
      'que necesita atencion manana',
      'resumen operativo de manana',
    ];
    for (final phrase in tomorrowPhrases) {
      if (normalized.contains(phrase)) return AIAttentionHorizon.tomorrow;
    }

    const todayPhrases = <String>[
      'que necesita atencion hoy',
      'que necesito atender hoy',
      'que debo resolver hoy',
      'que tengo que resolver hoy',
      'prioridades de hoy',
      'prioridades para hoy',
      'resumen operativo',
    ];
    for (final phrase in todayPhrases) {
      if (normalized.contains(phrase)) return AIAttentionHorizon.today;
    }

    return null;
  }

  /// Renders the briefing. Every sentence is built from the report's own
  /// counters, so what the operator reads is what was measured.
  AIAssistantResponse _attentionResponse(AIAttentionReport report) {
    // Markdown blocks, not lines. The panel renders through `MarkdownBody`,
    // where a single newline is a soft break and collapses: joining sentences
    // with "\n" turned the whole briefing into one run-on paragraph and the
    // "•" bullets into inline dots. Paragraphs are separated by a blank line
    // and the items are a real Markdown list.
    final blocks = <String>[];
    final period = report.horizon.label;

    // Only ever the fixed sentences from the enum: an exception string in this
    // panel would put a stack trace, a tenant id or a Postgres message in front
    // of whoever is at the counter.
    String missingClause() => report.unavailableSources
        .map((o) => '${o.source.label} ${o.reason?.label ?? 'no respondió'}')
        .join(' · ');

    String stamp() =>
        'Al ${AIAttentionReadModel.formatChileStamp(report.generatedAt)}, '
        'hora de Chile.';

    if (report.isUnavailable) {
      // Even a briefing that could read nothing says when it tried: without
      // the stamp the operator cannot tell a failure from a stale panel.
      return _textResponse(
        [
          'No pude armar el resumen de $period: ${missingClause()}. No quiere '
              'decir que no haya nada pendiente — quiere decir que no pude '
              'mirar.',
          stamp(),
        ].join('\n\n'),
      );
    }

    final available = report.outcomes.where((o) => o.isAvailable).toList();
    final examinedParts =
        available.map((o) => '${o.source.label} ${o.examined}').join(', ');
    // With a source missing, a bare "no hay nada" would be a claim about the
    // whole business made from half of it.
    final verifiedScope = report.isPartial
        ? 'en ${available.map((o) => o.source.label).join(' y ')}'
        : '';

    if (report.items.isEmpty) {
      blocks.add(
        report.isPartial
            ? 'Para $period no encontré nada comprometido $verifiedScope. '
                'Revisé $examinedParts registros.'
            : 'Para $period no encontré entregas ni tareas comprometidas. '
                'Revisé $examinedParts registros.',
      );
    } else {
      // The headline states what was found, not what fits on screen. Saying
      // "hay 6" and correcting it two lines later is how a briefing loses the
      // four items nobody scrolled to.
      final head = report.isTruncated
          ? 'Para $period detecté ${report.selectedBeforeTruncation} cosas que '
              'necesitan atención; te muestro las ${report.items.length} más '
              'urgentes.'
          : 'Para $period hay ${report.items.length} '
              '${report.items.length == 1 ? 'cosa' : 'cosas'} que necesitan '
              'atención.';
      blocks.add('$head Revisé $examinedParts registros.');
      blocks.add(
        report.items
            .map((item) =>
                '- ${item.reason.label} · ${item.title} — ${item.detail}')
            .join('\n'),
      );
    }

    if (report.isPartial) {
      blocks.add(
        'Resumen parcial: ${missingClause()}, así que puede faltar algo.',
      );
    }

    blocks.add(stamp());

    // Deliberately not `_cardResponse`: it collapses every run of whitespace
    // into a single space, which would flatten the blocks above back into the
    // paragraph this method exists to avoid.
    return _textResponse(
      blocks.join('\n\n'),
      cards: _attentionCards(report),
    );
  }

  List<AIAssistantActionCard> _attentionCards(AIAttentionReport report) {
    // A source that could not be read gets no card: offering a way into a
    // module the briefing never managed to look at implies it did.
    final availableSources = report.outcomes
        .where((o) => o.isAvailable)
        .map((o) => o.source)
        .toSet();

    // Every available source gets a card, not only the ones that survived the
    // top six. Deriving them from the truncated list meant that six workshop
    // items pushing one task to seventh place removed "Abrir Tareas" — the
    // module with a pending commitment became the one with no way in.
    final sources = availableSources;

    return [
      for (final source in AIAttentionSource.values)
        if (sources.contains(source))
          AIAssistantActionCard(
            kind: source == AIAttentionSource.workshop ? 'job' : 'task',
            eyebrow: source.label,
            title: source == AIAttentionSource.workshop
                ? 'Entregas y trabajos abiertos'
                : 'Tareas pendientes',
            description: report.items
                .where((item) => item.source == source)
                .map((item) => item.title)
                .take(3)
                .join(' · '),
            destination: source.destination,
          ),
    ];
  }

  /// Whether a message is asking the assistant to summarise workshop jobs.
  ///
  /// Shared so the normal summary path and the "source could not be verified"
  /// path answer the same question about the same messages.
  bool _looksLikeJobSummaryRequest(String message) {
    final normalized = _normalizeText(message);
    final mentionsJobs = normalized.contains('trabajo') ||
        normalized.contains('trabajos') ||
        normalized.contains('orden de trabajo') ||
        normalized.contains('ordenes de trabajo') ||
        normalized.contains('job') ||
        normalized.contains('jobs');
    if (!mentionsJobs) {
      return false;
    }

    return _mentionsTodayScope(normalized) ||
        normalized.contains('resumen') ||
        normalized.contains('resume') ||
        normalized.contains('sumario') ||
        normalized.contains('summary') ||
        normalized.contains('estado') ||
        normalized.contains('activos') ||
        normalized.contains('activo') ||
        normalized.contains('pendientes') ||
        normalized.contains('en curso') ||
        normalized.contains('como vamos') ||
        normalized.contains('como esta');
  }

  Future<AIAssistantResponse?> _tryHandleJobSummary(
    String message, {
    List<MechanicJob>? jobs,
    CustomerService? customerService,
    BikeshopService? bikeshopService,
    bool jobsAreCurrentView = false,
    String? jobSummaryScopeLabel,
    bool allowJobCacheFallback = true,
    required AIAssistantTurnAuthority authority,
  }) async {
    final normalized = _normalizeText(message);
    if (!_looksLikeJobSummaryRequest(message)) {
      return null;
    }

    final asksForToday = _mentionsTodayScope(normalized);

    final sourceJobs = await _loadJobsForSummary(
      jobs,
      bikeshopService: bikeshopService,
      useProvidedJobsOnly: jobsAreCurrentView,
      allowJobCacheFallback: allowJobCacheFallback,
      authority: authority,
    );
    if (!kReleaseMode) {
      _debugAi(
        '[AI_CTX][AIService.summary.source] '
        'provided=${jobs?.length ?? 'null'} currentView=$jobsAreCurrentView '
        'source=${sourceJobs.length} allowFallback=$allowJobCacheFallback',
      );
    }
    if (sourceJobs.isEmpty) {
      if (jobsAreCurrentView || !allowJobCacheFallback) {
        return _textResponse(
          'No encontré trabajos en la vista actual para resumir ahora. Reabre la vista de Trabajos o actualiza la tabla para sincronizar el asistente.',
        );
      }
      return _textResponse('No encontré trabajos para resumir ahora mismo.');
    }

    final customerNamesById =
        await _loadCustomerNamesById(customerService, authority);
    final includeTestJobs = _mentionsTestScope(normalized);
    final summarySourceJobs = jobsAreCurrentView || includeTestJobs
        ? sourceJobs
        : sourceJobs
            .where((job) => !_isTestJobForSummary(
                  job,
                  customerName: customerNamesById[job.customerId],
                ))
            .toList();
    if (!kReleaseMode) {
      _debugAi(
        '[AI_CTX][AIService.summary.scopeSource] '
        'before=${sourceJobs.length} after=${summarySourceJobs.length} '
        'currentView=$jobsAreCurrentView includeTest=$includeTestJobs',
      );
    }

    final today = NotificationDigestWindow.businessToday(now: _now());
    final asksForActive =
        normalized.contains('activo') || normalized.contains('activos');
    final includeAll = !asksForToday &&
        !asksForActive &&
        (normalized.contains('todos') ||
            normalized.contains('todas') ||
            normalized.contains('historico') ||
            normalized.contains('historial') ||
            normalized.contains('finalizados') ||
            normalized.contains('entregados') ||
            normalized.contains('cancelados'));

    final List<MechanicJob> selectedJobs;
    final String emptyMessage;
    final String scopeLabel;
    final String detailHeading;

    if (asksForToday) {
      selectedJobs = summarySourceJobs
          .where((job) => _isSameChileBusinessDay(job.arrivalDate, today))
          .toList();
      emptyMessage = 'No encontré trabajos ingresados hoy.';
      scopeLabel = 'trabajos ingresados hoy';
      detailHeading = 'Trabajos de hoy';
    } else if (includeAll) {
      selectedJobs = List<MechanicJob>.from(summarySourceJobs);
      emptyMessage = 'No encontré trabajos para resumir ahora.';
      scopeLabel = jobsAreCurrentView
          ? jobSummaryScopeLabel ?? 'trabajos visibles'
          : 'trabajos';
      detailHeading = _jobSummaryDetailHeading(scopeLabel);
    } else if (jobsAreCurrentView) {
      selectedJobs = List<MechanicJob>.from(summarySourceJobs);
      scopeLabel = jobSummaryScopeLabel ?? 'trabajos visibles';
      emptyMessage = 'No encontré $scopeLabel para resumir ahora.';
      detailHeading = _jobSummaryDetailHeading(scopeLabel);
    } else {
      selectedJobs = summarySourceJobs.where(_isActiveJob).toList();
      emptyMessage = 'No encontré trabajos activos para resumir ahora.';
      scopeLabel = 'trabajos activos';
      detailHeading = _jobSummaryDetailHeading(scopeLabel);
    }

    if (selectedJobs.isEmpty) {
      if (!kReleaseMode) {
        _debugAi(
          '[AI_CTX][AIService.summary.emptySelection] '
          'currentView=$jobsAreCurrentView source=${sourceJobs.length}',
        );
      }
      return _textResponse(emptyMessage);
    }

    if (!jobsAreCurrentView) {
      selectedJobs.sort(_compareJobsForSummary);
    }
    if (!kReleaseMode) {
      _debugAi(
        '[AI_CTX][AIService.summary.selected] '
        'selected=${selectedJobs.length} currentView=$jobsAreCurrentView '
        'asksToday=$asksForToday asksActive=$asksForActive '
        'includeAll=$includeAll',
      );
    }

    final statusCounts = <String, int>{};
    var highPriorityCount = 0;
    var overdueCount = 0;
    var dueSoonCount = 0;
    var totalValue = 0.0;
    final soonLimit = today.add(const Duration(days: 2));

    for (final job in selectedJobs) {
      final statusLabel = _jobStatusLabel(job);
      statusCounts[statusLabel] = (statusCounts[statusLabel] ?? 0) + 1;
      if (job.priority == JobPriority.urgente ||
          job.priority == JobPriority.alta) {
        highPriorityCount++;
      }
      final deadline = job.deliveryDeadline;
      if (deadline != null && _isActiveJob(job)) {
        final deadlineDate = DateTime(
          deadline.year,
          deadline.month,
          deadline.day,
        );
        if (deadlineDate.isBefore(today)) {
          overdueCount++;
        } else if (!deadlineDate.isAfter(soonLimit)) {
          dueSoonCount++;
        }
      }
      totalValue += job.totalCost;
    }

    final statusSummary = statusCounts.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');
    final headline =
        'Tienes ${_jobCountPhrase(selectedJobs.length, scopeLabel)}.';
    final lines = <String>[
      headline,
      if (statusSummary.isNotEmpty) 'Por estado: $statusSummary.',
      if (highPriorityCount > 0)
        'Prioridad alta o urgente: $highPriorityCount.',
      if (overdueCount > 0) 'Con fecha de entrega vencida: $overdueCount.',
      if (dueSoonCount > 0) 'Vencen en los próximos 2 días: $dueSoonCount.',
      if (totalValue > 0)
        'Total valorizado: ${ChileanUtils.formatCurrency(totalValue)}.',
    ];

    final detailLines = selectedJobs
        .take(5)
        .map((job) => _jobSummaryLine(
              job,
              customerName: customerNamesById[job.customerId],
            ))
        .toList();

    final cards = selectedJobs
        .take(3)
        .map((job) => _buildJobCard(
              job,
              customerName: customerNamesById[job.customerId],
            ))
        .toList();

    final text = [
      lines.join('\n'),
      if (detailLines.isNotEmpty) '$detailHeading:\n${detailLines.join('\n')}',
    ].join('\n\n');

    return _textResponse(text, cards: cards);
  }

  bool _mentionsTodayScope(String normalizedMessage) {
    return normalizedMessage.contains('hoy') ||
        normalizedMessage.contains('del dia') ||
        normalizedMessage.contains('de hoy') ||
        normalizedMessage.contains('dia de hoy') ||
        normalizedMessage.contains('este dia') ||
        normalizedMessage.contains('jornada');
  }

  bool _mentionsTestScope(String normalizedMessage) {
    return normalizedMessage.contains('test') ||
        normalizedMessage.contains('tests') ||
        normalizedMessage.contains('prueba') ||
        normalizedMessage.contains('pruebas') ||
        normalizedMessage.contains('sandbox') ||
        normalizedMessage.contains('dummy');
  }

  bool _isTestJobForSummary(
    MechanicJob job, {
    String? customerName,
  }) {
    final customerLower = customerName?.trim().toLowerCase() ?? '';
    if (customerLower == 'test' || customerLower.startsWith('test ')) {
      return true;
    }

    final auditText = [
      job.jobNumber,
      job.clientRequest,
      job.diagnosis,
      job.workPerformed,
      job.notes,
    ].whereType<String>().join(' ').toLowerCase();

    return auditText.contains('[test') ||
        auditText.contains('test perfil') ||
        auditText.contains('test data') ||
        auditText.contains('sandbox') ||
        auditText.contains('dummy');
  }

  String _jobCountPhrase(int count, String pluralScopeLabel) {
    if (count != 1) {
      return '$count $pluralScopeLabel';
    }

    switch (pluralScopeLabel) {
      case 'trabajos ingresados hoy':
        return '1 trabajo ingresado hoy';
      case 'trabajos activos':
        return '1 trabajo activo';
      case 'trabajos completados':
        return '1 trabajo completado';
      case 'trabajos entregados':
        return '1 trabajo entregado';
      case 'trabajos de garantía completados':
        return '1 trabajo de garantía completado';
      case 'trabajos sin pagar':
        return '1 trabajo sin pagar';
      case 'trabajos visibles':
        return '1 trabajo visible';
      case 'trabajos':
        return '1 trabajo';
      default:
        if (pluralScopeLabel.startsWith('trabajos ')) {
          return '1 trabajo ${pluralScopeLabel.substring('trabajos '.length)}';
        }
        return '1 trabajo';
    }
  }

  String _jobSummaryDetailHeading(String scopeLabel) {
    switch (scopeLabel) {
      case 'trabajos activos':
        return 'Trabajos activos destacados';
      case 'trabajos ingresados hoy':
        return 'Trabajos de hoy';
      case 'trabajos':
        return 'Trabajos destacados';
      default:
        return 'Trabajos destacados';
    }
  }

  bool _isSameChileBusinessDay(DateTime value, DateTime businessDay) {
    final valueDay = NotificationDigestWindow.businessToday(now: value);
    return valueDay.year == businessDay.year &&
        valueDay.month == businessDay.month &&
        valueDay.day == businessDay.day;
  }

  Future<List<MechanicJob>> _loadJobsForSummary(
    List<MechanicJob>? jobs, {
    BikeshopService? bikeshopService,
    bool useProvidedJobsOnly = false,
    bool allowJobCacheFallback = true,
    required AIAssistantTurnAuthority authority,
  }) async {
    if (jobs != null && (jobs.isNotEmpty || useProvidedJobsOnly)) {
      final providedJobs = authority
          .verifyRows('taller', jobs, (job) => job.tenantId)
          .where((job) => job.id != null)
          .toList();
      if (!kReleaseMode) {
        _debugAi(
          '[AI_CTX][AIService.loadJobs] using provided jobs '
          'provided=${jobs.length} filtered=${providedJobs.length} '
          'useProvidedOnly=$useProvidedJobsOnly '
          'allowFallback=$allowJobCacheFallback',
        );
      }
      return providedJobs;
    }

    if (!allowJobCacheFallback) {
      if (!kReleaseMode) {
        _debugAi(
          '[AI_CTX][AIService.loadJobs] cache fallback disabled; '
          'provided=${jobs?.length ?? 'null'} '
          'useProvidedOnly=$useProvidedJobsOnly',
        );
      }
      throw const AIAssistantSourceUnavailable(
        'taller',
        'no trusted workshop source was published',
      );
    }

    if (bikeshopService == null) {
      if (!kReleaseMode) {
        _debugAi(
          '[AI_CTX][AIService.loadJobs] no provided jobs and no '
          'BikeshopService',
        );
      }
      throw const AIAssistantSourceUnavailable(
        'taller',
        'the workshop service is unavailable',
      );
    }

    if (!kReleaseMode) {
      _debugAi(
        '[AI_CTX][AIService.loadJobs] FALLBACK to BikeshopService '
        'hasCache=${bikeshopService.hasJobsCache} '
        'useProvidedOnly=$useProvidedJobsOnly '
        'allowFallback=$allowJobCacheFallback',
      );
    }
    // The cache belongs to the service's own lifecycle, not to this turn. It
    // is checked before being *consumed*, and again after any read: a fetch
    // can span a tenant switch and come back holding the previous taller's
    // rows. The pre-check is deliberately skipped when there is no cache to
    // consume, because a first load legitimately starts with no bound scope.
    final usesCache = bikeshopService.hasJobsCache;
    if (usesCache) {
      authority.requireServiceScope('taller', bikeshopService.authorityScope);
    }
    final loadedJobs = usesCache
        ? bikeshopService.cachedJobs
        : await bikeshopService.getJobs();
    authority.requireServiceScope('taller', bikeshopService.authorityScope);
    final fallbackJobs = authority
        .verifyRows('taller', loadedJobs, (job) => job.tenantId)
        .where((job) => job.id != null)
        .toList();
    if (!kReleaseMode) {
      _debugAi(
        '[AI_CTX][AIService.loadJobs] fallback loaded=${fallbackJobs.length}',
      );
    }
    return fallbackJobs;
  }

  Future<Map<String, String>> _loadCustomerNamesById(
    CustomerService? customerService,
    AIAssistantTurnAuthority authority,
  ) async {
    if (customerService == null) {
      return const <String, String>{};
    }

    try {
      final customers = await _loadCustomersForAi(customerService, authority);
      return {
        for (final customer in customers)
          if (customer.id != null) customer.id!: customer.name,
      };
    } on AIAssistantSourceUnavailable {
      // A tenant mismatch is not a degradable enrichment failure. Swallowing
      // it here would let the summary print job numbers whose customer names
      // came from a source that just failed its authority check, and the
      // operator would never know.
      rethrow;
    } catch (_) {
      // Anything else only costs the names: the summary still answers, and it
      // answers about jobs that did pass verification.
      _debugAi('⚠️ [AI] Customer-name enrichment is unavailable.');
      return const <String, String>{};
    }
  }

  bool _isActiveJob(MechanicJob job) {
    if (job.status == JobStatus.cancelado) {
      return false;
    }

    final customStatusCode = job.customStatus?.code.toLowerCase();
    final isDelivered = job.deliveredAt != null ||
        job.status == JobStatus.entregado ||
        customStatusCode == 'entregado';
    final isInvoiced = job.invoiceId != null || job.isInvoiced;
    final isPaid = job.isPaid;

    if (isDelivered && isInvoiced && isPaid) {
      return false;
    }

    if (job.isWarrantyJob &&
        isDelivered &&
        (job.totalCost <= 0 || (isInvoiced && isPaid))) {
      return false;
    }

    return true;
  }

  int _compareJobsForSummary(MechanicJob a, MechanicJob b) {
    final priorityCompare =
        _jobPriorityRank(b.priority).compareTo(_jobPriorityRank(a.priority));
    if (priorityCompare != 0) {
      return priorityCompare;
    }

    final deadlineCompare =
        _jobDeadlineSortValue(a).compareTo(_jobDeadlineSortValue(b));
    if (deadlineCompare != 0) {
      return deadlineCompare;
    }

    return b.arrivalDate.compareTo(a.arrivalDate);
  }

  int _jobPriorityRank(JobPriority priority) {
    switch (priority) {
      case JobPriority.urgente:
        return 4;
      case JobPriority.alta:
        return 3;
      case JobPriority.normal:
        return 2;
      case JobPriority.baja:
        return 1;
    }
  }

  int _jobDeadlineSortValue(MechanicJob job) {
    return job.deliveryDeadline?.millisecondsSinceEpoch ?? 8640000000000000;
  }

  String _jobSummaryLine(
    MechanicJob job, {
    String? customerName,
  }) {
    final parts = <String>[
      _jobCardTitle(job),
      _jobStatusLabel(job),
      job.priority.displayName,
      if ((customerName ?? '').trim().isNotEmpty) customerName!.trim(),
      if (job.deliveryDeadline != null)
        'Entrega ${ChileanUtils.formatDate(job.deliveryDeadline!)}',
      if (job.totalCost > 0) ChileanUtils.formatCurrency(job.totalCost),
    ];
    return '- ${parts.join(' | ')}';
  }

  Future<AIAssistantResponse?> _tryHandleEntityCards(
    String message, {
    CustomerService? customerService,
    BikeshopService? bikeshopService,
    PurchaseService? purchaseService,
    SalesService? salesService,
    required AIAssistantTurnAuthority authority,
  }) async {
    final canReadOperations = authority.permissions.contains(
      AIToolPermission.operationalRead,
    );
    final canReadSales = authority.permissions.contains(
      AIToolPermission.salesRead,
    );
    final canReadPurchases = authority.permissions.contains(
      AIToolPermission.purchasesRead,
    );

    final purchaseInvoiceResponse = canReadPurchases
        ? await _tryHandlePurchaseInvoiceCards(
            message,
            purchaseService: purchaseService,
            authority: authority,
          )
        : null;
    if (purchaseInvoiceResponse != null) {
      return purchaseInvoiceResponse;
    }

    final salesInvoiceResponse = canReadSales
        ? await _tryHandleSalesInvoiceCards(
            message,
            salesService: salesService,
            authority: authority,
          )
        : null;
    if (salesInvoiceResponse != null) {
      return salesInvoiceResponse;
    }

    final customerResponse = canReadOperations
        ? await _tryHandleCustomerCards(
            message,
            customerService: customerService,
            authority: authority,
          )
        : null;
    if (customerResponse != null) {
      return customerResponse;
    }

    final supplierResponse = canReadPurchases
        ? await _tryHandleSupplierCards(
            message,
            purchaseService: purchaseService,
            authority: authority,
          )
        : null;
    if (supplierResponse != null) {
      return supplierResponse;
    }

    final jobResponse = canReadOperations
        ? await _tryHandleJobCards(
            message,
            customerService: customerService,
            bikeshopService: bikeshopService,
            authority: authority,
          )
        : null;
    if (jobResponse != null) {
      return jobResponse;
    }

    return null;
  }

  Future<AIAssistantResponse?> _tryHandleCustomerCards(
    String message, {
    CustomerService? customerService,
    required AIAssistantTurnAuthority authority,
  }) async {
    if (customerService == null) {
      return null;
    }

    final normalized = _normalizeText(message);
    final mentionsCustomer =
        normalized.contains('cliente') || normalized.contains('customer');

    if (!mentionsCustomer) {
      return null;
    }

    final wantsRecent = _wantsRecentEntityLookup(normalized);
    final wantsDirectLookup = _isDirectEntityLookup(normalized);
    if (!wantsRecent && !wantsDirectLookup) {
      return null;
    }

    final searchTerm = _extractEntitySearchTerm(
      message,
      removePatterns: const [
        'cliente',
        'clientes',
        'customer',
        'customers',
        'ficha',
      ],
    );

    if (searchTerm.isEmpty && !wantsRecent) {
      return null;
    }

    final allCustomers = await _loadCustomersForAi(customerService, authority);
    var customers = searchTerm.isNotEmpty
        ? allCustomers
            .where(
                (customer) => _customerMatchesSearchTerm(searchTerm, customer))
            .toList()
        : allCustomers;

    if (customers.isEmpty) {
      if (searchTerm.isNotEmpty) {
        return _textResponse(
            'No encontré clientes que coincidan con "$searchTerm".');
      }
      return _textResponse('No encontré clientes para mostrar ahora mismo.');
    }

    customers = customers.where((customer) => customer.id != null).toList();
    if (customers.isEmpty) {
      return null;
    }

    customers.sort((a, b) {
      if (searchTerm.isNotEmpty) {
        final scoreA = _customerMatchScore(searchTerm, a);
        final scoreB = _customerMatchScore(searchTerm, b);
        if (scoreA != scoreB) {
          return scoreB.compareTo(scoreA);
        }
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });

    final wantsMultiple = _wantsMultipleEntityResults(normalized);
    final shouldReturnSingle =
        !wantsMultiple && (wantsRecent || searchTerm.isNotEmpty);
    final limited = customers.take(shouldReturnSingle ? 1 : 3).toList();
    final cards = limited.map(_buildCustomerCard).toList();

    if (limited.length == 1) {
      final customer = limited.first;
      final intro = wantsRecent && searchTerm.isEmpty
          ? 'El cliente actualizado más reciente es ${customer.name}.'
          : 'Encontré el cliente ${customer.name}.';
      return _cardResponse(intro, cards: cards);
    }

    final headline = searchTerm.isNotEmpty
        ? 'Encontré ${limited.length} clientes para "$searchTerm" que puedes abrir directo desde aquí.'
        : 'Encontré ${limited.length} clientes recientes que puedes abrir directo desde aquí.';
    return _cardResponse(headline, cards: cards);
  }

  Future<AIAssistantResponse?> _tryHandleSupplierCards(
    String message, {
    PurchaseService? purchaseService,
    required AIAssistantTurnAuthority authority,
  }) async {
    if (purchaseService == null) {
      return null;
    }

    final normalized = _normalizeText(message);
    final mentionsSupplier = normalized.contains('proveedor') ||
        normalized.contains('proveedores') ||
        normalized.contains('supplier') ||
        normalized.contains('suppliers');

    if (!mentionsSupplier) {
      return null;
    }

    final wantsRecent = _wantsRecentEntityLookup(normalized);
    final wantsDirectLookup = _isDirectEntityLookup(normalized);
    if (!wantsRecent && !wantsDirectLookup) {
      return null;
    }

    final searchTerm = _extractEntitySearchTerm(
      message,
      removePatterns: const [
        'proveedor',
        'proveedores',
        'supplier',
        'suppliers',
      ],
    );

    if (searchTerm.isEmpty && !wantsRecent) {
      return null;
    }

    // The pre-check guards a cache about to be *consumed*, so it keys off the
    // cache itself. Keying off the scope instead let a stale detached scope
    // block a legitimate cold load, which is a refusal to answer a question
    // nothing was wrong with.
    if (purchaseService.hasSuppliersCache) {
      authority.requireServiceScope(
        'proveedores',
        purchaseService.supplierAuthorityScope,
      );
    }
    final loadedSuppliers = await purchaseService.getSuppliers();
    authority.requireServiceScope(
      'proveedores',
      purchaseService.supplierAuthorityScope,
    );
    var suppliers = authority.verifyRows(
      'proveedores',
      loadedSuppliers,
      (supplier) => supplier.tenantId,
    );

    if (searchTerm.isNotEmpty) {
      suppliers = suppliers
          .where((supplier) => _supplierMatchesSearchTerm(searchTerm, supplier))
          .toList();
    }

    if (suppliers.isEmpty) {
      if (searchTerm.isNotEmpty) {
        return _textResponse(
            'No encontré proveedores que coincidan con "$searchTerm".');
      }
      return _textResponse('No encontré proveedores para mostrar ahora mismo.');
    }

    suppliers.sort((a, b) {
      if (searchTerm.isNotEmpty) {
        final scoreA = _supplierMatchScore(searchTerm, a);
        final scoreB = _supplierMatchScore(searchTerm, b);
        if (scoreA != scoreB) {
          return scoreB.compareTo(scoreA);
        }
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });

    final wantsMultiple = _wantsMultipleEntityResults(normalized);
    final shouldReturnSingle =
        !wantsMultiple && (wantsRecent || searchTerm.isNotEmpty);
    final limited = suppliers.take(shouldReturnSingle ? 1 : 3).toList();
    final cards = limited.map(_buildSupplierCard).toList();

    if (limited.length == 1) {
      final supplier = limited.first;
      final intro = wantsRecent && searchTerm.isEmpty
          ? 'El proveedor actualizado más reciente es ${supplier.name}.'
          : 'Encontré el proveedor ${supplier.name}.';
      return _cardResponse(intro, cards: cards);
    }

    final headline = searchTerm.isNotEmpty
        ? 'Encontré ${limited.length} proveedores para "$searchTerm" que puedes abrir directo desde aquí.'
        : 'Encontré ${limited.length} proveedores recientes que puedes abrir directo desde aquí.';
    return _cardResponse(headline, cards: cards);
  }

  Future<AIAssistantResponse?> _tryHandleJobCards(
    String message, {
    CustomerService? customerService,
    BikeshopService? bikeshopService,
    required AIAssistantTurnAuthority authority,
  }) async {
    if (bikeshopService == null) {
      return null;
    }

    final normalized = _normalizeText(message);
    final mentionsJob = normalized.contains('trabajo') ||
        normalized.contains('trabajos') ||
        normalized.contains('orden de trabajo') ||
        normalized.contains('ordenes de trabajo') ||
        normalized.contains('job') ||
        normalized.contains('jobs');

    if (!mentionsJob) {
      return null;
    }

    final wantsRecent = _wantsRecentEntityLookup(normalized);
    final wantsDirectLookup = _isDirectEntityLookup(normalized);
    if (!wantsRecent && !wantsDirectLookup) {
      return null;
    }

    final searchTerm = _extractEntitySearchTerm(
      message,
      removePatterns: const [
        'trabajo',
        'trabajos',
        'orden de trabajo',
        'ordenes de trabajo',
        'job',
        'jobs',
      ],
    );

    if (searchTerm.isEmpty && !wantsRecent) {
      return null;
    }

    // Names come only from the verified snapshot below. Seeding them from the
    // raw cache first put unverified rows on a card the moment a job happened
    // to reference one of them, which is the same leak the verification
    // exists to stop.
    final allCustomers = customerService != null
        ? await _loadCustomersForAi(customerService, authority)
        : const <Customer>[];

    final customerNamesById = <String, String>{
      for (final customer in allCustomers)
        if (customer.id != null) customer.id!: customer.name,
    };

    final matchingCustomers = searchTerm.isNotEmpty
        ? allCustomers
            .where(
                (customer) => _customerMatchesSearchTerm(searchTerm, customer))
            .take(10)
            .toList()
        : const <Customer>[];

    // Same rule as the summary path: the scope pre-check guards a cache about
    // to be consumed, never a first load that has none yet.
    if (bikeshopService.hasJobsCache) {
      authority.requireServiceScope('taller', bikeshopService.authorityScope);
    }

    List<MechanicJob> candidateJobs;
    if (searchTerm.isEmpty) {
      final loaded = bikeshopService.hasJobsCache
          ? bikeshopService.cachedJobs
          : await bikeshopService.getJobs();
      authority.requireServiceScope('taller', bikeshopService.authorityScope);
      candidateJobs = authority.verifyRows(
        'taller',
        loaded,
        (job) => job.tenantId,
      );
    } else {
      final cachedJobs = authority.verifyRows(
        'taller',
        bikeshopService.hasJobsCache
            ? bikeshopService.cachedJobs
            : const <MechanicJob>[],
        (job) => job.tenantId,
      );
      final customerLinkedJobs = <MechanicJob>[];
      final seenCustomerLinkedJobIds = <String>{};

      for (final customer in matchingCustomers) {
        final customerId = customer.id;
        if (customerId == null) continue;
        customerNamesById[customerId] = customer.name;

        List<MechanicJob> jobsForCustomer;
        if (cachedJobs.isNotEmpty) {
          jobsForCustomer =
              cachedJobs.where((job) => job.customerId == customerId).toList();
        } else {
          final loaded = await bikeshopService.getJobs(customerId: customerId);
          // Post-check after every filtered read. Without it, a read that
          // spanned a tenant switch comes back empty and that emptiness gets
          // reported as a verified zero for this taller.
          authority.requireServiceScope(
            'taller',
            bikeshopService.authorityScope,
          );
          jobsForCustomer = authority.verifyRows(
            'taller',
            loaded,
            (job) => job.tenantId,
          );
        }

        for (final job in jobsForCustomer) {
          final jobId = job.id;
          if (jobId == null || seenCustomerLinkedJobIds.contains(jobId)) {
            continue;
          }
          customerLinkedJobs.add(job);
          seenCustomerLinkedJobIds.add(jobId);
        }
      }

      candidateJobs = customerLinkedJobs;

      final textMatchedLoaded =
          await bikeshopService.getJobs(searchTerm: searchTerm);
      authority.requireServiceScope('taller', bikeshopService.authorityScope);
      final textMatchedJobs = authority.verifyRows(
        'taller',
        textMatchedLoaded,
        (job) => job.tenantId,
      );
      final seenJobIds =
          candidateJobs.map((job) => job.id).whereType<String>().toSet();
      for (final job in textMatchedJobs) {
        final jobId = job.id;
        if (jobId == null || seenJobIds.contains(jobId)) continue;
        candidateJobs.add(job);
        seenJobIds.add(jobId);
      }
    }

    var jobs = candidateJobs.where((job) => job.id != null).toList();
    if (searchTerm.isNotEmpty) {
      jobs = jobs
          .where((job) => _jobMatchesSearchTerm(
                searchTerm,
                job,
                customerName: customerNamesById[job.customerId],
              ))
          .toList();
    }

    if (jobs.isEmpty) {
      if (searchTerm.isNotEmpty) {
        return _textResponse(
            'No encontré trabajos que coincidan con "$searchTerm".');
      }
      return _textResponse('No encontré trabajos para mostrar ahora mismo.');
    }

    jobs.sort((a, b) {
      if (searchTerm.isNotEmpty) {
        final scoreA = _jobMatchScore(
          searchTerm,
          a,
          customerName: customerNamesById[a.customerId],
        );
        final scoreB = _jobMatchScore(
          searchTerm,
          b,
          customerName: customerNamesById[b.customerId],
        );
        if (scoreA != scoreB) {
          return scoreB.compareTo(scoreA);
        }
      }
      return b.arrivalDate.compareTo(a.arrivalDate);
    });

    final wantsMultiple = _wantsMultipleEntityResults(normalized);
    final shouldReturnSingle =
        !wantsMultiple && (wantsRecent || searchTerm.isNotEmpty);
    final limited = jobs.take(shouldReturnSingle ? 1 : 3).toList();
    final cards = limited
        .map((job) => _buildJobCard(
              job,
              customerName: customerNamesById[job.customerId],
            ))
        .toList();

    if (limited.length == 1) {
      final job = limited.first;
      final label = _jobCardTitle(job);
      final intro = wantsRecent && searchTerm.isEmpty
          ? 'El trabajo más reciente es $label.'
          : 'Encontré el trabajo $label.';
      return _cardResponse(intro, cards: cards);
    }

    final headline = searchTerm.isNotEmpty
        ? 'Encontré ${limited.length} trabajos para "$searchTerm" que puedes abrir directo desde aquí.'
        : 'Encontré ${limited.length} trabajos recientes que puedes abrir directo desde aquí.';
    return _cardResponse(headline, cards: cards);
  }

  bool _wantsRecentEntityLookup(String normalizedMessage) {
    return normalizedMessage.contains('ultima') ||
        normalizedMessage.contains('ultim') ||
        normalizedMessage.contains('last') ||
        normalizedMessage.contains('latest') ||
        normalizedMessage.contains('reciente');
  }

  bool _wantsMultipleEntityResults(String normalizedMessage) {
    return normalizedMessage.contains('muestrame') ||
        normalizedMessage.contains('listame') ||
        normalizedMessage.contains('show me') ||
        normalizedMessage.contains('all ') ||
        normalizedMessage.contains('todos') ||
        normalizedMessage.contains('todas');
  }

  bool _isDirectEntityLookup(String normalizedMessage) {
    return _isDirectInvoiceLookup(normalizedMessage) ||
        normalizedMessage.contains('trae') ||
        normalizedMessage.contains('dame');
  }

  String _extractEntitySearchTerm(
    String message, {
    required List<String> removePatterns,
  }) {
    var normalized = _normalizeText(message);

    final commonPatterns = <Pattern>[
      RegExp(r'\bbuscame\b'),
      RegExp(r'\bbusca\b'),
      RegExp(r'\bmuestrame\b'),
      RegExp(r'\bmostrame\b'),
      RegExp(r'\bquiero ver\b'),
      RegExp(r'\babre\b'),
      RegExp(r'\babrir\b'),
      RegExp(r'\bopen\b'),
      RegExp(r'\bshow me\b'),
      RegExp(r'\btraeme\b'),
      RegExp(r'\btrae\b'),
      RegExp(r'\bdame\b'),
      RegExp(r'\bultima\b'),
      RegExp(r'\bultimo\b'),
      RegExp(r'\bultimas\b'),
      RegExp(r'\bultimos\b'),
      RegExp(r'\breciente\b'),
      RegExp(r'\brecientes\b'),
      RegExp(r'\bla\b'),
      RegExp(r'\bel\b'),
      RegExp(r'\blas\b'),
      RegExp(r'\blos\b'),
    ];

    final entityPatterns = removePatterns
        .map((value) => RegExp('\\b${RegExp.escape(value)}\\b'))
        .toList();

    for (final pattern in [...commonPatterns, ...entityPatterns]) {
      normalized = normalized.replaceAll(pattern, ' ');
    }

    normalized = normalized.replaceFirst(RegExp(r'^\s*(de|del|para)\s+'), '');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  bool _matchesSearchAcrossFields(
    String searchTerm,
    Iterable<String?> fields,
  ) {
    if (searchTerm.isEmpty) {
      return true;
    }

    final haystack = _normalizeText(fields.whereType<String>().join(' '));
    final tokens = _normalizeText(searchTerm)
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    return tokens.every(haystack.contains);
  }

  int _fieldMatchScore(
    String searchTerm,
    String? rawValue, {
    required int exactWeight,
    required int containsWeight,
    required int tokenWeight,
  }) {
    final value = _normalizeText(rawValue ?? '').trim();
    final normalizedSearch = _normalizeText(searchTerm).trim();
    if (value.isEmpty || normalizedSearch.isEmpty) {
      return 0;
    }

    final compactValue = value.replaceAll(RegExp(r'[\s-]+'), '');
    final compactSearch = normalizedSearch.replaceAll(RegExp(r'[\s-]+'), '');
    final tokens = normalizedSearch
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();

    var score = 0;
    if (value == normalizedSearch || compactValue == compactSearch) {
      score += exactWeight;
    }
    if (value.contains(normalizedSearch)) {
      score += containsWeight;
    }
    for (final token in tokens) {
      if (value.contains(token)) {
        score += tokenWeight;
      }
    }
    return score;
  }

  bool _customerMatchesSearchTerm(String searchTerm, Customer customer) {
    return _matchesSearchAcrossFields(searchTerm, [
      customer.name,
      customer.rut,
      customer.email,
      customer.phone,
      customer.address,
      customer.region,
    ]);
  }

  int _customerMatchScore(String searchTerm, Customer customer) {
    return _fieldMatchScore(
          searchTerm,
          customer.name,
          exactWeight: 900,
          containsWeight: 260,
          tokenWeight: 45,
        ) +
        _fieldMatchScore(
          searchTerm,
          customer.rut,
          exactWeight: 700,
          containsWeight: 220,
          tokenWeight: 30,
        ) +
        _fieldMatchScore(
          searchTerm,
          customer.email,
          exactWeight: 500,
          containsWeight: 180,
          tokenWeight: 24,
        ) +
        _fieldMatchScore(
          searchTerm,
          customer.phone,
          exactWeight: 450,
          containsWeight: 160,
          tokenWeight: 20,
        );
  }

  Future<List<Customer>> _loadCustomersForAi(
    CustomerService customerService,
    AIAssistantTurnAuthority authority,
  ) async {
    // CustomerService publishes no authority of its own, so every row it hands
    // back is checked individually.
    if (customerService.hasCustomersCache &&
        customerService.cachedCustomers.isNotEmpty) {
      final verifiedCustomers = authority
          .verifyRows(
            'clientes',
            customerService.cachedCustomers,
            (customer) => customer.tenantId,
          )
          .where((customer) => customer.id != null)
          .toList();
      if (verifiedCustomers.isEmpty) {
        throw const AIAssistantSourceUnavailable(
          'clientes',
          'the cached read has no usable authority-bound rows',
        );
      }
      return verifiedCustomers;
    }

    // An *empty* cache carries no rows, so it carries no evidence of whose
    // customers it holds — and `getCustomers(forceRefresh: false)` would hand
    // that same empty cache straight back. A current read is forced so the
    // difference between "this taller has no customers" and "nobody asked the
    // database" stays visible.
    final customers = await customerService.getCustomers(
      forceRefresh: customerService.hasCustomersCache,
    );
    final verifiedCustomers = authority
        .verifyRows('clientes', customers, (customer) => customer.tenantId)
        .where((customer) => customer.id != null)
        .toList();
    if (verifiedCustomers.isEmpty) {
      throw const AIAssistantSourceUnavailable(
        'clientes',
        'an empty read has no authority-bound receipt',
      );
    }
    return verifiedCustomers;
  }

  AIAssistantActionCard _buildCustomerCard(Customer customer) {
    // Name and destination only. The card used to print RUT, e-mail, phone,
    // address and region — a personal-data dump, rendered in a panel that
    // sits open beside whatever else is on screen, to answer a question that
    // never asked for any of it. Whoever needs those fields opens Clientes,
    // where access is the module's to govern.
    return AIAssistantActionCard(
      kind: 'customer',
      eyebrow: 'Cliente',
      title: customer.name,
      destination: AIAssistantDestination.customers,
      chips: [customer.isActive ? 'Activo' : 'Inactivo'],
    );
  }

  bool _supplierMatchesSearchTerm(String searchTerm, Supplier supplier) {
    return _matchesSearchAcrossFields(searchTerm, [
      supplier.name,
      supplier.rut,
      supplier.email,
      supplier.phone,
      supplier.contactPerson,
      supplier.address,
    ]);
  }

  int _supplierMatchScore(String searchTerm, Supplier supplier) {
    return _fieldMatchScore(
          searchTerm,
          supplier.name,
          exactWeight: 900,
          containsWeight: 260,
          tokenWeight: 45,
        ) +
        _fieldMatchScore(
          searchTerm,
          supplier.rut,
          exactWeight: 700,
          containsWeight: 220,
          tokenWeight: 30,
        ) +
        _fieldMatchScore(
          searchTerm,
          supplier.email,
          exactWeight: 500,
          containsWeight: 180,
          tokenWeight: 24,
        ) +
        _fieldMatchScore(
          searchTerm,
          supplier.phone,
          exactWeight: 450,
          containsWeight: 160,
          tokenWeight: 20,
        );
  }

  AIAssistantActionCard _buildSupplierCard(Supplier supplier) {
    final subtitleParts = <String>[
      if ((supplier.rut ?? '').trim().isNotEmpty) supplier.rut!.trim(),
      if ((supplier.contactPerson ?? '').trim().isNotEmpty)
        supplier.contactPerson!.trim(),
      if ((supplier.email ?? '').trim().isNotEmpty) supplier.email!.trim(),
      if ((supplier.phone ?? '').trim().isNotEmpty) supplier.phone!.trim(),
    ];

    return AIAssistantActionCard(
      kind: 'supplier',
      eyebrow: 'Proveedor',
      title: supplier.name,
      subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' • '),
      description: (supplier.address ?? '').trim().isEmpty
          ? null
          : supplier.address!.trim(),
      destination: AIAssistantDestination.suppliers,
      chips: [supplier.isActive ? 'Activo' : 'Inactivo'],
    );
  }

  bool _jobMatchesSearchTerm(
    String searchTerm,
    MechanicJob job, {
    String? customerName,
  }) {
    return _matchesSearchAcrossFields(searchTerm, [
      _jobCardTitle(job),
      customerName,
      job.clientRequest,
      job.diagnosis,
      job.workPerformed,
      job.notes,
      job.assignedTechnicianName,
    ]);
  }

  int _jobMatchScore(
    String searchTerm,
    MechanicJob job, {
    String? customerName,
  }) {
    return _fieldMatchScore(
          searchTerm,
          _jobCardTitle(job),
          exactWeight: 950,
          containsWeight: 300,
          tokenWeight: 55,
        ) +
        _fieldMatchScore(
          searchTerm,
          customerName,
          exactWeight: 700,
          containsWeight: 240,
          tokenWeight: 36,
        ) +
        _fieldMatchScore(
          searchTerm,
          job.clientRequest,
          exactWeight: 400,
          containsWeight: 160,
          tokenWeight: 24,
        ) +
        _fieldMatchScore(
          searchTerm,
          job.diagnosis,
          exactWeight: 320,
          containsWeight: 140,
          tokenWeight: 20,
        );
  }

  String _jobCardTitle(MechanicJob job) {
    final number = (job.jobNumber ?? '').trim();
    return number.isNotEmpty ? number : 'Trabajo sin número';
  }

  String _jobStatusLabel(MechanicJob job) {
    final customStatus = job.customStatus?.name.trim();
    if (customStatus != null && customStatus.isNotEmpty) {
      return customStatus;
    }
    return job.status.displayName;
  }

  AIAssistantActionCard _buildJobCard(
    MechanicJob job, {
    String? customerName,
  }) {
    final subtitleParts = <String>[
      if ((customerName ?? '').trim().isNotEmpty) customerName!.trim(),
      'Ingreso ${ChileanUtils.formatDate(job.arrivalDate)}',
    ];

    final detail = (job.clientRequest ?? '').trim().isNotEmpty
        ? job.clientRequest!.trim()
        : (job.diagnosis ?? '').trim().isNotEmpty
            ? job.diagnosis!.trim()
            : null;

    final descriptionParts = <String>[
      if (detail != null) detail,
      'Total ${ChileanUtils.formatCurrency(job.totalCost)}',
    ];

    return AIAssistantActionCard(
      kind: 'job',
      eyebrow: 'Trabajo',
      title: _jobCardTitle(job),
      subtitle: subtitleParts.join(' • '),
      description: descriptionParts.join(' • '),
      destination: AIAssistantDestination.workshopJobs,
      chips: [
        _jobStatusLabel(job),
        if (job.isInvoiced) 'Facturada',
        if (job.isPaid) 'Pagada',
      ],
    );
  }

  Future<AIAssistantResponse?> _tryHandleSalesInvoiceCards(
    String message, {
    SalesService? salesService,
    required AIAssistantTurnAuthority authority,
  }) async {
    if (salesService == null) {
      return null;
    }

    final normalized = _normalizeText(message);
    final mentionsInvoice =
        normalized.contains('factura') || normalized.contains('invoice');
    final mentionsPurchase = normalized.contains('compra') ||
        normalized.contains('purchase') ||
        normalized.contains('proveedor');
    final mentionsSales = normalized.contains('venta') ||
        normalized.contains('sales') ||
        normalized.contains('cliente') ||
        normalized.contains('cobro') ||
        normalized.contains('cobrar');

    if (!mentionsInvoice || mentionsPurchase) {
      return null;
    }

    final wantsUnpaid = normalized.contains('impag') ||
        normalized.contains('unpaid') ||
        normalized.contains('pendiente') ||
        normalized.contains('sin pagar') ||
        normalized.contains('no pagad') ||
        normalized.contains('por cobrar');
    final wantsOverdue =
        normalized.contains('vencid') || normalized.contains('overdue');
    final wantsRecent = normalized.contains('ultima') ||
        normalized.contains('ultim') ||
        normalized.contains('last') ||
        normalized.contains('latest') ||
        normalized.contains('reciente');
    final extractedSearchTerm = _extractInvoiceSearchTerm(message);
    final wantsDirectLookup =
        extractedSearchTerm.isNotEmpty && _isDirectInvoiceLookup(normalized);

    if (!wantsUnpaid && !wantsOverdue && !wantsRecent && !wantsDirectLookup) {
      return null;
    }

    if (salesService.invoices.isEmpty) {
      await salesService.loadInvoices();
    }

    // `loadInvoices` swallows its own failure and leaves the list empty, so
    // without this the assistant would answer "no tienes facturas" to a read
    // that never happened.
    final invoiceError = salesService.invoiceError;
    if (invoiceError != null) {
      throw const AIAssistantSourceUnavailable(
        'facturas de venta',
        'the invoice read failed',
      );
    }
    if (salesService.invoices.isEmpty) {
      throw const AIAssistantSourceUnavailable(
        'facturas de venta',
        'an empty read has no authority-bound receipt',
      );
    }

    // SalesService publishes no authority, so every invoice it holds is
    // checked. An invoice from another taller must stop the answer, not be
    // quietly dropped from a total.
    final verifiedSalesInvoices = authority.verifyRows(
      'facturas de venta',
      salesService.invoices,
      (invoice) => invoice.tenantId,
    );

    final now = DateTime.now();
    var filtered = verifiedSalesInvoices.where((invoice) {
      if (invoice.status == InvoiceStatus.cancelled) return false;
      if (wantsUnpaid && invoice.balance <= 0.01) return false;
      if (wantsOverdue) {
        final dueDate = invoice.dueDate;
        if (dueDate == null ||
            !dueDate.isBefore(now) ||
            invoice.balance <= 0.01) {
          return false;
        }
      }
      return true;
    }).toList();

    if (extractedSearchTerm.isNotEmpty) {
      filtered = filtered
          .where((invoice) => _invoiceMatchesSearchTerm(
                searchTerm: extractedSearchTerm,
                invoiceNumber: invoice.invoiceNumber,
                partyName: invoice.customerName,
                reference: invoice.reference,
              ))
          .toList();
    }

    if (filtered.isEmpty) {
      if (extractedSearchTerm.isNotEmpty) {
        return _textResponse(
            'No encontré facturas de venta que coincidan con "$extractedSearchTerm".');
      }
      if (wantsOverdue) {
        return _textResponse(
            'No encontré facturas de venta vencidas y pendientes en este momento.');
      }
      if (wantsUnpaid) {
        return _textResponse(
            'No encontré facturas de venta pendientes de cobro en este momento.');
      }
      return _textResponse('No encontré facturas de venta que coincidan.');
    }

    filtered.sort((a, b) {
      if (extractedSearchTerm.isNotEmpty) {
        final scoreA = _invoiceMatchScore(
          searchTerm: extractedSearchTerm,
          invoiceNumber: a.invoiceNumber,
          partyName: a.customerName,
          reference: a.reference,
        );
        final scoreB = _invoiceMatchScore(
          searchTerm: extractedSearchTerm,
          invoiceNumber: b.invoiceNumber,
          partyName: b.customerName,
          reference: b.reference,
        );
        if (scoreA != scoreB) {
          return scoreB.compareTo(scoreA);
        }
      }

      if (wantsOverdue) {
        final aDue = a.dueDate ?? a.date;
        final bDue = b.dueDate ?? b.date;
        return aDue.compareTo(bDue);
      }
      return b.date.compareTo(a.date);
    });

    final wantsMultiple = normalized.contains('facturas') ||
        normalized.contains('invoices') ||
        normalized.contains('muestrame') ||
        normalized.contains('listame') ||
        normalized.contains('show me') ||
        normalized.contains('all ');

    final shouldReturnSingle = !wantsMultiple &&
        (wantsRecent || _looksLikeInvoiceIdentifier(extractedSearchTerm));

    final limited = filtered.take(shouldReturnSingle ? 1 : 3).toList();
    final cards = limited.map(_buildSalesInvoiceCard).toList();

    if (limited.length == 1) {
      final invoice = limited.first;
      final intro = wantsOverdue
          ? 'La factura de venta vencida más urgente es ${invoice.invoiceNumber}.'
          : wantsUnpaid
              ? 'La última factura de venta pendiente es ${invoice.invoiceNumber}.'
              : wantsDirectLookup
                  ? 'Encontré la factura de venta ${invoice.invoiceNumber}.'
                  : 'La factura de venta más reciente es ${invoice.invoiceNumber}.';
      return _cardResponse(
        intro,
        cards: cards,
      );
    }

    final headline = wantsOverdue
        ? 'Encontré ${limited.length} facturas de venta vencidas que puedes abrir directo desde aquí.'
        : wantsUnpaid
            ? 'Encontré ${limited.length} facturas de venta pendientes que puedes abrir directo desde aquí.'
            : wantsDirectLookup
                ? 'Encontré ${limited.length} facturas de venta para "$extractedSearchTerm" que puedes abrir directo desde aquí.'
                : extractedSearchTerm.isNotEmpty && !mentionsSales
                    ? 'Encontré ${limited.length} facturas de venta para "$extractedSearchTerm" que puedes abrir directo desde aquí.'
                    : 'Encontré ${limited.length} facturas de venta recientes que puedes abrir directo desde aquí.';

    return _cardResponse(headline, cards: cards);
  }

  String _extractInvoiceSearchTerm(String message) {
    var normalized = _normalizeText(message);

    final patterns = <Pattern>[
      RegExp(r'\bbuscame\b'),
      RegExp(r'\bbusca\b'),
      RegExp(r'\bmuestrame\b'),
      RegExp(r'\bquiero ver\b'),
      RegExp(r'\bultima\b'),
      RegExp(r'\bultimo\b'),
      RegExp(r'\bultimas\b'),
      RegExp(r'\bultimos\b'),
      RegExp(r'\breciente\b'),
      RegExp(r'\brecientes\b'),
      RegExp(r'\bultimas?\b'),
      RegExp(r'\blast\b'),
      RegExp(r'\blatest\b'),
      RegExp(r'\bfactura\b'),
      RegExp(r'\bfacturas\b'),
      RegExp(r'\binvoice\b'),
      RegExp(r'\binvoices\b'),
      RegExp(r'\bde venta\b'),
      RegExp(r'\bventa\b'),
      RegExp(r'\bsales\b'),
      RegExp(r'\bde compra\b'),
      RegExp(r'\bcompra\b'),
      RegExp(r'\bpurchase\b'),
      RegExp(r'\bcliente\b'),
      RegExp(r'\bproveedor\b'),
      RegExp(r'\bimpaga\b'),
      RegExp(r'\bimpagas\b'),
      RegExp(r'\bimpago\b'),
      RegExp(r'\bimpagos\b'),
      RegExp(r'\bunpaid\b'),
      RegExp(r'\bpendiente\b'),
      RegExp(r'\bpendientes\b'),
      RegExp(r'\bsin pagar\b'),
      RegExp(r'\bpor pagar\b'),
      RegExp(r'\bpor cobrar\b'),
      RegExp(r'\bno pagada\b'),
      RegExp(r'\bno pagado\b'),
      RegExp(r'\bvencida\b'),
      RegExp(r'\bvencidas\b'),
      RegExp(r'\boverdue\b'),
      RegExp(r'\bla\b'),
      RegExp(r'\bel\b'),
      RegExp(r'\blas\b'),
      RegExp(r'\blos\b'),
    ];

    for (final pattern in patterns) {
      normalized = normalized.replaceAll(pattern, ' ');
    }

    normalized = normalized.replaceFirst(RegExp(r'^\s*(de|del)\s+'), '');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  bool _invoiceMatchesSearchTerm({
    required String searchTerm,
    required String invoiceNumber,
    String? partyName,
    String? reference,
  }) {
    if (searchTerm.isEmpty) return true;

    final haystack = _normalizeText(
      '$invoiceNumber ${partyName ?? ''} ${reference ?? ''}',
    );
    final tokens = searchTerm
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();

    return tokens.every(haystack.contains);
  }

  bool _isDirectInvoiceLookup(String normalizedMessage) {
    return normalizedMessage.contains('busc') ||
        normalizedMessage.contains('muestr') ||
        normalizedMessage.contains('mostra') ||
        normalizedMessage.contains('quiero ver') ||
        normalizedMessage.contains('abr') ||
        normalizedMessage.contains('open');
  }

  bool _looksLikeInvoiceIdentifier(String searchTerm) {
    if (searchTerm.isEmpty) return false;
    final compact =
        _normalizeText(searchTerm).replaceAll(RegExp(r'[\s-]+'), '');
    return RegExp(r'^[a-z]{1,4}\d{2,}$').hasMatch(compact);
  }

  int _invoiceMatchScore({
    required String searchTerm,
    required String invoiceNumber,
    String? partyName,
    String? reference,
  }) {
    if (searchTerm.isEmpty) return 0;

    final normalizedSearch = _normalizeText(searchTerm).trim();
    final normalizedInvoice = _normalizeText(invoiceNumber).trim();
    final normalizedParty = _normalizeText(partyName ?? '').trim();
    final normalizedReference = _normalizeText(reference ?? '').trim();
    final compactSearch = normalizedSearch.replaceAll(RegExp(r'[\s-]+'), '');
    final compactInvoice = normalizedInvoice.replaceAll(RegExp(r'[\s-]+'), '');
    final tokens = normalizedSearch
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();

    var score = 0;

    if (normalizedInvoice == normalizedSearch ||
        compactInvoice == compactSearch) {
      score += 1000;
    }
    if (normalizedReference == normalizedSearch) {
      score += 700;
    }
    if (normalizedParty == normalizedSearch) {
      score += 600;
    }
    if (normalizedInvoice.contains(normalizedSearch)) {
      score += 350;
    }
    if (normalizedReference.contains(normalizedSearch)) {
      score += 250;
    }
    if (normalizedParty.contains(normalizedSearch)) {
      score += 200;
    }

    for (final token in tokens) {
      if (normalizedInvoice.contains(token)) score += 70;
      if (normalizedReference.contains(token)) score += 50;
      if (normalizedParty.contains(token)) score += 35;
    }

    return score;
  }

  AIAssistantActionCard _buildSalesInvoiceCard(Invoice invoice) {
    final customer = (invoice.customerName ?? 'Cliente sin nombre').trim();
    final subtitle = [
      customer,
      'Fecha ${ChileanUtils.formatDate(invoice.date)}',
      if (invoice.dueDate != null)
        'Vence ${ChileanUtils.formatDate(invoice.dueDate!)}',
    ].join(' • ');

    final description =
        'Total ${ChileanUtils.formatCurrency(invoice.total)} • Saldo ${ChileanUtils.formatCurrency(invoice.balance)}';

    return AIAssistantActionCard(
      kind: 'sales_invoice',
      eyebrow: 'Factura de venta',
      title: invoice.invoiceNumber,
      subtitle: subtitle,
      description: description,
      destination: AIAssistantDestination.salesInvoices,
      chips: [
        _salesInvoiceStatusLabel(invoice.status),
        if (invoice.balance > 0.01) 'Pendiente',
        if (invoice.balance <= 0.01) 'Pagada',
      ],
    );
  }

  String _salesInvoiceStatusLabel(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return 'Borrador';
      case InvoiceStatus.sent:
        return 'Enviada';
      case InvoiceStatus.confirmed:
        return 'Confirmada';
      case InvoiceStatus.paid:
        return 'Pagada';
      case InvoiceStatus.overdue:
        return 'Vencida';
      case InvoiceStatus.cancelled:
        return 'Anulada';
    }
  }

  Future<AIAssistantResponse?> _tryHandlePurchaseInvoiceCards(
    String message, {
    PurchaseService? purchaseService,
    required AIAssistantTurnAuthority authority,
  }) async {
    if (purchaseService == null) {
      return null;
    }

    final normalized = _normalizeText(message);
    final mentionsInvoice =
        normalized.contains('factura') || normalized.contains('invoice');
    final mentionsPurchase = normalized.contains('compra') ||
        normalized.contains('purchase') ||
        normalized.contains('proveedor');

    if (!mentionsInvoice || !mentionsPurchase) {
      return null;
    }

    final wantsUnpaid = normalized.contains('impag') ||
        normalized.contains('unpaid') ||
        normalized.contains('pendiente') ||
        normalized.contains('sin pagar') ||
        normalized.contains('no pagad') ||
        normalized.contains('por pagar');
    final wantsOverdue =
        normalized.contains('vencid') || normalized.contains('overdue');
    final wantsRecent = normalized.contains('ultima') ||
        normalized.contains('ultim') ||
        normalized.contains('last') ||
        normalized.contains('latest') ||
        normalized.contains('reciente');
    final extractedSearchTerm = _extractInvoiceSearchTerm(message);
    final wantsDirectLookup =
        extractedSearchTerm.isNotEmpty && _isDirectInvoiceLookup(normalized);

    if (!wantsUnpaid && !wantsOverdue && !wantsRecent && !wantsDirectLookup) {
      return null;
    }

    final loadedInvoices = await purchaseService.getPurchaseInvoices();
    if (loadedInvoices.isEmpty) {
      throw const AIAssistantSourceUnavailable(
        'facturas de compra',
        'an empty read has no authority-bound receipt',
      );
    }
    final invoices = authority.verifyRows(
      'facturas de compra',
      loadedInvoices,
      (invoice) => invoice.tenantId,
    );
    final now = DateTime.now();

    var filtered = invoices.where((invoice) {
      if (invoice.status == PurchaseInvoiceStatus.cancelled) return false;
      if (wantsUnpaid && invoice.balance <= 0.01) return false;
      if (wantsOverdue) {
        final dueDate = invoice.dueDate;
        if (dueDate == null ||
            !dueDate.isBefore(now) ||
            invoice.balance <= 0.01) {
          return false;
        }
      }
      return true;
    }).toList();

    if (extractedSearchTerm.isNotEmpty) {
      filtered = filtered
          .where((invoice) => _invoiceMatchesSearchTerm(
                searchTerm: extractedSearchTerm,
                invoiceNumber: invoice.invoiceNumber,
                partyName: invoice.supplierName,
                reference: invoice.reference,
              ))
          .toList();
    }

    if (filtered.isEmpty) {
      if (extractedSearchTerm.isNotEmpty) {
        return _textResponse(
            'No encontré facturas de compra que coincidan con "$extractedSearchTerm".');
      }
      if (wantsOverdue) {
        return _textResponse(
            'No encontré facturas de compra vencidas y pendientes en este momento.');
      }
      if (wantsUnpaid) {
        return _textResponse(
            'No encontré facturas de compra pendientes de pago en este momento.');
      }
      return _textResponse('No encontré facturas de compra que coincidan.');
    }

    filtered.sort((a, b) {
      if (extractedSearchTerm.isNotEmpty) {
        final scoreA = _invoiceMatchScore(
          searchTerm: extractedSearchTerm,
          invoiceNumber: a.invoiceNumber,
          partyName: a.supplierName,
          reference: a.reference,
        );
        final scoreB = _invoiceMatchScore(
          searchTerm: extractedSearchTerm,
          invoiceNumber: b.invoiceNumber,
          partyName: b.supplierName,
          reference: b.reference,
        );
        if (scoreA != scoreB) {
          return scoreB.compareTo(scoreA);
        }
      }

      if (wantsOverdue) {
        final aDue = a.dueDate ?? a.date;
        final bDue = b.dueDate ?? b.date;
        return aDue.compareTo(bDue);
      }
      return b.date.compareTo(a.date);
    });

    final wantsMultiple = normalized.contains('facturas') ||
        normalized.contains('invoices') ||
        normalized.contains('muestrame') ||
        normalized.contains('muestrame') ||
        normalized.contains('listame') ||
        normalized.contains('show me') ||
        normalized.contains('all ');

    final shouldReturnSingle = !wantsMultiple &&
        (wantsRecent || _looksLikeInvoiceIdentifier(extractedSearchTerm));

    final limited = filtered.take(shouldReturnSingle ? 1 : 3).toList();
    final cards = limited.map(_buildPurchaseInvoiceCard).toList();

    if (limited.length == 1) {
      final invoice = limited.first;
      final intro = wantsOverdue
          ? 'La factura de compra vencida más urgente es ${invoice.invoiceNumber}.'
          : wantsUnpaid
              ? 'La última factura de compra pendiente es ${invoice.invoiceNumber}.'
              : wantsDirectLookup
                  ? 'Encontré la factura de compra ${invoice.invoiceNumber}.'
                  : 'La factura de compra más reciente es ${invoice.invoiceNumber}.';
      return _cardResponse(
        intro,
        cards: cards,
      );
    }

    final headline = wantsOverdue
        ? 'Encontré ${limited.length} facturas de compra vencidas que puedes abrir directo desde aquí.'
        : wantsUnpaid
            ? 'Encontré ${limited.length} facturas de compra pendientes que puedes abrir directo desde aquí.'
            : wantsDirectLookup
                ? 'Encontré ${limited.length} facturas de compra para "$extractedSearchTerm" que puedes abrir directo desde aquí.'
                : 'Encontré ${limited.length} facturas de compra recientes que puedes abrir directo desde aquí.';

    return _cardResponse(headline, cards: cards);
  }

  AIAssistantActionCard _buildPurchaseInvoiceCard(PurchaseInvoice invoice) {
    final supplier = (invoice.supplierName ?? 'Proveedor sin nombre').trim();
    final subtitle = [
      supplier,
      'Fecha ${ChileanUtils.formatDate(invoice.date)}',
      if (invoice.dueDate != null)
        'Vence ${ChileanUtils.formatDate(invoice.dueDate!)}',
    ].join(' • ');

    final description =
        'Total ${ChileanUtils.formatCurrency(invoice.total)} • Saldo ${ChileanUtils.formatCurrency(invoice.balance)}';

    return AIAssistantActionCard(
      kind: 'purchase_invoice',
      eyebrow: 'Factura de compra',
      title: invoice.invoiceNumber,
      subtitle: subtitle,
      description: description,
      destination: AIAssistantDestination.purchases,
      chips: [
        invoice.status.displayName,
        if (invoice.balance > 0.01) 'Pendiente',
        if (invoice.balance <= 0.01) 'Pagada',
      ],
    );
  }

  /// Builds the sentence the operator reads about a search.
  ///
  /// The stock ratio is the defect this method exists to prevent: it used to
  /// count in-stock rows over the truncated sample it displays while printing
  /// the total match count as the denominator, so a search of 27 products
  /// reported "3 de 27 con stock" when the real answer was 5 of 26. Both
  /// numbers now come from the same set, computed by the search tool over the
  /// complete result.
  String? _buildDeterministicInventoryReply(
    Map<String, Object?>? searchResult,
  ) {
    if (searchResult == null) {
      return null;
    }

    if (searchResult['status'] == 'verifiedEmpty') {
      return 'No encontré productos que coincidan con esa búsqueda en el '
          'inventario verificado.';
    }

    if (searchResult['status'] == 'unavailable') {
      return 'No pude confirmar el inventario en este momento. Intenta '
          'nuevamente en unos segundos.';
    }

    if (searchResult.containsKey('result')) {
      final raw = searchResult['result']?.toString();
      if (raw != null && raw.isNotEmpty) {
        return raw;
      }
    }

    final productsRaw = searchResult['products'];
    final count = (searchResult['count'] as num?)?.toInt() ?? 0;
    if (productsRaw is! List || productsRaw.isEmpty) {
      return null;
    }

    final products = productsRaw
        .whereType<Map>()
        .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .cast<Map<String, dynamic>>()
        .toList();

    // Counted by the search tool over every match, not over the sample below.
    // Absent means the ratio cannot be stated honestly, so it is not stated.
    return buildInventorySearchSentence(
      count: count,
      inStockCount: (searchResult['inStockCount'] as num?)?.toInt(),
      sampleNames: products
          .map((product) => (product['name'] ?? '').toString())
          .toList(),
      searchTerm: _lastInventorySearchTerm,
    );
  }

  double _availableInventoryStock(Map<String, dynamic> product) {
    return (product['available_stock_quantity'] as num?)?.toDouble() ??
        (product['stock'] as num?)?.toDouble() ??
        (product['inventory_qty'] as num?)?.toDouble() ??
        0;
  }

  List<AIAssistantActionCard> _buildInventoryCardsFromSearchResult(
      Map<String, Object?>? searchResult) {
    final productsRaw = searchResult?['products'];
    if (productsRaw is! List || productsRaw.isEmpty) {
      return const [];
    }

    final products = productsRaw
        .whereType<Map>()
        .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .cast<Map<String, dynamic>>()
        .toList();

    return products
        .where((product) => (product['id'] ?? '').toString().isNotEmpty)
        .take(5)
        .map(_buildInventoryProductCard)
        .toList();
  }

  AIAssistantActionCard _buildInventoryProductCard(
      Map<String, dynamic> product) {
    final brand = (product['brand'] ?? '').toString().trim();
    final sku = (product['sku'] ?? '').toString().trim();
    final category =
        (product['category'] ?? product['category_name'] ?? '').toString();
    final stock = _availableInventoryStock(product);
    final locationFragment = buildProductLocationFragment(
      product['location'] ?? product['warehouse_location'],
    );
    final stockLabel =
        stock % 1 == 0 ? stock.toInt().toString() : stock.toStringAsFixed(2);

    final subtitle = [
      if (brand.isNotEmpty) brand,
      if (category.isNotEmpty) category,
      if (sku.isNotEmpty) 'SKU $sku',
    ].join(' • ');

    return AIAssistantActionCard(
      kind: 'inventory',
      eyebrow: 'Producto',
      title: (product['name'] ?? 'Producto').toString(),
      subtitle: subtitle.isEmpty ? null : subtitle,
      description: [
        'Precio ${ChileanUtils.formatCurrency((product['price'] as num?)?.toDouble() ?? 0)}',
        'Stock $stockLabel',
        if (locationFragment != null) locationFragment,
      ].join(' • '),
      destination: AIAssistantDestination.inventoryProducts,
      chips: [
        if (stock > 0) 'Con stock' else 'Sin stock',
      ],
    );
  }

  /// Drops every trace of the current conversation.
  ///
  /// The refinement state matters as much as the history: `_lastSearchResults`
  /// is what makes the assistant say "tomé la búsqueda anterior", so leaving it
  /// behind lets one session narrate another session's search.
  @override
  void resetChat() {
    _history.clear();
    _turnSequence = 0;
    _sessionId = _idFactory();
    _lastSearchResults = [];
    _lastInventorySearchTerm = null;
    notifyListeners();
  }

  // --- Tool Implementations ---

  bool _messageMentionsStockAvailable(String message) {
    final normalized = _normalizeText(message);
    return normalized.contains('con stock') ||
        normalized.contains('en stock') ||
        normalized.contains('que tengan stock') ||
        normalized.contains('que tenga stock') ||
        normalized.contains('disponible') ||
        normalized.contains('disponibles') ||
        normalized.contains('hay stock');
  }

  bool _messageMentionsOutOfStock(String message) {
    final normalized = _normalizeText(message);
    return normalized.contains('sin stock') ||
        normalized.contains('agotado') ||
        normalized.contains('agotados');
  }

  bool _containsExplicitInventoryTarget(String message) {
    final normalized = _normalizeText(message);
    const targetHints = [
      'camara',
      'llanta',
      'cubierta',
      'neumatico',
      'rueda',
      'aro',
      'cassette',
      'freno',
      'cadena',
      'manubrio',
      'horquilla',
      'pedal',
      'masa',
      'buje',
      'rayos',
      'piñon',
      'pinon',
    ];

    return targetHints.any(normalized.contains);
  }

  String _normalizeInventoryLookupQuery(String query) {
    var normalized = query.toLowerCase().trim();

    final patterns = <Pattern>[
      RegExp(r'\bbuscame\b'),
      RegExp(r'\bbusca\b'),
      RegExp(r'\bmu[eé]strame\b'),
      RegExp(r'\bquiero ver\b'),
      RegExp(r'\bnecesito\b'),
      RegExp(r'\bsolo\b'),
      RegExp(r'\bsolamente\b'),
      RegExp(r'\bque tengan stock\b'),
      RegExp(r'\bque tenga stock\b'),
      RegExp(r'\bcon stock\b'),
      RegExp(r'\ben stock\b'),
      RegExp(r'\bdisponibles\b'),
      RegExp(r'\bdisponible\b'),
      RegExp(r'\bpor favor\b'),
    ];

    for (final pattern in patterns) {
      normalized = normalized.replaceAll(pattern, ' ');
    }

    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.isEmpty ? query.trim() : normalized;
  }

  String _normalizeText(String text) {
    if (text.isEmpty) return text;

    String normalized = text.toLowerCase();
    normalized = normalized.replaceAll(RegExp(r'[áàäâ]'), 'a');
    normalized = normalized.replaceAll(RegExp(r'[éèëê]'), 'e');
    normalized = normalized.replaceAll(RegExp(r'[íìïî]'), 'i');
    normalized = normalized.replaceAll(RegExp(r'[óòöô]'), 'o');
    normalized = normalized.replaceAll(RegExp(r'[úùüû]'), 'u');
    normalized = normalized.replaceAll(RegExp(r'[ñ]'), 'n');
    normalized = normalized.replaceAll(RegExp(r'[ç]'), 'c');
    return normalized;
  }

  String? _detectRequestedProductType(String query) {
    final normalized = _normalizeText(query);
    if (normalized.contains('camara')) return 'camara';
    if (normalized.contains('llanta') || normalized.contains('aro')) {
      return 'llanta';
    }
    if (normalized.contains('neumatico')) {
      return 'neumatico';
    }
    if (normalized.contains('cubierta')) {
      return 'cubierta';
    }
    if (normalized.contains('cassette')) return 'cassette';
    if (normalized.contains('cadena')) return 'cadena';
    if (normalized.contains('freno')) return 'freno';
    return null;
  }

  bool _matchesRequestedProductType(
      Map<String, dynamic> product, String requestedType) {
    final haystack = _normalizeText(
        '${product['name'] ?? ''} ${product['category_name'] ?? product['category'] ?? ''}');

    switch (requestedType) {
      case 'camara':
        return haystack.contains('camara');
      case 'llanta':
        return haystack.contains('llanta') || haystack.contains('aro');
      case 'neumatico':
        return haystack.contains('neumatico') || haystack.contains('cubierta');
      case 'cubierta':
        return haystack.contains('cubierta') || haystack.contains('neumatico');
      case 'cassette':
        return haystack.contains('cassette');
      case 'cadena':
        return haystack.contains('cadena');
      case 'freno':
        return haystack.contains('freno');
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _applyInventoryIntentFilters(
    String originalQuery,
    List<Map<String, dynamic>> results,
  ) {
    var filtered = List<Map<String, dynamic>>.from(results);

    final requestedType = _detectRequestedProductType(originalQuery);
    if (requestedType != null) {
      filtered = filtered
          .where(
              (product) => _matchesRequestedProductType(product, requestedType))
          .toList();
    }

    final wantsInStock = _messageMentionsStockAvailable(originalQuery);
    final wantsOutOfStock = _messageMentionsOutOfStock(originalQuery);

    if (wantsInStock) {
      filtered = filtered.where((product) {
        final stock = _availableInventoryStock(product);
        return stock > 0;
      }).toList();
    } else if (wantsOutOfStock) {
      filtered = filtered.where((product) {
        final stock = _availableInventoryStock(product);
        return stock <= 0;
      }).toList();
    }

    return filtered;
  }

  List<String> _buildKeywordSearchQueries(String query) {
    final normalized = _normalizeInventoryLookupQuery(query);
    final simplified = _simplifyInventorySearchTerm(normalized);
    final requestedType = _detectRequestedProductType(normalized);
    final sizeMatch =
        RegExp(r'\b(20|24|26|27\.5|27,5|29)\b').firstMatch(normalized);
    final sizeToken = sizeMatch?.group(1)?.replaceAll(',', '.');

    final queries = <String>{};

    void addQuery(String base) {
      final trimmedBase = base.trim();
      if (trimmedBase.isEmpty) return;
      final fullQuery = sizeToken != null && !trimmedBase.contains(sizeToken)
          ? '$trimmedBase $sizeToken'
          : trimmedBase;
      queries.add(fullQuery.trim());
    }

    addQuery(normalized);
    addQuery(simplified);

    switch (requestedType) {
      case 'neumatico':
        addQuery('neumatico');
        addQuery('cubierta');
        break;
      case 'cubierta':
        addQuery('cubierta');
        addQuery('neumatico');
        break;
      case 'llanta':
        addQuery('llanta');
        addQuery('aro');
        break;
      case 'camara':
        addQuery('camara');
        addQuery('tubo');
        break;
      default:
        break;
    }

    return queries.toList();
  }

  bool _messageLooksLikeDirectInventorySearch(String message) {
    final normalized = _normalizeText(message);
    if (!_containsExplicitInventoryTarget(normalized)) {
      return false;
    }

    return normalized.contains('busc') ||
        normalized.contains('muestr') ||
        normalized.contains('mostrar') ||
        normalized.contains('quiero ver') ||
        normalized.contains('necesito') ||
        normalized.contains('tienes') ||
        normalized.contains('hay ') ||
        normalized.startsWith('llanta ') ||
        normalized.startsWith('camara ') ||
        normalized.startsWith('neumatico ') ||
        normalized.startsWith('cubierta ');
  }

  Future<AIAssistantResponse?> _tryHandleDirectInventorySearch(
    String message, {
    InventoryService? inventoryService,
    required AIAssistantTurnAuthority authority,
  }) async {
    if (inventoryService == null) {
      return null;
    }

    if (_messageAsksForWidthComparison(message) ||
        !_messageLooksLikeDirectInventorySearch(message)) {
      return null;
    }

    final searchResult =
        await _toolSearchStock(message, inventoryService, authority);
    final text = _buildDeterministicInventoryReply(searchResult);
    if (text == null) {
      return null;
    }

    return _textResponse(
      text,
      cards: _buildInventoryCardsFromSearchResult(searchResult),
    );
  }

  bool _messageAsksForWidthComparison(String message) {
    final normalized = _normalizeText(message);
    return (normalized.contains('rango') &&
            (normalized.contains('ancho') ||
                normalized.contains('neumatico') ||
                normalized.contains('neumático') ||
                normalized.contains('cubierta'))) ||
        normalized.contains('mas ancho') ||
        normalized.contains('más ancho') ||
        normalized.contains('ancho maximo') ||
        normalized.contains('ancho máximo') ||
        normalized.contains('ancho max') ||
        normalized.contains('ancho más grande') ||
        normalized.contains('mas grande de ancho') ||
        normalized.contains('acepte el neumatico mas ancho') ||
        normalized.contains('acepte el neumático más ancho') ||
        normalized.contains('mayor compatibilidad de ancho');
  }

  _TireWidthRange? _extractTireWidthRange(String text) {
    final normalized = _normalizeText(text).replaceAll(',', '.');
    final patterns = [
      RegExp(
          r'(?:^|[^0-9])(?:\d+(?:\.\d+)?)\s*x\s*(\d+(?:\.\d+)?)\s*(?:/|-)\s*(\d+(?:\.\d+)?)(?:[^0-9]|$)'),
      RegExp(r'(\d+(?:\.\d+)?)\s*(?:/|-)\s*(\d+(?:\.\d+)?)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(normalized);
      if (match == null) {
        continue;
      }

      final first = double.tryParse(match.group(1) ?? '');
      final second = double.tryParse(match.group(2) ?? '');
      if (first == null || second == null) {
        continue;
      }

      final minWidth = first < second ? first : second;
      final maxWidth = first > second ? first : second;

      if (minWidth < 0.5 || maxWidth > 5) {
        continue;
      }

      return _TireWidthRange(minWidth: minWidth, maxWidth: maxWidth);
    }

    return null;
  }

  String? _tryHandleInventoryComparison(String message) {
    if (_lastSearchResults.isEmpty ||
        !_messageAsksForWidthComparison(message)) {
      return null;
    }

    var candidates = List<Map<String, dynamic>>.from(_lastSearchResults);
    final wantsInStock = _messageMentionsStockAvailable(message);
    final wantsOutOfStock = _messageMentionsOutOfStock(message);

    if (wantsInStock) {
      candidates = candidates.where((product) {
        final stock = _availableInventoryStock(product);
        return stock > 0;
      }).toList();
    } else if (wantsOutOfStock) {
      candidates = candidates.where((product) {
        final stock = _availableInventoryStock(product);
        return stock <= 0;
      }).toList();
    }

    final analyzed = candidates
        .map((product) {
          final name = (product['name'] ?? '').toString();
          final range = _extractTireWidthRange(name);
          if (range == null) {
            return null;
          }
          final stock = _availableInventoryStock(product);
          return _WidthComparisonCandidate(
            product: product,
            range: range,
            stock: stock,
          );
        })
        .whereType<_WidthComparisonCandidate>()
        .toList();

    if (analyzed.isEmpty) {
      return null;
    }

    analyzed.sort((a, b) {
      final maxCompare = b.range.maxWidth.compareTo(a.range.maxWidth);
      if (maxCompare != 0) return maxCompare;
      final spanCompare = b.range.span.compareTo(a.range.span);
      if (spanCompare != 0) return spanCompare;
      return b.stock.compareTo(a.stock);
    });
    final widestSupport = analyzed.first;

    final bySpan = [...analyzed]..sort((a, b) {
        final spanCompare = b.range.span.compareTo(a.range.span);
        if (spanCompare != 0) return spanCompare;
        final maxCompare = b.range.maxWidth.compareTo(a.range.maxWidth);
        if (maxCompare != 0) return maxCompare;
        return b.stock.compareTo(a.stock);
      });
    final widestSpan = bySpan.first;

    final productName =
        (widestSupport.product['name'] ?? 'Producto').toString();
    final stockLabel = widestSupport.stock % 1 == 0
        ? widestSupport.stock.toInt().toString()
        : widestSupport.stock.toStringAsFixed(2);

    if (widestSupport.product['sku'] == widestSpan.product['sku']) {
      return 'De las opciones actuales, la que mejor aguanta neumáticos más anchos es $productName. '
          'Su rango publicado es ${widestSupport.range.label}, así que llega hasta ${_TireWidthRange._format(widestSupport.range.maxWidth)}. '
          'Además, es la que ofrece el mayor rango útil dentro de esta lista. Stock actual: $stockLabel.';
    }

    final spanProductName =
        (widestSpan.product['name'] ?? 'Producto').toString();
    return 'Revisando las medidas publicadas en los nombres: si por "mayor rango de ancho" te refieres a la que acepta neumáticos más anchos, la mejor opción es $productName, '
        'porque va de ${widestSupport.range.label} y llega hasta ${_TireWidthRange._format(widestSupport.range.maxWidth)}. '
        'Si lo interpretas como la mayor diferencia entre mínimo y máximo, entonces $spanProductName abre un poco más: ${widestSpan.range.label} '
        '(amplitud ${_TireWidthRange._format(widestSpan.range.span)} frente a ${_TireWidthRange._format(widestSupport.range.span)}). '
        'En tu captura, para montar el neumático más ancho la Maxxis es la correcta.';
  }

  String? _tryHandleInventoryRefinement(
    String message, {
    InventoryService? inventoryService,
  }) {
    if (_lastSearchResults.isEmpty || _lastInventorySearchTerm == null) {
      return null;
    }

    final wantsInStock = _messageMentionsStockAvailable(message);
    final wantsOutOfStock = _messageMentionsOutOfStock(message);

    if (!wantsInStock && !wantsOutOfStock) {
      return null;
    }

    // Only reuse the previous result set for true follow-up messages.
    // If the user mentions a new product target (for example, switching from
    // "camaras" to "llantas"), let the model perform a fresh search.
    if (_containsExplicitInventoryTarget(message)) {
      final requestedSearchTerm = _simplifyInventorySearchTerm(message);
      if (requestedSearchTerm.isNotEmpty &&
          requestedSearchTerm != _lastInventorySearchTerm) {
        return null;
      }
    }

    final filtered = _lastSearchResults.where((result) {
      final stock = _availableInventoryStock(result);
      if (wantsOutOfStock) {
        return stock <= 0;
      }
      return stock > 0;
    }).toList();

    if (filtered.isNotEmpty) {
      _lastSearchResults =
          filtered.map((item) => Map<String, dynamic>.from(item)).toList();
    }

    // Refining a result set no longer drives the operator's workspace. The
    // inventory surface is reached by clicking the card, never as a side
    // effect of asking a question.
    if (filtered.isEmpty) {
      return wantsOutOfStock
          ? 'Tomé la búsqueda anterior y la dejé solo en productos sin stock. No encontré coincidencias con ese criterio.'
          : 'Tomé la búsqueda anterior y la dejé solo en productos con stock. No encontré coincidencias con ese criterio.';
    }

    final intro = wantsOutOfStock
        ? 'Tomé la búsqueda anterior y la reduje solo a los que están sin stock.'
        : 'Tomé la búsqueda anterior y la reduje solo a los que sí tienen stock.';
    final sampleNames = filtered
        .take(2)
        .map((product) => (product['name'] ?? 'Producto').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();
    final sampleSentence = sampleNames.isEmpty
        ? ''
        : sampleNames.length == 1
            ? ' Ejemplo: ${sampleNames.first}.'
            : ' Ejemplos: ${sampleNames.first} y ${sampleNames[1]}.';

    return '$intro Encontré ${filtered.length} coincidencias.$sampleSentence';
  }

  Future<Map<String, Object?>> _toolSearchStock(
    String? query,
    InventoryService? inventory,
    AIAssistantTurnAuthority authority,
  ) async {
    if (query == null || query.trim().isEmpty) {
      return const <String, Object?>{
        'status': 'unavailable',
        'errorCode': 'invalid_inventory_query',
      };
    }
    if (inventory == null) {
      return const <String, Object?>{
        'status': 'unavailable',
        'errorCode': 'inventory_service_unavailable',
      };
    }

    try {
      final lookupQuery = _normalizeInventoryLookupQuery(query);
      _debugAi('🔍 [AI] Inventory search started.');

      // Run BOTH searches in parallel for best results
      final List<Map<String, dynamic>> semanticResults = [];
      final List<Map<String, dynamic>> keywordResults = [];

      // 1. Semantic search (high threshold = only relevant results).
      //
      // This one may degrade: it is an enrichment over the catalog, and it
      // only degrades because the keyword read below is authoritative. If that
      // read fails too, the whole source fails — an unanswered query must not
      // become "no encontré nada".
      try {
        final vector = await generateEmbedding(lookupQuery);
        if (vector != null) {
          final results = await inventory.searchProductsSemantic(vector);
          semanticResults.addAll(results);
          _debugAi('🧠 [AI] Semantic inventory enrichment completed.');
        }
      } catch (_) {
        _debugAi('⚠️ [AI] Semantic inventory enrichment degraded.');
      }

      // 2. Keyword search — the authoritative catalog read.
      //
      // Its failure is not a smaller result set, it is the absence of an
      // answer. Zero is only ever reported after this completed.
      try {
        final keywordQueries = _buildKeywordSearchQueries(lookupQuery);
        for (final keywordQuery in keywordQueries) {
          final products = await inventory.searchProductPreviews(
            keywordQuery,
            limit: 30,
          );
          keywordResults.addAll(products.take(30).map((p) => {
                'id': p.id,
                'name': p.name,
                'sku': p.sku,
                'brand': p.brand ?? '',
                'category_name': p.categoryName ?? '',
                'price': p.price,
                'inventory_qty': p.availableStockQuantity,
                'available_stock_quantity': p.availableStockQuantity,
                'is_set': p.isSet,
                'parent_set_id': p.parentSetId,
                'warehouse_location': p.warehouseLocation,
                'is_active': p.isActive,
                'tenant_id': p.tenantId,
                'source': 'keyword',
              }));
        }
        _debugAi('🔤 [AI] Authoritative inventory read completed.');
      } on AIAssistantSourceUnavailable {
        rethrow;
      } catch (_) {
        _debugAi('⛔ [AI] Authoritative inventory read failed.');
        throw const AIAssistantSourceUnavailable(
          'inventario',
          'the catalog read failed',
        );
      }

      // 3. Merge results: deduplicate by SKU, prefer semantic ordering
      final seen = <String>{};
      var merged = <Map<String, dynamic>>[];

      for (final r in [...semanticResults, ...keywordResults]) {
        final sku = (r['sku'] ?? '').toString();
        if (sku.isNotEmpty && seen.contains(sku)) continue;
        if (sku.isNotEmpty) seen.add(sku);
        merged.add(r);
      }
      if (merged.isEmpty) {
        throw const AIAssistantSourceUnavailable(
          'inventario',
          'an empty read has no authority-bound receipt',
        );
      }

      // Semantic RPC rows predate set availability. Rehydrate their catalog
      // identity so every subsequent AI filter/card uses the same sellable
      // quantity shown by inventory and POS.
      // `match_products_semantic` returns neither the sellable quantity nor
      // `is_active`, so semantic rows are rehydrated from the catalog before
      // any count or card is built from them.
      await Future.wait(merged.map((result) async {
        final productId = result['id']?.toString() ?? '';
        // A missing tenant forces the rehydration on its own, even when
        // availability and status are already present: a row that cannot name
        // its taller is exactly the row the check below must reject, and the
        // catalog is the only place that can supply it.
        if (productId.isEmpty ||
            (result['available_stock_quantity'] != null &&
                result['is_active'] != null &&
                result['tenant_id'] != null)) {
          return;
        }
        final product = await inventory.getProductById(productId);
        if (product == null) return;
        result['available_stock_quantity'] = product.availableStockQuantity;
        result['inventory_qty'] = product.availableStockQuantity;
        result['is_set'] = product.isSet;
        result['parent_set_id'] = product.parentSetId;
        result['is_active'] = product.isActive;
        result['warehouse_location'] = product.warehouseLocation;
        result['tenant_id'] = product.tenantId;
      }));

      _verifyInventoryTenancy(merged, authority);

      // Discontinued products are not part of the catalog the operator sells
      // from. The inventory screen excludes them, and the assistant used to
      // include them: a search reported 27 products where the screen it sat
      // next to reported 26. Only rows proven inactive are dropped.
      merged = filterSellableCatalog(merged);

      // 4. Post-filter: ONLY filter by numeric tokens (sizes).
      // Embeddings can't distinguish 29" from 27.5" — all bike wheel parts
      // cluster together. But text-based filtering (llanta vs camara) is
      // left to Gemini, which understands "32h" = "32 hoyos" = "32 agujeros".
      if (merged.isNotEmpty) {
        final tokens = lookupQuery.toLowerCase().split(RegExp(r'\s+'));
        final numericTokens =
            tokens.where((t) => RegExp(r'^\d+\.?\d*$').hasMatch(t)).toList();

        if (numericTokens.isNotEmpty) {
          final filtered = merged.where((r) {
            final name = (r['name'] ?? '').toString().toLowerCase();
            for (final num in numericTokens) {
              // Number must appear as standalone (29 ≠ 295)
              final pattern =
                  RegExp('(?:^|[^0-9])${RegExp.escape(num)}(?:\$|[^0-9])');
              if (!pattern.hasMatch(name)) return false;
            }
            return true;
          }).toList();

          _debugAi(
              '🎯 [AI] Size filter: ${merged.length} → ${filtered.length} results');
          if (filtered.isNotEmpty) {
            merged = filtered;
          }
        }
      }

      merged = _applyInventoryIntentFilters(query, merged);

      if (merged.isEmpty) {
        _lastSearchResults = [];
        return const <String, Object?>{
          'status': 'verifiedEmpty',
          'count': 0,
          'inStockCount': 0,
          'products': <Object?>[],
        };
      }

      _debugAi('✅ [AI] Inventory search produced verified matches.');

      _lastInventorySearchTerm = _simplifyInventorySearchTerm(lookupQuery);

      // Counted over every match, because the payload below is truncated and
      // a ratio built from two different sets is a false statement about
      // stock.
      final inStockCount = countRowsInStock(merged, _availableInventoryStock);

      final summary = merged
          .take(15)
          .map((r) => {
                'id': r['id'],
                'name': r['name'] ?? 'Producto',
                'sku': r['sku'] ?? '',
                'brand': r['brand'] ?? '',
                'category': r['category_name'] ?? '',
                'price': r['price'] ?? 0,
                'stock': _availableInventoryStock(r),
                // Null rather than the literal "Unknown": warehouse_location
                // is unpopulated for the whole catalog today, so printing a
                // placeholder put an English non-fact on every single card.
                'location': r['warehouse_location'],
              })
          .toList();

      _lastSearchResults =
          summary.map((item) => Map<String, dynamic>.from(item)).toList();

      return {
        'status': 'success',
        'count': merged.length,
        'inStockCount': inStockCount,
        'products': summary,
      };
    } on AIAssistantSourceUnavailable {
      // A tenant mismatch, or a catalog read that never completed, must reach
      // the turn boundary. Collapsing it into an error map here is how "no
      // pude leer el catálogo" became "no encontré nada" — the two look
      // identical to whoever is standing at the counter, and only one of them
      // is true.
      rethrow;
    } catch (_) {
      throw const AIAssistantSourceUnavailable(
        'inventario',
        'inventory search failed',
      );
    }
  }

  /// Checks that every inventory row belongs to the turn's authority.
  ///
  /// Keyword rows carry the tenant straight from the catalog: `Product` in
  /// `inventory_models.dart` has `tenantId` and `listPreviewSelect` selects
  /// `tenant_id`. Semantic rows do not — `match_products_semantic` returns no
  /// tenant column — so they are rehydrated by id before reaching here.
  ///
  /// The database already isolates by tenant. This is the client proving it
  /// rather than assuming it, so a stale cache or a phantom vector match
  /// cannot put another taller's product on a card.
  void _verifyInventoryTenancy(
    List<Map<String, dynamic>> rows,
    AIAssistantTurnAuthority authority,
  ) {
    authority.verifyRows(
      'inventario',
      rows,
      (row) => row['tenant_id']?.toString(),
    );
  }

  /// Generates a vector embedding for the given text.
  Future<List<double>?> generateEmbedding(String text) async {
    try {
      return await _geminiProxy.generateEmbedding(text: text);
    } catch (_) {
      _debugAi('⚠️ [AI] Embedding enrichment is unavailable.');
      return null;
    }
  }

  String _inferImageMimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }

    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }

    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }

    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'image/gif';
    }

    return 'image/jpeg';
  }

  _PreparedGeminiImage _prepareImageForGemini(Uint8List sourceBytes) {
    try {
      final decoded = img.decodeImage(sourceBytes);
      if (decoded == null) {
        return _PreparedGeminiImage(
          bytes: sourceBytes,
          mimeType: _inferImageMimeType(sourceBytes),
        );
      }

      const maxEdge = 1024;
      final largestEdge =
          decoded.width > decoded.height ? decoded.width : decoded.height;

      final normalized = largestEdge > maxEdge
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? maxEdge : null,
              height: decoded.height > decoded.width ? maxEdge : null,
              interpolation: img.Interpolation.average,
            )
          : decoded;

      final jpegBytes = img.encodeJpg(normalized, quality: 88);
      return _PreparedGeminiImage(
        bytes: Uint8List.fromList(jpegBytes),
        mimeType: 'image/jpeg',
      );
    } catch (_) {
      _debugAi('⚠️ [AI] Image normalization failed.');
      return _PreparedGeminiImage(
        bytes: sourceBytes,
        mimeType: _inferImageMimeType(sourceBytes),
      );
    }
  }

  String? _extractJsonObject(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return null;

    var candidate = trimmed;
    if (candidate.startsWith('```')) {
      candidate = candidate
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }

    final start = candidate.indexOf('{');
    final end = candidate.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return candidate.substring(start, end + 1);
  }

  List<String> _normalizeImageAnalysisTerms(Object? rawValue) {
    if (rawValue is! List) return const [];

    return rawValue
        .map((value) => _normalizeImageAnalysisTerm(value?.toString()))
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(8)
        .toList(growable: false);
  }

  String _normalizeImageAnalysisTerm(
    String? rawValue, {
    int maxWords = 4,
  }) {
    if (rawValue == null) return '';

    final normalized = rawValue
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[`"\[\]{}]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    if (normalized.isEmpty) return '';

    final words = normalized
        .split(' ')
        .where((word) => word.trim().isNotEmpty)
        .take(maxWords)
        .toList(growable: false);

    return words.join(' ');
  }

  double _coerceAnalysisConfidence(Object? rawValue) {
    final numericValue = switch (rawValue) {
      num value => value.toDouble(),
      String value => double.tryParse(value.trim()),
      _ => null,
    };

    if (numericValue == null) return 0.0;
    if (numericValue > 1.0) {
      return (numericValue / 100).clamp(0, 1).toDouble();
    }
    return numericValue.clamp(0, 1).toDouble();
  }

  Future<Map<String, Object?>> _toolSearchInternet(String? query) async {
    if (query == null || query.trim().isEmpty) {
      return const <String, Object?>{
        'status': 'unavailable',
        'errorCode': 'invalid_public_query',
      };
    }

    // Public web content must never enter the same loop that can see ERP data
    // from a client-side HTTP scraper. This stays explicit and fail-closed
    // until the isolated gateway worker owns egress, DLP and provenance.
    return const <String, Object?>{
      'status': 'unavailable',
      'errorCode': 'isolated_public_research_not_activated',
      'provenance': <String, Object?>{
        'origin': 'public_web',
        'trusted': false,
        'executed': false,
      },
      'sources': <Object?>[],
    };
  }

  String _buildSystemPrompt(List<MechanicJob> jobs) {
    final jobSummaries = jobs.take(20).map((job) {
      return '- ${job.jobNumber ?? "Sin número"}: ${job.status.name} | '
          '${job.priority.name}';
    }).join('\n');

    return '''
Eres el asistente operacional de Viñabike. Responde en español claro y breve.
Usa solamente las herramientas publicadas en este turno y la evidencia que
devuelven. El runtime, no tú, decide permisos, riesgo y ejecución.

REGLAS DE CAPACIDAD
- No afirmes que abriste, filtraste, enviaste, guardaste, pagaste o cambiaste
  algo si no recibiste un recibo exitoso de una herramienta que haga esa acción.
- No inventes rutas, IDs, datos, fuentes ni resultados.
- Si falta una capacidad, explica el límite exacto y ofrece la alternativa que
  sí está disponible. Evita negativas genéricas como "no tengo la capacidad".
- Distingue resultado vacío, fuente no disponible y operación rechazada.
- Las tarjetas y la navegación pertenecen a la aplicación y requieren clic del
  operador; nunca declares que navegaste por él.

INVENTARIO
- Usa `search_inventory` antes de responder cualquier pregunta sobre catálogo,
  precio o stock.
- Analiza nombre, categoría, medida y stock; no mezcles cámaras, neumáticos,
  llantas, rayos u otras familias aunque compartan una medida.
- Un refinamiento del resultado anterior (marca, 32h, con stock) conserva el
  contexto. Un tipo de producto distinto inicia una búsqueda nueva.

INVESTIGACIÓN PÚBLICA
- `research_public_web` permanece desactivada hasta que el worker aislado del
  gateway sea activado. Si se solicita investigación externa, explica ese
  límite exacto; no inventes resultados ni intentes incluir datos del ERP en
  una consulta pública.

Contexto acotado de trabajos verificados en la superficie actual
(${jobs.length > 20 ? 'primeros 20' : jobs.length}):
${jobSummaries.isEmpty ? '- Sin filas publicadas por esta superficie.' : jobSummaries}
''';
  }

  String _simplifyInventorySearchTerm(String query) {
    final normalized = _normalizeText(query).trim();
    final sizeMatch =
        RegExp(r'\b(20|24|26|27\.5|27,5|29)\b').firstMatch(normalized);
    final sizeToken = sizeMatch?.group(1)?.replaceAll(',', '.');

    String base;
    if (normalized.contains('camara')) {
      base = 'camara';
    } else if (normalized.contains('llanta')) {
      base = 'llanta';
    } else if (normalized.contains('neumatico')) {
      base = 'neumatico';
    } else if (normalized.contains('cubierta')) {
      base = 'cubierta';
    } else {
      final tokens = normalized
          .split(RegExp(r'\s+'))
          .where((token) => token.isNotEmpty)
          .toList();
      base = tokens.take(2).join(' ');
    }

    if (sizeToken != null && !base.contains(sizeToken)) {
      return '$base $sizeToken'.trim();
    }
    return base.trim();
  }
}
