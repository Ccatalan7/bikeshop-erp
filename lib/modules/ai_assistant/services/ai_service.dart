import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../inventory/services/inventory_service.dart';

/// Callback type for navigation actions the AI can trigger.
/// The [route] is the path to navigate to (e.g. '/inventory/products').
/// The [searchTerm] is an optional pre-filled search query.
typedef AINavigationCallback = void Function(String route,
    {String? searchTerm});

class AIAssistantService extends ChangeNotifier {
  static final AIAssistantService _instance = AIAssistantService._internal();
  factory AIAssistantService() => _instance;
  AIAssistantService._internal();

  GenerativeModel? _model;
  GenerativeModel? _embeddingModel; // Added for semantic search
  ChatSession? _chatSession;
  final List<Content> _history = [];
  bool _isLoading = false;

  // Tools definition - NOT late final, so it can be reassigned safely
  List<Tool> _tools = [];

  bool get isLoading => _isLoading;
  List<Content> get history => _history;

  void initialize() {
    // Singleton guard: if already initialized, do nothing
    if (_model != null) {
      debugPrint('ℹ️ [AIService] Already initialized, skipping...');
      return;
    }

    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

    if (apiKey.isEmpty) {
      debugPrint('⚠️ GEMINI_API_KEY not found in .env');
      return;
    }

    debugPrint(
        '🔑 [AIService] Initializing with API key starting with: ${apiKey.substring(0, 6)}...');

    // Define tools
    _tools = [
      Tool(functionDeclarations: [
        FunctionDeclaration(
          'searchStock',
          'Search for products in the inventory using semantic search. Understands natural language concepts and meaning, not just exact keywords.',
          Schema(
            SchemaType.object,
            properties: {
              'query': Schema(SchemaType.string,
                  description:
                      'A natural language search query. Can be descriptive concepts (e.g., "ruedas para BMX", "protección para ciclista") or technical terms (e.g., "HG200", "cassette 7v"). The system uses AI vector matching to find semantically similar products.'),
            },
            requiredProperties: ['query'],
          ),
        ),
        FunctionDeclaration(
          'navigateToInventory',
          'Navigates the app to the Inventory module and pre-fills the search box. '
              'WARNING: The inventory screen uses KEYWORD text matching, NOT semantic search. '
              'You MUST simplify and translate the user\'s request into the shortest possible keyword that will match product names. '
              'Examples: "llantas mtb" → "llanta", "cámaras para mountain bike" → "camara", "ruedas para BMX" → "llanta 20". '
              'NEVER pass conversational phrases, categories like "mtb", or connector words like "para", "de", "con".',
          Schema(
            SchemaType.object,
            properties: {
              'searchTerm': Schema(SchemaType.string,
                  description:
                      'The simplified keyword for the inventory text filter. Must match actual product names. Use the shortest effective keyword (e.g., "llanta", "camara 29", "cassette shimano").'),
            },
            requiredProperties: ['searchTerm'],
          ),
        ),
        FunctionDeclaration(
          'searchInternet',
          'Search the internet for information not available in the internal database (e.g., bike compatibility, specs).',
          Schema(
            SchemaType.object,
            properties: {
              'query':
                  Schema(SchemaType.string, description: 'The search query.'),
            },
            requiredProperties: ['query'],
          ),
        ),
      ]),
    ];

    _model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: apiKey,
      tools: _tools,
    );

