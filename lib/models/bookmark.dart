class Bookmark {
  final int? id;
  final String filePath;
  final int pageNumber;
  final String label;
  final int createdAt;

  Bookmark({
    this.id,
    required this.filePath,
    required this.pageNumber,
    required this.label,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'file_path': filePath,
      'page_number': pageNumber,
      'label': label,
      'created_at': createdAt,
    };
  }

  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      id: (map['id'] as num?)?.toInt(),
      filePath: map['file_path'] as String? ?? '',
      pageNumber: (map['page_number'] as num?)?.toInt() ?? 1,
      label: map['label'] as String? ?? 'Page ${map['page_number'] ?? 1}',
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
    );
  }

  Bookmark copyWith({
    int? id,
    String? filePath,
    int? pageNumber,
    String? label,
    int? createdAt,
  }) {
    return Bookmark(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      pageNumber: pageNumber ?? this.pageNumber,
      label: label ?? this.label,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
