class Attachment {
  final String id;
  final String? postId;
  final String? assignmentId;
  final String? submissionId;
  final String fileName;
  final String fileType; // extension: pdf, jpg, png, mp3, mp4, csv, docx, ppt
  final String filePath; // local file path on device
  final int fileSize; // bytes

  Attachment({
    required this.id,
    this.postId,
    this.assignmentId,
    this.submissionId,
    required this.fileName,
    required this.fileType,
    required this.filePath,
    this.fileSize = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'postId': postId,
      'assignmentId': assignmentId,
      'submissionId': submissionId,
      'fileName': fileName,
      'fileType': fileType,
      'filePath': filePath,
      'fileSize': fileSize,
    };
  }

  factory Attachment.fromMap(Map<String, dynamic> map) {
    return Attachment(
      id: map['id'] as String,
      postId: map['postId'] as String?,
      assignmentId: map['assignmentId'] as String?,
      submissionId: map['submissionId'] as String?,
      fileName: map['fileName'] as String,
      fileType: map['fileType'] as String,
      filePath: map['filePath'] as String,
      fileSize: (map['fileSize'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => toMap();

  factory Attachment.fromJson(Map<String, dynamic> json) =>
      Attachment.fromMap(json);

  /// Returns a human-friendly file size string
  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Returns true if this is an image file
  bool get isImage => ['jpg', 'jpeg', 'png'].contains(fileType.toLowerCase());

  /// Returns true if this is an audio file
  bool get isAudio => ['mp3'].contains(fileType.toLowerCase());

  /// Returns true if this is a video file
  bool get isVideo => ['mp4'].contains(fileType.toLowerCase());

  /// Returns true if this is a document file
  bool get isDocument =>
      ['pdf', 'csv', 'docx', 'doc', 'ppt', 'pptx'].contains(fileType.toLowerCase());
}
