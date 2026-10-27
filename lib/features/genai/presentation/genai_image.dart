import 'package:flutter/material.dart';

import '../domain/genai_platform_contract.dart';
import 'genai_image_actions.dart';

/// Model text and tool output may only load campus images automatically.
/// A configured display resolver may route them through the preview proxy.
Uri? genAiAutomaticImageUri(
  String value, {
  Uri Function(String)? imageDisplayUri,
}) {
  try {
    final raw = Uri.parse(value.trim());
    if (raw.userInfo.isNotEmpty ||
        raw.hasQuery ||
        raw.hasFragment ||
        raw.pathSegments.any((part) => part == '..' || part == '.')) {
      return null;
    }
    var canonicalInput = value;
    if (raw.hasAuthority && raw.host != 'genaipic.shanghaitech.edu.cn') {
      if (imageDisplayUri == null) return null;
      final expected = imageDisplayUri(
        'https://genaipic.shanghaitech.edu.cn/sys/common/static/techpie-agent-origin-check.png',
      );
      // Some saved results already use the configured preview proxy. Accept
      // only its exact origin and static route before canonicalizing again.
      if ((raw.scheme != 'https' && raw.scheme != 'http') ||
          raw.origin != expected.origin ||
          !raw.path.startsWith('/sys/common/static/')) {
        return null;
      }
      canonicalInput = Uri(
        scheme: 'https',
        host: 'genaipic.shanghaitech.edu.cn',
        path: raw.path,
      ).toString();
    }
    final canonical = genAiImageUri(canonicalInput);
    return imageDisplayUri?.call(canonical.toString()) ?? canonical;
  } catch (_) {
    return null;
  }
}

/// Safe default for images embedded in both answers and reasoning Markdown.
class GenAiMarkdownImage extends StatelessWidget {
  const GenAiMarkdownImage({
    super.key,
    required this.uri,
    this.title,
    this.alt,
    this.imageDisplayUri,
  });

  final Uri uri;
  final String? title;
  final String? alt;
  final Uri Function(String)? imageDisplayUri;

  @override
  Widget build(BuildContext context) {
    final label =
        [alt, title].whereType<String>().where((value) => value.trim().isNotEmpty).firstOrNull;
    final display = genAiAutomaticImageUri(
      uri.toString(),
      imageDisplayUri: imageDisplayUri,
    );
    if (display == null) {
      return Text(
        label == null ? '外部图片未自动加载' : '外部图片未自动加载 · $label',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GenAiImageActions(
          image: NetworkImage(display.toString()),
          link: genAiImageUri(display.path),
          child: Image.network(
            display.toString(),
            fit: BoxFit.contain,
            semanticLabel: label,
            errorBuilder: (_, __, ___) => Text(label ?? '图片无法加载'),
          ),
        ),
      ),
    );
  }
}
