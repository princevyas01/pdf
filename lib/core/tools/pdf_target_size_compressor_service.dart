import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../utils/storage_location_helper.dart';

enum TargetCompressionQuality {
  maximumCompression,
  balanced,
  betterQuality,
}

class TargetCompressionResult {
  final String originalPath;
  final String outputPath;
  final int originalSizeBytes;
  final int targetSizeBytes;
  final int outputSizeBytes;
  final double reductionPercentage;
  final int pageCount;
  final String qualityProfile;
  final String statusMessage;
  final bool isTargetAchieved;

  TargetCompressionResult({
    required this.originalPath,
    required this.outputPath,
    required this.originalSizeBytes,
    required this.targetSizeBytes,
    required this.outputSizeBytes,
    required this.reductionPercentage,
    required this.pageCount,
    required this.qualityProfile,
    required this.statusMessage,
    required this.isTargetAchieved,
  });
}

class PdfTargetSizeCompressorService {
  /// Converts KB or MB to bytes (binary: 1 KB = 1024 bytes)
  static int parseSizeToBytes(double value, String unit) {
    if (unit.toUpperCase() == 'MB') {
      return (value * 1024 * 1024).round();
    }
    return (value * 1024).round();
  }

  /// Compresses an existing PDF toward a custom target size without cropping.
  /// Uses a target-directed binary search to produce the largest safe output <= targetBytes.
  static Future<TargetCompressionResult> compressPdfToTargetSize({
    required String inputPath,
    required int targetBytes,
    required TargetCompressionQuality quality,
    bool preserveTextVectors = true,
    Function(double progress, String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw Exception('Input PDF file not found at $inputPath');
    }

    final originalSize = await inputFile.length();
    final tempDir = await getTemporaryDirectory();
    final now = DateTime.now().millisecondsSinceEpoch;
    final baseName = p.basenameWithoutExtension(inputPath);
    final Set<File> createdTempFiles = {};

    onProgress?.call(0.1, 'Analyzing document structure...');
    if (isCancelled?.call() == true) throw Exception('Operation cancelled');

    int pageCount = 1;
    try {
      final doc = await pdfrx.PdfDocument.openFile(inputPath);
      pageCount = doc.pages.length;
      await doc.dispose();
    } catch (_) {}

    File? selectedFile;

    try {
      // Pass 1: Lossless structural stream compression first
      onProgress?.call(0.2, 'Applying stream optimization...');
      if (isCancelled?.call() == true) throw Exception('Operation cancelled');

      final pass1TempPath = p.join(tempDir.path, '${baseName}_temp_p1_$now.pdf');
      final pass1File = File(pass1TempPath);
      createdTempFiles.add(pass1File);

      try {
        final bytes = await inputFile.readAsBytes();
        final sfDoc = sf.PdfDocument(inputBytes: bytes);
        sfDoc.compressionLevel = sf.PdfCompressionLevel.best;
        final p1Bytes = await sfDoc.save();
        sfDoc.dispose();

        await pass1File.writeAsBytes(p1Bytes);
      } catch (_) {}

      final int pass1Size = pass1File.existsSync() ? await pass1File.length() : originalSize;

      // Pass 2: Dynamic Target-Directed Scale Search
      // Searches the scale parameter space to find the LARGEST safe candidate <= targetBytes
      File? bestUnderTargetFile;
      int bestUnderTargetSize = 0;

      File? bestOverTargetFile;
      int bestOverTargetSize = 1 << 60;

      if (pass1Size <= targetBytes) {
        bestUnderTargetFile = pass1File;
        bestUnderTargetSize = pass1Size;
      } else {
        bestOverTargetFile = pass1File;
        bestOverTargetSize = pass1Size;
      }

      pdfrx.PdfDocument? rxDoc;
      try {
        rxDoc = await pdfrx.PdfDocument.openFile(inputPath);

        double scaleMin = 0.15;
        double scaleMax = 1.0;
        switch (quality) {
          case TargetCompressionQuality.maximumCompression:
            scaleMin = 0.10;
            scaleMax = 0.85;
            break;
          case TargetCompressionQuality.betterQuality:
            scaleMin = 0.20;
            scaleMax = 1.15;
            break;
          case TargetCompressionQuality.balanced:
            scaleMin = 0.15;
            scaleMax = 1.0;
            break;
        }

        // Compute initial probe scale based on area scaling: Area ~ Scale^2 => Scale ~ sqrt(target / original)
        double estimatedScale = originalSize > 0
            ? (sqrt(targetBytes / originalSize) * 1.05).clamp(scaleMin, scaleMax)
            : 0.7;

        double scaleLow = scaleMin;
        double scaleHigh = scaleMax;

        const int maxSearchIterations = 12;
        final List<double> scalesToTest = [estimatedScale];

        for (int iter = 0; iter < maxSearchIterations; iter++) {
          if (isCancelled?.call() == true) throw Exception('Operation cancelled');

          final double currentScale;
          if (iter < scalesToTest.length) {
            currentScale = scalesToTest[iter];
          } else {
            if ((scaleHigh - scaleLow) < 0.003) {
              // Scale range sufficiently narrowed
              break;
            }
            currentScale = (scaleLow + scaleHigh) / 2.0;
          }

          final progressFraction = 0.3 + (0.6 * ((iter + 1) / maxSearchIterations));
          onProgress?.call(
            progressFraction,
            'Refining target compression (search ${iter + 1} of $maxSearchIterations)...',
          );

          final iterTempPath = p.join(tempDir.path, '${baseName}_temp_iter_${iter}_$now.pdf');
          final iterFile = await _renderPdfAtScale(
            rxDoc: rxDoc,
            scale: currentScale,
            tempPath: iterTempPath,
            isCancelled: isCancelled,
          );

          if (iterFile == null || !iterFile.existsSync()) continue;
          createdTempFiles.add(iterFile);

          final iterSize = await iterFile.length();

          if (iterSize <= targetBytes) {
            scaleLow = currentScale;

            if (bestUnderTargetFile == null || iterSize > bestUnderTargetSize) {
              if (bestUnderTargetFile != null &&
                  bestUnderTargetFile != bestOverTargetFile &&
                  bestUnderTargetFile != pass1File) {
                try {
                  if (bestUnderTargetFile.existsSync()) bestUnderTargetFile.deleteSync();
                  createdTempFiles.remove(bestUnderTargetFile);
                } catch (_) {}
              }
              bestUnderTargetFile = iterFile;
              bestUnderTargetSize = iterSize;
            }
          } else {
            scaleHigh = currentScale;

            if (bestOverTargetFile == null || iterSize < bestOverTargetSize) {
              if (bestOverTargetFile != null &&
                  bestOverTargetFile != bestUnderTargetFile &&
                  bestOverTargetFile != pass1File) {
                try {
                  if (bestOverTargetFile.existsSync()) bestOverTargetFile.deleteSync();
                  createdTempFiles.remove(bestOverTargetFile);
                } catch (_) {}
              }
              bestOverTargetFile = iterFile;
              bestOverTargetSize = iterSize;
            }
          }
        }
      } catch (_) {
      } finally {
        await rxDoc?.dispose();
      }

      // Candidate Selection: Prefer the LARGEST candidate at or below target
      final int finalOutputSize;
      if (bestUnderTargetFile != null && bestUnderTargetSize > 0) {
        selectedFile = bestUnderTargetFile;
        finalOutputSize = bestUnderTargetSize;
      } else if (bestOverTargetFile != null && bestOverTargetSize < (1 << 60)) {
        selectedFile = bestOverTargetFile;
        finalOutputSize = bestOverTargetSize;
      } else if (pass1File.existsSync()) {
        selectedFile = pass1File;
        finalOutputSize = pass1Size;
      } else {
        selectedFile = inputFile;
        finalOutputSize = originalSize;
      }

      onProgress?.call(0.95, 'Saving finalized document...');
      final isAchieved = finalOutputSize <= targetBytes;
      final statusMsg = isAchieved
          ? 'Target size achieved (${_formatBytes(finalOutputSize)})'
          : 'Closest safe result (${_formatBytes(finalOutputSize)})';

      return await _saveAndReturnResult(
        inputPath: inputPath,
        tempPath: selectedFile.path,
        originalSize: originalSize,
        targetBytes: targetBytes,
        pageCount: pageCount,
        qualityProfile: quality.name,
        isTargetAchieved: isAchieved,
        statusMessage: statusMsg,
      );
    } finally {
      // Clean up all temporary files created during the search
      for (final f in createdTempFiles) {
        try {
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
  }

  static Future<File?> _renderPdfAtScale({
    required pdfrx.PdfDocument rxDoc,
    required double scale,
    required String tempPath,
    bool Function()? isCancelled,
  }) async {
    final sfNewDoc = sf.PdfDocument();
    sfNewDoc.compressionLevel = sf.PdfCompressionLevel.best;

    try {
      for (int pageIdx = 0; pageIdx < rxDoc.pages.length; pageIdx++) {
        if (isCancelled?.call() == true) {
          sfNewDoc.dispose();
          return null;
        }

        final page = rxDoc.pages[pageIdx];
        final targetWidth = (page.width * scale).round().clamp(150, 2600);
        final targetHeight = (page.height * scale).round().clamp(150, 3600);

        final pageImage = await page.render(width: targetWidth, height: targetHeight);
        if (pageImage != null) {
          final uiImg = await pageImage.createImage();
          final byteData = await uiImg.toByteData(format: ui.ImageByteFormat.png);
          uiImg.dispose();

          if (byteData != null) {
            final imgBytes = byteData.buffer.asUint8List();
            final sfPage = sfNewDoc.pages.add();
            final bitmap = sf.PdfBitmap(imgBytes);
            // Full page rendering preserving 100% of aspect ratio and dimensions (0% cropping)
            sfPage.graphics.drawImage(
              bitmap,
              ui.Rect.fromLTWH(0, 0, sfPage.getClientSize().width, sfPage.getClientSize().height),
            );
          }
        }
      }

      final iterBytes = await sfNewDoc.save();
      sfNewDoc.dispose();

      final file = File(tempPath);
      await file.writeAsBytes(iterBytes);
      return file;
    } catch (e) {
      try {
        sfNewDoc.dispose();
      } catch (_) {}
      return null;
    }
  }

  static Future<TargetCompressionResult> _saveAndReturnResult({
    required String inputPath,
    required String tempPath,
    required int originalSize,
    required int targetBytes,
    required int pageCount,
    required String qualityProfile,
    required bool isTargetAchieved,
    required String statusMessage,
  }) async {
    final publicDir = await StorageLocationHelper.getPublicDocumentsDirectory(subFolder: 'Compressed');
    final baseName = p.basenameWithoutExtension(inputPath);
    final targetPath = await StorageLocationHelper.getUniqueFilePath(publicDir, '${baseName}_compressed.pdf');

    if (await File(tempPath).exists()) {
      await File(tempPath).copy(targetPath);
    } else {
      await File(inputPath).copy(targetPath);
    }

    final outputSize = await File(targetPath).length();
    final reduction = originalSize > 0
        ? ((originalSize - outputSize) / originalSize) * 100.0
        : 0.0;

    return TargetCompressionResult(
      originalPath: inputPath,
      outputPath: targetPath,
      originalSizeBytes: originalSize,
      targetSizeBytes: targetBytes,
      outputSizeBytes: outputSize,
      reductionPercentage: reduction < 0 ? 0.0 : reduction,
      pageCount: pageCount,
      qualityProfile: qualityProfile,
      statusMessage: statusMessage,
      isTargetAchieved: isTargetAchieved,
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }
}
