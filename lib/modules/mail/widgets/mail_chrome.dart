import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../purchases/widgets/brand_mark.dart';

/// Las piezas que comparten las dos vistas del correo, Inteligente y Normal.
///
/// El dueño (2026-11-08): «odio que la versión inteligente y la normal tenga
/// UI diferente». Las dos vistas ordenan distinto —una por lo que hay que
/// hacer, la otra por carpeta— pero se dibujan con la misma fila, la misma
/// barra y el mismo buscador. Un cambio de aspecto se hace aquí, una vez.

/// Una fila de la lista de correos.
///
/// Marca o iniciales del remitente (con el logo de la cuenta en la esquina
/// cuando se mezclan cuentas), quién escribe con el punto de no leído y la
/// hora, el asunto, y una línea de detalle: lo que el ERP leyó en la vista
/// Inteligente, el comienzo del correo en la Normal. A la derecha del detalle
/// va el estado («Por confirmar») o el clip de adjuntos.
class MailListRow extends StatelessWidget {
  const MailListRow({
    super.key,
    required this.title,
    required this.markName,
    required this.time,
    required this.subject,
    required this.onTap,
    this.markLogoUrl,
    this.accountBadge,
    this.detail,
    this.detailIcon,
    this.status,
    this.statusDone = false,
    this.unread = false,
    this.dimmed = false,
    this.selected = false,
    this.compact = false,
    this.hasAttachment = false,
  });

  final String title;
  final String markName;
  final String? markLogoUrl;

  /// Logo chico de la cuenta (Gmail, Zoho) sobre la esquina de la marca.
  final Widget? accountBadge;
  final String time;
  final String subject;
  final String? detail;
  final IconData? detailIcon;
  final String? status;
  final bool statusDone;
  final bool unread;

  /// Lo ya resuelto se lee más tenue.
  final bool dimmed;
  final bool selected;
  final bool compact;
  final bool hasAttachment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final markSize = compact ? 36.0 : 32.0;
    return Material(
      color: selected ? roles.neutral.container : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding:
              EdgeInsets.symmetric(horizontal: compact ? 16 : 20, vertical: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: roles.hairline)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: markSize + 4,
                height: markSize + 4,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    BrandMark(
                      name: markName,
                      logoUrl: markLogoUrl,
                      size: markSize,
                      solid: true,
                    ),
                    if (accountBadge != null)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: roles.hairline),
                          ),
                          child: accountBadge,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: compact ? 15 : 14,
                              fontWeight: unread || !dimmed
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: dimmed
                                  ? scheme.onSurfaceVariant
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                        if (unread) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                unread ? FontWeight.w600 : FontWeight.w400,
                            color: unread
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subject.isEmpty ? '(Sin asunto)' : subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 14 : 13.5,
                        fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                        color:
                            dimmed ? scheme.onSurfaceVariant : scheme.onSurface,
                      ),
                    ),
                    if ((detail ?? '').isNotEmpty ||
                        status != null ||
                        hasAttachment) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (detailIcon != null) ...[
                            Icon(detailIcon,
                                size: 14, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 5),
                          ],
                          Expanded(
                            child: Text(
                              detail ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.onSurfaceVariant),
                            ),
                          ),
                          if (hasAttachment) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.attach_file,
                                size: 14, color: scheme.onSurfaceVariant),
                          ],
                          if (status != null) ...[
                            const SizedBox(width: 10),
                            if (statusDone) ...[
                              Icon(Icons.check_rounded,
                                  size: 14, color: roles.success.accent),
                              const SizedBox(width: 3),
                            ],
                            Text(
                              status!,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: statusDone
                                    ? roles.success.accent
                                    : scheme.onSurface,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un control de la barra del correo: casilla, cuenta, carpeta o un filtro.
///
/// Relleno neutro, sin borde; elegido, en el tono de selección. Con
/// [dropdown] muestra la flecha de un menú.
class MailToolbarChip extends StatelessWidget {
  const MailToolbarChip({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.dropdown = false,
    this.selected = false,
    this.onTap,
    this.maxLabelWidth = 220,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final bool dropdown;
  final bool selected;
  final VoidCallback? onTap;
  final double maxLabelWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final foreground = selected ? roles.onSelectionContainer : scheme.onSurface;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, 6, dropdown ? 6 : 12, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              SizedBox(width: 17, height: 17, child: leading),
              const SizedBox(width: 7),
            ] else if (icon != null) ...[
              Icon(icon,
                  size: 17,
                  color: selected
                      ? roles.onSelectionContainer
                      : scheme.onSurfaceVariant),
              const SizedBox(width: 7),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxLabelWidth),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: foreground,
                ),
              ),
            ),
            if (dropdown) ...[
              const SizedBox(width: 2),
              Icon(Icons.expand_more, size: 18, color: scheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
    return Material(
      color: selected ? roles.selectionContainer : roles.neutral.container,
      borderRadius: BorderRadius.circular(8),
      child: onTap == null
          ? content
          : InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: content,
            ),
    );
  }
}

/// El buscador del correo, el mismo en las dos vistas.
class MailSearchField extends StatelessWidget {
  const MailSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    return SizedBox(
      height: 40,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: TextStyle(fontSize: 13.5, color: scheme.onSurface),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: roles.neutral.container,
            hintText: hint,
            hintStyle:
                TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            prefixIcon:
                Icon(Icons.search, size: 18, color: scheme.onSurfaceVariant),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 40, minHeight: 40),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar',
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      controller.clear();
                      onClear?.call();
                    },
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide(color: scheme.primary, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// El logo de la cuenta de un correo, para la esquina de su marca.
Widget? mailAccountLogo(String providerId) => switch (providerId) {
      'gmail' => Image.asset('assets/icons/gmail_logo.webp',
          fit: BoxFit.contain, cacheWidth: 48),
      'zoho' => Image.asset('assets/icons/zoho_logo.png',
          fit: BoxFit.contain, cacheWidth: 48),
      _ => null,
    };
