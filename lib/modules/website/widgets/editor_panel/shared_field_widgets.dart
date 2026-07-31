part of '../website_editor_panel.dart';

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.8),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _InspectorIntro extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;

  const _InspectorIntro({
    required this.title,
    required this.description,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF00A09D).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF00A09D).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF20C5C1)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsible section for progressive disclosure in the inspector.
class _CollapsibleSection extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;
  final IconData? icon;

  const _CollapsibleSection({
    required this.title,
    required this.children,
    this.initiallyExpanded = true,
    this.icon,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant _CollapsibleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // React to changes in initiallyExpanded (e.g., when active element changes)
    if (widget.initiallyExpanded != oldWidget.initiallyExpanded) {
      setState(() {
        _isExpanded = widget.initiallyExpanded;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      color: const Color(0xFF20C5C1),
                      size: 17,
                    ),
                    const SizedBox(width: 9),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1, color: Colors.white10),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.children,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EditorTextField extends StatefulWidget {
  final String label;
  final String value;
  final Function(String) onChanged;
  final TextEditingController? controller;
  final int maxLines;
  final String? hint;

  const _EditorTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.controller,
    this.maxLines = 1,
    this.hint,
  });

  @override
  State<_EditorTextField> createState() => _EditorTextFieldState();
}

class _EditorTextFieldState extends State<_EditorTextField> {
  TextEditingController? _internalController;

  TextEditingController get _effectiveController {
    return widget.controller ??
        (_internalController ??= TextEditingController(text: widget.value));
  }

  @override
  void initState() {
    super.initState();
    // Only create internal controller if external not provided
    if (widget.controller == null) {
      _internalController = TextEditingController(text: widget.value);
      // Add listener to catch paste events that onChanged might miss on web
      _internalController!.addListener(_onControllerChanged);
    }
  }

  void _onControllerChanged() {
    // This fires on ANY text change including paste
    final text = _effectiveController.text;
    if (text != widget.value) {
      debugPrint(
          '📝 [_EditorTextField] controller listener: label="${widget.label}", value="$text"');
      widget.onChanged(text);
    }
  }

  @override
  void didUpdateWidget(covariant _EditorTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update internal controller if we own it and value changed externally
    if (widget.controller == null && _internalController != null) {
      if (oldWidget.value != widget.value &&
          _internalController!.text != widget.value) {
        // Remove listener temporarily to avoid triggering onChanged
        _internalController!.removeListener(_onControllerChanged);
        _internalController!.text = widget.value;
        _internalController!.addListener(_onControllerChanged);
      }
    }
  }

  @override
  void dispose() {
    _internalController?.removeListener(_onControllerChanged);
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _effectiveController,
          maxLines: widget.maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: const Color(0xFF2D2D2D),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF00A09D)),
            ),
          ),
          onChanged: (v) {
            debugPrint(
                '📝 [_EditorTextField] onChanged: label="${widget.label}", value="$v"');
            widget.onChanged(v);
          },
        ),
      ],
    );
  }
}

class _EditorToggle extends StatelessWidget {
  final String label;
  final bool value;
  final Function(bool) onChanged;

  const _EditorToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: onChanged,
          // ON state: bright teal color (highlighted)
          activeThumbColor: Colors.white,
          activeTrackColor: const Color(0xFF00A09D),
          // OFF state: dim/dark (muted)
          inactiveThumbColor: Colors.grey.shade400,
          inactiveTrackColor: Colors.grey.shade700,
        ),
      ],
    );
  }
}

