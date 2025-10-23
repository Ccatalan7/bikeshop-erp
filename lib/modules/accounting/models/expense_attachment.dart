class ExpenseAttachment {
  const ExpenseAttachment({
    this.id,
    required this.expenseId,
    required this.fileName,
    required this.fileUrl,
    this.fileType,
    this.fileSize,
    this.uploadedBy,
    this.uploadedAt,
  });

  final String? id;
  final String expenseId;
  final String fileName;
  final String fileUrl;
  final String? fileType;
  final int? fileSize;
  final String? uploadedBy;
  final DateTime? uploadedAt;

  factory ExpenseAttachment.fromJson(Map<String, dynamic> json) {
    return ExpenseAttachment(
      id: json['id']?.toString(),
      expenseId: json['expense_id']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      fileUrl: json['file_url']?.toString() ?? '',
      fileType: json['file_type']?.toString(),
      fileSize: _parseInt(json['file_size']),
      uploadedBy: json['uploaded_by']?.toString(),
      uploadedAt: _parseDate(json['uploaded_at']),
    );
  }

  Map<String, dynamic> toJson({bool includeIdentifier = true}) {
    final payload = <String, dynamic>{
      'expense_id': expenseId,
      'file_name': fileName,
      'file_url': fileUrl,
      'file_type': fileType,
      'file_size': fileSize,
      'uploaded_by': uploadedBy,
      'uploaded_at': uploadedAt?.toIso8601String(),
    };

    if (includeIdentifier && id != null) {
      payload['id'] = id;
    }

    return payload;
  }

  ExpenseAttachment copyWith({
    String? id,
    String? expenseId,
    String? fileName,
    String? fileUrl,
    String? fileType,
    int? fileSize,
    String? uploadedBy,
    DateTime? uploadedAt,
  }) {
    return ExpenseAttachment(
      id: id ?? this.id,
      expenseId: expenseId ?? this.expenseId,
      fileName: fileName ?? this.fileName,
      fileUrl: fileUrl ?? this.fileUrl,
      fileType: fileType ?? this.fileType,
      fileSize: fileSize ?? this.fileSize,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      uploadedAt: uploadedAt ?? this.uploadedAt,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}
