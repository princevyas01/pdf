const Object _unset = Object();

class PdfFile {
  final String docId;
  final String path;
  final String name;
  final int sizeBytes;
  final int modifiedAt;
  final int pageCount;
  final bool isFavorite;
  final int? lastOpenedAt;
  final String? extractedText;
  final int lastOpenedPage;
  final double readingProgress;
  final int readingTime;
  final bool completed;
  final String? folder;
  final String? tags;
  final String sourceType; // 'imported', 'scanned', 'saved'
  final int? createdAt;
  final int? scanCreatedAt;

  PdfFile({
    required this.docId,
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.pageCount,
    this.isFavorite = false,
    this.lastOpenedAt,
    this.extractedText,
    this.lastOpenedPage = 1,
    this.readingProgress = 0.0,
    this.readingTime = 0,
    this.completed = false,
    this.folder,
    this.tags,
    this.sourceType = 'imported',
    this.createdAt,
    this.scanCreatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'doc_id': docId,
      'path': path,
      'name': name,
      'size_bytes': sizeBytes,
      'modified_at': modifiedAt,
      'page_count': pageCount,
      'is_favorite': isFavorite ? 1 : 0,
      'last_opened_at': lastOpenedAt,
      'extracted_text': extractedText,
      'last_opened_page': lastOpenedPage,
      'reading_progress': readingProgress,
      'reading_time': readingTime,
      'completed': completed ? 1 : 0,
      'folder': folder,
      'tags': tags,
      'source_type': sourceType,
      'created_at': createdAt,
      'scan_created_at': scanCreatedAt,
    };
  }

  factory PdfFile.fromMap(Map<String, dynamic> map) {
    return PdfFile(
      docId: map['doc_id'] as String? ??
          (DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
              (map['path'] as String? ?? '').hashCode.toRadixString(36)),
      path: map['path'] as String? ?? '',
      name: map['name'] as String? ?? '',
      sizeBytes: (map['size_bytes'] as num?)?.toInt() ?? 0,
      modifiedAt: (map['modified_at'] as num?)?.toInt() ?? 0,
      pageCount: (map['page_count'] as num?)?.toInt() ?? 0,
      isFavorite: ((map['is_favorite'] as num?)?.toInt() ?? 0) == 1,
      lastOpenedAt: (map['last_opened_at'] as num?)?.toInt(),
      extractedText: map['extracted_text'] as String?,
      lastOpenedPage: (map['last_opened_page'] as num?)?.toInt() ?? 1,
      readingProgress: (map['reading_progress'] as num?)?.toDouble() ?? 0.0,
      readingTime: (map['reading_time'] as num?)?.toInt() ?? 0,
      completed: ((map['completed'] as num?)?.toInt() ?? 0) == 1,
      folder: map['folder'] as String?,
      tags: map['tags'] as String?,
      sourceType: map['source_type'] as String? ?? 'imported',
      createdAt: (map['created_at'] as num?)?.toInt(),
      scanCreatedAt: (map['scan_created_at'] as num?)?.toInt(),
    );
  }

  PdfFile copyWith({
    String? docId,
    String? path,
    String? name,
    int? sizeBytes,
    int? modifiedAt,
    int? pageCount,
    bool? isFavorite,
    Object? lastOpenedAt = _unset,
    Object? extractedText = _unset,
    int? lastOpenedPage,
    double? readingProgress,
    int? readingTime,
    bool? completed,
    Object? folder = _unset,
    Object? tags = _unset,
    String? sourceType,
    Object? createdAt = _unset,
    Object? scanCreatedAt = _unset,
  }) {
    return PdfFile(
      docId: docId ?? this.docId,
      path: path ?? this.path,
      name: name ?? this.name,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      pageCount: pageCount ?? this.pageCount,
      isFavorite: isFavorite ?? this.isFavorite,
      lastOpenedAt: identical(lastOpenedAt, _unset)
          ? this.lastOpenedAt
          : lastOpenedAt as int?,
      extractedText: identical(extractedText, _unset)
          ? this.extractedText
          : extractedText as String?,
      lastOpenedPage: lastOpenedPage ?? this.lastOpenedPage,
      readingProgress: readingProgress ?? this.readingProgress,
      readingTime: readingTime ?? this.readingTime,
      completed: completed ?? this.completed,
      folder: identical(folder, _unset) ? this.folder : folder as String?,
      tags: identical(tags, _unset) ? this.tags : tags as String?,
      sourceType: sourceType ?? this.sourceType,
      createdAt: identical(createdAt, _unset)
          ? this.createdAt
          : createdAt as int?,
      scanCreatedAt: identical(scanCreatedAt, _unset)
          ? this.scanCreatedAt
          : scanCreatedAt as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfFile &&
          runtimeType == other.runtimeType &&
          docId == other.docId;

  @override
  int get hashCode => docId.hashCode;
}
