import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../core/ai/on_device_ai_service.dart';
import '../../core/storage/database_helper.dart';
import '../../core/storage/ocr_cache_service.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../models/exam_session.dart';
import '../../models/pdf_file.dart';
import '../../models/study_item.dart';
import '../../widgets/editorial_components.dart';

class ExamModeScreen extends ConsumerStatefulWidget {
  final PdfFile pdfFile;

  const ExamModeScreen({super.key, required this.pdfFile});

  @override
  ConsumerState<ExamModeScreen> createState() => _ExamModeScreenState();
}

class _ExamModeScreenState extends ConsumerState<ExamModeScreen> {
  String _selectedDifficulty = 'Medium';
  int _questionCount = 5;
  bool _isExamActive = false;
  bool _isGenerating = false;

  Map<int, String> _pageTextMap = {};
  List<StudyQuestion> _questions = [];
  final Map<int, String> _userAnswers = {};
  int _examStartTime = 0;
  bool _isSubmitted = false;
  double _finalScorePct = 0.0;

  @override
  void initState() {
    super.initState();
    _loadDocumentText();
  }

  Future<void> _loadDocumentText() async {
    final cachedOcr = await OcrCacheService.getCachedFileOcr(widget.pdfFile.path);
    _pageTextMap = Map.from(cachedOcr);

    if (_pageTextMap.isEmpty) {
      try {
        final fileBytes = await File(widget.pdfFile.path).readAsBytes();
        if (!mounted) return;
        final document = sf.PdfDocument(inputBytes: fileBytes);
        final extractor = sf.PdfTextExtractor(document);

        for (int i = 0; i < document.pages.count; i++) {
          final text = extractor.extractText(startPageIndex: i, endPageIndex: i).trim();
          if (text.isNotEmpty) {
            _pageTextMap[i + 1] = text;
          }
        }
        document.dispose();
      } catch (_) {}
    }
  }

  Future<void> _startExam() async {
    setState(() => _isGenerating = true);

    final questions = await OnDeviceAIService.instance.generateExamQuestions(
      filePath: widget.pdfFile.path,
      pageTextMap: _pageTextMap,
      topic: 'General',
      difficulty: _selectedDifficulty,
      questionCount: _questionCount,
    );

    if (mounted) {
      setState(() {
        _questions = questions;
        _isGenerating = false;
        _isExamActive = true;
        _examStartTime = DateTime.now().millisecondsSinceEpoch;
      });
    }
  }

