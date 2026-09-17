import 'package:flutter/material.dart';

import '../../services/right_toolbar_service.dart';
import '../../utils/bike_finder_search.dart';

/// Qué clase de cosa es un resultado.
///
/// El orden del `enum` es el desempate estable entre dos resultados con el
/// mismo puntaje: primero lo que se **hace**, después lo que se **abre**,
/// después a dónde se **va**. Sin él, dos teclas seguidas reordenaban la lista
/// sin que nada hubiera cambiado.
enum GlobalSearchKind {
  action,
  customer,
  job,
  bike,
  product,
  conversation,
  attachment,
  salesInvoice,
  purchase,
  supplier,
  employee,
  menu,
}

extension GlobalSearchKindPresentation on GlobalSearchKind {
  /// Encabezado del grupo, en plural y en el idioma de la tienda.
  String get groupTitle => switch (this) {
        GlobalSearchKind.action => 'Hacer',
        GlobalSearchKind.customer => 'Clientes',
        GlobalSearchKind.job => 'Trabajos',
        GlobalSearchKind.bike => 'Bicicletas',
        GlobalSearchKind.product => 'Productos',
        GlobalSearchKind.conversation => 'Conversaciones',
        GlobalSearchKind.attachment => 'Archivos recibidos',
        GlobalSearchKind.salesInvoice => 'Facturas de venta',
        GlobalSearchKind.purchase => 'Documentos de compra',
        GlobalSearchKind.supplier => 'Proveedores',
        GlobalSearchKind.employee => 'Equipo',
        GlobalSearchKind.menu => 'Ir a',
      };

  IconData get icon => switch (this) {
        GlobalSearchKind.action => Icons.bolt_outlined,
        GlobalSearchKind.customer => Icons.person_outline,
        GlobalSearchKind.job => Icons.build_outlined,
        GlobalSearchKind.bike => Icons.pedal_bike_outlined,
        GlobalSearchKind.product => Icons.inventory_2_outlined,
        GlobalSearchKind.conversation => Icons.forum_outlined,
        GlobalSearchKind.attachment => Icons.attach_file_rounded,
        GlobalSearchKind.salesInvoice => Icons.receipt_long_outlined,
        GlobalSearchKind.purchase => Icons.shopping_cart_outlined,
        GlobalSearchKind.supplier => Icons.local_shipping_outlined,
        GlobalSearchKind.employee => Icons.badge_outlined,
        GlobalSearchKind.menu => Icons.north_east_rounded,
      };

  /// Ruta de la lista que contiene esta clase, para «Ver todos» con la misma
  /// consulta. `null` cuando el grupo no tiene una lista propia.
  String? get listRoute => switch (this) {
        GlobalSearchKind.customer => '/clientes',
        GlobalSearchKind.job => '/taller/pegas',
        GlobalSearchKind.bike => '/taller/bicicletas',
        GlobalSearchKind.product => '/inventory/products',
        GlobalSearchKind.conversation => '/chat',
        GlobalSearchKind.attachment => null,
        GlobalSearchKind.salesInvoice => '/sales/invoices',
        GlobalSearchKind.purchase => '/purchases',
        GlobalSearchKind.supplier => '/purchases/suppliers',
        GlobalSearchKind.employee => '/hr/employees',
        GlobalSearchKind.action => null,
        GlobalSearchKind.menu => null,
      };
}

/// Un archivo que llegó por una conversación, con lo justo para abrirlo.
///
/// El buscador no monta el módulo de mensajería para mostrarlo: pide una URL
/// firmada y abre el mismo visor que usa el chat. Ver una factura que mandó un
/// proveedor no debería costar entrar a WhatsApp, buscar la conversación y
/// bajar por el hilo.
@immutable
class GlobalSearchAttachment {
  const GlobalSearchAttachment({
    required this.storagePath,
    required this.fileName,
    required this.extension,
    required this.contentType,
    required this.origin,
  });

  final String storagePath;
  final String fileName;
  final String extension;
  final String contentType;

  /// De dónde salió, dicho como lo diría alguien: «TeknoBike · WhatsApp».
  final String origin;

  bool get isImage => const <String>{
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'heic',
      }.contains(extension.toLowerCase());
}

