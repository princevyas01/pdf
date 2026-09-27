class StudyTopic {
  final int? id;
  final String filePath;
  final String title;
  final int startPage;
  final int endPage;
  final String? keywords;

  StudyTopic({
    this.id,
    required this.filePath,
    required this.title,
    required this.startPage,
    required this.endPage,
    this.keywords,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'file_path': filePath,
      'title': title,
      'start_page': startPage,
      'end_page': endPage,
      'keywords': keywords,
    };
  }

  factory StudyTopic.fromMap(Map<String, dynamic> map) {
    return StudyTopic(
      id: (map['id'] as num?)?.toInt(),
      filePath: map['file_path'] as String? ?? '',
      title: map['title'] as String? ?? '',
      startPage: (map['start_page'] as num?)?.toInt() ?? 1,
      endPage: (map['end_page'] as num?)?.toInt() ?? 1,
      keywords: map['keywords'] as String?,
    );
  }
}

class ImportantTerm {
  final String term;
  final String context;
  final int pageNumber;

  ImportantTerm({
    required this.term,
    required this.context,
    required this.pageNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      'term': term,
      'context': context,
      'page_number': pageNumber,
    };
  }

  factory ImportantTerm.fromMap(Map<String, dynamic> map) {
    return ImportantTerm(
      term: map['term'] as String? ?? '',
      context: map['context'] as String? ?? '',
      pageNumber: (map['page_number'] as num?)?.toInt() ?? 1,
    );
  }
}

class Flashcard {
  final int? id;
  final String filePath;
  final int pageNumber;
  final String front;
  final String back;
  final String? topic;
  final int status; // 0 = unstudied, 1 = known, 2 = difficult

  Flashcard({
    this.id,
    required this.filePath,
    required this.pageNumber,
    required this.front,
    required this.back,
    this.topic,
    this.status = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'file_path': filePath,
      'page_number': pageNumber,
      'front': front,
      'back': back,
      'topic': topic,
      'status': status,
    };
  }

  factory Flashcard.fromMap(Map<String, dynamic> map) {
    return Flashcard(
      id: (map['id'] as num?)?.toInt(),
      filePath: map['file_path'] as String? ?? '',
      pageNumber: (map['page_number'] as num?)?.toInt() ?? 1,
      front: map['front'] as String? ?? '',
      back: map['back'] as String? ?? '',
      topic: map['topic'] as String?,
      status: (map['status'] as num?)?.toInt() ?? 0,
    );
  }

  Flashcard copyWith({int? status}) {
    return Flashcard(
      id: id,
      filePath: filePath,
      pageNumber: pageNumber,
      front: front,
      back: back,
      topic: topic,
      status: status ?? this.status,
    );
  }
}

enum QuestionType { mcq, trueFalse, fillBlank, shortAnswer }

class StudyQuestion {
  final int? id;
  final String filePath;
  final int pageNumber;
  final QuestionType type;
  final String question;
  final List<String> options; // for MCQ
  final String correctAnswer;
  final String explanation;
  final int marks;
  final String? topic;

  StudyQuestion({
    this.id,
    required this.filePath,
    required this.pageNumber,
    required this.type,
    required this.question,
    this.options = const [],
    required this.correctAnswer,
    required this.explanation,
    this.marks = 1,
    this.topic,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'file_path': filePath,
      'page_number': pageNumber,
      'question_type': type.name,
      'question': question,
      'option_a': options.isNotEmpty ? options[0] : null,
      'option_b': options.length > 1 ? options[1] : null,
      'option_c': options.length > 2 ? options[2] : null,
      'option_d': options.length > 3 ? options[3] : null,
      'correct_answer': correctAnswer,
      'explanation': explanation,
      'marks': marks,
      'topic': topic,
    };
  }

  factory StudyQuestion.fromMap(Map<String, dynamic> map) {
    final opts = <String>[];
    if (map['option_a'] != null) opts.add(map['option_a'] as String);
    if (map['option_b'] != null) opts.add(map['option_b'] as String);
    if (map['option_c'] != null) opts.add(map['option_c'] as String);
    if (map['option_d'] != null) opts.add(map['option_d'] as String);

    final typeStr = map['question_type'] as String? ?? 'mcq';
    final type = QuestionType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => QuestionType.mcq,
    );

    return StudyQuestion(
      id: (map['id'] as num?)?.toInt(),
      filePath: map['file_path'] as String? ?? '',
      pageNumber: (map['page_number'] as num?)?.toInt() ?? 1,
      type: type,
      question: map['question'] as String? ?? '',
      options: opts,
      correctAnswer: map['correct_answer'] as String? ?? '',
      explanation: map['explanation'] as String? ?? '',
      marks: (map['marks'] as num?)?.toInt() ?? 1,
      topic: map['topic'] as String?,
    );
  }
}
