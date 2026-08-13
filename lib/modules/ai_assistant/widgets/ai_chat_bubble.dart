import 'dart:async';

import 'package:flutter/material.dart';
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

  const AIChatPanel({
    super.key,
    required this.jobs,
    this.embedded = false,
    this.jobsAreCurrentView = false,
    this.jobsScopeLabel,
    this.allowJobCacheFallback = true,
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
  void _handleCard(AIAssistantActionCard card) {
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
    final services = AIAssistantTurnServices(
      customerService: context.read<CustomerService>(),
      inventoryService: context.read<InventoryService>(),
      bikeshopService: context.read<BikeshopService>(),
      purchaseService: context.read<PurchaseService>(),
      salesService: context.read<SalesService>(),
      taskService: context.read<TaskService>(),
    );

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
                            onApproval: session.resolveTaskApproval,
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
    required this.approvalEnabled,
    required this.approvalBusy,
    required this.approvalDecisionInFlight,
    required this.approvalError,
    required this.onApproval,
  });

  final AIAssistantActionCard card;
  final VoidCallback onTap;
  final bool approvalEnabled;
  final bool approvalBusy;
  final AIAssistantApprovalDecision? approvalDecisionInFlight;
  final String? approvalError;
  final Future<void> Function(AIAssistantApprovalDecision decision) onApproval;

  @override
  Widget build(BuildContext context) {
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
                      const SizedBox(height: 10),
                      if (isApprovalPreview)
                        _TaskApprovalControls(
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

class _TaskApprovalControls extends StatelessWidget {
  const _TaskApprovalControls({
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
      AIAssistantApprovalState.pending =>
        'Vence ${_formatUtcApprovalExpiry(approval.expiresAt)}',
      AIAssistantApprovalState.approved => 'Tarea creada',
      AIAssistantApprovalState.discarded => 'Propuesta descartada',
      AIAssistantApprovalState.expired => 'Propuesta vencida',
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
                    : const Icon(Icons.add_task_rounded),
                label: Text(
                  busy &&
                          decisionInFlight ==
                              AIAssistantApprovalDecision.approve
                      ? 'Creando...'
                      : 'Crear tarea',
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

String _formatUtcApprovalExpiry(DateTime value) {
  final utc = value.toUtc();
  String twoDigits(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${twoDigits(utc.month)}-${twoDigits(utc.day)} · '
      '${twoDigits(utc.hour)}:${twoDigits(utc.minute)} UTC';
}
