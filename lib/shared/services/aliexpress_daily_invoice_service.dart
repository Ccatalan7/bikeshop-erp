class AliExpressDailyInvoiceService {
  const AliExpressDailyInvoiceService._();

  static const ordersUri = 'https://www.aliexpress.com/p/order/index.html';

  /// Dominios de AliExpress donde el ERP reconoce una sesión de compras.
  ///
  /// La lista es explícita a propósito: el extractor sólo debe correr en el
  /// sitio del proveedor, así que un patrón amplio como «contiene aliexpress»
  /// abriría la puerta a un dominio parecido. Se agregó `.us` porque la cuenta
  /// del taller navega el sitio estadounidense y allí la acción «Compras del
  /// día» simplemente no aparecía (2026-08-06).
  static const Set<String> _trustedRegistrableDomains = <String>{
    'aliexpress.com',
    'aliexpress.us',
    'aliexpress.ru',
    'aliexpress.es',
    'aliexpress.cl',
  };

  /// Exact allowlist shared with the embedded browser's document-start
  /// extractor. Returning an immutable copy prevents the security boundary
  /// from drifting through a second host list in a widget.
  static List<String> get trustedRegistrableDomains =>
      List<String>.unmodifiable(_trustedRegistrableDomains);

  static bool isTrustedUri(Uri? uri) {
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    for (final domain in _trustedRegistrableDomains) {
      if (host == domain || host.endsWith('.$domain')) return true;
    }
    return false;
  }

  static Uri? resolveOrderDetailUri(Map<String, dynamic> order) {
    final pageUrl = order['pageUrl']?.toString().trim() ?? '';
    final parsed = Uri.tryParse(pageUrl);
    final orderNumber = _digits(order['orderNumber']);
    if (isTrustedUri(parsed) &&
        !_isOrdersList(parsed!) &&
        _looksLikeOrderDetail(parsed) &&
        (orderNumber.isEmpty ||
            _orderNumberFromUri(parsed).isEmpty ||
            _orderNumberFromUri(parsed) == orderNumber)) {
      return parsed;
    }
    if (orderNumber.isEmpty) return null;
    return Uri.https(
      'www.aliexpress.com',
      '/p/order/detail.html',
      {'orderId': orderNumber},
    );
  }

  static Map<String, dynamic> mergeListAndDetailOrder(
    Map<String, dynamic> listOrder,
    Map<String, dynamic> detailOrder,
    Uri detailUri,
  ) {
    final list = _normalizeOrder(listOrder);
    final detail = _normalizeOrder(detailOrder);
    final listItems = _mapList(list['items']);
    final detailItems = _mapList(detail['items']);
    final listUsableItems = listItems.where(_isUsableProductItem).toList();
    final detailUsableItems = detailItems.where(_isUsableProductItem).toList();
    // Cuando el pedido viene de la API de AliExpress, sus líneas son la fuente
    // de verdad: traen producto, cantidad, precio unitario e imagen tal como
    // los tiene el proveedor. El detalle se lee de la página y puede perder
    // líneas —el 2026-04-06 dejó en 1 unidad un pedido de 2, y la diferencia
    // se absorbió como «ajuste», duplicando el costo unitario que habría
    // entrado al inventario— (2026-08-06). El detalle sigue aportando lo que
    // la lista no tiene: el desglose de subtotal, envío, impuesto y descuento.
    final listIsAuthoritative = _text(listOrder['via']) == 'api';
    final useDetailItems = !listIsAuthoritative &&
        detailUsableItems.isNotEmpty &&
        (detailUsableItems.length >= listUsableItems.length ||
            detailUsableItems
                .any((item) => _text(item['imageUrl']).isNotEmpty));
    final items = useDetailItems ? detailItems : listItems;
    final detailSubtotal = _nullableNumber(detail['subtotal']);
    final listSubtotal = _nullableNumber(list['subtotal']);
    final detailTotal = _nullableNumber(detail['total']);
    final listTotal = _nullableNumber(list['total']);
    final detailIsAuthoritative = detailOrder['__authoritativeTotals'] == true;

    dynamic pickComponent(String field) {
      final detailValue = _nullableNumber(detail[field]);
      if (detailValue != null) return detailValue;
      if (detailIsAuthoritative) return null;
      return _nullableNumber(list[field]);
    }

    final warnings = <dynamic>[
      ..._list(list['warnings']),
      ..._list(detail['warnings']),
    ];
    if (detailTotal != null && detailSubtotal != null) {
      final missing = <String>[
        for (final field in const ['shipping', 'tax', 'discount'])
          if (_nullableNumber(detail[field]) == null) field,
      ];
      if (missing.isNotEmpty) {
        warnings.add(
          'Detalle AliExpress incompleto: no se pudo leer '
          '${missing.join(', ')}.',
        );
      }
    }

    return <String, dynamic>{
      ...list,
      ...detail,
      'pageUrl': _firstText([
        detail['pageUrl'],
        detailUri.toString(),
        list['pageUrl'],
      ]),
      'pageTitle': _firstText([detail['pageTitle'], list['pageTitle']]),
      'orderNumber': _firstText([detail['orderNumber'], list['orderNumber']]),
      // La fecha de la API es la del pedido; la de la página puede ser otra
      // (pago, entrega) y arrastraba el pedido a un día que no era el suyo.
      'orderDate': listIsAuthoritative
          ? _firstText([list['orderDate'], detail['orderDate']])
          : _firstText([detail['orderDate'], list['orderDate']]),
      'supplierName': _firstText([
        detail['supplierName'],
        list['supplierName'],
        'AliExpress Marketplace',
      ]),
      'supplierTaxId':
          _firstText([detail['supplierTaxId'], list['supplierTaxId']]),
      'subtotal': detailSubtotal ?? listSubtotal ?? _sumItems(items),
      'shipping': pickComponent('shipping'),
      'tax': pickComponent('tax'),
      'discount': pickComponent('discount'),
      'total': detailTotal ?? listTotal ?? _sumItems(items),
      'notes': [
        _firstText([detail['notes'], list['notes']]),
        'Detalle enriquecido desde: $detailUri',
      ].where((value) => value.isNotEmpty).join('\n'),
      'items': items,
      'warnings': warnings,
    };
  }

  static Map<String, dynamic> buildDailyInvoice({
    required DateTime date,
    required List<Map<String, dynamic>> orders,
    String? sourcePageUrl,
  }) {
    if (orders.isEmpty) {
      throw ArgumentError.value(orders, 'orders', 'No puede estar vacío');
    }

    final normalizedOrders = _dedupeOrdersByNumber(
      orders.map(_normalizeOrder).toList(),
    );
    final dateText = _isoDate(date);
    final orderNumbers = normalizedOrders
        .map((order) => _text(order['orderNumber']))
        .where((number) => number.isNotEmpty)
        .toList();
    final rawItems = <Map<String, dynamic>>[];
    for (final order in normalizedOrders) {
      final orderNumber = _text(order['orderNumber']);
      for (final rawItem in _mapList(order['items'])) {
        rawItems.add(<String, dynamic>{
          ...rawItem,
          'description': _firstText(
              [rawItem['description'], rawItem['sku'], 'Línea AliExpress']),
          'sourceOrderNumber': orderNumber,
          'sourceOrderNumbers': [orderNumber],
          'sourceOrderDate': _text(order['orderDate']),
          'sourceOrderUrl': _text(order['pageUrl']),
        });
      }
    }
    final items = _aggregateDailyItems(rawItems);
    if (items.isEmpty) {
      throw StateError('AliExpress no entregó productos para ese día.');
    }

    final itemSubtotal = _roundMoney(
      items.fold<double>(0, (sum, item) => sum + _sourceItemTotal(item)),
    );
    final knownShipping = _sumKnown(normalizedOrders, 'shipping');
    final knownTax = _sumKnown(normalizedOrders, 'tax');
    final knownDiscount =
        _sumKnown(normalizedOrders, 'discount', absolute: true);
    final orderGrandTotal = _sumKnown(normalizedOrders, 'total');
    final finalTotal = orderGrandTotal > 0 ? orderGrandTotal : _sumItems(items);

    return <String, dynamic>{
      'source': 'AliExpress',
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'extractedAt': DateTime.now().toUtc().toIso8601String(),
      'pageUrl': sourcePageUrl ?? _text(normalizedOrders.first['pageUrl']),
      'pageTitle': 'AliExpress daily consolidated invoice',
      'supplierName': 'AliExpress Marketplace',
      'supplierTaxId': '',
      'orderNumber': _combinedOrderNumber(orderNumbers, dateText),
      'orderDate': dateText,
      'currency': 'CLP',
      'subtotal': itemSubtotal,
      'shipping': knownShipping == 0 ? null : knownShipping,
      'tax': knownTax == 0 ? null : knownTax,
      'discount': knownDiscount == 0 ? null : knownDiscount,
      'total': finalTotal,
      'componentDifference': _roundMoney(
        finalTotal -
            _roundMoney(
                itemSubtotal + knownShipping + knownTax - knownDiscount),
      ),
      'notes': [
        'Factura consolidada desde ${normalizedOrders.length} orden(es) AliExpress.',
        if (orderNumbers.isNotEmpty) 'Pedidos: ${orderNumbers.join(', ')}.',
        'Fecha exacta seleccionada: $dateText.',
        'Envío, impuestos y descuentos fueron prorrateados por producto dentro de cada pedido.',
      ].join('\n'),
      'items': items,
      'warnings': <dynamic>[
        for (final order in normalizedOrders) ..._list(order['warnings']),
        'Borrador consolidado: revisar parecidos y totales antes de guardar.',
      ],
      'sourceOrders': [
        for (final order in normalizedOrders)
          <String, dynamic>{
            'orderNumber': order['orderNumber'],
            'orderDate': order['orderDate'],
            'total': order['total'],
            'subtotal': order['subtotal'],
            'shipping': order['shipping'],
            'tax': order['tax'],
            'discount': order['discount'],
            'pageUrl': order['pageUrl'],
          },
      ],
      'bulkMath': <String, dynamic>{
        'itemSubtotal': itemSubtotal,
        'knownShipping': knownShipping,
        'knownTax': knownTax,
        'knownDiscount': knownDiscount,
        'orderGrandTotal': orderGrandTotal,
        'finalTotal': finalTotal,
        'allocatedRowTotal': _sumItems(items),
      },
    };
  }

  static Map<String, dynamic> _normalizeOrder(Map<String, dynamic> order) {
    final items = _dedupeOrderItems(
      _mapList(order['items']).map(_normalizeItem).toList(),
    );
    return _allocateInvoiceComponents(<String, dynamic>{
      ...order,
      'source': 'AliExpress',
      'supplierName':
          _firstText([order['supplierName'], 'AliExpress Marketplace']),
      'currency': 'CLP',
      'subtotal': _nullableNumber(order['subtotal']) ?? _sumItems(items),
      'total': _nullableNumber(order['total']) ?? _sumItems(items),
      'items': items,
      'warnings': _list(order['warnings']),
    });
  }

  static Map<String, dynamic> _normalizeItem(Map<String, dynamic> item) {
    final description = _firstText([
      item['description'],
      item['title'],
      item['sku'],
    ]);
    final sourcePurchaseQuantity = _number(
      item['sourcePurchaseQuantity'] ?? item['quantity'],
      fallback: 1,
    );
    final unitsPerPurchase = _number(
      item['unitsPerPurchase'],
      fallback: _inferUnitsPerPurchase(description),
    );
    final safePurchaseQuantity =
        sourcePurchaseQuantity <= 0 ? 1.0 : sourcePurchaseQuantity;
    final safeUnitsPerPurchase = unitsPerPurchase <= 0 ? 1.0 : unitsPerPurchase;
    final quantity = _roundQuantity(
      safePurchaseQuantity * safeUnitsPerPurchase,
    );
    final rawUnitPrice = _number(item['unitPrice']);
    final sourceTotal = _nullableNumber(item['sourceTotal']) ??
        _nullableNumber(item['total']) ??
        _roundMoney(safePurchaseQuantity * rawUnitPrice);
    final sourcePurchaseUnitPrice = _nullableNumber(
          item['sourcePurchaseUnitPrice'],
        ) ??
        _roundMoney(sourceTotal / safePurchaseQuantity);
    final sourceUnitPrice = _roundMoney(sourceTotal / quantity);
    return <String, dynamic>{
      ...item,
      'sku': _text(item['sku']),
      'description': description,
      'sourcePurchaseQuantity': safePurchaseQuantity,
      'unitsPerPurchase': safeUnitsPerPurchase,
      'inventoryUnit': safeUnitsPerPurchase > 1 ? 'par' : '',
      'quantity': quantity,
      'sourcePurchaseUnitPrice': sourcePurchaseUnitPrice,
      'sourceUnitPrice': sourceUnitPrice,
      'sourceTotal': sourceTotal,
      'unitPrice': sourceUnitPrice,
      'total': sourceTotal,
      'productUrl': _text(item['productUrl']),
      'itemId': _text(item['itemId']),
      'imageUrl': _text(item['imageUrl']),
    };
  }

  static Map<String, dynamic> _allocateInvoiceComponents(
    Map<String, dynamic> invoice,
  ) {
    final items = _mapList(invoice['items']).map(_normalizeItem).toList();
    if (items.isEmpty) return {...invoice, 'items': items};

    final sourceTotals = items.map(_sourceItemTotal).toList();
    final calculatedSubtotal = _roundMoney(
      sourceTotals.fold<double>(0, (sum, value) => sum + value),
    );
    final suppliedSubtotal = _nullableNumber(invoice['subtotal']);
    final subtotal = suppliedSubtotal ?? calculatedSubtotal;
    var shipping = _positive(invoice['shipping']);
    var tax = _positive(invoice['tax']);
    var discount = _positive(invoice['discount']);
    final statedTotal = _nullableNumber(invoice['total']);

    final finalTotal =
        statedTotal ?? _roundMoney(subtotal + shipping + tax - discount);
    final basis = sourceTotals.any((value) => value > 0)
        ? sourceTotals
        : List<double>.filled(items.length, 1);
    final shippingAllocations = _allocateByWeight(shipping, basis);
    final taxAllocations = _allocateByWeight(tax, basis);
    final discountAllocations = _allocateByWeight(discount, basis);
    final allocated = <Map<String, dynamic>>[];

    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final quantity = _number(item['quantity'], fallback: 1);
      final safeQuantity = quantity <= 0 ? 1 : quantity;
      final sourceTotal = sourceTotals[index];
      final sourceUnitPrice = _roundMoney(sourceTotal / safeQuantity);
      final allocatedShippingTotal = shippingAllocations[index];
      final allocatedTaxTotal = taxAllocations[index];
      final allocatedDiscountTotal = discountAllocations[index];
      final allocatedShipping =
          _roundMoney(allocatedShippingTotal / safeQuantity);
      final allocatedTax = _roundMoney(allocatedTaxTotal / safeQuantity);
      final allocatedDiscount =
          _roundMoney(allocatedDiscountTotal / safeQuantity);
      final unitPrice = _max(
        0,
        _roundMoney(
          sourceUnitPrice +
              allocatedShipping +
              allocatedTax -
              allocatedDiscount,
        ),
      );
      allocated.add(<String, dynamic>{
        ...item,
        'sourceUnitPrice': sourceUnitPrice,
        'sourceTotal': sourceTotal,
        'allocatedShipping': allocatedShipping,
        'allocatedTax': allocatedTax,
        'allocatedDiscount': allocatedDiscount,
        'allocatedShippingTotal': allocatedShippingTotal,
        'allocatedTaxTotal': allocatedTaxTotal,
        'allocatedDiscountTotal': allocatedDiscountTotal,
        'allocationGranularity': 'unit',
        'unitPrice': unitPrice,
        'total': _roundMoney(unitPrice * safeQuantity),
      });
    }

    final residual = _roundMoney(finalTotal - _sumItems(allocated));
    if (residual.abs() >= .01 && allocated.isNotEmpty) {
      final target = _largestIndex(sourceTotals);
      final quantity = _number(allocated[target]['quantity'], fallback: 1);
      final adjustedTotal = _roundMoney(
        _number(allocated[target]['total']) + residual,
      );
      allocated[target] = <String, dynamic>{
        ...allocated[target],
        'total': adjustedTotal,
        'unitPrice':
            _roundMoney(adjustedTotal / (quantity <= 0 ? 1 : quantity)),
        'allocatedAdjustmentTotal': residual,
        'allocatedAdjustment':
            _roundMoney(residual / (quantity <= 0 ? 1 : quantity)),
      };
    }

    return <String, dynamic>{
      ...invoice,
      'subtotal': subtotal,
      'shipping': shipping == 0 ? null : shipping,
      'tax': tax == 0 ? null : tax,
      'discount': discount == 0 ? null : discount,
      'total': finalTotal,
      'items': allocated,
      'allocation': <String, dynamic>{
        'method': 'weighted_by_product_total',
        'sourceSubtotal': subtotal,
        'shipping': shipping,
        'tax': tax,
        'discount': discount,
        'finalTotal': finalTotal,
        'componentDifference': _roundMoney(
          finalTotal - _roundMoney(subtotal + shipping + tax - discount),
        ),
      },
    };
  }

  static List<Map<String, dynamic>> _dedupeOrderItems(
    List<Map<String, dynamic>> items,
  ) {
    final result = <Map<String, dynamic>>[];
    for (final item in items) {
      final duplicateIndex = result.indexWhere(
        (existing) => _sameOrderItemObservation(existing, item),
      );
      if (duplicateIndex < 0) {
        result.add(item);
        continue;
      }
      final existing = result[duplicateIndex];
      result[duplicateIndex] = <String, dynamic>{
        ...existing,
        if (_text(existing['imageUrl']).isEmpty) 'imageUrl': item['imageUrl'],
        if (_text(existing['productUrl']).isEmpty)
          'productUrl': item['productUrl'],
        if (_text(existing['itemId']).isEmpty) 'itemId': item['itemId'],
      };
    }
    return result;
  }

  static bool _sameOrderItemObservation(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    if (_orderItemIdentity(first) == _orderItemIdentity(second)) return true;
    final firstId = _supplierProductId(first);
    final secondId = _supplierProductId(second);
    if (firstId.isNotEmpty && secondId.isNotEmpty && firstId != secondId) {
      return false;
    }
    final firstSku = _text(first['sku']);
    final secondSku = _text(second['sku']);
    if (firstSku.isNotEmpty && secondSku.isNotEmpty && firstSku != secondSku) {
      return false;
    }
    return _identityText(first['description']) ==
            _identityText(second['description']) &&
        _number(first['sourcePurchaseQuantity']) ==
            _number(second['sourcePurchaseQuantity']) &&
        _number(first['unitsPerPurchase']) ==
            _number(second['unitsPerPurchase']) &&
        _number(first['sourceTotal']) == _number(second['sourceTotal']);
  }

  static List<Map<String, dynamic>> _aggregateDailyItems(
    List<Map<String, dynamic>> items,
  ) {
    final result = <Map<String, dynamic>>[];
    for (final item in items) {
      final key = _dailyItemIdentity(item);
      final index = result.indexWhere(
        (existing) => _dailyItemIdentity(existing) == key,
      );
      if (index < 0) {
        result.add(Map<String, dynamic>.from(item));
        continue;
      }
      final existing = result[index];
      final quantity = _roundQuantity(
        _number(existing['quantity']) + _number(item['quantity']),
      );
      final purchaseQuantity = _roundQuantity(
        _number(existing['sourcePurchaseQuantity']) +
            _number(item['sourcePurchaseQuantity']),
      );
      final sourceTotal = _roundMoney(
        _number(existing['sourceTotal']) + _number(item['sourceTotal']),
      );
      final total = _roundMoney(
        _number(existing['total']) + _number(item['total']),
      );
      final shippingTotal = _roundMoney(
        _number(existing['allocatedShippingTotal']) +
            _number(item['allocatedShippingTotal']),
      );
      final taxTotal = _roundMoney(
        _number(existing['allocatedTaxTotal']) +
            _number(item['allocatedTaxTotal']),
      );
      final discountTotal = _roundMoney(
        _number(existing['allocatedDiscountTotal']) +
            _number(item['allocatedDiscountTotal']),
      );
      final adjustmentTotal = _roundMoney(
        _number(existing['allocatedAdjustmentTotal']) +
            _number(item['allocatedAdjustmentTotal']),
      );
      final orderNumbers = <String>{
        ..._list(existing['sourceOrderNumbers']).map(_text),
        ..._list(item['sourceOrderNumbers']).map(_text),
      }..removeWhere((value) => value.isEmpty);
      result[index] = <String, dynamic>{
        ...existing,
        'quantity': quantity,
        'sourcePurchaseQuantity': purchaseQuantity,
        'sourceTotal': sourceTotal,
        'sourceUnitPrice': _roundMoney(sourceTotal / quantity),
        'sourcePurchaseUnitPrice': _roundMoney(sourceTotal / purchaseQuantity),
        'allocatedShippingTotal': shippingTotal,
        'allocatedShipping': _roundMoney(shippingTotal / quantity),
        'allocatedTaxTotal': taxTotal,
        'allocatedTax': _roundMoney(taxTotal / quantity),
        'allocatedDiscountTotal': discountTotal,
        'allocatedDiscount': _roundMoney(discountTotal / quantity),
        'allocatedAdjustmentTotal': adjustmentTotal,
        'allocatedAdjustment': _roundMoney(adjustmentTotal / quantity),
        'unitPrice': _roundMoney(total / quantity),
        'total': total,
        'sourceOrderNumbers': orderNumbers.toList(),
        if (_text(existing['imageUrl']).isEmpty) 'imageUrl': item['imageUrl'],
      };
    }
    return result;
  }

  static List<Map<String, dynamic>> _dedupeOrdersByNumber(
    List<Map<String, dynamic>> orders,
  ) {
    final result = <Map<String, dynamic>>[];
    final indexByOrderNumber = <String, int>{};
    for (final order in orders) {
      final orderNumber = _text(order['orderNumber']);
      if (orderNumber.isEmpty) {
        result.add(order);
        continue;
      }
      final existingIndex = indexByOrderNumber[orderNumber];
      if (existingIndex == null) {
        indexByOrderNumber[orderNumber] = result.length;
        result.add(order);
        continue;
      }
      if (_orderQualityScore(order) >
          _orderQualityScore(result[existingIndex])) {
        result[existingIndex] = order;
      }
    }
    return result;
  }

  static int _orderQualityScore(Map<String, dynamic> order) {
    final items = _mapList(order['items']);
    final usableItems = items.where(_isUsableProductItem).length;
    final placeholders = items.where(_isPlaceholderItem).length;
    final images =
        items.where((item) => _text(item['imageUrl']).isNotEmpty).length;
    final detailUri = Uri.tryParse(_text(order['pageUrl']));
    final components = const ['shipping', 'tax', 'discount']
        .where((field) => _nullableNumber(order[field]) != null)
        .length;
    return (usableItems * 1000) -
        (placeholders * 1000) +
        (images * 25) +
        (_looksLikeOrderDetail(detailUri) ? 100 : 0) +
        (components * 10);
  }

  static bool _isUsableProductItem(Map<String, dynamic> item) {
    if (_isPlaceholderItem(item)) return false;
    final description = _firstText([item['description'], item['sku']]);
    if (description.isEmpty) return false;
    return _sourceItemTotal(item) > 0 ||
        _text(item['itemId']).isNotEmpty ||
        _text(item['imageUrl']).isNotEmpty;
  }

  static bool _isPlaceholderItem(Map<String, dynamic> item) {
    final description = _text(item['description']);
    final productUri = Uri.tryParse(_text(item['productUrl']));
    return RegExp(r'^AliExpress order\s+\d+$', caseSensitive: false)
            .hasMatch(description) ||
        (productUri != null &&
            productUri.path.toLowerCase().contains('/p/message/') &&
            _text(item['itemId']).isEmpty &&
            _text(item['imageUrl']).isEmpty);
  }

  static String _orderItemIdentity(Map<String, dynamic> item) => [
        _supplierItemIdentity(item),
        _identityText(item['description']),
        _number(item['sourcePurchaseQuantity']),
        _number(item['unitsPerPurchase']),
        _number(item['sourceTotal']),
      ].join('|');

  static String _dailyItemIdentity(Map<String, dynamic> item) => [
        _supplierItemIdentity(item),
        _identityText(item['description']),
        _number(item['unitsPerPurchase']),
      ].join('|');

  static String _supplierItemIdentity(Map<String, dynamic> item) {
    final productId = _supplierProductId(item);
    if (productId.isNotEmpty) return 'id:$productId';
    return 'sku:${_text(item['sku'])}';
  }

  static String _supplierProductId(Map<String, dynamic> item) {
    final itemId = _text(item['itemId']);
    if (itemId.isNotEmpty) return itemId;
    final url = _text(item['productUrl']);
    final urlId = RegExp(r'(?:/item/|itemId=|productId=)(\d{8,})')
        .firstMatch(url)
        ?.group(1);
    return urlId ?? '';
  }

  static String _identityText(dynamic value) => _text(value)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9áéíóúñ]+'), ' ')
      .trim();

  static double _inferUnitsPerPurchase(String description) {
    final matches = RegExp(
      r'\b(\d{1,2})\s*(?:pares?|pairs?)\b',
      caseSensitive: false,
    )
        .allMatches(description)
        .map((match) {
          return double.tryParse(match.group(1) ?? '') ?? 1;
        })
        .where((value) => value > 1 && value <= 50)
        .toSet();
    return matches.length == 1 ? matches.single : 1;
  }

  static double _roundQuantity(double value) =>
      (value * 10000).roundToDouble() / 10000;

  static List<double> _allocateByWeight(double amount, List<double> basis) {
    final total = amount.abs();
    if (total == 0 || basis.isEmpty) return List.filled(basis.length, 0);
    final basisSum =
        basis.fold<double>(0, (sum, value) => sum + _max(0, value));
    final allocations = <double>[
      for (final value in basis)
        _roundMoney(total *
            (basisSum > 0 ? _max(0, value) / basisSum : 1 / basis.length)),
    ];
    final residual = _roundMoney(
      total - allocations.fold<double>(0, (sum, value) => sum + value),
    );
    if (residual.abs() >= .01) {
      final target = _largestIndex(basis);
      allocations[target] = _roundMoney(allocations[target] + residual);
    }
    return allocations;
  }

  static double _sourceItemTotal(Map<String, dynamic> item) {
    final explicit = _nullableNumber(item['sourceTotal']);
    if (explicit != null) return explicit;
    final quantity = _number(item['quantity'], fallback: 1);
    final sourceUnit =
        _nullableNumber(item['sourceUnitPrice']) ?? _number(item['unitPrice']);
    final calculated = _roundMoney(sourceUnit * (quantity <= 0 ? 1 : quantity));
    return calculated != 0 ? calculated : _number(item['total']);
  }

  static double _sumItems(List<Map<String, dynamic>> items) => _roundMoney(
        items.fold<double>(0, (sum, item) => sum + _number(item['total'])),
      );

  static double _sumKnown(
    List<Map<String, dynamic>> orders,
    String field, {
    bool absolute = false,
  }) =>
      _roundMoney(orders.fold<double>(0, (sum, order) {
        final value = _nullableNumber(order[field]);
        return value == null ? sum : sum + (absolute ? value.abs() : value);
      }));

  static List<Map<String, dynamic>> _mapList(dynamic value) => [
        for (final item in _list(value))
          if (item is Map) Map<String, dynamic>.from(item),
      ];

  static List<dynamic> _list(dynamic value) =>
      value is List ? List<dynamic>.from(value) : const [];

  static String _combinedOrderNumber(List<String> numbers, String date) {
    if (numbers.isEmpty) return 'AE-BULK-$date';
    if (numbers.length == 1) return numbers.first;
    return 'AE-BULK-${_lastDigits(numbers.first, 6)}-'
        '${_lastDigits(numbers.last, 6)}-${numbers.length}';
  }

  static String _lastDigits(String value, int count) {
    final digits = _digits(value);
    return digits.length <= count
        ? digits
        : digits.substring(digits.length - count);
  }

  static bool _isOrdersList(Uri uri) =>
      uri.path.toLowerCase().contains('/p/order/index.html');

  static bool _looksLikeOrderDetail(Uri? uri) {
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    if (path.contains('/p/message/') || _isOrdersList(uri)) return false;
    return path.contains('order') && path.contains('detail');
  }

  static String _orderNumberFromUri(Uri uri) {
    for (final key in const [
      'orderId',
      'orderIdList',
      'orderNo',
      'orderNumber',
      'order_id',
      'order_no',
    ]) {
      final value = _digits(uri.queryParameters[key]);
      if (value.isNotEmpty) return value;
    }
    final match = RegExp(r'(\d{8,})').firstMatch(uri.path);
    return match?.group(1) ?? '';
  }

  static String _isoDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String _firstText(Iterable<dynamic> values) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';
  static String _digits(dynamic value) =>
      _text(value).replaceAll(RegExp(r'\D+'), '');

  static double _number(dynamic value, {double fallback = 0}) =>
      _nullableNumber(value) ?? fallback;

  static double? _nullableNumber(dynamic value) {
    if (value == null || value == '') return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim().replaceAll(',', '.'));
  }

  static double _positive(dynamic value) => (_nullableNumber(value) ?? 0).abs();
  static double _roundMoney(double value) => (value * 100).round() / 100;
  static double _max(double left, double right) => left > right ? left : right;

  static int _largestIndex(List<double> values) {
    var index = 0;
    for (var current = 1; current < values.length; current++) {
      if (values[current] > values[index]) index = current;
    }
    return index;
  }
}
