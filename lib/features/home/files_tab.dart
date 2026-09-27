import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import '../../core/permissions/permissions_service.dart';
import '../../core/tools/pdf_target_size_compressor_service.dart';
import '../../core/utils/utils.dart';
import '../../models/pdf_file.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/pdf_file_card.dart';
import '../../widgets/permission_banner.dart';
import '../settings/settings_screen.dart';
import '../viewer/pdf_viewer_screen.dart';
import '../merge/merge_screen.dart';
import '../delete_pages/delete_pages_screen.dart';
import '../ocr/ocr_screen.dart';
import '../study/study_mode_screen.dart';
import '../tools/version_history_screen.dart';
import '../tools/compress_pdf_screen.dart';
import '../tools/metadata_editor_screen.dart';
import '../tools/encrypt_pdf_screen.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../widgets/editorial_components.dart';
import 'pdf_list_provider.dart';

enum SortOption {
  nameAsc,
  nameDesc,
  dateNewest,
  dateOldest,
  sizeLargest,
  sizeSmallest
}

class FilesTab extends ConsumerStatefulWidget {
  const FilesTab({super.key});

  @override
  ConsumerState<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends ConsumerState<FilesTab> {
  SortOption _sortOption = SortOption.dateNewest;
  String _activeFilter = 'all'; // 'all', 'recent', 'starred'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getSortLabel() {
    switch (_sortOption) {
      case SortOption.nameAsc:
      case SortOption.nameDesc:
        return 'Name';
      case SortOption.dateNewest:
      case SortOption.dateOldest:
        return 'Date';
      case SortOption.sizeLargest:
      case SortOption.sizeSmallest:
        return 'Size';
    }
  }

  List<PdfFile> _applyFilter(List<PdfFile> files) {
    switch (_activeFilter) {
      case 'recent':
        final list = files
            .where((f) => f.lastOpenedAt != null || f.readingProgress > 0)
            .toList();
        list.sort((a, b) => (b.lastOpenedAt ?? b.modifiedAt)
            .compareTo(a.lastOpenedAt ?? a.modifiedAt));
        return list.isNotEmpty ? list : files;
      case 'starred':
        return files.where((f) => f.isFavorite).toList();
      case 'all':
      default:
        return files;
    }
  }

  List<PdfFile> _sortFiles(List<PdfFile> files) {
    final list = List<PdfFile>.from(files);
    switch (_sortOption) {
      case SortOption.nameAsc:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case SortOption.nameDesc:
        list.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case SortOption.dateNewest:
        list.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
        break;
      case SortOption.dateOldest:
        list.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
        break;
      case SortOption.sizeLargest:
        list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        break;
      case SortOption.sizeSmallest:
        list.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
        break;
    }
    return list;
  }

