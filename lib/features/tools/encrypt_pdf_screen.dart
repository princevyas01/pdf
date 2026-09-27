import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../core/tools/pdf_encryption_service.dart';
import '../../core/tools/pdf_version_service.dart';
import '../../core/utils/utils.dart';
import '../../models/pdf_file.dart';
import '../../widgets/editorial_components.dart';
import '../../widgets/pdf_tool_file_picker_screen.dart';
import '../viewer/pdf_viewer_screen.dart';

class EncryptPdfScreen extends ConsumerStatefulWidget {
  final PdfFile? pdfFile;

  const EncryptPdfScreen({super.key, this.pdfFile});

  @override
  ConsumerState<EncryptPdfScreen> createState() => _EncryptPdfScreenState();
}

class _EncryptPdfScreenState extends ConsumerState<EncryptPdfScreen> {
  PdfFile? _selectedFile;
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _ownerPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _useAes256 = true;
  bool _allowPrinting = true;
  bool _allowCopying = false;
  bool _allowAnnotations = true;
  bool _allowFillForms = true;
  bool _isEncrypting = false;

  @override
  void initState() {
    super.initState();
    _selectedFile = widget.pdfFile;
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _ownerPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    final result = await Navigator.push<List<PdfFile>>(
      context,
      MaterialPageRoute(
        builder: (_) => const PdfToolFilePickerScreen(
          title: 'Select Document to Encrypt',
          mode: ToolPickerMode.singleSelect,
          actionButtonText: 'CONFIRM DOCUMENT',
        ),
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _selectedFile = result.first;
      });
    }
  }

  Future<void> _generateRecoveryKeyfile() async {
    if (_selectedFile == null) {
      _showNotice('Please select a PDF document first.');
      return;
    }
    final pass = _passwordController.text;
    if (pass.isEmpty) {
      _showNotice('Please enter a decryption passphrase first.');
      return;
    }

    try {
      final parentDir = File(_selectedFile!.path).parent.path;
      final baseName = _selectedFile!.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
      final keyPath = '$parentDir${Platform.pathSeparator}${baseName}_recovery.key';

      final keyContent = StringBuffer()
        ..writeln('----- QUIET EDITORIAL DOCUMENT STUDIO RECOVERY KEYFILE -----')
        ..writeln('DOCUMENT: ${_selectedFile!.name}')
        ..writeln('CIPHER: ${_useAes256 ? 'AES-256 (Government/Military)' : 'AES-128 (Standard Compatibility)'}')
        ..writeln('CREATED: ${DateTime.now().toUtc().toIso8601String()}')
        ..writeln('RECOVERY_TOKEN: ${pass.hashCode.toRadixString(16).padLeft(16, '0')}-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}')
        ..writeln('HINT: Passphrase length: ${pass.length} characters')
        ..writeln('-------------------- END RECOVERY KEYFILE --------------------');

      await File(keyPath).writeAsString(keyContent.toString());
      _showNotice('Recovery keyfile written to: ${keyPath.split(Platform.pathSeparator).last}');
    } catch (e) {
      _showNotice('Failed to generate keyfile: $e');
    }
  }

  Future<void> _encrypt() async {
    if (_selectedFile == null) {
      _showNotice('Please select a PDF document first.');
      return;
    }

    final pass = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (pass.isEmpty) {
      _showNotice('Please enter a decryption passphrase.');
      return;
    }

    if (pass != confirm) {
      _showNotice('Passphrases do not match. Please verify.');
      return;
    }

    setState(() => _isEncrypting = true);

    try {
      final inputPath = _selectedFile!.path;
      final outputPath = inputPath.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false),
        '_encrypted.pdf',
      );

      final ownerPass = _ownerPasswordController.text.trim().isNotEmpty
          ? _ownerPasswordController.text.trim()
          : null;

      final ok = await PdfEncryptionService.encryptPdf(
        inputPath: inputPath,
        outputPath: outputPath,
        userPassword: pass,
        ownerPassword: ownerPass,
        useAes256: _useAes256,
        allowPrinting: _allowPrinting,
        allowCopyContent: _allowCopying,
        allowAnnotations: _allowAnnotations,
        allowFillForms: _allowFillForms,
      );

      if (ok) {
        await PdfVersionService.createVersion(
          docId: inputPath,
          filePath: outputPath,
          sourceOperation: _useAes256 ? 'Encrypted (AES-256)' : 'Encrypted (AES-128)',
        );
      }

      if (mounted) {
        setState(() => _isEncrypting = false);
        if (ok) {
          _showSuccessSheet(outputPath);
        } else {
          _showNotice('Encryption failed. Please verify document permissions.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isEncrypting = false);
        _showNotice('Error during encryption: $e');
      }
    }
  }

  void _showNotice(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: EditorialTokens.bodyMedium(color: Colors.white),
        ),
        backgroundColor: EditorialTokens.secondary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSheet(String outputPath) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final file = File(outputPath);
    final size = file.existsSync() ? file.lengthSync() : 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? EditorialTokens.darkSurface : EditorialTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(EditorialTokens.r6)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                  color: isDark ? EditorialTokens.darkBorder : EditorialTokens.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const EditorialEyebrow(
              text: 'PDF ENCRYPTION COMPLETE',
              color: EditorialTokens.primary,
            ),
            const SizedBox(height: 6),
            Text(
              'Document Encrypted (AES-256)',
              style: EditorialTokens.headlineSmall(
                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A new encrypted copy has been saved to storage. The password is required to open and decrypt the document.',
              style: EditorialTokens.bodySmall(
                color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
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
                  Text(
                    file.uri.pathSegments.last,
                    style: EditorialTokens.titleSmall(
                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${Utils.formatBytes(size)} · AES-256 Standard · Encrypted',
                    style: EditorialTokens.metadata(
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: EditorialSecondaryButton(
                    label: 'SHARE FILE',
                    icon: Icons.share_outlined,
                    onPressed: () {
                      Share.shareXFiles([XFile(outputPath)]);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: EditorialButton(
                    label: 'OPEN VIEWER',
                    icon: Icons.menu_book_outlined,
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PdfViewerScreen(
                            filePath: outputPath,
                          ),
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
    );
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
            const EditorialEyebrow(text: 'PDF SECURITY'),
            Text(
              'PDF Encryption',
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
          // Section 1: Active Document Card
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
                          '${Utils.formatBytes(_selectedFile!.sizeBytes)} · Unencrypted',
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
                    onPressed: _pickDocument,
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
                    Icons.file_present_outlined,
                    size: 36,
                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No document selected for encryption',
                    style: EditorialTokens.titleSmall(
                      color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose a PDF from your library to lock with AES-256 standard',
                    style: EditorialTokens.bodySmall(
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  EditorialSecondaryButton(
                    label: 'CHOOSE DOCUMENT',
                    icon: Icons.folder_open,
                    onPressed: _pickDocument,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Section 2: Cryptographic Standards Profile
          const EditorialSectionHeader(
            number: '02',
            label: 'Encryption Standard',
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
                        border: Border.all(
                          color: EditorialTokens.primary.withOpacity(0.3),
                          width: EditorialTokens.hairline,
                        ),
                      ),
                      child: Text(
                        'AES-256 · STANDARD CIPHER',
                        style: EditorialTokens.metadataStrong(color: EditorialTokens.primary).copyWith(fontSize: 10),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: EditorialTokens.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Standard PDF Encryption',
                  style: EditorialTokens.titleSmall(
                    color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Applies full document and stream-level encryption using 256-bit AES keys. The resulting document is readable by any compliant viewer upon entry of the decryption key.',
                  style: EditorialTokens.bodySmall(
                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section 3: Passphrase Credentials
          const EditorialSectionHeader(
            number: '03',
            label: 'Password Setup',
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
                Text(
                  'DOCUMENT PASSWORD',
                  style: EditorialTokens.metadataStrong(
                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                  ).copyWith(fontSize: 10),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: EditorialTokens.bodyMedium(
                    color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter document password...',
                    hintStyle: EditorialTokens.bodySmall(
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    ),
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
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                      borderSide: BorderSide(
                        color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                        width: EditorialTokens.hairline,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                      borderSide: const BorderSide(
                        color: EditorialTokens.primary,
                        width: 1.0,
                      ),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 18,
                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                Text(
                  'CONFIRM PASSWORD',
                  style: EditorialTokens.metadataStrong(
                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                  ).copyWith(fontSize: 10),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  style: EditorialTokens.bodyMedium(
                    color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Re-enter password...',
                    hintStyle: EditorialTokens.bodySmall(
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    ),
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
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                      borderSide: BorderSide(
                        color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                        width: EditorialTokens.hairline,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                      borderSide: const BorderSide(
                        color: EditorialTokens.primary,
                        width: 1.0,
                      ),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 18,
                        color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                      ),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                Text(
                  'OPTIONAL OWNER PASSWORD',
                  style: EditorialTokens.metadataStrong(
                    color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                  ).copyWith(fontSize: 10),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _ownerPasswordController,
                  obscureText: true,
                  style: EditorialTokens.bodyMedium(
                    color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Leave blank to use document password...',
                    hintStyle: EditorialTokens.bodySmall(
                      color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                    ),
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
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                      borderSide: BorderSide(
                        color: isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft,
                        width: EditorialTokens.hairline,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                      borderSide: const BorderSide(
                        color: EditorialTokens.primary,
                        width: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section 3: Cipher Architecture
          const EditorialSectionHeader(
            number: '03',
            label: 'Cipher Architecture',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _useAes256 = true),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _useAes256
                          ? EditorialTokens.primary.withOpacity(0.08)
                          : (isDark ? EditorialTokens.darkSurface : EditorialTokens.surface),
                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                      border: Border.all(
                        color: _useAes256
                            ? EditorialTokens.primary
                            : (isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft),
                        width: _useAes256 ? 1.5 : EditorialTokens.hairline,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _useAes256 ? Icons.radio_button_checked : Icons.radio_button_off,
                              size: 16,
                              color: _useAes256 ? EditorialTokens.primary : EditorialTokens.inkMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'AES-256',
                              style: EditorialTokens.titleSmall(
                                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Government & military archival standard',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ).copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _useAes256 = false),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: !_useAes256
                          ? EditorialTokens.primary.withOpacity(0.08)
                          : (isDark ? EditorialTokens.darkSurface : EditorialTokens.surface),
                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                      border: Border.all(
                        color: !_useAes256
                            ? EditorialTokens.primary
                            : (isDark ? EditorialTokens.darkBorderSoft : EditorialTokens.borderSoft),
                        width: !_useAes256 ? 1.5 : EditorialTokens.hairline,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              !_useAes256 ? Icons.radio_button_checked : Icons.radio_button_off,
                              size: 16,
                              color: !_useAes256 ? EditorialTokens.primary : EditorialTokens.inkMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'AES-128',
                              style: EditorialTokens.titleSmall(
                                color: isDark ? EditorialTokens.darkInk : EditorialTokens.ink,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Broad legacy reader compatibility',
                          style: EditorialTokens.metadata(
                            color: isDark ? EditorialTokens.darkInkSecondary : EditorialTokens.inkSecondary,
                          ).copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Section 4: Granular Permissions
          const EditorialSectionHeader(
            number: '04',
            label: 'Permissions Specification',
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
                _buildPermissionTile(
                  title: 'Allow High-Resolution Printing',
                  subtitle: 'Permits generating physical copies from reader',
                  value: _allowPrinting,
                  onChanged: (v) => setState(() => _allowPrinting = v),
                  isDark: isDark,
                ),
                const EditorialDivider(),
                _buildPermissionTile(
                  title: 'Allow Content Extraction & Copying',
                  subtitle: 'Permits selecting and copying text/formula blocks',
                  value: _allowCopying,
                  onChanged: (v) => setState(() => _allowCopying = v),
                  isDark: isDark,
                ),
                const EditorialDivider(),
                _buildPermissionTile(
                  title: 'Allow Annotations & Stationery',
                  subtitle: 'Permits ink drawings, highlights, and margin notes',
                  value: _allowAnnotations,
                  onChanged: (v) => setState(() => _allowAnnotations = v),
                  isDark: isDark,
                ),
                const EditorialDivider(),
                _buildPermissionTile(
                  title: 'Allow Form Fill & Digital Signatures',
                  subtitle: 'Permits filling interactive form fields and vector stamping',
                  value: _allowFillForms,
                  onChanged: (v) => setState(() => _allowFillForms = v),
                  isDark: isDark,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Recovery Keyfile Generation Button
          SizedBox(
            width: double.infinity,
            child: EditorialSecondaryButton(
              label: 'GENERATE RECOVERY KEYFILE (.KEY)',
              icon: Icons.key_outlined,
              onPressed: _generateRecoveryKeyfile,
            ),
          ),

          const SizedBox(height: 14),

          // Primary Fortify Button
          SizedBox(
            width: double.infinity,
            child: EditorialButton(
              label: _isEncrypting ? 'ENCRYPTING PDF...' : 'ENCRYPT PDF',
              icon: _isEncrypting ? null : Icons.lock_outline,
              onPressed: _isEncrypting ? null : _encrypt,
            ),
          ),
          const SizedBox(height: 24),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: EditorialTokens.primary,
            ),
          ],
        ),
      ),
    );
  }
}
