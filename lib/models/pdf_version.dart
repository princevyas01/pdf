class PdfVersion {
  final int? id;
  final String docId;
  final int versionNumber;
  final String filePath;
  final int sizeBytes;
  final int timestamp;
  final String sourceOperation;
  final String? hash;

  PdfVersion({
    this.id,
    required this.docId,
    required this.versionNumber,
    required this.filePath,
    required this.sizeBytes,
    required this.timestamp,
    required this.sourceOperation,
    this.hash,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'doc_id': docId,
      'version_number': versionNumber,
      'file_path': filePath,
      'size_bytes': sizeBytes,
      'timestamp': timestamp,
      'source_operation': sourceOperation,
      'hash': hash,
    };
  }

  factory PdfVersion.fromMap(Map<String, dynamic> map) {
    return PdfVersion(
      id: map['id'] as int?,
      docId: map['doc_id'] as String,
      versionNumber: map['version_number'] as int? ?? 1,
      filePath: map['file_path'] as String,
      sizeBytes: map['size_bytes'] as int? ?? 0,
      timestamp: map['timestamp'] as int? ?? 0,
      sourceOperation: map['source_operation'] as String? ?? 'Imported',
      hash: map['hash'] as String?,
    );
  }
}
