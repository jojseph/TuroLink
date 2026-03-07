import 'attachment.dart';

class ForumReply {
  final String id;
  final String threadId;
  final String authorId;
  final String authorName;
  final String content;
  final DateTime createdAt;
  final bool isTeacher;
  final List<Attachment> attachments;

  ForumReply({
    required this.id,
    required this.threadId,
    required this.authorId,
    required this.authorName,
    required this.content,
    DateTime? createdAt,
    this.isTeacher = false,
    List<Attachment>? attachments,
  })  : createdAt = createdAt ?? DateTime.now(),
        attachments = attachments ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'threadId': threadId,
      'authorId': authorId,
      'authorName': authorName,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'isTeacher': isTeacher ? 1 : 0,
    };
  }

  factory ForumReply.fromMap(Map<String, dynamic> map, {List<Attachment>? attachments}) {
    return ForumReply(
      id: map['id'] as String,
      threadId: map['threadId'] as String,
      authorId: map['authorId'] as String,
      authorName: map['authorName'] as String,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      isTeacher: (map['isTeacher'] as int? ?? 0) == 1,
      attachments: attachments,
    );
  }
}
