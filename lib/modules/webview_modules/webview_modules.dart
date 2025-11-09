import 'package:flutter/material.dart';
import '../../shared/widgets/webview_module_page.dart';
import '../../shared/widgets/main_layout.dart';

/// WhatsApp Web Module - Always accessible from sidebar
class WhatsAppWebModulePage extends StatelessWidget {
  const WhatsAppWebModulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainLayout(
      child: WebViewModulePage(
        url: 'https://web.whatsapp.com',
        title: 'WhatsApp Web',
        icon: Icons.message,
        iconColor: Color(0xFF25D366), // WhatsApp green
      ),
    );
  }
}

/// Google Sheets Module - For inventory management, reports, etc.
class GoogleSheetsModulePage extends StatelessWidget {
  final String? sheetUrl; // Optional specific sheet URL

  const GoogleSheetsModulePage({
    super.key,
    this.sheetUrl,
  });

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: WebViewModulePage(
        url: sheetUrl ?? 'https://docs.google.com/spreadsheets/',
        title: 'Google Sheets',
        icon: Icons.table_chart,
        iconColor: Colors.green,
      ),
    );
  }
}

/// Notion Module - For documentation, wikis, project management
class NotionModulePage extends StatelessWidget {
  final String? workspaceUrl;

  const NotionModulePage({
    super.key,
    this.workspaceUrl,
  });

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: WebViewModulePage(
        url: workspaceUrl ?? 'https://www.notion.so',
        title: 'Notion',
        icon: Icons.description,
        iconColor: Colors.black,
      ),
    );
  }
}

/// Analytics Dashboard Module - For Google Analytics, Mixpanel, etc.
class AnalyticsDashboardPage extends StatelessWidget {
  final String dashboardUrl;
  final String dashboardName;

  const AnalyticsDashboardPage({
    super.key,
    required this.dashboardUrl,
    this.dashboardName = 'Analytics',
  });

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: WebViewModulePage(
        url: dashboardUrl,
        title: dashboardName,
        icon: Icons.analytics,
        iconColor: Colors.orange,
      ),
    );
  }
}

/// Generic Web Tool Module - For any web tool
class GenericWebToolPage extends StatelessWidget {
  final String url;
  final String name;
  final IconData icon;
  final Color? iconColor;

  const GenericWebToolPage({
    super.key,
    required this.url,
    required this.name,
    this.icon = Icons.web,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: WebViewModulePage(
        url: url,
        title: name,
        icon: icon,
        iconColor: iconColor,
      ),
    );
  }
}
