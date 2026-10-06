// How the customer portal completes the rows it reads (Flutter's
// `CustomerAccountService` and the HTML store's portal read the same tables
// and complete them here). Moved out of the Flutter service on 2026-10-06.
import 'online_order.dart';
import 'public_commerce_product_projection.dart';

/// Each bike with how many times it came to the workshop
/// (`service_count`) and when it last arrived (`last_service_date`), from the
/// customer's jobs (`bike_id`, `arrival_date`, `created_at`), and the names
/// of its brand and model rows (`brand_name`, `model_name`). Changes [bikes]
/// in place and returns it.
List<Map<String, dynamic>> completeCustomerBikes(
  List<Map<String, dynamic>> bikes,
  List<Object?> jobs,
) {
  final counts = <String, int>{};
  final lastArrival = <String, DateTime>{};
  for (final job in jobs) {
    if (job is! Map) continue;
    final bikeId = job['bike_id']?.toString();
    if (bikeId == null) continue;
    counts[bikeId] = (counts[bikeId] ?? 0) + 1;
    final arrived = DateTime.tryParse(
      (job['arrival_date'] ?? job['created_at'] ?? '').toString(),
    );
    if (arrived != null &&
        (lastArrival[bikeId] == null ||
            arrived.isAfter(lastArrival[bikeId]!))) {
      lastArrival[bikeId] = arrived;
    }
  }
  for (final bike in bikes) {
    final bikeId = bike['id']?.toString();
    bike['service_count'] = counts[bikeId] ?? 0;
    bike['last_service_date'] = lastArrival[bikeId]?.toIso8601String();
    if (bike['bike_brands'] case final Map brand) {
      bike['brand_name'] = brand['name'];
    }
    if (bike['bike_models'] case final Map model) {
      bike['model_name'] = model['name'];
    }
  }
  return bikes;
}

/// Each job with the brand, model, color, type and wheel of its bike, from
/// the bikes read apart (`id, brand, model, color, bike_type, wheel_size`:
/// a nested read could be cut by the bikes' row security). Changes [jobs] in
/// place and returns it.
List<Map<String, dynamic>> completeCustomerJobs(
  List<Map<String, dynamic>> jobs,
  List<Object?> bikes,
) {
  final byId = {
    for (final bike in bikes)
      if (bike is Map) bike['id'].toString(): bike,
  };
  for (final job in jobs) {
    final bike = byId[job['bike_id']?.toString()];
    if (bike == null) continue;
    job['bike_brand'] = bike['brand'] ?? '';
    job['bike_model'] = bike['model'] ?? '';
    job['bike_color'] = bike['color'];
    job['bike_type'] = bike['bike_type'];
    job['bike_wheel_size'] = bike['wheel_size'];
  }
  return jobs;
}

/// The bikes the jobs name, for [completeCustomerJobs].
Set<String> customerJobBikeIds(List<Map<String, dynamic>> jobs) => {
  for (final job in jobs)
    if (job['bike_id'] != null) job['bike_id'].toString(),
};

/// The orders read with their lines (`*, online_order_items (*)`).
List<OnlineOrder> customerOrdersFromRows(List<Object?> rows) => [
  for (final raw in rows)
    if (raw is Map)
      () {
        final json = Map<String, dynamic>.from(raw);
        final items = [
          for (final item in json['online_order_items'] as List? ?? const [])
            if (item is Map)
              OnlineOrderItem.fromJson(Map<String, dynamic>.from(item)),
        ];
        return OnlineOrder.fromJson(json).copyWith(items: items);
      }(),
];

/// The products the orders' lines name, for [customerOrderImages].
List<String> customerOrderProductIds(List<OnlineOrder> orders) => orders
    .expand((order) => order.items)
    .map((item) => item.productId?.trim() ?? '')
    .where((id) => id.isNotEmpty)
    .toSet()
    .toList(growable: false);

/// The columns [customerOrderImages] reads from `products`.
const customerOrderImageColumns =
    'id,website_image_url_optimized,website_image_url,'
    'image_url_optimized,image_url,website_image_urls,image_urls';

/// Each product's first photo, as the store shows it.
Map<String, String> customerOrderImages(List<Object?> rows) {
  final images = <String, String>{};
  for (final raw in rows) {
    if (raw is! Map) continue;
    final row = Map<String, dynamic>.from(raw);
    final id = row['id']?.toString() ?? '';
    final urls = PublicCommerceProductProjection.fromJson(row).imageUrls;
    if (id.isNotEmpty && urls.isNotEmpty) images[id] = urls.first;
  }
  return images;
}

/// An order's first line with a photo.
String? customerOrderImage(OnlineOrder order, Map<String, String> images) {
  for (final item in order.items) {
    final url = images[item.productId];
    if (url != null) return url;
  }
  return null;
}
