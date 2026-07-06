class UserSession {
  final String sessionToken;
  final String tgc;
  final String userId;
  final String userName;
  final String schoolName;
  final String tenantId;
  final String phoneNumber;
  final String cookies;
  final String studentId;
  final DateTime createdAt;
  final String? geekpieToken;
  final String? geekpieExpiresAt;

  UserSession({
    required this.sessionToken,
    required this.tgc,
    required this.userId,
    required this.userName,
    required this.schoolName,
    required this.tenantId,
    required this.phoneNumber,
    this.cookies = '',
    required this.studentId,
    required this.createdAt,
    this.geekpieToken,
    this.geekpieExpiresAt,
  });

  Map<String, dynamic> toJson() => {
        'sessionToken': sessionToken,
        'tgc': tgc,
        'userId': userId,
        'userName': userName,
        'schoolName': schoolName,
        'tenantId': tenantId,
        'phoneNumber': phoneNumber,
        'cookies': cookies,
        'studentId': studentId,
        'createdAt': createdAt.toIso8601String(),
        if (geekpieToken != null) 'geekpieToken': geekpieToken,
        if (geekpieExpiresAt != null) 'geekpieExpiresAt': geekpieExpiresAt,
      };

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
        sessionToken: json['sessionToken'] as String? ?? '',
        tgc: json['tgc'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        userName: json['userName'] as String? ?? '',
        schoolName: json['schoolName'] as String? ?? '',
        tenantId: json['tenantId'] as String? ?? '',
        phoneNumber: json['phoneNumber'] as String? ?? '',
        cookies: json['cookies'] as String? ?? '',
        studentId:
            json['studentId'] as String? ?? json['openId'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        geekpieToken: json['geekpieToken'] as String?,
        geekpieExpiresAt: json['geekpieExpiresAt'] as String?,
      );

  UserSession copyWith({
    String? sessionToken,
    String? tgc,
    String? userId,
    String? userName,
    String? schoolName,
    String? tenantId,
    String? phoneNumber,
    String? cookies,
    String? studentId,
    DateTime? createdAt,
    String? geekpieToken,
    String? geekpieExpiresAt,
  }) =>
      UserSession(
        sessionToken: sessionToken ?? this.sessionToken,
        tgc: tgc ?? this.tgc,
        userId: userId ?? this.userId,
        userName: userName ?? this.userName,
        schoolName: schoolName ?? this.schoolName,
        tenantId: tenantId ?? this.tenantId,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        cookies: cookies ?? this.cookies,
        createdAt: createdAt ?? this.createdAt,
        studentId: studentId ?? this.studentId,
        geekpieToken: geekpieToken ?? this.geekpieToken,
        geekpieExpiresAt: geekpieExpiresAt ?? this.geekpieExpiresAt,
      );
}
