import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/storage/database_helper.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../core/tools/pdf_target_size_compressor_service.dart';
import '../../core/tools/pdf_version_service.dart';
import '../../core/utils/utils.dart';
import '../../models/pdf_file.dart';
import '../../widgets/editorial_components.dart';
import '../../widgets/pdf_tool_file_picker_screen.dart';
import '../home/pdf_list_provider.dart';
import '../viewer/pdf_viewer_screen.dart';

class CompressPdfToTargetSizeScreen extends ConsumerStatefulWidget {
  final PdfFile? initialFile;

  const CompressPdfToTargetSizeScreen({super.key, this.initialFile});

  @override
  ConsumerState<CompressPdfToTargetSizeScreen> createState() =>
      _CompressPdfToTargetSizeScreenState();
}

class _CompressPdfToTargetSizeScreenState
    extends ConsumerState<CompressPdfToTargetSizeScreen> {
  PdfFile? _selectedFile;
  final TextEditingController _targetSizeController =
      TextEditingController(text: '500');
  String _selectedUnit = 'KB';
  TargetCompressionQuality _quality = TargetCompressionQuality.balanced;
  bool _preserveTextVectors = true;

  bool _isCompressing = false;
  bool _isCancelled = false;
  double _progress = 0.0;
  String _progressStatus = '';
  TargetCompressionResult? _result;
  PdfFile? _createdPdfFile;

  static const List<Map<String, dynamic>> _presets = [
    {'label': 'Academic (<5MB)', 'val': 5.0, 'unit': 'MB'},
    {'label': 'Email (<1MB)', 'val': 1.0, 'unit': 'MB'},
    {'label': 'Web (<500KB)', 'val': 500.0, 'unit': 'KB'},
    {'label': 'Archival (<200KB)', 'val': 200.0, 'unit': 'KB'},
    {'label': 'Ultra (<100KB)', 'val': 100.0, 'unit': 'KB'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      _selectedFile = widget.initialFile;
      _adjustDefaultTarget(widget.initialFile!.sizeBytes);
    }
  }

  @override
  void dispose() {
    _targetSizeController.dispose();
    super.dispose();
  }

  void _adjustDefaultTarget(int originalSize) {
    if (originalSize > 0) {
      final targetBytes = (originalSize * 0.5).round();
      if (targetBytes >= 1024 * 1024) {
        _selectedUnit = 'MB';
        _targetSizeController.text =
            (targetBytes / (1024 * 1024)).toStringAsFixed(1);
      } else {
        _selectedUnit = 'KB';
        _targetSizeController.text = (targetBytes / 1024).round().toString();
      }
    }
  }

  Future<void> _pickPdf() async {
    final result = await Navigator.push<List<PdfFile>>(
      context,
      MaterialPageRoute(
        builder: (_) => const PdfToolFilePickerScreen(
          title: 'Select PDF to Downsize',
          mode: ToolPickerMode.singleSelect,
          actionButtonText: 'CONFIRM DOCUMENT',
        ),
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final picked = result.first;
      setState(() {
        _selectedFile = picked;
        _result = null;
        _createdPdfFile = null;
        _adjustDefaultTarget(picked.sizeBytes);
      });
    }
  }

  void _applyPreset(Map<String, dynamic> preset) {
    setState(() {
      _selectedUnit = preset['unit'] as String;
      final val = preset['val'] as double;
      _targetSizeController.text =
          val % 1 == 0 ? val.toInt().toString() : val.toString();
    });
  }

  int? _getTargetBytes() {
    final raw = double.tryParse(_targetSizeController.text.trim());
    if (raw == null || raw <= 0) return null;
    return _selectedUnit == 'MB'
        ? (raw * 1024 * 1024).round()
        : (raw * 1024).round();
  }

  Future<void> _startCompression() async {
    if (_selectedFile == null) {
      _showNotice('Please select a PDF document first.');
      return;
    }

    final targetBytes = _getTargetBytes();
    if (targetBytes == null || targetBytes <= 0) {
      _showNotice('Please enter a valid numeric target size.');
      return;
    }

    final originalSize = _selectedFile!.sizeBytes;
    if (originalSize > 0 && targetBytes >= originalSize) {
      _showNotice('Target size must be smaller than original size (${Utils.formatBytes(originalSize)}).');
      return;
    }

    setState(() {
      _isCompressing = true;
      _isCancelled = false;
      _progress = 0.05;
      _progressStatus = 'Initializing async isolate...';
      _result = null;
      _createdPdfFile = null;
    });

    try {
      final sizeLabel = _selectedUnit == 'MB'
          ? '${_targetSizeController.text.trim()}MB'
          : '${_targetSizeController.text.trim()}KB';

      final result = await PdfTargetSizeCompressorService.compressPdfToTargetSize(
        inputPath: _selectedFile!.path,
        targetBytes: targetBytes,
        quality: _quality,
        preserveTextVectors: _preserveTextVectors,
        isCancelled: () => _isCancelled,
        onProgress: (p, status) {
          if (!_isCancelled && mounted) {
            setState(() {
              _progress = p;
              _progressStatus = status;
            });
          }
        },
      );

      if (_isCancelled) {
        final f = File(result.outputPath);
        if (await f.exists()) await f.delete();
        return;
      }

      PdfFile? created;
      if (result.outputSizeBytes > 0 && await File(result.outputPath).exists()) {
        final stat = await File(result.outputPath).stat();
        final docId = DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
            result.outputPath.hashCode.toRadixString(36);

        created = PdfFile(
          docId: docId,
          path: result.outputPath,
          name: result.outputPath.split(Platform.pathSeparator).last,
          sizeBytes: stat.size,
          modifiedAt: stat.modified.millisecondsSinceEpoch,
          pageCount: result.pageCount,
          sourceType: 'compressed',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );

        await DatabaseHelper.instance.upsertPdfFile(created);
        ref.read(pdfListProvider.notifier).addFile(created);

        await PdfVersionService.createVersion(
          docId: _selectedFile!.path,
          filePath: result.outputPath,
          sourceOperation: 'Compress Target: $sizeLabel',
        );
      }

      if (mounted) {
        setState(() {
          _isCompressing = false;
          _result = result;
          _createdPdfFile = created;
          _progress = 1.0;
        });

        if (result.outputSizeBytes == 0) {
          _showNotice(result.statusMessage);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCompressing = false);
        _showNotice('Compression failed: $e');
      }
    }
  }

  void _showNotice(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: EditorialTokens.bodyMedium(color: Colors.white)),
        backgroundColor: EditorialTokens.secondary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _cancelCompression() {
    _isCancelled = true;
    setState(() {
      _isCompressing = false;
      _progressStatus = 'Compression cancelled';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final targetBytes = _getTargetBytes();
    final originalBytes = _selectedFile?.sizeBytes ?? 0;
    double? reductionPct;
    if (targetBytes != null && originalBytes > 0 && targetBytes < originalBytes) {
      reductionPct = ((originalBytes - targetBytes) / originalBytes) * 100.0;
    }

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
            const EditorialEyebrow(text: 'FILE COMPRESSION'),
            Text(
              'Compress to Target Size',
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
          // Section 01: Selected Document
          const EditorialSectionHeader(
            number: '01',
            label: 'Selected Document',
          ),
          const SizedBox(height: 8),
          if (_selectedFile != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                borderRadius: BorderRadius.circular(EditorialTokens.r4),
                border: Border.all(
                  color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                  width: EditorialTokens.hairline,
                ),
              ),
              child: Row(
                children: [
                  const EditorialPaperThumbnail(
                    thumbnailPath: null,
                    width: 44,
                    height: 60,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedFile!.name,
                          style: EditorialTokens.titleSmall(
                            color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${Utils.formatBytes(_selectedFile!.sizeBytes)} · ${_selectedFile!.pageCount} Pages',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.swap_horiz,
                      size: 20,
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    ),
                    onPressed: _isCompressing ? null : _pickPdf,
                    tooltip: 'Change document',
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                borderRadius: BorderRadius.circular(EditorialTokens.r4),
                border: Border.all(
                  color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                  width: EditorialTokens.hairline,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.tune_outlined,
                    size: 36,
                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No document selected',
                    style: EditorialTokens.titleSmall(
                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select a PDF from your library to compress to an exact kilobyte or megabyte target',
                    style: EditorialTokens.bodySmall(
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  EditorialSecondaryButton(
                    label: 'Choose Document',
                    icon: Icons.folder_open,
                    onPressed: _pickPdf,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Section 02: Budget Presets
          const EditorialSectionHeader(
            number: '02',
            label: 'Target Size Presets',
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _presets.map((preset) {
                final val = preset['val'] as double;
                final valStr = val % 1 == 0 ? val.toInt().toString() : val.toString();
                final isSelected = _selectedUnit == preset['unit'] &&
                    _targetSizeController.text.trim() == valStr;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: EditorialChip(
                    label: preset['label'] as String,
                    selected: isSelected,
                    onTap: _isCompressing ? () {} : () => _applyPreset(preset),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // Section 03: Target Budget Parameters
          const EditorialSectionHeader(
            number: '03',
            label: 'Target Size Specification',
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
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
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MAXIMUM TARGET SIZE',
                            style: EditorialTokens.metadataStrong(
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ).copyWith(fontSize: 10),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _targetSizeController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            enabled: !_isCompressing,
                            style: EditorialTokens.bodyMedium(
                              color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                            ),
                            decoration: InputDecoration(
                              hintText: '500',
                              filled: true,
                              fillColor: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(EditorialTokens.r4),
                                borderSide: BorderSide(
                                  color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                                  width: EditorialTokens.hairline,
                                ),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'UNIT',
                            style: EditorialTokens.metadataStrong(
                              color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                            ).copyWith(fontSize: 10),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                              borderRadius: BorderRadius.circular(EditorialTokens.r4),
                              border: Border.all(
                                color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                                width: EditorialTokens.hairline,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedUnit,
                                isExpanded: true,
                                icon: Icon(
                                  Icons.arrow_drop_down,
                                  color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'KB', child: Text('KB')),
                                  DropdownMenuItem(value: 'MB', child: Text('MB')),
                                ],
                                onChanged: _isCompressing
                                    ? null
                                    : (val) {
                                        if (val != null) setState(() => _selectedUnit = val);
                                      },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (reductionPct != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: EditorialTokens.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(EditorialTokens.r2),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'PROJECTED REDUCTION: -${reductionPct.toStringAsFixed(1)}%',
                          style: EditorialTokens.metadataStrong(color: EditorialTokens.primary),
                        ),
                        const Spacer(),
                        Text(
                          '${Utils.formatBytes(originalBytes)} → ${Utils.formatBytes(targetBytes!)}',
                          style: EditorialTokens.metadata(color: EditorialTokens.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section 04: Quality Strategy & Settings
          const EditorialSectionHeader(
            number: '04',
            label: 'Quality & Compression Settings',
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
              borderRadius: BorderRadius.circular(EditorialTokens.r4),
              border: Border.all(
                color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                width: EditorialTokens.hairline,
              ),
            ),
            child: Column(
              children: [
                _buildStrategyTile(
                  title: 'Balanced',
                  subtitle: 'Optimal compromise between size target and visual sharpness',
                  selected: _quality == TargetCompressionQuality.balanced,
                  onTap: () => setState(() => _quality = TargetCompressionQuality.balanced),
                  isDark: isDark,
                ),
                const EditorialDivider(),
                _buildStrategyTile(
                  title: 'High Quality',
                  subtitle: 'Preserves higher image resolution and detail',
                  selected: _quality == TargetCompressionQuality.betterQuality,
                  onTap: () => setState(() => _quality = TargetCompressionQuality.betterQuality),
                  isDark: isDark,
                ),
                const EditorialDivider(),
                _buildStrategyTile(
                  title: 'Maximum Compression',
                  subtitle: 'Reduces image sizes to meet tight file limits',
                  selected: _quality == TargetCompressionQuality.maximumCompression,
                  onTap: () => setState(() => _quality = TargetCompressionQuality.maximumCompression),
                  isDark: isDark,
                ),
                const EditorialDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Preserve Text & Vector Graphics',
                              style: EditorialTokens.titleSmall(
                                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Prevents text rasterization; preserves sharp typography',
                              style: EditorialTokens.bodySmall(
                                color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _preserveTextVectors,
                        onChanged: _isCompressing
                            ? null
                            : (v) => setState(() => _preserveTextVectors = v),
                        activeColor: EditorialTokens.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // In-progress or Primary Action
          if (_isCompressing) ...[
            Container(
              padding: const EdgeInsets.all(16),
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
                  Row(
                    children: [
                      const EditorialEyebrow(
                        text: 'COMPRESSING PDF...',
                        color: EditorialTokens.primary,
                      ),
                      const Spacer(),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: EditorialTokens.metadataStrong(color: EditorialTokens.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _progress.clamp(0.0, 1.0),
                    backgroundColor: isDark ? EditorialTokens.darkSurfaceMuted : EditorialTokens.surfaceMuted,
                    valueColor: const AlwaysStoppedAnimation<Color>(EditorialTokens.primary),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _progressStatus,
                    style: EditorialTokens.bodySmall(
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  EditorialSecondaryButton(
                    label: 'Cancel',
                    onPressed: _cancelCompression,
                  ),
                ],
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: EditorialButton(
                label: 'Compress to Target Size',
                icon: Icons.tune_outlined,
                onPressed: _selectedFile != null ? _startCompression : null,
              ),
            ),
          ],

          // Section 05: Result Card
          if (_result != null && _createdPdfFile != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
                borderRadius: BorderRadius.circular(EditorialTokens.r4),
                border: Border.all(
                  color: _result!.isTargetAchieved ? EditorialTokens.primary : EditorialTokens.border,
                  width: 1.0,
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
                          _result!.isTargetAchieved
                              ? 'TARGET SIZE ACHIEVED'
                              : 'CLOSEST SIZE REACHED',
                          style: EditorialTokens.metadataStrong(color: EditorialTokens.primary).copyWith(fontSize: 10),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '-${_result!.reductionPercentage.toStringAsFixed(1)}%',
                        style: EditorialTokens.displayMedium(color: EditorialTokens.primary).copyWith(fontSize: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _createdPdfFile!.name,
                    style: EditorialTokens.titleSmall(
                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${Utils.formatBytes(_result!.originalSizeBytes)} → ${Utils.formatBytes(_result!.outputSizeBytes)} (Target: ${Utils.formatBytes(_result!.targetSizeBytes)})',
                    style: EditorialTokens.metadata(
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const EditorialDivider(),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: EditorialSecondaryButton(
                          label: 'Share',
                          icon: Icons.share_outlined,
                          onPressed: () => Share.shareXFiles([XFile(_createdPdfFile!.path)]),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: EditorialButton(
                          label: 'Open Document',
                          icon: Icons.menu_book_outlined,
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PdfViewerScreen(filePath: _createdPdfFile!.path),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStrategyTile({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: _isCompressing ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: EditorialTokens.titleSmall(
                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: EditorialTokens.bodySmall(
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? EditorialTokens.primary
                      : (isDark ? EditorialTokens.darkBorder : EditorialTokens.border),
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: EditorialTokens.primary,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
