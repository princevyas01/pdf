import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart' as rx;
import '../../models/pdf_file.dart';
import 'database_helper.dart';

class PdfMetadataHelper {
  static Future<PdfFile?> registerAndSyncPdf(
    String filePath, {
    String? displayName,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) return null;

    final stat = file.statSync();
    int truePageCount = 0;

    try {
      final doc = await rx.PdfDocument.openFile(filePath);
      truePageCount = doc.pages.length;
      await doc.dispose();
    } catch (e) {
      debugPrint('pdfrx page count extraction failed for $filePath: $e');
    }

    final computedName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : filePath.split(Platform.pathSeparator).last;

    final docId = DateTime.now().microsecondsSinceEpoch.toRadixString(36) + filePath.hashCode.toRadixString(36);

    final pdfFile = PdfFile(
      docId: docId,
      path: filePath,
      name: computedName,
      sizeBytes: stat.size,
      modifiedAt: stat.modified.millisecondsSinceEpoch,
      pageCount: truePageCount,
    );

    await DatabaseHelper.instance.upsertPdfFile(pdfFile);
    return pdfFile;
  }
}
