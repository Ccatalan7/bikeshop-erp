import 'dart:async';

import 'package:flutter/material.dart';

import '../services/network/network_resilience.dart';
import '../themes/vinabike_theme_roles.dart';
import 'vb_button.dart';
import 'vb_overlay_surfaces.dart';
import 'vb_status_pill.dart';

/// Lo que el ERP dice de la conexión, encima de todas las pantallas.
///
/// Nunca dice «guardado» si no llegó (2026-11-04: «cosas que yo sé que
/// registré no quedan registradas»). Muestra, en este orden de importancia:
/// - **Sin conexión · reintentando**: lo último no llegó al servidor;
/// - **N cambios sin guardar**: guardados que no llegaron y quedaron en este
///   equipo; tocarlo abre la bandeja para reenviarlos o descartarlos;
/// - **Guardando… la conexión está lenta**: un guardado lleva más de 6 s;
/// - **Conexión recuperada**: unos segundos, al volver, con lo que se envió.
///
/// Sin nada que decir no ocupa lugar.
class ConnectionStatusPrompt extends StatefulWidget {
  const ConnectionStatusPrompt({super.key, this.status, this.journal});

  final ConnectionStatus? status;
  final UnsavedChangesJournal? journal;

  @override
  State<ConnectionStatusPrompt> createState() => _ConnectionStatusPromptState();
}

enum _PromptKind { none, offline, unsaved, slow, recovered }

class _ConnectionStatusPromptState extends State<ConnectionStatusPrompt>
    with WidgetsBindingObserver {
  ConnectionStatus get _status => widget.status ?? ConnectionStatus.instance;
  UnsavedChangesJournal get _journal =>
      widget.journal ?? UnsavedChangesJournal.instance;

  bool _wasOffline = false;
  bool _showRecovered = false;
  int _sentSinceRecovery = 0;
  Timer? _recoveredTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wasOffline = _status.isOffline;
    _status.addListener(_onStatus);
    _journal.addListener(_onJournal);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _status.removeListener(_onStatus);
    _journal.removeListener(_onJournal);
    _recoveredTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Al volver al frente: el sistema pudo haber dormido la red de la app.
    unawaited(_status.checkNow());
    unawaited(_journal.resendSafe());
  }

  void _onStatus() {
    final offline = _status.isOffline;
    if (_wasOffline && !offline) _flashRecovered();
    _wasOffline = offline;
    if (mounted) setState(() {});
  }

  void _onJournal() {
    final sent = _journal.takeRecentlySaved();
    if (sent > 0) {
      _sentSinceRecovery += sent;
      _flashRecovered();
    }
    if (mounted) setState(() {});
  }

  void _flashRecovered() {
    _recoveredTimer?.cancel();
    _showRecovered = true;
    _recoveredTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _showRecovered = false;
        _sentSinceRecovery = 0;
      });
    });
  }

  _PromptKind get _kind {
    if (_status.health == ConnectionHealth.offline) return _PromptKind.offline;
    if (_journal.pendingCount > 0) return _PromptKind.unsaved;
    if (_status.health == ConnectionHealth.slow) return _PromptKind.slow;
    if (_showRecovered) return _PromptKind.recovered;
    return _PromptKind.none;
  }

  void _openJournal(BuildContext anchorContext) {
    unawaited(showUnsavedChangesPanel(anchorContext, journal: _journal));
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    final bottom = MediaQuery.paddingOf(context).bottom + 18;
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: IgnorePointer(
        ignoring: kind == _PromptKind.none,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.35),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _buildPill(context, kind),
          ),
        ),
      ),
    );
  }

  Widget _buildPill(BuildContext context, _PromptKind kind) {
    final roles = VinabikeThemeRoles.of(context);
    final pending = _journal.pendingCount;
    final unsavedText = pending == 1 ? '1 sin guardar' : '$pending sin guardar';
    // En un teléfono no cabe todo: lo que no puede cortarse es cuánto quedó
    // sin guardar; «reintentando» ya lo dice el aviso mismo.
    final compact = MediaQuery.sizeOf(context).width < 600;
    switch (kind) {
      case _PromptKind.none:
        return const SizedBox.shrink(key: ValueKey('connection-prompt-none'));
      case _PromptKind.offline:
        return Builder(
          key: const ValueKey('connection-prompt-offline'),
          builder: (anchorContext) => VbStatusPill(
            tone: roles.warning,
            icon: Icons.wifi_off_rounded,
            title: 'Sin conexión',
            detail: pending == 0
                ? 'Reintentando…'
                : compact
                    ? unsavedText
                    : 'Reintentando · $unsavedText',
            actionLabel: pending > 0 ? 'Revisar' : 'Probar ahora',
            onTap: pending > 0
                ? () => _openJournal(anchorContext)
                : () => unawaited(_status.checkNow()),
          ),
        );
      case _PromptKind.unsaved:
        return Builder(
          key: const ValueKey('connection-prompt-unsaved'),
          builder: (anchorContext) => VbStatusPill(
            tone: roles.danger,
            icon: Icons.cloud_off_rounded,
            title: pending == 1
                ? '1 cambio sin guardar'
                : '$pending cambios sin guardar',
            detail: 'Quedaron en este equipo',
            actionLabel: 'Revisar',
            onTap: () => _openJournal(anchorContext),
          ),
        );
      case _PromptKind.slow:
        return VbStatusPill(
          key: const ValueKey('connection-prompt-slow'),
          tone: roles.info,
          busy: true,
          title: 'Guardando…',
          detail: 'La conexión está lenta',
        );
      case _PromptKind.recovered:
        return VbStatusPill(
          key: const ValueKey('connection-prompt-recovered'),
          tone: roles.success,
          icon: Icons.cloud_done_rounded,
          title: 'Conexión recuperada',
          detail: _sentSinceRecovery == 0
              ? null
              : _sentSinceRecovery == 1
                  ? '1 cambio enviado'
                  : '$_sentSinceRecovery cambios enviados',
        );
    }
  }
}

