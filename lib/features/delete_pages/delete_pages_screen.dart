import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../core/storage/pdf_metadata_helper.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../models/pdf_file.dart';
import '../../widgets/editorial_components.dart';
import '../../widgets/pdf_tool_file_picker_screen.dart';
import '../home/pdf_list_provider.dart';
import '../viewer/pdf_viewer_screen.dart';

class DeletePagesScreen extends ConsumerStatefulWidget {
  final PdfFile? sourceFile;

  const DeletePagesScreen({super.key, this.sourceFile});

  @override
  ConsumerState<DeletePagesScreen> createState() => _DeletePagesScreenState();
}

class _DeletePagesScreenState extends ConsumerState<DeletePagesScreen> {
  PdfFile? _selectedFile;
  final Set<int> _selectedPageIndices = {};
  bool _isProcessing = false;
  String? _outputFilePath;

  @override
  void initState() {
    super.initState();
    _selectedFile = widget.sourceFile;
  }

  Future<void> _pickFile() async {
    final file = await Navigator.push<PdfFile>(
      context,
      MaterialPageRoute(
        builder: (_) => const PdfToolFilePickerScreen(
          title: 'Select Document to Delete Pages',
          mode: ToolPickerMode.singleSelect,
        ),
      ),
    );

    if (file != null) {
      setState(() {
        _selectedFile = file;
        _selectedPageIndices.clear();
      });
    }
  }

  void _selectAll() {
    if (_selectedFile == null) return;
    setState(() {
      _selectedPageIndices.clear();
      for (int i = 0; i < _selectedFile!.pageCount; i++) {
        _selectedPageIndices.add(i);
      }
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedPageIndices.clear();
    });
  }

  Future<void> _confirmAndDelete() async {
    if (_selectedFile == null) return;
    final total = _selectedFile!.pageCount;
    final selCount = _selectedPageIndices.length;

    if (selCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least 1 page to delete.')),
      );
      return;
    }

