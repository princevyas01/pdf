import 'dart:math';
import 'package:flutter/foundation.dart';

class LocalSummarizerResult {
  final String quickSummary;
  final List<String> keyPoints;
  final List<String> chapterSummaries;

  LocalSummarizerResult({
    required this.quickSummary,
    required this.keyPoints,
    required this.chapterSummaries,
  });
}

class LocalSummarizerService {
  static const Set<String> _stopWords = {
    'the', 'a', 'an', 'and', 'or', 'but', 'is', 'are', 'was', 'were',
    'in', 'on', 'at', 'to', 'for', 'with', 'by', 'about', 'against',
    'between', 'into', 'through', 'during', 'before', 'after', 'above',
    'below', 'from', 'up', 'down', 'out', 'off', 'over', 'under',
    'again', 'further', 'then', 'once', 'here', 'there', 'when', 'where',
    'why', 'how', 'all', 'any', 'both', 'each', 'few', 'more', 'most',
    'other', 'some', 'such', 'no', 'nor', 'not', 'only', 'own', 'same',
    'so', 'than', 'too', 'very', 's', 't', 'can', 'will', 'just', 'don',
    'should', 'now', 'this', 'that', 'these', 'those', 'it', 'its', 'of'
  };

  static Future<LocalSummarizerResult> summarizeText(String text, {int maxKeyPoints = 5}) async {
    return compute(_SummarizerData.process, _SummarizerData(text: text, maxKeyPoints: maxKeyPoints));
  }

  static List<String> _splitSentences(String text) {
    final RegExp sentenceRegex = RegExp(r'(?<=[.!?])\s+');
    final raw = text.split(sentenceRegex);
    return raw
        .map((s) => s.trim())
        .where((s) => s.length > 20 && s.length < 350)
        .toList();
  }
}

class _SummarizerData {
  final String text;
  final int maxKeyPoints;

  _SummarizerData({required this.text, required this.maxKeyPoints});

  static LocalSummarizerResult process(_SummarizerData data) {
    if (data.text.trim().isEmpty) {
      return LocalSummarizerResult(
        quickSummary: 'No extractable text available in this document.',
        keyPoints: [],
        chapterSummaries: [],
      );
    }

    final sentences = LocalSummarizerService._splitSentences(data.text);
    if (sentences.isEmpty) {
      return LocalSummarizerResult(
        quickSummary: data.text.length > 200 ? '${data.text.substring(0, 200)}...' : data.text,
        keyPoints: [data.text],
        chapterSummaries: [],
      );
    }

    final Map<String, int> wordFreq = {};
    for (final sentence in sentences) {
      final words = sentence.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').split(RegExp(r'\s+'));
      for (final w in words) {
        if (w.length > 2 && !LocalSummarizerService._stopWords.contains(w)) {
          wordFreq[w] = (wordFreq[w] ?? 0) + 1;
        }
      }
    }

    final List<MapEntry<String, double>> scoredSentences = [];
    for (int i = 0; i < sentences.length; i++) {
      final s = sentences[i];
      final words = s.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').split(RegExp(r'\s+'));
      double score = 0.0;
      int wordCount = 0;
      for (final w in words) {
        if (w.length > 2 && !LocalSummarizerService._stopWords.contains(w)) {
          score += (wordFreq[w] ?? 0);
          wordCount++;
        }
      }
      if (wordCount > 0) {
        score = score / sqrt(wordCount);
        if (i == 0 || i < 3) score *= 1.25;
      }
      scoredSentences.add(MapEntry(s, score));
    }

    scoredSentences.sort((a, b) => b.value.compareTo(a.value));

    final topSentences = scoredSentences
        .take(min(data.maxKeyPoints, scoredSentences.length))
        .map((e) => e.key)
        .toList();

    final quickSummaryStr = topSentences.take(2).join(' ');

    return LocalSummarizerResult(
      quickSummary: quickSummaryStr.isEmpty ? data.text.take(200) : quickSummaryStr,
      keyPoints: topSentences,
      chapterSummaries: topSentences.take(min(3, topSentences.length)).toList(),
    );
  }
}

extension StringTakeExt on String {
  String take(int n) => length <= n ? this : '${substring(0, n)}...';
}
