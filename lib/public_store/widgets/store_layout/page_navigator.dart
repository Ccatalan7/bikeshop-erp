part of '../public_store_layout.dart';

class _PreviewNavAction {
  final String? id;
  final String? label;
  final IconData? icon;
  final bool isDivider;

  const _PreviewNavAction({
    required this.id,
    required this.label,
    required this.icon,
  }) : isDivider = false;

  const _PreviewNavAction.divider()
      : id = null,
        label = null,
        icon = null,
        isDivider = true;
}

enum _PageNavKind {
  core,
  published,
  draft,
  legal,
  system,
}

class _PageNavTarget {
  final String key;
  final String title;
  final String href;
  final _PageNavKind kind;
  final String? subtitle;
  final bool? isPublished;

  const _PageNavTarget({
    required this.key,
    required this.title,
    required this.href,
    required this.kind,
    this.subtitle,
    this.isPublished,
  });

  _PageNavTarget copyWith({
    String? key,
    String? title,
    String? href,
    _PageNavKind? kind,
    String? subtitle,
    bool? isPublished,
  }) {
    return _PageNavTarget(
      key: key ?? this.key,
      title: title ?? this.title,
      href: href ?? this.href,
      kind: kind ?? this.kind,
      subtitle: subtitle ?? this.subtitle,
      isPublished: isPublished ?? this.isPublished,
    );
  }
}

class _PageNavigatorDialog extends StatefulWidget {
  const _PageNavigatorDialog({
    required this.initialSlug,
    required this.targets,
    required this.onCopyLink,
    required this.onOpenNewTab,
  });

  final String initialSlug;
  final List<_PageNavTarget> targets;
  final Future<void> Function() onCopyLink;
  final Future<void> Function() onOpenNewTab;

  @override
  State<_PageNavigatorDialog> createState() => _PageNavigatorDialogState();
}

class _PageNavigatorDialogState extends State<_PageNavigatorDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final next = _searchController.text.trim().toLowerCase();
      if (next == _query) return;
      setState(() => _query = next);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only used for logic not for UI colors anymore as we hardcode dark theme
    // final theme = Theme.of(context);

    // Filter items based on search query
    // The items are already sorted by the caller (Core -> Published -> Draft -> Legal -> System) + Alphabetical
    final filtered = _query.isEmpty
        ? widget.targets
        : widget.targets.where((t) {
            final hay = '${t.title} ${t.subtitle ?? ''}'.toLowerCase();
            return hay.contains(_query);
          }).toList();

    bool isCurrent(_PageNavTarget t) {
      final currentSlug = widget.initialSlug;
      if (currentSlug.isEmpty) return t.key == 'home';
      return t.key == currentSlug;
    }

    // Dark theme for the editor dialog
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        dividerColor: Colors.white.withValues(alpha: 0.1),
        textTheme: const TextTheme(
          titleMedium: TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 0,
          leading: IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          title: const Text('Ir a página'),
          centerTitle: true,
          shape: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          actions: [
            IconButton(
              tooltip: 'Copiar enlace',
              onPressed: widget.onCopyLink,
              icon: const Icon(Icons.copy, size: 20),
            ),
            IconButton(
              tooltip: 'Abrir en nueva pestaña',
              onPressed: widget.onOpenNewTab,
              icon: const Icon(Icons.open_in_new, size: 20),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                  hintText: 'Buscar páginas (título o ruta)',
                  hintStyle: const TextStyle(color: Colors.white38),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No hay resultados',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 20),
                      // Simply use the filtered list which is already sorted
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final t = filtered[index];
                        final current = isCurrent(t);

                        return InkWell(
                          onTap: () => Navigator.of(context).pop(t),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.05),
                                ),
                              ),
                              color: current
                                  ? const Color(0xFF00A09D)
                                      .withValues(alpha: 0.15)
                                  : Colors.transparent,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  current
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  size: 18,
                                  color: current
                                      ? const Color(0xFF00A09D)
                                      : Colors.white38,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.title,
                                        style: TextStyle(
                                          color: current
                                              ? const Color(0xFF00A09D)
                                              : Colors.white,
                                          fontWeight: current
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      if (t.subtitle != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: Text(
                                            t.subtitle!,
                                            style: TextStyle(
                                              color: current
                                                  ? const Color(0xFF00A09D)
                                                      .withValues(alpha: 0.7)
                                                  : Colors.white38,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (t.isPublished != null)
                                  Tooltip(
                                    message: t.isPublished!
                                        ? 'Publicada'
                                        : 'Borrador (oculta)',
                                    child: Icon(
                                      t.isPublished!
                                          ? Icons.public
                                          : Icons.lock_outline,
                                      size: 16,
                                      color: t.isPublished!
                                          ? Colors.greenAccent
                                              .withValues(alpha: 0.7)
                                          : Colors.orangeAccent
                                              .withValues(alpha: 0.7),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
