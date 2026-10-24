import 'package:intl/intl.dart';

import '../domain/genai_failure.dart';

String genAiFailureText(GenAiFailure failure) => switch (failure.kind) {
      GenAiFailureKind.authenticationRequired => '登录已过期，请重新连接 GenAI。',
      GenAiFailureKind.identityMismatch =>
        'GenAI 账号与当前绑定的校园账号不一致，请使用对应的学校账号登录。',
      GenAiFailureKind.accountChanged => '账号已切换，请重新开始对话。',
      GenAiFailureKind.cancelled => '已停止生成。',
      GenAiFailureKind.timeout => '连接超时，请重试。',
      GenAiFailureKind.transport => '无法连接校园 GenAI，请检查网络后重试。',
      GenAiFailureKind.protocol => '平台返回的数据暂不兼容，请稍后重试。',
      GenAiFailureKind.rejected => '平台未接受本次请求，请检查账号权限或稍后重试。',
      GenAiFailureKind.interrupted => '连接已中断，已保留收到的内容。',
      GenAiFailureKind.storage => '无法访问安全存储，请重试。',
      GenAiFailureKind.busy => '请等待当前回复完成，或先停止生成。',
      GenAiFailureKind.messageTooLarge => '本条消息过长，请拆分发送；已有对话已保留。',
      GenAiFailureKind.contextTooLarge => '上下文或附件超过安全容量，请缩小附件或问题范围；完整历史已保留。',
      GenAiFailureKind.attachmentContextUnknown =>
        '旧附件缺少本地文本，无法确认上下文大小。请重新上传附件并开始新对话。',
    };

/// Keep server timestamps readable and consistent in both history views.
String genAiHistoryTime(String value) {
  final timestamp = DateTime.tryParse(value);
  return timestamp == null
      ? value
      : DateFormat('yyyy/MM/dd HH:mm').format(timestamp.toLocal());
}
