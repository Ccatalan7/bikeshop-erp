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

    // Define tools
    _tools = [
      Tool(functionDeclarations: [
        FunctionDeclaration(
          'searchStock',
          'Search for products in the inventory to check stock, price, and availability.',
          Schema(
            SchemaType.object,
            properties: {
              'query': Schema(SchemaType.string,
                  description:
                      'The product name, brand, or category to search for. Use short keywords (e.g., "HG200", "Cassette 7v") instead of long sentences.'),
            },
            requiredProperties: ['query'],
          ),
        ),
        FunctionDeclaration(
          'navigateToInventory',
          'Navigates the app to the Inventory module and pre-fills the search box with a query. '
              'Use this when the user asks to "show", "find", "list", or "buscar" products, parts, or items. '
              'CRITICAL: You MUST extract concise, searchable keywords. NEVER pass the raw conversational sentence. '
              'For bike parts, simplify to core components and dimensions (e.g., "llanta 20", "neumatico 29", "cassette 7v"). '
              'DO NOT use connector words like "para", "de", "con". '
              'After navigating, always confirm to the user what you did.',
          Schema(
            SchemaType.object,
            properties: {
              'searchTerm': Schema(SchemaType.string,
                  description:
                      'The semantic keyword search term (e.g., "llanta 20", "camara 29"). Never use full phrases.'),
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
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      tools: _tools,
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
          Content.text(systemPrompt),
          Content.model([
            TextPart(
                'Understood. I am ready to help with bike shop jobs, inventory, and technical questions.')
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
      final products = await inventory.getProducts(searchTerm: query);
      if (products.isEmpty) {
        return {'result': 'No products found for "$query".'};
      }

      final summary = products
          .take(5)
          .map((p) => {
                'name': p.name,
                'sku': p.sku,
                'price': p.price,
                'stock': p.inventoryQty,
                'location': p.warehouseLocation ?? 'Unknown',
              })
          .toList();

      return {
        'count': products.length,
        'products': summary,
      };
    } catch (e) {
      return {'error': 'Failed to search inventory: $e'};
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
2. Checking inventory stock and prices.
3. Navigating the app to show the user specific products in the Inventory module.
4. Answering technical questions about bike compatibility by searching the internet.

CRITICAL RULES FOR SEARCHING AND NAVIGATING INVENTORY:
1. The inventory system uses basic text matching. It CANNOT understand conversational queries.
2. When answering queries like "Do we have tires for a BMX?" or "Show me rims for a 29er":
   - You MUST translate the request into the actual technical specs.
   - BMX parts usually use "20" (e.g., "llanta 20", "neumatico 20", "camara 20").
   - Mountain bikes usually use "29", "27.5", or "26".
   - Road bikes usually use "700".
3. NEVER pass connector words to `searchStock` or `navigateToInventory` (e.g., instead of "llantas para bmx", use "llanta 20". Instead of "pastillas de freno shimano", use "pastilla shimano").
4. If a generic search returns 0 results, try simplifying it to just the core component (e.g., just "llanta").

NAVIGATION STRATEGY:
- When the user asks to "show", "find", "list", "buscar", "mostrar", or "listar" any product or item, ALWAYS use the `navigateToInventory` tool.
- After navigating, confirm to the user what you did in one short sentence (e.g., "Te llevé al inventario con las llantas aro 20").

When asked about compatibility or specs you don't know, use `searchInternet`.

Current Jobs Context:
$jobSummaries
''';
  }
}
