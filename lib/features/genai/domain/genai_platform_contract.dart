import 'dart:convert';

import 'genai_contract.dart';
import 'genai_failure.dart';
import 'genai_image_size.dart';
import 'genai_reference_image.dart';

final class GenAiPageResult<T> {
  const GenAiPageResult(
    this.records, {
    required this.page,
    required this.hasMore,
  });
  final List<T> records;
  final int page;
  final bool hasMore;
}

GenAiPageResult<T> genAiPage<T>(
  Object? value,
  T Function(Map<String, dynamic>) decode, {
  required int page,
  required int pageSize,
}) {
  final Object? records;
  num? total;
  if (value is List) {
    records = value;
  } else {
    final json = genAiObject(value);
    records = json['records'];
    total = json['total'] is num ? json['total'] as num : null;
  }
  if (records is! List) throw const GenAiFailure(GenAiFailureKind.protocol);
  final items = <T>[];
  for (final Object? row in records) {
    try {
      items.add(decode(genAiObject(row)));
    } catch (_) {
      // Gracefully ignore corrupt records so one bad record does not break the entire list.
    }
  }
  return GenAiPageResult(
    List.unmodifiable(items),
    page: page,
    hasMore:
        total == null ? records.length >= pageSize : page * pageSize < total,
  );
}

String genAiOptionalText(Map<String, dynamic> json, String key) =>
    json[key] is String ? json[key] as String : '';

final class GenAiConversationSummary {
  const GenAiConversationSummary({
    required this.id,
    required this.title,
    this.time = '',
  });
  factory GenAiConversationSummary.fromJson(Map<String, dynamic> json) {
    final id = genAiOptionalText(json, 'chatGroupId').trim();
    if (id.isEmpty) {
      throw const GenAiFailure(GenAiFailureKind.protocol);
    }
    return GenAiConversationSummary(
      id: id,
      title: _displayTitle(genAiOptionalText(json, 'question')),
      time: genAiOptionalText(json, 'createTime'),
    );
  }
  // The upstream sometimes uses the latest tool-result message as its title.
  // Sanitize only an actual leading protocol frame, preserving quoted examples.
  static String _displayTitle(String title) =>
      RegExp(r'^<techpie-agent-(?:call|result|history)(?:\s|>)')
              .hasMatch(title.trimLeft())
          ? '校园工具对话'
          : title;

  final String id;
  final String title;
  final String time;
}

final class GenAiSavedTurn {
  const GenAiSavedTurn({
    required this.prompt,
    required this.answer,
    this.aiType = '',
    this.reasoning = '',
    this.imageUrls = const [],
    this.isHistoryGap = false,
  });
  factory GenAiSavedTurn.fromJson(Map<String, dynamic> json) {
    if ((json['question'] != null && json['question'] is! String) ||
        (json['answer'] != null && json['answer'] is! String) ||
        (json['question'] is! String && json['answer'] is! String)) {
      throw const GenAiFailure(GenAiFailureKind.protocol);
    }
    var answer = genAiOptionalText(json, 'answer').trim();
    final thoughts = <String>[];
    final leadingThought = RegExp(r'^<think>([\s\S]*?)</think>\s*');
    // Reasoning is a leading server envelope. Tags in prose, code examples or
    // JSON tool arguments are literal answer content and must remain intact.
    while (true) {
      final match = leadingThought.firstMatch(answer);
      if (match == null) break;
      thoughts.add(match.group(1)!.trim());
      answer = answer.substring(match.end);
    }
    return GenAiSavedTurn(
      prompt: genAiOptionalText(json, 'question'),
      answer: answer,
      reasoning: thoughts.join('\n'),
      aiType: genAiOptionalText(json, 'aiType'),
      imageUrls: _savedImageUrls(json),
    );
  }

  // The official client accepts an array, or comma-separated legacy imageUrl.
  // Invalid optional attachments must not discard the saved text turn.
  static List<String> _savedImageUrls(Map<String, dynamic> json) {
    List<String> decode(Iterable<Object?> values) {
      final urls = <String>{};
      for (final value in values) {
        if (value is! String) continue;
        try {
          urls.add(genAiImageUri(value).toString());
        } on GenAiFailure {
          continue;
        }
      }
      return List.unmodifiable(urls);
    }

    final multiple = json['imageUrls'];
    if (multiple is List) {
      final urls = decode(multiple);
      if (urls.isNotEmpty) return urls;
    }
    final single = json['imageUrl'];
    return single is String ? decode(single.split(',')) : const [];
  }

  /// Canonical CDN URLs, never local preview proxy URLs.
  final List<String> imageUrls;
  final String prompt;
  final String answer;
  final String aiType;
  final String reasoning;

