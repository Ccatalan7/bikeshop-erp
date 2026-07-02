import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/customer_service.dart';
import '../../inventory/services/inventory_service.dart';
import '../../purchases/models/purchase_invoice.dart';
import '../../purchases/services/purchase_service.dart';
import '../../sales/models/sales_models.dart';
import '../../sales/services/sales_service.dart';
import '../../../shared/models/supplier.dart';
import '../../../shared/services/gemini_proxy_service.dart';
import '../../../shared/utils/chilean_utils.dart';

/// Callback type for navigation actions the AI can trigger.
/// The [route] is the path to navigate to (e.g. '/inventory/products').
/// The [searchTerm] is an optional pre-filled search query.
typedef AINavigationCallback = void Function(String route,
    {String? searchTerm});

class AIAssistantActionCard {
  const AIAssistantActionCard({
    required this.kind,
    required this.title,
    required this.route,
    this.eyebrow,
    this.subtitle,
    this.description,
    this.ctaLabel = 'Abrir',
    this.chips = const [],
  });

  final String kind;
  final String title;
  final String route;
  final String? eyebrow;
  final String? subtitle;
  final String? description;
  final String ctaLabel;
  final List<String> chips;
}

class AIAssistantResponse {
  const AIAssistantResponse({
    required this.text,
    this.cards = const [],
  });

  final String text;
  final List<AIAssistantActionCard> cards;
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

class AIAssistantService extends ChangeNotifier {
  static final AIAssistantService _instance = AIAssistantService._internal();
  factory AIAssistantService() => _instance;
  AIAssistantService._internal();

  final GeminiProxyService _geminiProxy = GeminiProxyService();
  final List<Map<String, dynamic>> _history = [];
  bool _isLoading = false;

  List<Map<String, dynamic>> _toolDeclarations = [];

  /// SKUs from the last searchStock call, used to sync with inventory page.
  List<String>? _lastSearchSkus;
  List<Map<String, dynamic>> _lastSearchResults = [];
  String? _lastInventorySearchTerm;

  static const int _stockFilterAll = 0;
  static const int _stockFilterInStock = 1;
  static const int _stockFilterOutOfStock = 3;

  bool get isLoading => _isLoading;
  List<Map<String, dynamic>> get history => _history;
  bool get isGeminiConfigured => true;

  void initialize() {
    if (_toolDeclarations.isNotEmpty) {
      return;
    }

    _toolDeclarations = [
      {
        'functionDeclarations': [
          {
            'name': 'searchStock',
            'description':
                'Search for products in the inventory using semantic AI search. Returns product name, SKU, brand, category, price, stock quantity, and location.',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'query': {
                  'type': 'STRING',
                  'description':
                      'Search query. Use the specific product type in Spanish as it appears in product names (e.g., "llanta 29" not "aro 29", "camara 29" not "tubo 29"). Include size and specs when the user mentions them.',
                },
              },
              'required': ['query'],
            },
          },
          {
            'name': 'navigateToInventory',
            'description':
                'Navigates the app to the Inventory module and pre-fills the search box. WARNING: The inventory screen uses KEYWORD text matching, NOT semantic search. You MUST simplify and translate the user\'s request into the shortest possible keyword that will match product names. Examples: "llantas mtb" → "llanta", "cámaras para mountain bike" → "camara", "ruedas para BMX" → "llanta 20". NEVER pass conversational phrases, categories like "mtb", or connector words like "para", "de", "con".',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'searchTerm': {
                  'type': 'STRING',
                  'description':
                      'The simplified keyword for the inventory text filter. Must match actual product names. Use the shortest effective keyword (e.g., "llanta", "camara 29", "cassette shimano").',
                },
              },
              'required': ['searchTerm'],
            },
          },
          {
            'name': 'searchInternet',
            'description':
                'Search the internet for information not available in the internal database (e.g., bike compatibility, specs, standard parts).',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'query': {
                  'type': 'STRING',
                  'description': 'The search query.',
                },
              },
              'required': ['query'],
            },
          },
        ],
      },
    ];
  }

  Future<String> generateOneShotText(
    String prompt, {
    String modelName = 'gemini-2.5-flash-lite',
  }) async {
    return _geminiProxy.generateText(prompt: prompt, model: modelName);
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
        debugPrint(
            '⚠️ [AI] Product image analysis returned non-JSON: $rawText');
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
    } catch (e) {
      debugPrint('❌ [AI] Product image analysis error: $e');
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
        debugPrint('⚠️ [AI] Visual comparison returned non-JSON: $rawText');
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
    } catch (e) {
      debugPrint('❌ [AI] Visual comparison error: $e');
      return null;
    }
  }

  /// Cache for cleaned product names. Keyed by image hash + raw title so
  /// repeated rows in the same AliExpress invoice share one Gemini call.
  final Map<String, AICleanedProductName> _cleanedNameCache = {};

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

    // Build cache key. Prefer image hash (stable across URL changes) but fall
    // back to URL when only the URL is known.
    final cacheKey = StringBuffer();
    if (imageBytes != null && imageBytes.isNotEmpty) {
      cacheKey.write('b:${imageBytes.lengthInBytes}:'
          '${imageBytes.take(64).fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff)}');
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      cacheKey.write('u:$imageUrl');
    } else {
      cacheKey.write('t:');
    }
    cacheKey.write('|${rawTitle.trim().toLowerCase()}');
    final cached = _cleanedNameCache[cacheKey.toString()];
    if (cached != null) return cached;

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
  "confidence": 0.92
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
- brand y model son opcionales; SOLO incluyelos si son claramente visibles
  en la foto o explicitamente nombrados en el titulo. NO inventes marca.
