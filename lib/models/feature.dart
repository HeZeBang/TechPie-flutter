import 'package:flutter/material.dart';

import '../pages/oa_gym_page.dart';
import '../widgets/ios_liquid/ios_platform_view_page_transitions.dart';

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

  Feature({
    required this.id,
    required this.description,
    required this.mode,
    this.url,
    this.cookieType,
    required this.icon,
    this.nativeEntry,
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
    nativeEntry: (context) => pushPlatformViewPage<void>(
      context,
      builder: (_) => const OaGymPage(),
    ),
    icon: const Icon(Icons.sports_tennis),
  ),
];

final moreFeature = Feature(
  id: 'more',
  description: '更多',
  mode: FeatureMode.native,
  nativeEntry: (context) {},
  icon: const Icon(Icons.more_horiz),
);
