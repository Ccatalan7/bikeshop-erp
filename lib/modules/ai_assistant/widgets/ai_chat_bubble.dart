import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/services/whatsapp_service.dart';
import '../../../shared/widgets/whatsapp_outgoing_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
import '../../tasks/services/task_service.dart';
import '../../../shared/services/workspace_manager.dart';
import '../../../shared/services/right_toolbar_service.dart';
import '../models/ai_assistant_destination.dart';
import '../models/ai_assistant_session_state.dart';
import '../services/ai_assistant_context_service.dart';
import '../services/ai_assistant_session_service.dart';
import '../services/ai_service.dart';
import 'ai_assistant_compact_action_tile.dart';

class AIAssistantButton extends StatelessWidget {
  final List<MechanicJob> jobs;

  const AIAssistantButton({super.key, required this.jobs});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () {
        context.read<RightToolbarService>().openTool(ToolbarTool.aiAssistant);
      },
      tooltip: 'Asistente IA',
      child: const Icon(Icons.smart_toy),
    );
  }
}

class AIChatPanel extends StatefulWidget {
  final List<MechanicJob> jobs;
  final bool embedded;
  final bool jobsAreCurrentView;
  final String? jobsScopeLabel;
  final bool allowJobCacheFallback;
  final AIAssistantTurnServices? turnServicesOverride;

  const AIChatPanel({
    super.key,
    required this.jobs,
    this.embedded = false,
    this.jobsAreCurrentView = false,
    this.jobsScopeLabel,
    this.allowJobCacheFallback = true,
    @visibleForTesting this.turnServicesOverride,
  });

  @override
  State<AIChatPanel> createState() => _AIChatPanelState();
}

class _AIChatPanelState extends State<AIChatPanel> {
  final TextEditingController _controller = TextEditingController();
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

  // Opening the assistant performs no work of its own — no `initState`
  // override at all. It used to kick off an embeddings backfill on mount,
  // against an RPC that does not exist in production, so every open logged a
  // failure loop the operator never asked for. Backfilling is catalog
  // maintenance, not a side effect of looking at a panel.

  /// Performs the effect registered for a verified card.
  ///
  /// The card supplies an identifier from a closed set; the resolver owns the
  /// route table and the toolbar table. An unregistered identifier produces no
  /// effect at all rather than a guessed route.
  /// El texto exacto que recibirá el cliente, armado con los MISMOS valores
  /// que usará el envío: su nombre, el del negocio y el de quien tiene la
  /// sesión abierta. Devuelve null si falta algo y la tarjeta cae a lo que
  /// mandó el servidor.
  /// Continuaciones que una tarjeta puede ofrecer, por su identificador.
  ///
  /// El catálogo vive **en el cliente** a propósito: la tarjeta la arma el
  /// servidor a partir de lo que devolvió una herramienta, así que dejar que
  /// traiga el texto sería dejar que algo de afuera escriba un mensaje en
  /// nombre del operador. El servidor elige cuál continuación ofrecer; qué
  /// dice, lo decide esta lista.
  static const Map<String, String> _followUpPrompts = <String, String>{
    'restock_by_supplier':
        'Agrupa por proveedor lo que tengo que reponer, y dime qué pedirle '
            'a cada uno.',
    'restock_only_moving':
        'Muéstrame sólo lo que necesito reponer y que además se haya vendido '
            'en los últimos 90 días.',
    'collections_priority':
        'De lo que me deben, ¿a quién le cobro primero? Ordénalo por monto y '
            'por cuánto lleva vencido.',
    'collections_contact':
        'Contacta al cliente que más me debe por su factura vencida.',
    'sales_top_customers':
        '¿Quién me compró más en ese mismo período?',
    'sales_compare_previous':
        'Compara ese período con el anterior: vendido, cobrado y cantidad de '
            'facturas.',
    'workshop_blockers':
        'De esos trabajos, ¿cuáles están frenados y por qué? Separa los que '
            'esperan repuestos, los que esperan aprobación y los en pausa.',
    'workshop_notify_ready':
        'Contacta al cliente del primer trabajo de esa lista para avisarle '
            'cómo va su bicicleta.',
    'tasks_overdue_first':
        'De esas tareas, ¿cuáles están atrasadas? Ordénalas por fecha de '
            'vencimiento, primero las más vencidas.',
  };

