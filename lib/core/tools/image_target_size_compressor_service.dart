import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../utils/storage_location_helper.dart';

class ImageTargetCompressionResult {
  final String originalPath;
  final String outputPath;
  final int originalSizeBytes;
  final int targetSizeBytes;
  final int outputSizeBytes;
  final double reductionPercentage;
  final int originalWidth;
  final int originalHeight;
  final int outputWidth;
  final int outputHeight;
  final String format;
  final bool isTargetAchieved;
  final String statusMessage;

  ImageTargetCompressionResult({
    required this.originalPath,
    required this.outputPath,
    required this.originalSizeBytes,
    required this.targetSizeBytes,
    required this.outputSizeBytes,
    required this.reductionPercentage,
    required this.originalWidth,
    required this.originalHeight,
    required this.outputWidth,
    required this.outputHeight,
    required this.format,
    required this.isTargetAchieved,
    required this.statusMessage,
  });
}

class ImageTargetSizeCompressorService {
  static const MethodChannel _intentChannel = MethodChannel('com.offlinepdf.app/intent');

  /// Converts KB or MB to bytes (binary: 1 KB = 1024 bytes)
  static int parseSizeToBytes(double value, String unit) {
    if (unit.toUpperCase() == 'MB') {
      return (value * 1024 * 1024).round();
    }
    return (value * 1024).round();
  }

  /// Compresses a single image to a custom target file size without cropping.
  static Future<ImageTargetCompressionResult> compressImageToTargetSize({
    required String inputPath,
    required int targetBytes,
    Function(double progress, String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw Exception('Input image not found at $inputPath');
    }

    final originalSize = await inputFile.length();
    final ext = p.extension(inputPath).toLowerCase();
    final baseName = p.basenameWithoutExtension(inputPath);

    onProgress?.call(0.1, 'Analyzing image dimensions and format...');
    if (isCancelled?.call() == true) throw Exception('Operation cancelled');

    final publicDir = await StorageLocationHelper.getPublicDocumentsDirectory(subFolder: 'Compressed_Images');
    final String outExt;
    if (ext == '.png') {
      outExt = '.png';
    } else if (ext == '.webp') {
      outExt = '.webp';
    } else if (ext == '.jpeg') {
      outExt = '.jpeg';
    } else {
      outExt = '.jpg';
    }
    final targetPath = await StorageLocationHelper.getUniqueFilePath(publicDir, '${baseName}_compressed$outExt');

    onProgress?.call(0.3, 'Optimizing image resolution and quality...');
    if (isCancelled?.call() == true) throw Exception('Operation cancelled');

    // 1. If on Android, use hardware-accelerated native Android Compressor
    if (Platform.isAndroid) {
      try {
        final res = await _intentChannel.invokeMapMethod<String, dynamic>('compressImage', {
          'inputPath': inputPath,
          'outputPath': targetPath,
          'targetBytes': targetBytes,
        });

        if (res != null) {
          final outputSize = (res['outputSizeBytes'] as num?)?.toInt() ?? await File(targetPath).length();
          final reduction = originalSize > 0
              ? ((originalSize - outputSize) / originalSize) * 100.0
              : 0.0;

          onProgress?.call(1.0, 'Finalized image compression');

          return ImageTargetCompressionResult(
            originalPath: inputPath,
            outputPath: targetPath,
            originalSizeBytes: originalSize,
            targetSizeBytes: targetBytes,
            outputSizeBytes: outputSize,
            reductionPercentage: reduction < 0 ? 0.0 : reduction,
            originalWidth: (res['originalWidth'] as num?)?.toInt() ?? 0,
            originalHeight: (res['originalHeight'] as num?)?.toInt() ?? 0,
            outputWidth: (res['outputWidth'] as num?)?.toInt() ?? 0,
            outputHeight: (res['outputHeight'] as num?)?.toInt() ?? 0,
            format: (res['format'] as String?) ?? ext.replaceAll('.', '').toUpperCase(),
            isTargetAchieved: (res['isTargetAchieved'] as bool?) ?? false,
            statusMessage: (res['statusMessage'] as String?) ?? 'Target achieved',
          );
        }
      } catch (_) {
        // Fallback to Dart-side image codec below
      }
    }

    // 2. Cross-platform / Fallback using dart:ui (Proportional scaling with ZERO cropping)
    final rawBytes = await inputFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(rawBytes);
    final frame = await codec.getNextFrame();
    final uiImage = frame.image;

    final origW = uiImage.width;
    final origH = uiImage.height;

    // Iterative proportional scaling passes
    final scales = [1.0, 0.85, 0.70, 0.55, 0.40, 0.25];
    int bestSize = originalSize;
    int finalW = origW;
    int finalH = origH;
    List<int> bestBytes = rawBytes;

    for (int i = 0; i < scales.length; i++) {
      if (isCancelled?.call() == true) throw Exception('Operation cancelled');

      final s = scales[i];
      final targetW = (origW * s).round().clamp(100, 4000);
      final targetH = (origH * s).round().clamp(100, 4000);

      final scaledCodec = await ui.instantiateImageCodec(
        rawBytes,
        targetWidth: targetW,
      );
      final scaledFrame = await scaledCodec.getNextFrame();
      final scaledUiImg = scaledFrame.image;

      final byteData = await scaledUiImg.toByteData(format: ui.ImageByteFormat.png);
      scaledUiImg.dispose();

      if (byteData != null) {
        final iterBytes = byteData.buffer.asUint8List();
        if (iterBytes.length < bestSize) {
          bestSize = iterBytes.length;
          bestBytes = iterBytes;
          finalW = targetW;
          finalH = targetH;
        }

        if (iterBytes.length <= targetBytes) {
          break;
        }
      }
    }

    uiImage.dispose();

    // Ensure fallback outputPath strictly matches the encoded PNG format to avoid mislabeled files
    final fallbackOutputPath = (p.extension(targetPath).toLowerCase() == '.png')
        ? targetPath
        : await StorageLocationHelper.getUniqueFilePath(publicDir, '${baseName}_compressed.png');

    await File(fallbackOutputPath).writeAsBytes(bestBytes);
    final actualSize = await File(fallbackOutputPath).length();
    final reduction = originalSize > 0
        ? ((originalSize - actualSize) / originalSize) * 100.0
        : 0.0;

    final isAchieved = actualSize <= targetBytes;
    final statusMsg = isAchieved
        ? 'Target size achieved (${_formatBytes(actualSize)})'
        : 'Closest safe result (${_formatBytes(actualSize)})';

    onProgress?.call(1.0, 'Finalized');

    return ImageTargetCompressionResult(
      originalPath: inputPath,
      outputPath: fallbackOutputPath,
      originalSizeBytes: originalSize,
      targetSizeBytes: targetBytes,
      outputSizeBytes: actualSize,
      reductionPercentage: reduction < 0 ? 0.0 : reduction,
      originalWidth: origW,
      originalHeight: origH,
      outputWidth: finalW,
      outputHeight: finalH,
      format: 'PNG',
      isTargetAchieved: isAchieved,
      statusMessage: statusMsg,
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }
}
