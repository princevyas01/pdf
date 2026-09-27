class StudySession {
  final int? id;
  final String filePath;
  final int startTime;
  final int endTime;
  final int durationSeconds;
  final int questionsAttempted;
  final int correctCount;
  final double accuracyPct;

  StudySession({
    this.id,
    required this.filePath,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.questionsAttempted,
    required this.correctCount,
    required this.accuracyPct,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'file_path': filePath,
      'start_time': startTime,
      'end_time': endTime,
      'duration_seconds': durationSeconds,
      'questions_attempted': questionsAttempted,
      'correct_count': correctCount,
      'accuracy_pct': accuracyPct,
    };
  }

  factory StudySession.fromMap(Map<String, dynamic> map) {
    return StudySession(
      id: (map['id'] as num?)?.toInt(),
      filePath: map['file_path'] as String? ?? '',
      startTime: (map['start_time'] as num?)?.toInt() ?? 0,
      endTime: (map['end_time'] as num?)?.toInt() ?? 0,
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      questionsAttempted: (map['questions_attempted'] as num?)?.toInt() ?? 0,
      correctCount: (map['correct_count'] as num?)?.toInt() ?? 0,
      accuracyPct: (map['accuracy_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class StudyAttempt {
  final int? id;
  final int sessionId;
  final int questionId;
  final String userAnswer;
  final bool isCorrect;
  final int timestamp;
  final String? topic;

  StudyAttempt({
    this.id,
    required this.sessionId,
    required this.questionId,
    required this.userAnswer,
    required this.isCorrect,
    required this.timestamp,
    this.topic,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'session_id': sessionId,
      'question_id': questionId,
      'user_answer': userAnswer,
      'is_correct': isCorrect ? 1 : 0,
      'timestamp': timestamp,
      'topic': topic,
    };
  }

  factory StudyAttempt.fromMap(Map<String, dynamic> map) {
    return StudyAttempt(
      id: (map['id'] as num?)?.toInt(),
      sessionId: (map['session_id'] as num?)?.toInt() ?? 0,
      questionId: (map['question_id'] as num?)?.toInt() ?? 0,
      userAnswer: map['user_answer'] as String? ?? '',
      isCorrect: map['is_correct'] == 1 || map['is_correct'] == true,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      topic: map['topic'] as String?,
    );
  }
}
