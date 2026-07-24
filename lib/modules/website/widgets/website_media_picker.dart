import 'package:flutter/material.dart';

import '../../../shared/services/image_service.dart';
import '../services/website_background_removal_service.dart';
import '../services/website_media_service.dart';
import 'website_background_removal_dialog.dart';

enum WebsiteMediaPickerTab { library, products, upload, url }

/// Opens the canonical Website Builder image picker.
Future<WebsiteMediaAsset?> showWebsiteMediaPicker({
  required BuildContext context,
  String? currentUrl,
  WebsiteMediaService? mediaService,
  bool allowProductLink = false,
}) {
  return showDialog<WebsiteMediaAsset>(
    context: context,
    barrierDismissible: false,
    builder: (_) => WebsiteMediaPickerDialog(
      currentUrl: currentUrl,
      mediaService: mediaService,
      allowProductLink: allowProductLink,
    ),
  );
}

class WebsiteMediaPickerDialog extends StatefulWidget {
  const WebsiteMediaPickerDialog({
    super.key,
    this.currentUrl,
    this.mediaService,
    this.allowProductLink = false,
  });

  final String? currentUrl;
  final WebsiteMediaService? mediaService;
  final bool allowProductLink;

  @override
  State<WebsiteMediaPickerDialog> createState() =>
      _WebsiteMediaPickerDialogState();
}

class _WebsiteMediaPickerDialogState extends State<WebsiteMediaPickerDialog> {
  late final WebsiteMediaService _service;
  late Future<List<WebsiteMediaAsset>> _assetsFuture;
  late Future<List<WebsiteProductMediaItem>> _productsFuture;
  final _searchController = TextEditingController();
  final _productSearchController = TextEditingController();
  final _urlController = TextEditingController();
  WebsiteMediaPickerTab _tab = WebsiteMediaPickerTab.library;
  WebsiteMediaAsset? _selected;
  WebsiteProductMediaItem? _selectedProduct;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.mediaService ?? WebsiteMediaService();
    _urlController.text = widget.currentUrl ?? '';
    _reloadLibrary();
    _reloadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _productSearchController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _reloadLibrary() {
    _assetsFuture = _service.listAssets(query: _searchController.text);
  }

