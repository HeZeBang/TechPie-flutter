import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../utils/platform.dart';
import 'adaptive_navigation_scaffold.dart';
import 'ios/ios_native_navigation_bar.dart';

/// A single setup task, with actions that scroll into reach on small displays.
class AdaptiveAccountSetup extends StatelessWidget {
  const AdaptiveAccountSetup({
    super.key,
    required this.title,
    required this.icon,
    required this.action,
    required this.onAction,
    required this.onBack,
    required this.backLabel,
    required this.children,
    this.description,
    this.error,
    this.disclosure,
    this.secondary,
    this.loading = false,
  });

  final String title;
  final IconData icon;
  final String action;
  final VoidCallback onAction;
  final VoidCallback onBack;
  final String backLabel;
  final List<Widget> children;
  final String? description;
  final String? error;
  final String? disclosure;
  final Widget? secondary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: '',
          leadingItems: [
            IosNativeNavigationBarItem(
              id: 'back',
              title: backLabel,
              sfSymbol: 'chevron.left',
              accessibilityLabel: backLabel,
              enabled: !loading,
            ),
          ],
          onItemPressed: (_) => onBack(),
        ),
        material: () => AppBar(
          backgroundColor: colors.canvas,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: backLabel,
            onPressed: loading ? null : onBack,
            icon: const Icon(TpIcons.chevronLeft),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 488),
            child: LayoutBuilder(
              builder: (context, bounds) => SingleChildScrollView(
                key: ValueKey(title),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  TpTokens.space5,
                  TpTokens.space6,
                  TpTokens.space5,
                  TpTokens.space4,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (bounds.maxHeight - TpTokens.space6 - TpTokens.space4)
                        .clamp(0.0, double.infinity),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: colors.brandSoft,
                                borderRadius: BorderRadius.circular(TpTokens.radiusM),
                              ),
                              child: Icon(icon, color: colors.brand, size: 24),
                            ),
                          ),
                          const SizedBox(height: TpTokens.space4),
                          Text(
                            title,
                            style: TpTypography.pageTitle(colors)
                                .copyWith(fontSize: 28, height: 36 / 28),
                          ),
                          if (description != null) ...[
                            const SizedBox(height: TpTokens.space4),
                            Text(
                              description!,
                              style: TpTypography.itemTitle(colors).copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.w400,
                                height: 25 / 17,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                          for (final child in children) ...[
                            const SizedBox(height: TpTokens.space4),
                            child,
                          ],
                          if (error != null) ...[
                            const SizedBox(height: TpTokens.space4),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                error!,
                                style: TpTypography.itemTitle(colors)
                                    .copyWith(color: colors.dangerRed),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: TpTokens.space5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (disclosure != null) ...[
                              Text(disclosure!,
                                  style: TpTypography.itemMeta(colors)
                                      .copyWith(fontSize: 14, height: 20 / 14),),
                              const SizedBox(height: TpTokens.space3),
                            ],
                            if (secondary != null) ...[
                              Align(alignment: AlignmentDirectional.centerStart, child: secondary!),
                              const SizedBox(height: TpTokens.space3),
                            ],
                            if (loading && isIos())
                              const Padding(
                                padding: EdgeInsets.only(bottom: TpTokens.space3),
                                child: Center(child: CircularProgressIndicator()),
                              ),
                            if (isIos())
                              SizedBox(
                                height: 52,
                                child: CNButton(
                                  label: action,
                                  semanticLabel: action,
                                  tint: colors.brand,
                                  enabled: !loading,
                                  onPressed: loading ? null : onAction,
                                  config: const CNButtonConfig(
                                    style: CNButtonStyle.filled,
                                    minHeight: 52,
                                    labelFontSize: 17,
                                  ),
                                ),
                              )
                            else
                              FilledButton(
                                onPressed: loading ? null : onAction,
                                style: FilledButton.styleFrom(
                                  backgroundColor: colors.brand,
                                  foregroundColor: colors.onBrand,
                                  minimumSize: const Size.fromHeight(52),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: TpTokens.space4,
                                    vertical: TpTokens.space3,
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                                child: loading
                                    ? SizedBox.square(
                                        dimension: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: colors.onBrand,
                                        ),
                                      )
                                    : Text(
                                        action,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontSize: 17, fontWeight: FontWeight.w600,),
                                      ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
