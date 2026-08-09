import 'package:flutter/material.dart';

import '../../../shared/services/image_service.dart';
import '../models/website_editor_capability.dart';
import '../providers/website_edit_mode_provider.dart';
import '../services/website_background_removal_service.dart';
import '../services/website_media_service.dart';
import '../services/website_service.dart';
import 'website_background_removal_dialog.dart';

/// Opaque, typed authority captured before an asynchronous Website field
/// yields control.
///
/// The concrete authority remains owned by its canonical provider. This
/// interface deliberately carries no generation or mutable state of its own;
/// it only lets a field hand the provider-issued arm to the binding that is
/// live when the asynchronous surface returns.
abstract interface class WebsiteAsyncFieldArm {}

/// Opaque owner of one focused/continuous edit (typing, IME composition).
abstract interface class WebsiteContinuousFieldArm {}

typedef WebsiteAsyncFieldOperation = WebsiteInlineMutationResult Function();
typedef WebsiteAsyncFieldArmCapture = WebsiteAsyncFieldArm? Function();
typedef WebsiteAsyncFieldArmCommit = WebsiteInlineMutationResult Function(
  WebsiteAsyncFieldArm arm,
  WebsiteAsyncFieldOperation operation,
);
typedef WebsiteAsyncRemoteAuthority = WebsiteEditorRemoteWriteAuthority?
    Function(
  WebsiteAsyncFieldArm arm,
  String operation,
  bool Function() isLiveBinding,
);
typedef WebsiteContinuousFieldBegin = WebsiteContinuousFieldArm? Function(
  Object? baselineValue,
);
typedef WebsiteContinuousFieldUpdate = WebsiteInlineMutationResult Function(
  WebsiteContinuousFieldArm arm,
  Object? nextValue,
  WebsiteAsyncFieldOperation operation,
);
typedef WebsiteContinuousFieldClose = WebsiteInlineMutationResult Function(
  WebsiteContinuousFieldArm arm,
);

/// Exact semantic identity of a field inside one page block.
///
/// [scopeKey] names the canonical field/node (for example
/// `root.backgroundImage` or `slides[id=hero].action`). It prevents a State
/// retained with the same Flutter key from handing A's result to a different
/// live field B inside the same unchanged block.
@immutable
class WebsiteAsyncFieldTarget {
  const WebsiteAsyncFieldTarget.block({
    required this.blockId,
    required this.scopeKey,
  });

  final String blockId;
  final String scopeKey;

  @override
  bool operator ==(Object other) =>
      other is WebsiteAsyncFieldTarget &&
      other.blockId == blockId &&
      other.scopeKey == scopeKey;

  @override
  int get hashCode => Object.hash(blockId, scopeKey);
}

/// Stateless arm -> live-commit transport shared by asynchronous Website
/// fields.
///
/// A widget captures from the binding rendered before its `await`, but commits
/// through `widget.asyncBinding` after it. Consequently callback A is never
/// invoked after replacement, and callback B only runs after accepting A's
/// canonical provider token. Other canonical owners (sitewide settings, for
/// example) can supply the same typed interface around their own provider
/// token without adding a second field-local FSM.
@immutable
class WebsiteAsyncFieldBinding {
  const WebsiteAsyncFieldBinding({
    required this.identity,
    required this.capture,
    required this.commit,
    this.ownerRevision,
    this.beginContinuous,
    this.updateContinuous,
    this.finishContinuous,
    this.cancelContinuous,
    this.remoteAuthority,
  });

