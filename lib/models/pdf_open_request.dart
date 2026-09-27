class PdfOpenRequest {
  final String localPath;
  final String originalUri;
  final String fileName;
  final String mimeType;
  final String action;
  final String sourceApp;
  final bool isExternalLaunch;
  final bool isTemporary;
  final String requestId;
  final List<PdfOpenRequest> documents;

  PdfOpenRequest({
    required this.localPath,
    required this.originalUri,
    required this.fileName,
    required this.mimeType,
    required this.action,
    required this.sourceApp,
    this.isExternalLaunch = false,
    this.isTemporary = false,
    required this.requestId,
    this.documents = const [],
  });

  factory PdfOpenRequest.fromMap(Map<dynamic, dynamic> map) {
    List<PdfOpenRequest> docsList = [];
    if (map['documents'] is List) {
      final rawDocs = map['documents'] as List;
      docsList = rawDocs
          .whereType<Map<dynamic, dynamic>>()
          .map((d) => PdfOpenRequest.fromMap(d))
          .toList();
    }

    return PdfOpenRequest(
      localPath: map['localPath'] as String? ?? '',
      originalUri: map['originalUri'] as String? ?? '',
      fileName: map['fileName'] as String? ?? 'External_Document.pdf',
      mimeType: map['mimeType'] as String? ?? 'application/pdf',
      action: map['action'] as String? ?? 'android.intent.action.VIEW',
      sourceApp: map['sourceApp'] as String? ?? 'external',
      isExternalLaunch: map['isExternalLaunch'] as bool? ?? false,
      isTemporary: map['isTemporary'] as bool? ?? false,
      requestId: map['requestId'] as String? ?? '',
      documents: docsList,
    );
  }
}