class _EditorSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? valueLabel;
  final Function(double) onChanged;

  const _EditorSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.valueLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                valueLabel ?? value.toInt().toString(),
                style: const TextStyle(color: Color(0xFF00A09D), fontSize: 12),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: const Color(0xFF00A09D),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
            thumbColor: const Color(0xFF00A09D),
            overlayColor: const Color(0xFF00A09D).withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _EditorDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<(String, String)> options; // (value, label)
  final Function(String) onChanged;

  const _EditorDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedLabel = options
        .firstWhere(
          (opt) => opt.$1 == value,
          orElse: () => (value, value),
        )
        .$2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 6),
        MenuAnchor(
          style: MenuStyle(
            backgroundColor: WidgetStateProperty.all(const Color(0xFF2D2D2D)),
            surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
            padding: WidgetStateProperty.all(EdgeInsets.zero),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
          ),
          menuChildren: options.map((opt) {
            final isSelected = opt.$1 == value;
            return MenuItemButton(
              onPressed: () => onChanged(opt.$1),
              style: ButtonStyle(
                backgroundColor: isSelected
                    ? WidgetStateProperty.all(
                        Colors.white.withValues(alpha: 0.1))
                    : null,
                foregroundColor: WidgetStateProperty.all(Colors.white),
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              child: Container(
                constraints: const BoxConstraints(minWidth: 120),
                child: Text(
                  opt.$2,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            );
          }).toList(),
          builder:
              (BuildContext context, MenuController controller, Widget? child) {
            return InkWell(
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        selectedLabel,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.expand_more,
                        color: Colors.white54, size: 18),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ImagePicker extends StatefulWidget {
  final String? currentUrl;
  final ValueChanged<String>? onChanged;
  final ValueChanged<WebsiteMediaAsset>? onAssetChanged;
  final bool allowProductLink;

  const _ImagePicker({
    this.currentUrl,
    this.onChanged,
    this.onAssetChanged,
    this.allowProductLink = false,
  }) : assert(onChanged != null || onAssetChanged != null);

  @override
  State<_ImagePicker> createState() => _ImagePickerState();
}

class _VideoPicker extends StatefulWidget {
  final String? currentUrl;
  final Function(String) onChanged;

  const _VideoPicker({
    this.currentUrl,
    required this.onChanged,
  });

  @override
  State<_VideoPicker> createState() => _VideoPickerState();
}

class _VideoPickerState extends State<_VideoPicker> {
  bool _isUploading = false;

  bool get _hasVideo =>
      widget.currentUrl != null && widget.currentUrl!.isNotEmpty;

  Future<String> _getTenantId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');

    final profileResponse = await Supabase.instance.client
        .from('user_profiles')
        .select('tenant_id')
        .eq('user_id', user.id)
        .single();

    return profileResponse['tenant_id'] as String;
  }

  String _videoContentType(PlatformFile file) {
    final ext = (file.extension ?? '').toLowerCase();
    if (ext == 'mp4') return 'video/mp4';
    if (ext.isNotEmpty) return 'video/$ext';
    return 'video/mp4';
  }

  Future<void> _uploadVideoFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: No se pudo leer el archivo')),
          );
        }
        return;
      }

      setState(() => _isUploading = true);

      final tenantId = await _getTenantId();

      final fileName =
          'video_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final storagePath = '$tenantId/videos/$fileName';

      await Supabase.instance.client.storage
          .from('website-assets')
          .uploadBinary(
            storagePath,
            file.bytes!,
            fileOptions: FileOptions(contentType: _videoContentType(file)),
          );

      final publicUrl = Supabase.instance.client.storage
          .from('website-assets')
          .getPublicUrl(storagePath);

      widget.onChanged(publicUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Video subido correctamente'),
            backgroundColor: Color(0xFF00A09D),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[VideoPicker] Error uploading video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isUploading ? null : _uploadVideoFile,
            icon: _isUploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.upload_file, size: 18),
            label:
                Text(_isUploading ? 'Subiendo...' : 'Subir archivo de video'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A09D),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (_hasVideo) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Archivo de video cargado',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Colors.red.shade300, size: 18),
                  onPressed: () => widget.onChanged(''),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Eliminar video',
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ImagePickerState extends State<_ImagePicker> {
  bool _isRemovingBackground = false;

  void _emitAsset(WebsiteMediaAsset asset) {
    final onAssetChanged = widget.onAssetChanged;
    if (onAssetChanged != null) {
      onAssetChanged(asset);
      return;
    }
    widget.onChanged?.call(asset.publicUrl);
  }

  void _emitUrl(String url) {
    _emitAsset(
      WebsiteMediaAsset(
        name: url.isEmpty ? 'Sin imagen' : 'Imagen seleccionada',
        path: url,
        publicUrl: url,
      ),
    );
  }

  Future<String?> _currentTenantId() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final profile = await Supabase.instance.client
        .from('user_profiles')
        .select('tenant_id')
        .eq('user_id', user.id)
        .maybeSingle();
    return profile?['tenant_id']?.toString();
  }

  Future<void> _removeBackground() async {
    final currentUrl = widget.currentUrl?.trim() ?? '';
    if (currentUrl.isEmpty || _isRemovingBackground) return;
    setState(() => _isRemovingBackground = true);
    try {
      final tenantId = await _currentTenantId();
      if (!mounted) return;
      final selection = await showWebsiteBackgroundRemovalDialog(
        context: context,
        imageUrl: currentUrl,
        tenantId: tenantId,
      );
      if (!mounted || selection == null) return;
      final service = WebsiteBackgroundRemovalService();
      final resultUrl = selection.imageUrl ??
          await service.uploadTransparentPng(
            selection.pngBytes!,
            prefix: 'block-no-bg',
            originalUrl: currentUrl,
          );
      if (!mounted) return;
      _emitUrl(resultUrl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fondo eliminado y versión web optimizada guardada.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRemovingBackground = false);
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final selection = await showWebsiteMediaPicker(
        context: context,
        currentUrl: widget.currentUrl,
        allowProductLink: widget.allowProductLink,
      );
      if (selection != null) _emitAsset(selection);
    } catch (e) {
      debugPrint('Error selecting image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.currentUrl != null && widget.currentUrl!.isNotEmpty;

    return Column(
      children: [
        // Image preview / upload area
        InkWell(
          onTap: _pickAndUploadImage,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
              image: hasImage
                  ? DecorationImage(
                      image: NetworkImage(widget.currentUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasImage
                ? Stack(
                    children: [
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Row(
                          children: [
                            _buildActionButton(
                              icon: Icons.edit,
                              tooltip: 'Cambiar imagen',
                              onTap: _pickAndUploadImage,
                            ),
                            const SizedBox(width: 4),
                            _buildActionButton(
                              icon: _isRemovingBackground
                                  ? Icons.hourglass_top_rounded
                                  : Icons.auto_fix_high_rounded,
                              tooltip: _isRemovingBackground
                                  ? 'Quitando fondo...'
                                  : 'Quitar fondo',
                              onTap: _isRemovingBackground
                                  ? () {}
                                  : _removeBackground,
                            ),
                            const SizedBox(width: 4),
                            _buildActionButton(
                              icon: Icons.delete,
                              tooltip: 'Eliminar',
                              onTap: () => _emitUrl(''),
                              isDestructive: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00A09D).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: const Icon(
                          Icons.cloud_upload_outlined,
                          color: Color(0xFF00A09D),
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Haz clic para elegir imagen',
                        style: TextStyle(
                          color: Color(0xFF00A09D),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'JPG, PNG, WebP • Optimización automática',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isDestructive
                ? Colors.red.shade700.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}

class _ColorField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final bool allowAlpha;
  final VoidCallback? onChanged;

  const _ColorField({
    required this.label,
    required this.controller,
    this.allowAlpha = true,
    this.onChanged,
  });

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  String _colorToHex(Color color) {
    return serializeWebsiteEditorColor(
      color,
      includeAlpha: widget.allowAlpha,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WebsiteColorPickerField(
          label: widget.label,
          value: widget.controller.text.isEmpty
              ? '#FFFFFF'
              : widget.controller.text,
          allowAlpha: widget.allowAlpha,
          onChanged: (value) {
            widget.controller.text = value;
            widget.onChanged?.call();
            setState(() {});
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _activateEyedropper(context),
            icon: const Icon(Icons.colorize, size: 16),
            label: const Text('Tomar color de la página'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF20C5C1),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _activateEyedropper(BuildContext context) async {
    final provider = context.read<WebsiteEditModeProvider>();
    final boundaryKey = provider.previewRepaintKey;

    if (boundaryKey.currentContext == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'No se pudo acceder al área de vista previa. Asegúrate de estar en modo edición.')),
      );
      return;
    }

    OverlayEntry? entry;
    // Create full screen overlay to capture click
    entry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: MouseRegion(
          cursor: SystemMouseCursors.precise, // Crosshair cursor
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              // Capture position and process
              _processColorPick(details.globalPosition, boundaryKey);
              entry?.remove();
              entry = null;
            },
            child: Container(
              color: Colors.transparent, // Transparent hit shield
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(entry!);

    // Optional: visual feedback that picking started
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Toca cualquier punto de la vista previa para copiar el color'),
        duration: Duration(milliseconds: 1500),
      ),
    );
  }

  Future<void> _processColorPick(Offset globalPosition, GlobalKey key) async {
    try {
      final renderBox =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (renderBox == null) return;

      // Convert global tap position to local coordinates of the boundary
      final localPosition = renderBox.globalToLocal(globalPosition);

      // Capture the image of the boundary
      // pixelRatio 1.0 is enough for color picking and faster
      final image = await renderBox.toImage(pixelRatio: 1.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (byteData != null) {
        final width = image.width;
        final height = image.height;

        // Ensure coordinates are within bounds
        final x = localPosition.dx.round().clamp(0, width - 1);
        final y = localPosition.dy.round().clamp(0, height - 1);

        // RGBA is 4 bytes per pixel
        final offset = (y * width + x) * 4;

        final r = byteData.getUint8(offset);
        final g = byteData.getUint8(offset + 1);
        final b = byteData.getUint8(offset + 2);
        // We ignore alpha for the picked color effectively, forcing full opacity for the background setting
        // or we could read it: final a = byteData.getUint8(offset + 3);

        final color = Color.fromARGB(255, r, g, b);

        if (mounted) {
          widget.controller.text = _colorToHex(color);
          widget.onChanged?.call();
          setState(() {});

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                Container(width: 20, height: 20, color: color),
                const SizedBox(width: 8),
                Text('Color copiado: ${_colorToHex(color)}')
              ]),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Eyedropper error: $e');
    }
  }
}
