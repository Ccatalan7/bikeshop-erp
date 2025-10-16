# 🔴 CRITICAL BUG: Web Image Upload - _Namespace Error

**Status:** ❌ UNRESOLVED  
**Severity:** CRITICAL  
**Impact:** Image uploads completely broken on web release builds  
**Date Discovered:** October 15, 2025  
**Investigation Duration:** ~3 hours

---

## 📋 Summary

Product image uploads fail on web release builds with error: **"Unsupported operation: _Namespace"**

The error occurs ONLY on web platform in release mode. Debug mode and other platforms (Windows, Android) work perfectly.

---

## 🔍 Symptoms

### What Works ✅
- ✅ **Windows .exe** (release build) - Image upload works perfectly
- ✅ **Web debug mode** (`flutter run -d chrome`) - Image upload works perfectly
- ✅ **Web debug mode** (`flutter run -d chrome --debug`) - Image upload works perfectly

### What Fails ❌
- ❌ **Web release** (`flutter build web --release` + deployed) - FAILS
- ❌ **Web release** (localhost:8000 serving build/web) - FAILS
- ❌ **Web profile** (`flutter run -d chrome --profile`) - FAILS
- ❌ **Deployed site** (https://project-vinabike.web.app) - FAILS

### Error Details
- **Error Message:** `"Error guardando producto: Unsupported operation: _Namespace"`
- **When it appears:** After clicking "Guardar" (Save) button when a product image is selected
- **Visual symptom:** Image preview shows as grey block instead of actual image
- **Console logs:** No error appears in browser console, even with verbose logging
- **Logging behavior:** `print()` statements and `console.log()` calls are silent in release mode

---

## 🧪 Reproduction Steps

1. Build web release: `flutter build web --release`
2. Deploy to Firebase or serve locally: `python -m http.server 8000` in `build/web`
3. Navigate to Inventory → New Product
4. Click "Cambiar imagen principal" (Change main image)
5. Select an image file from file picker
6. **BUG 1:** Image preview shows grey block instead of actual image
7. Fill out product form
8. Click "Guardar" (Save)
9. **BUG 2:** Error popup: "Error guardando producto: Unsupported operation: _Namespace"

---

## 💡 Technical Analysis

### The `_Namespace` Error

`_Namespace` is an **internal Dart VM class** that should NEVER appear in user code. This error typically indicates:

1. **Reflection/Mirrors usage** - dart:mirrors is not supported on web
2. **Platform-specific code leaking** - dart:io or Platform checks in web build
3. **dart2js compilation issue** - Strict compiler catches code that DDC (debug) allows

### Compiler Differences

| Compiler | Mode | Behavior |
|----------|------|----------|
| **DDC** (DevCompiler) | Debug | Lenient, allows platform-specific code |
| **dart2js** | Release/Profile | Strict, fails on platform-specific code |

This explains why debug works but release fails - **dart2js is stricter** about platform isolation.

### Code Paths Investigated

The error occurs somewhere in this flow:
```
User clicks "Guardar" 
  → _saveProduct() 
    → ImageService.uploadBytes() 
      → Supabase.storage.uploadBinary() 
        → ??? _Namespace error ???
```

**Mystery:** The exact location of the error is unknown because:
- No stack trace appears
- Logging is suppressed in release mode
- The error message provides no context

---

## 🛠️ Attempted Fixes (All Failed)

### Attempt 1: Remove XFile/cross_file Package ❌
**Theory:** XFile might have platform-specific code  
**Action:** Removed `cross_file` package, used raw `Uint8List` in state  
**Result:** FAILED - Same error persists

### Attempt 2: Fix ByteBuffer → Uint8List Conversion ❌
**Theory:** `FileReader.result` returns `ByteBuffer`, not `Uint8List`  
**Action:** 
```dart
// Before (wrong):
final bytes = reader.result as Uint8List;

// After (correct):
final ByteBuffer buffer = reader.result as ByteBuffer;
final bytes = buffer.asUint8List();
```
**Result:** FAILED - Same error persists

### Attempt 3: Create Byte Copy Instead of View ❌
**Theory:** `asUint8List()` creates a view that might reference ByteBuffer  
**Action:** `final bytes = Uint8List.fromList(buffer.asUint8List());`  
**Result:** FAILED - Same error persists

### Attempt 4: Use readAsDataUrl + base64 Decode ❌
**Theory:** Avoid ByteBuffer entirely by using base64  
**Action:**
```dart
reader.readAsDataUrl(file);
await reader.onLoad.first;
final dataUrl = reader.result as String;
final base64Data = dataUrl.split(',')[1];
final bytes = base64Decode(base64Data);
```
**Result:** FAILED - Same error persists

### Attempt 5: Switch to file_picker Package ❌
**Theory:** Use proven package instead of custom dart:html code  
**Action:** Replaced custom `dart:html` implementation with `file_picker` package  
**Result:** FAILED - Same error persists  
**Note:** This works perfectly on Windows, fails only on web

### Attempt 6: Remove lookupMimeType ❌
**Theory:** `lookupMimeType(headerBytes: bytes)` might inspect bytes in platform-specific way  
**Action:** Hardcoded `contentType: 'image/jpeg'`  
**Result:** FAILED - Same error persists

### Attempt 7: Remove dart:js Logging ❌
**Theory:** `dart:js` interop might cause issues  
**Action:** Removed all `js.context.callMethod('console.log', ...)` calls  
**Result:** FAILED - Same error persists

### Attempt 8: Remove Try-Catch Blocks ❌
**Theory:** Exception handling might interfere with compilation  
**Action:** Simplified code to bare minimum without error handling  
**Result:** FAILED - Same error persists

---

## 📂 Affected Files

### Core Files
- `lib/shared/services/image_service.dart` - Main image service
- `lib/shared/services/image_service_web.dart` - Web-specific picker
- `lib/shared/services/image_service_mobile.dart` - Mobile/desktop picker
- `lib/modules/inventory/pages/product_form_page.dart` - Product form with image upload
- `lib/modules/crm/pages/customer_form_page.dart` - Customer form with image upload
- `lib/modules/inventory/pages/category_form_page.dart` - Category form with image upload

### Current Implementation

**image_service_web.dart:**
```dart
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class ImageServicePlatform {
  static Future<({Uint8List bytes, String name})?> pickImagePlatform() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.first;
    
    if (file.bytes != null) {
      return (bytes: file.bytes!, name: file.name);
    }

    return null;
  }
}
```

**image_service.dart (uploadBytes):**
```dart
static Future<String?> uploadBytes({
  required Uint8List bytes,
  required String fileName,
  required String bucket,
  required String folder,
}) async {
  try {
    final uniqueFileName = '${DateTime.now().millisecondsSinceEpoch}_${fileName.replaceAll(' ', '_')}';
    final normalizedFolder = _normalizePath(folder);
    final segments = <String>[];
    if (normalizedFolder.isNotEmpty) {
      segments.add(normalizedFolder);
    }
    segments.add(uniqueFileName);
    final objectPath = segments.join('/');

    final storageFile = _client.storage.from(bucket);

    final options = FileOptions(
      cacheControl: '3600',
      upsert: true,
      contentType: 'image/jpeg', // Hardcoded to avoid lookupMimeType
    );

    await storageFile.uploadBinary(objectPath, bytes, fileOptions: options);

    final publicUrl = storageFile.getPublicUrl(objectPath);
    return publicUrl;
  } catch (e, stackTrace) {
    ErrorReportingService.report('Image upload failed: $e', stackTrace);
    rethrow;
  }
}
```

---

## 🔬 Theories for Future Investigation

### Theory 1: Supabase Storage Issue
The error might be in `Supabase.storage.uploadBinary()` method when running on web. The Supabase client might:
- Use platform-specific code internally
- Have different behavior on web vs native
- Trigger dart:mirrors or reflection

**How to test:**
1. Create minimal reproduction with ONLY Supabase upload
2. Test with different file types (not just images)
3. Check Supabase Flutter SDK web implementation
4. Try alternative upload methods (REST API instead of SDK)

### Theory 2: Flutter's Image.memory Widget
The grey preview block suggests `Image.memory(_selectedImageBytes!)` might fail to decode the bytes. This could mean:
- The bytes are corrupted during the read process
- The bytes are the wrong format
- Image.memory has platform-specific decoding on web

**How to test:**
1. Log the first 50 bytes of the array in both debug and release
2. Compare the byte patterns
3. Try saving bytes to a Blob and displaying with Image.network
4. Use a different image decoding library

### Theory 3: State Management Issue
The bytes might be stored correctly but referenced incorrectly. In release mode, dart2js might optimize away certain object references, causing:
- The Uint8List to become invalid
- The memory to be garbage collected prematurely
- Type information to be lost

**How to test:**
1. Store bytes in a global variable instead of state
2. Try different state management approaches (Provider, Riverpod, etc.)
3. Check if the issue persists with simpler widgets

### Theory 4: Service Worker Caching
Flutter web generates a service worker that might:
- Cache the broken version of the code
- Interfere with file reading
- Cause stale code to run

**How to test:**
1. Completely disable service worker in index.html
2. Test in incognito mode
3. Add cache-busting query parameters
4. Check Application → Service Workers in DevTools

### Theory 5: Web Assembly (WASM)
The error might be related to WASM compilation:

**How to test:**
1. Try building with `--wasm` flag
2. Compare WASM vs JS output
3. Check for WASM-specific issues in Flutter GitHub

---

## 🎯 Recommended Next Steps

### Immediate (Workaround)
1. ✅ **Use Windows desktop app** for adding products with images
2. ✅ **Keep web version** for all other operations
3. ✅ Document this limitation for users

### Short-term (Investigation)
1. 🔍 Create **minimal reproduction** (separate Flutter project with ONLY image upload)
2. 🔍 Test with **different Supabase operations** (not just storage)
3. 🔍 File **bug report** with Flutter team if minimal reproduction works
4. 🔍 Check **Supabase Flutter SDK** GitHub issues for similar problems

### Long-term (Alternative Solutions)
1. 🔄 **Use REST API** instead of Supabase SDK for uploads
2. 🔄 **Implement server-side upload** (backend handles file upload)
3. 🔄 **Use different storage provider** (Firebase Storage, Cloudinary, etc.)
4. 🔄 **Wait for Flutter/Supabase updates** that might fix the issue

---

## 📊 Environment Details

### Flutter Environment
```
Flutter 3.35.6 • channel stable
Dart 3.9.2
```

### Key Dependencies
```yaml
dependencies:
  flutter: sdk: flutter
  supabase_flutter: ^2.6.0
  file_picker: ^8.3.7
  cached_network_image: ^3.3.1
  mime: ^2.0.0
```

### Deployment
- **Hosting:** Firebase Hosting
- **URL:** https://project-vinabike.web.app
- **Auto-deploy:** GitHub Actions (on push to main)
- **Manual deploy:** `flutter build web --release && firebase deploy --only hosting`

---

## 🚨 Impact Assessment

### Affected Features
- ❌ Product creation with images
- ❌ Product editing (changing images)
- ❌ Customer profile pictures
- ❌ Category images
- ❌ Company logo upload

### Workarounds Available
- ✅ Use Windows desktop application
- ✅ Upload images via database directly (admin access)
- ✅ Pre-populate images during migration

### Business Impact
- **Severity:** HIGH - Core feature is broken on primary platform (web)
- **User Impact:** MEDIUM - Workaround exists (desktop app)
- **Development Impact:** HIGH - Blocks web-first deployment strategy

---

## 📚 References

### Flutter Issues
- Search for `_Namespace` errors: https://github.com/flutter/flutter/issues
- Web compilation issues: https://github.com/flutter/flutter/labels/platform-web

### Dart Language
- dart2js vs DDC: https://dart.dev/tools/dart-compile
- Platform-specific code: https://dart.dev/guides/libraries/library-tour#dartio

### Supabase
- Storage documentation: https://supabase.com/docs/reference/dart/storage
- GitHub issues: https://github.com/supabase/supabase-flutter/issues

---

## 💭 Final Notes

This bug is particularly frustrating because:
1. **No clear error location** - The stack trace is missing
2. **Works in debug** - Making it hard to reproduce and debug
3. **Platform-specific** - Only affects web, works everywhere else
4. **No console output** - Logging is completely suppressed
5. **Exhaustive attempts** - Tried 8+ different approaches, all failed

The `_Namespace` error is a red herring that points to platform-specific code, but we've systematically eliminated all obvious sources. The actual bug is likely:
- Deep in Supabase SDK's web implementation
- In Flutter's Image.memory widget for web
- In dart2js compiler optimization
- In some other unexpected location

**This requires either:**
- A Flutter/Supabase expert with deep knowledge of web internals
- Access to a working similar implementation to compare
- Waiting for a framework update that might coincidentally fix it

---

**Last Updated:** October 15, 2025  
**Investigator:** GitHub Copilot  
**Status:** Unresolved - Investigation suspended, workaround implemented
