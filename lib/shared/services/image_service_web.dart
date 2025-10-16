import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:convert';

class ImageServicePlatform {
  static Future<({Uint8List bytes, String name})?> pickImagePlatform() async {
    try {
      final html.FileUploadInputElement input = html.FileUploadInputElement()
        ..accept = 'image/*';
      input.click();

      await input.onChange.first;

      if (input.files == null || input.files!.isEmpty) {
        return null;
      }

      final html.File file = input.files!.first;
      final reader = html.FileReader();
      
      // Use readAsDataUrl instead of readAsArrayBuffer
      // This is more web-native and avoids ByteBuffer issues
      reader.readAsDataUrl(file);
      await reader.onLoad.first;

      final dataUrl = reader.result as String;
      
      // Remove the data:image/xxx;base64, prefix
      final base64Data = dataUrl.split(',')[1];
      final bytes = base64Decode(base64Data);
      
      return (bytes: bytes, name: file.name);
    } catch (e) {
      rethrow;
    }
  }
}