  void _submitExam() async {
    int correct = 0;
    for (int i = 0; i < _questions.length; i++) {
      if (_userAnswers[i] == _questions[i].correctAnswer) {
        correct++;
      }
    }

    final scorePct = (_questions.isNotEmpty ? (correct / _questions.length) : 0.0) * 100.0;
    final elapsedSec = (DateTime.now().millisecondsSinceEpoch - _examStartTime) ~/ 1000;

    final session = ExamSession(
      filePath: widget.pdfFile.path,
      topic: 'General',
      difficulty: _selectedDifficulty,
      numQuestions: _questions.length,
      scorePct: scorePct,
      durationSeconds: elapsedSec,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    await DatabaseHelper.instance.saveExamSession(session);

    if (mounted) {
      setState(() {
        _isSubmitted = true;
        _finalScorePct = scorePct;
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
              child: !_isExamActive
                  ? _buildSetupView()
                  : (_isSubmitted ? _buildResultsView() : _buildExamQuestionsView()),
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
                const EditorialEyebrow(text: '04 · ACADEMIC RIGOR'),
                const SizedBox(height: 2),
                Text(
                  'Examination Sandbox',
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

  Widget _buildSetupView() {
    return Padding(
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
              border: Border.all(color: EditorialTokens.border, width: EditorialTokens.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EditorialEyebrow(text: 'EVALUATION PROFILE'),
                const SizedBox(height: 6),
                Text(
                  'On-Device Knowledge Test',
                  style: EditorialTokens.titleMedium().copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Generate closed-book practice assessments directly from document contents using local models.',
                  style: EditorialTokens.bodySmall(color: EditorialTokens.inkSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const EditorialSectionHeader(
            number: '01',
            label: 'Rigor Calibration',
            trailing: 'DIFFICULTY',
          ),
          const SizedBox(height: 8),
          Row(
            children: ['Easy', 'Medium', 'Hard'].map((diff) {
              final isSelected = _selectedDifficulty == diff;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: EditorialChip(
                  label: diff,
                  selected: isSelected,
                  onTap: () => setState(() => _selectedDifficulty = diff),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          EditorialSectionHeader(
            number: '02',
            label: 'Question Quota',
            trailing: '$_questionCount ITEMS',
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: EditorialTokens.primary,
              inactiveTrackColor: EditorialTokens.surfaceMuted,
              thumbColor: EditorialTokens.primary,
              overlayColor: EditorialTokens.primary.withOpacity(0.12),
            ),
            child: Slider(
              value: _questionCount.toDouble(),
              min: 3,
              max: 15,
              divisions: 4,
              onChanged: (val) => setState(() => _questionCount = val.toInt()),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: EditorialButton(
              label: _isGenerating ? 'Generating Questions...' : 'Start Examination',
              icon: Icons.assignment_turned_in_outlined,
              onPressed: _isGenerating ? null : _startExam,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamQuestionsView() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _questions.length,
            itemBuilder: (context, index) {
              final q = _questions[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: EditorialTokens.paper,
                  borderRadius: BorderRadius.circular(EditorialTokens.r6),
                  border: Border.all(color: EditorialTokens.border, width: EditorialTokens.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QUESTION ${index + 1} · ${q.type.name.toUpperCase()}',
                      style: EditorialTokens.metadataStrong(color: EditorialTokens.primary).copyWith(fontSize: 10),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      q.question,
                      style: EditorialTokens.titleMedium().copyWith(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    if (q.type == QuestionType.mcq || q.type == QuestionType.trueFalse)
                      ...q.options.map((opt) {
                        final isSelected = _userAnswers[index] == opt;
                        return GestureDetector(
                          onTap: () => setState(() => _userAnswers[index] = opt),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFFBF1EE) : EditorialTokens.surface,
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
                                  size: 14,
                                  color: isSelected ? EditorialTokens.primary : EditorialTokens.border,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    opt,
                                    style: EditorialTokens.bodyMedium(color: EditorialTokens.ink).copyWith(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      })
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: EditorialTokens.surfaceMuted,
                          borderRadius: BorderRadius.circular(EditorialTokens.r4),
                          border: Border.all(color: EditorialTokens.borderSoft, width: EditorialTokens.hairline),
                        ),
                        child: TextField(
                          onChanged: (val) => _userAnswers[index] = val,
                          style: EditorialTokens.bodyMedium(color: EditorialTokens.ink),
                          decoration: InputDecoration(
                            hintText: 'TYPE RESPONSE...',
                            hintStyle: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: EditorialTokens.surface,
          child: SizedBox(
            width: double.infinity,
            child: EditorialButton(
              label: 'Submit Examination',
              icon: Icons.check,
              onPressed: _submitExam,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsView() {
    final passed = _finalScorePct >= 60;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: EditorialTokens.paper,
            borderRadius: BorderRadius.circular(EditorialTokens.r6),
            border: Border.all(color: EditorialTokens.border, width: EditorialTokens.hairline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                passed ? Icons.verified_outlined : Icons.info_outline,
                size: 48,
                color: passed ? const Color(0xFF386641) : EditorialTokens.primary,
              ),
              const SizedBox(height: 16),
              const EditorialEyebrow(text: 'EVALUATION REPORT'),
              const SizedBox(height: 4),
              Text(
                'Assessment Concluded',
                style: EditorialTokens.titleLarge(),
              ),
              const SizedBox(height: 12),
              EditorialStatStrip(
                primaryText: 'FINAL ACCURACY',
                secondaryText: '${_finalScorePct.toInt()}% SCORE',
              ),
              const SizedBox(height: 20),
              EditorialButton(
                label: 'Return to Document',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
