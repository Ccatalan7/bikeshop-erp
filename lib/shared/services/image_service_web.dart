import 'dart:typed_data';
import 'dart:html' as html;

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
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;

      final ByteBuffer buffer = reader.result as ByteBuffer;
      final bytes = buffer.asUint8List();
      
      return (bytes: bytes, name: file.name);
    } catch (e) {
      rethrow;
    }
  }
}
