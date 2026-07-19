class UserSession {
  final String userId;
  final String userName;
  final String schoolName;
  final String phoneNumber;
  final String studentId;
  final DateTime createdAt;
  final String? geekpieToken;
  final String? geekpieExpiresAt;
  final String? geekpieRefreshToken;

  UserSession({
    required this.userId,
    required this.userName,
    required this.schoolName,
    this.phoneNumber = '',
    this.studentId = '',
    required this.createdAt,
    this.geekpieToken,
    this.geekpieExpiresAt,
    this.geekpieRefreshToken,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'schoolName': schoolName,
        'phoneNumber': phoneNumber,
        'studentId': studentId,
        'createdAt': createdAt.toIso8601String(),
        if (geekpieToken != null) 'geekpieToken': geekpieToken,
        if (geekpieExpiresAt != null) 'geekpieExpiresAt': geekpieExpiresAt,
        if (geekpieRefreshToken != null) 'geekpieRefreshToken': geekpieRefreshToken,
      };

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
        userId: json['userId'] as String? ?? '',
        userName: json['userName'] as String? ?? '',
        schoolName: json['schoolName'] as String? ?? '上海科技大学',
        phoneNumber: json['phoneNumber'] as String? ?? '',
        studentId:
            json['studentId'] as String? ?? json['openId'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        geekpieToken: json['geekpieToken'] as String?,
        geekpieExpiresAt: json['geekpieExpiresAt'] as String?,
        geekpieRefreshToken: json['geekpieRefreshToken'] as String?,
      );

  UserSession copyWith({
    String? userId,
    String? userName,
    String? schoolName,
    String? phoneNumber,
    String? studentId,
    DateTime? createdAt,
    String? geekpieToken,
    String? geekpieExpiresAt,
    String? geekpieRefreshToken,
  }) =>
      UserSession(
        userId: userId ?? this.userId,
        userName: userName ?? this.userName,
        schoolName: schoolName ?? this.schoolName,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        studentId: studentId ?? this.studentId,
        createdAt: createdAt ?? this.createdAt,
        geekpieToken: geekpieToken ?? this.geekpieToken,
        geekpieExpiresAt: geekpieExpiresAt ?? this.geekpieExpiresAt,
        geekpieRefreshToken: geekpieRefreshToken ?? this.geekpieRefreshToken,
      );
}
