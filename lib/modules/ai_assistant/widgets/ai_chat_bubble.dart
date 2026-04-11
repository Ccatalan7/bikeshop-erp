import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../crm/services/customer_service.dart';
import '../../inventory/services/inventory_service.dart';
import '../../purchases/services/purchase_service.dart';
import '../../sales/services/sales_service.dart';
import '../../../shared/services/workspace_manager.dart';
import '../services/ai_service.dart';

class _AIChatMessage {
  const _AIChatMessage({
    required this.role,
    required this.text,
    this.cards = const [],
  });

  final String role;
  final String text;
  final List<AIAssistantActionCard> cards;
}

class AIAssistantButton extends StatelessWidget {
  final List<MechanicJob> jobs;

  const AIAssistantButton({super.key, required this.jobs});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () {
        context.read<WorkspaceManager>().toggleAIPanel();
      },
      tooltip: 'Asistente IA',
      child: const Icon(Icons.smart_toy),
    );
  }
}

class AIChatPanel extends StatefulWidget {
  final List<MechanicJob> jobs;

  const AIChatPanel({super.key, required this.jobs});

  @override
  State<AIChatPanel> createState() => _AIChatPanelState();
}

class _AIChatPanelState extends State<AIChatPanel> {
  final TextEditingController _controller = TextEditingController();
  final List<_AIChatMessage> _messages = [];
  late AIAssistantService _aiService;
  final ScrollController _scrollController = ScrollController();
  final SpeechToText _speechToText = SpeechToText();

  bool _isListening = false;
  bool _speechAvailable = false;
  bool _voiceSubmitPending = false;
  String? _speechLocaleId;

