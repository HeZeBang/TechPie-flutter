import 'dart:async';

import 'package:flutter/material.dart';

import '../models/ai_chat.dart';
import '../utils/platform.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';

/// A gallery of built-in prompt templates. Tapping one pops the page and
/// returns the chosen [AiPromptTemplate] to the chat page, which pre-fills it
/// into the composer.
class AiGalleryPage extends StatelessWidget {
  const AiGalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: '提示词画廊',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: 'Chat',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回对话',
                  placementGroup: 'leading-main',
                ),
              ],
              onItemPressed: (id) {
                if (id == 'back') unawaited(Navigator.maybePop(context));
              },
            )
          : const BlurredAppBar(title: Text('提示词画廊')),
      body: ListView.separated(
        padding: EdgeInsets.only(
          top: useIosChrome || useLegacyIosChrome
              ? 0
              : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top + 8,
          bottom: 16,
        ),
        itemCount: aiPromptGallery.length,
        separatorBuilder: (context, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, i) {
          final t = aiPromptGallery[i];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              child: Icon(t.icon),
            ),
            title: Text(t.title, style: theme.textTheme.titleSmall),
            subtitle: Text(
              t.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).pop<AiPromptTemplate>(t),
          );
        },
      ),
    );
  }
}
