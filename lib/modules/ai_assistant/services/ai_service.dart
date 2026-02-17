import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../bikeshop/models/bikeshop_models.dart';

class AIAssistantService extends ChangeNotifier {
  static final AIAssistantService _instance = AIAssistantService._internal();
  factory AIAssistantService() => _instance;
  AIAssistantService._internal();

  GenerativeModel? _model;
  ChatSession? _chatSession;
  final List<Content> _history = [];
  bool _isLoading = false;

  bool get isLoading => _isLoading;
  List<Content> get history => _history;

  void initialize() {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('⚠️ GEMINI_API_KEY not found in .env');
      return;
    }

    _model = GenerativeModel(
      model: 'gemini-pro',
      apiKey: apiKey,
    );
  }

  Future<String> sendMessage(String message, List<MechanicJob> jobs) async {
    if (_model == null) {
      return 'Error: API Key not configured. Please add GEMINI_API_KEY to .env file.';
    }

    _isLoading = true;
    notifyListeners();

    try {
      // Initialize chat if not already started
      if (_chatSession == null) {
        final systemPrompt = _buildSystemPrompt(jobs);
        _chatSession = _model!.startChat(history: [
          Content.text(systemPrompt),
          Content.model([
            TextPart('Understood. I am ready to help with the bike shop jobs.')
          ])
        ]);
      }

      final response = await _chatSession!.sendMessage(Content.text(message));
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

  String _buildSystemPrompt(List<MechanicJob> jobs) {
    // Basic summary of jobs to keep prompt size reasonable
    final jobSummaries = jobs.map((j) {
      return '- Job ${j.jobNumber ?? "N/A"}: ${j.status.name} | ${j.priority.name} | Customer: ${j.customerId} | Bike: ${j.bikeId} | Total: ${j.totalCost}';
    }).join('\n');

    return '''
You are a helpful AI assistant for a Bike Shop ERP system.
Your goal is to help the shop manager understand the current state of repair jobs (pegas).

Here is the current list of jobs in the system:
$jobSummaries

Please answer questions about these jobs. You can summarize status, identify urgent or overdue jobs, and calculate totals.
Keep your answers concise and professional.
If asked about something not in the list, politely say you don't have that information.
''';
  }
}
