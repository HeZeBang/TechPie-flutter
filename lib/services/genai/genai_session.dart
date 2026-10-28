class GenaiSession {
  const GenaiSession({
    required this.account,
    required this.password,
    required this.token,
    required this.expiresAt,
  });

  final String account;
  final String password;
  final String token;
  final DateTime expiresAt;

  Map<String, Object> toJson() => {
        'account': account,
        'password': password,
        'token': token,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
      };

  factory GenaiSession.fromJson(Map<String, dynamic> json) {
    final account = json['account'];
    final password = json['password'];
    final token = json['token'];
    final expiresAt = json['expiresAt'];
    if (account is! String ||
        account.isEmpty ||
        password is! String ||
        password.isEmpty ||
        token is! String ||
        token.isEmpty ||
        expiresAt is! int) {
      throw const FormatException('请重新登录 GenAI');
    }
    return GenaiSession(
      account: account,
      password: password,
      token: token,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true),
    );
  }
}
