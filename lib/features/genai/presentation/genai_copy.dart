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
    };
