class SemanticChunk {
  final int? id;
  final String filePath;
  final int pageNumber;
  final String chunkText;
  final List<double> vectorData;
  final String? keywords;

  SemanticChunk({
    this.id,
    required this.filePath,
    required this.pageNumber,
    required this.chunkText,
    required this.vectorData,
    this.keywords,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'file_path': filePath,
      'page_number': pageNumber,
      'chunk_text': chunkText,
      'vector_data': vectorData.join(','),
      'keywords': keywords,
    };
  }

  factory SemanticChunk.fromMap(Map<String, dynamic> map) {
    final rawVec = map['vector_data'] as String? ?? '';
    final vec = rawVec.isNotEmpty
        ? rawVec.split(',').map((e) => double.tryParse(e) ?? 0.0).toList()
        : <double>[];

    return SemanticChunk(
      id: (map['id'] as num?)?.toInt(),
      filePath: map['file_path'] as String? ?? '',
      pageNumber: (map['page_number'] as num?)?.toInt() ?? 1,
      chunkText: map['chunk_text'] as String? ?? '',
      vectorData: vec,
      keywords: map['keywords'] as String?,
    );
  }
}
