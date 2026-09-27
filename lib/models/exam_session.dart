class ExamSession {
  final int? id;
  final String filePath;
  final String topic;
  final String difficulty;
  final int numQuestions;
  final double scorePct;
  final int durationSeconds;
  final int timestamp;

  ExamSession({
    this.id,
    required this.filePath,
    required this.topic,
    required this.difficulty,
    required this.numQuestions,
    required this.scorePct,
    required this.durationSeconds,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'file_path': filePath,
      'topic': topic,
      'difficulty': difficulty,
      'num_questions': numQuestions,
      'score_pct': scorePct,
      'duration_seconds': durationSeconds,
      'timestamp': timestamp,
    };
  }

  factory ExamSession.fromMap(Map<String, dynamic> map) {
    return ExamSession(
      id: (map['id'] as num?)?.toInt(),
      filePath: map['file_path'] as String? ?? '',
      topic: map['topic'] as String? ?? 'General',
      difficulty: map['difficulty'] as String? ?? 'Medium',
      numQuestions: (map['num_questions'] as num?)?.toInt() ?? 10,
      scorePct: (map['score_pct'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
    );
  }
}
