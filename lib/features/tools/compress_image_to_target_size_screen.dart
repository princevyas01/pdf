import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../core/tools/image_target_size_compressor_service.dart';
import '../../core/utils/utils.dart';
import '../../widgets/editorial_components.dart';

class CompressImageToTargetSizeScreen extends StatefulWidget {
  const CompressImageToTargetSizeScreen({super.key});

  @override
  State<CompressImageToTargetSizeScreen> createState() =>
      _CompressImageToTargetSizeScreenState();
}

class _CompressImageToTargetSizeScreenState
    extends State<CompressImageToTargetSizeScreen> {
  final List<String> _selectedImagePaths = [];
  final TextEditingController _targetSizeController =
      TextEditingController(text: '100');
  String _selectedUnit = 'KB';

  bool _isCompressing = false;
  bool _isCancelled = false;
  double _progress = 0.0;
  String _progressStatus = '';
  final List<ImageTargetCompressionResult> _results = [];

  static const List<Map<String, dynamic>> _presets = [
    {'label': '50 KB', 'val': 50.0, 'unit': 'KB'},
    {'label': '100 KB', 'val': 100.0, 'unit': 'KB'},
    {'label': '200 KB', 'val': 200.0, 'unit': 'KB'},
    {'label': '500 KB', 'val': 500.0, 'unit': 'KB'},
    {'label': '1 MB', 'val': 1.0, 'unit': 'MB'},
    {'label': '2 MB', 'val': 2.0, 'unit': 'MB'},
  ];

  @override
  void dispose() {
    _targetSizeController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'bmp'],
      allowMultiple: true,
    );

    if (result != null && result.paths.isNotEmpty) {
      final validPaths = result.paths.whereType<String>().toList();
      setState(() {
        _selectedImagePaths.addAll(validPaths);
        _results.clear();
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImagePaths.removeAt(index);
    });
  }

  void _applyPreset(Map<String, dynamic> preset) {
    setState(() {
      final val = preset['val'] as double;
      _targetSizeController.text =
          val % 1 == 0 ? val.toInt().toString() : val.toString();
      _selectedUnit = preset['unit'] as String;
    });
  }

  int? _getTargetBytes() {
    final text = _targetSizeController.text.trim();
    final val = double.tryParse(text);
    if (val == null || val <= 0 || val.isNaN || val.isInfinite) {
      return null;
    }
    final bytes = ImageTargetSizeCompressorService.parseSizeToBytes(val, _selectedUnit);
    if (bytes < 10 * 1024) return 10 * 1024;
    return bytes;
  }

  Future<void> _startCompression() async {
    if (_selectedImagePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one image.')),
      );
      return;
    }

    final targetBytes = _getTargetBytes();
    if (targetBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid numeric target size (e.g. 100 KB).'),
        ),
      );
      return;
    }

    setState(() {
      _isCompressing = true;
      _isCancelled = false;
      _progress = 0.05;
      _progressStatus = 'Initializing image compressor...';
      _results.clear();
    });

    try {
      final List<ImageTargetCompressionResult> tempResults = [];

      for (int i = 0; i < _selectedImagePaths.length; i++) {
        if (_isCancelled) throw Exception('Operation cancelled');

        final imgPath = _selectedImagePaths[i];
        final fraction = (i + 1) / _selectedImagePaths.length;

        setState(() {
          _progress = fraction;
          _progressStatus = 'Compressing image ${i + 1} of ${_selectedImagePaths.length}...';
        });

        final res = await ImageTargetSizeCompressorService.compressImageToTargetSize(
          inputPath: imgPath,
          targetBytes: targetBytes,
          onProgress: (subProg, status) {},
          isCancelled: () => _isCancelled,
        );

        tempResults.add(res);
      }

      if (mounted) {
        setState(() {
          _isCompressing = false;
          _results.addAll(tempResults);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCompressing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isCancelled ? 'Compression cancelled.' : 'Error compressing images: $e'),
        ),
      );
    }
  }

  void _cancel() {
    setState(() {
      _isCancelled = true;
      _progressStatus = 'Cancelling...';
    });
  }

  void _openImage(String path) {
    if (File(path).existsSync()) {
      OpenFilex.open(path);
    }
  }

  void _shareImage(String path, String name) {
    if (File(path).existsSync()) {
      Share.shareXFiles([XFile(path)], text: 'Sharing $name');
    }
  }

  void _showRenameDialog(ImageTargetCompressionResult item, int index) {
    final currentName = item.outputPath.split(Platform.pathSeparator).last;
    final controller = TextEditingController(text: currentName);
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: EditorialTokens.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EditorialTokens.r6),
          side: const BorderSide(color: EditorialTokens.border, width: EditorialTokens.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EditorialEyebrow(text: 'RENAME ASSET'),
              const SizedBox(height: 6),
              Text('Rename Image', style: EditorialTokens.titleMedium()),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: EditorialTokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(EditorialTokens.r4),
                  border: Border.all(color: EditorialTokens.borderSoft, width: EditorialTokens.hairline),
                ),
                child: TextField(
                  controller: controller,
                  style: EditorialTokens.bodyMedium(color: EditorialTokens.ink),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  EditorialSecondaryButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(dialogCtx),
                  ),
                  const SizedBox(width: 8),
                  EditorialButton(
                    label: 'Rename',
                    onPressed: () async {
                      final newName = controller.text.trim();
                      if (newName.isNotEmpty && newName != currentName) {
                        Navigator.pop(dialogCtx);
                        final file = File(item.outputPath);
                        if (await file.exists()) {
                          final dir = file.parent.path;
                          final newPath = '$dir${Platform.pathSeparator}$newName';
                          await file.rename(newPath);
                          messenger.showSnackBar(SnackBar(content: Text('Renamed to $newName')));
                          if (mounted) {
                            setState(() {
                              _results[index] = ImageTargetCompressionResult(
                                originalPath: item.originalPath,
                                outputPath: newPath,
                                originalSizeBytes: item.originalSizeBytes,
                                targetSizeBytes: item.targetSizeBytes,
                                outputSizeBytes: item.outputSizeBytes,
                                reductionPercentage: item.reductionPercentage,
                                originalWidth: item.originalWidth,
                                originalHeight: item.originalHeight,
                                outputWidth: item.outputWidth,
                                outputHeight: item.outputHeight,
                                format: item.format,
                                isTargetAchieved: item.isTargetAchieved,
                                statusMessage: item.statusMessage,
                              );
                            });
                          }
                        }
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _deleteImage(ImageTargetCompressionResult item, int index) {
    final messenger = ScaffoldMessenger.of(context);
    final name = item.outputPath.split(Platform.pathSeparator).last;

    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: EditorialTokens.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EditorialTokens.r6),
          side: const BorderSide(color: EditorialTokens.border, width: EditorialTokens.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EditorialEyebrow(text: 'DELETE CONFIRMATION'),
              const SizedBox(height: 6),
              Text('Remove Image Asset', style: EditorialTokens.titleMedium()),
              const SizedBox(height: 10),
              Text('Purge "$name" from local filesystem?', style: EditorialTokens.body(color: EditorialTokens.inkSecondary)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  EditorialSecondaryButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(dialogCtx),
                  ),
                  const SizedBox(width: 8),
                  EditorialButton(
                    label: 'Delete',
                    isDestructive: true,
                    onPressed: () async {
                      Navigator.pop(dialogCtx);
                      final file = File(item.outputPath);
                      if (await file.exists()) {
                        await file.delete();
                      }
                      messenger.showSnackBar(const SnackBar(content: Text('Image deleted.')));
                      if (mounted) {
                        setState(() {
                          _results.removeAt(index);
                        });
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Image Selection Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: EditorialTokens.paper,
                        borderRadius: BorderRadius.circular(EditorialTokens.r6),
                        border: Border.all(color: EditorialTokens.border, width: EditorialTokens.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'SELECTED IMAGES (${_selectedImagePaths.length})',
                                style: EditorialTokens.metadataStrong(color: EditorialTokens.primary),
                              ),
                              EditorialSecondaryButton(
                                label: _selectedImagePaths.isEmpty ? 'Select Photos' : 'Add Photos',
                                icon: Icons.add_photo_alternate_outlined,
                                onPressed: _isCompressing ? null : _pickImages,
                              ),
                            ],
                          ),
                          if (_selectedImagePaths.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 100,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _selectedImagePaths.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final p = _selectedImagePaths[index];
                                  return Container(
                                    width: 80,
                                    height: 100,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                                      border: Border.all(color: EditorialTokens.borderSoft, width: EditorialTokens.hairline),
                                      image: DecorationImage(
                                        image: FileImage(File(p)),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: GestureDetector(
                                            onTap: () => _removeImage(index),
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.6),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.close, color: Colors.white, size: 12),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 4,
                                          left: 4,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: EditorialTokens.secondary,
                                              borderRadius: BorderRadius.circular(EditorialTokens.r2),
                                            ),
                                            child: Text(
                                              '${index + 1}',
                                              style: EditorialTokens.metadata(color: Colors.white).copyWith(fontSize: 9),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            Text(
                              'Select one or multiple photos to downsize toward an exact byte ceiling with zero cropping.',
                              style: EditorialTokens.bodySmall(color: EditorialTokens.inkMuted),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 2. Target Size Selection Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: EditorialTokens.paper,
                        borderRadius: BorderRadius.circular(EditorialTokens.r6),
                        border: Border.all(color: EditorialTokens.border, width: EditorialTokens.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const EditorialEyebrow(text: 'TARGET SPECIFICATION'),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: EditorialTokens.surfaceMuted,
                                  borderRadius: BorderRadius.circular(EditorialTokens.r2),
                                ),
                                child: Text(
                                  'PRESERVE ASPECT RATIO',
                                  style: EditorialTokens.metadata(color: EditorialTokens.tertiary).copyWith(fontSize: 9),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: EditorialTokens.surfaceMuted,
                                    borderRadius: BorderRadius.circular(EditorialTokens.r4),
                                    border: Border.all(color: EditorialTokens.borderSoft, width: EditorialTokens.hairline),
                                  ),
                                  child: TextField(
                                    controller: _targetSizeController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    enabled: !_isCompressing,
                                    style: EditorialTokens.bodyMedium(color: EditorialTokens.ink),
                                    decoration: InputDecoration(
                                      labelText: 'TARGET SIZE',
                                      labelStyle: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: EditorialTokens.surfaceMuted,
                                    borderRadius: BorderRadius.circular(EditorialTokens.r4),
                                    border: Border.all(color: EditorialTokens.borderSoft, width: EditorialTokens.hairline),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedUnit,
                                      style: EditorialTokens.bodyMedium(color: EditorialTokens.ink),
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
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'BUDGET PRESETS:',
                            style: EditorialTokens.metadata(color: EditorialTokens.inkMuted).copyWith(fontSize: 9.5),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _presets.map((preset) {
                              final val = preset['val'] as double;
                              final valStr = val % 1 == 0 ? val.toInt().toString() : val.toString();
                              final isSelected = _selectedUnit == preset['unit'] &&
                                  _targetSizeController.text == valStr;
                              return EditorialChip(
                                label: preset['label'] as String,
                                selected: isSelected,
                                onTap: _isCompressing ? null : () => _applyPreset(preset),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 3. Action or Progress Card
                    if (_isCompressing) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: EditorialTokens.paper,
                          borderRadius: BorderRadius.circular(EditorialTokens.r6),
                          border: Border.all(color: EditorialTokens.border, width: EditorialTokens.hairline),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _progressStatus.toUpperCase(),
                                    style: EditorialTokens.metadataStrong(color: EditorialTokens.primary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${(_progress * 100).toInt()}%',
                                  style: EditorialTokens.metadataStrong(color: EditorialTokens.ink),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: _progress.clamp(0.0, 1.0),
                                backgroundColor: EditorialTokens.surfaceMuted,
                                valueColor: const AlwaysStoppedAnimation(EditorialTokens.primary),
                                minHeight: 4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            EditorialSecondaryButton(
                              label: 'Cancel Compression',
                              icon: Icons.cancel_outlined,
                              onPressed: _cancel,
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        child: EditorialButton(
                          label: _selectedImagePaths.length <= 1
                              ? 'Compress Image'
                              : 'Compress (${_selectedImagePaths.length} Photos)',
                          icon: Icons.tune,
                          onPressed: _selectedImagePaths.isEmpty ? null : _startCompression,
                        ),
                      ),
                    ],

                    // 4. Results List
                    if (_results.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      EditorialSectionHeader(
                        number: '03',
                        label: 'Compressed Images',
                        trailing: '${_results.length} COMPLETED',
                      ),
                      const SizedBox(height: 8),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _results[index];
                          final name = item.outputPath.split(Platform.pathSeparator).last;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: EditorialTokens.paper,
                              borderRadius: BorderRadius.circular(EditorialTokens.r4),
                              border: Border.all(color: EditorialTokens.borderSoft, width: EditorialTokens.hairline),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(EditorialTokens.r2),
                                      child: Image.file(
                                        File(item.outputPath),
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 50),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: EditorialTokens.titleSmall().copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${Utils.formatBytes(item.originalSizeBytes)} → ${Utils.formatBytes(item.outputSizeBytes)} (${item.reductionPercentage.toStringAsFixed(1)}% reduction)',
                                            style: EditorialTokens.metadataStrong(color: const Color(0xFF386641)),
                                          ),
                                          Text(
                                            '${item.outputWidth}×${item.outputHeight}PX · ${item.format.toUpperCase()} · ZERO CROP',
                                            style: EditorialTokens.metadata(color: EditorialTokens.inkMuted).copyWith(fontSize: 9),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const EditorialDivider(),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    EditorialSecondaryButton(
                                      label: 'Open',
                                      icon: Icons.visibility_outlined,
                                      onPressed: () => _openImage(item.outputPath),
                                    ),
                                    const SizedBox(width: 6),
                                    EditorialSecondaryButton(
                                      label: 'Share',
                                      icon: Icons.share_outlined,
                                      onPressed: () => _shareImage(item.outputPath, name),
                                    ),
                                    const SizedBox(width: 6),
                                    EditorialSecondaryButton(
                                      label: 'Rename',
                                      icon: Icons.edit_outlined,
                                      onPressed: () => _showRenameDialog(item, index),
                                    ),
                                    IconButton(
                                      onPressed: () => _deleteImage(item, index),
                                      icon: const Icon(Icons.delete_outline, color: EditorialTokens.inkMuted, size: 18),
                                      tooltip: 'Delete',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
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
                const EditorialEyebrow(text: 'IMAGE COMPRESSION'),
                const SizedBox(height: 2),
                Text(
                  'Compress Images',
                  style: EditorialTokens.titleLarge(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
