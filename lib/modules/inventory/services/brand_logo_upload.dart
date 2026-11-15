import 'package:file_picker/file_picker.dart';

import '../../../shared/services/image_service.dart';
import '../models/brand_models.dart';

/// Elige una imagen y la sube como logo de una marca del taller, en
/// `vinabike-assets/brands/<taller>/<marca>` (20261103120000). Devuelve la URL
/// pública, o `null` si la persona no eligió nada. Las del catálogo compartido
/// las cuida la plataforma: no llegan acá.
///
/// Es el mismo camino del formulario de la marca y de su página, para que el
/// logo se guarde igual desde las dos.
Future<String?> pickAndUploadBrandLogo(ProductBrand brand) async {
  final id = brand.id;
  if (id == null || brand.isShared) return null;
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
  );
  final file = picked?.files.singleOrNull;
  final bytes = file?.bytes;
  if (file == null || bytes == null || bytes.isEmpty) return null;
  final url = await ImageService.uploadBytes(
    bytes: bytes,
    fileName: file.name,
    bucket: 'vinabike-assets',
    folder: 'brands/${brand.tenantId}/$id',
  );
  if (url == null) throw StateError('La imagen no se pudo subir.');
  return url;
}
