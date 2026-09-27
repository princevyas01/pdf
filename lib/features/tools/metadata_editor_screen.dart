import 'package:flutter/material.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../core/tools/pdf_metadata_service.dart';
import '../../core/tools/pdf_version_service.dart';
import '../../models/pdf_file.dart';
import '../../widgets/editorial_components.dart';

class MetadataEditorScreen extends StatefulWidget {
  final PdfFile pdfFile;

  const MetadataEditorScreen({super.key, required this.pdfFile});

  @override
  State<MetadataEditorScreen> createState() => _MetadataEditorScreenState();
}

class _MetadataEditorScreenState extends State<MetadataEditorScreen> {
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _subjectController = TextEditingController();
  final _keywordsController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _subjectController.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  Future<void> _loadMetadata() async {
    final meta = await PdfMetadataService.readMetadata(widget.pdfFile.path);
    _titleController.text = meta.title;
    _authorController.text = meta.author;
    _subjectController.text = meta.subject;
    _keywordsController.text = meta.keywords;
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveMetadata() async {
    setState(() => _isSaving = true);

    final newMeta = PdfMetadata(
      title: _titleController.text.trim(),
      author: _authorController.text.trim(),
      subject: _subjectController.text.trim(),
      keywords: _keywordsController.text.trim(),
    );

    final outputPath = widget.pdfFile.path.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false), '_meta.pdf');
    final ok = await PdfMetadataService.updateMetadata(
      inputPath: widget.pdfFile.path,
      outputPath: outputPath,
      metadata: newMeta,
    );

    if (ok) {
      await PdfVersionService.createVersion(
        docId: widget.pdfFile.path,
        filePath: outputPath,
        sourceOperation: 'Metadata Updated',
      );
    }

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Document metadata updated.' : 'Failed to update metadata.')),
      );
      if (ok) Navigator.pop(context);
    }
  }

  Future<void> _removeMetadata() async {
    _titleController.clear();
    _authorController.clear();
    _subjectController.clear();
    _keywordsController.clear();
    await _saveMetadata();
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
                  : SingleChildScrollView(
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
                                const EditorialEyebrow(text: 'DOCUMENT IDENTIFICATION'),
                                const SizedBox(height: 6),
                                Text(
                                  widget.pdfFile.name,
                                  style: EditorialTokens.titleMedium().copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  widget.pdfFile.path,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          const EditorialSectionHeader(
                            number: '01',
                            label: 'Document Metadata',
                            trailing: 'PROPERTIES',
                          ),
                          const SizedBox(height: 12),
                          _buildTextField('TITLE', _titleController),
                          const SizedBox(height: 12),
                          _buildTextField('AUTHOR', _authorController),
                          const SizedBox(height: 12),
                          _buildTextField('SUBJECT', _subjectController),
                          const SizedBox(height: 12),
                          _buildTextField('KEYWORDS', _keywordsController),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: EditorialSecondaryButton(
                                  label: 'Clear All',
                                  icon: Icons.cleaning_services_outlined,
                                  onPressed: _isSaving ? null : _removeMetadata,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: EditorialButton(
                                  label: _isSaving ? 'Saving...' : 'Save Metadata',
                                  icon: Icons.save_outlined,
                                  onPressed: _isSaving ? null : _saveMetadata,
                                ),
                              ),
                            ],
                          ),
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
                const EditorialEyebrow(text: 'DOCUMENT PROPERTIES'),
                const SizedBox(height: 2),
                Text(
                  'Edit Metadata',
                  style: EditorialTokens.titleLarge(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: EditorialTokens.metadataStrong(color: EditorialTokens.inkSecondary).copyWith(
            fontSize: 9.5,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: EditorialTokens.paper,
            borderRadius: BorderRadius.circular(EditorialTokens.r4),
            border: Border.all(
              color: EditorialTokens.borderSoft,
              width: EditorialTokens.hairline,
            ),
          ),
          child: TextField(
            controller: controller,
            style: EditorialTokens.bodyMedium(color: EditorialTokens.ink),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ],
    );
  }
}