  /// Canonical page-block binding backed by [WebsiteEditorAsyncIntent].
  factory WebsiteAsyncFieldBinding.pageBlock({
    required WebsiteEditModeProvider provider,
    required WebsiteAsyncFieldTarget target,
  }) {
    WebsiteAsyncFieldArm? capture() {
      final intent = provider.captureAsyncIntent(blockId: target.blockId);
      if (intent == null) return null;
      return _WebsitePageBlockFieldArm(
        provider: provider,
        target: target,
        intent: intent,
      );
    }

    WebsiteInlineMutationResult commit(
      WebsiteAsyncFieldArm arm,
      WebsiteAsyncFieldOperation operation,
    ) {
      if (arm is! _WebsitePageBlockFieldArm) {
        return WebsiteInlineMutationResult.rejected;
      }
      if (!identical(provider, arm.provider) || target != arm.target) {
        // Consume the canonical one-shot token without running either the old
        // or the new field callback. A later A -> B -> A rebuild cannot reuse
        // this already-returned asynchronous result.
        arm.provider.commitAsyncIntent(
          arm.intent,
          () => WebsiteInlineMutationResult.rejected,
        );
        return WebsiteInlineMutationResult.rejected;
      }
      return provider.commitAsyncIntent(arm.intent, operation);
    }

    WebsiteContinuousFieldArm? beginContinuous(Object? baselineValue) {
      final edit = provider.beginContinuousFieldEdit(
        blockId: target.blockId,
        scopeKey: target.scopeKey,
        baselineValue: baselineValue,
      );
      if (edit == null) return null;
      return _WebsitePageBlockContinuousArm(
        provider: provider,
        target: target,
        edit: edit,
      );
    }

    WebsiteInlineMutationResult updateContinuous(
      WebsiteContinuousFieldArm arm,
      Object? nextValue,
      WebsiteAsyncFieldOperation operation,
    ) {
      if (arm is! _WebsitePageBlockContinuousArm) {
        return WebsiteInlineMutationResult.rejected;
      }
      if (!identical(provider, arm.provider) || target != arm.target) {
        arm.provider.cancelContinuousFieldEdit(
          arm.edit,
          arm.target.scopeKey,
        );
        return WebsiteInlineMutationResult.rejected;
      }
      return provider.commitContinuousFieldEdit(
        arm.edit,
        target.scopeKey,
        nextValue,
        operation,
      );
    }

    WebsiteInlineMutationResult finishContinuous(
      WebsiteContinuousFieldArm arm,
    ) {
      if (arm is! _WebsitePageBlockContinuousArm) {
        return WebsiteInlineMutationResult.rejected;
      }
      if (!identical(provider, arm.provider) || target != arm.target) {
        arm.provider.finishContinuousFieldEdit(
          arm.edit,
          arm.target.scopeKey,
        );
        return WebsiteInlineMutationResult.rejected;
      }
      return provider.finishContinuousFieldEdit(arm.edit, target.scopeKey);
    }

    WebsiteInlineMutationResult cancelContinuous(
      WebsiteContinuousFieldArm arm,
    ) {
      if (arm is! _WebsitePageBlockContinuousArm) {
        return WebsiteInlineMutationResult.rejected;
      }
      if (!identical(provider, arm.provider) || target != arm.target) {
        arm.provider.cancelContinuousFieldEdit(
          arm.edit,
          arm.target.scopeKey,
        );
        return WebsiteInlineMutationResult.rejected;
      }
      return provider.cancelContinuousFieldEdit(arm.edit, target.scopeKey);
    }

    WebsiteEditorRemoteWriteAuthority? remoteAuthority(
      WebsiteAsyncFieldArm arm,
      String operation,
      bool Function() isLiveBinding,
    ) {
      if (arm is! _WebsitePageBlockFieldArm) return null;
      if (!identical(provider, arm.provider) || target != arm.target) {
        arm.provider.commitAsyncIntent(
          arm.intent,
          () => WebsiteInlineMutationResult.rejected,
        );
        return null;
      }

      final tenantId = provider.sessionOwnerTenantId?.trim() ?? '';
      final fingerprint = provider.sessionOwnerLeaseFingerprint;
      if (tenantId.isEmpty || fingerprint == null) {
        provider.commitAsyncIntent(
          arm.intent,
          () => WebsiteInlineMutationResult.rejected,
        );
        return null;
      }
      final pageId = provider.currentPageId;
      final pageSlug = provider.currentPageSlug;
      final sessionRevision = provider.documentSessionRevision;
      final documentEpoch = provider.pageDocumentEpoch;
      final entryGeneration = provider.editorEntryLeaseGeneration;
      final entryIdentityRevision = provider.editorEntryLeaseIdentityRevision;

      bool isCurrent() {
        return isLiveBinding() &&
            provider.currentPageId == pageId &&
            provider.currentPageSlug == pageSlug &&
            provider.documentSessionRevision == sessionRevision &&
            provider.pageDocumentEpoch == documentEpoch &&
            provider.editorEntryLeaseGeneration == entryGeneration &&
            provider.editorEntryLeaseIdentityRevision ==
                entryIdentityRevision &&
            provider.sessionOwnerTenantId == tenantId &&
            provider.sessionOwnerLeaseFingerprint == fingerprint;
      }

      return WebsiteEditorRemoteWriteAuthority(
        tenantId: tenantId,
        operation: operation,
        isCurrent: isCurrent,
        claimOwner: () =>
            provider.commitAsyncIntent(
              arm.intent,
              () => WebsiteInlineMutationResult.unchanged,
            ) !=
            WebsiteInlineMutationResult.rejected,
      );
    }

    return WebsiteAsyncFieldBinding(
      identity: _WebsitePageBlockFieldIdentity(provider, target),
      ownerRevision: (
        provider,
        target,
        provider.currentPageId,
        provider.currentPageSlug,
        provider.documentSessionRevision,
        provider.pageDocumentEpoch,
        provider.editorEntryLeaseGeneration,
        provider.editorEntryLeaseIdentityRevision,
        provider.sessionOwnerTenantId,
        provider.sessionOwnerLeaseFingerprint,
      ),
      capture: capture,
      commit: commit,
      beginContinuous: beginContinuous,
      updateContinuous: updateContinuous,
      finishContinuous: finishContinuous,
      cancelContinuous: cancelContinuous,
      remoteAuthority: remoteAuthority,
    );
  }