  void _showSortBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = [
      (SortOption.nameAsc, 'Name (A to Z)', Icons.sort_by_alpha),
      (SortOption.nameDesc, 'Name (Z to A)', Icons.sort_by_alpha),
      (SortOption.dateNewest, 'Date Modified (Newest first)', Icons.access_time),
      (SortOption.sizeLargest, 'Size (Largest first)', Icons.data_usage),
    ];

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
                        text: 'ORDER & ARRANGEMENT',
                        color: EditorialTokens.primary,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Sort Documents',
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
            const SizedBox(height: 10),
            const EditorialDivider(),
            const SizedBox(height: 8),
            ...options.map((opt) {
              final isSelected = _sortOption == opt.$1;
              return InkWell(
                onTap: () {
                  setState(() => _sortOption = opt.$1);
                  Navigator.pop(ctx);
                },
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        opt.$3,
                        size: 17,
                        color: isSelected
                            ? EditorialTokens.primary
                            : (isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          opt.$2,
                          style: EditorialTokens.bodySmall(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ).copyWith(
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (isSelected)
                        const Icon(
                          Icons.check,
                          size: 17,
                          color: EditorialTokens.primary,
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndOpenPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(filePath: filePath),
          ),
        );
      }
    }
  }

  void _handleMenuAction(String action, PdfFile file) {
    switch (action) {
      case 'open':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(filePath: file.path),
          ),
        );
        break;
      case 'merge':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MergeScreen(initialFile: file),
          ),
        );
        break;
      case 'delete_pages':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DeletePagesScreen(sourceFile: file),
          ),
        );
        break;
      case 'ocr':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OcrScreen(sourceFile: file),
          ),
        );
        break;
      case 'study':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudyModeScreen(pdfFile: file),
          ),
        );
        break;
      case 'version':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VersionHistoryScreen(pdfFile: file),
          ),
        );
        break;
      case 'compress_target':
        _showQuickCompressDialog(file);
        break;
      case 'compress':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CompressPdfScreen(pdfFile: file),
          ),
        );
        break;
      case 'metadata':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MetadataEditorScreen(pdfFile: file),
          ),
        );
        break;
      case 'encrypt':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EncryptPdfScreen(pdfFile: file),
          ),
        );
        break;
      case 'share':
        if (File(file.path).existsSync()) {
          Share.shareXFiles([XFile(file.path)], text: 'Sharing ${file.name}');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File does not exist on disk.')),
          );
        }
        break;
      case 'info':
        _showFileInfoDialog(file);
        break;
      case 'rename':
        _showRenameDialog(file);
        break;
      case 'delete':
        _showDeleteDialog(file);
        break;
    }
  }

  void _showQuickCompressDialog(PdfFile file) {
    final controller = TextEditingController(text: '500');
    String unit = 'KB';
    bool isCompressing = false;
    double progress = 0.0;
    String progressText = '';
    TargetCompressionResult? result;

    if (file.sizeBytes > 0) {
      final target = (file.sizeBytes * 0.5).round();
      if (target >= 1024 * 1024) {
        unit = 'MB';
        controller.text = (target / (1024 * 1024)).toStringAsFixed(1);
      } else {
        unit = 'KB';
        controller.text = (target / 1024).round().toString();
      }
    }

    final presets = [
      {'label': '50 KB', 'val': 50.0, 'unit': 'KB'},
      {'label': '100 KB', 'val': 100.0, 'unit': 'KB'},
      {'label': '200 KB', 'val': 200.0, 'unit': 'KB'},
      {'label': '500 KB', 'val': 500.0, 'unit': 'KB'},
      {'label': '1 MB', 'val': 1.0, 'unit': 'MB'},
      {'label': '2 MB', 'val': 2.0, 'unit': 'MB'},
    ];

    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bottomSheetCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune, color: Colors.deepOrange),
                      const SizedBox(width: 8),
                      const Text(
                        'Compress PDF to Target Size',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  Text(
                    file.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Current Size: ${Utils.formatBytes(file.sizeBytes)} • ${file.pageCount > 0 ? "${file.pageCount} pages" : ""}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (result == null && !isCompressing) ...[
                    const Text('Target Size:', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Target Size',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: unit,
                          items: const [
                            DropdownMenuItem(value: 'KB', child: Text('KB')),
                            DropdownMenuItem(value: 'MB', child: Text('MB')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => unit = val);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: presets.map((p) {
                        return ActionChip(
                          label: Text(p['label'] as String, style: const TextStyle(fontSize: 12)),
                          onPressed: () {
                            setModalState(() {
                              final v = p['val'] as double;
                              controller.text = v % 1 == 0 ? v.toInt().toString() : v.toString();
                              unit = p['unit'] as String;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.compress),
                            label: const Text('Compress'),
                            onPressed: () async {
                              final textVal = controller.text.trim();
                              final val = double.tryParse(textVal);
                              if (val == null || val <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter a valid target size.')),
                                );
                                return;
                              }
                              final targetBytes = PdfTargetSizeCompressorService.parseSizeToBytes(val, unit);

                              setModalState(() {
                                isCompressing = true;
                                progress = 0.1;
                                progressText = 'Optimizing PDF...';
                              });

                              try {
                                final compResult = await PdfTargetSizeCompressorService.compressPdfToTargetSize(
                                  inputPath: file.path,
                                  targetBytes: targetBytes,
                                  quality: TargetCompressionQuality.balanced,
                                  onProgress: (p, status) {
                                    setModalState(() {
                                      progress = p;
                                      progressText = status;
                                    });
                                  },
                                );

                                // Register generated PDF directly into database & state
                                final outFile = File(compResult.outputPath);
                                if (await outFile.exists()) {
                                  final stat = await outFile.stat();
                                  final docId = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
                                      compResult.outputPath.hashCode.toRadixString(36);
                                  final newPdfFile = PdfFile(
                                    docId: docId,
                                    path: compResult.outputPath,
                                    name: p.basename(compResult.outputPath),
                                    sizeBytes: stat.size,
                                    modifiedAt: stat.modified.millisecondsSinceEpoch,
                                    pageCount: compResult.pageCount,
                                    sourceType: 'compressed',
                                    createdAt: DateTime.now().millisecondsSinceEpoch,
                                  );

                                  ref.read(pdfListProvider.notifier).addFile(newPdfFile);
                                }

                                setModalState(() {
                                  isCompressing = false;
                                  result = compResult;
                                });
                              } catch (err) {
                                setModalState(() {
                                  isCompressing = false;
                                });
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Compression failed: $err'), backgroundColor: Colors.red),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ] else if (isCompressing) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: progress > 0 ? progress : null),
                    const SizedBox(height: 12),
                    Center(child: Text(progressText, style: const TextStyle(fontSize: 13, color: Colors.grey))),
                    const SizedBox(height: 16),
                  ] else if (result != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                result!.isTargetAchieved ? Icons.check_circle : Icons.info,
                                color: result!.isTargetAchieved ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  result!.statusMessage,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: result!.isTargetAchieved ? Colors.green.shade800 : Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Original: ${Utils.formatBytes(result!.originalSizeBytes)}'),
                          Text('Target: ${Utils.formatBytes(result!.targetSizeBytes)}'),
                          Text('Output: ${Utils.formatBytes(result!.outputSizeBytes)} (-${result!.reductionPercentage.toStringAsFixed(1)}%)'),
                          const SizedBox(height: 4),
                          Text('Saved to: ${result!.outputPath}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Done'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.visibility),
                            label: const Text('Open'),
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PdfViewerScreen(filePath: result!.outputPath),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showFileInfoDialog(PdfFile file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${file.name}'),
            const SizedBox(height: 8),
            Text('Path: ${file.path}'),
            const SizedBox(height: 8),
            Text('Pages: ${file.pageCount > 0 ? file.pageCount : "Unknown"}'),
            const SizedBox(height: 8),
            Text('Size: ${Utils.formatBytes(file.sizeBytes)}'),
            const SizedBox(height: 8),
            Text('Modified: ${Utils.formatDate(file.modifiedAt)}'),
            if (file.sourceType == 'scanned') ...[
              const SizedBox(height: 8),
              const Text('Source: Scanned Document', style: TextStyle(color: Colors.green)),
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

  void _showRenameDialog(PdfFile file) async {
    final controller = TextEditingController(text: file.name);
    final messenger = ScaffoldMessenger.of(context);
    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Rename File'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'File Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(dialogCtx);
                final error = await ref
                    .read(pdfListProvider.notifier)
                    .renameFile(file.path, newName);
                if (error != null) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(error), backgroundColor: Colors.red),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Renamed to $newName')),
                  );
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  void _showDeleteDialog(PdfFile file) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Are you sure you want to delete "${file.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final success = await ref.read(pdfListProvider.notifier).deleteFile(file.path);
              if (success) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Deleted "${file.name}"')),
                );
              } else {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Failed to delete file.'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentScansSection(List<PdfFile> recentScans) {
    if (recentScans.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: EditorialSectionHeader(
            number: '01',
            label: 'Recent Scans',
            count: '${recentScans.length} scans',
          ),
        ),
        SizedBox(
          height: 104,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: recentScans.length,
            itemBuilder: (context, index) {
              final scan = recentScans[index];
              return Container(
                width: 190,
                margin: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
                decoration: BoxDecoration(
                  color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surfaceStrong,
                  borderRadius: BorderRadius.circular(EditorialTokens.r4),
                  border: Border.all(
                    color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                    width: EditorialTokens.hairline,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A1C1A18),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(EditorialTokens.r4),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PdfViewerScreen(filePath: scan.path),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          EditorialPaperThumbnail(
                            pageNumber: 1,
                            totalPages: scan.pageCount > 0 ? scan.pageCount : 1,
                            width: 36,
                            height: 50,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  scan.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: EditorialTokens.title(
                                    color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                  ).copyWith(fontSize: 12),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  Utils.formatBytes(scan.sizeBytes),
                                  style: EditorialTokens.metadata(
                                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                  ).copyWith(fontSize: 10),
                                ),
                                Text(
                                  Utils.formatRelativeTime(scan.scanCreatedAt ?? scan.modifiedAt),
                                  style: EditorialTokens.metadata(
                                    color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                                  ).copyWith(fontSize: 9),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildCurrentlyReadingCard(PdfFile file) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progressPct = (file.readingProgress * 100).toInt();
    final folderPath = file.folder ??
        (file.path.contains(Platform.pathSeparator)
            ? file.path.substring(0, file.path.lastIndexOf(Platform.pathSeparator))
            : '');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surfaceStrong,
        borderRadius: BorderRadius.circular(EditorialTokens.r4),
        border: Border.all(
          color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
          width: EditorialTokens.hairline,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C1C1A18),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(EditorialTokens.r4),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PdfViewerScreen(filePath: file.path),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EditorialPaperThumbnail(
                      pageNumber: file.lastOpenedPage > 0 ? file.lastOpenedPage : 1,
                      totalPages: file.pageCount > 0 ? file.pageCount : 1,
                      isCompleted: file.completed,
                      progressPercent: file.readingProgress,
                      width: 52,
                      height: 72,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  file.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: EditorialTokens.displayMedium(
                                    color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                  ).copyWith(fontSize: 15),
                                ),
                              ),
                              IconButton(
                                iconSize: 18,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                icon: Icon(
                                  file.isFavorite ? Icons.star : Icons.star_border,
                                  color: file.isFavorite
                                      ? EditorialTokens.primary
                                      : (isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted),
                                ),
                                onPressed: () {
                                  ref.read(pdfListProvider.notifier).toggleFavorite(file.path);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${folderPath.isNotEmpty ? "$folderPath • " : ""}${Utils.formatBytes(file.sizeBytes)} • ${file.pageCount > 0 ? "${file.pageCount} pages" : "PDF"}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: EditorialTokens.metadata(
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ).copyWith(fontSize: 11),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Reading Progress',
                                style: EditorialTokens.bodySmall(
                                  color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                ).copyWith(fontSize: 11),
                              ),
                              Text(
                                '$progressPct%',
                                style: EditorialTokens.metadataStrong(
                                  color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                ).copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: file.readingProgress,
                              backgroundColor: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                EditorialTokens.primary,
                              ),
                              minHeight: 2.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const EditorialDivider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Page ${file.lastOpenedPage > 0 ? file.lastOpenedPage : 1} of ${file.pageCount > 0 ? file.pageCount : 1}',
                      style: EditorialTokens.metadata(
                        color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                      ).copyWith(fontSize: 10.5),
                    ),
                    const Spacer(),
                    EditorialSecondaryButton(
                      label: 'Study',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StudyModeScreen(pdfFile: file),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: Icon(
                        Icons.more_vert,
                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      ),
                      onPressed: () => _handleMenuAction('info', file),
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

  @override
  Widget build(BuildContext context) {
    final permState = ref.watch(permissionsProvider);
    final pdfState = ref.watch(pdfListProvider);
    final recentScans = ref.watch(recentScansListProvider);
    final isScanning = ref.watch(pdfListProvider.notifier).isScanning;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? EditorialTokens.darkCanvas : EditorialTokens.canvas,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? EditorialTokens.darkCanvas
                  : EditorialTokens.canvas,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? EditorialTokens.darkBorderSoft
                      : EditorialTokens.borderSoft,
                  width: EditorialTokens.hairline,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const EditorialEyebrow(
                          text: 'DOCUMENT STUDIO',
                          color: EditorialTokens.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'LOCAL STORAGE',
                          style: EditorialTokens.metadata(
                            color: isDark
                                ? EditorialTokens.darkInkSecondary
                                : EditorialTokens.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Files',
                      style: EditorialTokens.displayMedium(
                        color: isDark
                            ? EditorialTokens.darkInk
                            : EditorialTokens.ink,
                      ).copyWith(fontSize: 22, height: 1.1),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Sort pill button
                    InkWell(
                      onTap: _showSortBottomSheet,
                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? EditorialTokens.darkSurface
                              : EditorialTokens.surfaceStrong,
                          borderRadius: BorderRadius.circular(EditorialTokens.r4),
                          border: Border.all(
                            color: isDark
                                ? EditorialTokens.darkBorderSoft
                                : EditorialTokens.borderSoft,
                            width: EditorialTokens.hairline,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.swap_vert,
                              size: 16,
                              color: isDark
                                  ? EditorialTokens.darkInkSecondary
                                  : EditorialTokens.inkSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getSortLabel(),
                              style: EditorialTokens.label(
                                color: isDark
                                    ? EditorialTokens.darkInk
                                    : EditorialTokens.ink,
                              ).copyWith(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Account circle avatar 'P' linking to settings
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen()),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark
                              ? EditorialTokens.darkSurfaceMuted
                              : EditorialTokens.surfaceMuted,
                          border: Border.all(
                            color: isDark
                                ? EditorialTokens.darkBorder
                                : EditorialTokens.border,
                            width: EditorialTokens.hairline,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'P',
                          style: EditorialTokens.label(
                            color: isDark
                                ? EditorialTokens.darkInk
                                : EditorialTokens.ink,
                          ).copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (isScanning)
            const LinearProgressIndicator(
              minHeight: 2.5,
              valueColor:
                  AlwaysStoppedAnimation<Color>(EditorialTokens.primary),
            ),
          if (permState != StoragePermissionState.granted)
            PermissionBanner(
              onRequestPermission: () {
                if (permState == StoragePermissionState.permanentlyDenied) {
                  ref.read(permissionsProvider.notifier).openAppSettingsPage();
                } else {
                  ref
                      .read(permissionsProvider.notifier)
                      .requestStoragePermission();
                }
              },
            ),
          pdfState.when(
            data: (files) {
              final filtered = _applyFilter(files);
              final searchFiltered = _searchQuery.isEmpty
                  ? filtered
                  : filtered.where((f) =>
                      f.name.toLowerCase().contains(_searchQuery) ||
                      f.path.toLowerCase().contains(_searchQuery)).toList();
              final sorted = _sortFiles(searchFiltered);
              final totalBytes =
                  files.fold<int>(0, (sum, f) => sum + f.sizeBytes);

              // Find currently reading candidate
              final currentlyReading = files
                  .where((f) => f.readingProgress > 0 && !f.completed)
                  .firstOrNull;

              return Expanded(
                child: Column(
                  children: [
                    // Sub-bar: Library Stats Strip (responsive)
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
                            'LIBRARY',
                            style: EditorialTokens.eyebrow(
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ).copyWith(fontSize: 10),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: EditorialTokens.tertiary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    '${sorted.length} Docs · ${Utils.formatBytes(totalBytes)} · Indexed (Offline)',
                                    style: EditorialTokens.metadata(
                                      color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                                    ).copyWith(fontSize: 10),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Search documents, tags bar matching Design 01 Page 1 Screen 3
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      color: isDark ? EditorialTokens.darkCanvas : EditorialTokens.canvas,
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: isDark ? EditorialTokens.darkSurface : EditorialTokens.paper,
                          borderRadius: BorderRadius.circular(EditorialTokens.r4),
                          border: Border.all(
                            color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                            width: EditorialTokens.hairline,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search,
                              size: 16,
                              color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                                style: EditorialTokens.bodyMedium(
                                  color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                ).copyWith(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Search documents, tags...',
                                  hintStyle: EditorialTokens.bodyMedium(
                                    color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                                  ).copyWith(fontSize: 13),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            if (_searchQuery.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Filter Chips Strip with + Import (horizontal scrollable on narrow displays)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: isDark ? EditorialTokens.darkCanvas : EditorialTokens.canvas,
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  EditorialChip(
                                    label: 'All PDFs',
                                    selected: _activeFilter == 'all',
                                    onTap: () => setState(() => _activeFilter = 'all'),
                                  ),
                                  const SizedBox(width: 6),
                                  EditorialChip(
                                    label: 'Recent',
                                    selected: _activeFilter == 'recent',
                                    onTap: () => setState(() => _activeFilter = 'recent'),
                                  ),
                                  const SizedBox(width: 6),
                                  EditorialChip(
                                    label: 'Starred',
                                    selected: _activeFilter == 'starred',
                                    onTap: () => setState(() => _activeFilter = 'starred'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          EditorialSecondaryButton(
                            label: '+ Import',
                            icon: Icons.add,
                            onPressed: _pickAndOpenPdf,
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            tooltip: 'Refresh files',
                            onPressed: () {
                              ref.read(pdfListProvider.notifier).fastDeviceSync();
                            },
                          ),
                        ],
                      ),
                    ),

                    // Main Scrollable List Area
                    Expanded(
                      child: sorted.isEmpty
                          ? EmptyStateWidget(
                              icon: Icons.picture_as_pdf_outlined,
                              title: 'No PDF Files Found',
                              message: 'Pull to scan your device storage for PDFs or tap "+ Import" above.',
                              actionText: 'Scan Storage Now',
                              onAction: () {
                                ref.read(pdfListProvider.notifier).scanStorage();
                              },
                            )
                          : RefreshIndicator(
                              color: EditorialTokens.primary,
                              onRefresh: () async {
                                await ref.read(pdfListProvider.notifier).fastDeviceSync();
                              },
                              child: ListView.builder(
                                itemCount: sorted.length +
                                    (recentScans.isNotEmpty ? 1 : 0) +
                                    (_activeFilter == 'all' && currentlyReading != null ? 2 : 0),
                                itemBuilder: (context, index) {
                                  int currentIdx = index;

                                  // Slot 1: Recent Scans Section
                                  if (recentScans.isNotEmpty) {
                                    if (currentIdx == 0) {
                                      return _buildRecentScansSection(recentScans);
                                    }
                                    currentIdx--;
                                  }

                                  // Slot 2: Currently Reading Header & Card
                                  if (_activeFilter == 'all' && currentlyReading != null) {
                                    if (currentIdx == 0) {
                                      return Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                        child: EditorialSectionHeader(
                                          label: 'Currently Reading',
                                          trailing: Utils.formatRelativeTime(
                                            currentlyReading.lastOpenedAt ?? currentlyReading.modifiedAt,
                                          ),
                                        ),
                                      );
                                    }
                                    currentIdx--;

                                    if (currentIdx == 0) {
                                      return _buildCurrentlyReadingCard(currentlyReading);
                                    }
                                    currentIdx--;
                                  }

                                  final file = sorted[currentIdx];
                                  return PdfFileCard(
                                    file: file,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PdfViewerScreen(filePath: file.path),
                                        ),
                                      );
                                    },
                                    onToggleFavorite: () {
                                      ref.read(pdfListProvider.notifier).toggleFavorite(file.path);
                                    },
                                    onMenuAction: (action) => _handleMenuAction(action, file),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(EditorialTokens.primary),
                ),
              ),
            ),
            error: (err, _) => Expanded(
              child: EmptyStateWidget(
                icon: Icons.error_outline,
                title: 'Error Loading Files',
                message: err.toString(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

