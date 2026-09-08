enum SessionFailureKind { unbound, expired, forbidden, temporary, changed }

class SessionFailure implements Exception {
  const SessionFailure(this.kind, this.message);

  final SessionFailureKind kind;
  final String message;

  bool get needsLogin =>
      kind == SessionFailureKind.unbound || kind == SessionFailureKind.expired;

  static const unavailable = SessionFailure(
    SessionFailureKind.temporary,
    '暂时无法连接校园服务，请稍后重试',
  );
  static const changed = SessionFailure(
    SessionFailureKind.changed,
    '校园账号已变更，请重新加载',
  );

  factory SessionFailure.fromStatus(int status) => switch (status) {
        401 =>
          const SessionFailure(SessionFailureKind.expired, '登录状态已失效，请重新登录'),
        403 => const SessionFailure(SessionFailureKind.forbidden, '当前账号没有访问权限'),
        429 =>
          const SessionFailure(SessionFailureKind.temporary, '请求过于频繁，请稍后重试'),
        504 =>
          const SessionFailure(SessionFailureKind.temporary, '校园服务响应超时，请稍后重试'),
        _ => unavailable,
      };

  @override
  String toString() => message;
}
