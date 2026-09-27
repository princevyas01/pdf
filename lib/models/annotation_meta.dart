class PdfNote {
  final int? id;
  final String filePath;
  final int pageNumber;
  final String noteText;
  final int createdAt;

  PdfNote({
    this.id,
    required this.filePath,
    required this.pageNumber,
    required this.noteText,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'file_path': filePath,
      'page_number': pageNumber,
      'note_text': noteText,
      'created_at': createdAt,
    };
  }

  factory PdfNote.fromMap(Map<String, dynamic> map) {
    return PdfNote(
      id: (map['id'] as num?)?.toInt(),
      filePath: map['file_path'] as String? ?? '',
      pageNumber: (map['page_number'] as num?)?.toInt() ?? 1,
      noteText: map['note_text'] as String? ?? '',
      createdAt: (map['created_at'] as num?)?.toInt() ?? 0,
    );
  }

  PdfNote copyWith({
    int? id,
    String? filePath,
    int? pageNumber,
    String? noteText,
    int? createdAt,
  }) {
    return PdfNote(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      pageNumber: pageNumber ?? this.pageNumber,
      noteText: noteText ?? this.noteText,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
