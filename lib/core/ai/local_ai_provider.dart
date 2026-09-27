import '../../models/study_item.dart';

class GroundedAnswer {
  final String answer;
  final List<int> sourcePages;
  final bool hasSufficientContext;

  GroundedAnswer({
    required this.answer,
    required this.sourcePages,
    required this.hasSufficientContext,
  });
}

enum ExplanationMode { simple, detailed, examFocused }

abstract class LocalAIProvider {
  Future<GroundedAnswer> answerQuestion({
    required String filePath,
    required String question,
    required Map<int, String> pageTextMap,
  });

  Future<String> explainText({
    required String selectedText,
    required String surroundingContext,
    required ExplanationMode mode,
  });

  Future<String> summarizeSection({
    required String text,
    required int startPage,
    required int endPage,
  });

  Future<List<StudyQuestion>> generateExamQuestions({
    required String filePath,
    required Map<int, String> pageTextMap,
    required String topic,
    required String difficulty,
    required int questionCount,
  });
}
