class Classroom {
  final String id;
  final String name;
  final String password;
  final String teacherId;
  final String teacherName;
  final DateTime createdAt;

  Classroom({
    required this.id,
    required this.name,
    required this.password,
    required this.teacherId,
    required this.teacherName,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'password': password,
      'teacherId': teacherId,
      'teacherName': teacherName,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Classroom.fromMap(Map<String, dynamic> map) {
    return Classroom(
      id: map['id'] as String,
      name: map['name'] as String,
      password: map['password'] as String,
      teacherId: map['teacherId'] as String,
      teacherName: map['teacherName'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => toMap();

  factory Classroom.fromJson(Map<String, dynamic> json) =>
      Classroom.fromMap(json);
}
