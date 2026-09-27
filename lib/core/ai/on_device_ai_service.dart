import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/semantic_chunk.dart';
import '../../models/study_item.dart';
import '../storage/database_helper.dart';
import 'ai_model_manager.dart';
import 'local_ai_provider.dart';
import 'semantic_search_service.dart';

class OnDeviceAIService implements LocalAIProvider {
  static final OnDeviceAIService instance = OnDeviceAIService._init();
  OnDeviceAIService._init();

  @override
  Future<GroundedAnswer> answerQuestion({
    required String filePath,
    required String question,
    required Map<int, String> pageTextMap,
  }) async {
    if (!AiModelManager.instance.config.isEnabled) {
      return GroundedAnswer(
        answer: 'Local AI is currently disabled in AI Settings.',
        sourcePages: [],
        hasSufficientContext: false,
      );
    }

    if (pageTextMap.isEmpty) {
      return GroundedAnswer(
        answer: 'Not enough information was found in this document.',
        sourcePages: [],
        hasSufficientContext: false,
      );
    }

    // 1. Fetch or generate semantic chunks
    List<SemanticChunk> chunks = [];
    try {
      chunks = await DatabaseHelper.instance.getSemanticChunksForFile(filePath);
    } catch (_) {}

    if (chunks.isEmpty) {
      chunks = await SemanticSearchService.chunkDocumentText(filePath, pageTextMap);
      try {
        await DatabaseHelper.instance.saveSemanticChunks(chunks);
      } catch (_) {}
    }

    // 2. Perform local semantic vector search
    final searchResults = SemanticSearchService.search(question, chunks, topK: 4);

    if (searchResults.isEmpty || searchResults.first.score < 0.12) {
      return GroundedAnswer(
        answer: 'Not enough information was found in this document to answer your question.',
        sourcePages: [],
        hasSufficientContext: false,
      );
    }

    final topResults = searchResults.where((r) => r.score >= 0.10).toList();
    final sourcePages = topResults.map((r) => r.chunk.pageNumber).toSet().toList()..sort();

    final contextSnippet = topResults.map((r) => r.chunk.chunkText).join('\n\n');

    // 3. Extractive Document Q&A Generation
    final answerText = await compute(_generateExtractiveAnswer, _QAData(contextSnippet, question));

    return GroundedAnswer(
      answer: 'Based on this PDF:\n\n$answerText',
      sourcePages: sourcePages,
      hasSufficientContext: true,
    );
  }

  @override
  Future<String> explainText({
    required String selectedText,
    required String surroundingContext,
    required ExplanationMode mode,
  }) async {
    final cleanText = selectedText.trim();
    if (cleanText.isEmpty) return 'No text selected for explanation.';

    switch (mode) {
      case ExplanationMode.simple:
        return 'Simple Explanation:\n\n"$cleanText" means the core concept or mechanism described here in the document context. It represents a fundamental building block of the topic.';
      case ExplanationMode.detailed:
        return 'Detailed Technical Explanation:\n\nSelected Term: "$cleanText"\n\nIn the context of the document, this concept establishes structural rules, relationships, and computational behavior. Surrounding context reference: "${surroundingContext.take(120)}"';
      case ExplanationMode.examFocused:
        return 'Exam-Focused Key Points:\n\n• Definition: $cleanText\n• Key Takeaway: Essential concept commonly tested in exam short-answer questions.\n• Example Context: ${surroundingContext.take(100)}';
    }
  }

  @override
  Future<String> summarizeSection({
    required String text,
    required int startPage,
    required int endPage,
  }) async {
    if (text.trim().isEmpty) return 'No text available for pages $startPage - $endPage.';
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.trim().length > 20).toList();
    if (sentences.isEmpty) return text.take(200);

