import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../../core/storage/database_helper.dart';
import '../../core/storage/ocr_cache_service.dart';
import '../../core/study/local_summarizer_service.dart';
import '../../core/study/study_generator_service.dart';
import '../../core/study/topic_extractor_service.dart';
import '../../core/theme/editorial_tokens.dart';
import '../../models/pdf_file.dart';
import '../../models/study_item.dart';
import '../../models/study_session.dart';
import '../../widgets/editorial_components.dart';
import '../viewer/pdf_viewer_screen.dart';

class StudyModeScreen extends ConsumerStatefulWidget {
  final PdfFile pdfFile;

  const StudyModeScreen({super.key, required this.pdfFile});

  @override
  ConsumerState<StudyModeScreen> createState() => _StudyModeScreenState();
}

class _StudyModeScreenState extends ConsumerState<StudyModeScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  String _loadingMessage = 'Loading document text...';
  int _activeTabIndex = 0;

  Map<int, String> _pageTextMap = {};
  LocalSummarizerResult? _summaryResult;
  List<StudyTopic> _topics = [];
  List<ImportantTerm> _terms = [];
  List<Flashcard> _flashcards = [];
  List<StudyQuestion> _questions = [];

  int _currentFlashcardIndex = 0;
  bool _showFlashcardBack = false;

  final Map<int, String> _userAnswers = {};
  final Map<int, bool> _questionAnswered = {};
  int _correctCount = 0;
  int _attemptedCount = 0;

  final Stopwatch _studySessionStopwatch = Stopwatch();
  int _sessionStartTime = 0;
  Map<String, double> _weakTopics = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionStartTime = DateTime.now().millisecondsSinceEpoch;
    _studySessionStopwatch.start();
    _loadStudyData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _studySessionStopwatch.stop();
    _saveStudySession();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _studySessionStopwatch.stop();
      _saveStudySession();
    } else if (state == AppLifecycleState.resumed) {
      _studySessionStopwatch.start();
    }
  }

  Future<void> _saveStudySession() async {
    final elapsedSec = _studySessionStopwatch.elapsed.inSeconds;
    if (elapsedSec > 5 && _attemptedCount > 0) {
      final accuracy = (_correctCount / _attemptedCount) * 100.0;
      final session = StudySession(
        filePath: widget.pdfFile.path,
        startTime: _sessionStartTime,
        endTime: DateTime.now().millisecondsSinceEpoch,
        durationSeconds: elapsedSec,
        questionsAttempted: _attemptedCount,
        correctCount: _correctCount,
        accuracyPct: accuracy,
      );
      await DatabaseHelper.instance.saveStudySession(session);
    }
  }

  Future<void> _loadStudyData() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Reading text & cached OCR...';
    });

    try {
      final cachedOcr = await OcrCacheService.getCachedFileOcr(widget.pdfFile.path);
      _pageTextMap = Map.from(cachedOcr);

      if (_pageTextMap.isEmpty) {
        final fileBytes = await File(widget.pdfFile.path).readAsBytes();
        if (!mounted) return;
        final document = sf.PdfDocument(inputBytes: fileBytes);
        final extractor = sf.PdfTextExtractor(document);

        for (int i = 0; i < document.pages.count; i++) {
          final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i).trim();
          if (pageText.isNotEmpty) {
            _pageTextMap[i + 1] = pageText;
          }
        }
        document.dispose();
      }

      setState(() => _loadingMessage = 'Generating local summaries & study tools...');

      final fullText = _pageTextMap.values.join('\n\n');
      _summaryResult = await LocalSummarizerService.summarizeText(fullText);
      _topics = await TopicExtractorService.extractTopicsFromPages(widget.pdfFile.path, _pageTextMap);
      _terms = await TopicExtractorService.extractImportantTerms(_pageTextMap);

      final savedCards = await DatabaseHelper.instance.getFlashcards(widget.pdfFile.path);
      if (savedCards.isNotEmpty) {
        _flashcards = savedCards;
      } else {
        _flashcards = await StudyGeneratorService.generateFlashcards(widget.pdfFile.path, _pageTextMap);
        await DatabaseHelper.instance.saveFlashcards(_flashcards);
      }

      final savedQuestions = await DatabaseHelper.instance.getStudyQuestions(widget.pdfFile.path);
      if (savedQuestions.isNotEmpty) {
        _questions = savedQuestions;
      } else {
        _questions = await StudyGeneratorService.generateQuestions(widget.pdfFile.path, _pageTextMap);
        await DatabaseHelper.instance.saveStudyQuestions(_questions);
      }

      _weakTopics = await DatabaseHelper.instance.getTopicAccuracyForFile(widget.pdfFile.path);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToPage(int pageNumber) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          filePath: widget.pdfFile.path,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEditorialTopBar(),
            const EditorialDivider(),
            _buildTabSelector(),
            const EditorialDivider(),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: EditorialTokens.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _loadingMessage.toUpperCase(),
                            style: EditorialTokens.metadata().copyWith(
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _buildActiveTabContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorialTopBar() {
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
                const EditorialEyebrow(text: '04 · ACADEMIC SYNTHESIS'),
                const SizedBox(height: 2),
                Text(
                  'Study Studio',
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

  Widget _buildTabSelector() {
    final tabs = [
      '01 · SUMMARY',
      '02 · FLASHCARDS',
      '03 · QUIZ',
      '04 · TELEMETRY',
    ];

    return Container(
      height: 44,
      color: EditorialTokens.surface,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isSelected = _activeTabIndex == index;
          return GestureDetector(
            onTap: () => setState(() => _activeTabIndex = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? EditorialTokens.secondary : EditorialTokens.surfaceMuted,
                borderRadius: BorderRadius.circular(EditorialTokens.r4),
                border: Border.all(
                  color: isSelected ? EditorialTokens.secondary : EditorialTokens.border,
                  width: EditorialTokens.hairline,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                tabs[index],
                style: EditorialTokens.metadataStrong(
                  color: isSelected ? EditorialTokens.paper : EditorialTokens.inkMuted,
                ).copyWith(
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_activeTabIndex) {
      case 0:
        return _buildSummaryTab();
      case 1:
        return _buildFlashcardsTab();
      case 2:
        return _buildQuizTab();
      case 3:
        return _buildStatsTab();
      default:
        return _buildSummaryTab();
    }
  }

  // --- TAB 1: Summary & Key Points ---
  Widget _buildSummaryTab() {
    final summary = _summaryResult;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EditorialSectionHeader(
            number: '01',
            label: 'Executive Abstract',
            trailing: 'LOCAL AI SYNTHESIS',
          ),
          const SizedBox(height: 8),
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
            child: Text(
              summary?.quickSummary ?? 'No automated summary available for this document.',
              style: EditorialTokens.body(color: EditorialTokens.ink).copyWith(
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 24),
          EditorialSectionHeader(
            number: '02',
            label: 'Key Insights',
            trailing: '${summary?.keyPoints.length ?? 0} ITEMS',
          ),
          const SizedBox(height: 8),
          if (summary != null && summary.keyPoints.isNotEmpty)
            ...summary.keyPoints.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final point = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: EditorialTokens.paper,
                  borderRadius: BorderRadius.circular(EditorialTokens.r4),
                  border: Border.all(
                    color: EditorialTokens.borderSoft,
                    width: EditorialTokens.hairline,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: EditorialTokens.surfaceMuted,
                        borderRadius: BorderRadius.circular(EditorialTokens.r2),
                        border: Border.all(
                          color: EditorialTokens.border,
                          width: EditorialTokens.hairline,
                        ),
                      ),
                      child: Text(
                        idx.toString().padLeft(2, '0'),
                        style: EditorialTokens.metadataStrong(
                          color: EditorialTokens.primary,
                        ).copyWith(fontSize: 10),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        point,
                        style: EditorialTokens.bodyMedium(
                          color: EditorialTokens.ink,
                        ).copyWith(height: 1.45),
                      ),
                    ),
                  ],
                ),
              );
            })
          else
            Text(
              'No key insights identified.',
              style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
            ),
          const SizedBox(height: 24),
          EditorialSectionHeader(
            number: '03',
            label: 'Document Topics',
            trailing: '${_topics.length} SECTIONS',
          ),
          const SizedBox(height: 8),
          if (_topics.isNotEmpty)
            ..._topics.map((topic) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: EditorialTokens.paper,
                  borderRadius: BorderRadius.circular(EditorialTokens.r4),
                  border: Border.all(
                    color: EditorialTokens.borderSoft,
                    width: EditorialTokens.hairline,
                  ),
                ),
                child: InkWell(
                  onTap: () => _navigateToPage(topic.startPage),
                  borderRadius: BorderRadius.circular(EditorialTokens.r4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: EditorialTokens.surfaceMuted,
                            borderRadius: BorderRadius.circular(EditorialTokens.r2),
                          ),
                          child: Text(
                            'P. ${topic.startPage}–${topic.endPage}',
                            style: EditorialTokens.metadata(
                              color: EditorialTokens.tertiary,
                            ).copyWith(fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            topic.title,
                            style: EditorialTokens.titleSmall().copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward,
                          size: 14,
                          color: EditorialTokens.inkMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            })
          else
            Text(
              'No structured topics detected.',
              style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
            ),
          const SizedBox(height: 24),
          EditorialSectionHeader(
            number: '04',
            label: 'Codex Terms',
            trailing: '${_terms.length} DEFINED',
          ),
          const SizedBox(height: 8),
          if (_terms.isNotEmpty)
            ..._terms.map((term) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: EditorialTokens.paper,
                  borderRadius: BorderRadius.circular(EditorialTokens.r4),
                  border: Border.all(
                    color: EditorialTokens.borderSoft,
                    width: EditorialTokens.hairline,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          term.term,
                          style: EditorialTokens.titleSmall(
                            color: EditorialTokens.primary,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                        GestureDetector(
                          onTap: () => _navigateToPage(term.pageNumber),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: EditorialTokens.surfaceMuted,
                              borderRadius: BorderRadius.circular(EditorialTokens.r2),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'PAGE ${term.pageNumber}',
                                  style: EditorialTokens.metadata(
                                    color: EditorialTokens.secondary,
                                  ).copyWith(fontSize: 10),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.open_in_new,
                                  size: 10,
                                  color: EditorialTokens.secondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      term.context,
                      style: EditorialTokens.bodySmall(
                        color: EditorialTokens.inkSecondary,
                      ).copyWith(height: 1.4),
                    ),
                  ],
                ),
              );
            })
          else
            Text(
              'No salient terms detected.',
              style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
            ),
        ],
      ),
    );
  }

  // --- TAB 2: Flashcards ---
  Widget _buildFlashcardsTab() {
    if (_flashcards.isEmpty) {
      return Center(
        child: Text(
          'NO FLASHCARDS COMPILED FOR THIS DOCUMENT.',
          style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
        ),
      );
    }

    final card = _flashcards[_currentFlashcardIndex];
    final statusString = card.status == 1
        ? 'KNOWN'
        : (card.status == 2 ? 'DIFFICULT' : 'UNREVIEWED');

    final statusColor = card.status == 1
        ? const Color(0xFF386641)
        : (card.status == 2 ? EditorialTokens.primary : EditorialTokens.inkMuted);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'INDEX ${_currentFlashcardIndex + 1} OF ${_flashcards.length}',
                style: EditorialTokens.metadataStrong().copyWith(letterSpacing: 1.0),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: EditorialTokens.surface,
                  borderRadius: BorderRadius.circular(EditorialTokens.r2),
                  border: Border.all(
                    color: statusColor.withOpacity(0.5),
                    width: EditorialTokens.hairline,
                  ),
                ),
                child: Text(
                  statusString,
                  style: EditorialTokens.metadataStrong(
                    color: statusColor,
                  ).copyWith(fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showFlashcardBack = !_showFlashcardBack),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: EditorialTokens.paper,
                  borderRadius: BorderRadius.circular(EditorialTokens.r6),
                  border: Border.all(
                    color: EditorialTokens.border,
                    width: EditorialTokens.hairline,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    EditorialEyebrow(
                      text: _showFlashcardBack ? 'ANSWER' : 'QUESTION',
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                           child: Text(
                            _showFlashcardBack ? card.back : card.front,
                            style: EditorialTokens.displayMedium(
                              color: EditorialTokens.ink,
                            ).copyWith(
                              fontSize: 18,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'TAP CARD TO FLIP',
                      style: EditorialTokens.metadata(
                        color: EditorialTokens.inkMuted,
                      ).copyWith(
                        fontSize: 10,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: EditorialSecondaryButton(
                  label: 'Mark Difficult',
                  icon: Icons.flag_outlined,
                  onPressed: () async {
                    await DatabaseHelper.instance.updateFlashcardStatus(card.id!, 2);
                    setState(() {
                      _flashcards[_currentFlashcardIndex] = card.copyWith(status: 2);
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: EditorialButton(
                  label: 'Mark Known',
                  icon: Icons.check,
                  onPressed: () async {
                    await DatabaseHelper.instance.updateFlashcardStatus(card.id!, 1);
                    setState(() {
                      _flashcards[_currentFlashcardIndex] = card.copyWith(status: 1);
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: EditorialTokens.ink),
                onPressed: _currentFlashcardIndex > 0
                    ? () => setState(() {
                          _currentFlashcardIndex--;
                          _showFlashcardBack = false;
                        })
                    : null,
              ),
              Text(
                '${_currentFlashcardIndex + 1} / ${_flashcards.length}',
                style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward, color: EditorialTokens.ink),
                onPressed: _currentFlashcardIndex < _flashcards.length - 1
                    ? () => setState(() {
                          _currentFlashcardIndex++;
                          _showFlashcardBack = false;
                        })
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- TAB 3: Practice Quiz ---
  Widget _buildQuizTab() {
    if (_questions.isEmpty) {
      return Center(
        child: Text(
          'NO PRACTICE QUESTIONS COMPILED.',
          style: EditorialTokens.metadata(color: EditorialTokens.inkMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _questions.length,
      itemBuilder: (context, index) {
        final q = _questions[index];
        final isAnswered = _questionAnswered[index] ?? false;
        final selectedAnswer = _userAnswers[index];

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: EditorialTokens.surfaceMuted,
                      borderRadius: BorderRadius.circular(EditorialTokens.r2),
                      border: Border.all(
                        color: EditorialTokens.borderSoft,
                        width: EditorialTokens.hairline,
                      ),
                    ),
                    child: Text(
                      '${q.type.name.toUpperCase()}  ·  PAGE ${q.pageNumber}',
                      style: EditorialTokens.metadata(
                        color: EditorialTokens.tertiary,
                      ).copyWith(
                        fontSize: 10,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  if (q.marks > 1)
                    Text(
                      '${q.marks} PTS',
                      style: EditorialTokens.metadataStrong(
                        color: EditorialTokens.primary,
                      ).copyWith(fontSize: 10),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${index + 1}. ${q.question}',
                style: EditorialTokens.titleMedium().copyWith(
                  fontSize: 15,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              if (q.type == QuestionType.mcq || q.type == QuestionType.trueFalse) ...[
                ...q.options.map((opt) {
                  final isCorrectOpt = opt == q.correctAnswer;
                  final isSelected = selectedAnswer == opt;

                  Color optBg = EditorialTokens.surface;
                  Color borderColor = EditorialTokens.border;
                  Color textColor = EditorialTokens.ink;

                  if (isAnswered) {
                    if (isCorrectOpt) {
                      optBg = const Color(0xFFE8F0EA);
                      borderColor = const Color(0xFF386641);
                      textColor = const Color(0xFF24442B);
                    } else if (isSelected && !isCorrectOpt) {
                      optBg = const Color(0xFFF9ECE7);
                      borderColor = EditorialTokens.primary;
                      textColor = EditorialTokens.secondary;
                    }
                  } else if (isSelected) {
                    borderColor = EditorialTokens.primary;
                  }

                  return GestureDetector(
                    onTap: isAnswered
                        ? null
                        : () {
                            final isCorrect = opt == q.correctAnswer;
                            setState(() {
                              _userAnswers[index] = opt;
                              _questionAnswered[index] = true;
                              _attemptedCount++;
                              if (isCorrect) _correctCount++;
                            });

                            DatabaseHelper.instance.recordStudyAttempt(
                              StudyAttempt(
                                sessionId: 0,
                                questionId: q.id ?? index,
                                userAnswer: opt,
                                isCorrect: isCorrect,
                                timestamp: DateTime.now().millisecondsSinceEpoch,
                                topic: q.topic,
                              ),
                            );
                          },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: optBg,
                        border: Border.all(
                          color: borderColor,
                          width: EditorialTokens.hairline,
                        ),
                        borderRadius: BorderRadius.circular(EditorialTokens.r4),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isAnswered
                                ? (isCorrectOpt
                                    ? Icons.check_circle_outline
                                    : (isSelected ? Icons.cancel_outlined : Icons.circle_outlined))
                                : (isSelected ? Icons.radio_button_checked : Icons.radio_button_off),
                            size: 16,
                            color: borderColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              opt,
                              style: EditorialTokens.bodyMedium(
                                color: textColor,
                              ).copyWith(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ] else ...[
                if (!isAnswered)
                  EditorialButton(
                    label: 'Reveal Canonical Answer',
                    icon: Icons.visibility_outlined,
                    onPressed: () {
                      setState(() {
                        _userAnswers[index] = q.correctAnswer;
                        _questionAnswered[index] = true;
                        _attemptedCount++;
                        _correctCount++;
                      });
                    },
                  ),
              ],
              if (isAnswered) ...[
                const SizedBox(height: 10),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CANONICAL: ${q.correctAnswer}',
                        style: EditorialTokens.metadataStrong(
                          color: EditorialTokens.primary,
                        ).copyWith(fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        q.explanation,
                        style: EditorialTokens.bodySmall(
                          color: EditorialTokens.inkSecondary,
                        ).copyWith(height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _navigateToPage(q.pageNumber),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.menu_book,
                              size: 12,
                              color: EditorialTokens.secondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'OPEN PAGE ${q.pageNumber} IN VIEWER',
                              style: EditorialTokens.metadataStrong(
                                color: EditorialTokens.secondary,
                              ).copyWith(
                                fontSize: 10,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // --- TAB 4: Study Stats & Weak Topics ---
  Widget _buildStatsTab() {
    final accuracy = _attemptedCount > 0 ? (_correctCount / _attemptedCount) * 100.0 : 0.0;
    final elapsedSec = _studySessionStopwatch.elapsed.inSeconds;
    final mins = elapsedSec ~/ 60;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EditorialSectionHeader(
            number: '01',
            label: 'Session Telemetry',
            trailing: 'LOCAL BENCHMARK',
          ),
          const SizedBox(height: 12),
          EditorialStatStrip(
            primaryText: 'ACTIVE STUDY DURATION',
            secondaryText: '${mins}m · ACCURACY: ${accuracy.toInt()}%',
          ),
          const SizedBox(height: 8),
          EditorialStatStrip(
            primaryText: 'TOTAL ATTEMPTED',
            secondaryText: '$_attemptedCount QUESTIONS',
          ),
          const SizedBox(height: 24),
          const EditorialSectionHeader(
            number: '02',
            label: 'Critical Retention Focus',
            trailing: 'ACCURACY < 60%',
          ),
          const SizedBox(height: 10),
          if (_weakTopics.entries.any((e) => e.value < 0.60))
            ..._weakTopics.entries.where((e) => e.value < 0.60).map(
                  (e) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: EditorialTokens.paper,
                      borderRadius: BorderRadius.circular(EditorialTokens.r4),
                      border: Border.all(
                        color: EditorialTokens.borderSoft,
                        width: EditorialTokens.hairline,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.key,
                                style: EditorialTokens.titleSmall().copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'RETENTION TARGET REQUIRES REVIEW',
                                style: EditorialTokens.metadata(
                                  color: EditorialTokens.primary,
                                ).copyWith(fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: EditorialTokens.surfaceMuted,
                            borderRadius: BorderRadius.circular(EditorialTokens.r2),
                          ),
                          child: Text(
                            '${(e.value * 100).toInt()}%',
                            style: EditorialTokens.metadataStrong(
                              color: EditorialTokens.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
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
                  const Icon(
                    Icons.verified_outlined,
                    color: Color(0xFF386641),
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No weak topics recorded. Document comprehension exceeds thresholds.',
                      style: EditorialTokens.bodyMedium(
                        color: EditorialTokens.inkSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
