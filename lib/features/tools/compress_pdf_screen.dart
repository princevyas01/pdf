import 'package:flutter/material.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../core/tools/pdf_compression_service.dart';
import '../../core/tools/pdf_version_service.dart';
import '../../core/utils/utils.dart';
import '../../models/pdf_file.dart';
import '../../widgets/editorial_components.dart';

class CompressPdfScreen extends StatefulWidget {
  final PdfFile pdfFile;

  const CompressPdfScreen({super.key, required this.pdfFile});

  @override
  State<CompressPdfScreen> createState() => _CompressPdfScreenState();
}

class _CompressPdfScreenState extends State<CompressPdfScreen> {
  CompressionQuality _quality = CompressionQuality.medium;
  bool _isCompressing = false;
  CompressionResult? _result;

  Future<void> _compress() async {
    setState(() => _isCompressing = true);

    final outputPath = widget.pdfFile.path.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false), '_compressed.pdf');

    final result = await PdfCompressionService.compressPdf(
      inputPath: widget.pdfFile.path,
      outputPath: outputPath,
      quality: _quality,
    );

    await PdfVersionService.createVersion(
      docId: widget.pdfFile.path,
      filePath: outputPath,
      sourceOperation: 'Compressed (${_quality.name})',
    );

    if (mounted) {
      setState(() {
        _result = result;
        _isCompressing = false;
      });
    }
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: EditorialTokens.paper,
                        borderRadius: BorderRadius.circular(EditorialTokens.r6),
                        border: Border.all(
                          color: EditorialTokens.border,
                          width: EditorialTokens.hairline,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const EditorialEyebrow(text: 'DOCUMENT INFO'),
                          const SizedBox(height: 6),
                          Text(
                            widget.pdfFile.name,
                            style: EditorialTokens.titleMedium().copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'ORIGINAL SIZE: ${Utils.formatBytes(widget.pdfFile.sizeBytes).toUpperCase()}  ·  ${widget.pdfFile.pageCount} PAGES',
                            style: EditorialTokens.metadata(color: EditorialTokens.primary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const EditorialSectionHeader(
                      number: '01',
                      label: 'Compression Strategy',
                      trailing: 'OFFLINE',
                    ),
                    const SizedBox(height: 8),
                    _buildQualityOption(
                      quality: CompressionQuality.low,
                      title: 'Minimal Compression',
                      desc: 'Highest visual fidelity for fine typography and vectors.',
                      ratio: '~20% Reduction',
                    ),
                    const SizedBox(height: 8),
                    _buildQualityOption(
                      quality: CompressionQuality.medium,
                      title: 'Balanced Optimization',
                      desc: 'Optimal balance for reading, sharing, and archival storage.',
                      ratio: '~45% Reduction',
                    ),
                    const SizedBox(height: 8),
                    _buildQualityOption(
                      quality: CompressionQuality.high,
                      title: 'Aggressive Compact',
                      desc: 'Maximum size reduction for email delivery and low storage.',
                      ratio: '~70% Reduction',
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: EditorialButton(
                        label: _isCompressing ? 'Compressing...' : 'Compress PDF',
                        icon: Icons.compress,
                        onPressed: _isCompressing ? null : _compress,
                      ),
                    ),
                    if (_result != null) ...[
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: EditorialTokens.paper,
                          borderRadius: BorderRadius.circular(EditorialTokens.r6),
                          border: Border.all(
                            color: const Color(0xFF386641),
                            width: EditorialTokens.hairline,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.verified_outlined,
                                  color: Color(0xFF386641),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'COMPRESSION COMPLETE',
                                  style: EditorialTokens.metadataStrong(
                                    color: const Color(0xFF386641),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            EditorialStatStrip(
                              primaryText: 'SIZE REDUCTION',
                              secondaryText: '${_result!.reductionPercentage.toStringAsFixed(1)}% REDUCTION',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'ORIGINAL: ${Utils.formatBytes(_result!.originalSizeBytes)}  →  COMPRESSED: ${Utils.formatBytes(_result!.compressedSizeBytes)}',
                              style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
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
                const EditorialEyebrow(text: 'DOCUMENT COMPRESSION'),
                const SizedBox(height: 2),
                Text(
                  'Compress PDF',
                  style: EditorialTokens.titleLarge(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityOption({
    required CompressionQuality quality,
    required String title,
    required String desc,
    required String ratio,
  }) {
    final isSelected = _quality == quality;
    return GestureDetector(
      onTap: () => setState(() => _quality = quality),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFBF1EE) : EditorialTokens.paper,
          borderRadius: BorderRadius.circular(EditorialTokens.r4),
          border: Border.all(
            color: isSelected ? EditorialTokens.primary : EditorialTokens.borderSoft,
            width: isSelected ? 1.5 : EditorialTokens.hairline,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 16,
              color: isSelected ? EditorialTokens.primary : EditorialTokens.border,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: EditorialTokens.titleSmall().copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: EditorialTokens.bodySmall(color: EditorialTokens.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: EditorialTokens.surfaceMuted,
                borderRadius: BorderRadius.circular(EditorialTokens.r2),
              ),
              child: Text(
                ratio,
                style: EditorialTokens.metadata(color: EditorialTokens.tertiary).copyWith(fontSize: 9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
