import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../inventory/services/inventory_service.dart';

class AIAssistantService extends ChangeNotifier {
  static final AIAssistantService _instance = AIAssistantService._internal();
  factory AIAssistantService() => _instance;
  AIAssistantService._internal();

  GenerativeModel? _model;
  ChatSession? _chatSession;
  final List<Content> _history = [];
  bool _isLoading = false;

  // Tools definition
  late final List<Tool> _tools;

  bool get isLoading => _isLoading;
  List<Content> get history => _history;

  void initialize() {
    // Fallback to hardcoded key if .env fails to load (common on Web due to caching)
    final apiKey = dotenv.env['GEMINI_API_KEY'] ??
        'AIzaSyCs2hQbEXJ4xESeemQlWZRusrEUGdQWzBM';

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
3. Answering technical questions about bike compatibility by searching the internet.

When asked about products, ALWAYS check the inventory using the `searchStock` tool.
STRATEGY: 
- **COMPATIBILITY FIRST:** If the user needs a spare part (e.g., for a "Trek Marlin 5"), DO NOT search for the exact stock part (e.g., "Shimano HG200").
- **SEARCH GENERIC SPECS:** Instead, search for the **TECHNICAL SPEC** to find ALL compatible brands.
  - Example: For a 7-speed bike, search for "Cassette 7v" or "Piñon 7v". This will find Shimano, Sunrace, Saiguan, etc.
- **TYPOS:** Correct typos before searching (e.g., "casette" -> "cassette").
- Only search for a specific brand if the user EXPLICITLY asks for it (e.g., "I want a Shimano cassette").

When asked about compatibility or specs you don't know, use `searchInternet`.

Current Jobs Context:
$jobSummaries
''';
  }
}
