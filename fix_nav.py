import re

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'r', encoding='utf-8') as f:
    text = f.read()

old_fn = """  void _openWebsiteWorkspace() {
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

    showDialog(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.9,
          child: Scaffold(
            appBar: AppBar(
              title: Text(_nameController.text.isEmpty
                  ? 'Portal B2B'
                  : 'Portal: ${_nameController.text}'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            body: WebViewModulePage(
              url: validUrl,
              title: 'Portal B2B',
              icon: Icons.language,
            ),
          ),
        ),
      ),
    );
  }"""

new_fn = """  void _openWebsiteWorkspace() {
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

    // Abrimos el WebView en su propia página dentro del MainLayout en vez de un diálogo modal
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MainLayout(
          child: Scaffold(
            appBar: AppBar(
              title: Text(pageTitle),
              leading: BackButton(
                onPressed: () => Navigator.of(context).pop(),
              ),
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
  }"""

if old_fn in text:
    text = text.replace(old_fn, new_fn)
    with open('lib/modules/purchases/pages/supplier_form_page.dart', 'w', encoding='utf-8') as f:
        f.write(text)
    print("Replaced successfully")
else:
    print("Could not find the exact string. Checking alternative.")
