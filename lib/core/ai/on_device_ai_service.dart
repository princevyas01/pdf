import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/semantic_chunk.dart';
import '../../models/study_item.dart';
import '../storage/database_helper.dart';
import 'ai_model_manager.dart';
import 'local_ai_provider.dart';
import 'local_llm_service.dart';
import 'semantic_search_service.dart';

class OnDeviceAIService implements LocalAIProvider {
  static final OnDeviceAIService instance = OnDeviceAIService._init();
  OnDeviceAIService._init();

  String _clip(String text, int maxChars) =>
      text.length <= maxChars ? text : '${text.substring(0, maxChars)}...';

  Future<String?> _llm({required String system, required String user, int maxTokens = 512}) async {
    await AiModelManager.instance.initialize();
    if (!AiModelManager.instance.config.isEnabled || !AiModelManager.instance.config.isInstalled) return null;
    try {
      final output = await LocalLlmService.instance.generate(
        systemPrompt: system,
        userPrompt: user,
        maxTokens: maxTokens,
        temperature: AiModelManager.instance.config.temperature,
      );
      final trimmed = output.trim();
      if (trimmed.isEmpty) {
        throw const LocalLlmException('The local model returned an empty response.');
      }
      return trimmed;
    } finally {
      if (AiModelManager.instance.config.autoUnload) {
        await LocalLlmService.instance.unload();
      }
    }
  }

  @override
  Future<GroundedAnswer> answerQuestion({
    required String filePath,
    required String question,
    required Map<int, String> pageTextMap,
  }) async {
    if (pageTextMap.isEmpty) {
      return GroundedAnswer(answer: 'Not enough information was found in this document.', sourcePages: [], hasSufficientContext: false);
    }
    List<SemanticChunk> chunks = [];
    try { chunks = await DatabaseHelper.instance.getSemanticChunksForFile(filePath); } catch (_) {}
    if (chunks.isEmpty) {
      chunks = await SemanticSearchService.chunkDocumentText(filePath, pageTextMap);
      try { await DatabaseHelper.instance.saveSemanticChunks(chunks); } catch (_) {}
    }
    final results = SemanticSearchService.search(question, chunks, topK: 4);
    if (results.isEmpty || results.first.score < 0.12) {
      return GroundedAnswer(answer: 'Not enough information was found in this document to answer your question.', sourcePages: [], hasSufficientContext: false);
    }
    final top = results.where((r) => r.score >= 0.10).toList();
    final sourcePages = top.map((r) => r.chunk.pageNumber).toSet().toList()..sort();
    final context = top.map((r) => '[Page ${r.chunk.pageNumber}] ${r.chunk.chunkText}').join('\n\n');

    try {
      final answer = await _llm(
        system: 'You are a private offline study assistant. Answer only from the supplied document context. If the context is insufficient, say so. Do not invent facts. Give a concise student-friendly answer and cite relevant pages.',
        user: 'DOCUMENT CONTEXT:\n$context\n\nQUESTION:\n$question\n\nAnswer using only the document context.',
        maxTokens: 600,
      );
      if (answer != null) {
        return GroundedAnswer(answer: 'Based on this PDF:\n\n$answer', sourcePages: sourcePages, hasSufficientContext: true);
      }
    } catch (e) {
      return GroundedAnswer(
        answer: 'Local AI Inference Error: $e\n\nPlease check your model in Settings > Local AI Models.',
        sourcePages: sourcePages,
        hasSufficientContext: false,
      );
    }

    final fallback = await compute(_generateExtractiveAnswer, _QAData(context, question));
    return GroundedAnswer(answer: '[Local AI unavailable - using fallback extraction]\n\nBased on this PDF:\n\n$fallback', sourcePages: sourcePages, hasSufficientContext: true);
  }

  @override
  Future<String> explainText({required String selectedText, required String surroundingContext, required ExplanationMode mode}) async {
    final cleanText = selectedText.trim();
    if (cleanText.isEmpty) return 'No text selected for explanation.';
    final style = switch (mode) {
      ExplanationMode.simple => 'Explain in simple language for a college student.',
      ExplanationMode.detailed => 'Explain the concept technically, with mechanism and relationships.',
      ExplanationMode.examFocused => 'Explain in exam-ready form with definition, key points and one example.',
    };
    try {
      final answer = await _llm(
        system: 'You are an offline study tutor. $style Use only the provided text/context. Do not invent citations or facts. Do not reveal hidden reasoning.',
        user: 'SELECTED TEXT:\n$cleanText\n\nSURROUNDING CONTEXT:\n${_clip(surroundingContext, 4000)}',
        maxTokens: 450,
      );
      if (answer != null) return answer;
    } catch (e) {
      return 'Local AI Inference Error: $e\n\nPlease check your model in Settings > Local AI Models.';
    }
    return '[Local AI unavailable - using fallback extraction]\n\nExplanation:\n\n$cleanText\n\nContext:\n${_clip(surroundingContext, 240)}';
  }