/// Abre la bandeja de lo que no llegó: anclada al aviso en escritorio, desde
/// abajo en el teléfono.
Future<void> showUnsavedChangesPanel(
  BuildContext anchorContext, {
  UnsavedChangesJournal? journal,
}) {
  return showVbSurface<void>(
    anchorContext: anchorContext,
    title: 'Cambios sin guardar',
    minWidth: 360,
    maxWidth: 480,
    builder: (_) => UnsavedChangesPanel(
      journal: journal ?? UnsavedChangesJournal.instance,
    ),
  );
}

/// La lista de lo que no llegó, con «Reenviar» y «Descartar».
class UnsavedChangesPanel extends StatelessWidget {
  const UnsavedChangesPanel({super.key, required this.journal});

  final UnsavedChangesJournal journal;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: journal,
      builder: (context, _) {
        final roles = VinabikeThemeRoles.of(context);
        final text = Theme.of(context).textTheme;
        final changes = journal.pending;
        // La superficie compartida sólo pinta el título: el contenido trae su
        // propio margen, el mismo del título.
        const inset = EdgeInsets.fromLTRB(14, 8, 14, 14);
        if (changes.isEmpty) {
          // Vacía también después de «Descartar»: no se afirma que llegó.
          return Padding(
            padding: inset,
            child: Row(
              children: [
                Icon(Icons.cloud_done_rounded, color: roles.success.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No queda nada pendiente en este equipo.',
                    style: text.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        }
        final harmless =
            changes.where((c) => c.resendIsHarmless && c.canResend).length;
        // La superficie ya hace scroll: las filas van en una columna simple,
        // sin una lista con scroll propio adentro.
        return Padding(
          padding: inset,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'No llegaron al servidor y quedaron guardados en este equipo. '
                'Lo que no puede quedar dos veces se envía solo apenas vuelve la '
                'conexión; lo demás lo decides tú.',
                style: text.bodySmall?.copyWith(
                  color: roles.shell.mutedForeground,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 4),
              for (var index = 0; index < changes.length; index++) ...[
                if (index > 0) Divider(height: 1, color: roles.hairline),
                _UnsavedChangeRow(
                  key: ValueKey('unsaved-change-${changes[index].id}'),
                  change: changes[index],
                  journal: journal,
                ),
              ],
              if (harmless >= 2) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: VbButton(
                    label: 'Reenviar los $harmless seguros',
                    icon: Icons.send_rounded,
                    variant: VbButtonVariant.secondary,
                    onPressed: () => unawaited(journal.resendSafe()),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _UnsavedChangeRow extends StatefulWidget {
  const _UnsavedChangeRow({
    super.key,
    required this.change,
    required this.journal,
  });

  final UnsavedChange change;
  final UnsavedChangesJournal journal;

  @override
  State<_UnsavedChangeRow> createState() => _UnsavedChangeRowState();
}

class _UnsavedChangeRowState extends State<_UnsavedChangeRow> {
  bool _confirmingDiscard = false;
  String? _outcome;

  Future<void> _resend() async {
    final result = await widget.journal.resend(widget.change.id);
    if (!mounted) return;
    setState(() {
      _outcome = switch (result) {
        UnsavedChangeResend.saved => null,
        UnsavedChangeResend.rejected =>
          'El servidor no lo aceptó: mira el motivo antes de volver a intentar.',
        UnsavedChangeResend.stillOffline =>
          'Tampoco llegó: sigue sin conexión.',
        UnsavedChangeResend.serverBusy =>
          'El servidor no pudo atenderlo ahora. Prueba de nuevo en un rato.',
        UnsavedChangeResend.unavailable =>
          'No se puede reenviar desde aquí: vuelve a hacerlo en su pantalla.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final text = Theme.of(context).textTheme;
    final change = widget.change;
    final sending = widget.journal.isSending(change.id);
    final mayHaveArrived = !change.notSent && !change.resendIsHarmless;
    final title = change.detail == null
        ? change.label
        : '${change.label} · ${change.detail}';
    final state =
        change.notSent ? 'No llegó al servidor' : 'Puede que haya llegado';
    final muted = roles.shell.mutedForeground;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  _iconFor(change.effect),
                  size: 18,
                  color: mayHaveArrived
                      ? roles.warning.accent
                      : roles.danger.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$state · ${_when(change.createdAt)}',
                      style: text.bodySmall?.copyWith(color: muted),
                    ),
                    if (mayHaveArrived) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Antes de reenviar, revisa que no esté ya guardado: '
                        'si lo está, quedaría dos veces.',
                        style: text.bodySmall?.copyWith(
                          color: roles.warning.onContainer,
                          height: 1.3,
                        ),
                      ),
                    ],
                    if (change.lastError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        change.lastError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            ?.copyWith(color: muted, fontSize: 11.5),
                      ),
                    ],
                    if (_outcome != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _outcome!,
                        style: text.bodySmall?.copyWith(
                          color: roles.danger.onContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: _confirmingDiscard
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '¿Descartarlo? No se va a guardar.',
                        style: text.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      VbButton(
                        label: 'Descartar',
                        variant: VbButtonVariant.destructive,
                        onPressed: () =>
                            unawaited(widget.journal.discard(change.id)),
                      ),
                      VbButton(
                        label: 'Volver',
                        variant: VbButtonVariant.text,
                        onPressed: () =>
                            setState(() => _confirmingDiscard = false),
                      ),
                    ],
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      VbButton(
                        label: 'Reenviar',
                        icon: Icons.send_rounded,
                        variant: mayHaveArrived
                            ? VbButtonVariant.secondary
                            : VbButtonVariant.primary,
                        busy: sending,
                        onPressed: change.canResend
                            ? () => unawaited(_resend())
                            : null,
                        disabledReason: change.canResend
                            ? null
                            : 'Era muy grande para guardarlo: vuelve a hacerlo',
                      ),
                      VbButton(
                        label: 'Descartar',
                        variant: VbButtonVariant.text,
                        onPressed: sending
                            ? null
                            : () => setState(() => _confirmingDiscard = true),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(RequestEffect effect) => switch (effect) {
        RequestEffect.keyedCommand => Icons.receipt_long_rounded,
        RequestEffect.repeatableWrite => Icons.edit_note_rounded,
        _ => Icons.note_add_outlined,
      };

  static String _when(DateTime at) {
    final now = DateTime.now();
    final age = now.difference(at);
    if (age.inMinutes < 1) return 'recién';
    if (age.inMinutes < 60) return 'hace ${age.inMinutes} min';
    final time =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    if (day == today) return 'hoy $time';
    if (today.difference(day).inDays == 1) return 'ayer $time';
    return '${at.day}/${at.month} $time';
  }
}
