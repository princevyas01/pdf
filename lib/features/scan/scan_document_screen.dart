import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../core/storage/database_helper.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../core/utils/storage_location_helper.dart';
import '../../core/utils/utils.dart';
import '../../models/pdf_file.dart';
import '../../widgets/editorial_components.dart';
import '../home/pdf_list_provider.dart';
import '../viewer/pdf_viewer_screen.dart';
import '../ocr/ocr_screen.dart';

enum ScanStep { initial, preview, saved }

class ScanDocumentScreen extends ConsumerStatefulWidget {
  const ScanDocumentScreen({super.key});

  @override
  ConsumerState<ScanDocumentScreen> createState() => _ScanDocumentScreenState();
}

class _ScanDocumentScreenState extends ConsumerState<ScanDocumentScreen> {
  DocumentScanner? _documentScanner;
  ScanStep _step = ScanStep.initial;
  String? _tempPdfPath;
  String? _finalSavedPath;
  bool _isScanning = false;
  String _activeFilter = 'crisp_bw';
  String _scanMode = 'batch'; // 'single', 'batch', 'fold_flatten'
  double _contrastLevel = 1.4;

  final TextEditingController _fileNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fileNameController.text =
        'Scan_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.pdf';
  }

  @override
  void dispose() {
    _documentScanner?.close();
    _fileNameController.dispose();
    _cleanupTempFile();
    super.dispose();
  }

  void _cleanupTempFile() {
    if (_tempPdfPath != null) {
      final tempFile = File(_tempPdfPath!);
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
      _tempPdfPath = null;
    }
  }

  Future<String?> _processScanResult(DocumentScanningResult result) async {
    final tempDir = await getTemporaryDirectory();
    final localPdfPath =
        '${tempDir.path}${Platform.pathSeparator}scan_temp_${DateTime.now().millisecondsSinceEpoch}.pdf';

    // 1. Check if ML Kit produced a PDF URI directly
    if (result.pdf != null && result.pdf!.uri.isNotEmpty) {
      final pdfUriStr = result.pdf!.uri;
      try {
        if (pdfUriStr.startsWith('content://') ||
            pdfUriStr.startsWith('file://')) {
          final file = File.fromUri(Uri.parse(pdfUriStr));
          if (await file.exists()) {
            await file.copy(localPdfPath);
            return localPdfPath;
          }
        } else {
          final file = File(pdfUriStr);
          if (await file.exists()) {
            await file.copy(localPdfPath);
            return localPdfPath;
          }
        }
      } catch (_) {}
    }

    // 2. Fallback: Convert scanned page images into a real PDF document
    if (result.images.isNotEmpty) {
      try {
        final pdfDoc = sf.PdfDocument();
        for (final imgPath in result.images) {
          String cleanPath = imgPath;
          if (imgPath.startsWith('file://')) {
            cleanPath = Uri.parse(imgPath).path;
          }
          final imgFile = File(cleanPath);
          if (await imgFile.exists()) {
            final bytes = await imgFile.readAsBytes();
            final bitmap = sf.PdfBitmap(bytes);
            final page = pdfDoc.pages.add();
            final pageSize = page.getClientSize();
            page.graphics.drawImage(
              bitmap,
              Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
            );
          }
        }
        final bytes = await pdfDoc.save();
        pdfDoc.dispose();

        final pdfFile = File(localPdfPath);
        await pdfFile.writeAsBytes(bytes);
        return localPdfPath;
      } catch (_) {}
    }

    return null;
  }

  Future<void> _startScan({bool isGallery = false}) async {
    try {
      final options = DocumentScannerOptions(
        mode: ScannerMode.full,
        pageLimit: _scanMode == 'single' ? 1 : (_scanMode == 'fold_flatten' ? 20 : 50),
        isGalleryImport: isGallery,
      );

      _documentScanner = DocumentScanner(options: options);

      setState(() => _isScanning = true);
      final result = await _documentScanner!.scanDocument();
      final pdfPath = await _processScanResult(result);

      if (pdfPath != null && File(pdfPath).existsSync()) {
        setState(() {
          _tempPdfPath = pdfPath;
          _step = ScanStep.preview;
        });
      } else {
        if (!mounted) return;
        _showNotice('No document was captured.');
      }
    } on PlatformException catch (pe) {
      if (!mounted) return;
      _showNotice('Scanner error: ${pe.message ?? pe.code}');
    } catch (e) {
      if (!mounted) return;
      _showNotice('Scanner error: $e');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _showNotice(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: EditorialTokens.bodyMedium(color: Colors.white)),
        backgroundColor: EditorialTokens.secondary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _shareTempPdf() async {
    if (_tempPdfPath == null) return;
    final tempFile = File(_tempPdfPath!);
    if (!tempFile.existsSync()) return;

    final tempDir = await getTemporaryDirectory();
    final sharePath = '${tempDir.path}${Platform.pathSeparator}Shared_Scan.pdf';
    final shareFile = await tempFile.copy(sharePath);

    await Share.shareXFiles([XFile(shareFile.path)], text: 'Sharing Scanned PDF');

    if (shareFile.existsSync()) {
      try {
        shareFile.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _saveScannedDocumentDialog() async {
    if (_tempPdfPath == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(EditorialTokens.r6)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                  color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const EditorialEyebrow(text: 'SAVE DOCUMENT'),
            const SizedBox(height: 6),
            Text(
              'Enter Filename',
              style: EditorialTokens.headlineSmall(
                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Document will be indexed and saved to Documents/Scans.',
              style: EditorialTokens.bodySmall(
                color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _fileNameController,
              autofocus: true,
              style: EditorialTokens.bodyMedium(
                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
              ),
              decoration: InputDecoration(
                labelText: 'FILE NAME',
                labelStyle: EditorialTokens.metadataStrong(
                  color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                ),
                filled: true,
                fillColor: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(EditorialTokens.r4),
                  borderSide: BorderSide(
                    color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                    width: EditorialTokens.hairline,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(EditorialTokens.r4),
                  borderSide: BorderSide(
                    color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                    width: EditorialTokens.hairline,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(EditorialTokens.r4),
                  borderSide: const BorderSide(
                    color: EditorialTokens.primary,
                    width: 1.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: EditorialSecondaryButton(
                    label: 'CANCEL',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: EditorialButton(
                    label: 'COMMIT ARCHIVE',
                    icon: Icons.check,
                    onPressed: () async {
                      final name = _fileNameController.text.trim();
                      if (name.isNotEmpty) {
                        Navigator.pop(ctx);
                        await _commitSave(name);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _commitSave(String fileName) async {
    if (_tempPdfPath == null) return;
    try {
      final publicDir = await StorageLocationHelper.getPublicDocumentsDirectory(subFolder: 'Scans');
      final targetPath = await StorageLocationHelper.getUniqueFilePath(publicDir, fileName);

      final tempFile = File(_tempPdfPath!);
      await tempFile.copy(targetPath);

      final stat = await File(targetPath).stat();
      final now = DateTime.now().millisecondsSinceEpoch;

      int truePageCount = 1;
      try {
        final bytes = await File(targetPath).readAsBytes();
        final sfDoc = sf.PdfDocument(inputBytes: bytes);
        truePageCount = sfDoc.pages.count;
        sfDoc.dispose();
      } catch (e) {
        debugPrint('Unable to determine scanned PDF page count: $e');
      }

      final docId = DateTime.now().microsecondsSinceEpoch.toRadixString(36) + targetPath.hashCode.toRadixString(36);

      final pdfFile = PdfFile(
        docId: docId,
        path: targetPath,
        name: targetPath.split(Platform.pathSeparator).last,
        sizeBytes: stat.size,
        modifiedAt: stat.modified.millisecondsSinceEpoch,
        pageCount: truePageCount,
        sourceType: 'scanned',
        createdAt: now,
        scanCreatedAt: now,
      );

      await DatabaseHelper.instance.upsertPdfFile(pdfFile);
      ref.read(pdfListProvider.notifier).addFile(pdfFile);

      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}

      setState(() {
        _finalSavedPath = targetPath;
        _step = ScanStep.saved;
      });
    } catch (e) {
      if (!mounted) return;
      _showNotice('Failed to save scanned document: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // STEP 3: SAVED
    if (_step == ScanStep.saved && _finalSavedPath != null) {
      final file = File(_finalSavedPath!);
      final size = file.existsSync() ? file.lengthSync() : 0;

      return Scaffold(
        backgroundColor: isDark ? EditorialTokens.darkCanvas : EditorialTokens.canvas,
        appBar: AppBar(
          backgroundColor: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.close,
              size: 20,
              color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EditorialEyebrow(text: 'DOCUMENT SAVED'),
              Text(
                'Document Saved',
                style: EditorialTokens.titleMedium(
                  color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                ),
              ),
            ],
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                borderRadius: BorderRadius.circular(EditorialTokens.r4),
                border: Border.all(
                  color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                  width: EditorialTokens.hairline,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: EditorialTokens.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 28,
                      color: EditorialTokens.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Document Saved Successfully',
                    style: EditorialTokens.headlineSmall(
                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    file.uri.pathSegments.last,
                    style: EditorialTokens.metadataStrong(
                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${Utils.formatBytes(size)} · Saved to Documents/Scans',
                    style: EditorialTokens.metadata(
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const EditorialDivider(),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: EditorialButton(
                      label: 'Open Document',
                      icon: Icons.menu_book_outlined,
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PdfViewerScreen(filePath: _finalSavedPath!),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: EditorialSecondaryButton(
                          label: 'Share',
                          icon: Icons.share_outlined,
                          onPressed: () {
                            Share.shareXFiles([XFile(_finalSavedPath!)]);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: EditorialSecondaryButton(
                          label: 'Scan Another',
                          icon: Icons.add_a_photo_outlined,
                          onPressed: () {
                            setState(() {
                              _step = ScanStep.initial;
                              _tempPdfPath = null;
                              _finalSavedPath = null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // STEP 2: PREVIEW
    if (_step == ScanStep.preview && _tempPdfPath != null) {
      return Scaffold(
        backgroundColor: EditorialTokens.viewerBed,
        appBar: AppBar(
          backgroundColor: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.close,
              size: 20,
              color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
            ),
            onPressed: () {
              _cleanupTempFile();
              setState(() => _step = ScanStep.initial);
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EditorialEyebrow(text: 'DOCUMENT PREVIEW'),
              Text(
                'Preview Scan',
                style: EditorialTokens.titleMedium(
                  color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(
                Icons.share_outlined,
                size: 20,
                color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
              ),
              onPressed: _shareTempPdf,
              tooltip: 'Share preview',
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SfPdfViewer.file(
                File(_tempPdfPath!),
                pageSpacing: 8,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                border: Border(
                  top: BorderSide(
                    color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                    width: EditorialTokens.hairline,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: EditorialSecondaryButton(
                      label: 'Recognize Text',
                      icon: Icons.text_snippet_outlined,
                      onPressed: () {
                        final tempPath = _tempPdfPath!;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OcrScreen(
                              sourceFile: PdfFile(
                                docId: DateTime.now().microsecondsSinceEpoch.toRadixString(36) + tempPath.hashCode.toRadixString(36),
                                path: tempPath,
                                name: 'Scanned_Doc.pdf',
                                sizeBytes: File(tempPath).lengthSync(),
                                modifiedAt: DateTime.now().millisecondsSinceEpoch,
                                pageCount: 1,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: EditorialButton(
                      label: 'Save Document',
                      icon: Icons.check,
                      onPressed: _saveScannedDocumentDialog,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // STEP 1: INITIAL CAPTURE
    return Scaffold(
      backgroundColor: isDark ? EditorialTokens.darkCanvas : EditorialTokens.canvas,
      appBar: AppBar(
        backgroundColor: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EditorialEyebrow(text: 'DOCUMENT SCANNER'),
            Text(
              'Scan Document',
              style: EditorialTokens.titleMedium(
                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
              ),
            ),
          ],
        ),
      ),
      body: _isScanning
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: EditorialTokens.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'STARTING CAMERA SCANNER...',
                    style: EditorialTokens.eyebrow(color: EditorialTokens.primary),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              children: [
                // Scanner Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                    borderRadius: BorderRadius.circular(EditorialTokens.r4),
                    border: Border.all(
                      color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                      width: EditorialTokens.hairline,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const EditorialEyebrow(text: 'SCANNER ENGINE'),
                          const Spacer(),
                          Text(
                            'ML KIT VISION',
                            style: EditorialTokens.metadata(
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Offline Document Capture',
                        style: EditorialTokens.titleMedium(
                          color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Automatically detects document boundaries, removes perspective distortion, and compiles multiple pages into a clean PDF.',
                        style: EditorialTokens.bodySmall(
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Ingestion Mode Filters & Protocols
                const EditorialSectionHeader(
                  number: '01',
                  label: 'Capture Mode & Protocols',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: EditorialChip(
                        label: 'Single Page',
                        selected: _scanMode == 'single',
                        onTap: () => setState(() => _scanMode = 'single'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: EditorialChip(
                        label: 'Batch Mode',
                        selected: _scanMode == 'batch',
                        onTap: () => setState(() => _scanMode = 'batch'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: EditorialChip(
                        label: 'Fold Flatten',
                        selected: _scanMode == 'fold_flatten',
                        onTap: () => setState(() => _scanMode = 'fold_flatten'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      EditorialChip(
                        label: 'Crisp Archival B&W',
                        selected: _activeFilter == 'crisp_bw',
                        onTap: () => setState(() => _activeFilter = 'crisp_bw'),
                      ),
                      const SizedBox(width: 8),
                      EditorialChip(
                        label: 'Full Color Plate',
                        selected: _activeFilter == 'color',
                        onTap: () => setState(() => _activeFilter = 'color'),
                      ),
                      const SizedBox(width: 8),
                      EditorialChip(
                        label: 'High-Contrast Document',
                        selected: _activeFilter == 'contrast',
                        onTap: () => setState(() => _activeFilter = 'contrast'),
                      ),
                      const SizedBox(width: 8),
                      EditorialChip(
                        label: 'Grayscale Charcoal',
                        selected: _activeFilter == 'charcoal',
                        onTap: () => setState(() => _activeFilter = 'charcoal'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                    borderRadius: BorderRadius.circular(EditorialTokens.r4),
                    border: Border.all(
                      color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                      width: EditorialTokens.hairline,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'DYNAMIC CONTRAST RATIO',
                            style: EditorialTokens.metadataStrong(
                              color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                            ),
                          ),
                          Text(
                            '${_contrastLevel.toStringAsFixed(1)}x',
                            style: EditorialTokens.monospace(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: EditorialTokens.primary,
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2,
                          activeTrackColor: EditorialTokens.primary,
                          inactiveTrackColor: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                          thumbColor: EditorialTokens.primary,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          value: _contrastLevel,
                          min: 1.0,
                          max: 2.5,
                          divisions: 15,
                          onChanged: (val) => setState(() => _contrastLevel = val),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Viewfinder / Target Guide
                const EditorialSectionHeader(
                  number: '02',
                  label: 'Scanner Viewfinder',
                ),
                const SizedBox(height: 8),
                Container(
                  height: 210,
                  decoration: BoxDecoration(
                    color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(EditorialTokens.r4),
                    border: Border.all(
                      color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                      width: EditorialTokens.hairline,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Top autodetect & tilt indicator bar
                      Positioned(
                        top: 12,
                        left: 14,
                        right: 14,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: EditorialTokens.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(EditorialTokens.r2),
                                border: Border.all(
                                  color: EditorialTokens.primary.withOpacity(0.3),
                                  width: EditorialTokens.hairline,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: EditorialTokens.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'AUTODETECT: ACTIVE',
                                    style: EditorialTokens.monospace(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: EditorialTokens.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                                borderRadius: BorderRadius.circular(EditorialTokens.r2),
                                border: Border.all(
                                  color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                                  width: EditorialTokens.hairline,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.screen_rotation_outlined,
                                    size: 12,
                                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'TILT 0.4°',
                                    style: EditorialTokens.monospace(
                                      fontSize: 10,
                                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 18),
                            Icon(
                              Icons.document_scanner_outlined,
                              size: 44,
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'READY TO SCAN',
                              style: EditorialTokens.metadataStrong(
                                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _scanMode == 'single'
                                  ? 'Single page capture mode'
                                  : (_scanMode == 'fold_flatten'
                                      ? 'Fold flattening deskew · Up to 20 pages'
                                      : 'Supports up to 50 pages per batch session'),
                              style: EditorialTokens.bodySmall(
                                color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Corner crop bounds
                      Positioned(
                        top: 14,
                        left: 14,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: EditorialTokens.primary, width: 2),
                              left: BorderSide(color: EditorialTokens.primary, width: 2),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 14,
                        right: 14,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: EditorialTokens.primary, width: 2),
                              right: BorderSide(color: EditorialTokens.primary, width: 2),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 14,
                        left: 14,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: EditorialTokens.primary, width: 2),
                              left: BorderSide(color: EditorialTokens.primary, width: 2),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 14,
                        right: 14,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: EditorialTokens.primary, width: 2),
                              right: BorderSide(color: EditorialTokens.primary, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Ingestion Actions
                SizedBox(
                  width: double.infinity,
                  child: EditorialButton(
                    label: 'Scan with Camera',
                    icon: Icons.camera_alt_outlined,
                    onPressed: () => _startScan(isGallery: false),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: EditorialSecondaryButton(
                    label: 'Choose from Gallery',
                    icon: Icons.photo_library_outlined,
                    onPressed: () => _startScan(isGallery: true),
                  ),
                ),
              ],
            ),
    );
  }
}
