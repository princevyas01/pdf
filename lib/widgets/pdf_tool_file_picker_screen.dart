import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../core/storage/thumbnail_cache_service.dart';
import '../core/theme/editorial_tokens.dart';
import '../core/utils/utils.dart';
import '../features/home/files_tab.dart';
import '../features/home/pdf_list_provider.dart';
import '../models/pdf_file.dart';
import 'editorial_components.dart';

enum ToolPickerMode { singleSelect, multiSelect }

class PdfToolFilePickerScreen extends ConsumerStatefulWidget {
  final String title;
  final ToolPickerMode mode;
  final List<PdfFile>? initialSelectedFiles;
  final String? actionButtonText;

  const PdfToolFilePickerScreen({
    super.key,
    required this.title,
    required this.mode,
    this.initialSelectedFiles,
    this.actionButtonText,
  });

  @override
  ConsumerState<PdfToolFilePickerScreen> createState() =>
      _PdfToolFilePickerScreenState();
}

class _PdfToolFilePickerScreenState
    extends ConsumerState<PdfToolFilePickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<PdfFile> _selectedFiles = [];
  SortOption _sortOption = SortOption.dateNewest;
  String _searchQuery = '';
  bool _showReorderSheet = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSelectedFiles != null) {
      _selectedFiles.addAll(widget.initialSelectedFiles!);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PdfFile> _filterAndSortFiles(List<PdfFile> files) {
    var list = List<PdfFile>.from(files);
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((f) =>
              f.name.toLowerCase().contains(q) ||
              f.path.toLowerCase().contains(q))
          .toList();
    }

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

  void _showSortDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: EditorialTokens.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(EditorialTokens.r8)),
        side: BorderSide(color: EditorialTokens.border, width: EditorialTokens.hairline),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EditorialEyebrow(text: 'ORDERING PREFERENCE'),
            const SizedBox(height: 4),
            Text('Sort Documents', style: EditorialTokens.titleMedium()),
            const SizedBox(height: 12),
            const EditorialDivider(),
            _buildSortTile('Alphabetical (A to Z)', SortOption.nameAsc),
            _buildSortTile('Date modified (Newest first)', SortOption.dateNewest),
            _buildSortTile('Document size (Largest first)', SortOption.sizeLargest),
          ],
        ),
      ),
    );
  }

  Widget _buildSortTile(String title, SortOption option) {
    final isSelected = _sortOption == option;
    return InkWell(
      onTap: () {
        setState(() => _sortOption = option);
        Navigator.pop(context);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: EditorialTokens.bodyMedium(
                color: isSelected ? EditorialTokens.primary : EditorialTokens.ink,
              ).copyWith(fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400),
            ),
            if (isSelected)
              const Icon(Icons.check, size: 16, color: EditorialTokens.primary),
          ],
        ),
      ),
    );
  }

  String _getFolderDisplay(String filePath) {
    try {
      final parent = p.dirname(filePath);
      if (parent.startsWith('/storage/emulated/0/')) {
        return parent.replaceFirst('/storage/emulated/0/', '');
      } else if (parent.startsWith('/storage/emulated/0')) {
        return 'Internal Storage';
      }
      final parts = parent.split(Platform.pathSeparator);
      if (parts.length > 2) {
        return '.../${parts.sublist(parts.length - 2).join('/')}';
      }
      return parent;
    } catch (_) {
      return p.dirname(filePath);
    }
  }

  int get _totalSelectedPages {
    return _selectedFiles.fold(0, (sum, file) => sum + file.pageCount);
  }

  @override
  Widget build(BuildContext context) {
    final pdfState = ref.watch(pdfListProvider);

    return Scaffold(
      backgroundColor: EditorialTokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const EditorialDivider(),
            _buildSearchBar(),
            const EditorialDivider(),
            Expanded(
              child: pdfState.when(
                data: (allFiles) {
                  final displayFiles = _filterAndSortFiles(allFiles);

                  return Column(
                    children: [
                      // Reorderable sheet / Chips if multi-select
                      if (widget.mode == ToolPickerMode.multiSelect &&
                          _selectedFiles.isNotEmpty) ...[
                        Container(
                          color: EditorialTokens.surface,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'SELECTED (${_selectedFiles.length} DOCUMENTS · $_totalSelectedPages PAGES)',
                                    style: EditorialTokens.metadataStrong(
                                      color: EditorialTokens.primary,
                                    ),
                                  ),
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () => setState(() => _selectedFiles.clear()),
                                    child: Text(
                                      'CLEAR ALL',
                                      style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_showReorderSheet) ...[
                                Text(
                                  'Drag handles to sequence compilation order:',
                                  style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  height: 140,
                                  child: ReorderableListView.builder(
                                    itemCount: _selectedFiles.length,
                                    onReorder: (oldIdx, newIdx) {
                                      setState(() {
                                        if (newIdx > oldIdx) newIdx -= 1;
                                        final item = _selectedFiles.removeAt(oldIdx);
                                        _selectedFiles.insert(newIdx, item);
                                      });
                                    },
                                    itemBuilder: (context, index) {
                                      final f = _selectedFiles[index];
                                      return Container(
                                        key: ValueKey(f.path),
                                        margin: const EdgeInsets.symmetric(vertical: 3),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: EditorialTokens.paper,
                                          borderRadius: BorderRadius.circular(EditorialTokens.r4),
                                          border: Border.all(
                                            color: EditorialTokens.borderSoft,
                                            width: EditorialTokens.hairline,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.drag_handle, size: 16, color: EditorialTokens.inkMuted),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                f.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: EditorialTokens.titleSmall().copyWith(fontSize: 12),
                                              ),
                                            ),
                                            Text(
                                              '${f.pageCount}P',
                                              style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                                            ),
                                            const SizedBox(width: 6),
                                            GestureDetector(
                                              onTap: () => setState(() => _selectedFiles.removeAt(index)),
                                              child: const Icon(Icons.close, size: 14, color: EditorialTokens.inkMuted),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ] else ...[
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: _selectedFiles.map((file) {
                                      return Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: EditorialTokens.surfaceMuted,
                                          borderRadius: BorderRadius.circular(EditorialTokens.r2),
                                          border: Border.all(
                                            color: EditorialTokens.border,
                                            width: EditorialTokens.hairline,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              file.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: EditorialTokens.metadataStrong().copyWith(fontSize: 11),
                                            ),
                                            const SizedBox(width: 4),
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _selectedFiles.removeWhere((f) => f.path == file.path);
                                                });
                                              },
                                              child: const Icon(Icons.close, size: 12, color: EditorialTokens.inkMuted),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const EditorialDivider(),
                      ],

                      // File list
                      Expanded(
                        child: displayFiles.isEmpty
                            ? Center(
                                child: Text(
                                  _searchQuery.isNotEmpty
                                      ? 'NO MATCHING DOCUMENTS FOUND.'
                                      : 'NO DOCUMENTS REGISTERED IN STORAGE.',
                                  style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: displayFiles.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final file = displayFiles[index];
                                  final isSelected =
                                      _selectedFiles.any((f) => f.path == file.path);
                                  final folder = _getFolderDisplay(file.path);

                                  return Container(
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFFFBF1EE) : EditorialTokens.paper,
                                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                                      border: Border.all(
                                        color: isSelected ? EditorialTokens.primary : EditorialTokens.borderSoft,
                                        width: isSelected ? 1.5 : EditorialTokens.hairline,
                                      ),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                                      onTap: () {
                                        if (widget.mode == ToolPickerMode.singleSelect) {
                                          Navigator.pop(context, file);
                                        } else {
                                          setState(() {
                                            if (isSelected) {
                                              _selectedFiles.removeWhere((f) => f.path == file.path);
                                            } else {
                                              _selectedFiles.add(file);
                                            }
                                          });
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            // Thumbnail
                                            Container(
                                              width: 38,
                                              height: 50,
                                              decoration: BoxDecoration(
                                                color: EditorialTokens.surfaceMuted,
                                                borderRadius: BorderRadius.circular(EditorialTokens.r2),
                                                border: Border.all(
                                                  color: EditorialTokens.borderSoft,
                                                  width: EditorialTokens.hairline,
                                                ),
                                              ),
                                              child: FutureBuilder<File?>(
                                                future: ThumbnailCacheService.getThumbnailFile(file.path),
                                                builder: (context, snapshot) {
                                                  if (snapshot.connectionState == ConnectionState.done &&
                                                      snapshot.data != null &&
                                                      snapshot.data!.existsSync()) {
                                                    return ClipRRect(
                                                      borderRadius: BorderRadius.circular(EditorialTokens.r2),
                                                      child: Image.file(snapshot.data!, fit: BoxFit.cover),
                                                    );
                                                  }
                                                  return const Icon(
                                                    Icons.picture_as_pdf_outlined,
                                                    size: 18,
                                                    color: EditorialTokens.primary,
                                                  );
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    file.name,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: EditorialTokens.titleSmall().copyWith(
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    '${file.pageCount > 0 ? "${file.pageCount} PAGES" : "PAGES UNKNOWN"}  ·  ${Utils.formatBytes(file.sizeBytes).toUpperCase()}',
                                                    style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                                                  ),
                                                  if (folder.isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      folder.toUpperCase(),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: EditorialTokens.metadata(
                                                        color: EditorialTokens.inkMuted.withOpacity(0.8),
                                                      ).copyWith(fontSize: 9),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (widget.mode == ToolPickerMode.multiSelect)
                                              Icon(
                                                isSelected ? Icons.check_circle : Icons.circle_outlined,
                                                size: 18,
                                                color: isSelected ? EditorialTokens.primary : EditorialTokens.border,
                                              )
                                            else
                                              const Icon(
                                                Icons.chevron_right,
                                                size: 18,
                                                color: EditorialTokens.inkMuted,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),

                      // Bottom Action Bar for Multi-select Mode
                      if (widget.mode == ToolPickerMode.multiSelect)
                        Container(
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
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${_selectedFiles.length} DOCUMENTS SELECTED',
                                    style: EditorialTokens.metadataStrong(
                                      color: _selectedFiles.isNotEmpty ? EditorialTokens.primary : EditorialTokens.inkMuted,
                                    ),
                                  ),
                                  Text(
                                    'TOTAL $_totalSelectedPages PAGES',
                                    style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              EditorialSecondaryButton(
                                label: 'Cancel',
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 8),
                              EditorialButton(
                                label: widget.actionButtonText ?? 'Assemble',
                                onPressed: _selectedFiles.isNotEmpty
                                    ? () => Navigator.pop(context, _selectedFiles)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
                loading: () => const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: EditorialTokens.primary,
                    ),
                  ),
                ),
                error: (err, _) => Center(
                  child: Text('Error loading files: $err', style: EditorialTokens.metadata()),
                ),
              ),
            ),
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
            icon: const Icon(Icons.arrow_back, color: EditorialTokens.ink, size: 20),
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
                const EditorialEyebrow(text: 'DOCUMENT LIBRARY'),
                const SizedBox(height: 2),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EditorialTokens.titleLarge(),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.sort, color: EditorialTokens.ink, size: 20),
            onPressed: _showSortDialog,
            tooltip: 'Sort Documents',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          if (widget.mode == ToolPickerMode.multiSelect && _selectedFiles.isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.swap_vert,
                color: _showReorderSheet ? EditorialTokens.primary : EditorialTokens.ink,
                size: 20,
              ),
              onPressed: () => setState(() => _showReorderSheet = !_showReorderSheet),
              tooltip: 'Sequence order',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: EditorialTokens.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: EditorialTokens.surfaceMuted,
          borderRadius: BorderRadius.circular(EditorialTokens.r4),
          border: Border.all(
            color: EditorialTokens.borderSoft,
            width: EditorialTokens.hairline,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 16, color: EditorialTokens.inkMuted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: EditorialTokens.bodyMedium(color: EditorialTokens.ink),
                decoration: InputDecoration(
                  hintText: 'SEARCH ARCHIVE BY TITLE OR FOLDER...',
                  hintStyle: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: const Icon(Icons.clear, size: 16, color: EditorialTokens.inkMuted),
              ),
          ],
        ),
      ),
    );
  }
}