  /// An unreadable server row stays in sequence so adjacent agent records
  /// cannot be joined across a missing step. It contains no model/user text.
  final bool isHistoryGap;
}

Uri genAiImageUri(String value, {String? baseOrigin}) {
  const host = 'genaipic.shanghaitech.edu.cn';
  final trimmed = value.trim();
  final path = Uri.tryParse(trimmed);
  if (path == null ||
      trimmed.isEmpty ||
      path.userInfo.isNotEmpty ||
      path.hasFragment ||
      path.hasQuery ||
      path.pathSegments.any((s) => s == '..' || s == '.')) {
    throw const GenAiFailure(GenAiFailureKind.protocol);
  }
  if (path.hasScheme || path.hasAuthority) {
    if (path.scheme != 'https' || path.host != host) {
      throw const GenAiFailure(GenAiFailureKind.protocol);
    }
    final imagePath = path.path.replaceFirst(RegExp(r'^/+'), '/');
    final clean = imagePath.startsWith('/sys/common/static/')
        ? imagePath.substring('/sys/common/static/'.length)
        : imagePath.replaceFirst(RegExp(r'^/'), '');
    if (baseOrigin != null && baseOrigin.isNotEmpty) {
      final baseUri = Uri.tryParse(baseOrigin);
      if (baseUri != null && baseUri.host != 'genai.shanghaitech.edu.cn') {
        return baseUri.replace(path: '/sys/common/static/$clean');
      }
    }
    return Uri.parse('https://$host/sys/common/static/$clean');
  }
  final clean = trimmed.startsWith('/sys/common/static/')
      ? trimmed.substring('/sys/common/static/'.length)
      : (trimmed.startsWith('/') ? trimmed.substring(1) : trimmed);
  if (baseOrigin != null && baseOrigin.isNotEmpty) {
    final baseUri = Uri.tryParse(baseOrigin);
    if (baseUri != null && baseUri.host != 'genai.shanghaitech.edu.cn') {
      return baseUri.replace(path: '/sys/common/static/$clean');
    }
  }
  return Uri.parse('https://$host/sys/common/static/$clean');
}

final class GenAiImageRecord {
  const GenAiImageRecord({
    required this.id,
    required this.prompt,
    required this.images,
  });
  factory GenAiImageRecord.fromJson(Map<String, dynamic> json) {
    final images = json['images'];
    if (images is! List) throw const GenAiFailure(GenAiFailureKind.protocol);
    return GenAiImageRecord(
      id: genAiRequiredString(json, 'id'),
      prompt: genAiOptionalText(json, 'question'),
      images: List.unmodifiable(
        images.map(
          (Object? row) => genAiImageUri(
            genAiRequiredString(genAiObject(row), 'imageUrl'),
          ),
        ),
      ),
    );
  }
  final String id;
  final String prompt;
  final List<Uri> images;
}

final class GenAiImageRequest {
  GenAiImageRequest({
    required this.prompt,
    required this.model,
    required this.groupId,
    this.size = '1024x1024',
    this.quality = 'low',
    List<GenAiReferenceImage> referenceImages = const [],
  }) : referenceImages = List.unmodifiable(referenceImages) {
    GenAiReferenceImage.validate(this.referenceImages);
    if (prompt.trim().isEmpty ||
        groupId.isEmpty ||
        !model.isImage ||
        !(GenAiImageSize.tryParse(size)?.isValid ?? false) ||
        !const ['low', 'medium', 'high'].contains(quality)) {
      throw ArgumentError('Invalid image request');
    }
  }

  static final supportedSizes = Set<String>.unmodifiable({
    for (final sizes in GenAiImageSize.presets.values) ...sizes.values,
    '1536x1024',
    '1024x1536',
  });

  final String prompt;
  final GenAiModel model;
  final String groupId;
  final String size;
  final String quality;
  final List<GenAiReferenceImage> referenceImages;
  Map<String, Object?> toJson() => {
        'chatInfo': prompt,
        'type': '3',
        'aiSecType': '1',
        'aiType': model.aiType,
        'rootAiType': model.rootAiType,
        'chatGroupId': groupId,
        'size': size,
        'quality': quality,
        'count': '1',
        'style': 'vivid',
        'outputFormat': 'png',
        'imageBase64':
            referenceImages.length == 1 ? referenceImages.single.dataUrl : null,
        'imageBase64List': referenceImages.length > 1
            ? [for (final image in referenceImages) image.dataUrl]
            : null,
        'outputCompression': null,
      };
}

num _number(Map<String, dynamic> json, String key) {
  final n = json[key];
  if (n is num && n.isFinite) return n;
  if (n is String) {
    final value = num.tryParse(n);
    if (value != null && value.isFinite) return value;
  }
  throw const GenAiFailure(GenAiFailureKind.protocol);
}

