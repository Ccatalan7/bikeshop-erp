import 'package:intl/intl.dart';

import 'mail_work_models.dart';

/// Las palabras del correo que trabaja, en un solo lugar.
abstract final class MailWords {
  static final NumberFormat _number = NumberFormat.decimalPattern('es_CL');

  /// Pesos como se escriben en Chile: $45.990 (el formato de moneda de
  /// `es_CL` pone el signo al final).
  static String money(num value) => '\$${_number.format(value.round())}';

  // ---------------------------------------------------------------------------
  // Grupos de «Para hoy»
  // ---------------------------------------------------------------------------

  static const List<(String, String, Set<String>)> todayGroups = [
    ('pagos', 'Pagos', {'transfer'}),
    (
      'facturas',
      'Facturas',
      {'supplier_invoice', 'freight_invoice', 'service_invoice'}
    ),
    ('clientes', 'Clientes', {'customer', 'web_order'}),
    // Lo que espera respuesta y venció: lo mandado y los reclamos.
    ('seguimientos', 'Seguimientos', {'claim'}),
    ('envios', 'Envíos', {'shipment'}),
    ('banco', 'Banco', {'statement', 'bank'}),
    ('resenas', 'Reseñas', {'review'}),
    ('seguridad', 'Seguridad', {'security'}),
  ];

  static String todayGroupOf(MailItem item) {
    if (item.state.action == 'remind') return 'seguimientos';
    for (final (code, _, kinds) in todayGroups) {
      if (kinds.contains(item.kind)) return code;
    }
    return 'otros';
  }

  /// «Esperando» se ordena por cuánto lleva esperando: lo vencido primero.
  static const String overdueGroup = 'Vencidos';
  static const String waitingGroup = 'Esperando respuesta';

  /// Días enteros desde que empezó a esperar.
  static int waitingDays(MailItem item, [DateTime? now]) {
    final since = item.state.waitingSince;
    if (since == null) return 0;
    return (now ?? DateTime.now()).difference(since).inDays;
  }

  static String daysText(int days) => days == 1 ? '1 día' : '$days días';

  static String todayGroupTitle(String code) {
    for (final (groupCode, title, _) in todayGroups) {
      if (groupCode == code) return title;
    }
    return 'Otros';
  }

  /// Fuera de «Para hoy» el correo se ordena por día.
  static String dayGroup(DateTime date, DateTime now) {
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    if (diff < 7) return 'Esta semana';
    final month = DateFormat('MMMM', 'es').format(date);
    final label = '${month[0].toUpperCase()}${month.substring(1)}';
    return date.year == now.year ? label : '$label ${date.year}';
  }

  // ---------------------------------------------------------------------------
  // Hora corta de la fila
  // ---------------------------------------------------------------------------

  static String shortTime(DateTime date, DateTime now) {
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return DateFormat('HH:mm').format(date);
    if (diff == 1) return 'ayer';
    if (diff < 7) {
      return DateFormat('EEE', 'es').format(date).replaceAll('.', '');
    }
    if (date.year == now.year) {
      return DateFormat('d MMM', 'es').format(date).replaceAll('.', '');
    }
    return DateFormat('d/M/yy').format(date);
  }

  static String longTime(DateTime date) =>
      DateFormat("d 'de' MMMM, HH:mm", 'es').format(date);

  // ---------------------------------------------------------------------------
  // Estado en la fila y acción en el detalle
  // ---------------------------------------------------------------------------

  static String? rowStatus(MailItem item) {
    final state = item.state;
    if (!state.actionable) return null;
    if (state.done) return doneShort(item);
    return switch (state.action) {
      'register_purchase' => 'Por registrar',
      'register_expense' => 'Por registrar',
      'register_payment' => item.payer == null ? 'Elegir' : 'Por confirmar',
      'import_statement' => 'Por importar',
      'reply' => 'Por responder',
      'reply_review' => 'Agradecer',
      'follow_up' => 'En curso',
      'review' => 'Revisar',
      'remind' => state.overdue
          ? '${daysText(waitingDays(item))} sin respuesta'
          : 'Esperando',
      _ => null,
    };
  }

