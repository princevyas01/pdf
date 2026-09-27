import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/ai/local_ai_provider.dart';
import '../../core/ai/on_device_ai_service.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../widgets/editorial_components.dart';

class ExplainTextDialog extends StatefulWidget {
  final String selectedText;

  const ExplainTextDialog({super.key, required this.selectedText});

  @override
  State<ExplainTextDialog> createState() => _ExplainTextDialogState();
}

class _ExplainTextDialogState extends State<ExplainTextDialog> {
  ExplanationMode _mode = ExplanationMode.simple;
  String _explanation = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExplanation();
  }

  Future<void> _loadExplanation() async {
    setState(() => _isLoading = true);
    final result = await OnDeviceAIService.instance.explainText(
      selectedText: widget.selectedText,
      surroundingContext: widget.selectedText,
      mode: _mode,
    );
    if (mounted) {
      setState(() {
        _explanation = result;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: EditorialTokens.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EditorialTokens.r6),
        side: const BorderSide(
          color: EditorialTokens.border,
          width: EditorialTokens.hairline,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EditorialEyebrow(text: '02 · PASSAGE EXEGESIS'),
            const SizedBox(height: 4),
            Text(
              'Grounded Clarification',
              style: EditorialTokens.titleMedium().copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: EditorialTokens.surfaceMuted,
                borderRadius: BorderRadius.circular(EditorialTokens.r4),
                border: Border.all(
                  color: EditorialTokens.borderSoft,
                  width: EditorialTokens.hairline,
                ),
              ),
              child: Text(
                '“${widget.selectedText.trim()}”',
                style: EditorialTokens.bodySmall(color: EditorialTokens.inkSecondary).copyWith(
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildModeChip('SIMPLE', ExplanationMode.simple),
                const SizedBox(width: 8),
                _buildModeChip('SCHOLARLY', ExplanationMode.detailed),
                const SizedBox(width: 8),
                _buildModeChip('EXAM FOCUS', ExplanationMode.examFocused),
              ],
            ),
            const SizedBox(height: 14),
            const EditorialDivider(),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: _isLoading
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: EditorialTokens.primary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'SYNTHESIZING LOCAL CONTEXT...',
                              style: EditorialTokens.metadata().copyWith(
                                fontSize: 9.5,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Text(
                        _explanation,
                        style: EditorialTokens.body(color: EditorialTokens.ink).copyWith(
                          fontSize: 13.5,
                          height: 1.5,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isLoading && _explanation.isNotEmpty) ...[
                  EditorialSecondaryButton(
                    label: 'Copy',
                    icon: Icons.copy_outlined,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _explanation));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Exegesis copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                EditorialButton(
                  label: 'Dismiss',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeChip(String label, ExplanationMode mode) {
    final isSelected = _mode == mode;
    return GestureDetector(
      onTap: () {
        if (_mode != mode) {
          setState(() => _mode = mode);
          _loadExplanation();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? EditorialTokens.secondary : EditorialTokens.surface,
          borderRadius: BorderRadius.circular(EditorialTokens.r2),
          border: Border.all(
            color: isSelected ? EditorialTokens.secondary : EditorialTokens.border,
            width: EditorialTokens.hairline,
          ),
        ),
        child: Text(
          label,
          style: EditorialTokens.metadataStrong(
            color: isSelected ? EditorialTokens.paper : EditorialTokens.inkMuted,
          ).copyWith(fontSize: 9.5, letterSpacing: 0.8),
        ),
      ),
    );
  }
}
