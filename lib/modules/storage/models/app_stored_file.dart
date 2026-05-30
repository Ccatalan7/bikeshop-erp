class AppStoredFile {
  final String id;
  final String tenantId;
  final String? uploadedBy;
  final String fileName;
  final String storageBucket;
  final String storagePath;
  final String mimeType;
  final int sizeBytes;
  final String sourceType;
  final String? sourceId;
  final String? sourceProvider;
  final String? sourceRoute;
  final String? contextType;
  final String? contextId;
  final String? contextTitle;
  final String? contextSubtitle;
  final List<String> tags;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const AppStoredFile({
    required this.id,
    required this.tenantId,
    required this.uploadedBy,
    required this.fileName,
    required this.storageBucket,
    required this.storagePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.sourceType,
    required this.sourceId,
    required this.sourceProvider,
    required this.sourceRoute,
    required this.contextType,
    required this.contextId,
    required this.contextTitle,
    required this.contextSubtitle,
    required this.tags,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  factory AppStoredFile.fromJson(Map<String, dynamic> json) {
    return AppStoredFile(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      uploadedBy: json['uploaded_by'] as String?,
      fileName: json['file_name'] as String? ?? 'archivo',
      storageBucket: json['storage_bucket'] as String? ?? 'vinabike-files',
      storagePath: json['storage_path'] as String,
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      sourceType: json['source_type'] as String? ?? 'manual',
      sourceId: json['source_id'] as String?,
      sourceProvider: json['source_provider'] as String?,
      sourceRoute: json['source_route'] as String?,
      contextType: json['context_type'] as String?,
      contextId: json['context_id'] as String?,
      contextTitle: json['context_title'] as String?,
      contextSubtitle: json['context_subtitle'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((tag) => tag.toString())
          .where((tag) => tag.trim().isNotEmpty)
          .toList(growable: false),
      metadata: Map<String, dynamic>.from(
        json['metadata'] as Map? ?? const <String, dynamic>{},
      ),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      deletedAt: DateTime.tryParse(json['deleted_at']?.toString() ?? ''),
    );
  }

  String get extension {
    final dot = fileName.lastIndexOf('.');
    if (dot == -1 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  bool get isPdf =>
      extension == 'pdf' || mimeType.toLowerCase().contains('application/pdf');

  bool get isImage =>
      mimeType.toLowerCase().startsWith('image/') ||
      const {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(extension);

  bool get isTextLike {
    final lowerMime = mimeType.toLowerCase();
    return lowerMime.startsWith('text/') ||
        const {'txt', 'csv', 'json', 'log', 'md', 'xml'}.contains(extension);
  }

  String get displaySize {
    final bytes = sizeBytes;
    if (bytes <= 0) return 'Sin tamano';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }
}

class AppFileContext {
  final String sourceType;
  final String? sourceId;
  final String? sourceProvider;
  final String? sourceRoute;
  final String? contextType;
  final String? contextId;
  final String? contextTitle;
  final String? contextSubtitle;
  final List<String> tags;
  final Map<String, dynamic> metadata;

  const AppFileContext({
    this.sourceType = 'manual',
    this.sourceId,
    this.sourceProvider,
    this.sourceRoute,
    this.contextType,
    this.contextId,
    this.contextTitle,
    this.contextSubtitle,
    this.tags = const [],
    this.metadata = const {},
  });

  factory AppFileContext.manual({String? note}) {
    return AppFileContext(
      sourceType: 'manual',
      contextType: 'manual',
      contextTitle: note ?? 'Carga manual',
    );
  }
}
