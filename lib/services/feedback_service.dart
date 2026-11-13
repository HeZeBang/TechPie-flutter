import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'auth_service.dart';

class FeedbackImage {
  FeedbackImage(this.bytes);
  final Uint8List bytes;
  bool uploading = false;
  bool failed = false;
  String? _userId;
  Map<String, dynamic>? _receipt;
  bool get uploaded => _receipt != null;
}

class FeedbackService {
  static const imageLimit = 4000000;
  FeedbackService(this._auth, this._baseUrl);

  final AuthService _auth;
  final String _baseUrl;

  Future<void> submit(
    String message, {
    bool includeUsername = false,
    bool includeEmail = false,
    String contact = '',
    List<FeedbackImage> images = const [],
    VoidCallback? onImageChanged,
  }) async {
    final text = message.trim();
    if (text.isEmpty || text.length > 2000) {
      throw Exception('请填写 1–2000 字的反馈内容');
    }
    if (contact.trim().length > 200) throw Exception('联系方式请勿超过 200 字');
    if (images.length > 9) throw Exception('最多添加 9 张图片');
    if (images.any((image) => image.bytes.isEmpty || image.bytes.length > imageLimit)) {
      throw Exception('每张图片需在 4 MB 以内且不能为空');
    }
    final userId = _userId();
    final info = await PackageInfo.fromPlatform();
    for (final image in images) {
      if (_auth.session?.userId != userId) throw Exception('登录已变化，请重新提交');
      await uploadImage(image, onChanged: onImageChanged);
    }
    final token = await _token(userId);
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
            'includeUsername': includeUsername,
            'includeEmail': includeEmail,
            'contact': contact.trim(),
            'images': images.map((image) => image._receipt).toList(),
          }),
        )
        .timeout(const Duration(seconds: 25));
    _result(response);
  }

  Future<void> uploadImage(FeedbackImage image, {VoidCallback? onChanged}) async {
    final userId = _userId();
    if (image._userId == userId && image.uploaded) return;
    if (image.bytes.isEmpty || image.bytes.length > imageLimit) {
      throw Exception('每张图片需在 4 MB 以内且不能为空');
    }
    image._receipt = null;
    image.failed = false;
    image.uploading = true;
    onChanged?.call();
    try {
      final token = await _token(userId);
      final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/feedback/images'))
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes('image', image.bytes, filename: 'feedback-image'));
      final response =
          await request.send().then(http.Response.fromStream).timeout(const Duration(seconds: 35));
      final receipt = _result(response)['data'] as Map<String, dynamic>;
      if (_auth.session?.userId != userId) throw Exception('登录已变化，请重新提交');
      image._userId = userId;
      image._receipt = receipt;
    } catch (_) {
      image.failed = true;
      rethrow;
    } finally {
      image.uploading = false;
      onChanged?.call();
    }
  }

  String _userId() {
    final userId = _auth.session?.userId;
    if (userId == null || userId.isEmpty) throw Exception('请先登录 TechPie');
    return userId;
  }

  Future<String> _token(String userId) async {
    await _auth.tryRenewSession();
    final session = _auth.session;
    final token = session?.geekpieToken;
    if (session?.userId != userId || token == null || token.isEmpty) {
      throw Exception('登录已变化，请重新登录后提交');
    }
    return token;
  }

  Map<String, dynamic> _result(http.Response response) {
    if (response.statusCode == 413) throw Exception('每张图片请勿超过 4 MB');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || body['success'] != true) {
      throw Exception(body['error'] as String? ?? '反馈未发送成功，请稍后再试');
    }
    return body;
  }
}
