import re

with open('lib/shared/widgets/webview_module_page.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Fix the import to add Platform
if "import 'dart:io'" not in text:
    text = text.replace("import 'package:flutter/foundation.dart' show kIsWeb;", "import 'package:flutter/foundation.dart' show kIsWeb;\nimport 'dart:io' show Platform;")

# Fix initState
old_init = "if (!kIsWeb) {"
new_init = "if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {"
text = text.replace(old_init, new_init)

# Fix build
old_build = "if (kIsWeb) {"
new_build = "if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS)) {"
text = text.replace(old_build, new_build)

# Fix text messages
text = text.replace("'Los módulos WebView no están disponibles en la versión web de la aplicación.',", "'Los módulos WebView no están disponibles en esta plataforma.',")
text = text.replace("'Para usar esta función, ejecuta la aplicación en Windows, macOS, o descarga la app móvil.',", "'Para usar esta función, ejecuta la app en macOS, Android o iOS.',")

with open('lib/shared/widgets/webview_module_page.dart', 'w', encoding='utf-8') as f:
    f.write(text)
print("WebView fixed")
