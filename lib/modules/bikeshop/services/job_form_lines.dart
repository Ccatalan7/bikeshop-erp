import '../../../shared/models/product.dart';
import '../models/bikeshop_models.dart';
import 'service_wizard_service.dart';

/// Las líneas tal como las edita el formulario del trabajo, y el paso entre
/// ellas y lo que guarda `save_mechanic_job_lines_v1`: al cargar
/// ([JobPartItem.fromPersisted]) y al guardar ([jobLineFromPart],
/// [jobLineFromLabor]). Viven aquí, y no dentro del formulario, para que una
/// prueba recorra el mismo camino guardar → reabrir → guardar.

/// Una línea de repuesto, servicio o texto libre del formulario.
class JobPartItem {
  JobPartItem({
    String? id,
    this.product,
    required this.name,
    this.isCatalogProduct = true,
    this.isServiceItem = false,
    required this.quantity,
    required this.unitPrice,
    this.location = BikeMemoryLocation.none,
    this.notes,
    this.wizardAnswers,
    this.wizardProfile,
    this.quantityDraft,
    this.partChange,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  /// La línea como la guardó la base. La cantidad llega entera o con
  /// decimales (`numeric(10,2)`): horas de mano de obra, litros, metros. Se
  /// cargaba con `toInt()` y el guardado siguiente escribía 1 donde había 1,5
  /// (revisión del 2026-09-28).
  ///
  /// La marca del cambio de ficha de un repuesto (`part_change`) no es una
  /// respuesta de «Configurar»: se lee aparte, para que la línea siga
  /// teniendo su descripción editable.
  factory JobPartItem.fromPersisted(
    MechanicJobItem item, {
    Product? product,
    ServiceWizardProfile? wizardProfile,
  }) {
    final configuration = item.serviceConfigurationData == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(item.serviceConfigurationData!);
    final partChange = configuration.remove(kPartChangeConfigurationKey);
    return JobPartItem(
      id: item.id,
      product: product,
      name: item.productName,
      isCatalogProduct: product != null ||
          item.productId != null ||
          item.serviceProductId != null,
      isServiceItem: item.itemType == 'service' ||
          item.serviceProductId != null ||
          product?.isService == true,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      location: item.location,
      notes: item.notes,
      wizardAnswers: configuration.isEmpty ? null : configuration,
      wizardProfile: wizardProfile,
      // Una marca o, de una pieza con varios datos (una maza trasera), una
      // lista: tal como está, para que el guardado la compare.
      partChange: switch (partChange) {
        Map() => Map<String, dynamic>.from(partChange),
        List() => [
            for (final mark in partChange)
              mark is Map ? Map<String, dynamic>.from(mark) : mark,
          ],
        _ => null,
      },
    );
  }

  final String id; // Unique stable ID for widget keys
  Product? product; // Nullable for ad-hoc items
  String name; // For ad-hoc items
  bool isCatalogProduct;
  bool isServiceItem;
  double quantity;
  double unitPrice;
  BikeMemoryLocation location;
  String? notes;

  /// Answers captured from the service wizard (only for service products)
  Map<String, dynamic>? wizardAnswers;

  /// Cached wizard profile for re-editing without re-fetching from DB
  ServiceWizardProfile? wizardProfile;

  /// Lo que dice el campo de cantidad cuando todavía no es una cantidad
  /// (vacío mientras se reescribe). [quantity] conserva la última válida y el
  /// guardado se detiene: antes se guardaba 1 en silencio (revisión de Codex,
  /// 2026-09-28).
  String? quantityDraft;

  /// El cambio de ficha que el mecánico confirmó al elegir la rueda
  /// (`service_configuration_data.part_change`): una marca `{key, value}`, o
  /// una lista si la pieza cambia varios datos (una maza trasera, su driver y
  /// el anclaje del rotor; 20260928130000). Nace sólo de esa acción, nunca de
  /// un guardado: una línea antigua con rueda no cambia la ficha al volver a
  /// guardar su trabajo. Cambiar el repuesto la borra.
  Object? partChange;

  String get displayName => product?.name ?? name;
  String? get sku => product?.sku;
  bool get hasWizardAnswers =>
      wizardAnswers != null && wizardAnswers!.isNotEmpty;

  /// Cómo la cuentan los costos y la factura: servicio, producto del
  /// catálogo o texto libre.
  String get itemType {
    if (isServiceItem) return 'service';
    return isCatalogProduct ? 'product' : 'adhoc';
  }

  String? get serviceProductId => isServiceItem ? product?.id : null;

  /// La misma línea con el id que le dio la base al insertarla.
  JobPartItem withPersistedId(String persistedId) => JobPartItem(
        id: persistedId,
        product: product,
        name: name,
        isCatalogProduct: isCatalogProduct,
        isServiceItem: isServiceItem,
        quantity: quantity,
        unitPrice: unitPrice,
        location: location,
        notes: notes,
        wizardAnswers: wizardAnswers,
        wizardProfile: wizardProfile,
        quantityDraft: quantityDraft,
        partChange: partChange,
      );

  /// La línea con lo que se escribió en su campo de cantidad: la cantidad si
  /// se lee como tal, o el texto como borrador si no.
  JobPartItem withQuantityText(String text) {
    final parsed = parseJobLineQuantity(text);
    return parsed == null
        ? copyWith(quantityDraft: text)
        : copyWith(quantity: parsed, clearQuantityDraft: true);
  }

  /// Create a copy with the same ID (for preserving widget keys)
  JobPartItem copyWith({
    Product? product,
    String? name,
    bool? isCatalogProduct,
    bool? isServiceItem,
    double? quantity,
    double? unitPrice,
    BikeMemoryLocation? location,
    String? notes,
    Map<String, dynamic>? wizardAnswers,
    ServiceWizardProfile? wizardProfile,
    bool clearProduct = false,
    bool clearWizard = false,
    String? quantityDraft,
    bool clearQuantityDraft = false,
    Object? partChange,
    bool clearPartChange = false,
  }) {
    return JobPartItem(
      id: id, // Keep same ID!
      product: clearProduct ? null : (product ?? this.product),
      name: name ?? this.name,
      isCatalogProduct: isCatalogProduct ?? this.isCatalogProduct,
      isServiceItem: isServiceItem ?? this.isServiceItem,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      wizardAnswers: clearWizard ? null : (wizardAnswers ?? this.wizardAnswers),
      wizardProfile: clearWizard ? null : (wizardProfile ?? this.wizardProfile),
      quantityDraft:
          clearQuantityDraft ? null : (quantityDraft ?? this.quantityDraft),
      partChange: clearPartChange ? null : (partChange ?? this.partChange),
    );
  }
}

/// Dónde guarda una línea de repuesto el cambio de ficha que el mecánico vio
/// al elegir la rueda (20260928100000).
const String kPartChangeConfigurationKey = 'part_change';

/// Lo que la línea guarda en `service_configuration_data`: las respuestas de
/// «Configurar» de un servicio y, en un repuesto, la marca de su cambio de
/// ficha ([partChange]; nula, la línea no cambia la ficha).
Map<String, dynamic>? jobLineConfiguration({
  required Map<String, dynamic>? answers,
  required Object? partChange,
}) {
  final configuration = <String, dynamic>{
    ...?answers,
  }..remove(kPartChangeConfigurationKey);
  if (partChange != null) {
    configuration[kPartChangeConfigurationKey] = partChange;
  }
  return configuration.isEmpty ? null : configuration;
}

/// Lo que el comando escribe de una línea del formulario. [existing] es la
/// fila que se leyó al guardar (conserva lo que el formulario no edita);
/// [configuration], lo que respondió «Configurar».
MechanicJobItem jobLineFromPart(
  JobPartItem item, {
  required bool persisted,
  required String jobId,
  required String? jobBikeId,
  required String tenantId,
  MechanicJobItem? existing,
  Map<String, dynamic>? configuration,
}) {
  final quantity = item.quantity;
  return MechanicJobItem(
    id: persisted ? item.id : null,
    jobId: jobId,
    jobBikeId: jobBikeId,
    tenantId: tenantId,
    productId: item.isCatalogProduct
        ? (item.product?.id ?? existing?.productId)
        : null,
    serviceProductId: item.isServiceItem
        ? (item.serviceProductId ?? existing?.serviceProductId)
        : null,
    productName: item.name,
    productSku: item.sku ?? existing?.productSku ?? '',
    quantity: quantity,
    unitPrice: item.unitPrice,
    totalPrice: quantity * item.unitPrice,
    itemType: item.itemType,
    systemKey: existing?.systemKey,
    componentSlotKey: existing?.componentSlotKey,
    location: item.location,
    interventionType: existing?.interventionType,
    createsLifecycle: existing?.createsLifecycle ?? false,
    notes: item.notes,
    serviceConfigurationData: configuration,
  );
}

/// Una mano de obra (horas × tarifa) tal como la guarda el comando: siempre
/// `service`, con o sin su producto de servicio, como los servicios escritos
/// a mano. Así la cuentan igual los costos del trabajo (sólo `service` es
/// mano de obra) y la factura (sólo `product` es repuesto), y vuelve igual al
/// reabrirla como línea de General ([JobPartItem.fromPersisted]). Antes iba
/// sin tipo (`product`, repuesto); `adhoc` la habría contado como repuesto
/// en el trabajo y como mano de obra en la factura (revisión de Codex,
/// 2026-09-28).
MechanicJobItem jobLineFromLabor({
  required String? persistedId,
  required String jobId,
  required String tenantId,
  required Product? serviceProduct,
  required String name,
  required double hours,
  required double hourlyRate,
}) =>
    MechanicJobItem(
      id: persistedId,
      jobId: jobId,
      tenantId: tenantId,
      productId: serviceProduct?.id,
      serviceProductId: serviceProduct?.id,
      productName: name,
      productSku: serviceProduct?.sku ?? '',
      quantity: hours,
      unitPrice: hourlyRate,
      totalPrice: hours * hourlyRate,
      itemType: 'service',
      notes: 'Labor: ${hours.toStringAsFixed(1)}h @ '
          '\$${hourlyRate.toStringAsFixed(0)}/hr',
    );

/// La cantidad para mostrar y editar: entera sin decimales, con coma si los
/// tiene («1,5»).
String formatJobLineQuantity(double quantity) {
  if (quantity == quantity.roundToDouble()) {
    return quantity.toStringAsFixed(0);
  }
  var text = quantity.toStringAsFixed(2);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  return text.replaceAll('.', ',');
}

/// Lo que escribió el mecánico, con coma o punto y hasta dos decimales (lo
/// que guarda la base). Null si no es una cantidad.
double? parseJobLineQuantity(String text) {
  final normalized = text.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(normalized)) return null;
  return double.parse(normalized);
}

/// Pasa una línea de una pestaña a otra —de General a una bici, de una bici
/// a otra, o a General—: la misma línea —mismo id, producto, cantidad,
/// precio, descripción y respuestas de «Configurar»—, sin duplicarla; sólo
/// cambia de dueño, y al guardar el comando la actualiza en su lugar con la
/// versión que vio el formulario. Lo que confirmó para la ficha
/// (`part_change`) se suelta: se vio sin bici o con otra, y se vuelve a
/// confirmar en la suya. En General de un trabajo con varias bicis una línea
/// no es de ninguna (`line_without_bike`); ésta es la forma de resolverlo sin
/// quitarla y agregarla de nuevo (2026-09-28), de corregir la bici
/// equivocada y de dejar aparte lo que el cliente compró sin ser de la bici
/// (2026-10-01). Devuelve la línea pasada, o nula si no estaba en [general].
JobPartItem? assignJobLineToBike({
  required List<JobPartItem> general,
  required List<JobPartItem> bikeLines,
  required String itemId,
}) {
  final index = general.indexWhere((item) => item.id == itemId);
  if (index < 0) return null;
  final moved = general.removeAt(index).copyWith(clearPartChange: true);
  bikeLines
    ..removeWhere((item) => item.id == itemId)
    ..add(moved);
  return moved;
}
