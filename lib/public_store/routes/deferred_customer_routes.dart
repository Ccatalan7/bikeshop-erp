import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../pages/android_app_download_page.dart';
import '../pages/customer_addresses_page.dart';
import '../pages/customer_auth_page.dart';
import '../pages/customer_bikes_page.dart';
import '../pages/customer_chat_detail_page.dart';
import '../pages/customer_chat_hub_page.dart';
import '../pages/customer_chat_list_page.dart';
import '../pages/customer_dashboard_page.dart';
import '../pages/customer_orders_page.dart';
import '../pages/customer_profile_page.dart';
import '../pages/customer_service_history_page.dart';
import '../services/address_autocomplete_service.dart';

Widget buildCustomerRoutePage({
  required String routeKey,
  String? argument,
}) {
  return switch (routeKey) {
    'dashboard' => const CustomerDashboardPage(),
    'login' => const CustomerAuthPage(),
    'androidDownload' => const AndroidAppDownloadPage(),
    'profile' => const CustomerProfilePage(),
    'addresses' => ChangeNotifierProvider<AddressAutocompleteService>(
        create: (_) => AddressAutocompleteService(),
        child: const CustomerAddressesPage(),
      ),
    'orders' => const CustomerOrdersPage(),
    'bikes' => const CustomerBikesPage(),
    'serviceHistory' => CustomerServiceHistoryPage(bikeId: argument),
    'messages' => const CustomerChatListPage(),
    'messageDetail' => CustomerChatDetailPage(conversationId: argument ?? ''),
    'chats' => const CustomerChatHubPage(),
    'chatDetail' => CustomerChatHubPage(initialConversationId: argument),
    _ => const SizedBox.shrink(),
  };
}
