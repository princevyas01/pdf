import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../core/storage/database_helper.dart';
import '../../core/storage/pdf_metadata_helper.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../core/utils/utils.dart';
import '../../models/annotation_meta.dart';
import '../../models/pdf_file.dart';
import '../../widgets/editorial_components.dart';
import '../../widgets/pdf_tool_file_picker_screen.dart';
import '../home/pdf_list_provider.dart';
import '../viewer/pdf_viewer_screen.dart';

enum SplitMethod { ranges, singlePages, everyNPages }

class SplitScreen extends ConsumerStatefulWidget {
  final PdfFile? sourceFile;

  const SplitScreen({super.key, this.sourceFile});

  @override
  ConsumerState<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends ConsumerState<SplitScreen> {
  PdfFile? _selectedFile;
  SplitMethod _method = SplitMethod.ranges;

  final TextEditingController _rangeController = TextEditingController(text: '1-2');
  final TextEditingController _everyNController = TextEditingController(text: '2');
  final TextEditingController _prefixController = TextEditingController();

  bool _isSplitting = false;
  List<String> _createdFilePaths = [];

  bool _extractAsSingleCompiled = true;
  bool _preserveBookmarks = true;
  bool _retainAnnotations = true;

  List<String> _getRangeSegments() {
    final raw = _rangeController.text.trim();
    if (raw.isEmpty) return [];
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  @override
  void initState() {
    super.initState();
    _selectedFile = widget.sourceFile;
    if (_selectedFile != null) {
      _prefixController.text = _selectedFile!.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
    }
  }

  @override
  void dispose() {
    _rangeController.dispose();
    _everyNController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await Navigator.push<List<PdfFile>>(
      context,
      MaterialPageRoute(
        builder: (_) => const PdfToolFilePickerScreen(
          title: 'Select PDF to Split',
          mode: ToolPickerMode.singleSelect,
          actionButtonText: 'CONFIRM DOCUMENT',
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      final file = result.first;
      setState(() {
        _selectedFile = file;
        _prefixController.text = file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
      });
    }
  }

  Future<void> _performSplit() async {
    if (_selectedFile == null) {
      _showNotice('Please select a PDF document first.');
      return;
    }

    final prefix = _prefixController.text.trim();
    if (prefix.isEmpty) {
      _showNotice('Please specify an output filename prefix.');
      return;
    }

    setState(() {
      _isSplitting = true;
    });

    try {
      final sourceBytes = await File(_selectedFile!.path).readAsBytes();
      final sourceDoc = PdfDocument(inputBytes: sourceBytes);
      final totalPages = sourceDoc.pages.count;
      final parentDir = File(_selectedFile!.path).parent.path;

      final List<String> newFiles = [];

      if (_method == SplitMethod.ranges) {
        final rawRanges = _rangeController.text.trim();
        final segments = _getRangeSegments();

        if (_extractAsSingleCompiled) {
          final pagesToExtract = Utils.parsePageRanges(rawRanges, totalPages);
          if (pagesToExtract.isNotEmpty) {
            final outDoc = PdfDocument();
            for (final pageNum in pagesToExtract) {
              final template = sourceDoc.pages[pageNum - 1].createTemplate();
              final newPage = outDoc.pages.add();
              newPage.graphics.drawPdfTemplate(template, const Offset(0, 0));
            }
            if (_preserveBookmarks && sourceDoc.bookmarks.count > 0) {
              for (int b = 0; b < sourceDoc.bookmarks.count; b++) {
                final srcBm = sourceDoc.bookmarks[b];
                outDoc.bookmarks.add(srcBm.title);
              }
            }
            final targetPath = '$parentDir${Platform.pathSeparator}${prefix}_extracted.pdf';
            await File(targetPath).writeAsBytes(await outDoc.save());
            outDoc.dispose();
            newFiles.add(targetPath);
          }
        } else {
          int partIdx = 1;
          for (final seg in segments) {
            final segPages = Utils.parsePageRanges(seg, totalPages);
            if (segPages.isNotEmpty) {
              final outDoc = PdfDocument();
              for (final pageNum in segPages) {
                final template = sourceDoc.pages[pageNum - 1].createTemplate();
                final newPage = outDoc.pages.add();
                newPage.graphics.drawPdfTemplate(template, const Offset(0, 0));
              }
              final cleanSeg = seg.replaceAll(' ', '').replaceAll('-', '_');
              final targetPath = '$parentDir${Platform.pathSeparator}${prefix}_part_${partIdx}_pp$cleanSeg.pdf';
              await File(targetPath).writeAsBytes(await outDoc.save());
              outDoc.dispose();
              newFiles.add(targetPath);
              partIdx++;
            }
          }
        }
      } else if (_method == SplitMethod.singlePages) {
        for (int i = 0; i < totalPages; i++) {
          final outDoc = PdfDocument();
          final template = sourceDoc.pages[i].createTemplate();
          final newPage = outDoc.pages.add();
          newPage.graphics.drawPdfTemplate(template, const Offset(0, 0));

          final targetPath = '$parentDir${Platform.pathSeparator}${prefix}_page_${i + 1}.pdf';
          await File(targetPath).writeAsBytes(await outDoc.save());
          outDoc.dispose();
          newFiles.add(targetPath);
        }
      } else if (_method == SplitMethod.everyNPages) {
        final n = int.tryParse(_everyNController.text.trim()) ?? 1;
        int partIndex = 1;
        for (int i = 0; i < totalPages; i += n) {
          final outDoc = PdfDocument();
          final end = (i + n < totalPages) ? i + n : totalPages;
          for (int j = i; j < end; j++) {
            final template = sourceDoc.pages[j].createTemplate();
            final newPage = outDoc.pages.add();
            newPage.graphics.drawPdfTemplate(template, const Offset(0, 0));
          }
          final targetPath = '$parentDir${Platform.pathSeparator}${prefix}_part_$partIndex.pdf';
          await File(targetPath).writeAsBytes(await outDoc.save());
          outDoc.dispose();
          newFiles.add(targetPath);
          partIndex++;
        }
      }

      sourceDoc.dispose();

      if (_retainAnnotations && _selectedFile != null) {
        final sourceNotes = await DatabaseHelper.instance.getNotesForFile(_selectedFile!.path);
        for (final newPath in newFiles) {
          for (final n in sourceNotes) {
            await DatabaseHelper.instance.addNote(PdfNote(
              filePath: newPath,
              pageNumber: n.pageNumber,
              noteText: n.noteText,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ));
          }
        }
      }

      for (final p in newFiles) {
        final registered = await PdfMetadataHelper.registerAndSyncPdf(p);
        if (registered != null) {
          ref.read(pdfListProvider.notifier).addFile(registered);
        }
      }

      setState(() {
        _isSplitting = false;
        _createdFilePaths = newFiles;
      });
    } catch (e) {
      setState(() => _isSplitting = false);
      if (!mounted) return;
      _showNotice('Error splitting document: $e');
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_createdFilePaths.isNotEmpty) {
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
              const EditorialEyebrow(text: 'SPLIT COMPLETE'),
              Text(
                'Pages Extracted',
                style: EditorialTokens.titleMedium(
                  color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
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
                  const EditorialEyebrow(text: 'EXTRACTED FILES'),
                  const Spacer(),
                  Text(
                    '${_createdFilePaths.length} NEW DOCUMENTS CREATED',
                    style: EditorialTokens.metadata(
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _createdFilePaths.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final path = _createdFilePaths[index];
                  final name = path.split(Platform.pathSeparator).last;
                  final file = File(path);
                  final size = file.existsSync() ? file.lengthSync() : 0;
                  final seqNum = (index + 1).toString().padLeft(2, '0');

                  return Container(
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
                        name,
                        style: EditorialTokens.titleSmall(
                          color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        Utils.formatBytes(size),
                        style: EditorialTokens.metadata(
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.share_outlined,
                              size: 18,
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ),
                            onPressed: () => Share.shareXFiles([XFile(path)]),
                            tooltip: 'Share',
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.menu_book_outlined,
                              size: 18,
                              color: EditorialTokens.primary,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PdfViewerScreen(filePath: path),
                                ),
                              );
                            },
                            tooltip: 'Open in Viewer',
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
              child: SizedBox(
                width: double.infinity,
                child: EditorialButton(
                  label: 'DONE',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
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
            const EditorialEyebrow(text: 'DOCUMENT SPLIT'),
            Text(
              'Split & Extract Pages',
              style: EditorialTokens.titleMedium(
                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
            height: EditorialTokens.hairline,
          ),
        ),
      ),
      body: _isSplitting
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
                    const EditorialEyebrow(text: 'SPLITTING DOCUMENT'),
                    const SizedBox(height: 8),
                    Text(
                      'Extracting Pages...',
                      style: EditorialTokens.titleMedium(
                        color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Creating documents and saving to storage',
                      style: EditorialTokens.bodySmall(
                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              children: [
                // Section 01: Active Document Card
                const EditorialSectionHeader(
                  number: '01',
                  label: 'Source Document',
                ),
                const SizedBox(height: 8),
                if (_selectedFile != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
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
                        const EditorialPaperThumbnail(
                          thumbnailPath: null,
                          width: 44,
                          height: 60,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedFile!.name,
                                style: EditorialTokens.titleSmall(
                                  color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_selectedFile!.pageCount} Pages · ${Utils.formatBytes(_selectedFile!.sizeBytes)}',
                                style: EditorialTokens.metadata(
                                  color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.swap_horiz,
                            size: 20,
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ),
                          onPressed: _pickFile,
                          tooltip: 'Change document',
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                      border: Border.all(
                        color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                        width: EditorialTokens.hairline,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.call_split_outlined,
                          size: 36,
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No document selected',
                          style: EditorialTokens.titleSmall(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choose a PDF to split by page range or extract pages',
                          style: EditorialTokens.bodySmall(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        EditorialSecondaryButton(
                          label: 'CHOOSE DOCUMENT',
                          icon: Icons.folder_open,
                          onPressed: _pickFile,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Section 02: Extraction Method Protocol
                const EditorialSectionHeader(
                  number: '02',
                  label: 'Split Method',
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      EditorialChip(
                        label: 'Page Ranges',
                        selected: _method == SplitMethod.ranges,
                        onTap: () => setState(() => _method = SplitMethod.ranges),
                      ),
                      const SizedBox(width: 8),
                      EditorialChip(
                        label: 'Single Pages',
                        selected: _method == SplitMethod.singlePages,
                        onTap: () => setState(() => _method = SplitMethod.singlePages),
                      ),
                      const SizedBox(width: 8),
                      EditorialChip(
                        label: 'Every N Pages',
                        selected: _method == SplitMethod.everyNPages,
                        onTap: () => setState(() => _method = SplitMethod.everyNPages),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Section 03: Parameters
                const EditorialSectionHeader(
                  number: '03',
                  label: 'Range & Output Settings',
                ),
                const SizedBox(height: 8),
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
                      if (_method == SplitMethod.ranges) ...[
                        Text(
                          'PAGE RANGE SPECIFICATION (e.g. 1-5, 8, 12-15)',
                          style: EditorialTokens.metadataStrong(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ).copyWith(fontSize: 10),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _rangeController,
                          onChanged: (_) => setState(() {}),
                          style: EditorialTokens.bodyMedium(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ),
                          decoration: InputDecoration(
                            hintText: '1-5, 8',
                            hintStyle: EditorialTokens.bodySmall(
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ),
                            filled: true,
                            fillColor: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(EditorialTokens.r4),
                              borderSide: BorderSide(
                                color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                                width: EditorialTokens.hairline,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_getRangeSegments().isNotEmpty) ...[
                          Text(
                            'PARSED SEQUENCE PREVIEW',
                            style: EditorialTokens.eyebrow(color: EditorialTokens.primary).copyWith(fontSize: 9),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: _getRangeSegments().asMap().entries.map((e) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: EditorialTokens.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(EditorialTokens.r2),
                                  border: Border.all(
                                    color: EditorialTokens.primary.withOpacity(0.3),
                                    width: EditorialTokens.hairline,
                                  ),
                                ),
                                child: Text(
                                  'Part ${e.key + 1}: pp. ${e.value}',
                                  style: EditorialTokens.metadata(color: EditorialTokens.primary).copyWith(fontSize: 10),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 14),
                      ],
                      if (_method == SplitMethod.everyNPages) ...[
                        Text(
                          'PAGES PER FILE (N)',
                          style: EditorialTokens.metadataStrong(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ).copyWith(fontSize: 10),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _everyNController,
                          keyboardType: TextInputType.number,
                          style: EditorialTokens.bodyMedium(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ),
                          decoration: InputDecoration(
                            hintText: '2',
                            filled: true,
                            fillColor: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(EditorialTokens.r4),
                              borderSide: BorderSide(
                                color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                                width: EditorialTokens.hairline,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      Text(
                        'OUTPUT FILENAME PREFIX',
                        style: EditorialTokens.metadataStrong(
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                        ).copyWith(fontSize: 10),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _prefixController,
                        style: EditorialTokens.bodyMedium(
                          color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Document_Prefix',
                          filled: true,
                          fillColor: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(EditorialTokens.r4),
                            borderSide: BorderSide(
                              color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                              width: EditorialTokens.hairline,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const EditorialDivider(),
                      const SizedBox(height: 10),
                      Text(
                        'EXTRACTION FIDELITY PROTOCOLS',
                        style: EditorialTokens.eyebrow(
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                        ).copyWith(fontSize: 10),
                      ),
                      const SizedBox(height: 6),
                      if (_method == SplitMethod.ranges)
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Compile into Single Document',
                            style: EditorialTokens.bodyMedium(
                              color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                            ).copyWith(fontSize: 12),
                          ),
                          subtitle: Text(
                            _extractAsSingleCompiled
                                ? 'All parsed ranges will be bound into one extracted PDF'
                                : 'Each range segment will generate an isolated discrete PDF',
                            style: EditorialTokens.metadata(
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ).copyWith(fontSize: 10),
                          ),
                          value: _extractAsSingleCompiled,
                          activeColor: EditorialTokens.primary,
                          onChanged: (v) => setState(() => _extractAsSingleCompiled = v),
                        ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Preserve Table of Contents & Outlines',
                          style: EditorialTokens.bodyMedium(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ).copyWith(fontSize: 12),
                        ),
                        subtitle: Text(
                          'Transfer navigational bookmarks into target extracted documents',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ).copyWith(fontSize: 10),
                        ),
                        value: _preserveBookmarks,
                        activeColor: EditorialTokens.primary,
                        onChanged: (v) => setState(() => _preserveBookmarks = v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Retain Marginalia & Notes',
                          style: EditorialTokens.bodyMedium(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ).copyWith(fontSize: 12),
                        ),
                        subtitle: Text(
                          'Mirror local marginalia annotations into generated file ledger',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ).copyWith(fontSize: 10),
                        ),
                        value: _retainAnnotations,
                        activeColor: EditorialTokens.primary,
                        onChanged: (v) => setState(() => _retainAnnotations = v),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Action Button
                SizedBox(
                  width: double.infinity,
                  child: EditorialButton(
                    label: 'SPLIT DOCUMENT',
                    icon: Icons.call_split_outlined,
                    onPressed: _selectedFile != null ? _performSplit : null,
                  ),
                ),
                const SizedBox(height: 24),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
