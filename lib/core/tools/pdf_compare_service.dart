import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../models/pdf_compare_result.dart';
import '../storage/ocr_cache_service.dart';

class PdfCompareService {
  static Future<PdfCompareResult> comparePdfs({
    required String fileAPath,
    required String fileBPath,
  }) async {
    try {
      final Map<int, String> textMapA = await _extractDocumentText(fileAPath);
      final Map<int, String> textMapB = await _extractDocumentText(fileBPath);

      final int pagesA = textMapA.keys.length;
      final int pagesB = textMapB.keys.length;
      final int maxPages = pagesA > pagesB ? pagesA : pagesB;

      final List<PageDiff> pageDiffs = [];
      int totalAdded = 0;
      int totalRemoved = 0;

      for (int p = 1; p <= maxPages; p++) {
        final textA = textMapA[p] ?? '';
        final textB = textMapB[p] ?? '';

        final linesA = textA.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
        final linesB = textB.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();

        final setA = linesA.toSet();
        final setB = linesB.toSet();

        final added = linesB.where((l) => !setA.contains(l)).toList();
        final removed = linesA.where((l) => !setB.contains(l)).toList();

        totalAdded += added.length;
        totalRemoved += removed.length;

        if (added.isNotEmpty || removed.isNotEmpty || textA != textB) {
          pageDiffs.add(
            PageDiff(
              pageNumber: p,
              addedLines: added,
              removedLines: removed,
              hasVisualDiff: textA != textB,
            ),
          );
        }
      }

      final summary = 'Compared $maxPages pages: $totalAdded additions, $totalRemoved removals across ${pageDiffs.length} modified pages.';

      return PdfCompareResult(
        fileAPath: fileAPath,
        fileBPath: fileBPath,
        fileAPages: pagesA,
        fileBPages: pagesB,
        pageDiffs: pageDiffs,
        summary: summary,
      );
    } catch (e) {
      return PdfCompareResult(
        fileAPath: fileAPath,
        fileBPath: fileBPath,
        fileAPages: 0,
        fileBPages: 0,
        pageDiffs: [],
        summary: 'Comparison failed due to an error.',
      );
    }
  }

  static Future<Map<int, String>> _extractDocumentText(String filePath) async {
    final Map<int, String> textMap = {};
    final cached = await OcrCacheService.getCachedFileOcr(filePath);
    if (cached.isNotEmpty) {
      return Map.from(cached);
    }

    try {
      final fileBytes = await File(filePath).readAsBytes();
      final document = sf.PdfDocument(inputBytes: fileBytes);
      final extractor = sf.PdfTextExtractor(document);

      for (int i = 0; i < document.pages.count; i++) {
        final text = extractor.extractText(startPageIndex: i, endPageIndex: i).trim();
        if (text.isNotEmpty) {
          textMap[i + 1] = text;
        }
      }
      document.dispose();
    } catch (_) {}

    return textMap;
  }
}
