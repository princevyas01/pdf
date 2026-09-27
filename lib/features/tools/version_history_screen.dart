import 'package:flutter/material.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../core/tools/pdf_version_service.dart';
import '../../core/utils/utils.dart';
import '../../models/pdf_file.dart';
import '../../models/pdf_version.dart';
import '../../widgets/editorial_components.dart';

class VersionHistoryScreen extends StatefulWidget {
  final PdfFile pdfFile;

  const VersionHistoryScreen({super.key, required this.pdfFile});

  @override
  State<VersionHistoryScreen> createState() => _VersionHistoryScreenState();
}

class _VersionHistoryScreenState extends State<VersionHistoryScreen> {
  List<PdfVersion> _versions = [];
  bool _isLoading = true;
  int _totalSizeBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    final versions = await PdfVersionService.getVersions(widget.pdfFile.path);
    final totalStorage = await PdfVersionService.calculateTotalStorage(widget.pdfFile.path);
    if (mounted) {
      setState(() {
        _versions = versions;
        _totalSizeBytes = totalStorage > 0 ? totalStorage : widget.pdfFile.sizeBytes;
        _isLoading = false;
      });
    }
  }

  Future<void> _restoreVersion(PdfVersion version) async {
    final ok = await PdfVersionService.restoreVersion(version, widget.pdfFile.path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Restored version ${version.versionNumber} successfully' : 'Failed to restore version')),
      );
      if (ok) _loadVersions();
    }
  }

  Future<void> _deleteVersion(PdfVersion version) async {
    await PdfVersionService.deleteVersion(version);
    _loadVersions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EditorialTokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const EditorialDivider(),
            EditorialStatStrip(
              primaryText: 'TOTAL STORAGE',
              secondaryText: '${Utils.formatBytes(_totalSizeBytes).toUpperCase()} · ${_versions.length} VERSIONS',
            ),
            const EditorialDivider(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: EditorialTokens.primary,
                        ),
                      ),
                    )
                  : (_versions.isEmpty ? _buildEmptyVersions() : _buildVersionsList()),
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
                const EditorialEyebrow(text: 'DOCUMENT HISTORY'),
                const SizedBox(height: 2),
                Text(
                  'Version History',
                  style: EditorialTokens.titleLarge(),
                ),
                Text(
                  widget.pdfFile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyVersions() {
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
                Icons.history,
                size: 36,
                color: EditorialTokens.inkSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Historical Versions',
              style: EditorialTokens.titleMedium().copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Compression, editing, and encryption operations generate automatic restore points here.',
              textAlign: TextAlign.center,
              style: EditorialTokens.bodySmall(color: EditorialTokens.inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionsList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _versions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final v = _versions[index];
        return Container(
          padding: const EdgeInsets.all(14),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: EditorialTokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(EditorialTokens.r2),
                  border: Border.all(
                    color: EditorialTokens.border,
                    width: EditorialTokens.hairline,
                  ),
                ),
                child: Text(
                  'v${v.versionNumber}',
                  style: EditorialTokens.metadataStrong(color: EditorialTokens.primary).copyWith(fontSize: 10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.sourceOperation,
                      style: EditorialTokens.titleSmall().copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Utils.formatBytes(v.sizeBytes).toUpperCase()}  ·  ${Utils.formatRelativeTime(v.timestamp).toUpperCase()}',
                      style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.restore, color: EditorialTokens.tertiary, size: 18),
                tooltip: 'Restore Version',
                onPressed: () => _restoreVersion(v),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: EditorialTokens.inkMuted, size: 18),
                tooltip: 'Delete Version',
                onPressed: () => _deleteVersion(v),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        );
      },
    );
  }
}