  String? get _voiceInputBlockedReason {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return 'El dictado por voz no está soportado en Linux con este plugin.';
    }

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.macOS &&
        kDebugMode) {
      return 'En macOS, pedir permisos de voz desde una sesión Debug lanzada por VS Code puede cerrar la app. Prueba esta función desde Xcode o en una build no-debug.';
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _aiService = AIAssistantService();
    _aiService.initialize();

    // Backfill product embeddings in the background (only generates missing ones)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (mounted) {
          context.read<InventoryService>().backfillEmbeddings();
        }
      } catch (e) {
        debugPrint('⚠️ [AIChatPanel] Backfill trigger failed: $e');
      }
    });

    // Add welcome message
    _messages.add(const _AIChatMessage(
      role: 'assistant',
      text:
          'Hola! Soy tu asistente de taller. Puedo ayudarte a analizar trabajos, buscar productos en el inventario, y más. ¿Qué necesitas?',
    ));
  }

  /// Called by the AI when it wants to navigate somewhere inside the app.
  void _handleAINavigation(String route, {String? searchTerm}) {
    debugPrint(
        '🧭 [AIChatPanel] AI navigation requested: $route (search: $searchTerm)');

    // Use WorkspaceManager to navigate since we are now a global side panel
    final workspaceManager = context.read<WorkspaceManager>();

    // Defer the navigation slightly so the UI doesn't stutter while animating the chat response
    WidgetsBinding.instance.addPostFrameCallback((_) {
      workspaceManager.navigateActiveWorkspace(route);
    });
  }

  Future<void> _sendMessage({String? overrideText}) async {
    final text = (overrideText ?? _controller.text).trim();
    if (text.isEmpty) return;

    await _stopListening(sendTranscript: false);

    setState(() {
      _messages.add(_AIChatMessage(role: 'user', text: text));
      _controller.clear();
    });

    _scrollToBottom();

    final inventoryService = context.read<InventoryService>();
    final customerService = context.read<CustomerService>();
    final bikeshopService = context.read<BikeshopService>();
    final purchaseService = context.read<PurchaseService>();
    final salesService = context.read<SalesService>();
    final response = await _aiService.sendMessage(
      text,
      jobs: widget.jobs,
      customerService: customerService,
      inventoryService: inventoryService,
      bikeshopService: bikeshopService,
      purchaseService: purchaseService,
      salesService: salesService,
      onNavigate: _handleAINavigation,
    );

    if (mounted) {
      setState(() {
        _messages.add(_AIChatMessage(
          role: 'assistant',
          text: response.text,
          cards: response.cards,
        ));
      });
      _scrollToBottom();
    }
  }

  Future<bool> _ensureSpeechReady() async {
    if (_speechAvailable) {
      return true;
    }

    final available = await _speechToText.initialize(
      onStatus: _handleSpeechStatus,
      onError: _handleSpeechError,
      debugLogging: kDebugMode,
    );

    String? localeId;
    if (available) {
      final locales = await _speechToText.locales();
      localeId = _pickPreferredLocale(locales);
    }

    if (mounted) {
      setState(() {
        _speechAvailable = available;
        _speechLocaleId = localeId;
      });
    }

    return available;
  }

  Future<void> _toggleVoiceInput() async {
    final blockedReason = _voiceInputBlockedReason;
    if (blockedReason != null) {
      _showVoiceMessage(blockedReason);
      return;
    }

    if (_aiService.isLoading) {
      return;
    }

    if (_isListening) {
      await _stopListening(sendTranscript: true);
      return;
    }

    final available = await _ensureSpeechReady();
    if (!available) {
      _showVoiceMessage(
        'No pude habilitar el dictado por voz en este dispositivo.',
      );
      return;
    }

    final started = await _speechToText.listen(
      onResult: _handleSpeechResult,
      listenMode: ListenMode.dictation,
      partialResults: true,
      cancelOnError: true,
      pauseFor: const Duration(seconds: 3),
      listenFor: const Duration(minutes: 1),
      localeId: _speechLocaleId,
    );

    if (!started) {
      _showVoiceMessage('No pude iniciar la grabación por voz.');
      return;
    }

    if (mounted) {
      setState(() {
        _isListening = true;
        _voiceSubmitPending = true;
      });
    }
  }

  Future<void> _stopListening({required bool sendTranscript}) async {
    _voiceSubmitPending = sendTranscript;

    if (!_speechToText.isListening) {
      _finishVoiceSubmissionIfNeeded();
      if (mounted && _isListening) {
        setState(() {
          _isListening = false;
        });
      }
      return;
    }

    await _speechToText.stop();

    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }

  void _handleSpeechStatus(String status) {
    final isListeningNow = status.toLowerCase() == 'listening';

    if (mounted && _isListening != isListeningNow) {
      setState(() {
        _isListening = isListeningNow;
      });
    }

    if (!isListeningNow) {
      _finishVoiceSubmissionIfNeeded();
    }
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }

    if (error.permanent) {
      _showVoiceMessage(
        'El reconocimiento de voz fue bloqueado o no está disponible.',
      );
      return;
    }

    _showVoiceMessage(
        'Hubo un problema al escuchar tu audio. Intenta de nuevo.');
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    final spokenText = result.recognizedWords.trim();
    if (spokenText.isEmpty) return;

    _controller.value = TextEditingValue(
      text: spokenText,
      selection: TextSelection.collapsed(offset: spokenText.length),
    );

    if (result.finalResult) {
      _finishVoiceSubmissionIfNeeded();
    }
  }

  void _finishVoiceSubmissionIfNeeded() {
    if (!_voiceSubmitPending) {
      return;
    }

    _voiceSubmitPending = false;
    final transcript = _controller.text.trim();
    if (transcript.isEmpty) {
      return;
    }

    unawaited(_sendMessage(overrideText: transcript));
  }

  String? _pickPreferredLocale(List<LocaleName> locales) {
    const preferredLocales = [
      'es_CL',
      'es-CL',
      'es_ES',
      'es-ES',
      'es_MX',
      'es-MX',
      'es_US',
      'es-US',
      'es',
      'en_US',
      'en-US',
    ];

    for (final preferred in preferredLocales) {
      for (final locale in locales) {
        if (locale.localeId == preferred) {
          return locale.localeId;
        }
      }
    }

    return locales.isNotEmpty ? locales.first.localeId : null;
  }

  void _showVoiceMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _speechToText.stop();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400, // Fixed width for the side panel
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          left: BorderSide(color: Theme.of(context).dividerColor),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(-2, 0),
            blurRadius: 10,
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.smart_toy, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 8),
                  const Text('Asistente Taller',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  context.read<WorkspaceManager>().toggleAIPanel();
                },
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg.role == 'user';
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Theme.of(context).primaryColor
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: isUser
                        ? Text(msg.text,
                            style: const TextStyle(color: Colors.white))
                        : _AssistantMessageBody(
                            message: msg,
                            onNavigate: _handleAINavigation,
                          ),
                  ),
                );
              },
            ),
          ),
          if (_aiService.isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
          if (_isListening)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.mic_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Escuchando... habla ahora y volveré tu audio en un mensaje.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Pregunta o pide algo al asistente...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: _isListening
                    ? 'Detener y enviar audio'
                    : (_voiceInputBlockedReason ?? 'Hablar con el asistente'),
                child: IconButton(
                  icon: Icon(
                    _isListening
                        ? Icons.stop_circle_outlined
                        : Icons.mic_none_rounded,
                  ),
                  onPressed: _toggleVoiceInput,
                  color: _isListening
                      ? Theme.of(context).colorScheme.error
                      : _voiceInputBlockedReason != null
                          ? Theme.of(context).disabledColor
                          : Theme.of(context).colorScheme.primary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _sendMessage,
                color: Theme.of(context).primaryColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssistantMessageBody extends StatelessWidget {
  const _AssistantMessageBody({
    required this.message,
    required this.onNavigate,
  });

  final _AIChatMessage message;
  final void Function(String route, {String? searchTerm}) onNavigate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.text.trim().isNotEmpty) MarkdownBody(data: message.text),
        if (message.cards.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: message.text.trim().isEmpty ? 0 : 10),
            child: Column(
              children: message.cards
                  .map((card) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _AssistantActionCard(
                          card: card,
                          onTap: () => onNavigate(card.route),
                        ),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _AssistantActionCard extends StatelessWidget {
  const _AssistantActionCard({
    required this.card,
    required this.onTap,
  });

  final AIAssistantActionCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentFor(card.kind, theme);
    final background = Color.lerp(accent, Colors.white, 0.9) ?? Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [background, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_iconFor(card.kind), color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((card.eyebrow ?? '').isNotEmpty)
                        Text(
                          card.eyebrow!.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      Text(
                        card.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF162033),
                        ),
                      ),
                      if ((card.subtitle ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          card.subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[700],
                            height: 1.35,
                          ),
                        ),
                      ],
                      if ((card.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          card.description!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF25324A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (card.chips.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: card.chips
                              .map((chip) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                          color: accent.withValues(alpha: 0.14)),
                                    ),
                                    child: Text(
                                      chip,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: const Color(0xFF2F3B52),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            card.ctaLabel,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.arrow_outward_rounded,
                              color: accent, size: 18),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'customer':
        return Icons.person_rounded;
      case 'job':
        return Icons.build_circle_rounded;
      case 'purchase_invoice':
        return Icons.receipt_long_rounded;
      case 'inventory':
        return Icons.inventory_2_rounded;
      case 'sales_invoice':
        return Icons.point_of_sale_rounded;
      case 'supplier':
        return Icons.local_shipping_rounded;
      default:
        return Icons.link_rounded;
    }
  }

  Color _accentFor(String kind, ThemeData theme) {
    switch (kind) {
      case 'customer':
        return const Color(0xFF7B1FA2);
      case 'job':
        return const Color(0xFF6D4C41);
      case 'purchase_invoice':
        return const Color(0xFFBF6A02);
      case 'inventory':
        return const Color(0xFF1565C0);
      case 'sales_invoice':
        return const Color(0xFF00875A);
      case 'supplier':
        return const Color(0xFF6A1B9A);
      default:
        return theme.colorScheme.primary;
    }
  }
}
