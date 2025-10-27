import 'package:flutter/material.dart';

// Only import web version when on web platform
import 'website_editor_page_web.dart' if (dart.library.io) 'website_editor_page_stub.dart';

/// Website Editor - Ultra-minimal GrapesJS integration
/// 
/// Simple flow:
/// 1. Open editor
/// 2. Edit your site
/// 3. Click Save
/// 4. Click Preview to see result
/// 5. Go back and forth - that's it!
class WebsiteEditorPage extends StatelessWidget {
  const WebsiteEditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    // The conditional import above handles platform detection
    return const WebsiteEditorPageWeb();
  }
}
