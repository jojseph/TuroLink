import 'attachment.dart';

class Submission {
  final String id;
  final String assignmentId;
  final String studentDeviceId;
  final String studentName;
  final String content;
  final DateTime submittedAt;
  final double? score;
  final bool isReturned;
  // Local only flag to track if teacher has received this submission
  // so we don't keep re-transmitting it endlessly.
  final bool isSynced;
  final List<Attachment> attachments;

  Submission({
    required this.id,
    required this.assignmentId,
    required this.studentDeviceId,
    required this.studentName,
    required this.content,
    DateTime? submittedAt,
    this.score,
    this.isReturned = false,
    this.isSynced = false,
    List<Attachment>? attachments,
  })  : submittedAt = submittedAt ?? DateTime.now(),
        attachments = attachments ?? [];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'assignmentId': assignmentId,
      'studentDeviceId': studentDeviceId,
      'studentName': studentName,
      'content': content,
      'submittedAt': submittedAt.toIso8601String(),
      'score': score,
      'isReturned': isReturned ? 1 : 0,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory Submission.fromMap(Map<String, dynamic> map,
      {List<Attachment>? attachments}) {
    return Submission(
      id: map['id'] as String,
      assignmentId: map['assignmentId'] as String,
      studentDeviceId: map['studentDeviceId'] as String,
      studentName: map['studentName'] as String,
      content: map['content'] as String,
      submittedAt: DateTime.parse(map['submittedAt'] as String),
      score: map['score'] as double?,
      isReturned: (map['isReturned'] as int) == 1,
      isSynced: (map['isSynced'] as int) == 1,
      attachments: attachments,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'assignmentId': assignmentId,
        'studentDeviceId': studentDeviceId,
        'studentName': studentName,
        'content': content,
        'submittedAt': submittedAt.toIso8601String(),
        'score': score,
        'isReturned': isReturned,
        // We usually don't transmit isSynced over network as it's a local state
        // but it doesn't hurt to include it.
        'attachments': attachments.map((a) => a.toJson()).toList(),
      };

  factory Submission.fromJson(Map<String, dynamic> json) {
    final attachmentsList = (json['attachments'] as List?)
            ?.map(
                (a) => Attachment.fromJson(Map<String, dynamic>.from(a as Map)))
            .toList() ??
        [];
    return Submission(
      id: json['id'] as String,
      assignmentId: json['assignmentId'] as String,
      studentDeviceId: json['studentDeviceId'] as String,
      studentName: json['studentName'] as String,
      content: json['content'] ?? '',
      submittedAt: DateTime.parse(json['submittedAt'] as String),
      score: json['score'] as double?,
      isReturned: json['isReturned'] == true,
      isSynced: json['isSynced'] == true,
      attachments: attachmentsList,
    );
  }

  /// Whether this submission has any file attachments
  bool get hasAttachments => attachments.isNotEmpty;
}
