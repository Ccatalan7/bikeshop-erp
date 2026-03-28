import re

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'r', encoding='utf-8') as f:
    text = f.read()

pattern = r"  void _openWebsiteWorkspace\(\) \{.*?(?=  Widget \_buildInstructionsTab)|  void _openWebsiteWorkspace\(\) \{.*?(?=\n  Widget \w)"

match = re.search(pattern, text, flags=re.DOTALL)
if match:
    old_fn = match.group(0)
    
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
"""
    text = text.replace(old_fn, new_fn)
    with open('lib/modules/purchases/pages/supplier_form_page.dart', 'w', encoding='utf-8') as f:
        f.write(text)
    print("Replaced successfully")
else:
    print("Could not find method via regex")
