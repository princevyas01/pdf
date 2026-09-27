import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/database_helper.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../models/pdf_file.dart';
import '../../widgets/editorial_components.dart';
import '../../widgets/pdf_file_card.dart';
import '../home/pdf_list_provider.dart';
import '../viewer/pdf_viewer_screen.dart';
import '../ocr/ocr_screen.dart';

class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  bool _searchInside = false;
  List<PdfFile> _searchResults = [];
  List<String> _recentSearches = [];
  bool _isSearching = false;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _searchGeneration++;
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final currentGen = ++_searchGeneration;
    setState(() => _isSearching = true);

    final results = await DatabaseHelper.instance.searchPdfFiles(
      query,
      searchInside: _searchInside,
    );

    if (mounted && currentGen == _searchGeneration) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  void _addToRecent(String query) {
    if (query.trim().isEmpty) return;
    setState(() {
      _recentSearches.remove(query);
      _recentSearches.insert(0, query);
      if (_recentSearches.length > 10) {
        _recentSearches = _recentSearches.sublist(0, 10);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                const EditorialEyebrow(text: 'DOCUMENT SEARCH'),
                Text(
                  'Search Documents',
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
          // Search Input Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                    borderRadius: BorderRadius.circular(EditorialTokens.r4),
                    border: Border.all(
                      color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                      width: EditorialTokens.hairline,
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (query) => _addToRecent(query),
                    style: EditorialTokens.bodyMedium(
                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search by title, author, or keywords...',
                      hintStyle: EditorialTokens.bodySmall(
                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 20,
                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear,
                                size: 18,
                                color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                              ),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // OCR Search Inside Filter Strip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(EditorialTokens.r4),
                    border: Border.all(
                      color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                      width: EditorialTokens.hairline,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.manage_search,
                            size: 16,
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Search inside extracted OCR text',
                            style: EditorialTokens.label(
                              color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                            ).copyWith(fontSize: 11.5),
                          ),
                        ],
                      ),
                      Switch(
                        value: _searchInside,
                        activeColor: EditorialTokens.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (val) {
                          setState(() => _searchInside = val);
                          _onSearchChanged();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Search Stats Strip if active
          if (_searchController.text.isNotEmpty)
            EditorialStatStrip(
              primaryText: 'QUERY · ${_searchController.text.trim().toUpperCase()}',
              secondaryText: '${_searchResults.length} Results Found',
            ),

          Expanded(
            child: _searchController.text.isEmpty
                ? _buildRecentSearches(isDark)
                : _isSearching
                    ? const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: EditorialTokens.primary,
                        ),
                      )
                    : _searchResults.isEmpty
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
                                      Icons.search_off_outlined,
                                      size: 40,
                                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No Matching Documents',
                                      style: EditorialTokens.headlineSmall(
                                        color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'No documents match "${_searchController.text.trim()}". Try adjusting spelling or toggle OCR search.',
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
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final file = _searchResults[index];
                              final hasOcr = file.extractedText != null && file.extractedText!.isNotEmpty;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    PdfFileCard(
                                      file: file,
                                      onTap: () {
                                        _addToRecent(_searchController.text.trim());
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
                                    ),
                                    if (_searchInside && !hasOcr)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 12, right: 12, top: 4),
                                        child: Row(
                                          children: [
                                            Text(
                                              'Full text not yet extracted for this document',
                                              style: EditorialTokens.metadata(
                                                color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                              ),
                                            ),
                                            const Spacer(),
                                            InkWell(
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => OcrScreen(sourceFile: file),
                                                  ),
                                                );
                                              },
                                              child: Text(
                                                'EXTRACT OCR',
                                                style: EditorialTokens.metadataStrong(color: EditorialTokens.primary),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSearches(bool isDark) {
    if (_recentSearches.isEmpty) {
      return Center(
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
                  Icons.manage_search_outlined,
                  size: 40,
                  color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Search Library',
                  style: EditorialTokens.headlineSmall(
                    color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Search by filename or enable OCR text search to scan within document bodies.',
                  style: EditorialTokens.bodySmall(
                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            'RECENT QUERIES',
            style: EditorialTokens.eyebrow(color: EditorialTokens.primary),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recentSearches.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final term = _recentSearches[index];
              return Container(
                decoration: BoxDecoration(
                  color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                  borderRadius: BorderRadius.circular(EditorialTokens.r4),
                  border: Border.all(
                    color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                    width: EditorialTokens.hairline,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.history,
                    size: 18,
                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                  ),
                  title: Text(
                    term,
                    style: EditorialTokens.bodyMedium(
                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 16,
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    ),
                    onPressed: () {
                      setState(() => _recentSearches.removeAt(index));
                    },
                  ),
                  onTap: () {
                    _searchController.text = term;
                    _onSearchChanged();
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
