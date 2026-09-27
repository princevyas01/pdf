import 'dart:io';
import 'package:flutter/material.dart';
import '../core/theme/editorial_tokens.dart';

/// Design 01: Quiet Editorial Document Studio shared visual components.
/// Strictly implements the visual specification from Stitch Design 01.

// 1. Editorial Eyebrow
class EditorialEyebrow extends StatelessWidget {
  final String text;
  final Color? color;

  const EditorialEyebrow({
    super.key,
    required this.text,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: EditorialTokens.eyebrow(
        color: color ?? EditorialTokens.inkSecondary,
      ),
    );
  }
}

// 2. Editorial Page Header
class EditorialPageHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;

  const EditorialPageHeader({
    super.key,
    this.eyebrow = 'OFFLINE PDF',
    required this.title,
    this.trailing,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? EditorialTokens.darkCanvas : EditorialTokens.canvas,
        border: Border(
          bottom: BorderSide(
            color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
            width: EditorialTokens.hairline,
          ),
        ),
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                EditorialEyebrow(
                  text: eyebrow,
                  color: EditorialTokens.primary,
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EditorialTokens.displayMedium(
                    color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// 3. Editorial Section Header
class EditorialSectionHeader extends StatelessWidget {
  final String? number;
  final String label;
  final String? count;
  final String? trailing;

  const EditorialSectionHeader({
    super.key,
    this.number,
    required this.label,
    this.count,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (number != null && number!.isNotEmpty)
            Text(
              '$number · ',
              style: EditorialTokens.eyebrow(
                color: EditorialTokens.primary,
              ),
            ),
          Expanded(
            child: Text(
              label,
              style: EditorialTokens.displayMedium(
                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
              ).copyWith(fontSize: 17),
            ),
          ),
          if (count != null)
            Text(
              count!,
              style: EditorialTokens.metadata(
                color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
              ),
            ),
          if (trailing != null)
            Text(
              trailing!,
              style: EditorialTokens.metadata(
                color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
              ),
            ),
        ],
      ),
    );
  }
}

// 4. Editorial Divider
class EditorialDivider extends StatelessWidget {
  final double height;

  const EditorialDivider({super.key, this.height = 1});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: height,
      thickness: EditorialTokens.hairline,
      color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
    );
  }
}

// 5. Editorial Chip
class EditorialChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const EditorialChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? EditorialTokens.primary : EditorialTokens.secondary)
                : (isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected
                  ? (isDark ? EditorialTokens.primary : EditorialTokens.secondary)
                  : (isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft),
              width: EditorialTokens.hairline,
            ),
          ),
          child: Text(
            label,
            style: EditorialTokens.label(
              color: selected
                  ? Colors.white
                  : (isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary),
            ).copyWith(fontSize: 10.5),
          ),
        ),
      ),
    );
  }
}

// Backward compatibility alias
typedef EditorialFilterChip = EditorialChip;

// 6. Editorial Button (Primary)
class EditorialButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isDestructive;

  const EditorialButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDestructive ? EditorialTokens.error : EditorialTokens.primary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: EditorialTokens.label(color: Colors.white).copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 7. Editorial Secondary Button
class EditorialSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const EditorialSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surfaceStrong,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
              width: EditorialTokens.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: EditorialTokens.label(
                  color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                ).copyWith(fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 8. Editorial Metadata Text
class EditorialMetadata extends StatelessWidget {
  final String text;
  final Color? color;
  final int maxLines;

  const EditorialMetadata({
    super.key,
    required this.text,
    this.color,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: EditorialTokens.metadata(
        color: color ?? (isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary),
      ),
    );
  }
}

// 9. Editorial Stat Strip
class EditorialStatStrip extends StatelessWidget {
  final String primaryText;
  final String secondaryText;

  const EditorialStatStrip({
    super.key,
    required this.primaryText,
    required this.secondaryText,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            primaryText,
            style: EditorialTokens.metadataStrong(
              color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
            ),
          ),
          Text(
            secondaryText.toUpperCase(),
            style: EditorialTokens.eyebrow(
              color: EditorialTokens.primary,
            ).copyWith(fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

// 10. Physical Paper Thumbnail (1:1.414 ISO paper aspect ratio)
class EditorialPaperThumbnail extends StatelessWidget {
  final String? thumbnailPath;
  final int pageNumber;
  final int totalPages;
  final double? progressPercent;
  final bool isCompleted;
  final double width;
  final double height;

  const EditorialPaperThumbnail({
    super.key,
    this.thumbnailPath,
    this.pageNumber = 1,
    this.totalPages = 1,
    this.progressPercent,
    this.isCompleted = false,
    this.width = 46,
    this.height = 65,
  });

  @override
  Widget build(BuildContext context) {
    final hasValidThumbnail = thumbnailPath != null &&
        thumbnailPath!.isNotEmpty &&
        File(thumbnailPath!).existsSync();

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: EditorialTokens.paper,
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: EditorialTokens.border,
          width: EditorialTokens.hairline,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x121C1A18),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (hasValidThumbnail)
            Positioned.fill(
              child: Image.file(
                File(thumbnailPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildSimulatedRules(),
              ),
            )
          else
            Positioned.fill(child: _buildSimulatedRules()),

          // Small corner page notation
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 0.5),
              decoration: BoxDecoration(
                color: isCompleted
                    ? EditorialTokens.successLight
                    : EditorialTokens.surfaceMuted,
                borderRadius: BorderRadius.circular(1.5),
              ),
              child: Text(
                isCompleted ? '✓' : 'p.$pageNumber',
                style: EditorialTokens.metadata(
                  color: isCompleted
                      ? EditorialTokens.success
                      : EditorialTokens.inkSecondary,
                ).copyWith(fontSize: 7.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          // Bottom terracotta progress baseline
          if (progressPercent != null && progressPercent! > 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 2,
                color: EditorialTokens.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSimulatedRules() {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 2.5,
            width: width * 0.65,
            color: EditorialTokens.primary.withOpacity(0.65),
          ),
          const SizedBox(height: 3),
          Container(height: 1.2, color: EditorialTokens.border),
          const SizedBox(height: 2.5),
          Container(height: 1.2, width: width * 0.8, color: EditorialTokens.border),
          const SizedBox(height: 2.5),
          Container(height: 1.2, width: width * 0.7, color: EditorialTokens.border),
          const SizedBox(height: 2.5),
          Container(height: 1.2, width: width * 0.5, color: EditorialTokens.border),
        ],
      ),
    );
  }
}

// Alias for backwards compatibility
typedef PhysicalPaperThumbnail = EditorialPaperThumbnail;

// 11. Custom Editorial Bottom Navigation Bar (Files, Favorites, Search, Tools, Stats)
class EditorialBottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelected;

  const EditorialBottomBar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  static const items = [
    (Icons.folder_outlined, 'Files'),
    (Icons.bookmark_border, 'Favorites'),
    (Icons.search, 'Search'),
    (Icons.build_outlined, 'Tools'),
    (Icons.insights_outlined, 'Stats'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: isDark ? EditorialTokens.darkCanvas : EditorialTokens.canvas,
          border: Border(
            top: BorderSide(
              color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
              width: EditorialTokens.hairline,
            ),
          ),
        ),
        child: Row(
          children: List.generate(
            items.length,
            (index) {
              final selected = index == currentIndex;
              final item = items[index];

              return Expanded(
                child: InkWell(
                  onTap: () => onSelected(index),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.$1,
                        size: selected ? 20 : 19,
                        color: selected
                            ? EditorialTokens.primary
                            : (isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.$2,
                        style: selected
                            ? EditorialTokens.label(color: EditorialTokens.primary).copyWith(fontSize: 10.5)
                            : EditorialTokens.metadata(
                                color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                              ).copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// 12. Editorial Tool Card
class EditorialToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? badge;
  final VoidCallback onTap;

  const EditorialToolCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surfaceStrong,
        borderRadius: BorderRadius.circular(EditorialTokens.r8),
        border: Border.all(
          color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
          width: EditorialTokens.hairline,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(EditorialTokens.r8),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: EditorialTokens.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: EditorialTokens.title(
                          color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                        ),
                      ),
                    ),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          badge!,
                          style: EditorialTokens.metadata(
                            color: EditorialTokens.primary,
                          ).copyWith(fontSize: 9.5, fontWeight: FontWeight.w600),
                        ),
                      )
                    else
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: EditorialTokens.bodySmall(
                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
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

// 13. Editorial Document Operations Sheet
class EditorialDocumentOperationsSheet extends StatelessWidget {
  final String fileName;
  final int pageCount;
  final int sizeBytes;
  final bool isFavorite;
  final Function(String action) onAction;

  const EditorialDocumentOperationsSheet({
    super.key,
    required this.fileName,
    required this.pageCount,
    required this.sizeBytes,
    required this.isFavorite,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final actions = [
      (Icons.menu_book_outlined, 'Study Mode', 'study'),
      (Icons.history_outlined, 'Version History', 'version'),
      (Icons.compress_outlined, 'Compress PDF', 'compress'),
      (Icons.photo_size_select_small, 'Target Size', 'target_size'),
      (Icons.edit_note_outlined, 'Edit Metadata', 'metadata'),
      (Icons.lock_outline, 'Encrypt PDF', 'encrypt'),
      (Icons.compare_arrows_outlined, 'Compare PDF', 'compare'),
      (Icons.info_outline, 'Document Info', 'info'),
      (Icons.share_outlined, 'Share Document', 'share'),
      (Icons.drive_file_rename_outline, 'Rename File', 'rename'),
    ];

    return Container(
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
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        MediaQuery.of(context).padding.bottom + 16,
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
                      text: 'DOCUMENT OPERATIONS',
                      color: EditorialTokens.primary,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const EditorialDivider(),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 360;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: isNarrow ? 2.8 : 3.4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: actions.length,
                itemBuilder: (context, i) {
              final a = actions[i];
              return InkWell(
                onTap: () {
                  Navigator.pop(context);
                  onAction(a.$3);
                },
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                      width: EditorialTokens.hairline,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        a.$1,
                        size: 16,
                        color: EditorialTokens.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          a.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: EditorialTokens.label(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ).copyWith(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () {
              Navigator.pop(context);
              onAction('delete');
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: EditorialTokens.errorLight,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: EditorialTokens.error.withOpacity(0.3),
                  width: EditorialTokens.hairline,
                ),
              ),
              child: Text(
                'Delete Document from Device',
                style: EditorialTokens.label(color: EditorialTokens.error).copyWith(fontSize: 11.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
