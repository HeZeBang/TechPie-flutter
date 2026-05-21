import 'package:flutter/material.dart';

enum FeatureMode {
  native,
  webviewWithCookie,
}

enum CookieType {
  ids,
}

class Feature {
  final String id;
  final String description;
  final FeatureMode mode;
  final String? url;
  final String? mobileUrl;
  final CookieType? cookieType;
  final Icon icon;
  final void Function(BuildContext context)? nativeEntry;

  Feature({
    required this.id,
    required this.description,
    required this.mode,
    this.url,
    this.mobileUrl,
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
    url: 'https://ecourse.shanghaitech.edu.cn/',
    mobileUrl: 'https://ecourse.shanghaitech.edu.cn:8080/',
    cookieType: CookieType.ids,
    icon: Icon(Icons.cast_for_education),
  ),
  Feature(
    id: 'student_leave',
    description: '学生请假',
    mode: FeatureMode.webviewWithCookie,
    url: 'https://egate.shanghaitech.edu.cn/xsfw/sys/xsqjapp/*default/index.do',
    mobileUrl:
        'https://ids.shanghaitech.edu.cn/authserver/login?service=https://egate.shanghaitech.edu.cn/xsfw/sys/ydxsqjxs/index.html#/',
    cookieType: CookieType.ids,
    icon: Icon(Icons.door_front_door),
  ),
];

final moreFeature = Feature(
  id: 'more',
  description: '更多',
  mode: FeatureMode.native,
  nativeEntry: (context) {},
  icon: Icon(Icons.more_horiz),
);
