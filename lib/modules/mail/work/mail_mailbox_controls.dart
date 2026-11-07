import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/services/tenant_service.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/record_peek.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_overlay_surfaces.dart';
import 'mail_navigation.dart';
import 'mail_work_controller.dart';
import 'mail_work_models.dart';
import 'mail_work_words.dart';

/// Las casillas del correo: la bandeja unida o una sola, y su administración.
///
/// El dueño, 2026-11-06, al ver la pantalla nueva: «we lost the controls to
/// manage different accounts, like the merged inbox and the possibility to
/// toggle between different accounts». La bandeja unida sigue siendo lo
/// normal; el selector cambia a una casilla (las pestañas y sus números la
/// siguen) y «Administrar casillas» enciende, apaga o conecta otra.

// ---------------------------------------------------------------------------
// Selector
// ---------------------------------------------------------------------------

/// En el encabezado de escritorio, junto al título.
class MailboxSelector extends StatelessWidget {
  const MailboxSelector({super.key, required this.controller});

  final MailWorkController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final mailbox = controller.mailbox;
    final label = mailbox ?? MailWords.allMailboxes;
    return Builder(
      builder: (anchorContext) => Semantics(
        button: true,
        label: 'Casilla: $label',
        hint: 'Cambiar de casilla',
        excludeSemantics: true,
        child: Material(
          color: roles.neutral.container,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () =>
                unawaited(openMailboxChooser(anchorContext, controller)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      mailbox == null
                          ? Icons.all_inbox_outlined
                          : Icons.inbox_outlined,
                      size: 17,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more,
                        size: 18, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// En el teléfono: un botón junto a la búsqueda.
class MailboxCompactButton extends StatelessWidget {
  const MailboxCompactButton({super.key, required this.controller});

  final MailWorkController controller;

  @override
  Widget build(BuildContext context) {
    final filtered = controller.mailbox != null;
    return Builder(
      builder: (anchorContext) => IconButton(
        tooltip: filtered
            ? 'Casilla: ${controller.mailbox}'
            : 'Casillas: ${MailWords.allMailboxes.toLowerCase()}',
        onPressed: () =>
            unawaited(openMailboxChooser(anchorContext, controller)),
        icon: Icon(filtered ? Icons.inbox_outlined : Icons.all_inbox_outlined),
      ),
    );
  }
}

/// En el teléfono, mientras se ve una sola casilla: que se note y se pueda
/// volver a todas de un toque.
class MailboxFilterStrip extends StatelessWidget {
  const MailboxFilterStrip({super.key, required this.controller});

  final MailWorkController controller;

  @override
  Widget build(BuildContext context) {
    final mailbox = controller.mailbox;
    if (mailbox == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
      decoration: BoxDecoration(
        color: roles.neutral.container,
        border: Border(bottom: BorderSide(color: roles.hairline)),
      ),
      child: Row(
        children: [
          Icon(Icons.inbox_outlined, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sólo $mailbox',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: scheme.onSurface),
            ),
          ),
          TextButton(
            onPressed: () => controller.setMailbox(null),
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            child: const Text('Ver todas'),
          ),
        ],
      ),
    );
  }
}

/// La lista para elegir: anclada al botón en escritorio, hoja en el teléfono.
Future<void> openMailboxChooser(
  BuildContext anchorContext,
  MailWorkController controller,
) {
  return showVbSurface<void>(
    anchorContext: anchorContext,
    title: 'Casillas',
    minWidth: 320,
    maxWidth: 400,
    builder: (surfaceContext) => _MailboxChooser(
      controller: controller,
      onChoose: (address) {
        Navigator.of(surfaceContext).pop();
        controller.setMailbox(address);
      },
      onManage: () {
        Navigator.of(surfaceContext).pop();
        if (anchorContext.mounted) {
          unawaited(showMailboxManager(anchorContext, controller));
        }
      },
    ),
  );
}

class _MailboxChooser extends StatelessWidget {
  const _MailboxChooser({
    required this.controller,
    required this.onChoose,
    required this.onManage,
  });

  final MailWorkController controller;
  final ValueChanged<String?> onChoose;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final mailboxes = controller.counts.mailboxes;
    final total = mailboxes.fold<int>(0, (sum, m) => sum + m.today);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChoiceRow(
          icon: Icons.all_inbox_outlined,
          title: MailWords.allMailboxes,
          subtitle: mailboxes.length < 2
              ? 'La bandeja unida'
              : 'La bandeja unida de ${mailboxes.length}',
          today: total,
          selected: controller.mailbox == null,
          onTap: () => onChoose(null),
        ),
        for (final mailbox in mailboxes)
          _ChoiceRow(
            icon: Icons.inbox_outlined,
            title: mailbox.address,
            subtitle: '${MailWords.providerLabel(mailbox.provider)} · '
                '${MailWords.mailboxSync(lastSyncedAt: mailbox.lastSyncedAt, hasError: mailbox.hasError)}',
            warn: mailbox.hasError,
            today: mailbox.today,
            selected: controller.mailbox == mailbox.address,
            onTap: () => onChoose(mailbox.address),
          ),
        Divider(height: 9, thickness: 1, color: roles.hairline),
        _ChoiceRow(
          icon: Icons.tune,
          title: 'Administrar casillas',
          subtitle: 'Encender, apagar o conectar otra',
          onTap: onManage,
        ),
      ],
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.today,
    this.selected = false,
    this.warn = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int? today;
  final bool selected;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = today ?? 0;
    final countLabel = count == 0 ? 'nada para hoy' : '$count para hoy';
    return Semantics(
      button: true,
      selected: selected,
      label: today == null
          ? '$title. $subtitle'
          : '$title. $subtitle. $countLabel',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                Icon(icon, size: 19, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: warn ? scheme.error : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (today != null) ...[
                  const SizedBox(width: 12),
                  Tooltip(
                    message: countLabel,
                    child: Text(
                      count == 0 ? '—' : '$count',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: count == 0
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
                SizedBox(
                  width: 30,
                  child: selected
                      ? Icon(Icons.check, size: 18, color: scheme.primary)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Administrar
// ---------------------------------------------------------------------------

/// Las casillas de la empresa: cuáles se leen, cómo van y cómo conectar otra.
/// En escritorio entra desde la derecha; en el teléfono es una hoja.
Future<void> showMailboxManager(
  BuildContext context,
  MailWorkController controller,
) {
  return showRecordPeek(
    context,
    panelWidth: 460,
    builder: (hostContext, close) => _MailboxManager(
      controller: controller,
      close: close,
      pageContext: context,
    ),
  );
}

class _MailboxManager extends StatefulWidget {
  const _MailboxManager({
    required this.controller,
    required this.close,
    required this.pageContext,
  });

  final MailWorkController controller;
  final VoidCallback close;

  /// La página del correo: navegar desde aquí usa el enrutador de su espacio
  /// de trabajo, no el de la ventana sobre la que se abre este panel.
  final BuildContext pageContext;

  @override
  State<_MailboxManager> createState() => _MailboxManagerState();
}

class _MailboxManagerState extends State<_MailboxManager> {
  List<MailboxInfo>? _boxes;
  Object? _error;
  String? _confirmingOn;
  final Set<String> _busy = {};

  bool get _canSwitch => TenantService().currentUserRole == 'admin';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final boxes = await widget.controller.service.mailboxes();
      if (!mounted) return;
      setState(() {
        _boxes = boxes;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _setActive(MailboxInfo box, bool active) async {
    setState(() {
      _busy.add(box.id);
      _confirmingOn = null;
    });
    try {
      await widget.controller.service.setMailboxActive(box.id, active);
      if (!active && widget.controller.mailbox == box.address) {
        widget.controller.setMailbox(null);
      }
      await _load();
      unawaited(widget.controller.refresh(silent: true));
      // Una casilla recién encendida trae su correo ahora, no en 2 minutos.
      if (active) unawaited(widget.controller.syncNow());
    } catch (error) {
      _say('$error'.contains('mail_forbidden')
          ? 'Sólo un administrador enciende o apaga una casilla.'
          : 'No se pudo cambiar la casilla. Vuelve a intentar.');
    } finally {
      if (mounted) setState(() => _busy.remove(box.id));
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _openProviderInbox(String location) {
    final page = widget.pageContext;
    widget.close();
    if (page.mounted) openMailRoute(page, location);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final boxes = _boxes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Casillas de la empresa',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: widget.close,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                'Lo que llega a una casilla encendida lo lee todo el equipo, '
                'ligado a sus trabajos, clientes y compras. Una casilla '
                'conectada nace apagada: el correo personal de alguien nunca '
                'se guarda para todos.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              if (boxes == null && _error == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (boxes == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'No se pudieron leer las casillas.',
                          style:
                              TextStyle(fontSize: 14, color: scheme.onSurface),
                        ),
                      ),
                      VbButton(
                        label: 'Reintentar',
                        variant: VbButtonVariant.text,
                        onPressed: () {
                          setState(() => _error = null);
                          unawaited(_load());
                        },
                      ),
                    ],
                  ),
                )
              else if (boxes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Nadie ha conectado una casilla todavía.',
                    style: TextStyle(fontSize: 14, color: scheme.onSurface),
                  ),
                )
              else
                for (final box in boxes) ...[
                  Divider(height: 1, thickness: 1, color: roles.hairline),
                  _MailboxRow(
                    box: box,
                    canSwitch: _canSwitch,
                    busy: _busy.contains(box.id),
                    confirming: _confirmingOn == box.id,
                    onChanged: (value) {
                      if (value) {
                        setState(() => _confirmingOn = box.id);
                      } else {
                        unawaited(_setActive(box, false));
                      }
                    },
                    onConfirm: () => unawaited(_setActive(box, true)),
                    onCancel: () => setState(() => _confirmingOn = null),
                    onReconnect: () => _openProviderInbox(
                        '/mail/bandeja?connect=${box.provider}'),
                  ),
                ],
              if (boxes != null && boxes.isNotEmpty)
                Divider(height: 1, thickness: 1, color: roles.hairline),
              if (boxes != null && boxes.isNotEmpty && !_canSwitch) ...[
                const SizedBox(height: 10),
                Text(
                  'Sólo un administrador enciende o apaga una casilla.',
                  style:
                      TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 26),
              const _SectionLabel('Conectar otra'),
              const SizedBox(height: 6),
              for (final (provider, label) in const [
                ('gmail', 'Conectar Gmail'),
                ('zoho', 'Conectar Zoho'),
              ])
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        _openProviderInbox('/mail/bandeja?connect=$provider'),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(label),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                'Se conecta con tu cuenta y queda apagada hasta que un '
                'administrador la encienda.',
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 26),
              const _SectionLabel('En el proveedor'),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openProviderInbox('/mail/bandeja'),
                  icon: const Icon(Icons.open_in_new, size: 17),
                  label: const Text('Abrir la bandeja de Gmail y Zoho'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              ),
              Text(
                'Borradores, spam y papelera siguen allá, como llegan.',
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.9,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MailboxRow extends StatelessWidget {
  const _MailboxRow({
    required this.box,
    required this.canSwitch,
    required this.busy,
    required this.confirming,
    required this.onChanged,
    required this.onConfirm,
    required this.onCancel,
    required this.onReconnect,
  });

  final MailboxInfo box;
  final bool canSwitch;
  final bool busy;
  final bool confirming;
  final ValueChanged<bool> onChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failing = box.active && (box.lastSyncError ?? '').isNotEmpty;
    final status = !box.active
        ? 'Apagada: su correo no se guarda ni se muestra'
        : MailWords.mailboxSync(
            lastSyncedAt: box.lastSyncedAt,
            hasError: failing,
          );
    final statusText = '${box.providerLabel} · $status';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Row(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 20,
                  color:
                      box.active ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        box.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: box.active
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color:
                              failing ? scheme.error : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (busy)
                  const SizedBox(
                    width: 48,
                    height: 32,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
                  Switch(
                    value: box.active || confirming,
                    onChanged: canSwitch && !confirming ? onChanged : null,
                  ),
              ],
            ),
          ),
          if (failing) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onReconnect,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: Text('Volver a conectar ${box.providerLabel}'),
                ),
              ),
            ),
          ],
          if (confirming) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Todo el equipo va a leer el correo de esta casilla: el de '
                    'los últimos 120 días y lo que llegue.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      VbButton(label: 'Encender', onPressed: onConfirm),
                      VbButton(
                        label: 'Cancelar',
                        variant: VbButtonVariant.text,
                        onPressed: onCancel,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