  void _reloadProducts() {
    _productsFuture = _service.listProductMedia();
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
    final maxDialogHeight = screen.height * .86;
    final minDialogHeight = maxDialogHeight < 560 ? maxDialogHeight : 560.0;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: maxDialogHeight,
          minHeight: minDialogHeight,
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
                Text('Reutiliza un asset, un producto o sube una imagen.',
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
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<WebsiteMediaPickerTab>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: WebsiteMediaPickerTab.library,
                icon: Icon(Icons.photo_library_outlined),
                label: Text('Biblioteca'),
              ),
              ButtonSegment(
                value: WebsiteMediaPickerTab.products,
                icon: Icon(Icons.inventory_2_outlined),
                label: Text('Productos'),
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
              _selected = null;
              _selectedProduct = null;
              _error = null;
            }),
          ),
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
      case WebsiteMediaPickerTab.products:
        return _buildProducts();
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
                                    asset.thumbnailUrl,
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

  void _selectProduct(WebsiteProductMediaItem product) {
    if (product.imageUrls.isEmpty) return;
    setState(() {
      _selectedProduct = product;
      _selected = product.assetFor(product.imageUrls.first);
    });
  }

  void _selectProductImage(
    WebsiteProductMediaItem product,
    String imageUrl,
  ) {
    setState(() {
      _selectedProduct = product;
      _selected = product.assetFor(imageUrl);
    });
  }

  Widget _buildProducts() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('website_product_media_search'),
            controller: _productSearchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Buscar productos',
              hintText: 'Nombre, SKU, marca o categoría',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (_selectedProduct != null &&
              _selectedProduct!.imageUrls.length > 1)
            _buildSelectedProductImages(_selectedProduct!),
          Expanded(
            child: FutureBuilder<List<WebsiteProductMediaItem>>(
              future: _productsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _PickerLoadError(
                    message: _cleanError(snapshot.error!),
                    onRetry: () => setState(_reloadProducts),
                  );
                }

                final query =
                    _productSearchController.text.trim().toLowerCase();
                final products =
                    (snapshot.data ?? const <WebsiteProductMediaItem>[])
                        .where(
                          (product) =>
                              query.isEmpty ||
                              product.searchableText.contains(query),
                        )
                        .toList(growable: false);
                if (products.isEmpty) {
                  return const _EmptyProducts();
                }

                return GridView.builder(
                  key: const ValueKey('website_product_media_grid'),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 210,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: .78,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) =>
                      _buildProductCard(products[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedProductImages(WebsiteProductMediaItem product) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF00A09D).withValues(alpha: .045),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF00A09D).withValues(alpha: .2),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Imágenes del producto',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${product.imageUrls.length} disponibles',
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: product.imageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final imageUrl = product.imageUrls[index];
                  final selected = _selected?.publicUrl == imageUrl;
                  return Semantics(
                    button: true,
                    selected: selected,
                    label: 'Imagen ${index + 1} de ${product.name}',
                    child: InkWell(
                      key: ValueKey(
                        'website_product_media_${product.id}_image_$index',
                      ),
                      onTap: () => _selectProductImage(product, imageUrl),
                      borderRadius: BorderRadius.circular(7),
                      child: Container(
                        width: 72,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F5),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF00A09D)
                                : Colors.black12,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.black38,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(WebsiteProductMediaItem product) {
    final hasImage = product.imageUrls.isNotEmpty;
    final selected = _selectedProduct?.id == product.id;
    return Semantics(
      button: hasImage,
      enabled: hasImage,
      selected: selected,
      label: hasImage
          ? 'Seleccionar imagen de ${product.name}'
          : '${product.name}, sin imagen',
      child: InkWell(
        key: ValueKey('website_product_media_${product.id}'),
        onTap: hasImage ? () => _selectProduct(product) : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: hasImage ? Colors.white : const Color(0xFFF6F6F6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFF00A09D) : Colors.black12,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: const Color(0xFFF3F4F5),
                      child: hasImage
                          ? Image.network(
                              product.imageUrls.first,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.black38,
                              ),
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image_not_supported_outlined,
                                    color: Colors.black26),
                                SizedBox(height: 5),
                                Text('Sin imagen',
                                    style: TextStyle(
                                        fontSize: 10, color: Colors.black45)),
                              ],
                            ),
                    ),
                    if (product.imageUrls.length > 1)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .66),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${product.imageUrls.length} imágenes',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1.18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.sku.isEmpty ? 'Sin SKU' : product.sku,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          product.availableStockQuantity > 0
                              ? Icons.inventory_2_outlined
                              : Icons.remove_shopping_cart_outlined,
                          size: 12,
                          color: product.availableStockQuantity > 0
                              ? Colors.green.shade700
                              : Colors.red.shade600,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Stock ${product.availableStockQuantity}',
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                        Icon(
                          product.isPublished
                              ? Icons.public_rounded
                              : Icons.public_off_outlined,
                          size: 12,
                          color: product.isPublished
                              ? const Color(0xFF00A09D)
                              : Colors.black38,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
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
                    'JPG, PNG o WebP. Transparencia y calidad visual se conservan.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.compress_rounded,
                          size: 15, color: Colors.black45),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'El editor ajusta el tamaño y publica WebP automáticamente.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54, fontSize: 11),
                        ),
                      ),
                    ],
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

  void _finishProductSelection({required bool linkProduct}) {
    final product = _selectedProduct;
    final imageUrl = _selected?.publicUrl;
    if (product == null || imageUrl == null || imageUrl.isEmpty) return;
    Navigator.of(context).pop(
      product.assetFor(imageUrl, linkProduct: linkProduct),
    );
  }

  Widget _buildFooter() {
    final canApply = _tab == WebsiteMediaPickerTab.url || _selected != null;
    final actions = <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      if (_tab == WebsiteMediaPickerTab.products &&
          widget.allowProductLink) ...[
        OutlinedButton(
          key: const ValueKey('website_product_media_use_only'),
          onPressed: !canApply
              ? null
              : () => _finishProductSelection(linkProduct: false),
          child: const Text('Usar sólo imagen'),
        ),
        FilledButton.icon(
          key: const ValueKey('website_product_media_link'),
          onPressed: !canApply
              ? null
              : () => _finishProductSelection(linkProduct: true),
          icon: const Icon(Icons.link_rounded, size: 17),
          label: const Text('Vincular producto'),
        ),
      ] else
        FilledButton(
          onPressed: !canApply
              ? null
              : _tab == WebsiteMediaPickerTab.url
                  ? _useAdvancedUrl
                  : _tab == WebsiteMediaPickerTab.products
                      ? () => _finishProductSelection(linkProduct: false)
                      : () => Navigator.of(context).pop(_selected),
          child: const Text('Usar imagen'),
        ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actionBar = Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: actions,
          );
          final selectedLabel = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_selected?.isWebOptimized == true) ...[
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 15,
                  color: Colors.black45,
                ),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  _selected == null
                      ? ''
                      : _selected!.isWebOptimized
                          ? '${_selected!.name} · Optimizada para web'
                          : _selected!.name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          );

          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_selected != null) ...[
                  selectedLabel,
                  const SizedBox(height: 8),
                ],
                Align(alignment: Alignment.centerRight, child: actionBar),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: selectedLabel),
              const SizedBox(width: 12),
              actionBar,
            ],
          );
        },
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
            originalUrl: url,
          );
      if (!mounted) return;
      widget.onChanged(resultUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Imagen sin fondo optimizada y guardada.'),
        ),
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
                            'Cambiar imagen',
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
                      Text('Biblioteca, productos o subir',
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

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 42, color: Colors.black26),
          SizedBox(height: 12),
          Text('No hay productos que coincidan.'),
          SizedBox(height: 5),
          Text(
            'Busca por nombre, SKU, marca o categoría.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _PickerLoadError extends StatelessWidget {
  const _PickerLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42, color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text(
              'No se pudieron cargar los productos',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
