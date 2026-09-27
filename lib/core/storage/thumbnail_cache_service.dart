import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

class ThumbnailCacheService {
  static final Map<String, File?> _memoryCache = <String, File?>{};
  static final Map<String, Future<File?>> _inFlightTasks = <String, Future<File?>>{};
  static const int _maxMemoryCacheEntries = 100;
  static int _activeRenderJobs = 0;
  static const int _maxConcurrentRenders = 3;

  static void _cachePut(String key, File? file) {
    if (_memoryCache.containsKey(key)) {
      _memoryCache.remove(key);
    } else if (_memoryCache.length >= _maxMemoryCacheEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = file;
  }

  static File? _cacheGet(String key) {
    if (!_memoryCache.containsKey(key)) return null;
    final file = _memoryCache.remove(key);
    _memoryCache[key] = file;
    return file;
  }

  static Future<File?> getThumbnailFile(String filePath) async {
    if (filePath.isEmpty) return null;
    final sourceFile = File(filePath);
    if (!await sourceFile.exists()) return null;

    try {
      final stat = await sourceFile.stat();
      final cacheKey = md5
          .convert(utf8.encode(
              '$filePath:${stat.size}:${stat.modified.millisecondsSinceEpoch}'))
          .toString();

      final cachedMem = _cacheGet(cacheKey);
      if (cachedMem != null) {
        return cachedMem;
      }

      // In-flight task deduplication
      if (_inFlightTasks.containsKey(cacheKey)) {
        return await _inFlightTasks[cacheKey]!;
      }

      final task = _generateThumbnail(sourceFile, filePath, cacheKey);
      _inFlightTasks[cacheKey] = task;

      final result = await task;
      _inFlightTasks.remove(cacheKey);
      return result;
    } catch (_) {
      return null;
    }
  }

  static Future<File?> _generateThumbnail(
      File sourceFile, String filePath, String cacheKey) async {
    // Throttle concurrent PDF rendering
    while (_activeRenderJobs >= _maxConcurrentRenders) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _activeRenderJobs++;
    PdfDocument? pdfDoc;

    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir =
          Directory('${tempDir.path}${Platform.pathSeparator}pdf_thumbnails');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final cachedFile =
          File('${cacheDir.path}${Platform.pathSeparator}$cacheKey.png');
      if (await cachedFile.exists()) {
        _cachePut(cacheKey, cachedFile);
        return cachedFile;
      }

      // Render first page thumbnail via pdfrx
      pdfDoc = await PdfDocument.openFile(filePath);
      if (pdfDoc.pages.isEmpty) {
        return null;
      }

      final page = pdfDoc.pages.first;
      final pageImage = await page.render(width: 150, height: 200);

      if (pageImage != null) {
        final uiImage = await pageImage.createImage();
        try {
          final byteData =
              await uiImage.toByteData(format: ImageByteFormat.png);
          if (byteData != null) {
            final buffer = byteData.buffer.asUint8List();
            await cachedFile.writeAsBytes(buffer);
            _cachePut(cacheKey, cachedFile);
            return cachedFile;
          }
        } finally {
          uiImage.dispose();
        }
      }
    } catch (e) {
      debugPrint('Thumbnail generation failed for $filePath: $e');
    } finally {
      _activeRenderJobs = (_activeRenderJobs - 1).clamp(0, 999);
      await pdfDoc?.dispose();
    }

    return null;
  }

  static Future<void> clearCache() async {
    _memoryCache.clear();
    _inFlightTasks.clear();
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir =
          Directory('${tempDir.path}${Platform.pathSeparator}pdf_thumbnails');
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
