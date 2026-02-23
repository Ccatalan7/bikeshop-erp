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

  /// SKUs from the last searchStock call, used to sync with inventory page.
  List<String>? _lastSearchSkus;

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
          'Search for products in the inventory using semantic AI search. Returns product name, SKU, brand, category, price, stock quantity, and location.',
          Schema(
            SchemaType.object,
            properties: {
              'query': Schema(SchemaType.string,
                  description:
                      'Search query. Use the specific product type in Spanish as it appears in product names '
                      '(e.g., "llanta 29" not "aro 29", "camara 29" not "tubo 29"). '
                      'Include size and specs when the user mentions them.'),
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

      // 1. Semantic search (high threshold = only relevant results)
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
              'category_name': p.categoryName ?? '',
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
        final tokens = query.toLowerCase().split(RegExp(r'\s+'));
        final numericTokens = tokens
            .where((t) => RegExp(r'^\d+\.?\d*$').hasMatch(t))
            .toList();

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

      if (merged.isEmpty) {
        _lastSearchSkus = null;
        return {
          'result': 'No products found for "$query".'
        };
      }

      debugPrint(
          '✅ [AI] Combined: ${merged.length} unique results for "$query"');

      // Save matched SKUs so navigateToInventory can pass them to the list
      _lastSearchSkus = merged
          .map((r) => (r['sku'] ?? '').toString())
          .where((sku) => sku.isNotEmpty)
          .toList();

      final summary = merged
          .take(15)
          .map((r) => {
                'name': r['name'] ?? 'Unknown',
                'sku': r['sku'] ?? '',
                'brand': r['brand'] ?? '',
                'category': r['category_name'] ?? '',
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
      inventoryService.applyExternalSearch(searchTerm,
          matchedSkus: _lastSearchSkus);
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
   - Each result includes: name, SKU, brand, category, price, stock (quantity), and location.
   - YOU are responsible for analyzing results and only presenting products that match what the user asked.
   - Use the "category" field to verify product type. Use "stock" to check availability.
   - If the user asks for "llantas 29", only show products that are actually 29" rims — not tubes, tires, spokes, or other sizes.

2. STOCK & FOLLOW-UP AWARENESS:
   - Each result has a "stock" field. When the user asks "en stock" or "disponible", check the stock field.
   - When the user refines a previous query (adds "en stock", "32h", a brand, etc.), FIRST check if you can answer from results you already have. Don't re-search if you already have the data.

3. AFTER presenting results, ALWAYS use `navigateToInventory` to open the inventory screen.
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