    if (selCount >= total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete all pages from document.')),
      );
      return;
    }

    bool replaceOriginal = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: EditorialTokens.paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EditorialTokens.r6),
            side: const BorderSide(
              color: EditorialTokens.border,
              width: EditorialTokens.hairline,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EditorialEyebrow(text: 'CONFIRM DELETE'),
                const SizedBox(height: 6),
                Text(
                  'Permanent Page Removal',
                  style: EditorialTokens.titleLarge(),
                ),
                const SizedBox(height: 12),
                Text(
                  'Delete $selCount pages from "${_selectedFile!.name}"? The remaining ${total - selCount} pages will be saved cleanly.',
                  style:
                      EditorialTokens.body(color: EditorialTokens.inkSecondary),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () =>
                      setDialogState(() => replaceOriginal = !replaceOriginal),
                  child: Row(
                    children: [
                      Icon(
                        replaceOriginal
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 18,
                        color: EditorialTokens.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Replace source document in place',
                        style: EditorialTokens.bodyMedium(
                            color: EditorialTokens.ink),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    EditorialSecondaryButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 10),
                    EditorialButton(
                      label: 'Delete Pages',
                      isDestructive: true,
                      onPressed: () {
                        Navigator.pop(context);
                        _executeDeletePages(replaceOriginal);
                      },
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

  Future<void> _executeDeletePages(bool replaceOriginal) async {
    setState(() => _isProcessing = true);

    try {
      final sourceBytes = await File(_selectedFile!.path).readAsBytes();
      final document = sf.PdfDocument(inputBytes: sourceBytes);

      // Sort descending to avoid index shifting when calling removeAt
      final indicesToRemove = _selectedPageIndices.toList()
        ..sort((a, b) => b.compareTo(a));
      for (final pageIndex in indicesToRemove) {
        if (pageIndex >= 0 && pageIndex < document.pages.count) {
          document.pages.removeAt(pageIndex);
        }
      }

      final savedBytes = await document.save();
      document.dispose();

      String targetPath = _selectedFile!.path;
      if (!replaceOriginal) {
        final parentDir = File(_selectedFile!.path).parent.path;
        final name = _selectedFile!.name.replaceFirst(
            RegExp(r'\.pdf$', caseSensitive: false), '_trimmed.pdf');
        targetPath = '$parentDir${Platform.pathSeparator}$name';
      }

      await File(targetPath).writeAsBytes(savedBytes);

      final registered = await PdfMetadataHelper.registerAndSyncPdf(targetPath);
      if (registered != null) {
        ref.read(pdfListProvider.notifier).addFile(registered);
      }

      setState(() {
        _isProcessing = false;
        _outputFilePath = targetPath;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting pages: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_outputFilePath != null) {
      return Scaffold(
        backgroundColor: EditorialTokens.canvas,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: EditorialTokens.paper,
                  borderRadius: BorderRadius.circular(EditorialTokens.r6),
                  border: Border.all(
                    color: EditorialTokens.border,
                    width: EditorialTokens.hairline,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.verified_outlined,
                      size: 48,
                      color: Color(0xFF386641),
                    ),
                    const SizedBox(height: 16),
                    const EditorialEyebrow(text: 'DELETE COMPLETE'),
                    const SizedBox(height: 4),
                    Text(
                      'Pages Successfully Removed',
                      style: EditorialTokens.titleLarge(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _outputFilePath!,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: EditorialTokens.metadata(
                          color: EditorialTokens.inkMuted),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        EditorialButton(
                          label: 'Open Document',
                          icon: Icons.menu_book,
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PdfViewerScreen(filePath: _outputFilePath!),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        EditorialSecondaryButton(
                          label: 'Share',
                          icon: Icons.share_outlined,
                          onPressed: () {
                            Share.shareXFiles([XFile(_outputFilePath!)]);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'RETURN TO LIBRARY',
                        style: EditorialTokens.metadata(
                            color: EditorialTokens.inkMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: EditorialTokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const EditorialDivider(),
            _buildFileSelectorCard(),
            const EditorialDivider(),
            Expanded(
              child: _isProcessing
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: EditorialTokens.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'DELETING PAGES FROM DOCUMENT...',
                            style: EditorialTokens.metadata().copyWith(
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    )
                  : (_selectedFile == null
                      ? _buildEmptyPicker()
                      : _buildPageGrid()),
            ),
            if (_selectedFile != null) _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back,
                color: EditorialTokens.ink, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const EditorialEyebrow(text: 'PAGE MANAGEMENT'),
                const SizedBox(height: 2),
                Text(
                  'Delete Pages',
                  style: EditorialTokens.titleLarge(),
                ),
              ],
            ),
          ),
          if (_selectedFile != null) ...[
            TextButton(
              onPressed: _selectAll,
              child: Text(
                'ALL',
                style: EditorialTokens.metadataStrong(
                    color: EditorialTokens.primary),
              ),
            ),
            TextButton(
              onPressed: _deselectAll,
              child: Text(
                'CLEAR',
                style: EditorialTokens.metadataStrong(
                    color: EditorialTokens.inkMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileSelectorCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: EditorialTokens.surface,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedFile?.name ?? 'No Document Selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EditorialTokens.titleSmall()
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  _selectedFile != null
                      ? '${_selectedFile!.pageCount} PAGES TOTAL'
                      : 'TAP BROWSE TO SELECT DOCUMENT',
                  style:
                      EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          EditorialSecondaryButton(
            label: _selectedFile == null ? 'Browse' : 'Change',
            icon: Icons.folder_open,
            onPressed: _pickFile,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPicker() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: EditorialTokens.surfaceMuted,
                borderRadius: BorderRadius.circular(EditorialTokens.r6),
                border: Border.all(
                  color: EditorialTokens.border,
                  width: EditorialTokens.hairline,
                ),
              ),
              child: const Icon(
                Icons.delete_outline,
                size: 40,
                color: EditorialTokens.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Document Selected',
              style: EditorialTokens.titleMedium()
                  .copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a PDF from your library to select and remove unwanted pages cleanly without quality loss.',
              textAlign: TextAlign.center,
              style: EditorialTokens.bodySmall(color: EditorialTokens.inkMuted),
            ),
            const SizedBox(height: 24),
            EditorialButton(
              label: 'Browse Library',
              icon: Icons.folder_open,
              onPressed: _pickFile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.72,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _selectedFile!.pageCount,
      itemBuilder: (context, index) {
        final isSelected = _selectedPageIndices.contains(index);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedPageIndices.remove(index);
              } else {
                _selectedPageIndices.add(index);
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color:
                  isSelected ? const Color(0xFFFBF1EE) : EditorialTokens.paper,
              borderRadius: BorderRadius.circular(EditorialTokens.r4),
              border: Border.all(
                color: isSelected
                    ? EditorialTokens.primary
                    : EditorialTokens.border,
                width: isSelected ? 1.5 : EditorialTokens.hairline,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 32,
                        color: isSelected
                            ? EditorialTokens.primary
                            : EditorialTokens.inkSecondary,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'P. ${index + 1}',
                        style: EditorialTokens.metadataStrong(
                          color: isSelected
                              ? EditorialTokens.primary
                              : EditorialTokens.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: EditorialTokens.primary,
                        borderRadius: BorderRadius.circular(EditorialTokens.r2),
                      ),
                      child: Text(
                        'REMOVE',
                        style: EditorialTokens.metadata(color: Colors.white)
                            .copyWith(
                          fontSize: 8,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final selCount = _selectedPageIndices.length;
    final total = _selectedFile?.pageCount ?? 0;
    final canDelete = selCount > 0 && selCount < total;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: EditorialTokens.surface,
        border: Border(
          top: BorderSide(
            color: EditorialTokens.border,
            width: EditorialTokens.hairline,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$selCount MARKED FOR REMOVAL',
                  style: EditorialTokens.metadataStrong(
                    color: selCount > 0
                        ? EditorialTokens.primary
                        : EditorialTokens.inkMuted,
                  ),
                ),
                Text(
                  '${total - selCount} PAGES REMAINING',
                  style:
                      EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                ),
              ],
            ),
          ),
          EditorialButton(
            label: 'Delete Pages',
            icon: Icons.delete_outline,
            isDestructive: true,
            onPressed: canDelete ? _confirmAndDelete : null,
          ),
        ],
      ),
    );
  }
}
