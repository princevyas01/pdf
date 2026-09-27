import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../core/storage/pdf_metadata_helper.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../core/utils/utils.dart';
import '../../models/pdf_file.dart';
import '../../widgets/editorial_components.dart';
import '../../widgets/pdf_tool_file_picker_screen.dart';
import '../home/pdf_list_provider.dart';
import '../viewer/pdf_viewer_screen.dart';

class MergeScreen extends ConsumerStatefulWidget {
  final PdfFile? initialFile;

  const MergeScreen({super.key, this.initialFile});

  @override
  ConsumerState<MergeScreen> createState() => _MergeScreenState();
}

class _MergeScreenState extends ConsumerState<MergeScreen> {
  final List<PdfFile> _selectedFiles = [];
  final TextEditingController _fileNameController = TextEditingController();

  bool _isMerging = false;
  double _progress = 0.0;
  String? _outputFilePath;

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      _selectedFiles.add(widget.initialFile!);
    }
    final nowStr = DateTime.now().millisecondsSinceEpoch;
    _fileNameController.text = 'Merged_Document_$nowStr.pdf';
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  Future<void> _openFilePicker() async {
    final result = await Navigator.push<List<PdfFile>>(
      context,
      MaterialPageRoute(
        builder: (_) => PdfToolFilePickerScreen(
          title: 'Select PDF Documents to Merge',
          mode: ToolPickerMode.multiSelect,
          initialSelectedFiles: _selectedFiles,
          actionButtonText: 'CONFIRM SELECTION',
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _selectedFiles.clear();
        _selectedFiles.addAll(result);
      });
    }
  }

  Future<void> _performMerge() async {
    if (_selectedFiles.length < 2) {
      _showNotice('Please select at least 2 PDF documents to merge.');
      return;
    }

    final outputName = _fileNameController.text.trim();
    if (outputName.isEmpty) {
      _showNotice('Please provide an output filename.');
      return;
    }

    setState(() {
      _isMerging = true;
      _progress = 0.1;
    });

    try {
      final parentDir = File(_selectedFiles.first.path).parent.path;
      final targetPath = '$parentDir${Platform.pathSeparator}$outputName';

      final outputDocument = sf.PdfDocument();
      int processedCount = 0;

      for (final file in _selectedFiles) {
        try {
          final bytes = await File(file.path).readAsBytes();
          final inputDoc = sf.PdfDocument(inputBytes: bytes);

          for (int i = 0; i < inputDoc.pages.count; i++) {
            final template = inputDoc.pages[i].createTemplate();
            final newPage = outputDocument.pages.add();
            newPage.graphics.drawPdfTemplate(template, const Offset(0, 0));
          }
          inputDoc.dispose();
        } catch (_) {}

        processedCount++;
        setState(() {
          _progress = processedCount / _selectedFiles.length;
        });
      }

      final savedBytes = await outputDocument.save();
      outputDocument.dispose();

      final outputFile = File(targetPath);
      await outputFile.writeAsBytes(savedBytes);

      final registered = await PdfMetadataHelper.registerAndSyncPdf(targetPath);
      if (registered != null) {
        ref.read(pdfListProvider.notifier).addFile(registered);
      }

      setState(() {
        _isMerging = false;
        _outputFilePath = targetPath;
      });
    } catch (e) {
      setState(() => _isMerging = false);
      if (!mounted) return;
      _showNotice('Error merging documents: $e');
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

  int get _totalPageCount {
    return _selectedFiles.fold(0, (sum, f) => sum + f.pageCount);
  }

  int get _totalSizeBytes {
    return _selectedFiles.fold(0, (sum, f) => sum + f.sizeBytes);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_outputFilePath != null) {
      final file = File(_outputFilePath!);
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
              const EditorialEyebrow(text: 'MERGE COMPLETE'),
              Text(
                'Documents Merged',
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
                      Icons.layers,
                      size: 28,
                      color: EditorialTokens.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Merged PDF Saved',
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
                    '${Utils.formatBytes(size)} · $_totalPageCount Total Pages',
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
                      label: 'OPEN MERGED PDF',
                      icon: Icons.menu_book_outlined,
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PdfViewerScreen(filePath: _outputFilePath!),
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
                          label: 'SHARE PDF',
                          icon: Icons.share_outlined,
                          onPressed: () {
                            Share.shareXFiles([XFile(_outputFilePath!)]);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: EditorialSecondaryButton(
                          label: 'DONE',
                          onPressed: () => Navigator.pop(context),
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
            const EditorialEyebrow(text: 'DOCUMENT MERGE'),
            Text(
              'Merge Documents',
              style: EditorialTokens.titleMedium(
                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.add,
              size: 22,
              color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
            ),
            onPressed: _openFilePicker,
            tooltip: 'Add documents',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
            height: EditorialTokens.hairline,
          ),
        ),
      ),
      body: _isMerging
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
                    const EditorialEyebrow(text: 'MERGING DOCUMENTS'),
                    const SizedBox(height: 8),
                    Text(
                      'Merging Documents... ${(_progress * 100).round()}%',
                      style: EditorialTokens.titleMedium(
                        color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Combining pages and saving PDF',
                      style: EditorialTokens.bodySmall(
                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // Sequence summary sub-strip
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
                      Text(
                        'DOCUMENT SEQUENCE',
                        style: EditorialTokens.eyebrow(color: EditorialTokens.primary),
                      ),
                      const Spacer(),
                      Text(
                        '${_selectedFiles.length} FILES · $_totalPageCount PAGES · ${Utils.formatBytes(_totalSizeBytes)}',
                        style: EditorialTokens.metadata(
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Volume output name input
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _fileNameController,
                    style: EditorialTokens.bodyMedium(
                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                    ),
                    decoration: InputDecoration(
                      labelText: 'OUTPUT FILENAME',
                      labelStyle: EditorialTokens.metadataStrong(
                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      ),
                      filled: true,
                      fillColor: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                ),

                // Document Sequence list
                Expanded(
                  child: _selectedFiles.isEmpty
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
                                    Icons.layers_outlined,
                                    size: 48,
                                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No Documents Added Yet',
                                    style: EditorialTokens.headlineSmall(
                                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Select two or more PDF files to combine them into a single document.',
                                    style: EditorialTokens.bodySmall(
                                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  EditorialButton(
                                    label: 'SELECT DOCUMENTS',
                                    icon: Icons.folder_open,
                                    onPressed: _openFilePicker,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _selectedFiles.length,
                          onReorder: (oldIdx, newIdx) {
                            setState(() {
                              if (newIdx > oldIdx) newIdx -= 1;
                              final item = _selectedFiles.removeAt(oldIdx);
                              _selectedFiles.insert(newIdx, item);
                            });
                          },
                          itemBuilder: (context, index) {
                            final file = _selectedFiles[index];
                            final seqNum = (index + 1).toString().padLeft(2, '0');

                            return Container(
                              key: ValueKey(file.path),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                                borderRadius: BorderRadius.circular(EditorialTokens.r4),
                                border: Border.all(
                                  color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                                  width: EditorialTokens.hairline,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      seqNum,
                                      style: EditorialTokens.eyebrow(color: EditorialTokens.primary).copyWith(fontSize: 12),
                                    ),
                                    const SizedBox(width: 10),
                                    const EditorialPaperThumbnail(
                                      thumbnailPath: null,
                                      width: 32,
                                      height: 44,
                                    ),
                                  ],
                                ),
                                title: Text(
                                  file.name,
                                  style: EditorialTokens.titleSmall(
                                    color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${file.pageCount} Pages · ${Utils.formatBytes(file.sizeBytes)}',
                                  style: EditorialTokens.metadata(
                                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.close,
                                        size: 18,
                                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _selectedFiles.removeAt(index);
                                        });
                                      },
                                    ),
                                    Icon(
                                      Icons.drag_indicator,
                                      size: 20,
                                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Docked Merge Action
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
                          label: 'ADD DOCUMENT',
                          icon: Icons.add,
                          onPressed: _openFilePicker,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: EditorialButton(
                          label: 'MERGE DOCUMENTS',
                          icon: Icons.layers_outlined,
                          onPressed: _selectedFiles.length >= 2 ? _performMerge : null,
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
