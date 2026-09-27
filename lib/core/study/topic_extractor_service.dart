import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/study_item.dart';

class TopicExtractorService {
  static const Set<String> _commonStopWords = {
    'the', 'a', 'an', 'and', 'or', 'but', 'is', 'are', 'was', 'were',
    'in', 'on', 'at', 'to', 'for', 'with', 'by', 'about', 'against',
    'between', 'into', 'through', 'during', 'before', 'after', 'above',
    'below', 'from', 'up', 'down', 'out', 'off', 'over', 'under',
    'again', 'further', 'then', 'once', 'here', 'there', 'when', 'where',
    'why', 'how', 'all', 'any', 'both', 'each', 'few', 'more', 'most',
    'other', 'some', 'such', 'no', 'nor', 'not', 'only', 'own', 'same',
    'so', 'than', 'too', 'very', 's', 't', 'can', 'will', 'just', 'don',
    'should', 'now', 'this', 'that', 'these', 'those', 'it', 'its', 'of',
    'figure', 'table', 'page', 'chapter', 'section', 'also', 'using', 'used'
  };

  static Future<List<StudyTopic>> extractTopicsFromPages(
    String filePath,
    Map<int, String> pageTextMap,
  ) async {
    return compute(_extractTopicsLogic, _TopicData(filePath: filePath, pageTextMap: pageTextMap));
  }

  static Future<List<ImportantTerm>> extractImportantTerms(
    Map<int, String> pageTextMap, {
    int maxTerms = 12,
  }) async {
    return compute(_extractTermsLogic, _TermsData(pageTextMap: pageTextMap, maxTerms: maxTerms));
  }
}

class _TopicData {
  final String filePath;
  final Map<int, String> pageTextMap;
  _TopicData({required this.filePath, required this.pageTextMap});
}

List<StudyTopic> _extractTopicsLogic(_TopicData data) {
  if (data.pageTextMap.isEmpty) return [];

  final List<StudyTopic> topics = [];
  final totalPages = data.pageTextMap.keys.isNotEmpty
      ? data.pageTextMap.keys.reduce(max)
      : 1;

  // Detect section headers / capitalized phrases
  final RegExp headerRegex = RegExp(
    r'^(?:Chapter|Section|\d+\.|\d+\.\d+)?\s*([A-Z][A-Za-z0-9\s]{3,40})$',
    multiLine: true,
  );

  final Map<String, List<int>> topicPages = {};

  data.pageTextMap.forEach((page, text) {
    final matches = headerRegex.allMatches(text);
    for (final m in matches) {
      final title = m.group(1)?.trim();
      if (title != null && title.isNotEmpty && !TopicExtractorService._commonStopWords.contains(title.toLowerCase())) {
        topicPages.putIfAbsent(title, () => []).add(page);
      }
    }
  });

  if (topicPages.isNotEmpty) {
    topicPages.forEach((title, pages) {
      pages.sort();
      topics.add(
        StudyTopic(
          filePath: data.filePath,
          title: title,
          startPage: pages.first,
          endPage: pages.last,
        ),
      );
    });
  }

  // Fallback: If no headers detected, chunk document into logical page-range topics
  if (topics.isEmpty) {
    final chunkSize = max(1, (totalPages / 4).ceil());
    for (int i = 1; i <= totalPages; i += chunkSize) {
      final end = min(totalPages, i + chunkSize - 1);
      topics.add(
        StudyTopic(
          filePath: data.filePath,
          title: 'Section (Pages $i - $end)',
          startPage: i,
          endPage: end,
        ),
      );
    }
  }

  return topics.take(8).toList();
}

class _TermsData {
  final Map<int, String> pageTextMap;
  final int maxTerms;
  _TermsData({required this.pageTextMap, required this.maxTerms});
}

List<ImportantTerm> _extractTermsLogic(_TermsData data) {
  if (data.pageTextMap.isEmpty) return [];

  final Map<String, int> termFrequency = {};
  final Map<String, String> termContexts = {};
  final Map<String, int> termPage = {};

  // Pattern for Title-Cased or Defined Terms (e.g. "Primary Key", "Normalization")
  final RegExp termRegex = RegExp(r'\b([A-Z][a-z]{2,}(?:\s+[A-Z][a-z]{2,})?)\b');

  data.pageTextMap.forEach((page, text) {
    final matches = termRegex.allMatches(text);
    for (final m in matches) {
      final term = m.group(1)?.trim();
      if (term != null &&
          term.length >= 4 &&
          !TopicExtractorService._commonStopWords.contains(term.toLowerCase())) {
        termFrequency[term] = (termFrequency[term] ?? 0) + 1;
        if (!termContexts.containsKey(term)) {
          final idx = text.indexOf(term);
          final start = max(0, idx - 40);
          final end = min(text.length, idx + term.length + 60);
          termContexts[term] = '...${text.substring(start, end).replaceAll('\n', ' ').trim()}...';
          termPage[term] = page;
        }
      }
    }
  });

  final sortedTerms = termFrequency.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final List<ImportantTerm> result = [];
  for (final entry in sortedTerms.take(data.maxTerms)) {
    final term = entry.key;
    result.add(
      ImportantTerm(
        term: term,
        context: termContexts[term] ?? term,
        pageNumber: termPage[term] ?? 1,
      ),
    );
  }

  return result;
}
