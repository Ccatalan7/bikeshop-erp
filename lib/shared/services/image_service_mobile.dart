import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class ImageServicePlatform {
  static Future<({Uint8List bytes, String name})?> pickImagePlatform() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final file = result.files.first;

      if (file.bytes != null) {
        return (bytes: file.bytes!, name: file.name);
      } else if (file.path != null) {
        final fileObj = File(file.path!);
        final bytes = await fileObj.readAsBytes();
        return (bytes: bytes, name: file.name);
      }

      return null;
    } catch (e) {
      rethrow;
    }
  }
}