  /// Stable semantic owner of the field rendered by this binding.
  ///
  /// Transactional controls use it to cancel a draft when Flutter retains the
  /// same State while its provider or exact target changes. It is deliberately
  /// separate from the one-shot arm: identity detects replacement during a
  /// synchronous gesture; the canonical provider token admits the later
  /// asynchronous commit.
  final Object identity;
  final Object? ownerRevision;
  Object get readOwnerIdentity => ownerRevision ?? identity;
  final WebsiteAsyncFieldArmCapture capture;
  final WebsiteAsyncFieldArmCommit commit;
  final WebsiteContinuousFieldBegin? beginContinuous;
  final WebsiteContinuousFieldUpdate? updateContinuous;
  final WebsiteContinuousFieldClose? finishContinuous;
  final WebsiteContinuousFieldClose? cancelContinuous;
  final WebsiteAsyncRemoteAuthority? remoteAuthority;
}

WebsiteMediaRemoteAuthorityResolver? websiteRemoteAuthorityResolver({
  required WebsiteAsyncFieldBinding? openingBinding,
  required WebsiteAsyncFieldArm? remoteArm,
  required WebsiteAsyncFieldBinding? Function() liveBinding,
  required bool Function() isMounted,
  required String operation,
}) {
  if (openingBinding == null || remoteArm == null) return null;
  final openingIdentity = openingBinding.identity;
  return () {
    if (!isMounted()) return null;
    final live = liveBinding();
    return live?.remoteAuthority?.call(
      remoteArm,
      operation,
      () => isMounted() && liveBinding()?.identity == openingIdentity,
    );
  };
}

final class _WebsitePageBlockFieldIdentity {
  const _WebsitePageBlockFieldIdentity(this.provider, this.target);

  final WebsiteEditModeProvider provider;
  final WebsiteAsyncFieldTarget target;

  @override
  bool operator ==(Object other) =>
      other is _WebsitePageBlockFieldIdentity &&
      identical(provider, other.provider) &&
      target == other.target;

  @override
  int get hashCode => Object.hash(identityHashCode(provider), target);
}

