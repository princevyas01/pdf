import 'dart:async';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../core/storage/database_helper.dart';
import '../../core/tts/tts_service.dart';
import '../../core/utils/storage_location_helper.dart';
import '../../core/utils/utils.dart';
import '../../models/bookmark.dart';
import '../../models/annotation_meta.dart';
import '../../models/pdf_file.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../widgets/editorial_components.dart';
import '../ocr/ocr_screen.dart';
import '../study/study_mode_screen.dart';
import '../ai/doc_qa_screen.dart';
import '../ai/explain_text_dialog.dart';
import '../home/pdf_list_provider.dart';

enum MarkupAnnotationType { highlight, underline, strikethrough, squiggly }

class PdfViewerScreen extends ConsumerStatefulWidget {
  final String filePath;
  final bool isExternalLaunch;
  final int initialPage;
  final bool openAnnotationInspector;

  const PdfViewerScreen({
    super.key,
    required this.filePath,
    this.isExternalLaunch = false,
    this.initialPage = 1,
    this.openAnnotationInspector = false,
  });

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen>
    with WidgetsBindingObserver {
  late PdfViewerController _pdfViewerController;
  final TtsService _ttsService = TtsService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _currentPage = 1;
  int _totalPages = 0;
  int _initialPage = 1;
  int _rotationAngle = 0;
  bool _hasResumedPosition = false;

  bool _isSearchActive = false;
  bool _isTtsPlaying = false;
  bool _isTtsPaused = false;
  final double _ttsSpeechRate = 1.0;
  bool _isCorrupted = false;
  sf.PdfDocument? _ttsDocument;
  bool _ttsInitialized = false;

  final ValueNotifier<double> _zoomNotifier = ValueNotifier<double>(1.0);
  Timer? _progressDebounceTimer;

  final TextEditingController _searchFieldController = TextEditingController();
  PdfTextSearchResult _searchResult = PdfTextSearchResult();
  PdfTextSelectionChangedDetails? _lastTextSelectionDetails;
  bool _showSelectionMenu = false;
  bool _isAnnotationToolbarOpen = false;
  String _selectedAnnotationTool = 'chisel';
  String _selectedStrokeWidth = '1.0mm';
  Color _selectedAnnotationColor = EditorialTokens.primary;

  List<Bookmark> _userBookmarks = [];
  List<PdfNote> _pdfNotes = [];
  sf.PdfBookmarkBase? _docBookmarks;

  final Stopwatch _sessionStopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pdfViewerController = PdfViewerController();
    if (widget.initialPage > 1) {
      _initialPage = widget.initialPage;
      _currentPage = widget.initialPage;
    }
    _loadMetadataAndProgress();
    _sessionStopwatch.start();
    if (widget.openAnnotationInspector) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showAnnotationInspectorSheet();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionStopwatch.stop();
    _saveReadingSession();
    _progressDebounceTimer?.cancel();
    _flushReadingProgress();
    _ttsService.stop();
    _ttsService.dispose();
    _pdfViewerController.dispose();
    _searchFieldController.dispose();
    _ttsDocument?.dispose();
    _zoomNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _sessionStopwatch.stop();
      _saveReadingSession();
      _progressDebounceTimer?.cancel();
      _flushReadingProgress();
    } else if (state == AppLifecycleState.resumed) {
      _sessionStopwatch.start();
    }
  }

  Future<void> _saveReadingSession() async {
    final elapsedSec = _sessionStopwatch.elapsed.inSeconds;
    if (elapsedSec > 0) {
      await DatabaseHelper.instance.addReadingTime(widget.filePath, elapsedSec);
    }
  }

  Future<void> _loadMetadataAndProgress() async {
    final pdfFile = await DatabaseHelper.instance.getPdfFile(widget.filePath);
    final bookmarks =
        await DatabaseHelper.instance.getBookmarksForFile(widget.filePath);
    final notes =
        await DatabaseHelper.instance.getNotesForFile(widget.filePath);

    if (mounted) {
      setState(() {
        _userBookmarks = bookmarks;
        _pdfNotes = notes;
        if (widget.initialPage > 1) {
          _initialPage = widget.initialPage;
          _currentPage = widget.initialPage;
        } else if (pdfFile != null && pdfFile.lastOpenedPage > 1) {
          _initialPage = pdfFile.lastOpenedPage;
        }
      });
    }
    await DatabaseHelper.instance.updateLastOpened(widget.filePath);
  }

  void _handleBackNavigation() {
    _ttsService.stop();
    if (widget.isExternalLaunch) {
      SystemNavigator.pop();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      SystemNavigator.pop();
    }
  }

  void _updateProgress(int pageNumber) {
    if (_totalPages <= 0) return;
    _progressDebounceTimer?.cancel();
    _progressDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _flushReadingProgress();
    });
  }

  void _flushReadingProgress() {
    if (_totalPages <= 0) return;
    final double progress = (_currentPage / _totalPages).clamp(0.0, 1.0);
    final bool completed = progress >= 0.95 || _currentPage == _totalPages;

    DatabaseHelper.instance.updateReadingProgress(
      widget.filePath,
      page: _currentPage,
      progress: progress,
      completed: completed,
    );
  }

  void _rotateClockwise() {
    setState(() {
      _rotationAngle = (_rotationAngle + 90) % 360;
    });
  }

  Future<void> _ensureTtsInitialized() async {
    if (!_ttsInitialized) {
      await _ttsService.init();
      _ttsInitialized = true;
    }
  }

  Future<void> _sharePdf() async {
    try {
      final file = File(widget.filePath);
      if (await file.exists()) {
        final fileName = widget.filePath.split(Platform.pathSeparator).last;
        await Share.shareXFiles([XFile(widget.filePath)], text: 'Sharing $fileName');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing PDF: $e')),
      );
    }
  }

  Future<void> _saveToDevice() async {
    try {
      final sourceFile = File(widget.filePath);
      if (!await sourceFile.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Source file not found.')),
        );
        return;
      }

      final fileName = widget.filePath.split(Platform.pathSeparator).last;
      final targetDir = await StorageLocationHelper.getPublicDocumentsDirectory(subFolder: 'Saved');
      final targetPath = await StorageLocationHelper.getUniqueFilePath(targetDir, fileName);

      await sourceFile.copy(targetPath);

      // Register the saved document in index
      final stat = await File(targetPath).stat();
      final now = DateTime.now().millisecondsSinceEpoch;
      final docId = DateTime.now().microsecondsSinceEpoch.toRadixString(36) + targetPath.hashCode.toRadixString(36);

      final pdfFile = PdfFile(
        docId: docId,
        path: targetPath,
        name: targetPath.split(Platform.pathSeparator).last,
        sizeBytes: stat.size,
        modifiedAt: stat.modified.millisecondsSinceEpoch,
        pageCount: _totalPages,
        sourceType: 'saved',
        createdAt: now,
      );

      await DatabaseHelper.instance.upsertPdfFile(pdfFile);
      ref.read(pdfListProvider.notifier).addFile(pdfFile);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to: $targetPath'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving PDF: $e')),
      );
    }
  }

  void _showDocumentInfo() {
    final file = File(widget.filePath);
    final stat = file.existsSync() ? file.statSync() : null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Document Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${widget.filePath.split(Platform.pathSeparator).last}'),
            const SizedBox(height: 8),
            Text('Path: ${widget.filePath}'),
            const SizedBox(height: 8),
            Text('Total Pages: $_totalPages'),
            const SizedBox(height: 8),
            if (stat != null) ...[
              Text('Size: ${Utils.formatBytes(stat.size)}'),
              const SizedBox(height: 8),
              Text(
                  'Modified: ${Utils.formatDate(stat.modified.millisecondsSinceEpoch)}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSignatureDialog() {
    final SignatureController sigController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.transparent,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Freehand Drawing / Signature'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Signature(
                controller: sigController,
                backgroundColor: Colors.grey.shade100,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              sigController.clear();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (sigController.isNotEmpty) {
                final imageBytes = await sigController.toPngBytes();
                if (imageBytes != null) {
                  await _embedSignatureImage(imageBytes);
                }
              }
              sigController.dispose();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _embedSignatureImage(Uint8List imageBytes) async {
    try {
      final fileBytes = await File(widget.filePath).readAsBytes();
      final document = sf.PdfDocument(inputBytes: fileBytes);
      final page = document.pages[_currentPage - 1];

      final sf.PdfBitmap bitmap = sf.PdfBitmap(imageBytes);
      page.graphics.drawImage(bitmap, const Rect.fromLTWH(100, 100, 150, 75));

      final savedBytes = await document.save();
      document.dispose();

      await File(widget.filePath).writeAsBytes(savedBytes);

      await DatabaseHelper.instance.addNote(
        PdfNote(
          filePath: widget.filePath,
          pageNumber: _currentPage,
          noteText: '[SIGNATURE / DRAWING] Added to page $_currentPage',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      await _loadMetadataAndProgress();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Signature added to page $_currentPage')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding signature: $e')),
      );
    }
  }

  // --- Anchored Text Markup Annotations ---
  Future<void> _applyTextMarkupAnnotation(MarkupAnnotationType type) async {
    final details = _lastTextSelectionDetails;
    if (details == null ||
        details.selectedText == null ||
        details.selectedText!.trim().isEmpty) {
      return;
    }

    final selectedText = details.selectedText!.trim();

    try {
      final fileBytes = await File(widget.filePath).readAsBytes();
      final document = sf.PdfDocument(inputBytes: fileBytes);
      final page = document.pages[_currentPage - 1];

      final bounds = details.globalSelectedRegion ??
          const Rect.fromLTWH(100, 100, 200, 20);

      sf.PdfAnnotation annotation;
      Color annotationColor;

      switch (type) {
        case MarkupAnnotationType.highlight:
          annotationColor = Colors.yellow;
          annotation = sf.PdfRectangleAnnotation(bounds, 'Highlight')
            ..color = sf.PdfColor(255, 255, 0);
          break;
        case MarkupAnnotationType.underline:
          annotationColor = Colors.blue;
          annotation = sf.PdfLineAnnotation([
            bounds.left.toInt(),
            bounds.bottom.toInt(),
            bounds.right.toInt(),
            bounds.bottom.toInt()
          ], 'Underline')
            ..color = sf.PdfColor(0, 0, 255);
          break;
        case MarkupAnnotationType.strikethrough:
          annotationColor = Colors.red;
          final midY = (bounds.top + bounds.bottom) / 2;
          annotation = sf.PdfLineAnnotation([
            bounds.left.toInt(),
            midY.toInt(),
            bounds.right.toInt(),
            midY.toInt()
          ], 'Strikethrough')
            ..color = sf.PdfColor(255, 0, 0);
          break;
        case MarkupAnnotationType.squiggly:
          annotationColor = Colors.green;
          annotation = sf.PdfRectangleAnnotation(bounds, 'Squiggly')
            ..color = sf.PdfColor(0, 255, 0);
          break;
      }

      page.annotations.add(annotation);
      final savedBytes = await document.save();
      document.dispose();

      await File(widget.filePath).writeAsBytes(savedBytes);

      await DatabaseHelper.instance.addNote(
        PdfNote(
          filePath: widget.filePath,
          pageNumber: _currentPage,
          noteText: '[${type.name.toUpperCase()}] "$selectedText"',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      _pdfViewerController.clearSelection();
      setState(() => _showSelectionMenu = false);
      await _loadMetadataAndProgress();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('${type.name.toUpperCase()} added to page $_currentPage'),
          backgroundColor: annotationColor,
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving annotation: $e')),
      );
    }
  }

  void _handleCopyText() {
    final text = _lastTextSelectionDetails?.selectedText;
    if (text != null && text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      _pdfViewerController.clearSelection();
      setState(() => _showSelectionMenu = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Text copied to clipboard'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  // --- Read Aloud TTS Operations ---
  Future<void> _readAloudPage() async {
    await _ensureTtsInitialized();
    try {
      if (_ttsDocument == null) {
        final fileBytes = await File(widget.filePath).readAsBytes();
        _ttsDocument = sf.PdfDocument(inputBytes: fileBytes);
      }
      final extractor = sf.PdfTextExtractor(_ttsDocument!);
      final pageText = extractor.extractText(
          startPageIndex: _currentPage - 1, endPageIndex: _currentPage - 1);

      if (pageText.trim().isEmpty) {
        if (!mounted) return;
        _showImageBasedOcrPrompt();
        return;
      }

      setState(() {
        _isTtsPlaying = true;
        _isTtsPaused = false;
      });

      await _ttsService.setSpeechRate(_ttsSpeechRate);
      await _ttsService.speak(pageText, onCompletion: () {
        if (_currentPage < _totalPages) {
          _pdfViewerController.nextPage();
          _readAloudPage();
        } else {
          setState(() {
            _isTtsPlaying = false;
            _isTtsPaused = false;
          });
        }
      });
    } catch (_) {}
  }

  Future<void> _pauseTts() async {
    await _ttsService.pause();
    setState(() {
      _isTtsPlaying = false;
      _isTtsPaused = true;
    });
  }

  Future<void> _resumeTts() async {
    await _ttsService.resume();
    setState(() {
      _isTtsPlaying = true;
      _isTtsPaused = false;
    });
  }

  void _showImageBasedOcrPrompt() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
            'This document is image-based. Run OCR to enable text selection & reading.'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Run OCR',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OcrScreen(
                  sourceFile: PdfFile(
                    docId: DateTime.now().microsecondsSinceEpoch.toRadixString(36) + widget.filePath.hashCode.toRadixString(36),
                    path: widget.filePath,
                    name: widget.filePath.split(Platform.pathSeparator).last,
                    sizeBytes: File(widget.filePath).existsSync()
                        ? File(widget.filePath).lengthSync()
                        : 0,
                    modifiedAt: DateTime.now().millisecondsSinceEpoch,
                    pageCount: _totalPages,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // --- End Drawer with Outline, Bookmarks & Annotations ---
  Widget _buildDrawer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      backgroundColor: isDark ? EditorialTokens.darkSurface : EditorialTokens.surfaceStrong,
      child: DefaultTabController(
        length: 3,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const EditorialEyebrow(
                      text: 'DOCUMENT NAVIGATION',
                      color: EditorialTokens.primary,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Outline & Bookmarks',
                      style: EditorialTokens.displayMedium(
                        color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                      ).copyWith(fontSize: 17),
                    ),
                  ],
                ),
              ),
              TabBar(
                labelColor: EditorialTokens.primary,
                unselectedLabelColor: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                indicatorColor: EditorialTokens.primary,
                indicatorWeight: 2,
                labelStyle: EditorialTokens.label(color: EditorialTokens.primary).copyWith(fontSize: 11),
                unselectedLabelStyle: EditorialTokens.label().copyWith(fontSize: 11),
                tabs: const [
                  Tab(text: 'OUTLINE'),
                  Tab(text: 'BOOKMARKS'),
                  Tab(text: 'NOTES'),
                ],
              ),
              const EditorialDivider(),
              Expanded(
                child: TabBarView(
                  children: [
                    // Outline Tab
                    _docBookmarks == null || _docBookmarks!.count == 0
                        ? Center(
                            child: Text(
                              'No document outline available.',
                              style: EditorialTokens.bodySmall(
                                color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _docBookmarks!.count,
                            separatorBuilder: (_, __) => const EditorialDivider(),
                            itemBuilder: (context, index) {
                              final bm = _docBookmarks![index];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.bookmark_outline,
                                  size: 16,
                                  color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                ),
                                title: Text(
                                  bm.title,
                                  style: EditorialTokens.bodySmall(
                                    color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                  ),
                                ),
                                onTap: () => Navigator.pop(context),
                              );
                            },
                          ),

                    // Bookmarks Tab
                    Column(
                      children: [
                        InkWell(
                          onTap: _addUserBookmark,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                            child: Row(
                              children: [
                                const Icon(Icons.bookmark_add_outlined, size: 16, color: EditorialTokens.primary),
                                const SizedBox(width: 8),
                                Text(
                                  '+ Add Bookmark (Page $_currentPage)',
                                  style: EditorialTokens.label(color: EditorialTokens.primary).copyWith(fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const EditorialDivider(),
                        Expanded(
                          child: _userBookmarks.isEmpty
                              ? Center(
                                  child: Text(
                                    'No bookmarks added yet.',
                                    style: EditorialTokens.bodySmall(
                                      color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _userBookmarks.length,
                                  separatorBuilder: (_, __) => const EditorialDivider(),
                                  itemBuilder: (context, index) {
                                    final bm = _userBookmarks[index];
                                    return ListTile(
                                      dense: true,
                                      leading: const Icon(Icons.bookmark, size: 16, color: EditorialTokens.primary),
                                      title: Text(
                                        bm.label,
                                        style: EditorialTokens.bodySmall(
                                          color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'Page ${bm.pageNumber}',
                                        style: EditorialTokens.metadata(
                                          color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                                        ).copyWith(fontSize: 10),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 16),
                                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                            onPressed: () => _editBookmarkDialog(bm),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 16),
                                            color: EditorialTokens.error,
                                            onPressed: () async {
                                              if (bm.id != null) {
                                                await DatabaseHelper.instance.deleteBookmark(bm.id!);
                                                _loadMetadataAndProgress();
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                      onTap: () {
                                        _pdfViewerController.jumpToPage(bm.pageNumber);
                                        Navigator.pop(context);
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),

                    // Notes & Annotations Tab
                    _pdfNotes.isEmpty
                        ? Center(
                            child: Text(
                              'No annotations or notes recorded.',
                              style: EditorialTokens.bodySmall(
                                color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _pdfNotes.length,
                            separatorBuilder: (_, __) => const EditorialDivider(),
                            itemBuilder: (context, index) {
                              final note = _pdfNotes[index];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.note_alt_outlined,
                                  size: 16,
                                  color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                ),
                                title: Text(
                                  note.noteText,
                                  style: EditorialTokens.bodySmall(
                                    color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                  ),
                                ),
                                subtitle: Text(
                                  'Page ${note.pageNumber}',
                                  style: EditorialTokens.metadata(
                                    color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                                  ).copyWith(fontSize: 10),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 16),
                                  color: EditorialTokens.error,
                                  onPressed: () async {
                                    if (note.id != null) {
                                      await DatabaseHelper.instance.deleteNote(note.id!);
                                      _loadMetadataAndProgress();
                                    }
                                  },
                                ),
                                onTap: () {
                                  _pdfViewerController.jumpToPage(note.pageNumber);
                                  Navigator.pop(context);
                                },
                              );
                            },
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addUserBookmark() async {
    final label = 'Page $_currentPage Bookmark';
    final bookmark = Bookmark(
      filePath: widget.filePath,
      pageNumber: _currentPage,
      label: label,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await DatabaseHelper.instance.addBookmark(bookmark);
    await _loadMetadataAndProgress();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added bookmark for page $_currentPage')),
    );
  }

  void _editBookmarkDialog(Bookmark bm) async {
    final controller = TextEditingController(text: bm.label);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Bookmark Label'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (bm.id != null && controller.text.trim().isNotEmpty) {
                await DatabaseHelper.instance
                    .updateBookmarkLabel(bm.id!, controller.text.trim());
                await _loadMetadataAndProgress();
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  // --- Compact Floating Contextual Selection Toolbar ---
  Widget _buildSelectionToolbar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      bottom: 12,
      left: 16,
      right: 16,
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surfaceStrong,
            borderRadius: BorderRadius.circular(EditorialTokens.r4),
            border: Border.all(
              color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
              width: EditorialTokens.hairline,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A1C1A18),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSelectionAction(
                  icon: Icons.copy,
                  label: 'Copy',
                  onTap: _handleCopyText,
                ),
                _buildSelectionDivider(),
                _buildSelectionAction(
                  icon: Icons.brush_outlined,
                  label: 'Highlight',
                  onTap: () => _applyTextMarkupAnnotation(MarkupAnnotationType.highlight),
                ),
                _buildSelectionDivider(),
                _buildSelectionAction(
                  icon: Icons.format_underlined,
                  label: 'Underline',
                  onTap: () => _applyTextMarkupAnnotation(MarkupAnnotationType.underline),
                ),
                _buildSelectionDivider(),
                _buildSelectionAction(
                  icon: Icons.strikethrough_s,
                  label: 'Strike',
                  onTap: () => _applyTextMarkupAnnotation(MarkupAnnotationType.strikethrough),
                ),
                _buildSelectionDivider(),
                _buildSelectionAction(
                  icon: Icons.gesture,
                  label: 'Squiggly',
                  onTap: () => _applyTextMarkupAnnotation(MarkupAnnotationType.squiggly),
                ),
                _buildSelectionDivider(),
                _buildSelectionAction(
                  icon: Icons.auto_awesome,
                  label: 'Explain',
                  onTap: _handleExplainText,
                ),
                _buildSelectionDivider(),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                  onPressed: () {
                    _pdfViewerController.clearSelection();
                    setState(() => _showSelectionMenu = false);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionDivider() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 14,
      width: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
    );
  }

  Widget _buildSelectionAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(EditorialTokens.r4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: EditorialTokens.primary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: EditorialTokens.label(
                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
              ).copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  void _showAnnotationInspectorSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paletteColors = [
      (EditorialTokens.primary, 'Terracotta'),
      (const Color(0xFFC2843A), 'Ochre'),
      (const Color(0xFF5D7052), 'Sage'),
      (const Color(0xFF2C2825), 'Charcoal'),
      (const Color(0xFF4E5866), 'Slate'),
    ];
    final strokeWidths = ['0.5mm', '1.0mm', '2.0mm'];
    final noteController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final notesOnCurrentPage = _pdfNotes.where((n) => n.pageNumber == _currentPage).toList();

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: BoxDecoration(
              color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surfaceStrong,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(EditorialTokens.r8)),
              border: Border.all(
                color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                width: EditorialTokens.hairline,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2A1C1A18),
                  blurRadius: 16,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pull indicator
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              EditorialEyebrow(
                                text: 'DOCUMENT STUDIO / PAGE $_currentPage OF ${_totalPages > 0 ? _totalPages : 1}',
                                color: EditorialTokens.primary,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Annotation Inspector',
                                style: EditorialTokens.titleMedium(
                                  color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          onPressed: () => Navigator.pop(bottomSheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const EditorialDivider(),
                    const SizedBox(height: 14),

                    // Associated Formula Block (from Stitch Page 1 & 2)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                        borderRadius: BorderRadius.circular(EditorialTokens.r4),
                        border: Border.all(
                          color: EditorialTokens.primary.withOpacity(0.3),
                          width: EditorialTokens.hairline,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.functions, size: 14, color: EditorialTokens.primary),
                              const SizedBox(width: 6),
                              Text(
                                'ASSOCIATED FORMULATION (PAGE $_currentPage)',
                                style: EditorialTokens.eyebrow(color: EditorialTokens.primary).copyWith(fontSize: 9),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(const ClipboardData(
                                    text: r'\mathcal{L}\{\ddot{x} + 2\zeta\omega_n\dot{x} + \omega_n^2x\} = X(s)(s^2 + 2\zeta\omega_n s + \omega_n^2)',
                                  ));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('LaTeX expression copied to clipboard')),
                                  );
                                },
                                child: Text(
                                  'COPY TEX',
                                  style: EditorialTokens.metadata(color: EditorialTokens.tertiary).copyWith(fontSize: 9, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? EditorialTokens.darkCanvas : EditorialTokens.paper,
                              borderRadius: BorderRadius.circular(EditorialTokens.r4),
                              border: Border.all(
                                color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                                width: EditorialTokens.hairline,
                              ),
                            ),
                            child: Text(
                              r'\mathcal{L}\{\ddot{x} + 2\zeta\omega_n\dot{x} + \omega_n^2x\} = X(s)(s^2 + 2\zeta\omega_n s + \omega_n^2)',
                              style: EditorialTokens.mono(
                                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                              ).copyWith(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Stationery Suite / Markup Tools
                    Text(
                      'MARKUP INSTRUMENTS',
                      style: EditorialTokens.eyebrow(
                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      ).copyWith(fontSize: 10),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildStationeryToolPill(
                            id: 'pen',
                            icon: Icons.edit,
                            label: 'Pen',
                            onTap: () {
                              setState(() => _selectedAnnotationTool = 'pen');
                              Navigator.pop(bottomSheetContext);
                              _showSignatureDialog();
                            },
                          ),
                          const SizedBox(width: 6),
                          _buildStationeryToolPill(
                            id: 'chisel',
                            icon: Icons.brush_outlined,
                            label: 'Chisel',
                            onTap: () {
                              setState(() => _selectedAnnotationTool = 'chisel');
                              Navigator.pop(bottomSheetContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Highlight active: Select text on document to highlight')),
                              );
                            },
                          ),
                          const SizedBox(width: 6),
                          _buildStationeryToolPill(
                            id: 'eraser',
                            icon: Icons.cleaning_services_outlined,
                            label: 'Eraser',
                            onTap: () {
                              setState(() => _selectedAnnotationTool = 'eraser');
                              Navigator.pop(bottomSheetContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Eraser active: Select annotation to remove')),
                              );
                            },
                          ),
                          const SizedBox(width: 6),
                          _buildStationeryToolPill(
                            id: 'sketch',
                            icon: Icons.gesture,
                            label: 'Sketch',
                            onTap: () {
                              setState(() => _selectedAnnotationTool = 'sketch');
                              Navigator.pop(bottomSheetContext);
                              _showSignatureDialog();
                            },
                          ),
                          const SizedBox(width: 6),
                          _buildStationeryToolPill(
                            id: 'sign',
                            icon: Icons.verified_outlined,
                            label: 'Sign',
                            onTap: () {
                              Navigator.pop(bottomSheetContext);
                              _showSignatureDialog();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Stroke Width and Opacity Selector
                    Row(
                      children: [
                        Text(
                          'STROKE',
                          style: EditorialTokens.eyebrow(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ).copyWith(fontSize: 9),
                        ),
                        const SizedBox(width: 8),
                        ...strokeWidths.map((w) {
                          final isSel = _selectedStrokeWidth == w;
                          return InkWell(
                            onTap: () {
                              setState(() => _selectedStrokeWidth = w);
                              setModalState(() {});
                            },
                            borderRadius: BorderRadius.circular(EditorialTokens.r4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: isSel ? EditorialTokens.primary.withOpacity(0.12) : Colors.transparent,
                                borderRadius: BorderRadius.circular(EditorialTokens.r4),
                                border: Border.all(
                                  color: isSel ? EditorialTokens.primary : (isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft),
                                  width: EditorialTokens.hairline,
                                ),
                              ),
                              child: Text(
                                w,
                                style: EditorialTokens.metadata(
                                  color: isSel ? EditorialTokens.primary : (isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary),
                                ).copyWith(fontSize: 10, fontWeight: isSel ? FontWeight.w600 : FontWeight.w400),
                              ),
                            ),
                          );
                        }),
                        const Spacer(),
                        Text(
                          'PALETTE',
                          style: EditorialTokens.eyebrow(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ).copyWith(fontSize: 9),
                        ),
                        const SizedBox(width: 8),
                        ...paletteColors.map((cp) {
                          final isSel = _selectedAnnotationColor == cp.$1;
                          return InkWell(
                            onTap: () {
                              setState(() => _selectedAnnotationColor = cp.$1);
                              setModalState(() {});
                            },
                            child: Container(
                              width: 18,
                              height: 18,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: cp.$1,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSel ? EditorialTokens.ink : Colors.transparent,
                                  width: 2.0,
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const EditorialDivider(),
                    const SizedBox(height: 14),

                    // Verified Signature Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                        borderRadius: BorderRadius.circular(EditorialTokens.r4),
                        border: Border.all(
                          color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                          width: EditorialTokens.hairline,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified, size: 24, color: EditorialTokens.tertiary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'VERIFIED SIGNATURE STAMP',
                                  style: EditorialTokens.eyebrow(color: EditorialTokens.tertiary).copyWith(fontSize: 10),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Stamp signed vector graphic on Page $_currentPage',
                                  style: EditorialTokens.bodySmall(
                                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                  ).copyWith(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          EditorialSecondaryButton(
                            label: 'STAMP',
                            icon: Icons.draw,
                            onPressed: () {
                              Navigator.pop(bottomSheetContext);
                              _showSignatureDialog();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Marginalia Note Section
                    Text(
                      'PAGE MARGINALIA & MEMORANDA',
                      style: EditorialTokens.eyebrow(
                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      ).copyWith(fontSize: 10),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? EditorialTokens.darkCanvas : EditorialTokens.paper,
                        borderRadius: BorderRadius.circular(EditorialTokens.r4),
                        border: Border.all(
                          color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                          width: EditorialTokens.hairline,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Column(
                        children: [
                          TextField(
                            controller: noteController,
                            maxLines: 2,
                            style: EditorialTokens.bodyMedium(
                              color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                            ).copyWith(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'Enter marginalia note for page $_currentPage...',
                              hintStyle: EditorialTokens.bodySmall(
                                color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              EditorialButton(
                                label: 'RECORD NOTE',
                                icon: Icons.save_outlined,
                                onPressed: () async {
                                  final text = noteController.text.trim();
                                  if (text.isNotEmpty) {
                                    await DatabaseHelper.instance.addNote(
                                      PdfNote(
                                        filePath: widget.filePath,
                                        pageNumber: _currentPage,
                                        noteText: text,
                                        createdAt: DateTime.now().millisecondsSinceEpoch,
                                      ),
                                    );
                                    noteController.clear();
                                    await _loadMetadataAndProgress();
                                    setModalState(() {});
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Note recorded on page $_currentPage')),
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (notesOnCurrentPage.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...notesOnCurrentPage.map((n) => Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                          borderRadius: BorderRadius.circular(EditorialTokens.r4),
                          border: Border.all(
                            color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                            width: EditorialTokens.hairline,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.notes, size: 14, color: EditorialTokens.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                n.noteText,
                                style: EditorialTokens.bodySmall(
                                  color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                ).copyWith(fontSize: 11),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 14),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                              color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                              onPressed: () async {
                                if (n.id != null) {
                                  await DatabaseHelper.instance.deleteNote(n.id!);
                                  await _loadMetadataAndProgress();
                                  setModalState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                      )),
                    ],
                    const SizedBox(height: 14),
                    const EditorialDivider(),
                    const SizedBox(height: 10),
                    // Autosave Telemetry Strip
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: EditorialTokens.tertiary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Local Vault: Synced / Ready · Auto-commit active',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ).copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEditorialAnnotationInspector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paletteColors = [
      (EditorialTokens.primary, 'Terracotta'),
      (const Color(0xFFC2843A), 'Ochre'),
      (const Color(0xFF5D7052), 'Sage'),
      (const Color(0xFF2C2825), 'Charcoal'),
      (const Color(0xFF4E5866), 'Slate'),
    ];

    final strokeWidths = ['0.5mm', '1.0mm', '2.0mm'];

    return Positioned(
      bottom: 12,
      left: 16,
      right: 16,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surfaceStrong,
            borderRadius: BorderRadius.circular(EditorialTokens.r4),
            border: Border.all(
              color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
              width: EditorialTokens.hairline,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A1C1A18),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Row 1: Tools & Close
              Row(
                children: [
                  const EditorialEyebrow(
                    text: 'STATIONERY SUITE',
                    color: EditorialTokens.primary,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    onPressed: () => setState(() => _isAnnotationToolbarOpen = false),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStationeryToolPill(
                      id: 'pen',
                      icon: Icons.edit,
                      label: 'Pen',
                      onTap: () {
                        setState(() => _selectedAnnotationTool = 'pen');
                        _showSignatureDialog();
                      },
                    ),
                    const SizedBox(width: 4),
                    _buildStationeryToolPill(
                      id: 'chisel',
                      icon: Icons.brush_outlined,
                      label: 'Chisel',
                      onTap: () {
                        setState(() => _selectedAnnotationTool = 'chisel');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Select text to apply Chisel highlighter'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    _buildStationeryToolPill(
                      id: 'underline',
                      icon: Icons.format_underlined,
                      label: 'Underline',
                      onTap: () {
                        setState(() => _selectedAnnotationTool = 'underline');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Select text to apply Underline'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    _buildStationeryToolPill(
                      id: 'strike',
                      icon: Icons.strikethrough_s,
                      label: 'Strike',
                      onTap: () {
                        setState(() => _selectedAnnotationTool = 'strike');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Select text to apply Strikethrough'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    _buildStationeryToolPill(
                      id: 'sign',
                      icon: Icons.verified_outlined,
                      label: 'Sign',
                      onTap: _showSignatureDialog,
                    ),
                    const SizedBox(width: 4),
                    _buildStationeryToolPill(
                      id: 'note',
                      icon: Icons.note_add_outlined,
                      label: 'Note',
                      onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const EditorialDivider(),
              const SizedBox(height: 6),
              // Row 2: Stroke Widths & Palette
              Row(
                children: [
                  // Stroke width selectors
                  ...strokeWidths.map((w) {
                    final isSel = _selectedStrokeWidth == w;
                    return InkWell(
                      onTap: () => setState(() => _selectedStrokeWidth = w),
                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: isSel
                              ? (isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(EditorialTokens.r4),
                          border: Border.all(
                            color: isSel ? EditorialTokens.primary : Colors.transparent,
                            width: EditorialTokens.hairline,
                          ),
                        ),
                        child: Text(
                          w,
                          style: EditorialTokens.metadata(
                            color: isSel
                                ? EditorialTokens.primary
                                : (isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary),
                          ).copyWith(fontSize: 10, fontWeight: isSel ? FontWeight.w600 : FontWeight.w400),
                        ),
                      ),
                    );
                  }),
                  const Spacer(),
                  // Palette swatches
                  ...paletteColors.map((cp) {
                    final isSel = _selectedAnnotationColor == cp.$1;
                    return InkWell(
                      onTap: () => setState(() => _selectedAnnotationColor = cp.$1),
                      child: Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: cp.$1,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSel ? Colors.white : Colors.transparent,
                            width: 1.5,
                          ),
                          boxShadow: isSel
                              ? [
                                  BoxShadow(
                                    color: cp.$1.withOpacity(0.6),
                                    blurRadius: 3,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStationeryToolPill({
    required String id,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedAnnotationTool == id;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(EditorialTokens.r4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(EditorialTokens.r4),
          border: Border.all(
            color: isSelected ? EditorialTokens.primary : Colors.transparent,
            width: EditorialTokens.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected
                  ? EditorialTokens.primary
                  : (isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: EditorialTokens.label(
                color: isSelected
                    ? EditorialTokens.primary
                    : (isDark ? EditorialTokens.darkInk : EditorialTokens.ink),
              ).copyWith(fontSize: 10.5, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomToolTrigger({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    bool isAccent = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = isAccent
        ? EditorialTokens.primary
        : (isActive
            ? EditorialTokens.primary
            : (isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(EditorialTokens.r4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: EditorialTokens.label(
                color: color,
              ).copyWith(
                fontSize: 11,
                fontWeight: (isActive || isAccent) ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReaderModeSheet() {
    final isNightMode = ref.read(isNightReadingModeProvider);
    final isEyeComfortMode = ref.read(isEyeComfortModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        decoration: BoxDecoration(
          color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surfaceStrong,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(EditorialTokens.r8)),
          border: Border(
            top: BorderSide(
              color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
              width: EditorialTokens.hairline,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const EditorialEyebrow(
                        text: 'READING ENVIRONMENT',
                        color: EditorialTokens.primary,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Atmosphere & Modes',
                        style: EditorialTokens.title(
                          color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const EditorialDivider(),
            const SizedBox(height: 8),
            _buildModeTile(
              label: 'Standard Editorial (Default)',
              description: 'Authentic warm paper canvas bed with clean serif styling',
              isSelected: !isNightMode && !isEyeComfortMode,
              onTap: () {
                ref.read(isEyeComfortModeProvider.notifier).toggle(false);
                ref.read(isNightReadingModeProvider.notifier).toggle(false);
                Navigator.pop(ctx);
              },
            ),
            _buildModeTile(
              label: 'Eye Comfort (Amber Warmth)',
              description: 'Softened blue light reduction for extended reading',
              isSelected: isEyeComfortMode,
              onTap: () {
                ref.read(isNightReadingModeProvider.notifier).toggle(false);
                ref.read(isEyeComfortModeProvider.notifier).toggle(true);
                Navigator.pop(ctx);
              },
            ),
            _buildModeTile(
              label: 'Night Studio (Low Contrast Dark)',
              description: 'Deep archival ink bed with inverted readability',
              isSelected: isNightMode,
              onTap: () {
                ref.read(isEyeComfortModeProvider.notifier).toggle(false);
                ref.read(isNightReadingModeProvider.notifier).toggle(true);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTile({
    required String label,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(EditorialTokens.r4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(EditorialTokens.r4),
          border: Border.all(
            color: isSelected ? EditorialTokens.primary : Colors.transparent,
            width: EditorialTokens.hairline,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: EditorialTokens.bodySmall(
                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                    ).copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: EditorialTokens.metadata(
                      color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                    ).copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check,
                size: 16,
                color: EditorialTokens.primary,
              ),
          ],
        ),
      ),
    );
  }

  void _openStudyMode() {
    final pdfFile = PdfFile(
      docId: DateTime.now().microsecondsSinceEpoch.toRadixString(36) + widget.filePath.hashCode.toRadixString(36),
      path: widget.filePath,
      name: widget.filePath.split(Platform.pathSeparator).last,
      sizeBytes: File(widget.filePath).existsSync() ? File(widget.filePath).lengthSync() : 0,
      modifiedAt: DateTime.now().millisecondsSinceEpoch,
      pageCount: _totalPages,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudyModeScreen(pdfFile: pdfFile),
      ),
    );
  }

  void _openDocQa() {
    final pdfFile = PdfFile(
      docId: DateTime.now().microsecondsSinceEpoch.toRadixString(36) + widget.filePath.hashCode.toRadixString(36),
      path: widget.filePath,
      name: widget.filePath.split(Platform.pathSeparator).last,
      sizeBytes: File(widget.filePath).existsSync() ? File(widget.filePath).lengthSync() : 0,
      modifiedAt: DateTime.now().millisecondsSinceEpoch,
      pageCount: _totalPages,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocQaScreen(pdfFile: pdfFile),
      ),
    );
  }

  void _handleExplainText() {
    final text = _lastTextSelectionDetails?.selectedText;
    _pdfViewerController.clearSelection();
    setState(() => _showSelectionMenu = false);
    if (text != null && text.trim().isNotEmpty) {
      showDialog(
        context: context,
        builder: (_) => ExplainTextDialog(selectedText: text),
      );
    }
  }

  Future<void> _toggleBookmarkForCurrentPage() async {
    final existing = _userBookmarks.where((b) => b.pageNumber == _currentPage).toList();
    if (existing.isNotEmpty) {
      if (existing.first.id != null) {
        await DatabaseHelper.instance.deleteBookmark(existing.first.id!);
      }
    } else {
      await DatabaseHelper.instance.addBookmark(
        Bookmark(
          filePath: widget.filePath,
          pageNumber: _currentPage,
          label: 'Page $_currentPage',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    _loadMetadataAndProgress();
  }



  void _showJumpToPageDialog() async {
    final controller = TextEditingController(text: '$_currentPage');
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jump to Page'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '1 - $_totalPages',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final target = int.tryParse(controller.text);
              if (target != null && target >= 1 && target <= _totalPages) {
                _pdfViewerController.jumpToPage(target);
                Navigator.pop(context);
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNightMode = ref.watch(isNightReadingModeProvider);
    final isEyeComfortMode = ref.watch(isEyeComfortModeProvider);
    final isDark =
        Theme.of(context).brightness == Brightness.dark || isNightMode;

    final scaffoldBg = isEyeComfortMode
        ? AppTheme.eyeComfortReaderBg
        : (isNightMode ? AppTheme.nightReaderBg : EditorialTokens.viewerBed);

    final appBarBg = isEyeComfortMode
        ? AppTheme.eyeComfortCardBg
        : (isDark ? EditorialTokens.darkSurface : EditorialTokens.surfaceStrong);

    final textColor = isEyeComfortMode
        ? const Color(0xFF3B2F23)
        : (isDark ? EditorialTokens.darkInk : EditorialTokens.ink);

    final double currentProgress =
        _totalPages > 0 ? (_currentPage / _totalPages).clamp(0.0, 1.0) : 0.0;
    final int progressPct = (currentProgress * 100).toInt();

    Widget viewerWidget = SfPdfViewer.file(
      File(widget.filePath),
      controller: _pdfViewerController,
      enableTextSelection: true,
      canShowTextSelectionMenu: false, // CRITICAL FIX: Disables double native popup toolbar!
      canShowScrollHead: false,
      canShowScrollStatus: false,
      enableDoubleTapZooming: true,
      pageLayoutMode: PdfPageLayoutMode.continuous,
      scrollDirection: PdfScrollDirection.vertical,
      pageSpacing: 4.0,
      currentSearchTextHighlightColor: Colors.yellow.withOpacity(0.6),
      otherSearchTextHighlightColor: Colors.yellow.withOpacity(0.3),
      onTextSelectionChanged: (details) {
        _lastTextSelectionDetails = details;
        if (details.selectedText != null &&
            details.selectedText!.trim().isNotEmpty) {
          setState(() => _showSelectionMenu = true);
        } else {
          setState(() => _showSelectionMenu = false);
        }
      },
      onZoomLevelChanged: (details) {
        _zoomNotifier.value = details.newZoomLevel;
      },
      onDocumentLoaded: (details) {
        setState(() {
          _totalPages = details.document.pages.count;
          _docBookmarks = details.document.bookmarks;
        });
        if (!_hasResumedPosition &&
            _initialPage > 1 &&
            _initialPage <= _totalPages) {
          _hasResumedPosition = true;
          _pdfViewerController.jumpToPage(_initialPage);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Resumed reading at page $_initialPage'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      onPageChanged: (details) {
        setState(() {
          _currentPage = details.newPageNumber;
        });
        _updateProgress(details.newPageNumber);
      },
      onDocumentLoadFailed: (details) {
        setState(() => _isCorrupted = true);
      },
    );

    if (isEyeComfortMode) {
      viewerWidget = ColorFiltered(
        colorFilter: const ColorFilter.mode(
          Color(0x1CFFAA00),
          BlendMode.darken,
        ),
        child: viewerWidget,
      );
    }

    return PopScope(
      canPop: !widget.isExternalLaunch,
      onPopInvokedWithResult: (didPop, result) {
        if (_isTtsPlaying || _isTtsPaused) {
          _ttsService.stop();
        }
        if (!didPop || widget.isExternalLaunch) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: scaffoldBg,
        endDrawer: _buildDrawer(),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 380;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: appBarBg,
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                        width: EditorialTokens.hairline,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        color: textColor,
                        onPressed: _handleBackNavigation,
                      ),
                      const SizedBox(width: 4),
                      if (_isSearchActive)
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchFieldController,
                                  autofocus: true,
                                  style: EditorialTokens.bodySmall(color: textColor),
                                  decoration: InputDecoration(
                                    hintText: 'Search document text...',
                                    hintStyle: EditorialTokens.metadata(
                                      color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                  onChanged: (query) {
                                    if (query.trim().isNotEmpty) {
                                      _searchResult = _pdfViewerController.searchText(query);
                                    } else {
                                      _searchResult.clear();
                                    }
                                    setState(() {});
                                  },
                                ),
                              ),
                              if (_searchResult.totalInstanceCount > 0)
                                Text(
                                  '${_searchResult.currentInstanceIndex}/${_searchResult.totalInstanceCount}',
                                  style: EditorialTokens.metadataStrong(
                                    color: EditorialTokens.primary,
                                  ).copyWith(fontSize: 11),
                                ),
                              IconButton(
                                icon: const Icon(Icons.navigate_before, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                onPressed: () => _searchResult.previousInstance(),
                              ),
                              IconButton(
                                icon: const Icon(Icons.navigate_next, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                onPressed: () => _searchResult.nextInstance(),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                onPressed: () {
                                  _searchResult.clear();
                                  _searchFieldController.clear();
                                  setState(() => _isSearchActive = false);
                                },
                              ),
                            ],
                          ),
                        )
                      else
                        Expanded(
                          child: InkWell(
                            onTap: _showJumpToPageDialog,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'PAGE $_currentPage OF ${_totalPages > 0 ? _totalPages : 1} ($progressPct%)',
                                  style: EditorialTokens.eyebrow(color: EditorialTokens.primary).copyWith(fontSize: 8.5),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  widget.filePath.split(Platform.pathSeparator).last,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: EditorialTokens.title(color: textColor).copyWith(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (!_isSearchActive) ...[
                        IconButton(
                          icon: const Icon(Icons.search, size: 19),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          tooltip: 'Search Document',
                          onPressed: () => setState(() => _isSearchActive = true),
                        ),
                        IconButton(
                          icon: Icon(
                            _userBookmarks.any((b) => b.pageNumber == _currentPage)
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            size: 19,
                            color: _userBookmarks.any((b) => b.pageNumber == _currentPage)
                                ? EditorialTokens.primary
                                : (isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          tooltip: 'Bookmark Page',
                          onPressed: _toggleBookmarkForCurrentPage,
                        ),
                        if (!isNarrow)
                          IconButton(
                            icon: const Icon(Icons.rotate_right, size: 19),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            tooltip: 'Rotate Clockwise',
                            onPressed: _rotateClockwise,
                          ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 19),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surfaceStrong,
                          onSelected: (val) {
                            switch (val) {
                              case 'rotate':
                                _rotateClockwise();
                                break;
                              case 'share':
                                _sharePdf();
                                break;
                              case 'save':
                                _saveToDevice();
                                break;
                              case 'info':
                                _showDocumentInfo();
                                break;
                              case 'draw':
                                _showSignatureDialog();
                                break;
                              case 'tts':
                                if (_isTtsPlaying) {
                                  _pauseTts();
                                } else if (_isTtsPaused) {
                                  _resumeTts();
                                } else {
                                  _readAloudPage();
                                }
                                break;
                              case 'mode':
                                _showReaderModeSheet();
                                break;
                              case 'study':
                                _openStudyMode();
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            if (isNarrow)
                              PopupMenuItem(
                                value: 'rotate',
                                child: Row(
                                  children: [
                                    const Icon(Icons.rotate_right, size: 16),
                                    const SizedBox(width: 8),
                                    Text('Rotate Clockwise', style: EditorialTokens.bodySmall()),
                                  ],
                                ),
                              ),
                            PopupMenuItem(
                              value: 'mode',
                              child: Row(
                                children: [
                                  const Icon(Icons.visibility_outlined, size: 16),
                                  const SizedBox(width: 8),
                                  Text('Reading Atmosphere', style: EditorialTokens.bodySmall()),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'tts',
                              child: Row(
                                children: [
                                  Icon(
                                    _isTtsPlaying ? Icons.pause_circle_filled : Icons.volume_up,
                                    size: 16,
                                    color: EditorialTokens.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isTtsPlaying ? 'Pause Read Aloud' : 'Read Aloud Page',
                                    style: EditorialTokens.bodySmall(),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'study',
                              child: Row(
                                children: [
                                  const Icon(Icons.school_outlined, size: 16),
                                  const SizedBox(width: 8),
                                  Text('Study Mode', style: EditorialTokens.bodySmall()),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'info',
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline, size: 16),
                                  const SizedBox(width: 8),
                                  Text('Document Info', style: EditorialTokens.bodySmall()),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'share',
                              child: Row(
                                children: [
                                  const Icon(Icons.share_outlined, size: 16),
                                  const SizedBox(width: 8),
                                  Text('Share PDF', style: EditorialTokens.bodySmall()),
                                ],
                              ),
                            ),
                            if (widget.isExternalLaunch)
                              PopupMenuItem(
                                value: 'save',
                                child: Row(
                                  children: [
                                    const Icon(Icons.download, size: 16),
                                    const SizedBox(width: 8),
                                    Text('Save to Device', style: EditorialTokens.bodySmall()),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        body: Stack(
          children: [
            _isCorrupted
                ? const Center(child: Text('Failed to load PDF document.'))
                : viewerWidget,
            if (_showSelectionMenu) _buildSelectionToolbar(),
            if (_isAnnotationToolbarOpen) _buildEditorialAnnotationInspector(),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: appBarBg,
            border: Border(
              top: BorderSide(
                color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                width: EditorialTokens.hairline,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Scrubber row
                Row(
                  children: [
                    InkWell(
                      onTap: _showJumpToPageDialog,
                      child: Text(
                        'Page $_currentPage of ${_totalPages > 0 ? _totalPages : 1}',
                        style: EditorialTokens.metadataStrong(
                          color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                        ).copyWith(fontSize: 11),
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2.0,
                          activeTrackColor: EditorialTokens.primary,
                          inactiveTrackColor: isDark
                              ? EditorialTokens.darkSurfaceMuted
                              : EditorialTokens.borderSoft,
                          thumbColor: EditorialTokens.primary,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 9),
                        ),
                        child: Slider(
                          value: _currentPage.toDouble().clamp(
                              1.0, (_totalPages > 0 ? _totalPages : 1).toDouble()),
                          min: 1.0,
                          max: (_totalPages > 0 ? _totalPages : 1).toDouble(),
                          onChanged: (val) {
                            final page = val.toInt();
                            if (page != _currentPage) {
                              _pdfViewerController.jumpToPage(page);
                            }
                          },
                        ),
                      ),
                    ),
                    Text(
                      '$progressPct%',
                      style: EditorialTokens.metadataStrong(
                        color: EditorialTokens.primary,
                      ).copyWith(fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const EditorialDivider(),
                const SizedBox(height: 4),

                // Tool Triggers row (responsive, never overflows)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: (MediaQuery.of(context).size.width - 32).clamp(0.0, double.infinity),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildBottomToolTrigger(
                          icon: Icons.format_list_bulleted,
                          label: 'Outline',
                          onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                        ),
                        _buildBottomToolTrigger(
                          icon: Icons.draw_outlined,
                          label: 'Annotate',
                          isActive: _isAnnotationToolbarOpen,
                          onTap: _showAnnotationInspectorSheet,
                        ),
                        _buildBottomToolTrigger(
                          icon: Icons.psychology_outlined,
                          label: 'Ask Doc',
                          isAccent: true,
                          onTap: _openDocQa,
                        ),
                        _buildBottomToolTrigger(
                          icon: Icons.visibility_outlined,
                          label: 'Mode',
                          onTap: _showReaderModeSheet,
                        ),
                        const SizedBox(width: 4),
                        // Zoom Level Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                            borderRadius: BorderRadius.circular(EditorialTokens.r4),
                            border: Border.all(
                              color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                              width: EditorialTokens.hairline,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, size: 14),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                tooltip: 'Zoom Out',
                                onPressed: () {
                                  final next = (_pdfViewerController.zoomLevel - 0.25).clamp(1.0, 3.0);
                                  _pdfViewerController.zoomLevel = next;
                                  _zoomNotifier.value = next;
                                },
                              ),
                              ValueListenableBuilder<double>(
                                valueListenable: _zoomNotifier,
                                builder: (context, zoom, _) => Text(
                                  '${(zoom * 100).toInt()}%',
                                  style: EditorialTokens.metadataStrong(
                                    color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                  ).copyWith(fontSize: 10),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add, size: 14),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                tooltip: 'Zoom In',
                                onPressed: () {
                                  final next = (_pdfViewerController.zoomLevel + 0.25).clamp(1.0, 3.0);
                                  _pdfViewerController.zoomLevel = next;
                                  _zoomNotifier.value = next;
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
