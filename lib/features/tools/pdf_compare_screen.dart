import 'package:flutter/material.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../core/tools/pdf_compare_service.dart';
import '../../core/utils/utils.dart';
import '../../models/pdf_compare_result.dart';
import '../../models/pdf_file.dart';
import '../../widgets/editorial_components.dart';
import '../../widgets/pdf_tool_file_picker_screen.dart';

class PdfCompareScreen extends StatefulWidget {
  const PdfCompareScreen({super.key});

  @override
  State<PdfCompareScreen> createState() => _PdfCompareScreenState();
}

class _PdfCompareScreenState extends State<PdfCompareScreen> {
  PdfFile? _fileA;
  PdfFile? _fileB;
  bool _isComparing = false;
  PdfCompareResult? _result;
  int _activeTab = 0; // 0: Diff Ledger, 1: Text & Formula Delta

  Future<void> _pickFileA() async {
    final result = await Navigator.push<List<PdfFile>>(
      context,
      MaterialPageRoute(
        builder: (_) => const PdfToolFilePickerScreen(
          title: 'Select Baseline PDF (Document A)',
          mode: ToolPickerMode.singleSelect,
          actionButtonText: 'SET AS BASELINE',
        ),
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _fileA = result.first;
        _result = null;
      });
    }
  }

  Future<void> _pickFileB() async {
    final result = await Navigator.push<List<PdfFile>>(
      context,
      MaterialPageRoute(
        builder: (_) => const PdfToolFilePickerScreen(
          title: 'Select Revised PDF (Document B)',
          mode: ToolPickerMode.singleSelect,
          actionButtonText: 'SET AS REVISED',
        ),
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _fileB = result.first;
        _result = null;
      });
    }
  }

  Future<void> _runComparison() async {
    if (_fileA == null || _fileB == null) return;
    setState(() => _isComparing = true);

    final res = await PdfCompareService.comparePdfs(
      fileAPath: _fileA!.path,
      fileBPath: _fileB!.path,
    );

    if (mounted) {
      setState(() {
        _result = res;
        _isComparing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            const EditorialEyebrow(text: 'DOCUMENT COMPARISON'),
            Text(
              'Compare Revisions',
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
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // Section 01: Dual Document Selection
          const EditorialSectionHeader(
            number: '01',
            label: 'Select Documents',
          ),
          const SizedBox(height: 8),

          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 360;
              if (isNarrow) {
                return Column(
                  children: [
                    _buildDocumentCard(
                      label: 'DOCUMENT A (BASELINE)',
                      file: _fileA,
                      onSelect: _pickFileA,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _buildDocumentCard(
                      label: 'DOCUMENT B (REVISED)',
                      file: _fileB,
                      onSelect: _pickFileB,
                      isDark: isDark,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: _buildDocumentCard(
                      label: 'DOCUMENT A (BASELINE)',
                      file: _fileA,
                      onSelect: _pickFileA,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDocumentCard(
                      label: 'DOCUMENT B (REVISED)',
                      file: _fileB,
                      onSelect: _pickFileB,
                      isDark: isDark,
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 20),

          // Compare Action Button
          SizedBox(
            width: double.infinity,
            child: EditorialButton(
              label: _isComparing ? 'ANALYZING DOCUMENTS...' : 'COMPARE DOCUMENTS',
              icon: _isComparing ? null : Icons.compare_arrows_outlined,
              onPressed: (_fileA == null || _fileB == null || _isComparing) ? null : _runComparison,
            ),
          ),

          if (_result != null) ...[
            const SizedBox(height: 28),

            // Section 02: Diff Summary
            const EditorialSectionHeader(
              number: '02',
              label: 'Comparison Summary',
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                borderRadius: BorderRadius.circular(EditorialTokens.r4),
                border: Border.all(
                  color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                  width: EditorialTokens.hairline,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: EditorialTokens.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(EditorialTokens.r2),
                        ),
                        child: Text(
                          'DELTA ANALYSIS COMPLETE',
                          style: EditorialTokens.metadataStrong(color: EditorialTokens.primary).copyWith(fontSize: 9.5),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_result!.pageDiffs.length} PAGES ANALYZED',
                        style: EditorialTokens.metadata(
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _result!.summary,
                    style: EditorialTokens.titleSmall(
                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // View Tabs
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  EditorialChip(
                    label: 'Diff Ledger',
                    selected: _activeTab == 0,
                    onTap: () => setState(() => _activeTab = 0),
                  ),
                  const SizedBox(width: 8),
                  EditorialChip(
                    label: 'Text & Formula Delta',
                    selected: _activeTab == 1,
                    onTap: () => setState(() => _activeTab = 1),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Diff Ledger List
            ..._result!.pageDiffs.map((diff) {
              final hasAdditions = diff.addedLines.isNotEmpty;
              final hasRemovals = diff.removedLines.isNotEmpty;
              final isIdentical = !hasAdditions && !hasRemovals;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                          EditorialEyebrow(
                            text: 'PAGE ${diff.pageNumber.toString().padLeft(2, '0')}',
                            color: EditorialTokens.primary,
                          ),
                          const Spacer(),
                          Text(
                            isIdentical
                                ? 'IDENTICAL'
                                : '+${diff.addedLines.length} / -${diff.removedLines.length} CHANGES',
                            style: EditorialTokens.metadata(
                              color: isIdentical
                                  ? (isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary)
                                  : EditorialTokens.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: isIdentical
                          ? Text(
                              'Content is verbatim across both editions.',
                              style: EditorialTokens.bodySmall(
                                color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (hasAdditions) ...[
                                  Text(
                                    'INSERTIONS (+)',
                                    style: EditorialTokens.metadataStrong(color: const Color(0xFF2E6F40)).copyWith(fontSize: 9.5),
                                  ),
                                  const SizedBox(height: 4),
                                  ...diff.addedLines.map(
                                    (l) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                                      child: Text(
                                        '+ $l',
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          color: Color(0xFF2E6F40),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                if (hasRemovals) ...[
                                  Text(
                                    'DELETIONS (-)',
                                    style: EditorialTokens.metadataStrong(color: const Color(0xFFB33A3A)).copyWith(fontSize: 9.5),
                                  ),
                                  const SizedBox(height: 4),
                                  ...diff.removedLines.map(
                                    (l) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                                      child: Text(
                                        '- $l',
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          color: Color(0xFFB33A3A),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDocumentCard({
    required String label,
    required PdfFile? file,
    required VoidCallback onSelect,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
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
          EditorialEyebrow(text: label),
          const SizedBox(height: 10),
          if (file != null) ...[
            const Center(
              child: EditorialPaperThumbnail(
                thumbnailPath: null,
                width: 38,
                height: 52,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              file.name,
              style: EditorialTokens.titleSmall(
                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${file.pageCount} Pages · ${Utils.formatBytes(file.sizeBytes)}',
              style: EditorialTokens.metadata(
                color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
              ),
            ),
            const SizedBox(height: 10),
            EditorialSecondaryButton(
              label: 'CHANGE',
              onPressed: onSelect,
            ),
          ] else ...[
            Container(
              height: 90,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.file_present_outlined,
                    size: 28,
                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'No document chosen',
                    style: EditorialTokens.bodySmall(
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            EditorialSecondaryButton(
              label: 'CHOOSE',
              icon: Icons.folder_open,
              onPressed: onSelect,
            ),
          ],
        ],
      ),
    );
  }
}
