import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../pages/ecard_wizard_copy.dart';
import '../theme/ecard_wizard_tokens.dart';
import '../theme/tp_tokens.dart';
import '../utils/platform.dart';
import 'ios/ios_native_navigation_bar.dart';
import 'wizard_card_face.dart';

/// Platform controls and presentation for the eCard setup flow.
class AdaptiveEcardWizard extends StatelessWidget {
  const AdaptiveEcardWizard({
    super.key,
    required this.title,
    required this.backLabel,
    required this.cardLabel,
    required this.onBack,
    required this.backEnabled,
    required this.controls,
    required this.showCard,
    required this.cardFirst,
    this.description,
    this.stateIcon,
    this.field,
    this.error,
    this.details,
    this.loading = false,
  });

  final String title;
  final String backLabel;
  final String cardLabel;
  final VoidCallback onBack;
  final bool backEnabled;
  final List<Widget> controls;
  final bool showCard;
  final bool cardFirst;
  final String? description;
  final IconData? stateIcon;
  final Widget? field;
  final String? error;
  final Widget? details;
  final bool loading;

  static ({String title, String description}) heading(WizardStep step, {required bool chinese}) =>
      wizardHeading(step, ios: isIos(), chinese: chinese);

  @override
  Widget build(BuildContext context) {
    final ios = isIos();
    final theme = Theme.of(context);
    final background = theme.brightness == Brightness.dark
        ? theme.colorScheme.surface
        : ios
            ? EcardWizardTokens.iosBackground
            : EcardWizardTokens.materialBackground;
    return Scaffold(
      backgroundColor: background,
      appBar: ios
          ? IosNativeNavigationBar(
              title: '',
              leadingItems: [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: backLabel,
                  sfSymbol: 'chevron.left',
                  enabled: backEnabled,
                  accessibilityLabel: backLabel,
                ),
              ],
              onItemPressed: (_) => onBack(),
            )
          : AppBar(
              backgroundColor: background,
              surfaceTintColor: Colors.transparent,
              toolbarHeight: 64,
              title: const Text('eCard'),
            ),
      body: SafeArea(
        top: false,
        child: loading ? const Center(child: CircularProgressIndicator()) : _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final ios = isIos();
    final artwork = Container(
      height: ios ? 206 : 236,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ios
            ? null
            : theme.brightness == Brightness.dark
                ? theme.colorScheme.surfaceContainerHigh
                : EcardWizardTokens.materialContainer,
        borderRadius: BorderRadius.circular(TpTokens.radiusL),
      ),
      child: Semantics(
        image: true,
        label: cardLabel,
        child: const ExcludeSemantics(child: WizardCardFace()),
      ),
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 800 && showCard;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (stateIcon != null) ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? theme.colorScheme.surfaceContainerHigh
                        : ios
                            ? EcardWizardTokens.iosContainer
                            : EcardWizardTokens.materialContainer,
                    borderRadius: BorderRadius.circular(EcardWizardTokens.stepIconRadius),
                  ),
                  child: Icon(stateIcon, size: 29),
                ),
              ),
              const SizedBox(height: 26),
            ],
            Text(
              title,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: ios ? 28 : 32,
                height: ios ? 34 / 28 : 1.25,
                fontWeight: ios ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: 9),
              Text(
                description!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: ios ? 17 : 16,
                  height: ios ? 25 / 17 : 1.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (field != null) ...[const SizedBox(height: 24), field!],
            if (error != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            ],
          ],
        );
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 948 : 488),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(24, ios ? 32 : 20, 24, 12),
                  sliver: SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: artwork),
                              const SizedBox(width: 40),
                              Expanded(child: text),
                            ],
                          )
                        else ...[
                          if (cardFirst) ...[artwork, const SizedBox(height: 26)],
                          text,
                          if (showCard && !cardFirst) ...[const SizedBox(height: 26), artwork],
                        ],
                        if (details != null) ...[const SizedBox(height: 18), details!],
                        const SizedBox(height: 24),
                        const Spacer(),
                        for (final control in controls)
                          Padding(padding: const EdgeInsets.only(bottom: 6), child: control),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AdaptiveEcardWizardButton extends StatelessWidget {
  const AdaptiveEcardWizardButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.buttonKey,
    this.primary = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final Key? buttonKey;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final ios = isIos();
    final enabled = onPressed;
    final color = Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.primary
        : ios
            ? EcardWizardTokens.iosAction
            : EcardWizardTokens.materialAction;
    if (ios) {
      return SizedBox(
        height: 52,
        child: CNButton(
          key: buttonKey,
          label: label,
          semanticLabel: label,
          enabled: enabled != null,
          onPressed: enabled,
          tint: color,
          config: CNButtonConfig(
            style: primary ? CNButtonStyle.filled : CNButtonStyle.plain,
            minHeight: 52,
            labelFontSize: 17,
            labelFontWeight: primary ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: primary
          ? FilledButton(
              key: buttonKey,
              onPressed: enabled,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: ThemeData.estimateBrightnessForColor(color) == Brightness.light
                    ? Colors.black
                    : Colors.white,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              child: Text(label),
            )
          : TextButton(key: buttonKey, onPressed: enabled, child: Text(label)),
    );
  }
}
