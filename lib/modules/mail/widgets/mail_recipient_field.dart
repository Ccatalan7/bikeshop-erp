import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../purchases/widgets/brand_mark.dart';
import '../services/mail_recipient_directory.dart';

/// Un campo de destinatarios de Redactar («Para», «CC», «CCO») que sugiere de
/// la libreta del taller mientras se escribe: proveedores, sus contactos,
/// clientes y a quién ya se le escribió (`MailRecipientDirectory`).
///
/// Las sugerencias son filas debajo del campo, en su sitio, y no un menú
/// flotante (`.github/GUI_DESIGN_PRINCIPLES.md`, «Elegir no abre un bloque
/// flotante»). Flechas para moverse, Enter o Tab para elegir, Esc para
/// cerrarlas; con el mouse o el dedo, se toca la fila. Elegir deja
/// «dirección, » con el cursor listo para la siguiente.
class MailRecipientField extends StatefulWidget {
  const MailRecipientField({
    super.key,
    required this.label,
    required this.controller,
    required this.recipients,
    this.decoration = const InputDecoration(),
    this.validator,
    this.excluded = const {},
    this.labelWidth = 60,
    this.maxSuggestions = 6,
    this.fieldKey,
  });

  /// La llave del campo, para que un agente escriba en él (`enter-text`).
  final Key? fieldKey;

  final String label;
  final TextEditingController controller;

  /// La libreta; vacía mientras llega, y el campo se escribe igual a mano.
  final List<MailRecipient> recipients;
  final InputDecoration decoration;
  final FormFieldValidator<String>? validator;

  /// Direcciones ya puestas en los otros campos del mismo correo.
  final Set<String> excluded;
  final double labelWidth;
  final int maxSuggestions;

  @override
  State<MailRecipientField> createState() => _MailRecipientFieldState();
}

class _MailRecipientFieldState extends State<MailRecipientField> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'MailRecipientField');
  List<MailRecipient> _shown = const [];
  int _highlight = 0;
  String? _token;
  String? _dismissed;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focusNode.addListener(_changed);
    _refresh();
  }

  @override
  void didUpdateWidget(MailRecipientField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    _refresh();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focusNode.removeListener(_changed);
    _focusNode.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(_refresh);
  }

  MailRecipientToken _currentToken() {
    final value = widget.controller.value;
    final cursor = value.selection.isValid
        ? value.selection.baseOffset
        : value.text.length;
    return currentMailRecipientToken(value.text, cursor);
  }

  void _refresh() {
    final token = _currentToken();
    if (token.text != _token) {
      _token = token.text;
      _highlight = 0;
      _dismissed = null;
    }
    final typed = token.text.trim();
    _shown = !_focusNode.hasFocus || typed.isEmpty || _dismissed == token.text
        ? const []
        : suggestMailRecipients(
            widget.recipients,
            typed,
            exclude: {
              ...widget.excluded,
              ...mailRecipientAddresses(widget.controller.text, except: token),
            },
            limit: widget.maxSuggestions,
          );
    if (_highlight >= _shown.length) _highlight = 0;
  }

  void _accept(MailRecipient recipient) {
    widget.controller.value =
        acceptMailRecipient(widget.controller.value, recipient.address);
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_shown.isEmpty) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _highlight = (_highlight + 1) % _shown.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(
          () => _highlight = (_highlight - 1 + _shown.length) % _shown.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _dismissed = _token;
        _shown = const [];
      });
      return KeyEventResult.handled;
    }
    final accepts = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        (key == LogicalKeyboardKey.tab &&
            !HardwareKeyboard.instance.isShiftPressed);
    if (accepts) {
      if (event is KeyDownEvent) _accept(_shown[_highlight]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// La tecla de acción del teclado en pantalla: con sugerencias elige la
  /// marcada; sin ellas cierra el teclado, como antes.
  void _editingComplete() {
    if (_shown.isNotEmpty) {
      _accept(_shown[_highlight]);
    } else {
      _focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final validator = widget.validator;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: widget.labelWidth,
              child: Text(
                widget.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _onKey,
                child: TextFormField(
                  key: widget.fieldKey,
                  controller: widget.controller,
                  focusNode: _focusNode,
                  decoration: widget.decoration,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  onEditingComplete: _editingComplete,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  // Mientras el ERP ofrece cómo completar lo que se escribe,
                  // no reclama la dirección a medias; enviar sigue exigiendo
                  // direcciones válidas.
                  validator: validator == null
                      ? null
                      : (value) => _shown.isNotEmpty ? null : validator(value),
                ),
              ),
            ),
          ],
        ),
        if (_shown.isNotEmpty)
          LayoutBuilder(
            // Con espacio, las filas van alineadas bajo el campo; en un
            // teléfono usan todo el ancho para que la dirección se lea.
            builder: (context, constraints) => Padding(
              padding: EdgeInsets.only(
                left: constraints.maxWidth < 420 ? 0 : widget.labelWidth,
                top: 4,
              ),
              // Tocar una fila no es tocar fuera del campo: el foco se queda
              // y la fila recibe el toque.
              child: TextFieldTapRegion(
                child: _MailRecipientSuggestions(
                  recipients: _shown,
                  highlighted: _highlight,
                  onPick: _accept,
                  onHover: (index) {
                    if (index != _highlight) {
                      setState(() => _highlight = index);
                    }
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MailRecipientSuggestions extends StatelessWidget {
  const _MailRecipientSuggestions({
    required this.recipients,
    required this.highlighted,
    required this.onPick,
    required this.onHover,
  });

  final List<MailRecipient> recipients;
  final int highlighted;
  final ValueChanged<MailRecipient> onPick;
  final ValueChanged<int> onHover;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: roles.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < recipients.length; index++)
            _MailRecipientRow(
              key: ValueKey(
                  'mail-recipient-suggestion-${recipients[index].address}'),
              recipient: recipients[index],
              highlighted: index == highlighted,
              onTap: () => onPick(recipients[index]),
              onHover: () => onHover(index),
            ),
        ],
      ),
    );
  }
}

class _MailRecipientRow extends StatelessWidget {
  const _MailRecipientRow({
    super.key,
    required this.recipient,
    required this.highlighted,
    required this.onTap,
    required this.onHover,
  });

  final MailRecipient recipient;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final detail = recipient.detail;
    return Semantics(
      button: true,
      selected: highlighted,
      child: Material(
        color: highlighted ? roles.neutral.container : Colors.transparent,
        child: InkWell(
          canRequestFocus: false,
          onTap: onTap,
          onHover: (inside) {
            if (inside) onHover();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  BrandMark(
                    name: recipient.markName,
                    logoUrl: recipient.logoUrl,
                    size: 28,
                    solid: true,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recipient.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (detail != null)
                          Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