  /// La tercera línea de la fila: con qué registro calza y, si el correo
  /// trae plata o un folio, cuánto y cuál.
  static String rowDetail(MailItem item) {
    final link = item.primaryLink;
    if (item.direction == 'out') {
      final sent =
          'Enviado el ${DateFormat("d 'de' MMMM", 'es').format(item.receivedAt)}';
      final label = link?.label ?? '';
      return label.isNotEmpty && label != item.recipientTitle
          ? '$label · $sent'
          : sent;
    }
    final parts = <String>[
      if (link != null && (link.label ?? '').isNotEmpty) link.label!,
    ];
    final amount = item.amount;
    if (item.kind == 'transfer') {
      if (item.payer != null) parts.add(item.payer!);
      if (amount != null) parts.add(money(amount));
    } else if (item.facts['folio'] != null &&
        const {'supplier_invoice', 'freight_invoice', 'service_invoice'}
            .contains(item.kind)) {
      parts.add('Folio ${item.facts['folio']}');
      if (amount != null) parts.add(money(amount));
    } else if (link != null && (link.detail ?? '').isNotEmpty) {
      parts.add(link.detail!);
    }
    if (parts.isNotEmpty) return parts.join(' · ');
    // Sin nombre, la dirección ya es el título de la fila.
    return item.senderTitle == item.fromAddress ? '' : item.fromAddress;
  }

  /// El texto del correo para leerlo de una pasada: sin las direcciones
  /// largas de los enlaces que los correos en texto plano traen escritas.
  static String readable(String text) {
    var out = stripCss(decodeEntities(text));
    out = out.replaceAll(RegExp(r'<https?://[^>\s]+>'), '');
    out = out.replaceAll(RegExp(r'https?://\S{30,}'), '');
    // Lo que queda de una imagen o un enlace sin texto: una línea con sólo
    // «[» o «]».
    out = out.replaceAll(RegExp(r'^[ \t]*[\[\]]+[ \t]*$', multiLine: true), '');
    out = out.split('\n').map((line) => line.trimRight()).join('\n');
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return _reflow(out);
  }

  static final RegExp _cssRule = RegExp(r'[^{}\n]{0,160}\{([^{}]*)\}');
  static final RegExp _cssDeclarations =
      RegExp(r'^\s*(?:[-a-zA-Z]+\s*:[^;{}]*;?\s*)*$');

  /// Reglas de CSS que algunos remitentes dejan dentro de su texto plano
  /// («.header { margin-bottom: 20px; }», un `@media` entero). Sólo se quita
  /// un bloque entre llaves que no tiene más que declaraciones; se repite
  /// para vaciar primero las reglas de adentro de un `@media`.
  static String stripCss(String text) {
    if (!text.contains('{')) return text;
    var out = text;
    for (var pass = 0; pass < 4; pass++) {
      final next = out.replaceAllMapped(_cssRule, (match) {
        final inner = match.group(1)!;
        return _cssDeclarations.hasMatch(inner) ? '' : match.group(0)!;
      });
      if (next == out) break;
      out = next;
    }
    return out;
  }

  static final RegExp _listStart = RegExp(r'^\s*([-•*>]|\d+[.)])\s');

  /// El correo en texto plano llega cortado a mano cada ~70 letras; en un
  /// teléfono eso se lee en escalera. Dentro de un párrafo cuyas líneas
  /// tienen todas ese largo se unen; las listas, los datos («Nombre: …») y
  /// las firmas, de líneas cortas, quedan como vienen.
  static String _reflow(String text) {
    return text.split('\n\n').map((paragraph) {
      final lines = paragraph.split('\n');
      if (lines.length < 2) return paragraph;
      final wrapped = lines.take(lines.length - 1).every((line) {
        final trimmed = line.trim();
        return trimmed.length >= 40 && trimmed.length <= 100;
      });
      if (!wrapped || lines.any(_listStart.hasMatch)) return paragraph;
      return lines.map((line) => line.trim()).join(' ');
    }).join('\n\n');
  }

