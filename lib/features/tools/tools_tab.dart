import 'package:flutter/material.dart';
import '../../core/storage/database_helper.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../widgets/editorial_components.dart';
import '../merge/merge_screen.dart';
import '../split/split_screen.dart';
import '../delete_pages/delete_pages_screen.dart';
import '../scan/scan_document_screen.dart';
import '../ocr/ocr_screen.dart';
import 'pdf_compare_screen.dart';
import 'compress_pdf_to_target_size_screen.dart';
import 'compress_image_to_target_size_screen.dart';
import 'encrypt_pdf_screen.dart';

class ToolsTab extends StatefulWidget {
  const ToolsTab({super.key});

  @override
  State<ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends State<ToolsTab> {
  String _selectedCategory = 'all'; // 'all', 'transform', 'capture', 'security'
  final TextEditingController _searchController = TextEditingController();
  String _searchFilter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(String title, String desc) {
    if (_searchFilter.isEmpty) return true;
    return title.toLowerCase().contains(_searchFilter) ||
        desc.toLowerCase().contains(_searchFilter);
  }

  void _openTool(BuildContext context, String toolName, Widget screen) {
    DatabaseHelper.instance.incrementToolUsage(toolName);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? EditorialTokens.darkCanvas : EditorialTokens.canvas,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: SafeArea(
          child: Container(
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const EditorialEyebrow(
                      text: 'DOCUMENT OPERATIONS',
                      color: EditorialTokens.primary,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Document Utilities',
                      style: EditorialTokens.displayMedium(
                        color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                      ).copyWith(fontSize: 22, height: 1.1),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: EditorialTokens.tertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '100% OFFLINE',
                        style: EditorialTokens.eyebrow(
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
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
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Queued Workspace Banner
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                const Icon(Icons.layers, size: 16, color: EditorialTokens.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'QUEUED WORKSPACE',
                        style: EditorialTokens.eyebrow(color: EditorialTokens.primary).copyWith(fontSize: 9),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Direct sandboxed execution available',
                        style: EditorialTokens.metadata(
                          color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                        ).copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                EditorialSecondaryButton(
                  label: 'INSPECT →',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('All document pipelines operational and idle.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Search / Filter Input
          Container(
            margin: const EdgeInsets.only(bottom: 12),
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
                    onChanged: (val) => setState(() => _searchFilter = val.trim().toLowerCase()),
                    style: EditorialTokens.bodyMedium(
                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                    ).copyWith(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Filter transforms, processors, or integrity',
                      hintStyle: EditorialTokens.bodyMedium(
                        color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
                      ).copyWith(fontSize: 12),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_searchFilter.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchFilter = '');
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

          // Filter Chips Strip
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                EditorialChip(
                  label: 'ALL UTILITIES',
                  selected: _selectedCategory == 'all',
                  onTap: () => setState(() => _selectedCategory = 'all'),
                ),
                const SizedBox(width: 6),
                EditorialChip(
                  label: 'TRANSFORM',
                  selected: _selectedCategory == 'transform',
                  onTap: () => setState(() => _selectedCategory = 'transform'),
                ),
                const SizedBox(width: 6),
                EditorialChip(
                  label: 'CAPTURE',
                  selected: _selectedCategory == 'capture',
                  onTap: () => setState(() => _selectedCategory = 'capture'),
                ),
                const SizedBox(width: 6),
                EditorialChip(
                  label: 'SECURITY',
                  selected: _selectedCategory == 'security',
                  onTap: () => setState(() => _selectedCategory = 'security'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Group 01: Document Transformation
          if (_selectedCategory == 'all' || _selectedCategory == 'transform') ...[
            const EditorialSectionHeader(
              number: '01',
              label: 'Document Transformation',
              count: '3 modules',
            ),
            const SizedBox(height: 6),
            if (_matches('Merge PDF Documents', 'Combine multiple PDF files into a single sequential document'))
              EditorialToolCard(
                icon: Icons.layers_outlined,
                title: 'Merge PDF Documents',
                description: 'Combine multiple PDF files into a single sequential document',
                onTap: () => _openTool(context, 'merge', const MergeScreen()),
              ),
            if (_matches('Split & Extract Pages', 'Divide documents into separate files or chapters with page range selector'))
              EditorialToolCard(
                icon: Icons.splitscreen_outlined,
                title: 'Split & Extract Pages',
                description: 'Divide documents into separate files or chapters with page range selector',
                onTap: () => _openTool(context, 'split', const SplitScreen()),
              ),
            if (_matches('Delete Pages', 'Selectively remove unwanted pages using visual thumbnail selection'))
              EditorialToolCard(
                icon: Icons.delete_sweep_outlined,
                title: 'Delete Pages',
                description: 'Selectively remove unwanted pages using visual thumbnail selection',
                onTap: () => _openTool(context, 'delete_pages', const DeletePagesScreen()),
              ),
            const SizedBox(height: 16),
          ],

          // Group 02: Conversion & Capture
          if (_selectedCategory == 'all' || _selectedCategory == 'capture') ...[
            const EditorialSectionHeader(
              number: '02',
              label: 'Conversion & Capture',
              count: '3 modules',
            ),
            const SizedBox(height: 6),
            if (_matches('Document Scanner', 'Capture physical documents with high-contrast filter and perspective cropping'))
              EditorialToolCard(
                icon: Icons.document_scanner_outlined,
                title: 'Document Scanner',
                description: 'Capture physical documents with high-contrast filter and perspective cropping',
                badge: 'Vision v2',
                onTap: () => _openTool(context, 'scan', const ScanDocumentScreen()),
              ),
            if (_matches('OCR & Text Extraction', 'On-device text recognition with formula extraction and searchable PDF export'))
              EditorialToolCard(
                icon: Icons.text_snippet_outlined,
                title: 'OCR & Text Extraction',
                description: 'On-device text recognition with formula extraction and searchable PDF export',
                badge: 'ML Kit',
                onTap: () => _openTool(context, 'ocr', const OcrScreen()),
              ),
            if (_matches('Document Comparison', 'Side-by-side visual diff and page comparison across document versions'))
              EditorialToolCard(
                icon: Icons.compare_arrows_outlined,
                title: 'Document Comparison',
                description: 'Side-by-side visual diff and page comparison across document versions',
                onTap: () => _openTool(context, 'compare', const PdfCompareScreen()),
              ),
            const SizedBox(height: 16),
          ],

          // Group 03: Storage & Integrity
          if (_selectedCategory == 'all' || _selectedCategory == 'security') ...[
            const EditorialSectionHeader(
              number: '03',
              label: 'Storage & Integrity',
              count: '3 modules',
            ),
            const SizedBox(height: 6),
            if (_matches('Compress to Target Size', 'Targeted size reduction (e.g. Email <1MB, Academic <5MB) with quality controls'))
              EditorialToolCard(
                icon: Icons.tune_outlined,
                title: 'Compress to Target Size',
                description: 'Targeted size reduction (e.g. Email <1MB, Academic <5MB) with quality controls',
                badge: 'Isolate',
                onTap: () => _openTool(context, 'compress_target_size', const CompressPdfToTargetSizeScreen()),
              ),
            if (_matches('Compress Images to Size', 'Downsize standalone images to an exact target kilobyte threshold'))
              EditorialToolCard(
                icon: Icons.photo_size_select_small_outlined,
                title: 'Compress Images to Size',
                description: 'Downsize standalone images to an exact target kilobyte threshold',
                onTap: () => _openTool(context, 'compress_image_target_size', const CompressImageToTargetSizeScreen()),
              ),
            if (_matches('Encrypt PDF', 'Standard AES-256 encryption with password protection and permission locks'))
              EditorialToolCard(
                icon: Icons.lock_outline,
                title: 'Encrypt PDF',
                description: 'Standard AES-256 encryption with password protection and permission locks',
                badge: 'AES-256',
                onTap: () => _openTool(context, 'encrypt', const EncryptPdfScreen()),
              ),
            const SizedBox(height: 16),
          ],

          // System & Storage Specs Card
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
                    const EditorialEyebrow(
                      text: 'SYSTEM & STORAGE SPECS',
                      color: EditorialTokens.primary,
                    ),
                    const Spacer(),
                    Text(
                      '9 UTILITIES READY',
                      style: EditorialTokens.metadataStrong(
                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      ).copyWith(fontSize: 9.5),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const EditorialDivider(),
                const SizedBox(height: 6),
                _buildDiagnosticRow('Execution:', '100% On-Device (No Network Connection)', isDark),
                const SizedBox(height: 3),
                _buildDiagnosticRow('OCR Engine:', 'Google ML Kit Text Recognition', isDark),
                const SizedBox(height: 3),
                _buildDiagnosticRow('PDF Security:', 'Standard AES-256 Encryption', isDark),
                const SizedBox(height: 3),
                _buildDiagnosticRow('Storage Sandbox:', 'Private Device Storage', isDark),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDiagnosticRow(String label, String value, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: EditorialTokens.metadata(
            color: isDark ? EditorialTokens.darkInkMuted : EditorialTokens.inkMuted,
          ).copyWith(fontSize: 10),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: EditorialTokens.metadata(
              color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
            ).copyWith(fontSize: 10, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
