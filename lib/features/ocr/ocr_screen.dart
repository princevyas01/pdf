import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../core/storage/database_helper.dart';
import '../../core/storage/pdf_metadata_helper.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../core/utils/utils.dart';
import '../../models/pdf_file.dart';
import '../../widgets/editorial_components.dart';
import '../../widgets/pdf_tool_file_picker_screen.dart';
import '../home/pdf_list_provider.dart';

class OcrScreen extends ConsumerStatefulWidget {
  final PdfFile? sourceFile;

  const OcrScreen({super.key, this.sourceFile});

  @override
  ConsumerState<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends ConsumerState<OcrScreen> {
  PdfFile? _selectedFile;
  bool _isProcessing = false;
  int _currentPage = 0;
  int _totalPages = 0;
  int _activeViewIndex = 0; // 0: Extracted Text, 1: Page Breakdown, 2: Formula Index

  final Map<int, TextEditingController> _pageTextControllers = {};
  final Map<int, RecognizedText> _recognizedPages = {};
  final TextEditingController _fullTextController = TextEditingController();

  String _combinedText = '';
  File? _tempTextFile;

  @override
  void initState() {
    super.initState();
    _selectedFile = widget.sourceFile;
    if (_selectedFile != null) {
      _startOcrProcess();
    }
  }

  @override
  void dispose() {
    for (final c in _pageTextControllers.values) {
      c.dispose();
    }
    _fullTextController.dispose();
    _deleteTempFile();
    super.dispose();
  }

  Future<void> _deleteTempFile() async {
    try {
      if (_tempTextFile != null && await _tempTextFile!.exists()) {
        await _tempTextFile!.delete();
      }
    } catch (_) {}
  }

  Future<void> _startOcrProcess() async {
    if (_selectedFile == null) return;

    setState(() {
      _isProcessing = true;
      _currentPage = 0;
      _pageTextControllers.clear();
      _recognizedPages.clear();
    });

    try {
      final pdfDoc = await pdfrx.PdfDocument.openFile(_selectedFile!.path);
      _totalPages = pdfDoc.pages.length;

      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final StringBuffer fullTextBuffer = StringBuffer();
      final tempDir = await getTemporaryDirectory();

      for (int i = 0; i < _totalPages; i++) {
        if (!mounted) break;
        setState(() {
          _currentPage = i + 1;
        });

        try {
          final page = pdfDoc.pages[i];

          // High-resolution 300 DPI rendering (min 2000px width) for ultra-crisp ML Kit OCR accuracy
          final renderWidth = (page.width * 3.0).toInt().clamp(1800, 3600);
          final renderHeight = (page.height * 3.0).toInt().clamp(2400, 4800);
          final pageImage = await page.render(width: renderWidth, height: renderHeight);

          if (pageImage != null) {
            final imagePath = '${tempDir.path}${Platform.pathSeparator}ocr_highres_page_$i.png';

            final uiImage = await pageImage.createImage();
            final byteData = await uiImage.toByteData(format: ImageByteFormat.png);
            if (byteData != null) {
              final buffer = byteData.buffer.asUint8List();
              await File(imagePath).writeAsBytes(buffer);

              final inputImage = InputImage.fromFilePath(imagePath);
              final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

              _recognizedPages[i] = recognizedText;
              String pageText = recognizedText.text.trim();

              if (pageText.isEmpty) {
                final pdfPageText = await page.loadText();
                pageText = pdfPageText.fullText.trim();
              }

              _pageTextControllers[i] = TextEditingController(text: pageText);
              fullTextBuffer.writeln('=== PAGE ${i + 1} OF $_totalPages ===');
              fullTextBuffer.writeln(pageText);
              fullTextBuffer.writeln();
            }
          }
        } catch (_) {
          _pageTextControllers[i] = TextEditingController(text: '[OCR extraction failed for this page]');
        }
      }

      await textRecognizer.close();
      await pdfDoc.dispose();

      _combinedText = fullTextBuffer.toString();
      _fullTextController.text = _combinedText;

      await _deleteTempFile();
      _tempTextFile = File('${tempDir.path}${Platform.pathSeparator}temp_ocr_${DateTime.now().millisecondsSinceEpoch}.txt');
      await _tempTextFile!.writeAsString(_combinedText);

      await DatabaseHelper.instance.updateExtractedText(_selectedFile!.path, _combinedText);
      ref.read(pdfListProvider.notifier).loadFiles();

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _showNotice('OCR Process error: $e');
      }
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

  Future<void> _updateTempFileContent(String updatedText) async {
    _combinedText = updatedText;
    if (_tempTextFile != null) {
      try {
        await _tempTextFile!.writeAsString(updatedText);
      } catch (_) {}
    }
  }

  Future<void> _exportAsTxt() async {
    if (_selectedFile == null) return;
    try {
      final parentDir = File(_selectedFile!.path).parent.path;
      final txtPath = '$parentDir${Platform.pathSeparator}${_selectedFile!.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '.txt')}';
      await File(txtPath).writeAsString(_fullTextController.text);
      if (!mounted) return;
      _showNotice('Exported to ${txtPath.split(Platform.pathSeparator).last}');
    } catch (e) {
      if (!mounted) return;
      _showNotice('Failed to export .txt: $e');
    }
  }

  Future<void> _exportSearchablePdf() async {
    if (_selectedFile == null) return;
    try {
      final parentDir = File(_selectedFile!.path).parent.path;
      final targetPath = '$parentDir${Platform.pathSeparator}${_selectedFile!.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '_searchable.pdf')}';

      final pdfDoc = sf.PdfDocument();
      final font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 10);
      final tempDir = await getTemporaryDirectory();

      for (int i = 0; i < _totalPages; i++) {
        final page = pdfDoc.pages.add();
        final imagePath = '${tempDir.path}${Platform.pathSeparator}ocr_highres_page_$i.png';
        final imageFile = File(imagePath);

        if (imageFile.existsSync()) {
          final bitmap = sf.PdfBitmap(imageFile.readAsBytesSync());
          final pageSize = page.getClientSize();

          page.graphics.drawImage(bitmap, Rect.fromLTWH(0, 0, pageSize.width, pageSize.height));

          final recognized = _recognizedPages[i];
          if (recognized != null) {
            final scaleX = pageSize.width / 2400.0;
            final scaleY = pageSize.height / 3200.0;
            for (final block in recognized.blocks) {
              for (final line in block.lines) {
                final rect = line.boundingBox;
                page.graphics.drawString(
                  line.text,
                  font,
                  brush: sf.PdfBrushes.transparent,
                  bounds: Rect.fromLTWH(
                    rect.left * scaleX,
                    rect.top * scaleY,
                    rect.width * scaleX,
                    rect.height * scaleY,
                  ),
                );
              }
            }
          }
        }
      }

      final bytes = await pdfDoc.save();
      pdfDoc.dispose();

      await File(targetPath).writeAsBytes(bytes);

      final registered = await PdfMetadataHelper.registerAndSyncPdf(targetPath);
      if (registered != null) {
        ref.read(pdfListProvider.notifier).addFile(registered);
      }

      if (!mounted) return;
      _showNotice('Searchable PDF committed to ${targetPath.split(Platform.pathSeparator).last}');
    } catch (e) {
      if (!mounted) return;
      _showNotice('Failed to export Searchable PDF: $e');
    }
  }

  Future<void> _pickFile() async {
    final result = await Navigator.push<List<PdfFile>>(
      context,
      MaterialPageRoute(
        builder: (_) => const PdfToolFilePickerScreen(
          title: 'Select PDF for OCR Extraction',
          mode: ToolPickerMode.singleSelect,
          actionButtonText: 'CONFIRM DOCUMENT',
        ),
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _selectedFile = result.first;
      });
      _startOcrProcess();
    }
  }