    final summary = sentences.take(min(3, sentences.length)).join(' ');
    return 'Summary of Pages $startPage - $endPage:\n\n$summary';
  }

  @override
  Future<List<StudyQuestion>> generateExamQuestions({
    required String filePath,
    required Map<int, String> pageTextMap,
    required String topic,
    required String difficulty,
    required int questionCount,
  }) async {
    if (pageTextMap.isEmpty) return [];

    return compute(_generateExamQuestionsLogic, _ExamData(
      filePath: filePath,
      pageTextMap: pageTextMap,
      topic: topic,
      difficulty: difficulty,
      questionCount: questionCount,
    ));
  }
}

class _QAData {
  final String contextSnippet;
  final String question;
  _QAData(this.contextSnippet, this.question);
}

String _generateExtractiveAnswer(_QAData data) {
  final sentences = data.contextSnippet.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.trim().length > 15).toList();
  final qLower = data.question.toLowerCase();
  final keywords = qLower.split(RegExp(r'\s+')).where((k) => k.length > 2).toList();

  List<String> matchedSentences = [];
  for (final s in sentences) {
    final sLower = s.toLowerCase();
    int matches = 0;
    for (final k in keywords) {
      if (sLower.contains(k)) matches++;
    }
    if (matches > 0) {
      matchedSentences.add(s);
    }
  }

  if (matchedSentences.isNotEmpty) {
    return matchedSentences.take(3).join(' ');
  } else {
    return sentences.take(2).join(' ');
  }
}

class _ExamData {
  final String filePath;
  final Map<int, String> pageTextMap;
  final String topic;
  final String difficulty;
  final int questionCount;
  _ExamData({
    required this.filePath,
    required this.pageTextMap,
    required this.topic,
    required this.difficulty,
    required this.questionCount,
  });
}

List<StudyQuestion> _generateExamQuestionsLogic(_ExamData data) {
  final List<StudyQuestion> questions = [];
  final List<MapEntry<int, String>> pages = data.pageTextMap.entries.toList();

  for (int i = 0; i < data.questionCount && i < pages.length * 2; i++) {
    final entry = pages[i % pages.length];
    final page = entry.key;
    final text = entry.value;

    final sentences = text.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.trim().length > 30).toList();
    if (sentences.isEmpty) continue;

    final sentence = sentences.first.trim();
    final words = sentence.split(RegExp(r'\s+')).where((w) => w.length > 4).toList();
    final keyword = words.isNotEmpty ? words.first : 'Concept';

    if (data.difficulty.toLowerCase() == 'easy') {
      questions.add(
        StudyQuestion(
          filePath: data.filePath,
          pageNumber: page,
          type: QuestionType.trueFalse,
          question: '(Easy) $sentence',
          options: ['TRUE', 'FALSE'],
          correctAnswer: 'TRUE',
          explanation: 'Source Page $page: "$sentence"',
          topic: data.topic,
        ),
      );
    } else if (data.difficulty.toLowerCase() == 'medium') {
      questions.add(
        StudyQuestion(
          filePath: data.filePath,
          pageNumber: page,
          type: QuestionType.mcq,
          question: '(Medium) What does the document state regarding $keyword?',
          options: [
            sentence.take(60),
            'It has no impact on system behavior',
            'It is explicitly deprecated',
            'None of the above'
          ]..shuffle(),
          correctAnswer: sentence.take(60),
          explanation: 'Source Page $page: $sentence',
          topic: data.topic,
        ),
      );
    } else {
      questions.add(
        StudyQuestion(
          filePath: data.filePath,
          pageNumber: page,
          type: QuestionType.shortAnswer,
          question: '(Hard - 5 Marks) Critically analyze the role of $keyword as discussed on Page $page.',
          correctAnswer: sentence,
          explanation: 'Document Reference: $sentence',
          marks: 5,
          topic: data.topic,
        ),
      );
    }
  }

  return questions;
}

extension StringTakeExt on String {
  String take(int n) => length <= n ? this : '${substring(0, n)}...';
}
