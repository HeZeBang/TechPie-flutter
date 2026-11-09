import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'auth_service.dart';

class FeedbackService {
  FeedbackService(this._auth, this._baseUrl);

  final AuthService _auth;
  final String _baseUrl;

  Future<void> submit(String message) async {
    final text = message.trim();
    if (text.isEmpty || text.length > 2000) {
      throw Exception('请填写 1–2000 字的反馈内容');
    }
    final userId = _auth.session?.userId;
    if (userId == null || userId.isEmpty) throw Exception('请先登录 TechPie');
    final info = await PackageInfo.fromPlatform();
    await _auth.tryRenewSession();
    final session = _auth.session;
    final token = session?.geekpieToken;
    if (session?.userId != userId || token == null || token.isEmpty) {
      throw Exception('登录已变化，请重新登录后提交');
    }
    // Feedback is user-authored private text; keep it out of diagnostic logs.
    final response = await http
        .post(
          Uri.parse('$_baseUrl/feedback'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'message': text,
            'version': '${info.version}+${info.buildNumber}',
            'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode == 401) throw Exception('登录已失效，请重新登录');
    if (response.statusCode == 429) throw Exception('提交太频繁，请稍后再试');
    if (response.statusCode != 200 || jsonDecode(response.body)['success'] != true) {
      throw Exception('反馈未发送成功，请稍后再试');
    }
  }
}
