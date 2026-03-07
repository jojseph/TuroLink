import 'attachment.dart';

class ForumThread {
  final String id;
  final String classroomId;
  final String authorId;
  final String authorName;
  final String title;
  final String content;
  final DateTime createdAt;
  final int replyCount;
  final bool isPinned;
  final List<Attachment> attachments;

  ForumThread({
    required this.id,
    required this.classroomId,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.content,
    DateTime? createdAt,
    this.replyCount = 0,
    this.isPinned = false,
    List<Attachment>? attachments,
  })  : createdAt = createdAt ?? DateTime.now(),
        attachments = attachments ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'classroomId': classroomId,
      'authorId': authorId,
      'authorName': authorName,
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'replyCount': replyCount,
      'isPinned': isPinned ? 1 : 0,
    };
  }

  factory ForumThread.fromMap(Map<String, dynamic> map, {List<Attachment>? attachments}) {
    return ForumThread(
      id: map['id'] as String,
      classroomId: map['classroomId'] as String,
      authorId: map['authorId'] as String,
      authorName: map['authorName'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      replyCount: map['replyCount'] as int? ?? 0,
      isPinned: (map['isPinned'] as int? ?? 0) == 1,
      attachments: attachments,
    );
  }
}