final class _WebsitePageBlockFieldArm implements WebsiteAsyncFieldArm {
  const _WebsitePageBlockFieldArm({
    required this.provider,
    required this.target,
    required this.intent,
  });

  final WebsiteEditModeProvider provider;
  final WebsiteAsyncFieldTarget target;
  final WebsiteEditorAsyncIntent intent;
}

final class _WebsitePageBlockContinuousArm
    implements WebsiteContinuousFieldArm {
  const _WebsitePageBlockContinuousArm({
    required this.provider,
    required this.target,
    required this.edit,
  });

  final WebsiteEditModeProvider provider;
  final WebsiteAsyncFieldTarget target;
  final WebsiteContinuousFieldEdit edit;
}

enum WebsiteMediaPickerTab { library, products, upload, url }

typedef WebsiteMediaRemoteAuthorityResolver = WebsiteEditorRemoteWriteAuthority?
    Function();

/// Opens the canonical Website Builder image picker.
Future<WebsiteMediaAsset?> showWebsiteMediaPicker({
  required BuildContext context,
  String? currentUrl,
  WebsiteMediaService? mediaService,
  bool allowProductLink = false,
  WebsiteMediaRemoteAuthorityResolver? remoteWriteAuthority,
}) {
  return showDialog<WebsiteMediaAsset>(
    context: context,
    barrierDismissible: false,
    builder: (_) => WebsiteMediaPickerDialog(
      currentUrl: currentUrl,
      mediaService: mediaService,
      allowProductLink: allowProductLink,
      remoteWriteAuthority: remoteWriteAuthority,
    ),
  );
}

class WebsiteMediaPickerDialog extends StatefulWidget {
  const WebsiteMediaPickerDialog({
    super.key,
    this.currentUrl,
    this.mediaService,
    this.allowProductLink = false,
    this.remoteWriteAuthority,
  });

  final String? currentUrl;
  final WebsiteMediaService? mediaService;
  final bool allowProductLink;
  final WebsiteMediaRemoteAuthorityResolver? remoteWriteAuthority;

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
      final authority = widget.remoteWriteAuthority?.call();
      if (widget.remoteWriteAuthority != null && authority == null) {
        throw const WebsiteEditorWriteSupersededException(
          'La sesión del editor cambió antes de subir la imagen.',
        );
      }
      final writeGuard = authority?.claimForWrite();
      final asset = await _service.uploadImage(
        bytes: picked.bytes,
        fileName: picked.name,
        tenantId: authority?.tenantId,
        writeGuard: writeGuard,
      );
      authority?.ensureCurrent();
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
    this.asyncBinding,
  });

  final String? currentUrl;
  final ValueChanged<String> onChanged;
  final bool enableBackgroundRemoval;
  final WebsiteAsyncFieldBinding? asyncBinding;

  @override
  State<WebsiteImagePickerField> createState() =>
      _WebsiteImagePickerFieldState();
}

class _WebsiteImagePickerFieldState extends State<WebsiteImagePickerField> {
  bool _removingBackground = false;

  Future<void> _openPicker() async {
    final currentUrl = widget.currentUrl;
    final openingCallback = widget.onChanged;
    final openingBinding = widget.asyncBinding;
    final arm = openingBinding?.capture();
    final remoteArm = openingBinding?.capture();
    if (openingBinding != null && (arm == null || remoteArm == null)) return;
    final remoteAuthority = websiteRemoteAuthorityResolver(
      openingBinding: openingBinding,
      remoteArm: remoteArm,
      liveBinding: () => widget.asyncBinding,
      isMounted: () => mounted,
      operation: 'subir una imagen del sitio web',
    );
    final selection = await showWebsiteMediaPicker(
      context: context,
      currentUrl: currentUrl,
      remoteWriteAuthority: remoteAuthority,
    );
    if (!mounted) return;
    if (widget.currentUrl != currentUrl) {
      if (arm != null) {
        widget.asyncBinding?.commit(
          arm,
          () => WebsiteInlineMutationResult.rejected,
        );
      }
      return;
    }
    if (selection == null) {
      if (arm != null) {
        widget.asyncBinding?.commit(
          arm,
          () => WebsiteInlineMutationResult.unchanged,
        );
      }
      return;
    }
    if (arm != null) {
      final liveBinding = widget.asyncBinding;
      if (liveBinding == null) return;
      liveBinding.commit(arm, () {
        if (selection.publicUrl == currentUrl) {
          return WebsiteInlineMutationResult.unchanged;
        }
        widget.onChanged(selection.publicUrl);
        return WebsiteInlineMutationResult.committed;
      });
      return;
    }
    if (!identical(widget.onChanged, openingCallback)) return;
    widget.onChanged(selection.publicUrl);
  }