  static const Map<String, String> _entities = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'aacute': 'á',
    'eacute': 'é',
    'iacute': 'í',
    'oacute': 'ó',
    'uacute': 'ú',
    'Aacute': 'Á',
    'Eacute': 'É',
    'Iacute': 'Í',
    'Oacute': 'Ó',
    'Uacute': 'Ú',
    'ntilde': 'ñ',
    'Ntilde': 'Ñ',
    'uuml': 'ü',
    'Uuml': 'Ü',
    'iexcl': '¡',
    'iquest': '¿',
    'ordm': 'º',
    'ordf': 'ª',
    'deg': '°',
    'middot': '·',
    'bull': '•',
    'hellip': '…',
    'ndash': '–',
    'mdash': '—',
    'laquo': '«',
    'raquo': '»',
    'lsquo': '‘',
    'rsquo': '’',
    'ldquo': '“',
    'rdquo': '”',
    'euro': '€',
    'copy': '©',
    'reg': '®',
  };

  /// Entidades que quedaron escritas en el texto guardado, aunque vengan
  /// codificadas dos veces («p&amp;aacute;gina» → «página»). El servidor ya
  /// las decodifica en el correo nuevo; esto cubre el ya guardado.
  static String decodeEntities(String text) {
    if (!text.contains('&')) return text;
    final pattern = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);');
    var out = text;
    for (var pass = 0; pass < 3; pass++) {
      final next = out.replaceAllMapped(pattern, (match) {
        final code = match.group(1)!;
        if (code.startsWith('#')) {
          final hex = code.length > 1 && (code[1] == 'x' || code[1] == 'X');
          final value = hex
              ? int.tryParse(code.substring(2), radix: 16)
              : int.tryParse(code.substring(1));
          if (value == null || value <= 0 || value > 0x10FFFF) {
            return match.group(0)!;
          }
          return String.fromCharCode(value);
        }
        return _entities[code] ?? match.group(0)!;
      });
      if (next == out) break;
      out = next;
    }
    return out;
  }

  /// El número de operación que escribe el banco en el aviso («Número de
  /// operación: 635938240135», «N° de operación 1234567»), para la referencia
  /// del cobro.
  static String? operationNumber(String? text) {
    if (text == null || text.isEmpty) return null;
    final match = RegExp(
      r'(?:n[uú]mero|n[°º]|nro\.?)\s*(?:de\s+)?(?:la\s+)?operaci[oó]n\s*:?\s*([0-9][0-9-]{5,})',
      caseSensitive: false,
    ).firstMatch(text);
    return match?.group(1);
  }

  static final RegExp _receiptWords = RegExp(
    r'comprobante\s+de\s+(transferencia|pago|dep[oó]sito)'
    r'|transferencia\s+(realizada|exitosa|efectuada|de\s+fondos)'
    r'|aviso\s+de\s+transferencia|te\s+transfer[ií]',
    caseSensitive: false,
  );

  /// Un correo que habla de un pago hecho pero no viene de un banco (un
  /// comprobante reenviado, una captura, un aviso falso): no prueba que la
  /// plata llegó. La estafa común es pedir que se despache con un
  /// «comprobante»; el aviso del banco o la cartola lo confirman.
  static bool unverifiedPayment(MailItem item) =>
      item.direction == 'in' &&
      item.kind != 'transfer' &&
      item.partyType != 'bank' &&
      _receiptWords.hasMatch('${item.subject}\n${item.snippet ?? ''}');

  static const String unverifiedPaymentText =
      'Habla de un pago, pero no viene de un banco: un comprobante no prueba '
      'que la plata llegó. Antes de entregar o despachar, confírmalo en el '
      'aviso del banco o en la cartola.';

  static String doneShort(MailItem item) {
    final text = item.state.doneText ?? '';
    if (text.startsWith('Ya registrada en Compras')) return 'Registrada';
    if (text.startsWith('Ya está en Gastos')) return 'En Gastos';
    if (text.startsWith('Ya registrado')) return 'Pagado';
    if (text.startsWith('Ya pagado')) return 'Pagado';
    if (text.startsWith('Ya importada')) return 'Importada';
    if (text.startsWith('Ya respondido')) return 'Respondido';
    if (text.startsWith('Ya respondieron')) return 'Respondieron';
    return 'Hecho';
  }

  static String actionLabel(MailItem item) => switch (item.state.action) {
        'register_purchase' => 'Registrar compra',
        'register_expense' => 'Registrar gasto',
        'register_payment' => 'Registrar pago',
        'import_statement' => 'Importar cartola',
        'reply' => 'Responder',
        'reply_review' => 'Responder en Google',
        'follow_up' => 'Ver el caso',
        'remind' => 'Mandar recordatorio',
        'review' => 'Ya lo revisé',
        _ => 'Hecho',
      };

  /// Por qué el correo está en «Para hoy», en una frase.
  static (String, String?) why(MailItem item) {
    final state = item.state;
    if (item.direction == 'out') {
      return state.action == 'remind' ? waitingWhy(item) : ('', null);
    }
    final supplier = _linkLabel(item, 'supplier');
    final amount = item.amount;
    switch (item.kind) {
      case 'transfer':
        if (state.done) return ('${state.doneText}.', null);
        final payer = item.payer;
        if (payer == null) {
          return (
            'El aviso no dice quién transfirió.',
            amount == null
                ? 'Elige a qué cliente o pedido corresponde.'
                : 'Elige a qué cliente o pedido corresponden los ${money(amount)}.',
          );
        }
        return (
          'Nadie ha registrado un pago de $payer${amount == null ? '' : ' por ${money(amount)}'}.',
          'Se marca pagado sólo cuando calzan el monto y el nombre.',
        );
      case 'supplier_invoice':
        if (state.done) return ('${state.doneText}.', null);
        return (
          'Esta factura no está en Compras todavía.',
          supplier == null ? null : 'Es de $supplier.',
        );
      case 'freight_invoice':
      case 'service_invoice':
        if (state.done) return ('${state.doneText}.', null);
        return (
          'Esta factura no está en Gastos todavía.',
          supplier == null ? null : 'Es de $supplier.'
        );
      case 'statement':
        if (state.done) return ('${state.doneText}.', null);
        return (
          'No hay una cartola importada después de este correo.',
          'La conciliación del banco espera la cartola.'
        );
      case 'customer':
        if (state.done) return ('${state.doneText}.', null);
        return ('Nadie le ha respondido todavía.', null);
      case 'review':
        return (
          'Una reseña nueva en Google.',
          'Agradecerla ayuda a que el taller se vea atendido.'
        );
      case 'security':
        if (item.fakeBank) return (fakeBankText(item), fakeBankNote);
        return (
          'Un aviso de seguridad de una cuenta del taller.',
          'Si no fue alguien del equipo, cambia la contraseña de esa cuenta.'
        );
      case 'claim':
        if (state.done) return ('${state.doneText}.', null);
        final who = item.senderTitle;
        if (state.action == 'reply') {
          final day = DateFormat("d 'de' MMMM", 'es').format(item.receivedAt);
          return (
            '$who respondió el reclamo el $day.',
            'Si quedó resuelto, márcalo hecho; si no, respóndele.'
          );
        }
        return (
          'Un reclamo abierto con $who.',
          state.overdue
              ? 'Sin novedades hace ${daysText(waitingDays(item))}: el recordatorio está listo.'
              : 'Si en 5 días no hay novedades, vuelve a «Para hoy» con un recordatorio.'
        );
      case 'shipment':
        return ('Novedades de un envío.', null);
      case 'web_order':
        return ('Un correo sobre un pedido web.', null);
      default:
        return ('', null);
    }
  }

  /// Lo que mandamos y espera respuesta: por qué está aquí.
  static (String, String?) waitingWhy(MailItem item) {
    final state = item.state;
    if (state.done) return ('${state.doneText}.', null);
    final day = DateFormat("d 'de' MMMM", 'es').format(item.receivedAt);
    return (
      'Le escribiste a ${item.recipientTitle} el $day y no ha respondido.',
      state.overdue
          ? 'Pasaron ${daysText(waitingDays(item))}: el recordatorio está listo.'
          : 'Si en 3 días no responde, vuelve a «Para hoy» con un recordatorio.'
    );
  }

  /// El recordatorio, escrito para revisarlo y mandarlo: corto, con lo que
  /// identifica el caso (su número o el asunto) y la fecha.
  static String reminderText(MailItem item) {
    // Un reclamo se nombra por el día en que empezó, no por su último correo.
    var start = item.receivedAt;
    if (item.direction == 'in') {
      for (final entry in item.caseEntries) {
        if (entry.receivedAt.isBefore(start)) start = entry.receivedAt;
      }
    }
    final day = DateFormat("d 'de' MMMM", 'es').format(start);
    final subject = plainSubject(item.subject);
    final caseRef = '${item.facts['case_ref'] ?? ''}'.trim();
    final String body;
    if (item.direction == 'out') {
      body = subject.isEmpty
          ? 'Hola, ¿pudieron revisar mi correo del $day? Quedamos atentos.'
          : 'Hola, ¿pudieron revisar mi correo del $day sobre «$subject»? '
              'Quedamos atentos.';
    } else if (caseRef.isNotEmpty) {
      body = 'Hola, escribo por el caso $caseRef del $day. '
          '¿Tienen novedades?';
    } else {
      body = subject.isEmpty
          ? 'Hola, escribo por el reclamo del $day. ¿Tienen novedades?'
          : 'Hola, escribo por «$subject», del $day. ¿Tienen novedades?';
    }
    return '$body\n\nEquipo Viñabike';
  }

  /// El asunto sin los «Re:» y «RV:» de las respuestas.
  static String plainSubject(String subject) => subject
      .replaceFirst(
          RegExp(r'^\s*((re|rv|fw|fwd)\s*:\s*)+', caseSensitive: false), '')
      .replaceFirst(RegExp(r'[\s.;:,]+$'), '')
      .trim();

  static String fakeBankText(MailItem item) {
    final bank = item.bankName ?? 'un banco';
    return 'Dice ser de $bank, pero no viene de su dirección.';
  }

  static const String fakeBankNote =
      'No abras sus enlaces ni sus adjuntos. Si dudas, entra al banco por su '
      'app o su sitio, nunca desde el correo.';

  static String? _linkLabel(MailItem item, String type) {
    for (final link in item.links) {
      if (link.type == type && (link.label ?? '').isNotEmpty) return link.label;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Casillas
  // ---------------------------------------------------------------------------

  static const String allMailboxes = 'Todas las casillas';

  static String providerLabel(String provider) => switch (provider) {
        'gmail' => 'Gmail',
        'zoho' => 'Zoho',
        _ => provider,
      };

  /// Cómo va la lectura de una casilla, en pocas palabras.
  static String mailboxSync({
    required DateTime? lastSyncedAt,
    required bool hasError,
    DateTime? now,
  }) {
    if (hasError) return 'no se pudo leer';
    if (lastSyncedAt == null) return 'trayendo su correo…';
    final minutes = (now ?? DateTime.now()).difference(lastSyncedAt).inMinutes;
    if (minutes < 3) return 'al día';
    if (minutes < 60) return 'al día hace $minutes min';
    final hours = minutes ~/ 60;
    if (hours < 24) return 'leída hace $hours h';
    return 'leída el ${DateFormat("d 'de' MMMM", 'es').format(lastSyncedAt)}';
  }

  // ---------------------------------------------------------------------------
  // Registros ligados
  // ---------------------------------------------------------------------------

  static String linkTitle(MailLink link) => switch (link.type) {
        'job' => 'Trabajo',
        'customer' => 'Cliente',
        'supplier' => 'Proveedor',
        'purchase_invoice' => 'En Compras',
        'online_order' => 'Pedido web',
        'expense' => 'En Gastos',
        'sales_invoice' => 'Venta',
        _ => 'Registro',
      };

  static String openLabel(MailLink link) => switch (link.type) {
        'job' => 'Abrir trabajo',
        'customer' => 'Abrir cliente',
        'supplier' => 'Abrir proveedor',
        'purchase_invoice' => 'Abrir compra',
        'online_order' => 'Abrir pedido',
        'expense' => 'Abrir gasto',
        _ => 'Abrir',
      };

  static String? routeFor(MailLink link) => switch (link.type) {
        'job' => '/taller/pegas/${link.id}',
        'customer' => '/clientes/${link.id}',
        'supplier' => '/purchases/suppliers/${link.id}',
        'purchase_invoice' => '/purchases/${link.id}',
        'online_order' => '/website/orders?order=${link.id}',
        'expense' => '/accounting/expenses/${link.id}',
        _ => null,
      };

  // ---------------------------------------------------------------------------
  // Datos leídos del correo
  // ---------------------------------------------------------------------------

  static List<(String, String)> facts(MailItem item) {
    final facts = item.facts;
    final rows = <(String, String)>[];
    void add(String label, Object? value) {
      if (value == null) return;
      final text = value is List ? value.join(', ') : '$value';
      if (text.trim().isEmpty) return;
      rows.add((label, text.trim()));
    }

    final amount = item.amount;
    if (amount != null) add('Monto', money(amount));
    add('Quién paga', item.payer);
    add('Folio', facts['folio']);
    add('RUT', facts['rut']);
    add('Orden de flete', facts['freight_order']);
    add('Seguimiento', facts['tracking']);
    add('Trabajo', facts['job_numbers']);
    add('Pedido web', facts['web_orders']);
    add('Pedido', facts['order_refs']);
    add('Caso', facts['case_ref']);
    return rows;
  }

  // ---------------------------------------------------------------------------
  // Tipos (para corregir) y temas
  // ---------------------------------------------------------------------------

  static const Map<String, String> kindLabels = {
    'customer': 'Cliente',
    'web_order': 'Pedido web',
    'supplier_order': 'Pedido a proveedor',
    'claim': 'Reclamo',
    'supplier_invoice': 'Factura de proveedor',
    'freight_invoice': 'Factura de flete',
    'service_invoice': 'Factura de servicio',
    'transfer': 'Transferencia',
    'statement': 'Cartola',
    'bank': 'Banco',
    'shipment': 'Envío',
    'review': 'Reseña',
    'site': 'Google',
    'platform': 'Servicio',
    'security': 'Seguridad',
    'promo': 'Promoción',
    'noise': 'Ruido',
    'own': 'Nuestro',
    'other': 'Otro',
  };

  static const Map<String, String> spaceLabels = {
    'clientes': 'Clientes',
    'pedidos_web': 'Pedidos web',
    'proveedores': 'Proveedores',
    'facturas': 'Facturas',
    'banco': 'Banco',
    'envios': 'Envíos',
    'resenas': 'Reseñas',
    'google': 'Google',
    'servicios': 'Servicios',
    'seguridad': 'Seguridad',
    'promociones': 'Promociones',
    'ruido': 'Ruido',
    'otros': 'Otros',
  };

  static String fileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
