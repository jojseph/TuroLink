class QuizItem {
  final String id;
  final String quizId;
  final String question;
  final List<String> choices;
  final int correctIndex;
  final int orderIndex;

  QuizItem({
    required this.id,
    required this.quizId,
    required this.question,
    required this.choices,
    required this.correctIndex,
    this.orderIndex = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'quizId': quizId,
      'question': question,
      'choices': choices.join('|||'),
      'correctIndex': correctIndex,
      'orderIndex': orderIndex,
    };
  }

  factory QuizItem.fromMap(Map<String, dynamic> map) {
    return QuizItem(
      id: map['id'] as String,
      quizId: map['quizId'] as String,
      question: map['question'] as String,
      choices: (map['choices'] as String).split('|||'),
      correctIndex: map['correctIndex'] as int,
      orderIndex: (map['orderIndex'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'quizId': quizId,
        'question': question,
        'choices': choices,
        'correctIndex': correctIndex,
        'orderIndex': orderIndex,
      };

  factory QuizItem.fromJson(Map<String, dynamic> json) {
    return QuizItem(
      id: json['id'] as String,
      quizId: json['quizId'] as String,
      question: json['question'] as String,
      choices: List<String>.from(json['choices'] as List),
      correctIndex: json['correctIndex'] as int,
      orderIndex: (json['orderIndex'] as int?) ?? 0,
    );
  }

  QuizItem copyWith({
    String? id,
    String? quizId,
    String? question,
    List<String>? choices,
    int? correctIndex,
    int? orderIndex,
  }) {
    return QuizItem(
      id: id ?? this.id,
      quizId: quizId ?? this.quizId,
      question: question ?? this.question,
      choices: choices ?? this.choices,
      correctIndex: correctIndex ?? this.correctIndex,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }
}

class Quiz {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final List<QuizItem> items;

  Quiz({
    required this.id,
    required this.title,
    this.description = '',
    DateTime? createdAt,
    List<QuizItem>? items,
  })  : createdAt = createdAt ?? DateTime.now(),
        items = items ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Quiz.fromMap(Map<String, dynamic> map, {List<QuizItem>? items}) {
    return Quiz(
      id: map['id'] as String,
      title: map['title'] as String,
      description: (map['description'] as String?) ?? '',
      createdAt: DateTime.parse(map['createdAt'] as String),
      items: items,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory Quiz.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List?)
            ?.map((i) => QuizItem.fromJson(Map<String, dynamic>.from(i as Map)))
            .toList() ??
        [];
    return Quiz(
      id: json['id'] as String,
      title: json['title'] as String,
      description: (json['description'] as String?) ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      items: itemsList,
    );
  }

  Quiz copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? createdAt,
    List<QuizItem>? items,
  }) {
    return Quiz(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      items: items ?? this.items,
    );
  }

  int get itemCount => items.length;
}
