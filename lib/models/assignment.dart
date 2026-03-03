import 'attachment.dart';

class Assignment {
  final String id;
  final String classroomId;
  final String title;
  final String description;
  final DateTime? dueDate;
  final double? maxScore;
  final DateTime createdAt;
  final DateTime? scheduledDate;
  final List<Attachment> attachments;
  final String? type; // null = normal assignment, 'quiz' = quiz

  Assignment({
    required this.id,
    required this.classroomId,
    required this.title,
    required this.description,
    this.dueDate,
    this.maxScore,
    this.type,
    this.scheduledDate,
    DateTime? createdAt,
    List<Attachment>? attachments,
  })  : createdAt = createdAt ?? DateTime.now(),
        attachments = attachments ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'classroomId': classroomId,
      'title': title,
      'description': description,
      'dueDate': dueDate?.toIso8601String(),
      'maxScore': maxScore,
      'createdAt': createdAt.toIso8601String(),
      if (scheduledDate != null) 'scheduledDate': scheduledDate!.toIso8601String(),
      'type': type,
    };
  }

  factory Assignment.fromMap(Map<String, dynamic> map,
      {List<Attachment>? attachments}) {
    return Assignment(
      id: map['id'] as String,
      classroomId: map['classroomId'] as String,
      title: map['title'] as String,
      description: map['description'] as String,
      dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate']) : null,
      maxScore: map['maxScore'] as double?,
      scheduledDate: map['scheduledDate'] != null ? DateTime.parse(map['scheduledDate'] as String) : null,
      createdAt: DateTime.parse(map['createdAt'] as String),
      attachments: attachments,
      type: map['type'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        ...toMap(),
        'attachments': attachments.map((a) => a.toJson()).toList(),
      };

  factory Assignment.fromJson(Map<String, dynamic> json) {
    final attachmentsList = (json['attachments'] as List?)
            ?.map(
                (a) => Attachment.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList() ??
        [];
    return Assignment(
      id: json['id'] as String,
      classroomId: json['classroomId'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
      maxScore: json['maxScore'] as double?,
      scheduledDate: json['scheduledDate'] != null ? DateTime.parse(json['scheduledDate'] as String) : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      attachments: attachmentsList,
      type: json['type'] as String?,
    );
  }

  /// Whether this assignment has any file attachments
  bool get hasAttachments => attachments.isNotEmpty;
}
