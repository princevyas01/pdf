import 'dart:io';
import '../storage/database_helper.dart';

class BatchOperationResult {
  final int totalCount;
  final int successCount;
  final int failureCount;
  final List<String> failedFilePaths;

  BatchOperationResult({
    required this.totalCount,
    required this.successCount,
    required this.failureCount,
    this.failedFilePaths = const [],
  });
}

class PdfBatchService {
  static Future<BatchOperationResult> batchDelete(List<String> filePaths) async {
    int success = 0;
    int failure = 0;
    final List<String> failed = [];

    for (final path in filePaths) {
      bool fileDeleted = false;
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          fileDeleted = true;
        } else {
          fileDeleted = true; // Already gone
        }
      } catch (_) {
        failure++;
        failed.add(path);
        continue; // Skip DB delete if file delete failed
      }

      if (fileDeleted) {
        try {
          await DatabaseHelper.instance.deletePdfFileFromIndex(path);
          success++;
        } catch (_) {
          // Log the error but continue, file is already deleted
          failure++;
          failed.add(path);
        }
      }
    }

    return BatchOperationResult(
      totalCount: filePaths.length,
      successCount: success,
      failureCount: failure,
      failedFilePaths: failed,
    );
  }

  static Future<BatchOperationResult> batchFavorite(List<String> filePaths, bool favorite) async {
    int success = 0;
    int failure = 0;
    final List<String> failed = [];

    for (final path in filePaths) {
      try {
        await DatabaseHelper.instance.toggleFavorite(path, favorite);
        success++;
      } catch (_) {
        failure++;
        failed.add(path);
      }
    }

    return BatchOperationResult(
      totalCount: filePaths.length,
      successCount: success,
      failureCount: failure,
      failedFilePaths: failed,
    );
  }
}
