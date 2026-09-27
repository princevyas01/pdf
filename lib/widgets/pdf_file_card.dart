import 'dart:io';
import 'package:flutter/material.dart';
import '../core/storage/thumbnail_cache_service.dart';
import '../core/theme/editorial_tokens.dart';
import '../core/utils/utils.dart';
import '../models/pdf_file.dart';
import 'editorial_components.dart';

class PdfFileCard extends StatefulWidget {
  final PdfFile file;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onDelete;
  final Function(String)? onMenuAction;
  final VoidCallback? onMoreOptions;
  final bool showFolderPath;

  const PdfFileCard({
    super.key,
    required this.file,
    required this.onTap,
    this.onFavoriteToggle,
    this.onToggleFavorite,
    this.onDelete,
    this.onMenuAction,
    this.onMoreOptions,
    this.showFolderPath = true,
  });

  @override
  State<PdfFileCard> createState() => _PdfFileCardState();
}

class _PdfFileCardState extends State<PdfFileCard> {
  File? _thumbnailFile;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant PdfFileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    if (!mounted) return;
    final file = await ThumbnailCacheService.getThumbnailFile(widget.file.path);
    if (mounted) {
      setState(() {
        _thumbnailFile = file;
      });
    }
  }

  void _showOperationsSheet(BuildContext context) {
    if (widget.onMoreOptions != null) {
      widget.onMoreOptions!();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditorialDocumentOperationsSheet(
        fileName: widget.file.name,
        pageCount: widget.file.pageCount,
        sizeBytes: widget.file.sizeBytes,
        isFavorite: widget.file.isFavorite,
        onAction: (action) {
          if (action == 'delete') {
            if (widget.onDelete != null) {
              widget.onDelete!();
            } else {
              widget.onMenuAction?.call('delete');
            }
          } else {
            widget.onMenuAction?.call(action);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final folderPath = file.folder ??
        (file.path.contains(Platform.pathSeparator)
            ? file.path
                .substring(0, file.path.lastIndexOf(Platform.pathSeparator))
            : '');

    final progressPct = (file.readingProgress * 100).toInt();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surfaceStrong,
        borderRadius: BorderRadius.circular(EditorialTokens.r8),
        border: Border.all(
          color: isDark
              ? EditorialTokens.darkBorderSoft
              : EditorialTokens.borderSoft,
          width: EditorialTokens.hairline,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(EditorialTokens.r8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1:1.414 ISO Physical Paper Thumbnail
                EditorialPaperThumbnail(
                  thumbnailPath: _thumbnailFile?.path,
                  pageNumber: file.lastOpenedPage > 0
                      ? file.lastOpenedPage
                      : (file.pageCount > 0 ? file.pageCount : 1),
                  totalPages: file.pageCount,
                  isCompleted: file.completed,
                  progressPercent: file.readingProgress,
                  width: 44,
                  height: 62,
                ),
                const SizedBox(width: 12),

                // Main metadata column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: EditorialTokens.title(
                          color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                        ).copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 5),
                      EditorialMetadata(
                        text:
                            '${file.pageCount > 0 ? "${file.pageCount} pages" : "PDF"} · ${Utils.formatBytes(file.sizeBytes)}${progressPct > 0 ? " · $progressPct% read" : ""}',
                        color: isDark
                            ? EditorialTokens.darkInkSecondary
                            : EditorialTokens.inkSecondary,
                      ),
                      if (widget.showFolderPath && folderPath.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        EditorialMetadata(
                          text: folderPath,
                          color: isDark
                              ? EditorialTokens.darkInkMuted
                              : EditorialTokens.inkMuted,
                        ),
                      ],
                      if (file.readingProgress > 0 && !file.completed) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(1),
                          child: LinearProgressIndicator(
                            value: file.readingProgress,
                            backgroundColor: isDark
                                ? EditorialTokens.darkSurfaceMuted
                                : EditorialTokens.surfaceMuted,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              EditorialTokens.primary,
                            ),
                            minHeight: 2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 6),

                // Star & Menu Actions
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: Icon(
                        file.isFavorite ? Icons.star : Icons.star_border,
                        color: file.isFavorite
                            ? EditorialTokens.primary
                            : (isDark
                                ? EditorialTokens.darkInkMuted
                                : EditorialTokens.inkMuted),
                      ),
                      onPressed: () {
                        final cb =
                            widget.onFavoriteToggle ?? widget.onToggleFavorite;
                        if (cb != null) cb();
                      },
                    ),
                    IconButton(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: Icon(
                        Icons.more_vert,
                        color: isDark
                            ? EditorialTokens.darkInkMuted
                            : EditorialTokens.inkMuted,
                      ),
                      onPressed: () => _showOperationsSheet(context),
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
}
