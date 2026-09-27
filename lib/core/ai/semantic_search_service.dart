import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../models/semantic_chunk.dart';

class SemanticSearchResult {
  final SemanticChunk chunk;
  final double score;

  SemanticSearchResult({required this.chunk, required this.score});
}

class SemanticSearchService {
  static const int _vectorDim = 16;

  static Future<List<SemanticChunk>> chunkDocumentText(
    String filePath,
    Map<int, String> pageTextMap,
  ) async {
    return compute(_chunkDocumentLogic, _ChunkData(filePath: filePath, pageTextMap: pageTextMap));
  }

  static List<SemanticSearchResult> search(
    String query,
    List<SemanticChunk> chunks, {
    int topK = 5,
  }) {
    if (query.trim().isEmpty || chunks.isEmpty) return [];

    final queryVector = _generateLocalEmbedding(query);
    final List<SemanticSearchResult> results = [];

    for (final chunk in chunks) {
      double score = 0.0;
      if (chunk.vectorData.length == _vectorDim && queryVector.length == _vectorDim) {
        score = _cosineSimilarity(queryVector, chunk.vectorData);
      }

      // Keyword match boost
      final qTerms = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.length > 2);
      final chunkLower = chunk.chunkText.toLowerCase();
      for (final term in qTerms) {
        if (chunkLower.contains(term)) {
          score += 0.25;
        }
      }

      results.add(SemanticSearchResult(chunk: chunk, score: score));
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(topK).toList();
  }

  static List<double> _generateLocalEmbedding(String text) {
    final clean = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    final words = clean.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
    final vector = List<double>.filled(_vectorDim, 0.0);

    if (words.isEmpty) return vector;

    for (final w in words) {
      int hash = 0;
      for (int i = 0; i < w.length; i++) {
        hash = (hash * 31 + w.codeUnitAt(i)) & 0xFFFFFFFF;
      }
      final idx = hash % _vectorDim;
      vector[idx] += 1.0;
    }

    // Normalize L2 norm
    double norm = 0.0;
    for (final val in vector) {
      norm += val * val;
    }
    norm = sqrt(norm);
    if (norm > 0) {
      for (int i = 0; i < _vectorDim; i++) {
        vector[i] /= norm;
      }
    }

    return vector;
  }

  static double _cosineSimilarity(List<double> v1, List<double> v2) {
    double dot = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;
    for (int i = 0; i < v1.length; i++) {
      dot += v1[i] * v2[i];
      norm1 += v1[i] * v1[i];
      norm2 += v2[i] * v2[i];
    }
    if (norm1 <= 0 || norm2 <= 0) return 0.0;
    return dot / (sqrt(norm1) * sqrt(norm2));
  }
}

class _ChunkData {
  final String filePath;
  final Map<int, String> pageTextMap;
  _ChunkData({required this.filePath, required this.pageTextMap});
}

List<SemanticChunk> _chunkDocumentLogic(_ChunkData data) {
  const int vectorDim = 16;
  final List<SemanticChunk> chunks = [];

  for (final entry in data.pageTextMap.entries) {
    final page = entry.key;
    final text = entry.value;
    if (text.trim().isEmpty) continue;

    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    final buffer = StringBuffer();
    int sentCount = 0;

    for (final sentence in sentences) {
      buffer.write('$sentence ');
      sentCount++;

      if (sentCount >= 3 || buffer.length > 300) {
        final chunkText = buffer.toString().trim();
        if (chunkText.length > 20) {
          final vector = _generateEmbedding(chunkText, vectorDim);
          final keywords = _extractKeywords(chunkText);
          chunks.add(SemanticChunk(
            filePath: data.filePath,
            pageNumber: page,
            chunkText: chunkText,
            vectorData: vector,
            keywords: keywords,
          ));
        }
        buffer.clear();
        sentCount = 0;
      }
    }

    if (buffer.isNotEmpty) {
      final chunkText = buffer.toString().trim();
      if (chunkText.length > 20) {
        final vector = _generateEmbedding(chunkText, vectorDim);
        final keywords = _extractKeywords(chunkText);
        chunks.add(SemanticChunk(
          filePath: data.filePath,
          pageNumber: page,
          chunkText: chunkText,
          vectorData: vector,
          keywords: keywords,
        ));
      }
    }
  }

  return chunks;
}

List<double> _generateEmbedding(String text, int dim) {
  final clean = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
  final words = clean.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
  final vector = List<double>.filled(dim, 0.0);
  if (words.isEmpty) return vector;
  for (final w in words) {
    int hash = 0;
    for (int i = 0; i < w.length; i++) {
      hash = (hash * 31 + w.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    vector[hash % dim] += 1.0;
  }
  double norm = 0.0;
  for (final val in vector) {
    norm += val * val;
  }
  norm = sqrt(norm);
  if (norm > 0) {
    for (int i = 0; i < dim; i++) {
      vector[i] /= norm;
    }
  }
  return vector;
}

String _extractKeywords(String text) {
  final words = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').split(RegExp(r'\s+'));
  final freq = <String, int>{};
  for (final w in words) {
    if (w.length > 3) freq[w] = (freq[w] ?? 0) + 1;
  }
  final sorted = freq.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(5).map((e) => e.key).join(',');
}