  Future<String?> _previewCardOption(
    AIAssistantActionCard card,
    AIAssistantCardOption option,
  ) async {
    if (card.optionKind != 'whatsapp_template') return null;
    final customerId = card.entityRef?.id;
    if (customerId == null) return null;
    final template = WhatsAppService.customerTemplateOptions
        .where((candidate) => candidate.defaultTemplateName == option.id)
        .firstOrNull;
    if (template == null) return null;
    final service = WhatsAppService();
    final contact = await service.customerContactForAssistant(customerId);
    if (contact == null) return null;
    return service.buildTemplatePreviewText(
      option: template,
      customerName: contact.name,
      businessName: contact.businessName,
      agentName: contact.agentName,
    );
  }

  /// Se llama sólo cuando el operador ya revisó el texto en la tarjeta y
  /// apretó Enviar. La revisión vive en el chat, no en un diálogo del sistema:
  /// lo que hay que poder juzgar es cómo le llegará el mensaje al cliente.
  Future<void> _handleCardOption(
    AIAssistantActionCard card,
    AIAssistantCardOption option,
  ) async {
    if (card.optionKind == 'follow_up') {
      final prompt = _followUpPrompts[option.id];
      // Un id que este cliente no conoce no hace nada. Es la misma disciplina
      // que las plantillas: lista cerrada acá, elección allá.
      if (prompt == null) return;
      await _sendMessage(overrideText: prompt);
      return;
    }
    if (card.optionKind != 'whatsapp_template') return;
    final customerId = card.entityRef?.id;
    if (customerId == null) return;
    final template = WhatsAppService.customerTemplateOptions
        .where((candidate) => candidate.defaultTemplateName == option.id)
        .firstOrNull;
    if (template == null) return;

    final service = WhatsAppService();
    final contact = await service.customerContactForAssistant(customerId);
    if (!mounted) return;
    if (contact == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ese cliente no tiene teléfono registrado.'),
        ),
      );
      return;
    }

    final receipt = await service.sendTemplateMessage(
      option: template,
      customerPhone: contact.phone,
      customerName: contact.name,
      // Sin esto, una plantilla que se presenta por persona sale firmada como
      // «parte del equipo» en vez de con el nombre del operador.
      agentName: contact.agentName,
      contextType: 'customer',
      contextId: customerId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          receipt.isSuccess
              ? 'Mensaje enviado a ${contact.name}.'
              : 'No se pudo enviar. Revisa la conversación.',
        ),
      ),
    );
  }

  void _handleCard(AIAssistantActionCard card) {
    final inventoryList = card.inventoryListRef;
    if (inventoryList != null) {
      final inventoryService = widget.turnServicesOverride?.inventoryService ??
          context.read<InventoryService>();
      inventoryService.applyExternalSearch(
        // A complete server projection is an exact ID selection, not a local
        // keyword search. Keep the search box empty so the Product List does
        // not misrepresent structured category/spec filtering as typed text.
        inventoryList.entityIds == null ? inventoryList.query : '',
        matchedProductIds: inventoryList.entityIds,
        stockFilter: switch (inventoryList.availability) {
          AIAssistantInventoryAvailability.any =>
            InventoryExternalStockFilter.any,
          AIAssistantInventoryAvailability.inStock =>
            InventoryExternalStockFilter.inStock,
          AIAssistantInventoryAvailability.lowStock =>
            InventoryExternalStockFilter.lowStock,
          AIAssistantInventoryAvailability.outOfStock =>
            InventoryExternalStockFilter.outOfStock,
        },
      );
    }
    final workspaceManager = context.read<WorkspaceManager>();
    final toolbar = context.read<RightToolbarService>();
    final resolver = AIAssistantDestinationResolver(
      navigateWorkspace: (route) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          workspaceManager.openRouteInWorkspace(route);
        });
      },
      openToolbarTool: toolbar.openTool,
    );

    final dispatched = resolver.dispatch(
      card.destination,
      entityRef: card.entityRef,
    );
    if (!dispatched && !kReleaseMode) {
      debugPrint(
        '🧭 [AIChatPanel] Card destination ${card.destination} has no '
        'compatible registered effect; '
        'ignored.',
      );
    }
  }

  /// Hands the turn to the session service, which is the only sequencer.
  ///
  /// The panel no longer keeps its own message list. Transcript and model
  /// input come from one place, so the two cannot drift apart the way they did
  /// when closing the panel emptied the visible thread while the engine kept
  /// answering from it.
  Future<void> _sendMessage({String? overrideText}) async {
    final session = context.read<AIAssistantSessionService>();
    if (!session.canSend) return;

    final text = (overrideText ?? _controller.text).trim();
    if (text.isEmpty) return;

    await _stopListening(sendTranscript: false);
    if (!mounted) return;

    _controller.clear();
    _scrollToBottom();

    final aiContext = context.read<AIAssistantContextService>();
    final services = widget.turnServicesOverride ??
        AIAssistantTurnServices(
          customerService: context.read<CustomerService>(),
          inventoryService: context.read<InventoryService>(),
          bikeshopService: context.read<BikeshopService>(),
          purchaseService: context.read<PurchaseService>(),
          salesService: context.read<SalesService>(),
          taskService: context.read<TaskService>(),
        );
    final transcriptLengthBefore = session.transcript.length;

    await session.send(
      text,
      services: services,
      visibleJobs: widget.jobs,
      hasVisibleJobsContext: aiContext.hasVisibleJobsContext,
      visibleJobsScopeLabel: widget.jobsScopeLabel,
      jobsAreCurrentView: widget.jobsAreCurrentView,
      allowJobCacheFallback: widget.allowJobCacheFallback,
    );

    if (mounted) {
      _scrollToBottom();
      final transcript = session.transcript;
      if (transcript.length > transcriptLengthBefore) {
        final newAssistantTurns = transcript
            .skip(transcriptLengthBefore)
            .where((entry) => entry.role == AIAssistantTranscriptRole.assistant)
            .toList(growable: false);
        if (newAssistantTurns.length == 1) {
          final autoOpenCards = newAssistantTurns.single.cards
              .where((card) => card.inventoryListRef?.autoOpen == true)
              .toList(growable: false);
          if (autoOpenCards.length == 1) {
            _handleCard(autoOpenCards.single);
          }
        }
      }
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

    if (!context.read<AIAssistantSessionService>().canSend) {
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
      pauseFor: const Duration(seconds: 3),
      listenFor: const Duration(minutes: 1),
      localeId: _speechLocaleId,
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
      ),
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

  /// Why the composer is closed, in the operator's words. Never shows data
  /// from a previous authority.
  static String _composerBlockedHint(AIAssistantSessionStatus status) {
    switch (status) {
      case AIAssistantSessionStatus.signedOut:
        return 'Inicia sesión para usar el asistente.';
      case AIAssistantSessionStatus.resolving:
        return 'Preparando tu sesión...';
      case AIAssistantSessionStatus.unavailable:
        return 'No pude confirmar tu taller. Vuelve a entrar para usar el asistente.';
      case AIAssistantSessionStatus.ready:
        return 'Pregunta o pide algo al asistente...';
    }
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
    final theme = Theme.of(context);
    final session = context.watch<AIAssistantSessionService>();
    final transcript = session.transcript;

    return Container(
      width: widget.embedded ? double.infinity : 400,
      decoration: widget.embedded
          ? null
          : BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(
                left: BorderSide(color: theme.dividerColor),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  offset: const Offset(-2, 0),
                  blurRadius: 10,
                )
              ],
            ),
      padding: EdgeInsets.all(widget.embedded ? 12 : 16),
      child: Column(
        children: [
          if (!widget.embedded) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.smart_toy, color: theme.primaryColor),
                    const SizedBox(width: 8),
                    const Text(
                      'Asistente Taller',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    context.read<RightToolbarService>().close();
                  },
                ),
              ],
            ),
            const Divider(),
          ],
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: transcript.length,
              itemBuilder: (context, index) {
                final msg = transcript[index];
                final isUser = msg.role == AIAssistantTranscriptRole.user;
                final bubbleColor = isUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest;
                final bubbleForeground = isUser
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    key: ValueKey('ai-chat-${msg.role.name}-bubble-$index'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: isUser
                        ? Text(
                            msg.text,
                            style: TextStyle(color: bubbleForeground),
                          )
                        : _AssistantMessageBody(
                            message: msg,
                            onCard: _handleCard,
                            canResolveApproval: session.canResolveApproval,
                            approvalInFlightId: session.approvalInFlightId,
                            approvalDecisionInFlight:
                                session.approvalDecisionInFlight,
                            approvalErrorFor: session.approvalErrorFor,
                            onApproval: session.resolveApproval,
                            onOption: _handleCardOption,
                            onOptionPreview: _previewCardOption,
                          ),
                  ),
                );
              },
            ),
          ),
          if (session.isSending)
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
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.18),
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
                child: CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.enter): () {
                      unawaited(_sendMessage());
                    },
                    const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
                      unawaited(_sendMessage());
                    },
                  },
                  child: TextField(
                    key: const ValueKey<String>('ai-assistant-message-input'),
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    // Fail-closed: while the authority is unresolved, or a
                    // turn is already in flight, there is nothing coherent to
                    // send a message against.
                    enabled: session.canSend,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: session.canSend
                          ? 'Pregunta o pide algo al asistente...'
                          : _composerBlockedHint(session.status),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                enabled: session.canSend,
                // A tooltip alone is announced as a hint, not as the control's
                // name, so the dictation button needs an explicit label.
                label: _isListening
                    ? 'Detener el dictado y enviar el audio'
                    : 'Dictar un mensaje al asistente',
                child: Tooltip(
                  message: _isListening
                      ? 'Detener y enviar audio'
                      : (_voiceInputBlockedReason ?? 'Hablar con el asistente'),
                  child: IconButton(
                    key: const ValueKey<String>('ai-assistant-voice-input'),
                    icon: Icon(
                      _isListening
                          ? Icons.stop_circle_outlined
                          : Icons.mic_none_rounded,
                    ),
                    onPressed: session.canSend ? _toggleVoiceInput : null,
                    color: _isListening
                        ? Theme.of(context).colorScheme.error
                        : _voiceInputBlockedReason != null
                            ? Theme.of(context).disabledColor
                            : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              Semantics(
                button: true,
                enabled: session.canSend,
                label: 'Enviar mensaje al asistente',
                child: IconButton(
                  key: const ValueKey<String>('ai-assistant-send-message'),
                  icon: const Icon(Icons.send),
                  onPressed: session.canSend ? _sendMessage : null,
                  tooltip: 'Enviar mensaje',
                  color: Theme.of(context).primaryColor,
                ),
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
    required this.onCard,
    required this.canResolveApproval,
    required this.approvalInFlightId,
    required this.approvalDecisionInFlight,
    required this.approvalErrorFor,
    required this.onApproval,
    required this.onOption,
    required this.onOptionPreview,
  });

  final AIAssistantTranscriptEntry message;
  final void Function(AIAssistantActionCard card) onCard;
  final bool Function(AIAssistantActionCard card) canResolveApproval;
  final String? approvalInFlightId;
  final AIAssistantApprovalDecision? approvalDecisionInFlight;
  final String? Function(String approvalId) approvalErrorFor;
  final Future<void> Function(
    AIAssistantActionCard card,
    AIAssistantApprovalDecision decision,
  ) onApproval;
  final void Function(
    AIAssistantActionCard card,
    AIAssistantCardOption option,
  ) onOption;
  final Future<String?> Function(
    AIAssistantActionCard card,
    AIAssistantCardOption option,
  ) onOptionPreview;

  void _openSourceInEmbeddedBrowser(BuildContext context, String? href) {
    final uri = Uri.tryParse(href?.trim() ?? '');
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return;
    }

    context.read<WorkspaceManager>().openBrowserWorkspace(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNotice = message.role == AIAssistantTranscriptRole.notice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.text.trim().isNotEmpty)
          if (isNotice)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    message.text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            )
          else
            MarkdownBody(
              data: message.text,
              onTapLink: (_, href, __) =>
                  _openSourceInEmbeddedBrowser(context, href),
            ),
        if (message.cards.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: message.text.trim().isEmpty ? 0 : 10),
            child: Column(
              children: message.cards
                  .map((card) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _AssistantActionCard(
                          card: card,
                          onTap: () => onCard(card),
                          approvalEnabled: canResolveApproval(card),
                          approvalBusy:
                              card.approvalRef?.id == approvalInFlightId,
                          approvalDecisionInFlight:
                              card.approvalRef?.id == approvalInFlightId
                                  ? approvalDecisionInFlight
                                  : null,
                          approvalError: card.approvalRef == null
                              ? null
                              : approvalErrorFor(card.approvalRef!.id),
                          onApproval: (decision) => onApproval(card, decision),
                          onOption: (option) => onOption(card, option),
                          onOptionPreview: (option) =>
                              onOptionPreview(card, option),
                        ),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _AssistantActionCard extends StatefulWidget {
  const _AssistantActionCard({
    required this.card,
    required this.onTap,
    required this.approvalEnabled,
    required this.approvalBusy,
    required this.approvalDecisionInFlight,
    required this.approvalError,
    required this.onApproval,
    required this.onOption,
    required this.onOptionPreview,
  });

  final AIAssistantActionCard card;
  final VoidCallback onTap;
  final void Function(AIAssistantCardOption option) onOption;
  /// Devuelve el texto EXACTO que se enviará, resuelto con los mismos valores
  /// que usa el envío: cliente, negocio y quien tiene la sesión abierta.
  final Future<String?> Function(AIAssistantCardOption option) onOptionPreview;
  final bool approvalEnabled;
  final bool approvalBusy;
  final AIAssistantApprovalDecision? approvalDecisionInFlight;
  final String? approvalError;
  final Future<void> Function(AIAssistantApprovalDecision decision) onApproval;

  @override
  State<_AssistantActionCard> createState() => _AssistantActionCardState();
}

class _AssistantActionCardState extends State<_AssistantActionCard> {
  /// La opción que el operador está revisando. Elegir no envía: abre esta
  /// revisión, y sólo «Enviar» ejecuta.
  AIAssistantCardOption? _reviewing;
  String? _reviewText;

  /// Elegir abre la revisión; nunca envía. El texto se pide resuelto para que
  /// sea el mismo que recibirá el cliente, no una aproximación.
  /// Sólo se revisa antes de ejecutar lo que sale del taller. Una plantilla
  /// llega a un cliente y no se puede deshacer; una continuación sólo le
  /// vuelve a preguntar al asistente, así que exigirle confirmación agrega un
  /// clic y no protege de nada.
  bool get _optionNeedsReview => widget.card.optionKind == 'whatsapp_template';

  Future<void> _choose(AIAssistantCardOption option) async {
    if (!_optionNeedsReview) {
      widget.onOption(option);
      return;
    }
    await _review(option);
  }

  Future<void> _review(AIAssistantCardOption option) async {
    if (_reviewing?.id == option.id) {
      setState(() {
        _reviewing = null;
        _reviewText = null;
      });
      return;
    }
    setState(() {
      _reviewing = option;
      _reviewText = null;
    });
    final text = await widget.onOptionPreview(option);
    if (!mounted || _reviewing?.id != option.id) return;
    setState(() => _reviewText = text ?? option.description ?? option.label);
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final onTap = widget.onTap;
    final onOption = widget.onOption;
    final approvalEnabled = widget.approvalEnabled;
    final approvalBusy = widget.approvalBusy;
    final approvalDecisionInFlight = widget.approvalDecisionInFlight;
    final approvalError = widget.approvalError;
    final onApproval = widget.onApproval;
    if (card.inventoryListRef != null) {
      return AIAssistantCompactActionTile(card: card, onTap: onTap);
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = _accentFor(card.kind, theme);
    // The card used to be tinted white regardless of theme, so in dark mode a
    // panel of white islands sat inside the app's dark chrome. The surface now
    // comes from the scheme and the accent only tints it, which keeps the
    // per-kind cue in both brightnesses.
    final surface = scheme.surfaceContainerHigh;
    final background =
        Color.alphaBlend(accent.withValues(alpha: 0.08), surface);
    // The accent is decorative only — tint, border, shadow, icon wash. It used
    // to paint the eyebrow, the icon, the CTA and its arrow, and those hues
    // were chosen against a white card: `job` (#6D4C41) on the dark surface
    // measures roughly 1.8:1, which nobody can read. Every foreground now
    // comes from a role defined against this surface in both brightnesses.
    final onCard = scheme.onSurface;
    final onCardMuted = scheme.onSurfaceVariant;

    // Two cards of the same kind can appear in one answer, so the key carries
    // the destination too.
    final approvalKey = card.approvalRef?.id;
    final cardKey = 'ai-action-card-${card.kind}-${card.destination.name}'
        '${approvalKey == null ? '' : '-$approvalKey'}';
    final isApprovalPreview = card.approvalRef != null;

    return Material(
      key: ValueKey<String>(cardKey),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        // A preview is a governed command, not a navigation card. Only its
        // explicit approve/discard controls may produce an effect.
        onTap: isApprovalPreview ? null : onTap,
        child: Ink(
          key: ValueKey<String>('$cardKey-ink'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [background, surface],
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
                  child: Icon(_iconFor(card.kind), color: onCard, size: 22),
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
                            color: onCardMuted,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      Text(
                        card.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                      ),
                      if ((card.subtitle ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          card.subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if ((card.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          card.description!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface,
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
                                      color: scheme.surface,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                          color:
                                              accent.withValues(alpha: 0.14)),
                                    ),
                                    child: Text(
                                      chip,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: scheme.onSurface,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                      if (card.options.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        // Elegir una opción no envía: abre la revisión aquí
                        // mismo, con la pinta que tendrá el mensaje en el chat
                        // del cliente. El diálogo del sistema que había antes
                        // sacaba al operador de la conversación para mostrarle
                        // un texto plano que no se parecía a nada.
                        for (final option in card.options)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                // La clave incluye a quién pertenece la
                                // tarjeta: dos contactos en el mismo hilo
                                // ofrecen las mismas plantillas, y sin eso
                                // comparten clave y se confunden.
                                key: Key(
                                  'ai-card-option-${card.kind}'
                                  '-${card.entityRef?.id ?? card.title}'
                                  '-${option.id}',
                                ),
                                onPressed: () => _choose(option),
                                style: OutlinedButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  backgroundColor: _reviewing?.id == option.id
                                      ? accent.withValues(alpha: 0.10)
                                      : null,
                                  side: BorderSide(
                                    color: accent.withValues(
                                      alpha: _reviewing?.id == option.id
                                          ? 0.55
                                          : 0.35,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        option.label,
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                          color: scheme.onSurface,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    // El ícono promete lo que va a pasar. Un
                                    // chevron dice «esto se despliega», y es
                                    // cierto para la plantilla, que abre su
                                    // previsualizado. Una continuación se
                                    // ejecuta al tocar, así que un chevron ahí
                                    // sería una promesa falsa.
                                    Icon(
                                      !_optionNeedsReview
                                          ? Icons.arrow_forward_rounded
                                          : _reviewing?.id == option.id
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                      size: 18,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (_reviewing != null && _reviewText == null)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        if (_reviewing != null && _reviewText != null)
                          WhatsAppOutgoingPreview(
                            key: const Key('ai-card-option-preview'),
                            text: _reviewText!,
                            onCancel: () => setState(() {
                              _reviewing = null;
                              _reviewText = null;
                            }),
                            onSend: () {
                              final chosen = _reviewing!;
                              setState(() {
                                _reviewing = null;
                                _reviewText = null;
                              });
                              onOption(chosen);
                            },
                          ),
                      ],
                      const SizedBox(height: 10),
                      if (isApprovalPreview)
                        _ApprovalControls(
                          approval: card.approvalRef!,
                          enabled: approvalEnabled,
                          busy: approvalBusy,
                          decisionInFlight: approvalDecisionInFlight,
                          error: approvalError,
                          onDecision: onApproval,
                        )
                      else
                        Row(
                          children: [
                            Text(
                              card.ctaLabel,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: onCard,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.arrow_outward_rounded,
                                color: onCard, size: 18),
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
      case 'diagnosis_preview':
      case 'workshop_item_preview':
        return Icons.build_circle_rounded;
      case 'purchase_invoice':
        return Icons.receipt_long_rounded;
      case 'inventory':
        return Icons.inventory_2_rounded;
      case 'sales_invoice':
        return Icons.point_of_sale_rounded;
      case 'task':
      case 'task_preview':
        return Icons.checklist_rounded;
      case 'supplier':
        return Icons.local_shipping_rounded;
      case 'expense':
        return Icons.receipt_rounded;
      case 'conversation':
        return Icons.forum_rounded;
      default:
        return Icons.link_rounded;
    }
  }

  Color _accentFor(String kind, ThemeData theme) {
    switch (kind) {
      case 'customer':
        return const Color(0xFF7B1FA2);
      case 'job':
      case 'diagnosis_preview':
      case 'workshop_item_preview':
        return const Color(0xFF6D4C41);
      case 'purchase_invoice':
        return const Color(0xFFBF6A02);
      case 'task':
      case 'task_preview':
        return theme.colorScheme.tertiary;
      case 'inventory':
        return const Color(0xFF1565C0);
      case 'sales_invoice':
        return const Color(0xFF00875A);
      case 'supplier':
        return const Color(0xFF6A1B9A);
      case 'expense':
        return theme.colorScheme.secondary;
      case 'conversation':
        return theme.colorScheme.primary;
      default:
        return theme.colorScheme.primary;
    }
  }
}

class _ApprovalControls extends StatelessWidget {
  const _ApprovalControls({
    required this.approval,
    required this.enabled,
    required this.busy,
    required this.decisionInFlight,
    required this.error,
    required this.onDecision,
  });

  final AIAssistantApprovalRef approval;
  final bool enabled;
  final bool busy;
  final AIAssistantApprovalDecision? decisionInFlight;
  final String? error;
  final Future<void> Function(AIAssistantApprovalDecision decision) onDecision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stateLabel = switch (approval.state) {
      // «Vence» a secas se leía como el vencimiento de la TAREA, que puede ser
      // mañana, cuando en realidad expira la propuesta y le quedan minutos.
      // Y en UTC: al taller le sobran cuatro horas de diferencia mentales para
      // algo que se decide ahora. Se dice cuánto queda.
      AIAssistantApprovalState.pending =>
        _approvalCountdownLabel(approval.expiresAt),
      AIAssistantApprovalState.approved => switch (approval.action) {
          AIAssistantApprovalAction.createTask => 'Tarea creada',
          AIAssistantApprovalAction.updateDiagnosis =>
            'Diagnóstico actualizado',
          AIAssistantApprovalAction.addWorkshopItem => 'Línea agregada',
        },
      AIAssistantApprovalState.discarded => 'Propuesta descartada',
      AIAssistantApprovalState.expired => 'Propuesta vencida',
    };
    final approveLabel = switch (approval.action) {
      AIAssistantApprovalAction.createTask => 'Crear tarea',
      AIAssistantApprovalAction.updateDiagnosis => 'Actualizar diagnóstico',
      AIAssistantApprovalAction.addWorkshopItem => 'Agregar al trabajo',
    };
    final approvingLabel = switch (approval.action) {
      AIAssistantApprovalAction.createTask => 'Creando...',
      AIAssistantApprovalAction.updateDiagnosis => 'Actualizando...',
      AIAssistantApprovalAction.addWorkshopItem => 'Agregando...',
    };
    final approveIcon = switch (approval.action) {
      AIAssistantApprovalAction.createTask => Icons.add_task_rounded,
      AIAssistantApprovalAction.updateDiagnosis => Icons.save_outlined,
      AIAssistantApprovalAction.addWorkshopItem => Icons.playlist_add_rounded,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          key: ValueKey<String>('ai-approval-${approval.id}-status'),
          children: [
            Icon(
              switch (approval.state) {
                AIAssistantApprovalState.pending => Icons.schedule_rounded,
                AIAssistantApprovalState.approved => Icons.task_alt_rounded,
                AIAssistantApprovalState.discarded => Icons.cancel_outlined,
                AIAssistantApprovalState.expired => Icons.timer_off_outlined,
              },
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                stateLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if ((error ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            error!,
            key: ValueKey<String>('ai-approval-${approval.id}-error'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (approval.state == AIAssistantApprovalState.pending) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: ValueKey<String>('ai-approval-${approval.id}-approve'),
                onPressed: enabled
                    ? () => unawaited(
                          onDecision(AIAssistantApprovalDecision.approve),
                        )
                    : null,
                icon: busy &&
                        decisionInFlight == AIAssistantApprovalDecision.approve
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(approveIcon),
                label: Text(
                  busy &&
                          decisionInFlight ==
                              AIAssistantApprovalDecision.approve
                      ? approvingLabel
                      : approveLabel,
                ),
              ),
              OutlinedButton.icon(
                key: ValueKey<String>('ai-approval-${approval.id}-discard'),
                onPressed: enabled
                    ? () => unawaited(
                          onDecision(AIAssistantApprovalDecision.discard),
                        )
                    : null,
                icon: busy &&
                        decisionInFlight == AIAssistantApprovalDecision.discard
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.close_rounded),
                label: Text(
                  busy &&
                          decisionInFlight ==
                              AIAssistantApprovalDecision.discard
                      ? 'Descartando...'
                      : 'Descartar',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Cuánto le queda a la PROPUESTA, no a lo que propone.
///
/// Una cuenta regresiva no necesita zona horaria ni fecha, y por eso no puede
/// confundirse con la fecha de vencimiento de la tarea que está al lado.
String _approvalCountdownLabel(DateTime value) {
  final restante = value.toUtc().difference(DateTime.now().toUtc());
  if (restante.isNegative) return 'Propuesta vencida';
  final minutos = restante.inMinutes;
  if (minutos < 1) return 'Confirma en menos de 1 min';
  if (minutos < 60) return 'Confirma en $minutos min';
  final horas = restante.inHours;
  return 'Confirma en $horas ${horas == 1 ? 'hora' : 'horas'}';
}
