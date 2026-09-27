import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/study_item.dart';

class StudyGeneratorService {
  static Future<List<Flashcard>> generateFlashcards(
    String filePath,
    Map<int, String> pageTextMap, {
    int maxCards = 10,
  }) async {
    return compute(_generateFlashcardsLogic, _StudyGenData(filePath: filePath, pageTextMap: pageTextMap, maxItems: maxCards));
  }

  static Future<List<StudyQuestion>> generateQuestions(
    String filePath,
    Map<int, String> pageTextMap, {
    int maxQuestions = 12,
  }) async {
    return compute(_generateQuestionsLogic, _StudyGenData(filePath: filePath, pageTextMap: pageTextMap, maxItems: maxQuestions));
  }

  static List<_DefItem> _extractDefinitionSentences(Map<int, String> pageTextMap) {
    final List<_DefItem> items = [];
    final RegExp defPattern = RegExp(
      r'\b([A-Z][a-zA-Z0-9 ]{2,25})\s+(?:is|are|refers to|means|is defined as)\s+([^.!\n]{15,150})',
      caseSensitive: false,
    );

    pageTextMap.forEach((page, text) {
      final matches = defPattern.allMatches(text);
      for (final m in matches) {
        final term = m.group(1)?.trim();
        final def = m.group(2)?.trim();
        if (term != null && def != null && term.length > 3) {
          items.add(
            _DefItem(
              term: term,
              definition: def,
              sentence: '${m.group(0)?.trim()}',
              pageNumber: page,
            ),
          );
        }
      }
    });

    return items;
  }
}

class _DefItem {
  final String term;
  final String definition;
  final String sentence;
  final int pageNumber;

  _DefItem({
    required this.term,
    required this.definition,
    required this.sentence,
    required this.pageNumber,
  });
}

class _StudyGenData {
  final String filePath;
  final Map<int, String> pageTextMap;
  final int maxItems;
  _StudyGenData({required this.filePath, required this.pageTextMap, required this.maxItems});
}

List<Flashcard> _generateFlashcardsLogic(_StudyGenData data) {
  final items = StudyGeneratorService._extractDefinitionSentences(data.pageTextMap);
  final List<Flashcard> cards = [];

  for (int i = 0; i < min(data.maxItems, items.length); i++) {
    final item = items[i];
    cards.add(Flashcard(
      filePath: data.filePath,
      pageNumber: item.pageNumber,
      front: item.term,
      back: '${item.definition}\n\n(Source: Page ${item.pageNumber})',
    ));
  }

  if (cards.isEmpty) {
    final pages = data.pageTextMap.entries.toList();
    for (int i = 0; i < min(data.maxItems, pages.length); i++) {
      final entry = pages[i];
      final sentences = entry.value.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.trim().length > 30).toList();
      if (sentences.isEmpty) continue;
      final sentence = sentences.first.trim();
      final words = sentence.split(RegExp(r'\s+')).where((w) => w.length > 4).toList();
      final keyword = words.isNotEmpty ? words.first : 'Concept';
      cards.add(Flashcard(
        filePath: data.filePath,
        pageNumber: entry.key,
        front: 'Define: $keyword',
        back: sentence,
      ));
    }
  }

  return cards;
}

List<StudyQuestion> _generateQuestionsLogic(_StudyGenData data) {
  final items = StudyGeneratorService._extractDefinitionSentences(data.pageTextMap);
  final List<StudyQuestion> questions = [];

  for (int i = 0; i < min(data.maxItems, items.length); i++) {
    final item = items[i];
    if (i % 3 == 0) {
      questions.add(StudyQuestion(
        filePath: data.filePath,
        pageNumber: item.pageNumber,
        type: QuestionType.mcq,
        question: 'What does "${item.term}" refer to?',
        options: [
          item.definition,
          'It has no impact on system behavior',
          'It is explicitly deprecated',
          'None of the above',
        ],
        correctAnswer: item.definition,
        explanation: 'Source Page ${item.pageNumber}: ${item.sentence}',
      ));
    } else if (i % 3 == 1) {
      questions.add(StudyQuestion(
        filePath: data.filePath,
        pageNumber: item.pageNumber,
        type: QuestionType.trueFalse,
        question: '${item.term} ${item.definition}',
        options: ['TRUE', 'FALSE'],
        correctAnswer: 'TRUE',
        explanation: 'Source Page ${item.pageNumber}: ${item.sentence}',
      ));
    } else {
      questions.add(StudyQuestion(
        filePath: data.filePath,
        pageNumber: item.pageNumber,
        type: QuestionType.shortAnswer,
        question: 'Explain the concept of "${item.term}" as discussed on Page ${item.pageNumber}.',
        correctAnswer: item.definition,
        explanation: 'Document Reference: ${item.sentence}',
        marks: 3,
      ));
    }
  }

  return questions;
}