final class GenAiQuota {
  const GenAiQuota({
    required this.name,
    required this.total,
    required this.used,
    required this.remaining,
  });
  factory GenAiQuota.fromJson(String name, Map<String, dynamic> json) =>
      GenAiQuota(
        name: name,
        total: _number(json, 'total'),
        used: _number(json, 'used'),
        remaining: _number(json, 'remain'),
      );
  final String name;
  final num total;
  final num used;
  final num remaining;
}

final class GenAiUsageSummary {
  const GenAiUsageSummary(this.quotas);
  factory GenAiUsageSummary.fromJson(Map<String, dynamic> json) {
    final quotas = <GenAiQuota>[];
    for (final key in ['free', 'recharge']) {
      if (json[key] != null) {
        quotas.add(
          GenAiQuota.fromJson(
            key == 'free' ? '免费额度' : '充值额度',
            genAiObject(json[key]),
          ),
        );
      }
    }
    final projects = json['projects'];
    if (projects is List) {
      for (final item in projects) {
        final project = genAiObject(item);
        quotas.add(
          GenAiQuota.fromJson(genAiOptionalText(project, 'name'), project),
        );
      }
    }
    // Deliberately discard developer keys, including plaintext appKey fields.
    return GenAiUsageSummary(List.unmodifiable(quotas));
  }
  final List<GenAiQuota> quotas;
}

final class GenAiUsageOrder {
  const GenAiUsageOrder({
    required this.model,
    required this.time,
    required this.used,
    required this.inputTokens,
    required this.outputTokens,
    required this.imageTokens,
  });
  factory GenAiUsageOrder.fromJson(Map<String, dynamic> json) =>
      GenAiUsageOrder(
        model: genAiOptionalText(json, 'modelName').isEmpty
            ? genAiOptionalText(json, 'modelCode')
            : genAiOptionalText(json, 'modelName'),
        time: genAiOptionalText(json, 'orderTime'),
        used: _number(json, 'totalUsed'),
        inputTokens:
            json['inputTokens'] == null ? 0 : _number(json, 'inputTokens'),
        outputTokens:
            json['outputTokens'] == null ? 0 : _number(json, 'outputTokens'),
        imageTokens:
            json['imageTokens'] == null ? 0 : _number(json, 'imageTokens'),
      );
  final String model;
  final String time;
  final num used;
  final num inputTokens;
  final num outputTokens;
  final num imageTokens;
}

final class GenAiWebSearchCitation {
  const GenAiWebSearchCitation({
    required this.num,
    required this.title,
    required this.link,
    required this.snippet,
  });

  factory GenAiWebSearchCitation.fromJson(Map<String, dynamic> json) =>
      GenAiWebSearchCitation(
        num: json['num'] is int
            ? json['num'] as int
            : int.tryParse('${json['num']}') ?? 0,
        title: genAiOptionalText(json, 'title'),
        link: genAiOptionalText(json, 'link'),
        snippet: genAiOptionalText(json, 'snippet'),
      );

  final int num;
  final String title;
  final String link;
  final String snippet;
}

final class GenAiUploadedFile {
  const GenAiUploadedFile({
    required this.fileId,
    required this.fileName,
    this.content = '',
    this.chatGroupId = '',
  });

  factory GenAiUploadedFile.fromJson(Map<String, dynamic> json) =>
      GenAiUploadedFile(
        fileId: genAiRequiredString(json, 'fileId'),
        fileName: genAiOptionalText(json, 'fileName'),
        content: genAiOptionalText(json, 'content'),
        chatGroupId: genAiOptionalText(json, 'chatGroupId'),
      );

  final String fileId;
  final String fileName;
  final String content;
  final String chatGroupId;
}

final class GenAiUploadedImage {
  const GenAiUploadedImage({
    required this.url,
    this.width,
    this.height,
  });

  factory GenAiUploadedImage.fromJson(Map<String, dynamic> json) =>
      GenAiUploadedImage(
        url: genAiRequiredString(json, 'url'),
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
      );

  final String url;
  final int? width;
  final int? height;
}

final class GenAiAudioTranscription {
  const GenAiAudioTranscription(this.text);

  factory GenAiAudioTranscription.fromJson(Map<String, dynamic> json) {
    final raw = genAiOptionalText(json, 'transcription');
    if (raw.isEmpty) return const GenAiAudioTranscription('');
    try {
      final inner = jsonDecode(raw) as Map<String, dynamic>;
      final list = inner['transcription'] as List<dynamic>?;
      if (list != null && list.isNotEmpty) {
        final item = list.first as Map<String, dynamic>;
        return GenAiAudioTranscription(item['text'] as String? ?? '');
      }
    } catch (_) {}
    return GenAiAudioTranscription(raw);
  }

  final String text;
}
