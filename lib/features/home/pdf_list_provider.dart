import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../models/pdf_file.dart';
import '../../core/storage/database_helper.dart';
import '../../core/storage/file_scanner.dart';

class PdfListNotifier extends StateNotifier<AsyncValue<List<PdfFile>>> {
  PdfListNotifier() : super(const AsyncValue.loading()) {
    loadFiles();
  }

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  List<PdfFile> _deduplicateFiles(List<PdfFile> files) {
    final Map<String, PdfFile> uniqueMap = {};
    for (final f in files) {
      final canonicalPath = p.canonicalize(f.path);
      uniqueMap[canonicalPath] = f.copyWith(path: canonicalPath);
    }
    return uniqueMap.values.toList();
  }

  /// 1. SQLite-First Startup: Load immediately from database without blocking on filesystem scan
  Future<void> loadFiles() async {
    try {
      final rawFiles = await DatabaseHelper.instance.getAllPdfFiles();
      final files = _deduplicateFiles(rawFiles);
      state = AsyncValue.data(files);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 2. Fast Device Sync: Instant reconciliation using MediaStore changes without full recursive walk
  Future<void> fastDeviceSync() async {
    try {
      final rawUpdated = await FileScanner.fastDeviceSync();
      final updated = _deduplicateFiles(rawUpdated);
      state = AsyncValue.data(updated);
    } catch (_) {}
  }

  /// 3. Deep Recursive Storage Sync (For explicit manual "Re-scan Storage Now")
  Future<void> syncStorage({bool isUserInitiated = false}) async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      final rawUpdatedFiles = await FileScanner.runScanAndUpdateDb();
      final updatedFiles = _deduplicateFiles(rawUpdatedFiles);
      state = AsyncValue.data(updatedFiles);
    } catch (e) {
      // Keep existing data on background sync failure
      if (state.value == null) {
        state = AsyncValue.error(e, StackTrace.current);
      }
    } finally {
      _isScanning = false;
    }
  }

  // Backward compatible alias
  Future<void> scanStorage() => syncStorage(isUserInitiated: true);

  Future<void> toggleFavorite(String path) async {
    if (state.value == null) return;
    final targetCanonical = p.canonicalize(path);
    final currentFiles = List<PdfFile>.from(state.value!);
    final index = currentFiles
        .indexWhere((f) => p.canonicalize(f.path) == targetCanonical);
    if (index != -1) {
      final file = currentFiles[index];
      final updatedStatus = !file.isFavorite;
      await DatabaseHelper.instance.toggleFavorite(file.path, updatedStatus);
      currentFiles[index] = file.copyWith(isFavorite: updatedStatus);
      state = AsyncValue.data(currentFiles);
    }
  }

  /// 3. Async Transactional Delete: Deletes physical file and database records without full scan
  Future<bool> deleteFile(String path) async {
    try {
      final canonicalPath = p.canonicalize(path);
      final file = File(canonicalPath);
      if (await file.exists()) {
        await file.delete();
      }
      await DatabaseHelper.instance.deletePdfFileFromIndex(canonicalPath);
      if (state.value != null) {
        state = AsyncValue.data(state.value!
            .where((f) => p.canonicalize(f.path) != canonicalPath)
            .toList());
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 4. Identity-Preserving Rename: Atomically updates filesystem and database child tables
  Future<String?> renameFile(String oldPath, String newName) async {
    try {
      final canonicalOldPath = p.canonicalize(oldPath);
      final file = File(canonicalOldPath);
      if (!await file.exists()) return 'File does not exist on disk.';

      var sanitizedName = newName.trim();
      if (sanitizedName.isEmpty) return 'Filename cannot be empty.';

      // Strip illegal characters
      sanitizedName = sanitizedName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      if (!sanitizedName.toLowerCase().endsWith('.pdf')) {
        sanitizedName = '$sanitizedName.pdf';
      }

      final dir = file.parent.path;
      final newPath = p.canonicalize('$dir${Platform.pathSeparator}$sanitizedName');

      if (newPath == canonicalOldPath) return null; // No change needed

      if (await File(newPath).exists()) {
        return 'A file with this name already exists.';
      }

      // Asynchronous filesystem rename
      await file.rename(newPath);

      // Atomic database update preserving docId, bookmarks, notes, OCR, study data, etc.
      final success = await DatabaseHelper.instance.renamePdfFile(
        oldPath: canonicalOldPath,
        newPath: newPath,
        newName: sanitizedName,
      );

      if (success && state.value != null) {
        final currentFiles = List<PdfFile>.from(state.value!);
        final idx = currentFiles.indexWhere((f) => p.canonicalize(f.path) == canonicalOldPath);
        if (idx != -1) {
          final oldItem = currentFiles[idx];
          currentFiles[idx] = oldItem.copyWith(
            path: newPath,
            name: sanitizedName,
            modifiedAt: DateTime.now().millisecondsSinceEpoch,
          );
          state = AsyncValue.data(currentFiles);
        }
      }

      return null; // Success (no error)
    } catch (e) {
      return 'Failed to rename file: $e';
    }
  }

  void addFile(PdfFile file) {
    final canonicalFile = file.copyWith(path: p.canonicalize(file.path));
    DatabaseHelper.instance.upsertPdfFile(canonicalFile);
    if (state.value != null) {
      final filtered = state.value!
          .where((f) => p.canonicalize(f.path) != canonicalFile.path)
          .toList();
      state = AsyncValue.data([canonicalFile, ...filtered]);
    }
  }
}

final pdfListProvider =
    StateNotifierProvider<PdfListNotifier, AsyncValue<List<PdfFile>>>((ref) {
  return PdfListNotifier();
});

final favoritePdfListProvider = Provider<List<PdfFile>>((ref) {
  final pdfState = ref.watch(pdfListProvider);
  return pdfState.when(
    data: (files) => files.where((f) => f.isFavorite).toList(),
    loading: () => [],
    error: (_, __) => [],
  );
});

final recentScansListProvider = Provider<List<PdfFile>>((ref) {
  final pdfState = ref.watch(pdfListProvider);
  return pdfState.when(
    data: (files) {
      final scans = files
          .where((f) => f.sourceType == 'scanned' || f.scanCreatedAt != null)
          .toList();
      scans.sort((a, b) {
        final aTime = a.scanCreatedAt ?? a.createdAt ?? a.modifiedAt;
        final bTime = b.scanCreatedAt ?? b.createdAt ?? b.modifiedAt;
        return bTime.compareTo(aTime);
      });
      return scans;
    },
    loading: () => [],
    error: (_, __) => [],
  );
});