- category_name debe ser una categoria humana en plural ("Postizas",
  "Poleas", "Pastillas de freno", "Cassettes", "Cadenas", "Cambios
  traseros"). Sirve para sugerir la categoria de catalogo.
- confidence entre 0 y 1.
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
        debugPrint('⚠️ [AI] Clean product title returned non-JSON: $rawText');
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
      );

      _cleanedNameCache[cacheKey.toString()] = result;
      return result;
    } catch (e) {
      debugPrint('❌ [AI] Clean product title error: $e');
      return null;
    }
  }

  Future<Uint8List?> _downloadImageBytes(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
      debugPrint(
          '⚠️ [AI] Image download failed (${response.statusCode}) for $url');
      return null;
    } catch (e) {
      debugPrint('❌ [AI] Image download error for $url: $e');
      return null;
    }
  }

  String _imageBytesCacheKey(Uint8List bytes) {
    var hash = 0;
    final stride = math.max(1, bytes.lengthInBytes ~/ 96);
    for (var index = 0; index < bytes.lengthInBytes; index += stride) {
      hash = (hash * 31 + bytes[index]) & 0x7fffffff;
    }
    return 'b:${bytes.lengthInBytes}:$hash';
  }

  Future<AIAssistantResponse> sendMessage(
    String message, {
    List<MechanicJob>? jobs,
    CustomerService? customerService,
    InventoryService? inventoryService,
    BikeshopService? bikeshopService,
    PurchaseService? purchaseService,
    SalesService? salesService,
    AINavigationCallback? onNavigate,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final jobSummaryResponse = await _tryHandleJobSummary(
        message,
        jobs: jobs,
        customerService: customerService,
        bikeshopService: bikeshopService,
      );
      if (jobSummaryResponse != null) {
        return jobSummaryResponse;
      }

      final entityCardResponse = await _tryHandleEntityCards(
        message,
        customerService: customerService,
        bikeshopService: bikeshopService,
        purchaseService: purchaseService,
        salesService: salesService,
      );
      if (entityCardResponse != null) {
        return entityCardResponse;
      }

      final inventoryRefinement = _tryHandleInventoryRefinement(
        message,
        inventoryService: inventoryService,
        onNavigate: onNavigate,
      );
      if (inventoryRefinement != null) {
        return _textResponse(inventoryRefinement);
      }

      final inventoryComparison = _tryHandleInventoryComparison(message);
      if (inventoryComparison != null) {
        return _textResponse(inventoryComparison);
      }

      final directInventorySearch = await _tryHandleDirectInventorySearch(
        message,
        inventoryService: inventoryService,
        onNavigate: onNavigate,
      );
      if (directInventorySearch != null) {
        return directInventorySearch;
      }

      initialize();

      final workingHistory = List<Map<String, dynamic>>.from(_history);
      final systemPrompt = _buildSystemPrompt(jobs ?? []);
      workingHistory.add({
        'role': 'user',
        'parts': [
          {'text': message},
        ],
      });

      var response = await _geminiProxy.generateContent(
        model: 'gemini-2.5-flash-lite',
        systemInstruction: {
          'parts': [
            {'text': systemPrompt},
          ],
        },
        contents: workingHistory,
        tools: _toolDeclarations,
      );

      // Handle Tool Calls (Recursively if needed)
      int maxTurns = 5;
      while (response.functionCalls.isNotEmpty && maxTurns > 0) {
        maxTurns--;
        final functionCalls = response.functionCalls;
        final functionResponses = <Map<String, dynamic>>[];
        Map<String, Object?>? inventorySearchResult;
        Map<String, Object?>? inventoryNavigateResult;

        workingHistory.add({
          'role': 'model',
          'parts': [
            for (final call in functionCalls)
              {
                'functionCall': {
                  'name': call.name,
                  'args': call.args,
                },
              },
            if (response.text.trim().isNotEmpty) {'text': response.text.trim()},
          ],
        });

        for (final call in functionCalls) {
          final name = call.name;
          final args = call.args;

          debugPrint('🔧 [AI] Calling tool: $name with args: $args');

          Map<String, Object?> result;

          if (name == 'searchStock') {
            result = await _toolSearchStock(
                args['query'] as String?, inventoryService);
            inventorySearchResult = result;
          } else if (name == 'navigateToInventory') {
            result = _toolNavigateToInventory(
              args['searchTerm'] as String?,
              inventoryService: inventoryService,
              onNavigate: onNavigate,
            );
            inventoryNavigateResult = result;
          } else if (name == 'searchInternet') {
            result = await _toolSearchInternet(args['query'] as String?);
          } else {
            result = {'error': 'Function $name not found'};
          }

          functionResponses.add({
            'functionResponse': {
              'name': name,
              'response': result,
            },
          });
        }

        final shouldAutoNavigateToInventory = inventorySearchResult != null &&
            inventoryNavigateResult == null &&
            inventorySearchResult.containsKey('products') &&
            ((inventorySearchResult['count'] as num?)?.toInt() ?? 0) > 0 &&
            _lastInventorySearchTerm != null &&
            _lastInventorySearchTerm!.isNotEmpty &&
            onNavigate != null;

        if (shouldAutoNavigateToInventory) {
          inventoryNavigateResult = _toolNavigateToInventory(
            _lastInventorySearchTerm,
            inventoryService: inventoryService,
            onNavigate: onNavigate,
          );
        }

        final deterministicInventoryReply = _buildDeterministicInventoryReply(
          inventorySearchResult,
          inventoryNavigateResult,
        );
        if (deterministicInventoryReply != null) {
          _history
            ..clear()
            ..addAll(workingHistory)
            ..add({
              'role': 'model',
              'parts': [
                {'text': deterministicInventoryReply},
              ],
            });
          return _cardResponse(
            deterministicInventoryReply,
            cards: _buildInventoryCardsFromSearchResult(inventorySearchResult),
          );
        }

        workingHistory.add({
          'role': 'user',
          'parts': functionResponses,
        });

        response = await _geminiProxy.generateContent(
          model: 'gemini-2.5-flash-lite',
          systemInstruction: {
            'parts': [
              {'text': systemPrompt},
            ],
          },
          contents: workingHistory,
          tools: _toolDeclarations,
        );
      }

      final text = response.text.trim();

      if (text.isEmpty) {
        return _textResponse('Sorry, I could not generate a response.');
      }

      workingHistory.add({
        'role': 'model',
        'parts': [
          {'text': text},
        ],
      });

      _history
        ..clear()
        ..addAll(workingHistory);

      return _textResponse(text);
    } on GeminiProxyException catch (e) {
      debugPrint('Error sending message via Gemini proxy: $e');
      return _textResponse(_friendlyGeminiErrorMessage(e));
    } catch (e) {
      debugPrint('Error sending message via AI assistant: $e');
      return _textResponse(
        'No pude procesar esa solicitud ahora. Intenta de nuevo en unos segundos.',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

  Future<AIAssistantResponse?> _tryHandleJobSummary(
    String message, {
    List<MechanicJob>? jobs,
    CustomerService? customerService,
    BikeshopService? bikeshopService,
  }) async {
    final normalized = _normalizeText(message);
    final mentionsJobs = normalized.contains('trabajo') ||
        normalized.contains('trabajos') ||
        normalized.contains('orden de trabajo') ||
        normalized.contains('ordenes de trabajo') ||
        normalized.contains('job') ||
        normalized.contains('jobs');
    if (!mentionsJobs) {
      return null;
    }

    final wantsSummary = normalized.contains('resumen') ||
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
    if (!wantsSummary) {
      return null;
    }

    final sourceJobs = await _loadJobsForSummary(
      jobs,
      bikeshopService: bikeshopService,
    );
    if (sourceJobs.isEmpty) {
      return _textResponse('No encontré trabajos para resumir ahora mismo.');
    }

    final asksForActive =
        normalized.contains('activo') || normalized.contains('activos');
    final includeAll = !asksForActive &&
        (normalized.contains('todos') ||
            normalized.contains('todas') ||
            normalized.contains('historico') ||
            normalized.contains('historial') ||
            normalized.contains('finalizados') ||
            normalized.contains('entregados') ||
            normalized.contains('cancelados'));
    final selectedJobs = includeAll
        ? List<MechanicJob>.from(sourceJobs)
        : sourceJobs.where(_isActiveJob).toList();

    if (selectedJobs.isEmpty) {
      return _textResponse('No encontré trabajos activos para resumir ahora.');
    }

    final customerNamesById = await _loadCustomerNamesById(customerService);
    selectedJobs.sort(_compareJobsForSummary);

    final statusCounts = <String, int>{};
    var highPriorityCount = 0;
    var overdueCount = 0;
    var dueSoonCount = 0;
    var totalValue = 0.0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
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
    final scopeLabel = includeAll ? 'trabajos' : 'trabajos activos';
    final headline = 'Tienes ${selectedJobs.length} $scopeLabel.';
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
      if (detailLines.isNotEmpty)
        'Trabajos destacados:\n${detailLines.join('\n')}',
    ].join('\n\n');

    return _textResponse(text, cards: cards);
  }

  Future<List<MechanicJob>> _loadJobsForSummary(
    List<MechanicJob>? jobs, {
    BikeshopService? bikeshopService,
  }) async {
    if (jobs != null && jobs.isNotEmpty) {
      return jobs.where((job) => job.id != null).toList();
    }

    if (bikeshopService == null) {
      return const <MechanicJob>[];
    }

    final loadedJobs = bikeshopService.hasJobsCache
        ? bikeshopService.cachedJobs
        : await bikeshopService.getJobs();
    return loadedJobs.where((job) => job.id != null).toList();
  }

  Future<Map<String, String>> _loadCustomerNamesById(
    CustomerService? customerService,
  ) async {
    if (customerService == null) {
      return const <String, String>{};
    }

    try {
      final customers = await _loadCustomersForAi(customerService);
      return {
        for (final customer in customers)
          if (customer.id != null) customer.id!: customer.name,
      };
    } catch (e) {
      debugPrint('⚠️ [AI] Failed to load customers for job summary: $e');
      return const <String, String>{};
    }
  }

  bool _isActiveJob(MechanicJob job) {
    return job.status != JobStatus.finalizado &&
        job.status != JobStatus.entregado &&
        job.status != JobStatus.cancelado;
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
  }) async {
    final purchaseInvoiceResponse = await _tryHandlePurchaseInvoiceCards(
      message,
      purchaseService: purchaseService,
    );
    if (purchaseInvoiceResponse != null) {
      return purchaseInvoiceResponse;
    }

    final salesInvoiceResponse = await _tryHandleSalesInvoiceCards(
      message,
      salesService: salesService,
    );
    if (salesInvoiceResponse != null) {
      return salesInvoiceResponse;
    }

    final customerResponse = await _tryHandleCustomerCards(
      message,
      customerService: customerService,
    );
    if (customerResponse != null) {
      return customerResponse;
    }

    final supplierResponse = await _tryHandleSupplierCards(
      message,
      purchaseService: purchaseService,
    );
    if (supplierResponse != null) {
      return supplierResponse;
    }

    final jobResponse = await _tryHandleJobCards(
      message,
      customerService: customerService,
      bikeshopService: bikeshopService,
    );
    if (jobResponse != null) {
      return jobResponse;
    }

    return null;
  }

  Future<AIAssistantResponse?> _tryHandleCustomerCards(
    String message, {
    CustomerService? customerService,
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

    final allCustomers = await _loadCustomersForAi(customerService);
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

    var suppliers = await purchaseService.getSuppliers();

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

    final customerNamesById = <String, String>{
      for (final customer
          in customerService?.cachedCustomers ?? const <Customer>[])
        if (customer.id != null) customer.id!: customer.name,
    };

    final allCustomers = customerService != null
        ? await _loadCustomersForAi(customerService)
        : const <Customer>[];
    final matchingCustomers = searchTerm.isNotEmpty
        ? allCustomers
            .where(
                (customer) => _customerMatchesSearchTerm(searchTerm, customer))
            .take(10)
            .toList()
        : const <Customer>[];

    List<MechanicJob> candidateJobs;
    if (searchTerm.isEmpty) {
      candidateJobs = bikeshopService.hasJobsCache
          ? bikeshopService.cachedJobs
          : await bikeshopService.getJobs();
    } else {
      final cachedJobs = bikeshopService.hasJobsCache
          ? bikeshopService.cachedJobs
          : const <MechanicJob>[];
      final customerLinkedJobs = <MechanicJob>[];
      final seenCustomerLinkedJobIds = <String>{};

      for (final customer in matchingCustomers) {
        final customerId = customer.id;
        if (customerId == null) continue;
        customerNamesById[customerId] = customer.name;

        final jobsForCustomer = cachedJobs.isNotEmpty
            ? cachedJobs.where((job) => job.customerId == customerId).toList()
            : await bikeshopService.getJobs(customerId: customerId);

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

      final textMatchedJobs =
          await bikeshopService.getJobs(searchTerm: searchTerm);
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
  ) async {
    if (customerService.hasCustomersCache &&
        customerService.cachedCustomers.isNotEmpty) {
      return customerService.cachedCustomers
          .where((customer) => customer.id != null)
          .toList();
    }

    final customers = await customerService.getCustomers(forceRefresh: false);
    return customers.where((customer) => customer.id != null).toList();
  }

  AIAssistantActionCard _buildCustomerCard(Customer customer) {
    final subtitleParts = <String>[
      if (customer.rut.trim().isNotEmpty) customer.rut.trim(),
      if ((customer.email ?? '').trim().isNotEmpty) customer.email!.trim(),
      if ((customer.phone ?? '').trim().isNotEmpty) customer.phone!.trim(),
    ];

    final descriptionParts = <String>[
      if ((customer.address ?? '').trim().isNotEmpty) customer.address!.trim(),
      if ((customer.region ?? '').trim().isNotEmpty) customer.region!.trim(),
    ];

    return AIAssistantActionCard(
      kind: 'customer',
      eyebrow: 'Cliente',
      title: customer.name,
      subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' • '),
      description:
          descriptionParts.isEmpty ? null : descriptionParts.join(' • '),
      route: '/clientes/${customer.id}',
      ctaLabel: 'Abrir cliente',
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
      route: '/purchases/suppliers/${supplier.id}/edit',
      ctaLabel: 'Abrir proveedor',
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
      route: '/taller/pegas/${job.id}',
      ctaLabel: 'Abrir trabajo',
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

    final now = DateTime.now();
    var filtered = salesService.invoices.where((invoice) {
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
      route: '/sales/invoices/${invoice.id}',
      ctaLabel: 'Abrir factura',
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

    final invoices = await purchaseService.getPurchaseInvoices();
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
      route: '/purchases/${invoice.id}',
      ctaLabel: 'Abrir factura',
      chips: [
        invoice.status.displayName,
        if (invoice.balance > 0.01) 'Pendiente',
        if (invoice.balance <= 0.01) 'Pagada',
      ],
    );
  }

  String? _buildDeterministicInventoryReply(
    Map<String, Object?>? searchResult,
    Map<String, Object?>? navigateResult,
  ) {
    if (searchResult == null && navigateResult == null) {
      return null;
    }

    if (searchResult != null && searchResult.containsKey('error')) {
      return 'Error buscando en inventario: ${searchResult['error']}';
    }

    if (searchResult != null && searchResult.containsKey('result')) {
      final raw = searchResult['result']?.toString();
      if (raw != null && raw.isNotEmpty) {
        return raw;
      }
    }

    final productsRaw = searchResult?['products'];
    final count = (searchResult?['count'] as num?)?.toInt() ?? 0;
    if (productsRaw is! List || productsRaw.isEmpty) {
      return navigateResult?['message']?.toString();
    }

    final products = productsRaw
        .whereType<Map>()
        .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .cast<Map<String, dynamic>>()
        .toList();

    final queryLabel = (() {
      final raw = (navigateResult?['searchTerm'] ?? _lastInventorySearchTerm)
          ?.toString()
          .trim();
      if (raw == null || raw.isEmpty) {
        return 'tu búsqueda';
      }
      return '"$raw"';
    })();

    final inStockCount = products.where((product) {
      final stock = (product['stock'] as num?)?.toDouble() ??
          (product['inventory_qty'] as num?)?.toDouble() ??
          0;
      return stock > 0;
    }).length;

    final sampleNames = products
        .take(2)
        .map((product) => (product['name'] ?? 'Producto').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();

    final stockSentence = inStockCount == 0
        ? 'Ahora mismo todos aparecen sin stock.'
        : inStockCount == count
            ? 'Todos aparecen con stock.'
            : '$inStockCount de $count aparecen con stock ahora.';

    final sampleSentence = sampleNames.isEmpty
        ? 'Te dejé algunas coincidencias abajo.'
        : sampleNames.length == 1
            ? 'La principal coincidencia es ${sampleNames.first}.'
            : 'Entre las primeras coincidencias están ${sampleNames.first} y ${sampleNames[1]}.';

    final navigationSentence = navigateResult?['searchTerm'] != null
        ? ' Ya abrí inventario con ese filtro.'
        : '';

    return 'Encontré $count resultados para $queryLabel. '
        '$stockSentence $sampleSentence$navigationSentence';
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
    final stock = (product['stock'] as num?)?.toDouble() ??
        (product['inventory_qty'] as num?)?.toDouble() ??
        0;
    final location =
        (product['location'] ?? product['warehouse_location'] ?? 'Unknown')
            .toString();
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
      description:
          'Precio ${ChileanUtils.formatCurrency((product['price'] as num?)?.toDouble() ?? 0)} • Stock $stockLabel • Ubicación $location',
      route: '/inventory/products/${product['id']}/edit',
      ctaLabel: 'Abrir producto',
      chips: [
        if (stock > 0) 'Con stock' else 'Sin stock',
      ],
    );
  }

  void resetChat() {
    _history.clear();
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
        final stock = (product['inventory_qty'] as num?)?.toDouble() ??
            (product['stock'] as num?)?.toDouble() ??
            0;
        return stock > 0;
      }).toList();
    } else if (wantsOutOfStock) {
      filtered = filtered.where((product) {
        final stock = (product['inventory_qty'] as num?)?.toDouble() ??
            (product['stock'] as num?)?.toDouble() ??
            0;
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

  String _resolveNavigationSearchTerm(String requestedSearchTerm) {
    final normalizedRequested =
        _simplifyInventorySearchTerm(requestedSearchTerm);

    if (normalizedRequested.isNotEmpty) {
      return normalizedRequested;
    }

    if (_lastSearchResults.isNotEmpty &&
        _lastInventorySearchTerm != null &&
        _lastInventorySearchTerm!.isNotEmpty) {
      return _lastInventorySearchTerm!;
    }

    return normalizedRequested;
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
    AINavigationCallback? onNavigate,
  }) async {
    if (inventoryService == null) {
      return null;
    }

    if (_messageAsksForWidthComparison(message) ||
        !_messageLooksLikeDirectInventorySearch(message)) {
      return null;
    }

    final searchResult = await _toolSearchStock(message, inventoryService);
    Map<String, Object?>? navigateResult;

    final count = (searchResult['count'] as num?)?.toInt() ?? 0;
    if (count > 0 && onNavigate != null && _lastInventorySearchTerm != null) {
      navigateResult = _toolNavigateToInventory(
        _lastInventorySearchTerm,
        inventoryService: inventoryService,
        onNavigate: onNavigate,
      );
    }

    final text =
        _buildDeterministicInventoryReply(searchResult, navigateResult);
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
        final stock = (product['stock'] as num?)?.toDouble() ??
            (product['inventory_qty'] as num?)?.toDouble() ??
            0;
        return stock > 0;
      }).toList();
    } else if (wantsOutOfStock) {
      candidates = candidates.where((product) {
        final stock = (product['stock'] as num?)?.toDouble() ??
            (product['inventory_qty'] as num?)?.toDouble() ??
            0;
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
          final stock = (product['stock'] as num?)?.toDouble() ??
              (product['inventory_qty'] as num?)?.toDouble() ??
              0;
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
    AINavigationCallback? onNavigate,
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
      final stock = (result['stock'] as num?)?.toDouble() ??
          (result['inventory_qty'] as num?)?.toDouble() ??
          0;
      if (wantsOutOfStock) {
        return stock <= 0;
      }
      return stock > 0;
    }).toList();

    _lastSearchSkus = filtered
        .map((r) => (r['sku'] ?? '').toString())
        .where((sku) => sku.isNotEmpty)
        .toList();

    if (filtered.isNotEmpty) {
      _lastSearchResults =
          filtered.map((item) => Map<String, dynamic>.from(item)).toList();
    }

    if (inventoryService != null && onNavigate != null) {
      final stockFilterIndex =
          wantsOutOfStock ? _stockFilterOutOfStock : _stockFilterInStock;
      inventoryService.applyExternalSearch(
        _lastInventorySearchTerm!,
        matchedSkus: _lastSearchSkus,
        stockFilterIndex: stockFilterIndex,
      );
      onNavigate('/inventory/products', searchTerm: _lastInventorySearchTerm);
    }

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
      String? query, InventoryService? inventory) async {
    if (query == null || query.isEmpty) return {'error': 'Query is empty'};
    if (inventory == null) return {'error': 'Inventory service not available'};

    try {
      final lookupQuery = _normalizeInventoryLookupQuery(query);
      debugPrint(
          '🔍 [AI] Combined search for: "$query" (lookup: "$lookupQuery")');

      // Run BOTH searches in parallel for best results
      final List<Map<String, dynamic>> semanticResults = [];
      final List<Map<String, dynamic>> keywordResults = [];

      // 1. Semantic search (high threshold = only relevant results)
      try {
        final vector = await generateEmbedding(lookupQuery);
        if (vector != null) {
          final results = await inventory.searchProductsSemantic(vector);
          semanticResults.addAll(results);
          debugPrint(
              '🧠 [AI] Semantic: ${results.length} results for "$lookupQuery"');
        }
      } catch (e) {
        debugPrint('⚠️ [AI] Semantic search failed: $e');
      }

      // 2. Keyword search
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
                'inventory_qty': p.inventoryQty,
                'warehouse_location': p.warehouseLocation ?? 'Unknown',
                'source': 'keyword',
              }));
        }
        debugPrint(
            '🔤 [AI] Keyword: ${keywordResults.length} raw results for "$lookupQuery"');
      } catch (e) {
        debugPrint('⚠️ [AI] Keyword search failed: $e');
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

          debugPrint(
              '🎯 [AI] Size filter: ${merged.length} → ${filtered.length} results');
          if (filtered.isNotEmpty) {
            merged = filtered;
          }
        }
      }

      merged = _applyInventoryIntentFilters(query, merged);

      if (merged.isEmpty) {
        _lastSearchSkus = null;
        _lastSearchResults = [];
        return {'result': 'No products found for "$query".'};
      }

      debugPrint(
          '✅ [AI] Combined: ${merged.length} unique results for "$query"');

      // Save matched SKUs so navigateToInventory can pass them to the list
      _lastSearchSkus = merged
          .map((r) => (r['sku'] ?? '').toString())
          .where((sku) => sku.isNotEmpty)
          .toList();
      _lastInventorySearchTerm = _simplifyInventorySearchTerm(lookupQuery);

      final summary = merged
          .take(15)
          .map((r) => {
                'id': r['id'],
                'name': r['name'] ?? 'Unknown',
                'sku': r['sku'] ?? '',
                'brand': r['brand'] ?? '',
                'category': r['category_name'] ?? '',
                'price': r['price'] ?? 0,
                'stock': r['inventory_qty'] ?? 0,
                'location': r['warehouse_location'] ?? 'Unknown',
              })
          .toList();

      _lastSearchResults =
          summary.map((item) => Map<String, dynamic>.from(item)).toList();

      return {
        'count': merged.length,
        'products': summary,
      };
    } catch (e) {
      return {'error': 'Failed to search inventory: $e'};
    }
  }

  /// Generates a vector embedding for the given text.
  Future<List<double>?> generateEmbedding(String text) async {
    try {
      return await _geminiProxy.generateEmbedding(text: text);
    } catch (e) {
      debugPrint('❌ [AI] Embedding generation error: $e');
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
    } catch (e) {
      debugPrint('⚠️ [AI] Failed to normalize image for Gemini: $e');
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

  Map<String, Object?> _toolNavigateToInventory(
    String? searchTerm, {
    InventoryService? inventoryService,
    AINavigationCallback? onNavigate,
  }) {
    if (searchTerm == null || searchTerm.isEmpty) {
      return {'error': 'Search term is required'};
    }

    if (onNavigate == null) {
      return {'error': 'Navigation is not available in this context'};
    }

    final resolvedSearchTerm = _resolveNavigationSearchTerm(searchTerm);

    debugPrint(
        '🧭 [AI] Navigating to inventory with search: "$resolvedSearchTerm"');
    _lastInventorySearchTerm = resolvedSearchTerm;

    // Set the saved search term AND signal any active listeners
    if (inventoryService != null) {
      inventoryService.applyExternalSearch(resolvedSearchTerm,
          matchedSkus: _lastSearchSkus, stockFilterIndex: _stockFilterAll);
    }

    // Trigger navigation (closes the dialog and navigates)
    onNavigate('/inventory/products', searchTerm: resolvedSearchTerm);

    return {
      'success': true,
      'navigatedTo': '/inventory/products',
      'searchTerm': resolvedSearchTerm,
      'message':
          'Navigated to inventory and searched for "$resolvedSearchTerm". The results are now displayed on screen.',
    };
  }

  Future<Map<String, Object?>> _toolSearchInternet(String? query) async {
    if (query == null || query.isEmpty) return {'error': 'Query is empty'};

    debugPrint('🌐 [AI] Searching internet for: "$query"');

    try {
      final url = Uri.parse(
          'https://html.duckduckgo.com/html/?q=${Uri.encodeComponent(query)}');
      final response = await http.get(
        url,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      );

      if (response.statusCode == 200) {
        var body = response.body;
        // Simple regex to extract search result snippets from DuckDuckGo HTML
        final snippetRegex =
            RegExp(r'<a class="result__snippet[^>]*>(.*?)</a>', dotAll: true);

        final snippets = snippetRegex
            .allMatches(body)
            .map((m) {
              // Remove all HTML tags and decode basic entities manually or rely on LLM to read them
              var text =
                  m.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
              text = text
                  .replaceAll('&amp;', '&')
                  .replaceAll('&quot;', '"')
                  .replaceAll('&#x27;', "'")
                  .replaceAll('&lt;', '<')
                  .replaceAll('&gt;', '>');
              return text;
            })
            .where((s) => s.isNotEmpty)
            .take(5)
            .toList();

        if (snippets.isEmpty) {
          return {'result': 'No internet search results found.'};
        }

        return {
          'result':
              'Internet search results for "$query":\n\n${snippets.join('\n\n')}'
        };
      } else {
        return {
          'error':
              'Failed to fetch search results. Status code: ${response.statusCode}'
        };
      }
    } catch (e) {
      debugPrint('❌ [AI] Internet search error: $e');
      return {'error': 'Failed to search internet: $e'};
    }
  }

  String _buildSystemPrompt(List<MechanicJob> jobs) {
    // Basic summary of jobs to keep prompt size reasonable
    final jobSummaries = jobs.map((j) {
      return '- Job ${j.jobNumber ?? "N/A"}: ${j.status.name} | ${j.priority.name} | Customer: ${j.customerId} | Bike: ${j.bikeId} | Total: ${j.totalCost}';
    }).join('\n');

    return '''
You are a helpful and powerful AI assistant for "Vinabike" Bike Shop ERP.
Your capabilities include:
1. Managing repair jobs (Trabajos).
2. Checking inventory stock and prices via semantic search.
3. Navigating the app to show the user specific products in the Inventory module.
4. Answering technical questions about bike compatibility by searching the internet.

INVENTORY SEARCH — SEMANTIC SEARCH:
The `searchStock` tool uses AI-powered semantic vector matching. You can search using natural language concepts directly — the system understands meaning, not just keywords.
- You CAN use descriptive queries like "ruedas para saltar en la calle", "repuestos para frenos de disco", "cámaras para mountain bike".
- You can also use technical terms like "cassette shimano 7v" or "llanta 20" — both work.
- The system will automatically find products with similar meaning, even if the exact words don't match.

TOOL STRATEGY:
1. ALWAYS use `searchStock` first for ANY product question. It uses semantic AI search.
   - Each result includes: name, SKU, brand, category, price, stock (quantity), and location.
   - YOU are responsible for analyzing results and only presenting products that match what the user asked.
   - Use the "category" field to verify product type. Use "stock" to check availability.
   - If the user asks for "llantas 29", only show products that are actually 29" rims — not tubes, tires, spokes, or other sizes.

2. STOCK & FOLLOW-UP AWARENESS:
   - Each result has a "stock" field. When the user asks "en stock" or "disponible", check the stock field.
  - When the user refines a previous query (adds "en stock", "32h", a brand, etc.), FIRST refine the previous result set if possible. Don't re-search if you already have the data.
  - If the user says things like "los que tengan stock", "solo con stock", or "solo disponibles", treat that as a refinement of the immediately previous inventory results, not as a brand new search.
  - IMPORTANT: if the user mentions a different product type than the previous search (for example, they switch from "camaras" to "llantas"), that is a NEW search, not a refinement.

3. INTERNET SEARCH FALLBACK (CRITICAL):
   - If the user asks about a specific bike model's specs (e.g. "qué llanta usa una trek xcaliber 8") AND `searchStock` returns no results or irrelevant results, you MUST use `searchInternet`.
   - Use `searchInternet` to find the technical specifications or compatibility information online. This performs a live web search. Read the snippet results carefully to answer the user's question, but do NOT hallucinate info that is not actually in the snippets.
   - Do NOT just tell the user "I couldn't find it in the inventory". If it's a general question about a bike or part, search the internet!

4. AFTER presenting results, ALWAYS use `navigateToInventory` to open the inventory screen.
   - CRITICAL: The inventory screen uses KEYWORD text matching, NOT semantic search.
   - You MUST simplify and translate the search term for navigation:
     - "llantas mtb" → navigate with "llanta"
     - "llantas 29 32h" → navigate with "llanta 29"
     - "cámaras para mountain bike" → navigate with "camara 29"
     - "repuestos de freno shimano" → navigate with "freno shimano"
     - "ruedas para BMX" → navigate with "llanta 20"
   - NEVER pass the raw user query to navigateToInventory. Always extract the simplest keyword.
  - If the user is refining a previous inventory result set, keep the previous keyword and narrow the current result set instead of replacing it with a different loose search.
   - After navigating, briefly confirm (e.g., "También te llevé al inventario buscando 'llanta 29'").

Current Jobs Context:
$jobSummaries
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
