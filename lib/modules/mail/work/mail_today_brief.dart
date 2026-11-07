import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import 'mail_navigation.dart';
import 'mail_today_badge.dart';
import 'mail_work_models.dart';
import 'mail_work_service.dart';
import 'mail_work_words.dart';

/// El resumen de la mañana en Inicio (etapa 4 de Correo que trabaja): lo que
/// entró y lo que hay que hacer, sin abrir el correo. Sale sólo si hay algo
/// que hacer; cada línea abre su grupo en «Para hoy». Una frase y una lista,
/// sin bloques de cifras.
class MailTodayBrief extends StatefulWidget {
  const MailTodayBrief({super.key, this.service});

  final MailWorkService? service;

  @override
  State<MailTodayBrief> createState() => _MailTodayBriefState();
}

class _MailTodayBriefState extends State<MailTodayBrief> {
  MailMorningSummary? _summary;
  int _lastBadge = -1;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // El número del menú se relee cada pocos minutos: si cambió, también
    // cambió el resumen.
    MailTodayBadge.instance.addListener(_onBadge);
  }

  @override
  void dispose() {
    MailTodayBadge.instance.removeListener(_onBadge);
    super.dispose();
  }

  void _onBadge() {
    final value = MailTodayBadge.instance.value;
    if (value == _lastBadge) return;
    _lastBadge = value;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final summary =
          await (widget.service ?? MailWorkService()).morningSummary();
      if (mounted) setState(() => _summary = summary);
    } catch (_) {
      // Sin acceso al correo (o sin red), Inicio sigue sin el resumen.
      if (mounted) setState(() => _summary = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary == null || !summary.hasSomething) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final lines = MailWords.morningLines(summary);
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: roles.hairline),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mail_outline_rounded,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Correo de hoy',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => openMailRoute(context, '/mail'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 40),
                    foregroundColor: scheme.onSurface,
                  ),
                  child: const Text('Abrir el correo'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 2, 8, 12),
              child: Text(
                MailWords.morningHeadline(summary),
                style: TextStyle(
                    fontSize: 14, height: 1.45, color: scheme.onSurfaceVariant),
              ),
            ),
            for (final (group, text) in lines)
              _BriefLine(
                text: text,
                icon: _iconFor(group),
                onTap: () => openMailRoute(context, '/mail?grupo=$group'),
              ),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String group) => switch (group) {
        'pagos' => Icons.payments_outlined,
        'facturas' => Icons.receipt_long_outlined,
        'clientes' => Icons.person_outline_rounded,
        'seguimientos' => Icons.schedule_rounded,
        'banco' => Icons.account_balance_outlined,
        'resenas' => Icons.star_outline_rounded,
        'seguridad' => Icons.gpp_maybe_outlined,
        _ => Icons.mail_outline_rounded,
      };
}

class _BriefLine extends StatelessWidget {
  const _BriefLine(
      {required this.text, required this.icon, required this.onTap});

  final String text;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: roles.hairline)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 14, color: scheme.onSurface),
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
