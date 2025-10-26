# GrapesJS Platform Compatibility Fix

## Problem
The GrapesJS website editor uses web-only APIs (`dart:html`, `dart:ui_web`) that are not available on Windows, Android, or iOS platforms. This caused compilation errors when building for desktop or mobile.

## Solution: Conditional Exports
We implemented platform-specific code splitting using Dart's conditional exports:

### File Structure
```
lib/modules/website/pages/
├── grapesjs_editor_page.dart          (Export selector - 2 lines)
├── grapesjs_editor_page_web.dart      (Web implementation - full GrapesJS)
└── grapesjs_editor_page_stub.dart     (Non-web stub - "not available" message)

lib/public_store/pages/
├── static_html_home_page.dart         (Export selector - 2 lines)
├── static_html_home_page_web.dart     (Web implementation - HTML renderer)
└── static_html_home_page_stub.dart    (Non-web stub - "not available" message)
```

### How It Works

**Export Selector** (`grapesjs_editor_page.dart`):
```dart
// Conditional export: uses web implementation on web, stub on other platforms
export 'grapesjs_editor_page_web.dart' if (dart.library.io) 'grapesjs_editor_page_stub.dart';
```

**Web Implementation** (`grapesjs_editor_page_web.dart`):
- Full GrapesJS WYSIWYG editor
- Uses `dart:html` for IFrame embedding
- Uses `dart:ui_web` for platform view registration
- PostMessage API for Dart ↔ JavaScript communication
- Auto-save functionality

**Non-Web Stub** (`grapesjs_editor_page_stub.dart`):
- Simple Flutter widget showing "Editor only available on web"
- No web-specific dependencies
- Compiles on all platforms

## Platform Behavior

| Platform | Editor | Preview |
|----------|--------|---------|
| **Web** (Chrome) | ✅ Full GrapesJS WYSIWYG | ✅ Static HTML renderer |
| **Windows** | ⚠️ "Not available" message | ⚠️ "Not available" message |
| **Android** | ⚠️ "Not available" message | ⚠️ "Not available" message |
| **iOS** | ⚠️ "Not available" message | ⚠️ "Not available" message |

## User Experience

### On Web Platform
1. Open app in browser
2. Navigate to Website → Editor
3. Full GrapesJS editor loads
4. Drag-and-drop blocks, visual editing
5. Auto-save to database
6. Preview at `/tienda` shows exact output

### On Desktop/Mobile Platforms
1. Open app on Windows/Android/iOS
2. Navigate to Website → Editor
3. See friendly message: "Editor web no disponible"
4. Message explains to use web version for editing
5. Rest of ERP app works normally

## Import Rules

### ✅ Correct (Web-Only Files)
```dart
// grapesjs_editor_page_web.dart
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
```

### ❌ Incorrect (Export Files)
```dart
// grapesjs_editor_page.dart - WRONG!
import 'dart:async';  // ❌ NO IMPORTS IN EXPORT FILES
import 'package:flutter/material.dart';  // ❌ NO IMPORTS
```

### ✅ Correct (Export Files)
```dart
// grapesjs_editor_page.dart - CORRECT
export 'grapesjs_editor_page_web.dart' if (dart.library.io) 'grapesjs_editor_page_stub.dart';
// ONLY THE EXPORT STATEMENT, NOTHING ELSE
```

## Conditional Export Syntax

```dart
export 'file_web.dart' if (dart.library.io) 'file_stub.dart';
```

**Meaning:**
- If `dart.library.io` is available → use `file_stub.dart` (desktop/mobile)
- If `dart.library.io` is NOT available → use `file_web.dart` (web)

**Logic:**
- Web platform: NO file system (`dart:io`) → uses `_web.dart`
- Desktop/Mobile: HAS file system (`dart:io`) → uses `_stub.dart`

## Testing Checklist

### ✅ Web Platform
- [ ] `flutter run -d chrome`
- [ ] Navigate to Website module
- [ ] GrapesJS editor loads
- [ ] Drag product/service blocks
- [ ] Save HTML to database
- [ ] Preview at `/tienda` matches editor

### ✅ Windows Platform
- [ ] `flutter run -d windows`
- [ ] Navigate to Website module
- [ ] See "Editor web no disponible" message
- [ ] Rest of ERP works (Inventory, Sales, etc.)
- [ ] No compilation errors

### ✅ Android Platform
- [ ] `flutter run -d android`
- [ ] Navigate to Website module
- [ ] See "Editor web no disponible" message
- [ ] Rest of ERP works

## Files Modified

1. **lib/modules/website/pages/grapesjs_editor_page.dart**
   - Changed from full implementation to 2-line export
   - Removed all imports, classes, widgets
   - Only contains conditional export statement

2. **lib/modules/website/pages/grapesjs_editor_page_web.dart**
   - Created (renamed from original)
   - Full GrapesJS implementation
   - Web-only imports (`dart:html`, `dart:ui_web`)

3. **lib/modules/website/pages/grapesjs_editor_page_stub.dart**
   - Created (new file)
   - Simple "not available" widget
   - No web dependencies

4. **lib/public_store/pages/static_html_home_page.dart**
   - Changed to 2-line export
   - Removed all implementation code

5. **lib/public_store/pages/static_html_home_page_web.dart**
   - Created (renamed from original)
   - HTML renderer with IFrame
   - Web-only imports

6. **lib/public_store/pages/static_html_home_page_stub.dart**
   - Created (new file)
   - "Not available" message widget

## Compilation Errors Fixed

### Before
```
Error: Not found: 'dart:html'
Error: Not found: 'dart:ui_web'
Error: Undefined class 'Timer'
Error: Undefined name 'kIsWeb'
```

### After
```
✅ No errors on Windows build
✅ No errors on Web build
✅ All platforms compile successfully
```

## Future Considerations

### Option 1: Keep Current Approach ✅ RECOMMENDED
- Web editing only (best UX for WYSIWYG)
- Simple stub messages on desktop/mobile
- No platform-specific bugs
- Consistent behavior

### Option 2: Desktop Editor (Future)
- Use Webview on Windows/Android to embed GrapesJS
- Requires `webview_flutter` package
- More complex, possible rendering issues
- Not urgent for MVP

### Option 3: Native Editor (Future)
- Build custom drag-and-drop editor in Flutter
- Works on all platforms
- Massive development effort
- GrapesJS already does this better

## Best Practice

**When creating platform-specific features:**

1. ✅ Create `_web.dart` file with web implementation
2. ✅ Create `_stub.dart` file with fallback widget
3. ✅ Create main `.dart` file with ONLY export statement (2 lines)
4. ✅ Test compilation on both web and desktop
5. ✅ Document platform availability in UI

**Never:**
- ❌ Mix web imports (`dart:html`) in shared files
- ❌ Use `kIsWeb` guards everywhere (hard to maintain)
- ❌ Put implementation code in export selector files
- ❌ Assume all platforms support all features

## Related Documentation

- `GRAPESJS_MIGRATION_COMPLETE.md` - Full migration overview
- `GRAPESJS_ARCHITECTURE_DIAGRAM.md` - System architecture
- `GRAPESJS_TESTING_GUIDE.md` - Complete testing workflow
