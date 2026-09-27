import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

class PdfMetadata {
  String title;
  String author;
  String subject;
  String keywords;
  String creator;
  String producer;

  PdfMetadata({
    this.title = '',
    this.author = '',
    this.subject = '',
    this.keywords = '',
    this.creator = '',
    this.producer = '',
  });
}

class PdfMetadataService {
  static Future<PdfMetadata> readMetadata(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);
      final info = document.documentInformation;

      final meta = PdfMetadata(
        title: info.title,
        author: info.author,
        subject: info.subject,
        keywords: info.keywords,
        creator: info.creator,
        producer: info.producer,
      );

      document.dispose();
      return meta;
    } catch (_) {
      return PdfMetadata();
    }
  }

  static Future<bool> updateMetadata({
    required String inputPath,
    required String outputPath,
    required PdfMetadata metadata,
  }) async {
    try {
      final bytes = await File(inputPath).readAsBytes();
      final document = sf.PdfDocument(inputBytes: bytes);

      document.documentInformation.title = metadata.title;
      document.documentInformation.author = metadata.author;
      document.documentInformation.subject = metadata.subject;
      document.documentInformation.keywords = metadata.keywords;
      document.documentInformation.creator = metadata.creator;

      final savedBytes = await document.save();
      document.dispose();

      await File(outputPath).writeAsBytes(savedBytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> removeAllMetadata({
    required String inputPath,
    required String outputPath,
  }) async {
    return await updateMetadata(
      inputPath: inputPath,
      outputPath: outputPath,
      metadata: PdfMetadata(
        title: '',
        author: '',
        subject: '',
        keywords: '',
        creator: '',
        producer: '',
      ),
    );
  }
}
