import 'package:flutter/material.dart';

import '../pages/ai_assistant_page.dart';
import '../pages/ai_demo/ai_demo_page.dart';
import '../pages/oa_gym_page.dart';

enum FeatureMode {
  native,
  webviewWithCookie,
}

enum CookieType {
  ecourse,
  egate,
  eams,
}

class Feature {
  final String id;
  final String description;
  final FeatureMode mode;
  final String? url;
  final CookieType? cookieType;
  final Icon icon;
  final void Function(BuildContext context)? nativeEntry;

  /// Only shown when the debug-mode setting is on.
  final bool debugOnly;

  Feature({
    required this.id,
    required this.description,
    required this.mode,
    this.url,
    this.cookieType,
    required this.icon,
    this.nativeEntry,
    this.debugOnly = false,
  });
}

final featureEntries = <Feature>[
  Feature(
    id: 'ecourse',
    description: 'E云课堂',
    mode: FeatureMode.webviewWithCookie,
    url: 'https://ecourse.shanghaitech.edu.cn:8080/',
    cookieType: CookieType.ecourse,
    icon: const Icon(Icons.cast_for_education),
  ),
  Feature(
    id: 'student_leave',
    description: '学生请假',
    mode: FeatureMode.webviewWithCookie,
    url: 'https://egate.shanghaitech.edu.cn/xsfw/sys/xsqjapp/*default/index.do',
    cookieType: CookieType.egate,
    icon: const Icon(Icons.door_front_door),
  ),
  Feature(
    id: 'oa_gym',
    description: '场馆预约',
    mode: FeatureMode.native,
    nativeEntry: (context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const OaGymPage()),
    ),
    icon: const Icon(Icons.sports_tennis),
  ),
  Feature(
    id: 'ai_assistant',
    description: 'AI 助手',
    mode: FeatureMode.native,
    nativeEntry: (context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AiAssistantPage()),
    ),
    icon: const Icon(Icons.smart_toy_outlined),
  ),
  Feature(
    id: 'ai_demo',
    description: 'AI 演示',
    mode: FeatureMode.native,
    debugOnly: true,
    nativeEntry: (context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AiDemoPage()),
    ),
    icon: const Icon(Icons.auto_awesome),
  ),
];

final moreFeature = Feature(
  id: 'more',
  description: '更多',
  mode: FeatureMode.native,
  nativeEntry: (context) {},
  icon: const Icon(Icons.more_horiz),
);
