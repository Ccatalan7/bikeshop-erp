import 'package:flutter/material.dart';

import '../../../shared/services/image_service.dart';
import '../services/website_background_removal_service.dart';
import '../services/website_media_service.dart';
import 'website_background_removal_dialog.dart';

enum WebsiteMediaPickerTab { library, upload, url }

/// Opens the canonical Website Builder image picker.
Future<WebsiteMediaAsset?> showWebsiteMediaPicker({
  required BuildContext context,
  String? currentUrl,
  WebsiteMediaService? mediaService,
}) {
  return showDialog<WebsiteMediaAsset>(
    context: context,
    barrierDismissible: false,
    builder: (_) => WebsiteMediaPickerDialog(
      currentUrl: currentUrl,
      mediaService: mediaService,
    ),
  );
}

class WebsiteMediaPickerDialog extends StatefulWidget {
  const WebsiteMediaPickerDialog({
    super.key,
    this.currentUrl,
    this.mediaService,
  });

  final String? currentUrl;
  final WebsiteMediaService? mediaService;

  @override
  State<WebsiteMediaPickerDialog> createState() =>
      _WebsiteMediaPickerDialogState();
}

class _WebsiteMediaPickerDialogState extends State<WebsiteMediaPickerDialog> {
  late final WebsiteMediaService _service;
  late Future<List<WebsiteMediaAsset>> _assetsFuture;
  final _searchController = TextEditingController();
  final _urlController = TextEditingController();
  WebsiteMediaPickerTab _tab = WebsiteMediaPickerTab.library;
  WebsiteMediaAsset? _selected;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.mediaService ?? WebsiteMediaService();
    _urlController.text = widget.currentUrl ?? '';
    _reloadLibrary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _reloadLibrary() {
    _assetsFuture = _service.listAssets(query: _searchController.text);
  }

