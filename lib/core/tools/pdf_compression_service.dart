import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

enum CompressionQuality { low, medium, high }

class CompressionResult {
  final String originalPath;
  final String compressedPath;
  final int originalSizeBytes;
  final int compressedSizeBytes;
  final double reductionPercentage;

  CompressionResult({
    required this.originalPath,
    required this.compressedPath,
    required this.originalSizeBytes,
    required this.compressedSizeBytes,
    required this.reductionPercentage,
  });
}

class PdfCompressionService {
  static Future<CompressionResult> compressPdf({
    required String inputPath,
    required String outputPath,
    required CompressionQuality quality,
  }) async {
    final inputFile = File(inputPath);
    int originalSize = 0;
    if (await inputFile.exists()) {
      originalSize = await inputFile.length();
    }

    try {
      final bytes = await inputFile.readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);

      switch (quality) {
        case CompressionQuality.low:
          document.compressionLevel = sf.PdfCompressionLevel.bestSpeed;
          break;
        case CompressionQuality.medium:
          document.compressionLevel = sf.PdfCompressionLevel.normal;
          break;
        case CompressionQuality.high:
          document.compressionLevel = sf.PdfCompressionLevel.best;
          break;
      }

      final compressedBytes = await document.save();
      document.dispose();

      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(compressedBytes);

      final compressedSize = await outputFile.length();
      final reduction = originalSize > 0
          ? ((originalSize - compressedSize) / originalSize) * 100.0
          : 0.0;

      return CompressionResult(
        originalPath: inputPath,
        compressedPath: outputPath,
        originalSizeBytes: originalSize,
        compressedSizeBytes: compressedSize,
        reductionPercentage: reduction < 0 ? 0.0 : reduction,
      );
    } catch (_) {
      return CompressionResult(
        originalPath: inputPath,
        compressedPath: outputPath,
        originalSizeBytes: originalSize,
        compressedSizeBytes: originalSize,
        reductionPercentage: 0.0,
      );
    }
  }
}
