import 'package:flutter/material.dart';

import '../utils/responsive_breakpoints.dart';
import '../themes/vinabike_theme_roles.dart';
import 'vb_anchored_popover.dart';

/// Owners compartidos de superficie contextual con host dual:
/// **O-02** popover anclado en escritorio y **O-05** bottom sheet en
/// compacto (< `ResponsiveBreakpoints.desktopMin`), con la misma anatomía que
/// publican S-05/S-06 en la guía: popover con 4 px de gap que se voltea si no
/// cabe; hoja con radio superior 14, handle 34×4 `pill`, título anunciado y
/// máx. 60 % de alto («con más, es una página»).
///
/// Un contenido largo hace scroll dentro de la superficie; el teclado empuja
/// la hoja con `viewInsets`.

bool vbSurfaceIsTouchHost(BuildContext context) =>
    MediaQuery.sizeOf(context).width < ResponsiveBreakpoints.desktopMin;

/// Abre [builder] en el host dual. En escritorio ancla al `anchorContext`
/// (el propio botón que lo invoca); en compacto abre la hoja O-05 titulada.
Future<T?> showVbSurface<T>({
  required BuildContext anchorContext,
  required String title,
  required WidgetBuilder builder,
  double minWidth = 288,
  double maxWidth = 460,
}) {
  if (!vbSurfaceIsTouchHost(anchorContext)) {
    return showVbAnchoredPopover<T>(
      anchorContext: anchorContext,
      minWidth: minWidth,
      barrierLabel: 'Cerrar $title',
      builder: (popoverContext) => _VbSurfacePopoverChrome(
        title: title,
        maxWidth: maxWidth,
        child: builder(popoverContext),
      ),
    );
  }
  final media = MediaQuery.of(anchorContext);
  return showModalBottomSheet<T>(
    context: anchorContext,
    // La superficie la pinta O-05, no el tema del sheet.
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    constraints: BoxConstraints(
      // «Máx. 60% de alto; con más, es una página.»
      maxHeight: media.size.height * 0.6,
    ),
    builder: (sheetContext) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: _VbSurfaceSheetChrome(
        title: title,
        child: builder(sheetContext),
      ),
    ),
  );
}

class _VbSurfacePopoverChrome extends StatelessWidget {
  const _VbSurfacePopoverChrome({
    required this.title,
    required this.maxWidth,
    required this.child,
  });

  final String title;
  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // La superficie O-02 es del owner canónico (radio, borde y sombra F-05
    // viven en VbPopoverSurface); aquí solo se compone título + contenido.
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: VbPopoverSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Flexible(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );
  }
}

class _VbSurfaceSheetChrome extends StatelessWidget {
  const _VbSurfaceSheetChrome({required this.title, required this.child});

  final String title;
  final Widget child;

  static const double _sheetRadius = 14;
  static const double _pillRadius = 999;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    const radius = BorderRadius.vertical(top: Radius.circular(_sheetRadius));

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: roles.shadow,
            blurRadius: 40,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: scheme.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle 34×4 `pill`. Decorativo: lo que se anuncia es el título.
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(top: 9, bottom: 7),
                  child: Center(
                    child: Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outline,
                        borderRadius: BorderRadius.circular(_pillRadius),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 0, 13, 6),
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Flexible(child: SingleChildScrollView(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Captura breve de un motivo obligatorio, en el host dual.
///
/// Devuelve el texto no vacío, o null si se canceló. El botón dice lo que
/// hace ([confirmLabel]); nunca «OK».
Future<String?> showVbReasonPrompt({
  required BuildContext anchorContext,
  required String title,
  required String hint,
  required String confirmLabel,
}) {
  return showVbSurface<String>(
    anchorContext: anchorContext,
    title: title,
    builder: (_) => _VbReasonPromptBody(
      hint: hint,
      confirmLabel: confirmLabel,
    ),
  );
}

/// Owns the reason controller for exactly as long as the routed surface is
/// mounted. A popup route's result completes when `pop` starts, before its
/// reverse transition has removed the widgets; disposing from `whenComplete`
/// therefore left the exiting TextField listening to a dead controller and
/// could corrupt the inherited-element teardown during an immediate model
/// refresh.
class _VbReasonPromptBody extends StatefulWidget {
  const _VbReasonPromptBody({
    required this.hint,
    required this.confirmLabel,
  });

  final String hint;
  final String confirmLabel;

  @override
  State<_VbReasonPromptBody> createState() => _VbReasonPromptBodyState();
}

class _VbReasonPromptBodyState extends State<_VbReasonPromptBody> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    if (reason.isNotEmpty) Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 2,
            decoration: InputDecoration(hintText: widget.hint, isDense: true),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => FilledButton(
                  onPressed: value.text.trim().isEmpty ? null : _submit,
                  child: Text(widget.confirmLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
