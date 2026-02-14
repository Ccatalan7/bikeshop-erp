/// Data model for a bug report or suggestion in the Debug module.
class BugReport {
  final String id;
  final String tenantId;
  final String title;
  final String type; // 'bug' | 'suggestion'
  final String? description;
  final String? module;
  final String status; // 'active' | 'resolved'
  final List<String> imageUrls;
  final String? reportedBy;
  final String? reportedByName;
  final DateTime? resolvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  BugReport({
    required this.id,
    required this.tenantId,
    required this.title,
    this.type = 'bug',
    this.description,
    this.module,
    this.status = 'active',
    this.imageUrls = const [],
    this.reportedBy,
    this.reportedByName,
    this.resolvedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BugReport.fromJson(Map<String, dynamic> json) {
    return BugReport(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      title: json['title'] as String,
      type: (json['type'] as String?) ?? 'bug',
      description: json['description'] as String?,
      module: json['module'] as String?,
      status: (json['status'] as String?) ?? 'active',
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      reportedBy: json['reported_by'] as String?,
      reportedByName: json['reported_by_name'] as String?,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'type': type,
      'description': description,
      'module': module,
      'status': status,
      'image_urls': imageUrls,
      'reported_by': reportedBy,
      'reported_by_name': reportedByName,
      if (resolvedAt != null) 'resolved_at': resolvedAt!.toIso8601String(),
    };
  }

  BugReport copyWith({
    String? title,
    String? type,
    String? description,
    String? module,
    String? status,
    List<String>? imageUrls,
    DateTime? resolvedAt,
    bool clearResolvedAt = false,
  }) {
    return BugReport(
      id: id,
      tenantId: tenantId,
      title: title ?? this.title,
      type: type ?? this.type,
      description: description ?? this.description,
      module: module ?? this.module,
      status: status ?? this.status,
      imageUrls: imageUrls ?? this.imageUrls,
      reportedBy: reportedBy,
      reportedByName: reportedByName,
      resolvedAt: clearResolvedAt ? null : (resolvedAt ?? this.resolvedAt),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  bool get isResolved => status == 'resolved';
  bool get isBug => type == 'bug';
  bool get isSuggestion => type == 'suggestion';
}
