import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import '../../models/pdf_file.dart';
import 'database_helper.dart';

enum ScanCompleteness {
  complete,
  partial,
}

class ScanDiagnostics {
  final ScanCompleteness completeness;
  final bool filesystemScanComplete;
  final int filesystemCandidateCount;
  final int mediaStoreCandidateCount;
  final int uniqueCandidateCount;
  final int inaccessibleDirectoryCount;
  final int alreadyIndexedUnchanged;
  final int newlyIndexedOrUpdated;

  ScanDiagnostics({
    required this.completeness,
    required this.filesystemScanComplete,
    required this.filesystemCandidateCount,
    required this.mediaStoreCandidateCount,
    required this.uniqueCandidateCount,
    required this.inaccessibleDirectoryCount,
    required this.alreadyIndexedUnchanged,
    required this.newlyIndexedOrUpdated,
  });

  @override
  String toString() {
    return 'ScanDiagnostics(Completeness: $completeness, Filesystem: $filesystemCandidateCount, MediaStore: $mediaStoreCandidateCount, Unique: $uniqueCandidateCount, Inaccessible: $inaccessibleDirectoryCount, Unchanged: $alreadyIndexedUnchanged, Updated: $newlyIndexedOrUpdated)';
  }
}

class ScanResultData {
  final List<PdfFile> files;
  final ScanDiagnostics diagnostics;
  final Set<String> successfullyScannedDirs;

  ScanResultData({
    required this.files,
    required this.diagnostics,
    required this.successfullyScannedDirs,
  });
}

class FileScanner {
  static Future<List<PdfFile>>? _inFlightScan;
  static const MethodChannel _intentChannel = MethodChannel('com.offlinepdf.app/intent');

  /// Runs multi-source PDF discovery combining Android MediaStore, resilient filesystem walk, and persisted index.
  static Future<ScanResultData> scanAllStorageDetailed({
    Map<String, Map<String, dynamic>>? existingCache,
  }) async {
    final cache = existingCache ?? await _buildExistingCache();

    // 1. Query Android MediaStore if on Android
    List<String> mediaStorePaths = [];
    if (Platform.isAndroid) {
      try {
        final res = await _intentChannel.invokeMethod<List<dynamic>>('queryMediaStorePdfs');
        if (res != null) {
          mediaStorePaths = res.whereType<String>().toList();
        }
      } catch (_) {
        // Fallback gracefully
      }
    }

    final payload = {
      'cache': cache,
      'mediaStorePaths': mediaStorePaths,
    };

    final Map<String, dynamic> rawResult = await compute(_scanStorageIsolate, payload);

    final List<PdfFile> files = (rawResult['files'] as List<dynamic>).cast<PdfFile>();
    final int fsCount = rawResult['filesystemCandidateCount'] as int;
    final int msCount = rawResult['mediaStoreCandidateCount'] as int;
    final int uCount = rawResult['uniqueCandidateCount'] as int;
    final int inaccCount = rawResult['inaccessibleDirectoryCount'] as int;
    final int unchangedCount = rawResult['alreadyIndexedUnchanged'] as int;
    final int newCount = rawResult['newlyIndexedOrUpdated'] as int;
    final bool fsComplete = rawResult['filesystemScanComplete'] as bool;
    final List<String> scannedDirsList = (rawResult['successfullyScannedDirs'] as List<dynamic>).cast<String>();

    final diagnostics = ScanDiagnostics(
      completeness: inaccCount > 0 ? ScanCompleteness.partial : ScanCompleteness.complete,
      filesystemScanComplete: fsComplete,
      filesystemCandidateCount: fsCount,
      mediaStoreCandidateCount: msCount,
      uniqueCandidateCount: uCount,
      inaccessibleDirectoryCount: inaccCount,
      alreadyIndexedUnchanged: unchangedCount,
      newlyIndexedOrUpdated: newCount,
    );

    return ScanResultData(
      files: files,
      diagnostics: diagnostics,
      successfullyScannedDirs: scannedDirsList.toSet(),
    );
  }

