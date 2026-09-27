import 'dart:io';
import 'package:crypto/crypto.dart';
import '../../models/pdf_version.dart';
import '../storage/database_helper.dart';

class PdfVersionService {
  static Future<PdfVersion> createVersion({
    required String docId,
    required String filePath,
    required String sourceOperation,
  }) async {
    final file = File(filePath);
    final sizeBytes = await file.exists() ? await file.length() : 0;
    String? hash;
    if (await file.exists()) {
      try {
        final digest = await sha256.bind(file.openRead()).first;
        hash = digest.toString().substring(0, 12);
      } catch (_) {}
    }

    final existingVersions = await DatabaseHelper.instance.getVersionsForDocument(docId);
    final versionNumber = existingVersions.length + 1;

    final version = PdfVersion(
      docId: docId,
      versionNumber: versionNumber,
      filePath: filePath,
      sizeBytes: sizeBytes,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      sourceOperation: sourceOperation,
      hash: hash,
    );

    final id = await DatabaseHelper.instance.addPdfVersion(version);
    return PdfVersion(
      id: id,
      docId: version.docId,
      versionNumber: version.versionNumber,
      filePath: version.filePath,
      sizeBytes: version.sizeBytes,
      timestamp: version.timestamp,
      sourceOperation: version.sourceOperation,
      hash: version.hash,
    );
  }

  static Future<List<PdfVersion>> getVersions(String docId) async {
    return await DatabaseHelper.instance.getVersionsForDocument(docId);
  }

  static Future<bool> restoreVersion(PdfVersion version, String targetPath) async {
    try {
      final sourceFile = File(version.filePath);
      if (!sourceFile.existsSync()) return false;

      final targetFile = File(targetPath);
      await sourceFile.copy(targetFile.path);

      await createVersion(
        docId: version.docId,
        filePath: targetPath,
        sourceOperation: 'Restored from v${version.versionNumber}',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> deleteVersion(PdfVersion version) async {
    if (version.id != null) {
      await DatabaseHelper.instance.deletePdfVersion(version.id!);
      try {
        final file = File(version.filePath);
        if (file.existsSync() && !version.filePath.contains('/original/')) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  static Future<int> calculateTotalStorage(String docId) async {
    final versions = await getVersions(docId);
    int total = 0;
    for (final v in versions) {
      total += v.sizeBytes;
    }
    return total;
  }
}
