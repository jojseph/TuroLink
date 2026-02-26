class UserProfile {
  final String deviceId;
  final String displayName;
  final bool isTeacher;

  UserProfile({
    required this.deviceId,
    required this.displayName,
    required this.isTeacher,
  });

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'displayName': displayName,
      'isTeacher': isTeacher ? 1 : 0,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      deviceId: map['deviceId'] as String,
      displayName: map['displayName'] as String,
      isTeacher: (map['isTeacher'] as int) == 1,
    );
  }
}