/// Una fila candidata del índice.
///
/// Trae **texto ya plegado**: el puntaje se calcula por cada tecla sobre miles
/// de filas, y normalizar ahí dentro era el costo dominante. [haystack] existe
/// sólo para el descarte barato; [fields] es lo que puntúa.
@immutable
class GlobalSearchEntry {
  GlobalSearchEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.route,
    this.subtitle,
    this.identifier,
    this.icon,
    this.updatedAt,
    this.toolbarTool,
    this.moduleWords = const <String>{},
    this.isModuleFrontDoor = false,
    this.attachment,
    this.conversationId,
    Set<String> alsoNamed = const <String>{},
    List<BikeFinderSearchField> fields = const <BikeFinderSearchField>[],
  })  : fields = fields.isEmpty
            ? <BikeFinderSearchField>[BikeFinderSearchField(title)]
            : fields,
        haystack = _buildHaystack(
          fields.isEmpty
              ? <BikeFinderSearchField>[BikeFinderSearchField(title)]
              : fields,
        ),
        normalizedIdentifier = identifier == null
            ? null
            : normalizeBikeFinderSearch(identifier)
                .replaceAll(RegExp(r'[^a-z0-9]'), ''),
        titleWords = <String>{
          for (final word in normalizeBikeFinderSearch(title)
              .split(RegExp(r'[^a-z0-9]+')))
            if (word.isNotEmpty) word,
          for (final alias in alsoNamed)
            for (final word in normalizeBikeFinderSearch(alias)
                .split(RegExp(r'[^a-z0-9]+')))
              if (word.isNotEmpty) word,
        };

  static String _buildHaystack(List<BikeFinderSearchField> fields) {
    final buffer = StringBuffer();
    for (final field in fields) {
      final value = field.value;
      if (value == null || value.isEmpty) continue;
      buffer
        ..write(normalizeBikeFinderSearch(value))
        ..write(' ');
    }
    return buffer.toString();
  }

  final GlobalSearchKind kind;

  /// Clave estable del destino. Es también la clave de uso: si cambia, el
  /// aprendizaje de este resultado se pierde, así que nunca lleva el nombre
  /// del registro, sólo su identidad.
  final String id;

  final String title;

  /// El contexto que distingue dos títulos iguales: el módulo para un menú,
  /// el dueño para una bicicleta, la fecha para un documento.
  final String? subtitle;

  /// `FV-01035`, un SKU, un RUT: lo que el operador puede haber tecleado
  /// completo y que, si calza exacto, gana sin discusión.
  final String? identifier;

  final String route;

  /// Herramienta del rail derecho que abre este resultado, cuando el destino no
  /// es una ruta sino un panel.
  ///
  /// Media docena de destinos del ERP —Tareas, Calculadora, Kiosko, el
  /// Asistente— no viven en el menú lateral sino en el rail, y un índice que
  /// sólo mira el menú contesta «no existe» sobre cosas que sí existen. Es el
  /// mismo defecto que buscar sólo en una tabla.
  final ToolbarTool? toolbarTool;

  final IconData? icon;
  final DateTime? updatedAt;

  final List<BikeFinderSearchField> fields;
  final String haystack;
  final String? normalizedIdentifier;

  /// Las palabras por las que esta fila **se llama**, plegadas. Escribir una
  /// entera es una señal distinta de que el texto la contenga en alguna parte:
  /// ver el bono de palabra exacta en el motor.
  ///
  /// Salen del título y de `alsoNamed`, porque **una cosa puede responder a más
  /// de un nombre**. El chat con TeknoBike se titula «TeknoBike» y en el taller
  /// se pide como «el de Diego»: los dos son su nombre, y ninguno es un
  /// sinónimo inventado — los dos están en el registro. Lo que no entra acá es
  /// el contexto (el dueño de una bicicleta no es el nombre de la bicicleta):
  /// eso pesa como campo, no como nombre.
  final Set<String> titleWords;

  /// Las palabras del **módulo** al que pertenece este destino, plegadas.
  ///
  /// El operador nombra el módulo tanto como la pantalla —«taller» por
  /// Trabajos, «ventas» por Facturas— y el módulo es contexto, no nombre: por
  /// sí solo pesa poco. Lo que sí decide es cuál de sus pantallas contesta,
  /// que es para lo que existe [isModuleFrontDoor].
  final Set<String> moduleWords;

  /// El archivo que abre este resultado, cuando el destino es un adjunto.
  final GlobalSearchAttachment? attachment;

  /// El hilo que abre este resultado, cuando el destino es una conversación.
  ///
  /// Va junto con [toolbarTool], que dice **en qué bandeja** — proveedores o
  /// clientes—. El hilo se abre en el panel del rail y no en el módulo porque
  /// ahí es donde se contesta: el módulo completo es para sentarse a revisar,
  /// el panel es para responderle a alguien sin soltar la pantalla en la que
  /// uno estaba, que es exactamente lo que interrumpe una búsqueda.
  final String? conversationId;

  /// Esta es la **primera** pantalla de su módulo, es decir su puerta de
  /// entrada.
  ///
  /// El orden lo publica el propio modelo de navegación, ordenado por el
  /// usuario: la primera de Taller es Trabajos, la de Ventas es Facturas de
  /// venta, la de Inventario es Productos. Nombrar el módulo y aterrizar en su
  /// puerta de entrada es lo que la gente espera, y no requiere que nadie
  /// escriba «taller significa trabajos» en ninguna parte.
  final bool isModuleFrontDoor;

  IconData get resolvedIcon => icon ?? kind.icon;
}
