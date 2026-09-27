import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

class PdfEncryptionService {
  static Future<bool> encryptPdf({
    required String inputPath,
    required String outputPath,
    required String userPassword,
    String? ownerPassword,
    bool allowPrinting = true,
    bool allowCopyContent = true,
    bool allowAnnotations = true,
  }) async {
    try {
      final bytes = await File(inputPath).readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);

      final security = document.security;
      security.userPassword = userPassword;
      security.ownerPassword = ownerPassword ?? userPassword;
      security.algorithm = sf.PdfEncryptionAlgorithm.aesx256Bit;
      security.permissions.clear();
      if (allowPrinting) {
        security.permissions.add(sf.PdfPermissionsFlags.print);
      }
      if (allowCopyContent) {
        security.permissions.add(sf.PdfPermissionsFlags.copyContent);
      }
      if (allowAnnotations) {
        security.permissions.add(sf.PdfPermissionsFlags.editAnnotations);
      }

      final encryptedBytes = await document.save();
      document.dispose();

      await File(outputPath).writeAsBytes(encryptedBytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> validatePassword({
    required String filePath,
    required String password,
  }) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes, password: password);
      final isLoaded = document.pages.count > 0;
      document.dispose();
      return isLoaded;
    } catch (_) {
      return false;
    }
  }
}