    // Initialize the embedding model
    _embeddingModel = GenerativeModel(
      model: 'gemini-embedding-001',
      apiKey: apiKey,
    );
  }

  Future<String> sendMessage(
    String message, {
    List<MechanicJob>? jobs,
    InventoryService? inventoryService,
    AINavigationCallback? onNavigate,
  }) async {
    if (_model == null) {
      return 'Error: API Key not configured. Please add GEMINI_API_KEY to .env file.';
    }

    _isLoading = true;
    notifyListeners();

    try {
      // Initialize chat if not already started
      if (_chatSession == null) {
        final systemPrompt = _buildSystemPrompt(jobs ?? []);
        _chatSession = _model!.startChat(history: [
          Content('user', [TextPart(systemPrompt)]),
          Content('model', [
            TextPart(
                'Entendido. Estoy listo para ayudar con trabajos, inventario y preguntas técnicas.')
          ])
        ]);
      }

      var response = await _chatSession!.sendMessage(Content.text(message));

      // Handle Tool Calls (Recursively if needed)
      int maxTurns = 5;
      while (response.functionCalls.isNotEmpty && maxTurns > 0) {
        maxTurns--;
        final functionCalls = response.functionCalls;
        final functionResponses = <FunctionResponse>[];

        for (final call in functionCalls) {
          final name = call.name;
          final args = call.args;

          debugPrint('🔧 [AI] Calling tool: $name with args: $args');

          Map<String, Object?> result;

          if (name == 'searchStock') {
            result = await _toolSearchStock(
                args['query'] as String?, inventoryService);
          } else if (name == 'navigateToInventory') {
            result = _toolNavigateToInventory(
              args['searchTerm'] as String?,
              inventoryService: inventoryService,
              onNavigate: onNavigate,
            );
          } else if (name == 'searchInternet') {
            result = await _toolSearchInternet(args['query'] as String?);
          } else {
            result = {'error': 'Function $name not found'};
          }

          functionResponses.add(FunctionResponse(name, result));
        }

        // Send tool results back to model
        response = await _chatSession!.sendMessage(
          Content.functionResponses(functionResponses),
        );
      }

      final text = response.text;

      if (text == null) {
        return 'Sorry, I could not generate a response.';
      }

      return text;
    } catch (e) {
      debugPrint('Error sending message to Gemini: $e');
      return 'Error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void resetChat() {
    _chatSession = null;
    _history.clear();
    notifyListeners();
  }

  // --- Tool Implementations ---

  Future<Map<String, Object?>> _toolSearchStock(
      String? query, InventoryService? inventory) async {
    if (query == null || query.isEmpty) return {'error': 'Query is empty'};
    if (inventory == null) return {'error': 'Inventory service not available'};

    try {
      debugPrint('🔍 [AI] Combined search for: "$query"');

      // Run BOTH searches in parallel for best results
      final List<Map<String, dynamic>> semanticResults = [];
      final List<Map<String, dynamic>> keywordResults = [];

      // 1. Semantic search
      try {
        final vector = await generateEmbedding(query);
        if (vector != null) {
          final results = await inventory.searchProductsSemantic(vector);
          semanticResults.addAll(results);
          debugPrint(
              '🧠 [AI] Semantic: ${results.length} results for "$query"');
        }
      } catch (e) {
        debugPrint('⚠️ [AI] Semantic search failed: $e');
      }

      // 2. Keyword search
      try {
        final products = await inventory.getProducts(searchTerm: query);
        keywordResults.addAll(products.take(10).map((p) => {
              'name': p.name,
              'sku': p.sku,
              'brand': p.brand ?? '',
              'price': p.price,
              'inventory_qty': p.inventoryQty,
              'warehouse_location': p.warehouseLocation ?? 'Unknown',
              'source': 'keyword',
            }));
        debugPrint(
            '🔤 [AI] Keyword: ${products.length} results for "$query"');
      } catch (e) {
        debugPrint('⚠️ [AI] Keyword search failed: $e');
      }

      // 3. Merge results: deduplicate by SKU, prefer semantic ordering
      final seen = <String>{};
      final merged = <Map<String, dynamic>>[];

      for (final r in [...semanticResults, ...keywordResults]) {
        final sku = (r['sku'] ?? '').toString();
        if (sku.isNotEmpty && seen.contains(sku)) continue;
        if (sku.isNotEmpty) seen.add(sku);
        merged.add(r);
      }

      if (merged.isEmpty) {
        return {
          'result': 'No products found for "$query".'
        };
      }

      debugPrint(
          '✅ [AI] Combined: ${merged.length} unique results for "$query"');

      final summary = merged
          .take(15)
          .map((r) => {
                'name': r['name'] ?? 'Unknown',
                'sku': r['sku'] ?? '',
                'brand': r['brand'] ?? '',
                'price': r['price'] ?? 0,
                'stock': r['inventory_qty'] ?? 0,
                'location': r['warehouse_location'] ?? 'Unknown',
              })
          .toList();

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
    if (_embeddingModel == null) {
      final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
      if (apiKey.isEmpty) return null;
      _embeddingModel = GenerativeModel(
        model: 'gemini-embedding-001',
        apiKey: apiKey,
      );
    }

    try {
      final content = Content.text(text);
      final result = await _embeddingModel!.embedContent(content,
          outputDimensionality: 768);
      return result.embedding.values.toList();
    } catch (e) {
      debugPrint('❌ [AI] Embedding generation error: $e');
      return null;
    }
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

    debugPrint('🧭 [AI] Navigating to inventory with search: "$searchTerm"');

    // Set the saved search term AND signal any active listeners
    if (inventoryService != null) {
      inventoryService.applyExternalSearch(searchTerm);
    }

    // Trigger navigation (closes the dialog and navigates)
    onNavigate('/inventory/products', searchTerm: searchTerm);

    return {
      'success': true,
      'navigatedTo': '/inventory/products',
      'searchTerm': searchTerm,
      'message':
          'Navigated to inventory and searched for "$searchTerm". The results are now displayed on screen.',
    };
  }

  Future<Map<String, Object?>> _toolSearchInternet(String? query) async {
    if (query == null) return {'error': 'Query is empty'};

    // Mock simulation for now
    await Future.delayed(const Duration(seconds: 1));
    return {
      'result': 'Simulated search result for "$query":\n'
          '- Official Trek Archive: Marlin 5 Gen 2 (2022) uses a Shimano HG200, 12-32, 7 speed cassette (or 8 speed depending on sub-model).\n'
          '- Logic suggests checking 7/8 speed HG cassettes compatibility.\n'
          '(Note: Real internet search requires a separate Google Search API key)'
    };
  }

  String _buildSystemPrompt(List<MechanicJob> jobs) {
    // Basic summary of jobs to keep prompt size reasonable
    final jobSummaries = jobs.map((j) {
      return '- Job ${j.jobNumber ?? "N/A"}: ${j.status.name} | ${j.priority.name} | Customer: ${j.customerId} | Bike: ${j.bikeId} | Total: ${j.totalCost}';
    }).join('\n');

    return '''
You are a helpful and powerful AI assistant for "Vinabike" Bike Shop ERP.
Your capabilities include:
1. Managing repair jobs (Pegas).
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
   - CRITICAL: You MUST review and FILTER the results before presenting them. The semantic search may return loosely related products.
   - For example, if the user asks for "llantas 29 32h" (29" rims with 32 holes), only present products that are actually RIMS ("llanta"), not tubes ("camara"), tires ("neumatico"), spokes ("rayos"), hubs ("maza"), or forks ("horquilla").
   - Only present products that genuinely match what the user asked for. If none of the semantic results are relevant, say so.

BIKE NOMENCLATURE — IMPORTANT EQUIVALENCES:
When filtering results, understand that bike parts use many equivalent abbreviations:
- "32H" = "32h" = "32 hoyos" = "32 agujeros" = "32 holes" (all mean 32 spoke holes)
- "36H" = "36 hoyos", "28H" = "28 hoyos", etc.
- "7v" = "7 velocidades" = "7 speed"
- "V/A" = "V.Auto" = "Válvula Auto" = "Schrader valve"
- "V/F" = "V.Francesa" = "Válvula Francesa" = "Presta valve"
- "MTB" = "Mountain Bike" = bikes with 26", 27.5", or 29" wheels
- "Doble Pared" = "Double Wall" (rim construction type)
Always treat these as equivalent when deciding if a product matches the user's query.

2. AFTER presenting results, ALWAYS use `navigateToInventory` to open the inventory screen.
   - CRITICAL: The inventory screen uses KEYWORD text matching, NOT semantic search.
   - You MUST simplify and translate the search term for navigation:
     - "llantas mtb" → navigate with "llanta"
     - "llantas 29 32h" → navigate with "llanta 29"
     - "cámaras para mountain bike" → navigate with "camara 29"
     - "repuestos de freno shimano" → navigate with "freno shimano"
     - "ruedas para BMX" → navigate with "llanta 20"
   - NEVER pass the raw user query to navigateToInventory. Always extract the simplest keyword.
   - After navigating, briefly confirm (e.g., "También te llevé al inventario buscando 'llanta 29'").

When asked about compatibility or specs you don't know, use `searchInternet`.

Current Jobs Context:
$jobSummaries
''';
  }
}
