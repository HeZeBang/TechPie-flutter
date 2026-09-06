/// Deliberately contains no upstream body, cookie, URL or native error message.
enum ElrcErrorKind {
  forbidden,
  network,
  invalidResponse,
  unsafeAddress,
  noRecording,
  noPlayableSource,
  staleSession,
  playback,
}

class ElrcException implements Exception {
  const ElrcException(this.kind);
  final ElrcErrorKind kind;

  String get message => switch (kind) {
        ElrcErrorKind.forbidden => '此录播暂时无法匿名访问。',
        ElrcErrorKind.network => '暂时无法连接学校服务，请检查网络后重试。',
        ElrcErrorKind.invalidResponse => '学校返回的数据格式异常，请稍后重试。',
        ElrcErrorKind.unsafeAddress => '学校返回了暂不支持的播放地址，请联系项目组核对。',
        ElrcErrorKind.noRecording => '这节课暂时没有录播。',
        ElrcErrorKind.noPlayableSource => '这节课暂时没有可播放的机位。',
        ElrcErrorKind.staleSession => '录播已断开，请返回课程重新加载。',
        ElrcErrorKind.playback => '视频加载失败，请重新加载这节课。',
      };

  @override
  String toString() => 'ElrcException(${kind.name})';
}
