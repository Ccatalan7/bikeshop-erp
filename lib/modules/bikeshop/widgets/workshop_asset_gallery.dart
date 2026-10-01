import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/widgets/workshop_asset_content.dart';
import '../../messaging/widgets/chat_attachment_viewer.dart';
import '../services/workshop_asset_service.dart';

/// Las mismas referencias sirven al ERP y al portal. La miniatura y cada
/// apertura resuelven su permiso actual; la URL temporal no entra en la fila.
class WorkshopAssetGallery extends StatefulWidget {
  const WorkshopAssetGallery({super.key, required this.references});

  final List<String> references;

  @override
  State<WorkshopAssetGallery> createState() => _WorkshopAssetGalleryState();
}

class _WorkshopAssetGalleryState extends State<WorkshopAssetGallery> {
  String? _opening;
  String? _error;

  Future<void> _open(String reference) async {
    if (_opening != null) return;
    setState(() {
      _opening = reference;
      _error = null;
    });
    try {
      final url = await WorkshopAssetService(Supabase.instance.client)
          .resolve(reference);
      if (!mounted || !widget.references.contains(reference)) return;
      final name =
          Uri.tryParse(reference)?.pathSegments.last ?? 'Archivo del trabajo';
      final extension = name.split('.').last.toLowerCase();
      await ChatAttachmentViewer.show(
        context,
        url: url,
        fileName: name,
        extension: extension,
        contentType: extension == 'pdf' ? 'application/pdf' : '',
        isImage: extension != 'pdf',
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = const WorkshopAssetUnavailable().toString());
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Archivos del trabajo',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var index = 0; index < widget.references.length; index++)
              Semantics(
                button: true,
                label: 'Abrir archivo ${index + 1} del trabajo',
                child: SizedBox.square(
                  dimension: 96,
                  child: Material(
                    clipBehavior: Clip.antiAlias,
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: _opening == null
                          ? () => _open(widget.references[index])
                          : null,
                      child: _opening == widget.references[index]
                          ? const Center(child: CircularProgressIndicator())
                          : WorkshopAssetContent(
                              reference: widget.references[index],
                              builder: (context, url) => Uri.tryParse(
                                              widget.references[index])
                                          ?.path
                                          .toLowerCase()
                                          .endsWith('.pdf') ==
                                      true
                                  ? const Center(
                                      child:
                                          Icon(Icons.picture_as_pdf_outlined))
                                  : Image.network(
                                      url,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Center(
                                              child: Icon(
                                                  Icons.broken_image_outlined)),
                                    ),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: colors.error)),
        ],
      ],
    );
  }
}
