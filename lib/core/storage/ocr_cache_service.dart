import '../../models/ocr_cache_entry.dart';
import 'database_helper.dart';

class OcrCacheService {
  static const int _maxCacheSize = 50;
  static final Map<String, Map<int, String>> _memoryCache = {};
  static final List<String> _cacheAccessOrder = [];

  static void _updateCacheAccess(String filePath) {
    _cacheAccessOrder.remove(filePath);
    _cacheAccessOrder.add(filePath);
    if (_cacheAccessOrder.length > _maxCacheSize) {
      final oldest = _cacheAccessOrder.removeAt(0);
      _memoryCache.remove(oldest);
    }
  }

  static Future<String?> getCachedPageText(String filePath, int pageNumber) async {
    if (_memoryCache[filePath]?.containsKey(pageNumber) == true) {
      _updateCacheAccess(filePath);
      return _memoryCache[filePath]![pageNumber];
    }

    final dbEntry = await DatabaseHelper.instance.getOcrCacheEntry(filePath, pageNumber);
    if (dbEntry != null) {
      _memoryCache.putIfAbsent(filePath, () => {})[pageNumber] = dbEntry.extractedText;
      _updateCacheAccess(filePath);
      return dbEntry.extractedText;
    }

    return null;
  }

  static Future<Map<int, String>> getCachedFileOcr(String filePath) async {
    if (_memoryCache.containsKey(filePath) && _memoryCache[filePath]!.isNotEmpty) {
      _updateCacheAccess(filePath);
      return _memoryCache[filePath]!;
    }

    final entries = await DatabaseHelper.instance.getOcrCacheForFile(filePath);
    final Map<int, String> result = {};
    for (final e in entries) {
      result[e.pageNumber] = e.extractedText;
    }

    if (result.isNotEmpty) {
      _memoryCache[filePath] = result;
      _updateCacheAccess(filePath);
    }

    return result;
  }

  static Future<void> cachePageOcrText(
    String filePath,
    int pageNumber,
    String text,
  ) async {
    if (text.trim().isEmpty) return;

    final entry = OcrCacheEntry(
      filePath: filePath,
      pageNumber: pageNumber,
      extractedText: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    await DatabaseHelper.instance.upsertOcrCacheEntry(entry);
    _memoryCache.putIfAbsent(filePath, () => {})[pageNumber] = text;
    _updateCacheAccess(filePath);
  }

  static Future<void> invalidateFileOcr(String filePath) async {
    _memoryCache.remove(filePath);
    _cacheAccessOrder.remove(filePath);
    await DatabaseHelper.instance.invalidateOcrCacheForFile(filePath);
  }
}
