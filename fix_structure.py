import re

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# 1. Update TabBar tabs
old_tabs = """              tabs: const [
                Tab(text: 'Instrucciones & Resumen'),
                Tab(text: 'Historial Facturas'),
                Tab(text: 'Editar Datos'),
              ],"""
new_tabs = """              tabs: const [
                Tab(text: 'Editar Datos'),
                Tab(text: 'Instrucciones & Resumen'),
                Tab(text: 'Historial Facturas'),
              ],"""
text = text.replace(old_tabs, new_tabs)

# 2. Update TabBarView children
old_views = """              children: [
                _buildInstructionsTab(),
                _buildHistoryTab(),
                _buildEditTab(),
              ],"""
new_views = """              children: [
                _buildEditTab(),
                _buildInstructionsTab(),
                _buildHistoryTab(),
              ],"""
text = text.replace(old_views, new_views)

# 3. Add import
if "import '../../../shared/widgets/webview_module_page.dart';" not in text:
    text = text.replace(
        "import '../../../shared/widgets/main_layout.dart';",
        "import '../../../shared/widgets/main_layout.dart';\nimport '../../../shared/widgets/webview_module_page.dart';"
    )

# 4. Add _openWebsiteWorkspace method
if "_openWebsiteWorkspace()" not in text:
    text = text.replace(
        "  void _closePage({bool saved = false}) {",
        """  void _openWebsiteWorkspace() {
    final url = _websiteController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Por favor ingrese un Sitio Web primero (ej: https://www.proveedor.com)')),
      );
      return;
    }

    final validUrl = url.startsWith('http') ? url : 'https://$url';
    final pageTitle = _nameController.text.isEmpty
        ? 'Portal B2B'
        : 'Portal: ${_nameController.text}';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MainLayout(
          child: Scaffold(
            appBar: AppBar(
              title: Text(pageTitle),
              leading: BackButton(
                onPressed: () => Navigator.of(context).pop(),
              ),
              elevation: 0,
            ),
            body: WebViewModulePage(
              url: validUrl,
              title: pageTitle,
              icon: Icons.language,
            ),
          ),
        ),
      ),
    );
  }

  void _closePage({bool saved = false}) {"""
    )

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'w', encoding='utf-8') as f:
    f.write(text)
print("Basic structure restored")