  @override
  Future<String> summarizeSection({required String text, required int startPage, required int endPage}) async {
    if (text.trim().isEmpty) return 'No text available for pages $startPage - $endPage.';
    try {
      final answer = await _llm(
        system: 'You are an offline study-note generator. Produce a compact factual revision summary using only the supplied document text. Include 5-8 bullet points and a short key takeaway. Do not reveal hidden reasoning.',
        user: 'PAGES $startPage-$endPage:\n${_clip(text, 10000)}',
        maxTokens: 500,
      );
      if (answer != null) return 'Summary of Pages $startPage - $endPage:\n\n$answer';
    } catch (e) {
      return 'Local AI Inference Error: $e\n\nPlease check your model in Settings > Local AI Models.';
    }
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.trim().length > 20).toList();
    final summary = sentences.take(min(3, sentences.length)).join(' ');
    return '[Local AI unavailable - using fallback extraction]\n\nSummary of Pages $startPage - $endPage:\n\n$summary';
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
    final compact = pageTextMap.entries.map((e) => '[Page ${e.key}] ${_clip(e.value, 1200)}').join('\n');
    final validPageNumbers = pageTextMap.keys.toSet();

    try {
      final output = await _llm(
        system: 'You generate exam questions from source text. Output ONLY valid JSON array. Each item must have: page, type, question, options, correctAnswer, explanation, marks, topic. type must be one of mcq,trueFalse,shortAnswer.',
        user: 'TOPIC: $topic\nDIFFICULTY: $difficulty\nCOUNT: $questionCount\nSOURCE:\n$compact',
        maxTokens: 1000,
      );
      if (output != null) {
        final cleaned = output.replaceFirst(RegExp(r'^[^\[]*'), '').replaceFirst(RegExp(r'[^\]]*$'), '');
        final data = jsonDecode(cleaned);
        if (data is List) {
          final items = <StudyQuestion>[];
          for (final raw in data) {
            if (raw is! Map) continue;
            final qText = raw['question']?.toString().trim() ?? '';
            final cAns = raw['correctAnswer']?.toString().trim() ?? '';
            if (qText.isEmpty || cAns.isEmpty) continue;

            final rawPage = int.tryParse(raw['page']?.toString() ?? '');
            if (rawPage == null || !validPageNumbers.contains(rawPage)) continue;

            final typeName = raw['type']?.toString() ?? 'mcq';
            final type = QuestionType.values.firstWhere((e) => e.name == typeName, orElse: () => QuestionType.mcq);
            final opts = (raw['options'] is List) ? (raw['options'] as List).map((e) => e.toString()).toList() : <String>[];
            items.add(StudyQuestion(
              filePath: filePath,
              pageNumber: rawPage,
              type: type,
              question: qText,
              options: opts,
              correctAnswer: cAns,
              explanation: raw['explanation']?.toString() ?? '',
              marks: int.tryParse(raw['marks']?.toString() ?? '') ?? 1,
              topic: raw['topic']?.toString() ?? topic,
            ));
          }
          if (items.isNotEmpty) return items.take(questionCount).toList();
        }
      }
    } catch (e) {
      debugPrint('Local AI question generation error: $e');
      return compute(_fallbackQuestions, _FallbackQuestionData(
        filePath,
        pageTextMap,
        topic,
        difficulty,
        questionCount,
        errorNote: 'Local AI Inference Error: $e',
      ));
    }
    return compute(_fallbackQuestions, _FallbackQuestionData(
      filePath,
      pageTextMap,
      topic,
      difficulty,
      questionCount,
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
  final keywords = data.question.toLowerCase().split(RegExp(r'\s+')).where((k) => k.length > 2).toList();
  final matched = sentences.where((s) => keywords.any((k) => s.toLowerCase().contains(k))).toList();
  return (matched.isNotEmpty ? matched : sentences).take(3).join(' ');
}

class _FallbackQuestionData {
  final String filePath;
  final Map<int, String> pages;
  final String topic;
  final String difficulty;
  final int count;
  final String? errorNote;
  _FallbackQuestionData(this.filePath, this.pages, this.topic, this.difficulty, this.count, {this.errorNote});
}

List<StudyQuestion> _fallbackQuestions(_FallbackQuestionData data) {
  final items = <StudyQuestion>[];
  final entries = data.pages.entries.toList();
  final note = data.errorNote != null
      ? '[Fallback - ${data.errorNote}] '
      : '[Fallback Extraction - Local AI Not Active] ';
  for (int i = 0; i < data.count && i < entries.length * 2; i++) {
    final e = entries[i % entries.length];
    final sentence = e.value.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.trim().length > 30).firstOrNull;
    if (sentence == null) continue;
    final words = sentence.split(RegExp(r'\s+')).where((w) => w.length > 4).toList();
    final keyword = words.isNotEmpty ? words.first : 'Concept';
    items.add(StudyQuestion(
      filePath: data.filePath,
      pageNumber: e.key,
      type: QuestionType.shortAnswer,
      question: 'Explain the role of $keyword as discussed on Page ${e.key}.',
      correctAnswer: sentence,
      explanation: '${note}Document context from Page ${e.key}',
      marks: 2,
      topic: data.topic,
    ));
  }
  return items;
}
