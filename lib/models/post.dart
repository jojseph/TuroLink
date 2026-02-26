import 'attachment.dart';

class Post {
  final String id;
  final String classroomId;
  final String content;
  final DateTime createdAt;
  final List<Attachment> attachments;

  Post({
    required this.id,
    required this.classroomId,
    required this.content,
    DateTime? createdAt,
    List<Attachment>? attachments,
  })  : createdAt = createdAt ?? DateTime.now(),
        attachments = attachments ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'classroomId': classroomId,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Post.fromMap(Map<String, dynamic> map,
      {List<Attachment>? attachments}) {
    return Post(
      id: map['id'] as String,
      classroomId: map['classroomId'] as String,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      attachments: attachments,
    );
  }

  Map<String, dynamic> toJson() => {
        ...toMap(),
        'attachments': attachments.map((a) => a.toJson()).toList(),
      };

  factory Post.fromJson(Map<String, dynamic> json) {
    final attachmentsList = (json['attachments'] as List?)
            ?.map(
                (a) => Attachment.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList() ??
        [];
    return Post(
      id: json['id'] as String,
      classroomId: json['classroomId'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      attachments: attachmentsList,
    );
  }

  /// Whether this post has any file attachments
  bool get hasAttachments => attachments.isNotEmpty;
}