  List<String> _extractFormulas() {
    final text = _fullTextController.text;
    final List<String> formulas = [];
    final regExp = RegExp(r'(\$\$.*?\$\$|\$.*?\$|\\\[.*?\\\]|\\\(.*?\\\)|\b[A-Za-z]\s*=\s*[^;\n]+)', dotAll: true);
    for (final match in regExp.allMatches(text)) {
      final matchStr = match.group(0)?.trim() ?? '';
      if (matchStr.length > 3 && !formulas.contains(matchStr)) {
        formulas.add(matchStr);
      }
    }
    return formulas;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            const EditorialEyebrow(text: 'OPTICAL RECOGNITION'),
            Text(
              'OCR & Text Extraction',
              style: EditorialTokens.titleMedium(
                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
              ),
            ),
          ],
        ),
        actions: [
          if (_fullTextController.text.isNotEmpty && !_isProcessing) ...[
            IconButton(
              icon: Icon(
                Icons.copy,
                size: 20,
                color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _fullTextController.text));
                _showNotice('All extracted OCR text copied to clipboard');
              },
              tooltip: 'Copy all text',
            ),
            IconButton(
              icon: Icon(
                Icons.share_outlined,
                size: 20,
                color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
              ),
              onPressed: () {
                Share.share(_fullTextController.text, subject: 'Extracted OCR Text');
              },
              tooltip: 'Share text',
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
            height: EditorialTokens.hairline,
          ),
        ),
      ),
      body: _isProcessing
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: EditorialTokens.primary,
                    ),
                    const SizedBox(height: 24),
                    const EditorialEyebrow(text: 'OPTICAL CHARACTER RECOGNITION'),
                    const SizedBox(height: 8),
                    Text(
                      'Processing Page $_currentPage of $_totalPages',
                      style: EditorialTokens.titleMedium(
                        color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'High-resolution 300 DPI neural extraction in progress...',
                      style: EditorialTokens.bodySmall(
                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : _selectedFile == null
              ? Center(
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
                          Icon(
                            Icons.text_snippet_outlined,
                            size: 48,
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Select PDF for Optical Extraction',
                            style: EditorialTokens.headlineSmall(
                              color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Extract raw copyable text, isolate mathematical formulas, or compile a transparent searchable PDF layer.',
                            style: EditorialTokens.bodySmall(
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          EditorialButton(
                            label: 'SELECT PDF DOCUMENT',
                            icon: Icons.folder_open,
                            onPressed: _pickFile,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Sub-strip: active file info & view switcher
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                        border: Border(
                          bottom: BorderSide(
                            color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                            width: EditorialTokens.hairline,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedFile!.name.toUpperCase(),
                              style: EditorialTokens.metadataStrong(
                                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${Utils.formatBytes(_selectedFile!.sizeBytes)} · $_totalPages PAGES',
                            style: EditorialTokens.metadata(
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // View Mode Tabs
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          EditorialChip(
                            label: 'Extracted Text',
                            selected: _activeViewIndex == 0,
                            onTap: () => setState(() => _activeViewIndex = 0),
                          ),
                          const SizedBox(width: 8),
                          EditorialChip(
                            label: 'Page Breakdown',
                            selected: _activeViewIndex == 1,
                            onTap: () => setState(() => _activeViewIndex = 1),
                          ),
                          const SizedBox(width: 8),
                          EditorialChip(
                            label: 'Formula Index',
                            selected: _activeViewIndex == 2,
                            onTap: () => setState(() => _activeViewIndex = 2),
                          ),
                        ],
                      ),
                    ),

                    // Active View Content
                    Expanded(
                      child: IndexedStack(
                        index: _activeViewIndex,
                        children: [
                          // Tab 0: Full Text Editor
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: Container(
                              decoration: BoxDecoration(
                                color: EditorialTokens.paper,
                                borderRadius: BorderRadius.circular(EditorialTokens.r4),
                                border: Border.all(
                                  color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                                  width: EditorialTokens.hairline,
                                ),
                              ),
                              child: TextField(
                                controller: _fullTextController,
                                maxLines: null,
                                expands: true,
                                style: const TextStyle(
                                  fontFamily: EditorialTokens.monoFamily,
                                  fontSize: 13,
                                  height: 1.5,
                                  color: EditorialTokens.ink,
                                ),
                                onChanged: _updateTempFileContent,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.all(16),
                                  border: InputBorder.none,
                                  hintText: 'Extracted text will appear here. Edit or copy freely...',
                                  hintStyle: EditorialTokens.bodySmall(color: EditorialTokens.inkMuted),
                                ),
                              ),
                            ),
                          ),

                          // Tab 1: Page-by-Page Breakdown
                          _pageTextControllers.isEmpty
                              ? Center(
                                  child: Text(
                                    'No individual page data available.',
                                    style: EditorialTokens.bodySmall(
                                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  itemCount: _pageTextControllers.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    return Container(
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
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                                                  width: EditorialTokens.hairline,
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                EditorialEyebrow(
                                                  text: 'PAGE ${index + 1} OF $_totalPages',
                                                  color: EditorialTokens.primary,
                                                ),
                                                const Spacer(),
                                                InkWell(
                                                  onTap: () {
                                                    Clipboard.setData(ClipboardData(text: _pageTextControllers[index]?.text ?? ''));
                                                    _showNotice('Page ${index + 1} copied to clipboard');
                                                  },
                                                  child: Text(
                                                    'COPY',
                                                    style: EditorialTokens.metadataStrong(color: EditorialTokens.primary),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: TextField(
                                              controller: _pageTextControllers[index],
                                              maxLines: null,
                                              style: TextStyle(
                                                fontFamily: EditorialTokens.monoFamily,
                                                fontSize: 12.5,
                                                height: 1.45,
                                                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                              ),
                                              decoration: const InputDecoration(
                                                border: InputBorder.none,
                                                isDense: true,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),

                          // Tab 2: Formula Index
                          Builder(
                            builder: (context) {
                              final formulas = _extractFormulas();
                              if (formulas.isEmpty) {
                                return Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.functions_outlined,
                                        size: 40,
                                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No isolated mathematical formulas found.',
                                        style: EditorialTokens.titleSmall(
                                          color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Extracted text contains primarily prose content.',
                                        style: EditorialTokens.bodySmall(
                                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                itemCount: formulas.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final formula = formulas[index];
                                  return Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                                      border: Border.all(
                                        color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                                        width: EditorialTokens.hairline,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: EditorialTokens.tertiary.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(EditorialTokens.r2),
                                          ),
                                          child: Text(
                                            'MATH',
                                            style: EditorialTokens.metadataStrong(color: EditorialTokens.tertiary).copyWith(fontSize: 9),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            formula,
                                            style: const TextStyle(
                                              fontFamily: EditorialTokens.monoFamily,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.copy, size: 16),
                                          onPressed: () {
                                            Clipboard.setData(ClipboardData(text: formula));
                                            _showNotice('Formula copied: $formula');
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // Quiet Action Dock
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
                              label: 'EXPORT .TXT',
                              icon: Icons.save_alt_outlined,
                              onPressed: _exportAsTxt,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: EditorialButton(
                              label: 'SEARCHABLE PDF',
                              icon: Icons.picture_as_pdf_outlined,
                              onPressed: _exportSearchablePdf,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
