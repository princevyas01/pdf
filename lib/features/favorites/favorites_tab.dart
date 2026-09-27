import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../core/utils/utils.dart';
import '../../widgets/editorial_components.dart';
import '../../widgets/pdf_file_card.dart';
import '../home/pdf_list_provider.dart';
import '../viewer/pdf_viewer_screen.dart';
import '../merge/merge_screen.dart';
import '../delete_pages/delete_pages_screen.dart';
import '../ocr/ocr_screen.dart';

class FavoritesTab extends ConsumerWidget {
  const FavoritesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritePdfListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final totalBytes = favorites.fold<int>(0, (sum, f) => sum + f.sizeBytes);

    return Scaffold(
      backgroundColor: isDark ? EditorialTokens.darkCanvas : EditorialTokens.canvas,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                  width: EditorialTokens.hairline,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const EditorialEyebrow(text: 'CURATED DOCUMENTS · BOOKMARKED'),
                Text(
                  'Favorites',
                  style: EditorialTokens.titleLarge(
                    color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Sub-strip: stats
          EditorialStatStrip(
            primaryText: 'FAVORITES · QUICK ACCESS',
            secondaryText: '${favorites.length} Starred · ${Utils.formatBytes(totalBytes)}',
          ),

          Expanded(
            child: favorites.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
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
                              Icons.star_outline,
                              size: 40,
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No Starred Documents',
                              style: EditorialTokens.headlineSmall(
                                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Star any document from the library to pin it here for immediate reading.',
                              style: EditorialTokens.bodySmall(
                                color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: favorites.length,
                    itemBuilder: (context, index) {
                      final file = favorites[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: PdfFileCard(
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
                          onMenuAction: (action) {
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
                              case 'share':
                                Share.shareXFiles([XFile(file.path)], text: 'Sharing ${file.name}');
                                break;
                              case 'delete':
                                ref.read(pdfListProvider.notifier).deleteFile(file.path);
                                break;
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
