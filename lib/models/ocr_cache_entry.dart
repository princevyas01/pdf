class OcrCacheEntry {
  final String filePath;
  final int pageNumber;
  final String extractedText;
  final int timestamp;
  final String? hash;

  OcrCacheEntry({
    required this.filePath,
    required this.pageNumber,
    required this.extractedText,
    required this.timestamp,
    this.hash,
  });

  Map<String, dynamic> toMap() {
    return {
      'file_path': filePath,
      'page_number': pageNumber,
      'extracted_text': extractedText,
      'timestamp': timestamp,
      'hash': hash,
    };
  }

  factory OcrCacheEntry.fromMap(Map<String, dynamic> map) {
    return OcrCacheEntry(
      filePath: map['file_path'] as String? ?? '',
      pageNumber: (map['page_number'] as num?)?.toInt() ?? 1,
      extractedText: map['extracted_text'] as String? ?? '',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      hash: map['hash'] as String?,
    );
  }
}
