import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class ImageServicePlatform {
  static Future<({Uint8List bytes, String name})?> pickImagePlatform() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true, // Important for web!
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
