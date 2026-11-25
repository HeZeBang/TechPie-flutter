enum CampusErrorKind {
  notLoggedIn,
  idsNotBound,
  sessionExpired,
  rateLimited,
  notOpen,
  network,
  parseFailed,
  forbidden,
  notFound,
  rejected,
}

class CampusRequestException implements Exception {
  const CampusRequestException(this.kind, this.message);
  final CampusErrorKind kind;
  final String message;

  static const expired = CampusRequestException(CampusErrorKind.sessionExpired, '校园登录态已失效');
  static const invalid = CampusRequestException(CampusErrorKind.parseFailed, '校园服务返回的数据格式有变');
  @override
  String toString() => message;
}