  static Future<List<PdfFile>> scanAllStorage({
    Map<String, Map<String, dynamic>>? existingCache,
  }) async {
    final res = await scanAllStorageDetailed(existingCache: existingCache);
    return res.files;
  }

  /// Fast device synchronization: Queries MediaStore and updates only new/modified PDFs
  /// Completes in milliseconds without traversing the entire storage tree
  static Future<List<PdfFile>> fastDeviceSync({
    Map<String, Map<String, dynamic>>? existingCache,
  }) async {
    final cache = existingCache ?? await _buildExistingCache();
    List<String> mediaStorePaths = [];

    if (Platform.isAndroid) {
      try {
        final res = await _intentChannel.invokeMethod<List<dynamic>>('queryMediaStorePdfs');
        if (res != null) {
          mediaStorePaths = res.whereType<String>().toList();
        }
      } catch (_) {}
    }

    final dbHelper = DatabaseHelper.instance;
    final List<PdfFile> filesToUpsert = [];

    for (final rawPath in mediaStorePaths) {
      final canonicalPath = p.canonicalize(rawPath);
      if (!canonicalPath.toLowerCase().endsWith('.pdf')) continue;

      try {
        final file = File(canonicalPath);
        if (!file.existsSync()) continue;

        final stat = file.statSync();
        final cached = cache[canonicalPath];

        if (cached != null) {
          if (cached['size_bytes'] != stat.size ||
              cached['modified_at'] != stat.modified.millisecondsSinceEpoch) {
            int pageCount = 1;
            try {
              final document = await pdfrx.PdfDocument.openFile(canonicalPath);
              pageCount = document.pages.length;
              document.dispose();
            } catch (_) {}

            filesToUpsert.add(PdfFile(
              docId: cached['doc_id'] as String,
              path: canonicalPath,
              name: p.basename(canonicalPath),
              sizeBytes: stat.size,
              modifiedAt: stat.modified.millisecondsSinceEpoch,
              pageCount: pageCount,
              isFavorite: ((cached['is_favorite'] as num?)?.toInt() ?? 0) == 1,
              lastOpenedAt: (cached['last_opened_at'] as num?)?.toInt(),
              extractedText: cached['extracted_text'] as String?,
              lastOpenedPage: (cached['last_opened_page'] as num?)?.toInt() ?? 1,
              readingProgress: (cached['reading_progress'] as num?)?.toDouble() ?? 0.0,
              readingTime: (cached['reading_time'] as num?)?.toInt() ?? 0,
              completed: ((cached['completed'] as num?)?.toInt() ?? 0) == 1,
              folder: cached['folder'] as String? ?? p.basename(p.dirname(canonicalPath)),
              tags: cached['tags'] as String?,
              sourceType: cached['source_type'] as String? ?? 'imported',
              createdAt: (cached['created_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
              scanCreatedAt: (cached['scan_created_at'] as num?)?.toInt(),
            ));
          }
        } else {
          int pageCount = 1;
          try {
            final document = await pdfrx.PdfDocument.openFile(canonicalPath);
            pageCount = document.pages.length;
            document.dispose();
          } catch (_) {}

          final docId = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
              canonicalPath.hashCode.toRadixString(36);

          filesToUpsert.add(PdfFile(
            docId: docId,
            path: canonicalPath,
            name: p.basename(canonicalPath),
            sizeBytes: stat.size,
            modifiedAt: stat.modified.millisecondsSinceEpoch,
            pageCount: pageCount,
            folder: p.basename(p.dirname(canonicalPath)),
            sourceType: 'imported',
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
        }
      } catch (_) {}
    }

    if (filesToUpsert.isNotEmpty) {
      await dbHelper.bulkUpsertPdfFiles(filesToUpsert);
    }

    return await dbHelper.getAllPdfFiles();
  }

  static Future<Map<String, Map<String, dynamic>>> _buildExistingCache() async {
    try {
      final existingFiles = await DatabaseHelper.instance.getAllPdfFiles();
      final Map<String, Map<String, dynamic>> cache = {};
      for (final f in existingFiles) {
        cache[p.canonicalize(f.path)] = f.toMap();
      }
      return cache;
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, dynamic>> _scanStorageIsolate(Map<String, dynamic> payload) async {
    final Map<String, Map<String, dynamic>> existingCache =
        (payload['cache'] as Map<dynamic, dynamic>?)?.cast<String, Map<String, dynamic>>() ?? {};
    final List<String> mediaStorePaths =
        (payload['mediaStorePaths'] as List<dynamic>?)?.cast<String>() ?? [];

    final List<PdfFile> results = [];
    final Set<String> discoveredPdfPaths = {};
    final Set<String> visitedDirs = {};
    final Set<String> successfullyScannedDirs = {};

    int mediaStoreCandidatesCount = 0;
    int filesystemCandidatesCount = 0;
    int inaccessibleDirsCount = 0;
    int unchangedHits = 0;
    int newlyIndexedCount = 0;

    // A. Add valid MediaStore PDF paths
    for (final rawPath in mediaStorePaths) {
      final canonicalPath = p.canonicalize(rawPath);
      if (canonicalPath.toLowerCase().endsWith('.pdf') && !discoveredPdfPaths.contains(canonicalPath)) {
        try {
          final file = File(canonicalPath);
          if (file.existsSync()) {
            discoveredPdfPaths.add(canonicalPath);
            mediaStoreCandidatesCount++;
          }
        } catch (_) {}
      }
    }

    // B. Resilient Filesystem Traversal
    final List<String> searchPaths = [];
    if (Platform.isAndroid) {
      searchPaths.add('/storage/emulated/0');
      final dir = Directory('/storage');
      if (dir.existsSync()) {
        try {
          for (final entity in dir.listSync()) {
            if (entity is Directory &&
                !entity.path.endsWith('emulated') &&
                !entity.path.endsWith('self')) {
              searchPaths.add(entity.path);
            }
          }
        } catch (_) {}
      }
    } else {
      searchPaths.add(Directory.current.path);
    }

    for (final basePath in searchPaths) {
      final canonicalBasePath = p.canonicalize(basePath);
      final baseDir = Directory(canonicalBasePath);
      if (!baseDir.existsSync()) continue;
      await _walkDirectoryResilient(
        baseDir,
        visitedDirs,
        discoveredPdfPaths,
        successfullyScannedDirs,
        () => inaccessibleDirsCount++,
      );
    }

    // C. Process all discovered PDF paths into PdfFile objects without re-parsing unchanged PDFs
    for (final canonicalPath in discoveredPdfPaths) {
      try {
        final entity = File(canonicalPath);
        if (!entity.existsSync()) continue;

        final stat = entity.statSync();
        final cached = existingCache[canonicalPath];

        // 1. FAST CACHE HIT: Size and modified timestamp match
        if (cached != null &&
            cached['size_bytes'] == stat.size &&
            cached['modified_at'] == stat.modified.millisecondsSinceEpoch) {
          results.add(PdfFile.fromMap(cached));
          unchangedHits++;
          continue;
        }

        // 2. NEW OR MODIFIED FILE: Safely extract page count via pdfrx
        int pageCount = 0;
        try {
          final document = await pdfrx.PdfDocument.openFile(canonicalPath);
          pageCount = document.pages.length;
          document.dispose();
        } catch (_) {
          // Encrypted or malformed PDF handled gracefully
        }

        final name = p.basename(canonicalPath);
        final existingDocId = cached != null ? cached['doc_id'] as String? : null;
        final docId = existingDocId ??
            (DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
                canonicalPath.hashCode.toRadixString(36));

        results.add(PdfFile(
          docId: docId,
          path: canonicalPath,
          name: name,
          sizeBytes: stat.size,
          modifiedAt: stat.modified.millisecondsSinceEpoch,
          pageCount: pageCount,
          isFavorite: cached != null ? ((cached['is_favorite'] as num?)?.toInt() ?? 0) == 1 : false,
          lastOpenedAt: cached != null ? (cached['last_opened_at'] as num?)?.toInt() : null,
          extractedText: cached != null ? cached['extracted_text'] as String? : null,
          lastOpenedPage: cached != null ? (cached['last_opened_page'] as num?)?.toInt() ?? 1 : 1,
          readingProgress: cached != null ? (cached['reading_progress'] as num?)?.toDouble() ?? 0.0 : 0.0,
          readingTime: cached != null ? (cached['reading_time'] as num?)?.toInt() ?? 0 : 0,
          completed: cached != null ? ((cached['completed'] as num?)?.toInt() ?? 0) == 1 : false,
          folder: cached != null ? cached['folder'] as String? : p.basename(p.dirname(canonicalPath)),
          tags: cached != null ? cached['tags'] as String? : null,
          sourceType: cached != null ? (cached['source_type'] as String? ?? 'imported') : 'imported',
          createdAt: cached != null ? (cached['created_at'] as num?)?.toInt() : DateTime.now().millisecondsSinceEpoch,
          scanCreatedAt: cached != null ? (cached['scan_created_at'] as num?)?.toInt() : null,
        ));
        newlyIndexedCount++;
      } catch (_) {}
    }

    debugPrint('--- PDF Scan Diagnostics ---');
    debugPrint('MediaStore PDF candidates: $mediaStoreCandidatesCount');
    debugPrint('Filesystem PDF candidates: $filesystemCandidatesCount');
    debugPrint('Unique PDF candidates: ${discoveredPdfPaths.length}');
    debugPrint('Inaccessible directories: $inaccessibleDirsCount');
    debugPrint('Unchanged indexed files: $unchangedHits');
    debugPrint('Newly indexed/updated files: $newlyIndexedCount');
    debugPrint('Completeness: ${inaccessibleDirsCount == 0 ? "COMPLETE" : "PARTIAL"}');
    debugPrint('----------------------------');

    return {
      'files': results,
      'filesystemCandidateCount': filesystemCandidatesCount,
      'mediaStoreCandidateCount': mediaStoreCandidatesCount,
      'uniqueCandidateCount': discoveredPdfPaths.length,
      'inaccessibleDirectoryCount': inaccessibleDirsCount,
      'alreadyIndexedUnchanged': unchangedHits,
      'newlyIndexedOrUpdated': newlyIndexedCount,
      'filesystemScanComplete': inaccessibleDirsCount == 0,
      'successfullyScannedDirs': successfullyScannedDirs.toList(),
    };
  }

  static Future<void> _walkDirectoryResilient(
    Directory dir,
    Set<String> visitedDirs,
    Set<String> discoveredPdfPaths,
    Set<String> successfullyScannedDirs,
    void Function() onInaccessibleDirectory,
  ) async {
    final canonicalDir = p.canonicalize(dir.path);

    if (visitedDirs.contains(canonicalDir)) {
      return;
    }

    visitedDirs.add(canonicalDir);

    try {
      final entities = dir.listSync(
        followLinks: false,
      );

      // This directory itself was successfully enumerated.
      successfullyScannedDirs.add(canonicalDir);

      for (final entity in entities) {
        try {
          final canonicalPath = p.canonicalize(entity.path);
          final lowerPath = canonicalPath.toLowerCase();
          final name = p.basename(canonicalPath).toLowerCase();

          // Preserve current Android restricted-directory behavior.
          if (lowerPath.contains('/android/data') ||
              lowerPath.contains('\\android\\data') ||
              lowerPath.contains('/android/obb') ||
              lowerPath.contains('\\android\\obb')) {
            continue;
          }

          // Preserve known system-generated directory exclusions.
          if (name == '.thumbnails' ||
              name == '.system_generated') {
            continue;
          }

          // IMPORTANT:
          // Do not exclude Android/media.
          // User PDFs can exist there.

          if (entity is Directory) {
            await _walkDirectoryResilient(
              Directory(canonicalPath),
              visitedDirs,
              discoveredPdfPaths,
              successfullyScannedDirs,
              onInaccessibleDirectory,
            );
          } else if (entity is File &&
              lowerPath.endsWith('.pdf')) {
            discoveredPdfPaths.add(canonicalPath);
          }
        } catch (e) {
          // One bad child must never stop sibling processing.
          debugPrint(
            'PDF scanner skipped inaccessible entry: ${entity.path} - $e',
          );

          // IMPORTANT:
          // A child entry could not be inspected.
          // Treat scan as partial.
          onInaccessibleDirectory();
        }
      }
    } catch (e) {
      // The directory itself could not be enumerated.
      // This makes the scan PARTIAL.
      onInaccessibleDirectory();

      debugPrint(
        'PDF scanner could not access directory: $canonicalDir - $e',
      );
    }
  }

  /// Incremental sync with in-flight lock to prevent duplicate scans
  static Future<List<PdfFile>> runScanAndUpdateDb() async {
    if (_inFlightScan != null) {
      return await _inFlightScan!;
    }

    final completer = Completer<List<PdfFile>>();
    _inFlightScan = completer.future;

    try {
      final dbHelper = DatabaseHelper.instance;
      final existingFiles = await dbHelper.getAllPdfFiles();

      final Map<String, Map<String, dynamic>> existingCache = {};
      final Map<String, PdfFile> existingMap = {};
      for (final f in existingFiles) {
        final cp = p.canonicalize(f.path);
        existingCache[cp] = f.toMap();
        existingMap[cp] = f;
      }

      final scanResult = await scanAllStorageDetailed(existingCache: existingCache);
      final scannedFiles = scanResult.files;

      final Set<String> scannedPaths = {};
      final List<PdfFile> filesToUpsert = [];

      for (final scanned in scannedFiles) {
        final cp = p.canonicalize(scanned.path);
        scannedPaths.add(cp);
        final existing = existingMap[cp];

        if (existing != null) {
          // Check if modified on disk
          if (existing.sizeBytes != scanned.sizeBytes ||
              existing.modifiedAt != scanned.modifiedAt ||
              existing.pageCount != scanned.pageCount) {
            filesToUpsert.add(scanned.copyWith(
              docId: existing.docId,
              isFavorite: existing.isFavorite,
              lastOpenedAt: existing.lastOpenedAt,
              extractedText: existing.extractedText,
              lastOpenedPage: existing.lastOpenedPage,
              readingProgress: existing.readingProgress,
              readingTime: existing.readingTime,
              completed: existing.completed,
              folder: existing.folder,
              tags: existing.tags,
              sourceType: existing.sourceType,
              createdAt: existing.createdAt,
              scanCreatedAt: existing.scanCreatedAt,
            ));
          }
        } else {
          // Newly discovered file
          filesToUpsert.add(scanned);
        }
      }

      if (filesToUpsert.isNotEmpty) {
        await dbHelper.bulkUpsertPdfFiles(filesToUpsert);
      }

      // IMPORTANT:
      // Do NOT delete indexed files merely because they were not
      // returned by a potentially partial storage scan.
      //
      // An incomplete/inaccessible directory must never cause
      // existing user documents to disappear from the database.
      //
      // Physical deletion is already handled by the app's explicit
      // delete action. Storage synchronization must not guess.

      final updatedList = await dbHelper.getAllPdfFiles();
      completer.complete(updatedList);
      return updatedList;
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _inFlightScan = null;
    }
  }
}