  Future<void> _removeBackground() async {
    final url = widget.currentUrl?.trim() ?? '';
    if (url.isEmpty || _removingBackground) return;
    final openingCallback = widget.onChanged;
    final enableBackgroundRemoval = widget.enableBackgroundRemoval;
    final openingBinding = widget.asyncBinding;
    final arm = openingBinding?.capture();
    final remoteArm = openingBinding?.capture();
    if (openingBinding != null && (arm == null || remoteArm == null)) return;
    final remoteAuthority = websiteRemoteAuthorityResolver(
      openingBinding: openingBinding,
      remoteArm: remoteArm,
      liveBinding: () => widget.asyncBinding,
      isMounted: () => mounted,
      operation: 'quitar el fondo de una imagen del sitio web',
    );
    setState(() => _removingBackground = true);
    try {
      final selection = await showWebsiteBackgroundRemovalDialog(
        context: context,
        imageUrl: url,
        remoteWriteAuthority: remoteAuthority,
      );
      if (!mounted) return;
      if (selection == null) {
        if (arm != null) {
          widget.asyncBinding?.commit(
            arm,
            () => WebsiteInlineMutationResult.unchanged,
          );
        }
        return;
      }
      String resultUrl;
      if (selection.imageUrl != null) {
        resultUrl = selection.imageUrl!;
      } else {
        final authority = remoteAuthority?.call();
        if (remoteAuthority != null && authority == null) {
          throw const WebsiteEditorWriteSupersededException(
            'La sesión del editor cambió antes de guardar la imagen.',
          );
        }
        final writeGuard = authority?.claimForWrite();
        resultUrl =
            await WebsiteBackgroundRemovalService().uploadTransparentPng(
          selection.pngBytes!,
          prefix: 'block-no-bg',
          originalUrl: url,
          tenantId: authority?.tenantId,
          writeGuard: writeGuard,
        );
        authority?.ensureCurrent();
      }
      if (!mounted) return;
      if (widget.currentUrl?.trim() != url ||
          widget.enableBackgroundRemoval != enableBackgroundRemoval) {
        if (arm != null) {
          widget.asyncBinding?.commit(
            arm,
            () => WebsiteInlineMutationResult.rejected,
          );
        }
        return;
      }
      var accepted = false;
      if (arm != null) {
        final liveBinding = widget.asyncBinding;
        accepted = liveBinding != null &&
            liveBinding.commit(arm, () {
              if (resultUrl == url) {
                return WebsiteInlineMutationResult.unchanged;
              }
              widget.onChanged(resultUrl);
              return WebsiteInlineMutationResult.committed;
            }).accepted;
      } else if (identical(widget.onChanged, openingCallback)) {
        widget.onChanged(resultUrl);
        accepted = true;
      }
      if (accepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Imagen sin fondo optimizada y guardada.'),
          ),
        );
      }
    } catch (error) {
      var accepted = mounted && identical(widget.onChanged, openingCallback);
      if (mounted && arm != null) {
        final liveBinding = widget.asyncBinding;
        accepted = liveBinding != null &&
            liveBinding
                .commit(
                  arm,
                  () => WebsiteInlineMutationResult.unchanged,
                )
                .accepted;
      }
      if (accepted) {
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
