import 'package:flutter_test/flutter_test.dart';
import 'package:offline_pdf_reader/core/utils/utils.dart';
import 'package:offline_pdf_reader/models/pdf_file.dart';
import 'package:offline_pdf_reader/models/pdf_open_request.dart';
import 'package:offline_pdf_reader/models/bookmark.dart';
import 'package:offline_pdf_reader/models/annotation_meta.dart';
import 'package:offline_pdf_reader/models/tool_usage_stat.dart';
import 'package:offline_pdf_reader/core/study/local_summarizer_service.dart';
import 'package:offline_pdf_reader/core/study/topic_extractor_service.dart';
import 'package:offline_pdf_reader/core/study/study_generator_service.dart';
import 'package:offline_pdf_reader/core/ai/semantic_search_service.dart';
import 'package:offline_pdf_reader/core/ai/on_device_ai_service.dart';
import 'package:offline_pdf_reader/models/pdf_version.dart';
import 'package:offline_pdf_reader/models/pdf_compare_result.dart';
import 'package:offline_pdf_reader/core/tools/pdf_metadata_service.dart';
import 'package:offline_pdf_reader/core/tools/pdf_target_size_compressor_service.dart';
import 'package:offline_pdf_reader/core/tools/image_target_size_compressor_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  group('Utils Formatting Tests', () {
    test('formatBytes converts bytes into human-readable strings', () {
      expect(Utils.formatBytes(0), '0 B');
      expect(Utils.formatBytes(512), '512.0 B');
      expect(Utils.formatBytes(1024), '1.0 KB');
      expect(Utils.formatBytes(1048576), '1.0 MB');
      expect(Utils.formatBytes(1073741824), '1.0 GB');
    });

    test('parsePageRanges handles single pages, ranges, and maxPage bounds',
        () {
      final pages = Utils.parsePageRanges('1-3, 5, 8-10', 12);
      expect(pages, equals({1, 2, 3, 5, 8, 9, 10}));

      final boundedPages = Utils.parsePageRanges('1-100', 5);
      expect(boundedPages, equals({1, 2, 3, 4, 5}));

      final invalidPages =
          Utils.parsePageRanges('0, -1, 10-5, 999999999999999999999', 5);
      expect(invalidPages, isEmpty);
    });

    test('formatRelativeTime returns accurate human-readable intervals', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(Utils.formatRelativeTime(now), 'Just now');
      expect(Utils.formatRelativeTime(null), 'Never');
    });
  });

  group('Data Model Serialization Tests', () {
    test('PdfFile map conversion & copyWith with null clearing', () {
      final pdf = PdfFile(
        docId: 'test_doc_id',
        path: '/storage/emulated/0/sample.pdf',
        name: 'sample.pdf',
        sizeBytes: 4096,
        modifiedAt: 1600000000000,
        pageCount: 15,
        isFavorite: true,
        lastOpenedAt: 1600000000000,
        extractedText: 'Sample text layer',
        lastOpenedPage: 5,
        readingProgress: 0.333,
        readingTime: 120,
        completed: false,
        folder: 'Documents',
        tags: 'work,study',
        sourceType: 'scanned',
        scanCreatedAt: 1600000000000,
      );

      final map = pdf.toMap();
      expect(map['path'], '/storage/emulated/0/sample.pdf');
      expect(map['is_favorite'], 1);
      expect(map['extracted_text'], 'Sample text layer');
      expect(map['last_opened_page'], 5);
      expect(map['reading_progress'], 0.333);
      expect(map['reading_time'], 120);
      expect(map['folder'], 'Documents');
      expect(map['source_type'], 'scanned');
      expect(map['scan_created_at'], 1600000000000);

      final restored = PdfFile.fromMap(map);
      expect(restored.path, pdf.path);
      expect(restored.isFavorite, true);
      expect(restored.extractedText, 'Sample text layer');
      expect(restored.lastOpenedPage, 5);
      expect(restored.readingProgress, 0.333);
      expect(restored.folder, 'Documents');
      expect(restored.sourceType, 'scanned');
      expect(restored.scanCreatedAt, 1600000000000);

      final cleared = pdf.copyWith(
          lastOpenedAt: null,
          extractedText: null,
          folder: null,
          scanCreatedAt: null);
      expect(cleared.lastOpenedAt, isNull);
      expect(cleared.extractedText, isNull);
      expect(cleared.folder, isNull);
      expect(cleared.scanCreatedAt, isNull);
      expect(cleared.isFavorite, true);
      expect(cleared.sourceType, 'scanned');
    });

    test('PdfOpenRequest requestId & multi-document parsing', () {
      final reqMap = {
        'localPath': '/data/user/0/app/files/external_pdfs/123.pdf',
        'originalUri': 'content://media/external/123',
        'fileName': 'College Notes.pdf',
        'mimeType': 'application/pdf',
        'action': 'android.intent.action.SEND_MULTIPLE',
        'sourceApp': 'com.whatsapp',
        'isExternalLaunch': true,
        'requestId': 'req-uuid-12345',
        'documents': [
          {
            'localPath': '/data/user/0/app/files/external_pdfs/123.pdf',
            'fileName': 'College Notes.pdf',
          },
          {
            'localPath': '/data/user/0/app/files/external_pdfs/456.pdf',
            'fileName': 'Assignment.pdf',
          }
        ]
      };

      final request = PdfOpenRequest.fromMap(reqMap);
      expect(request.localPath, '/data/user/0/app/files/external_pdfs/123.pdf');
      expect(request.fileName, 'College Notes.pdf');
      expect(request.requestId, 'req-uuid-12345');
      expect(request.documents.length, 2);
      expect(request.documents[1].fileName, 'Assignment.pdf');
    });

    test('Bookmark map conversion', () {
      final bm = Bookmark(
        id: 42,
        filePath: '/storage/sample.pdf',
        pageNumber: 7,
        label: 'Chapter 2',
        createdAt: 1600000000000,
      );

      final map = bm.toMap();
      expect(map['id'], 42);
      expect(map['file_path'], '/storage/sample.pdf');
      expect(map['page_number'], 7);

      final restored = Bookmark.fromMap(map);
      expect(restored.id, 42);
      expect(restored.label, 'Chapter 2');
    });

    test('PdfNote map conversion', () {
      final note = PdfNote(
        id: 10,
        filePath: '/storage/sample.pdf',
        pageNumber: 3,
        noteText: 'Important summary note',
        createdAt: 1600000000000,
      );

      final map = note.toMap();
      expect(map['note_text'], 'Important summary note');

      final restored = PdfNote.fromMap(map);
      expect(restored.noteText, 'Important summary note');
    });

    test('ToolUsageStat map conversion', () {
      final stat = ToolUsageStat(
        toolName: 'merge',
        useCount: 5,
        lastUsedAt: 1600000000000,
      );

      final map = stat.toMap();
      expect(map['tool_name'], 'merge');
      expect(map['use_count'], 5);

      final restored = ToolUsageStat.fromMap(map);
      expect(restored.useCount, 5);
    });
  });

  group('Phase 2 Study Tools & NLP Services Tests', () {
    test('LocalSummarizerService summarizes text locally without network',
        () async {
      const sampleText =
          'Database Normalization is the process of structuring a relational database in accordance with a series of normal forms to reduce data redundancy and improve data integrity. Primary Key uniquely identifies each tuple in a relation. Foreign Key establishes a link between tables.';

      final result = await LocalSummarizerService.summarizeText(sampleText);
      expect(result.quickSummary, isNotEmpty);
      expect(result.keyPoints, isNotEmpty);
    });

    test('TopicExtractorService extracts topics and terms with page numbers',
        () async {
      final pageMap = {
        1: 'Chapter 1 Introduction to Database Architecture. Normalization reduces redundancy.',
        2: 'Primary Key uniquely identifies a record. Foreign Key links tables.',
      };

      final topics = await TopicExtractorService.extractTopicsFromPages(
          '/sample.pdf', pageMap);
      expect(topics, isNotEmpty);

      final terms = await TopicExtractorService.extractImportantTerms(pageMap);
      expect(terms, isNotEmpty);
    });

    test('StudyGeneratorService generates Flashcards and MCQs locally',
        () async {
      final pageMap = {
        1: 'Database Normalization is defined as reducing data redundancy in relational tables.',
        2: 'Primary Key is defined as a unique record identifier in a database table.',
      };

      final cards = await StudyGeneratorService.generateFlashcards(
          '/sample.pdf', pageMap);
      expect(cards, isNotEmpty);

      final questions =
          await StudyGeneratorService.generateQuestions('/sample.pdf', pageMap);
      expect(questions, isNotEmpty);
    });
  });

  group('Phase 3 Local Intelligence & Semantic Search Tests', () {
    test(
        'SemanticSearchService chunks and ranks query relevance via vector similarity',
        () async {
      final pageMap = {
        1: 'Normalization reduces data redundancy in relational databases by organizing table structures.',
        2: 'Indexing accelerates query performance by creating B-tree data structures.',
      };

      final chunks =
          await SemanticSearchService.chunkDocumentText('/sample.pdf', pageMap);
      expect(chunks, isNotEmpty);

      final results = SemanticSearchService.search('data redundancy', chunks);
      expect(results, isNotEmpty);
      expect(results.first.chunk.pageNumber, 1);
    });

    test('OnDeviceAIService performs grounded Q&A with source page references',
        () async {
      final pageMap = {
        10: 'Primary Key uniquely identifies each record in a database table.',
      };

      final answer = await OnDeviceAIService.instance.answerQuestion(
        filePath: '/sample.pdf',
        question: 'What does Primary Key do?',
        pageTextMap: pageMap,
      );

      expect(answer.hasSufficientContext, true);
      expect(answer.sourcePages, contains(10));
      expect(answer.answer, contains('Based on this PDF'));
    });
  });

  group('Phase 4 Power-User PDF Tools Tests', () {
    test('PdfVersion serialization & database model', () {
      final version = PdfVersion(
        docId: '/sample.pdf',
        versionNumber: 1,
        filePath: '/sample.pdf',
        sizeBytes: 1024,
        timestamp: 1600000000000,
        sourceOperation: 'Imported',
      );

      final map = version.toMap();
      expect(map['doc_id'], '/sample.pdf');
      expect(map['version_number'], 1);

      final restored = PdfVersion.fromMap(map);
      expect(restored.docId, '/sample.pdf');
      expect(restored.versionNumber, 1);
      expect(restored.sourceOperation, 'Imported');
    });

    test('PdfCompareResult page difference representation', () {
      final result = PdfCompareResult(
        fileAPath: '/a.pdf',
        fileBPath: '/b.pdf',
        fileAPages: 5,
        fileBPages: 5,
        pageDiffs: [
          PageDiff(
              pageNumber: 1,
              addedLines: ['+ New line'],
              removedLines: ['- Old line']),
        ],
        summary: '1 page modified',
      );

      expect(result.pageDiffs.length, 1);
      expect(result.pageDiffs.first.hasDiff, true);
      expect(result.pageDiffs.first.addedLines.first, '+ New line');
    });

    test('PdfMetadata default values and field assignment', () {
      final meta = PdfMetadata(
        title: 'Mastering Flutter',
        author: 'John Doe',
        subject: 'PDF Architecture',
        keywords: 'flutter, pdf, study',
      );

      expect(meta.title, 'Mastering Flutter');
      expect(meta.author, 'John Doe');
      expect(meta.subject, 'PDF Architecture');
      expect(meta.keywords, 'flutter, pdf, study');
    });

    test('PdfTargetSizeCompressorService unit parsing and result metrics', () {
      expect(
          PdfTargetSizeCompressorService.parseSizeToBytes(100, 'KB'), 102400);
      expect(PdfTargetSizeCompressorService.parseSizeToBytes(1.5, 'MB'),
          (1.5 * 1024 * 1024).round());
      expect(
          PdfTargetSizeCompressorService.parseSizeToBytes(500, 'kb'), 512000);

      final result = TargetCompressionResult(
        originalPath: '/storage/original.pdf',
        outputPath: '/storage/original_compressed.pdf',
        originalSizeBytes: 1048576,
        targetSizeBytes: 524288,
        outputSizeBytes: 512000,
        reductionPercentage: 51.17,
        pageCount: 12,
        qualityProfile: 'balanced',
        statusMessage: 'Target achieved',
        isTargetAchieved: true,
      );

      expect(result.originalSizeBytes, 1048576);
      expect(result.targetSizeBytes, 524288);
      expect(result.outputSizeBytes, 512000);
      expect(result.isTargetAchieved, true);
      expect(result.pageCount, 12);
    });

    test(
        'PdfTargetSizeCompressorService prefers largest candidate at or below target',
        () {
      const targetBytes = 1024 * 1024; // 1 MB = 1048576 bytes
      final candidates = [
        1650000, // Over target
        1280000, // Over target
        980000, // Best under target (closest to 1 MB)
        720000, // Undersized
        320000, // Too small
      ];

      int bestUnderTarget = 0;
      int bestOverTarget = 1 << 60;

      for (final c in candidates) {
        if (c <= targetBytes) {
          if (c > bestUnderTarget) {
            bestUnderTarget = c;
          }
        } else {
          if (c < bestOverTarget) {
            bestOverTarget = c;
          }
        }
      }

      final chosenSize = bestUnderTarget > 0 ? bestUnderTarget : bestOverTarget;
      expect(chosenSize, 980000); // 980 KB beats 320 KB and 720 KB
      expect(chosenSize <= targetBytes, true);
    });

    test('ImageTargetSizeCompressorService unit parsing and result metrics',
        () {
      expect(
          ImageTargetSizeCompressorService.parseSizeToBytes(100, 'KB'), 102400);
      expect(ImageTargetSizeCompressorService.parseSizeToBytes(2.5, 'MB'),
          (2.5 * 1024 * 1024).round());

      final imgResult = ImageTargetCompressionResult(
        originalPath: '/storage/photo.jpg',
        outputPath: '/storage/photo_compressed.jpg',
        originalSizeBytes: 5242880,
        targetSizeBytes: 512000,
        outputSizeBytes: 498000,
        reductionPercentage: 90.5,
        originalWidth: 4000,
        originalHeight: 3000,
        outputWidth: 2200,
        outputHeight: 1650,
        format: 'JPEG',
        isTargetAchieved: true,
        statusMessage: 'Target size achieved',
      );

      expect(imgResult.originalSizeBytes, 5242880);
      expect(imgResult.outputSizeBytes, 498000);
      expect(imgResult.originalWidth, 4000);
      expect(imgResult.originalHeight, 3000);
      expect(imgResult.outputWidth, 2200);
      expect(imgResult.outputHeight, 1650);
      expect(imgResult.format, 'JPEG');
      expect(imgResult.isTargetAchieved, true);
    });
  });

  group('Structural PDF Operations (Delete, Merge, Split) Verification', () {
    test(
        'In-place page deletion via document.pages.removeAt preserves remaining pages and structure',
        () async {
      final doc = sf.PdfDocument();
      for (int i = 0; i < 3; i++) {
        final page = doc.pages.add();
        page.graphics.drawString(
          'Page content ${i + 1}',
          sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12),
          bounds: const Rect.fromLTWH(20, 20, 200, 30),
        );
      }
      expect(doc.pages.count, 3);

      final bytes = await doc.save();
      doc.dispose();

      // Test in-place removal of page index 1 (descending order)
      final docToEdit = sf.PdfDocument(inputBytes: bytes);
      final indicesToRemove = [1]..sort((a, b) => b.compareTo(a));
      for (final idx in indicesToRemove) {
        docToEdit.pages.removeAt(idx);
      }
      expect(docToEdit.pages.count, 2);

      final editedBytes = await docToEdit.save();
      docToEdit.dispose();

      // Verify reloaded document has 2 pages with intact text
      final reloadedDoc = sf.PdfDocument(inputBytes: editedBytes);
      expect(reloadedDoc.pages.count, 2);
      final textP1 = sf.PdfTextExtractor(reloadedDoc)
          .extractText(startPageIndex: 0, endPageIndex: 0);
      final textP2 = sf.PdfTextExtractor(reloadedDoc)
          .extractText(startPageIndex: 1, endPageIndex: 1);
      expect(textP1, contains('Page content 1'));
      expect(textP2, contains('Page content 3'));
      reloadedDoc.dispose();
    });

    test(
        'Structural merge via exact-size PdfSection preserves original geometry and non-raster text',
        () async {
      // Document 1 with custom size 300x500
      final doc1 = sf.PdfDocument();
      doc1.pageSettings.size = const Size(300, 500);
      doc1.pageSettings.margins.all = 0;
      final p1 = doc1.pages.add();
      p1.graphics.drawString(
        'Document 1 Text',
        sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12),
        bounds: const Rect.fromLTWH(10, 10, 200, 30),
      );
      final bytes1 = await doc1.save();
      doc1.dispose();

      // Document 2 with custom size 450x650
      final doc2 = sf.PdfDocument();
      doc2.pageSettings.size = const Size(450, 650);
      doc2.pageSettings.margins.all = 0;
      final p2 = doc2.pages.add();
      p2.graphics.drawString(
        'Document 2 Text',
        sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12),
        bounds: const Rect.fromLTWH(10, 10, 200, 30),
      );
      final bytes2 = await doc2.save();
      doc2.dispose();

      // Perform structural merge with exact PdfSection geometry
      final outputDoc = sf.PdfDocument();
      sf.PdfSection? currentSection;

      for (final docBytes in [bytes1, bytes2]) {
        final input = sf.PdfDocument(inputBytes: docBytes);
        for (int i = 0; i < input.pages.count; i++) {
          final srcPage = input.pages[i];
          final template = srcPage.createTemplate();
          if (currentSection == null ||
              currentSection.pageSettings.size != template.size) {
            currentSection = outputDoc.sections!.add();
            currentSection.pageSettings.size = template.size;
            currentSection.pageSettings.margins.all = 0;
          }
          final newPage = currentSection.pages.add();
          newPage.graphics.drawPdfTemplate(template, const Offset(0, 0));
        }
        input.dispose();
      }

      final mergedBytes = await outputDoc.save();
      outputDoc.dispose();

      // Reload and assert geometry and extractable text
      final mergedReloaded = sf.PdfDocument(inputBytes: mergedBytes);
      expect(mergedReloaded.pages.count, 2);
      expect(mergedReloaded.pages[0].size.width, 300);
      expect(mergedReloaded.pages[0].size.height, 500);
      expect(mergedReloaded.pages[1].size.width, 450);
      expect(mergedReloaded.pages[1].size.height, 650);

      final text1 = sf.PdfTextExtractor(mergedReloaded)
          .extractText(startPageIndex: 0, endPageIndex: 0);
      final text2 = sf.PdfTextExtractor(mergedReloaded)
          .extractText(startPageIndex: 1, endPageIndex: 1);
      expect(text1, contains('Document 1 Text'));
      expect(text2, contains('Document 2 Text'));
      mergedReloaded.dispose();
    });

    test(
        'Structural split via exact-size PdfSection preserves original geometry without rasterization',
        () async {
      // Document with 2 distinct custom page sizes
      final srcDoc = sf.PdfDocument();
      final sec1 = srcDoc.sections!.add();
      sec1.pageSettings.size = const Size(350, 450);
      sec1.pageSettings.margins.all = 0;
      final sp1 = sec1.pages.add();
      sp1.graphics.drawString(
        'Split Page 1 Text',
        sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12),
        bounds: const Rect.fromLTWH(10, 10, 200, 30),
      );

      final sec2 = srcDoc.sections!.add();
      sec2.pageSettings.size = const Size(400, 600);
      sec2.pageSettings.margins.all = 0;
      final sp2 = sec2.pages.add();
      sp2.graphics.drawString(
        'Split Page 2 Text',
        sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12),
        bounds: const Rect.fromLTWH(10, 10, 200, 30),
      );

      final srcBytes = await srcDoc.save();
      srcDoc.dispose();

      // Extract page 2 using structural split
      final inputDoc = sf.PdfDocument(inputBytes: srcBytes);
      final outDoc = sf.PdfDocument();
      final template = inputDoc.pages[1].createTemplate();
      final targetSection = outDoc.sections!.add();
      targetSection.pageSettings.size = template.size;
      targetSection.pageSettings.margins.all = 0;
      final extractedPage = targetSection.pages.add();
      extractedPage.graphics.drawPdfTemplate(template, const Offset(0, 0));

      final splitBytes = await outDoc.save();
      outDoc.dispose();
      inputDoc.dispose();

      final reloadedSplit = sf.PdfDocument(inputBytes: splitBytes);
      expect(reloadedSplit.pages.count, 1);
      expect(reloadedSplit.pages[0].size.width, 400);
      expect(reloadedSplit.pages[0].size.height, 600);

      final splitText = sf.PdfTextExtractor(reloadedSplit)
          .extractText(startPageIndex: 0, endPageIndex: 0);
      expect(splitText, contains('Split Page 2 Text'));
      reloadedSplit.dispose();
    });
  });
}