  Future<void> _upload() async {
    if (_uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final picked = await ImageService.pickImage();
      if (picked == null) return;
      final asset = await _service.uploadImage(
        bytes: picked.bytes,
        fileName: picked.name,
      );
      if (!mounted) return;
      setState(() {
        _selected = asset;
        _tab = WebsiteMediaPickerTab.library;
        _reloadLibrary();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _cleanError(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _useAdvancedUrl() {
    final value = _urlController.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Ingresa una URL de imagen válida.');
      return;
    }
    Navigator.of(context).pop(
      WebsiteMediaAsset(name: 'Imagen externa', path: value, publicUrl: value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: screen.height * .86,
          minHeight: 560,
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildTabs(),
            if (_error != null) _buildError(),
            Expanded(child: _buildBody()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
      child: Row(
        children: [
          const Icon(Icons.perm_media_outlined, color: Color(0xFF00A09D)),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Seleccionar imagen',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('Reutiliza un asset o súbelo una sola vez.',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SegmentedButton<WebsiteMediaPickerTab>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: WebsiteMediaPickerTab.library,
              icon: Icon(Icons.photo_library_outlined),
              label: Text('Biblioteca'),
            ),
            ButtonSegment(
              value: WebsiteMediaPickerTab.upload,
              icon: Icon(Icons.upload_outlined),
              label: Text('Subir'),
            ),
            ButtonSegment(
              value: WebsiteMediaPickerTab.url,
              icon: Icon(Icons.link_outlined),
              label: Text('URL avanzada'),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (value) => setState(() {
            _tab = value.first;
            _error = null;
          }),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(_error!, style: const TextStyle(color: Colors.red)),
    );
  }

  Widget _buildBody() {
    switch (_tab) {
      case WebsiteMediaPickerTab.library:
        return _buildLibrary();
      case WebsiteMediaPickerTab.upload:
        return _buildUpload();
      case WebsiteMediaPickerTab.url:
        return _buildUrl();
    }
  }

  Widget _buildLibrary() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Buscar en la biblioteca',
              hintText: 'Nombre del archivo',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(_reloadLibrary),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<WebsiteMediaAsset>>(
              future: _assetsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final assets = snapshot.data ?? const <WebsiteMediaAsset>[];
                if (assets.isEmpty) {
                  return _EmptyLibrary(
                      onUpload: () => setState(
                            () => _tab = WebsiteMediaPickerTab.upload,
                          ));
                }
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: .95,
                  ),
                  itemCount: assets.length,
                  itemBuilder: (context, index) {
                    final asset = assets[index];
                    final selected = _selected?.publicUrl == asset.publicUrl;
                    return Semantics(
                      button: true,
                      selected: selected,
                      label: 'Seleccionar ${asset.name}',
                      child: InkWell(
                        key: ValueKey('website_media_${asset.path}'),
                        onTap: () => setState(() => _selected = asset),
                        onDoubleTap: () => Navigator.of(context).pop(asset),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF00A09D)
                                  : Colors.black12,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ColoredBox(
                                  color: const Color(0xFFF3F4F5),
                                  child: Image.network(
                                    asset.publicUrl,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.black38,
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  asset.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpload() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: InkWell(
            key: const ValueKey('website_media_upload'),
            onTap: _uploading ? null : _upload,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
              decoration: BoxDecoration(
                color: const Color(0xFF00A09D).withValues(alpha: .05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF00A09D).withValues(alpha: .4),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_uploading)
                    const CircularProgressIndicator()
                  else
                    const Icon(Icons.cloud_upload_outlined,
                        size: 48, color: Color(0xFF00A09D)),
                  const SizedBox(height: 16),
                  Text(
                    _uploading ? 'Subiendo…' : 'Elegir imagen',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'PNG, WebP, JPG o GIF. Los formatos transparentes se conservan.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUrl() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Usar una URL externa',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                'Opción de compatibilidad. Para que el asset quede administrable y reutilizable, usa Biblioteca o Subir.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'URL de imagen',
                  hintText: 'https://…',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _useAdvancedUrl(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final canApply = _tab == WebsiteMediaPickerTab.url || _selected != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          if (_selected != null)
            Expanded(
              child: Text(
                _selected!.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            )
          else
            const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: !canApply
                ? null
                : _tab == WebsiteMediaPickerTab.url
                    ? _useAdvancedUrl
                    : () => Navigator.of(context).pop(_selected),
            child: const Text('Usar imagen'),
          ),
        ],
      ),
    );
  }

  static String _cleanError(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}

class WebsiteImagePickerField extends StatefulWidget {
  const WebsiteImagePickerField({
    super.key,
    required this.onChanged,
    this.currentUrl,
    this.enableBackgroundRemoval = true,
  });

  final String? currentUrl;
  final ValueChanged<String> onChanged;
  final bool enableBackgroundRemoval;

  @override
  State<WebsiteImagePickerField> createState() =>
      _WebsiteImagePickerFieldState();
}

class _WebsiteImagePickerFieldState extends State<WebsiteImagePickerField> {
  bool _removingBackground = false;

  Future<void> _openPicker() async {
    final selection = await showWebsiteMediaPicker(
      context: context,
      currentUrl: widget.currentUrl,
    );
    if (selection != null) widget.onChanged(selection.publicUrl);
  }

  Future<void> _removeBackground() async {
    final url = widget.currentUrl?.trim() ?? '';
    if (url.isEmpty || _removingBackground) return;
    setState(() => _removingBackground = true);
    try {
      final selection = await showWebsiteBackgroundRemovalDialog(
        context: context,
        imageUrl: url,
      );
      if (!mounted || selection == null) return;
      final resultUrl = selection.imageUrl ??
          await WebsiteBackgroundRemovalService().uploadTransparentPng(
            selection.pngBytes!,
            prefix: 'block-no-bg',
          );
      if (!mounted) return;
      widget.onChanged(resultUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PNG sin fondo guardado en Biblioteca.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(error.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _removingBackground = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.currentUrl?.trim().isNotEmpty == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('website_image_picker_field'),
          onTap: _openPicker,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 140,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: hasImage
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        widget.currentUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: double.infinity,
                          color: Colors.black.withValues(alpha: .62),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: const Text(
                            'Cambiar desde Biblioteca',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined,
                          color: Color(0xFF00A09D), size: 30),
                      SizedBox(height: 8),
                      Text('Biblioteca o subir imagen',
                          style: TextStyle(
                              color: Color(0xFF00A09D), fontSize: 12)),
                    ],
                  ),
          ),
        ),
        if (hasImage) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: _openPicker,
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('Reemplazar'),
              ),
              if (widget.enableBackgroundRemoval)
                TextButton.icon(
                  onPressed: _removingBackground ? null : _removeBackground,
                  icon: Icon(
                    _removingBackground
                        ? Icons.hourglass_top
                        : Icons.auto_fix_high,
                    size: 16,
                  ),
                  label: const Text('Quitar fondo'),
                ),
              TextButton.icon(
                onPressed: () => widget.onChanged(''),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Quitar'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onUpload});

  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined,
              size: 42, color: Colors.black26),
          const SizedBox(height: 12),
          const Text('No hay imágenes que coincidan.'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onUpload,
            icon: const Icon(Icons.upload_outlined),
            label: const Text('Subir la primera'),
          ),
        ],
      ),
    );
  }
}
