import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/platform.dart';

import 'genai_icons.dart';

/// Keep TechPie's palette, typography and component styles as the source of
/// truth, including dynamic colors, platform styling and AMOLED surfaces.
/// The workspace only adds a compact, outlined treatment for the few Material
/// controls it embeds, and delays incidental hover help in the densely
/// interactive chat.
///
/// Every value is derived from [base]'s [ColorScheme] or [GenAiPalette], so the
/// result follows TechPie's light/dark, AMOLED, dynamic-color and iOS-accent
/// settings. Because nothing here rewrites the scheme, the text theme or the
/// scaffold color the palette is read from, applying this to an already-themed
/// [ThemeData] produces the same result again.
ThemeData genAiTheme(ThemeData base) {
  final scheme = base.colorScheme;
  final palette = GenAiPalette._(base);
  final textTheme = base.textTheme;

  const menuShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)));
  const controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10)));
  const fieldRadius = BorderRadius.all(Radius.circular(9));
  const controlPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 10);

  final disabledBackground = scheme.onSurface.withValues(alpha: .12);
  final disabledForeground = scheme.onSurface.withValues(alpha: .38);

  OutlineInputBorder fieldBorder(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: fieldRadius,
    borderSide: BorderSide(color: color, width: width),
  );

  WidgetStateProperty<Color?> buttonBackground(Color normal) =>
      WidgetStateProperty.resolveWith<Color?>(
        (states) => states.contains(WidgetState.disabled) ? disabledBackground : normal,
      );

  WidgetStateProperty<Color?> buttonForeground(Color normal) =>
      WidgetStateProperty.resolveWith<Color?>(
        (states) => states.contains(WidgetState.disabled) ? disabledForeground : normal,
      );

  final inputDecoration = InputDecorationTheme(
    isDense: true,
    filled: true,
    fillColor: palette.raised,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    hintStyle: textTheme.bodyMedium?.copyWith(color: palette.muted),
    labelStyle: textTheme.bodyMedium?.copyWith(color: palette.muted),
    floatingLabelStyle: textTheme.bodyMedium?.copyWith(color: palette.accent),
    iconColor: palette.muted,
    prefixIconColor: palette.muted,
    suffixIconColor: palette.muted,
    border: fieldBorder(palette.line),
    enabledBorder: fieldBorder(palette.line),
    disabledBorder: fieldBorder(palette.line.withValues(alpha: .5)),
    focusedBorder: fieldBorder(palette.accent, 1.5),
    errorBorder: fieldBorder(scheme.error),
    focusedErrorBorder: fieldBorder(scheme.error, 1.5),
  );

  final textButtonStyle = ButtonStyle(
    foregroundColor: buttonForeground(palette.accent),
    overlayColor: WidgetStatePropertyAll(palette.hover),
    padding: const WidgetStatePropertyAll(controlPadding),
    shape: const WidgetStatePropertyAll(controlShape),
    textStyle: WidgetStatePropertyAll(textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
  );
  final filledButtonStyle = textButtonStyle.copyWith(
    backgroundColor: buttonBackground(palette.accent),
    foregroundColor: buttonForeground(palette.onAccent),
  );
  final outlinedButtonStyle = textButtonStyle.copyWith(
    side: WidgetStateProperty.resolveWith<BorderSide?>(
      (states) => BorderSide(
        color: states.contains(WidgetState.disabled)
            ? palette.line.withValues(alpha: .5)
            : palette.line,
      ),
    ),
  );

  final iconButtonStyle = ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith<Color?>(
      (states) => states.contains(WidgetState.disabled) ? disabledForeground : palette.muted,
    ),
    overlayColor: WidgetStatePropertyAll(palette.hover),
    iconSize: const WidgetStatePropertyAll(20),
    shape: const WidgetStatePropertyAll(controlShape),
  );

  final menuStyle = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(palette.raised),
    elevation: const WidgetStatePropertyAll(3),
    shape: const WidgetStatePropertyAll(menuShape),
    side: WidgetStatePropertyAll(BorderSide(color: palette.line)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
  );

  final menuButtonStyle = ButtonStyle(
    foregroundColor: WidgetStatePropertyAll(palette.text),
    overlayColor: WidgetStatePropertyAll(palette.hover),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
    shape: const WidgetStatePropertyAll(menuShape),
    textStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
  );

  return base.copyWith(
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: palette.accent.withValues(alpha: .22),
      cursorColor: palette.accent,
      selectionHandleColor: palette.accent,
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      waitDuration: const Duration(milliseconds: 700),
      showDuration: const Duration(seconds: 2),
    ),
    filledButtonTheme: FilledButtonThemeData(style: filledButtonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: outlinedButtonStyle),
    textButtonTheme: TextButtonThemeData(style: textButtonStyle),
    iconButtonTheme: IconButtonThemeData(style: iconButtonStyle),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.raised,
      surfaceTintColor: palette.raised,
      shadowColor: scheme.shadow,
      elevation: 3,
      shape: menuShape,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      textStyle: textTheme.bodyMedium?.copyWith(color: palette.text),
      iconColor: palette.muted,
      iconSize: 20,
    ),
    menuTheme: MenuThemeData(style: menuStyle),
    menuButtonTheme: MenuButtonThemeData(style: menuButtonStyle),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.raised,
      surfaceTintColor: palette.raised,
      shadowColor: scheme.shadow,
      elevation: 6,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
      iconColor: palette.muted,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        color: palette.text,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: palette.muted),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.raised,
      modalBackgroundColor: palette.raised,
      surfaceTintColor: palette.raised,
      shadowColor: scheme.shadow,
      elevation: 3,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      showDragHandle: true,
      dragHandleColor: palette.muted,
    ),
    inputDecorationTheme: inputDecoration,
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: textTheme.bodyMedium?.copyWith(color: palette.text),
      inputDecorationTheme: inputDecoration,
      menuStyle: menuStyle,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.soft,
      selectedColor: palette.accentSoft,
      disabledColor: disabledBackground,
      checkmarkColor: palette.accent,
      showCheckmark: true,
      labelStyle: textTheme.labelMedium?.copyWith(color: palette.text),
      secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: palette.accent),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      side: BorderSide(color: palette.line),
      shape: const StadiumBorder(),
      brightness: base.brightness,
      elevation: 0,
      pressElevation: 0,
      surfaceTintColor: palette.raised,
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      selectedColor: palette.accent,
      selectedTileColor: palette.accentSoft,
      iconColor: palette.muted,
      textColor: palette.text,
      titleTextStyle: textTheme.titleSmall?.copyWith(color: palette.text),
      subtitleTextStyle: textTheme.bodySmall?.copyWith(color: palette.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      horizontalTitleGap: 12,
      minVerticalPadding: 6,
      minTileHeight: 44,
      enableFeedback: true,
    ),
    dividerTheme: DividerThemeData(color: palette.line, space: 1, thickness: 1),
  );
}

/// Applies the GenAI component theme at an overlay route boundary.
///
/// Dialog and sheet routes capture themes from their launch context, which may
/// be above a widget's local workspace theme. Reapplying the same derived theme
/// in the route builder keeps those overlays consistent without changing the
/// host app's theme.
Widget genAiThemeScope(BuildContext context, Widget child) =>
    Theme(data: genAiTheme(Theme.of(context)), child: child);

/// Shared draft scrim: drawers are lighter than dialogs and modal sheets.
Color genAiOverlayScrim({bool drawer = false}) =>
    drawer ? const Color(0x55121015) : const Color(0x66121015);

/// Opens a standard Material dialog with the shared GenAI theme and scrim.
Future<T?> genAiShowDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push<T>(
    DialogRoute<T>(
      context: context,
      builder: (context) => genAiThemeScope(context, builder(context)),
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierColor: genAiOverlayScrim(),
      barrierDismissible: barrierDismissible,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    ),
  );
}

/// Draft dialog chrome shared by confirmation and form dialogs. The route owns
/// dismissal policy; the close affordance returns the same null result as Escape.
class GenAiDialogFrame extends StatelessWidget {
  const GenAiDialogFrame({
    super.key,
    required this.title,
    this.content,
    this.actions,
    this.insetPadding,
    this.shape,
    this.contentPadding,
    this.actionsPadding,
    this.constraints,
    this.scrollable = false,
    this.surfaceKey,
    this.headerKey,
  });

  final Widget title;
  final Widget? content;
  final List<Widget>? actions;
  final EdgeInsets? insetPadding;
  final ShapeBorder? shape;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? actionsPadding;
  final BoxConstraints? constraints;
  final bool scrollable;
  final Key? surfaceKey;
  final Key? headerKey;

  @override
  Widget build(BuildContext context) {
    final palette = GenAiPalette.of(context);
    final compact = MediaQuery.sizeOf(context).width <= 600;
    final body = content == null
        ? null
        : Padding(
            padding: contentPadding ?? EdgeInsets.all(compact ? 18 : 24),
            child: DefaultTextStyle.merge(
              style: TextStyle(fontSize: 13, height: 1.75, color: palette.muted),
              child: content!,
            ),
          );
    return Dialog(
      insetPadding: insetPadding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape:
          shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 14 : 18)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        key: surfaceKey,
        constraints: constraints ?? const BoxConstraints.tightFor(width: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              key: headerKey,
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 15)
                  : const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              child: Row(
                children: [
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                      child: title,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: '关闭',
                    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: () => Navigator.pop(context),
                    icon: GenAiIcon(GenAiGlyph.close, size: 18, color: palette.muted),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: palette.line),
            if (body != null)
              Flexible(child: scrollable ? SingleChildScrollView(child: body) : body),
            if (actions?.isNotEmpty ?? false)
              Padding(
                padding:
                    actionsPadding ??
                    (compact
                        ? const EdgeInsets.fromLTRB(18, 0, 18, 18)
                        : const EdgeInsets.fromLTRB(24, 0, 24, 22)),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 9,
                  overflowSpacing: 9,
                  children: actions!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Layout decisions use the space available to the feature, including short
/// landscape windows. These are presentation rules, never platform capabilities.
class GenAiLayout {
  /// Hover-only actions must remain visible on touch platforms, including OHOS.
  static bool get touchPlatform =>
      isOhos() ||
      switch (defaultTargetPlatform) {
        TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
        _ => false,
      };

  const GenAiLayout(this.size);

  factory GenAiLayout.of(BuildContext context) => GenAiLayout(MediaQuery.sizeOf(context));

  final Size size;
  bool get narrow => size.width <= 680;
  bool get short => size.height < 560;
  bool get compactControls => narrow || short;
}

/// A compact command row shared by anchored menus and phone sheets.
PopupMenuItem<T> genAiActionItem<T>(
  GenAiPalette palette,
  T? value,
  Widget icon,
  String label, {
  Key? key,
  bool enabled = true,
  bool danger = false,
  Widget? trailing,
}) => PopupMenuItem<T>(
  key: key,
  value: value,
  enabled: enabled,
  height: 42,
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  child: Row(
    children: [
      IconTheme.merge(
        data: IconThemeData(
          size: 17,
          color: enabled ? palette.muted : palette.muted.withValues(alpha: .4),
        ),
        child: icon,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: !enabled
                ? palette.muted.withValues(alpha: .5)
                : danger
                ? palette.accent
                : palette.text,
          ),
        ),
      ),
      if (trailing != null) trailing,
    ],
  ),
);

/// Short menus stay by their trigger. Longer lists use a sheet on phones.
/// Both return the same value and support dismissal without changing selection.
Future<T?> genAiShowMenu<T>({
  required BuildContext context,
  required BuildContext anchorContext,
  required List<PopupMenuEntry<T>> items,
  double minWidth = 220,
  String? semanticLabel,
  bool preferAbove = false,
  bool alignEnd = false,
  bool pointerMenu = false,
  Offset? pressPosition,
  double gap = 7,
  double menuPadding = 6,
  double radius = 12,
}) {
  final layout = GenAiLayout.of(context);
  final compact = layout.narrow || GenAiLayout.touchPlatform && layout.short;
  final menuHeight = items.fold<double>(menuPadding * 2, (height, item) => height + item.height);
  if (!compact || pointerMenu || menuHeight <= 300) {
    return genAiShowAnchoredMenu<T>(
      context: context,
      anchorContext: anchorContext,
      items: items,
      pressPosition: pressPosition,
      minWidth: minWidth,
      semanticLabel: semanticLabel,
      preferAbove: preferAbove,
      alignEnd: alignEnd,
      gap: gap,
      menuPadding: menuPadding,
      radius: radius,
    );
  }
  return genAiShowModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      final media = MediaQuery.of(context);
      return Padding(
        padding: media.viewInsets,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  (media.size.height - media.padding.vertical - media.viewInsets.vertical).clamp(
                    0.0,
                    double.infinity,
                  ) *
                  .8,
            ),
            child: Semantics(
              key: const ValueKey('genai-choice-sheet'),
              role: ui.SemanticsRole.menu,
              explicitChildNodes: true,
              label: semanticLabel ?? '选项',
              child: _GenAiMenuInteraction(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: items.map(genAiMenuEntry).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Shared chrome for rich answers. Actions stay reachable at narrow widths;
/// a foldable title exposes its expanded state to assistive technology.
class GenAiContentHeader extends StatelessWidget {
  const GenAiContentHeader({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
    this.expanded,
    this.onToggle,
    this.divider = true,
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;
  final bool? expanded;
  final VoidCallback? onToggle;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final palette = GenAiPalette.of(context);
    final label = Row(
      children: [
        if (onToggle != null)
          GenAiIcon(expanded == true ? GenAiGlyph.down : GenAiGlyph.chevron, size: 15)
        else if (leading != null)
          leading!,
        if (onToggle != null || leading != null) const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: palette.text),
          ),
        ),
      ],
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.line)),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              expanded: expanded,
              child: onToggle == null
                  ? Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: label)
                  : TextButton(
                      onPressed: onToggle,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        alignment: Alignment.centerLeft,
                      ),
                      child: label,
                    ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// The sheet counterpart of [genAiShowDialog], sharing its barrier treatment.
Future<T?> genAiShowModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool? showDragHandle,
  bool useSafeArea = false,
}) async {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final localizations = MaterialLocalizations.of(context);
  final route = ModalBottomSheetRoute<T>(
    builder: (context) => genAiThemeScope(context, builder(context)),
    capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(localizations.bottomSheetLabel),
    modalBarrierColor: genAiOverlayScrim(),
    isScrollControlled: isScrollControlled,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
  );
  final result = await navigator.push(route);
  // A selection can open another modal. Finish removing this sheet first.
  await route.completed;
  return result;
}

/// Shows a popover using the draft's anchor rule rather than Material's
/// viewport clamping, which can otherwise push a bottom menu over its button.
///
/// The nearest Scaffold is the workspace-local stage. The measured menu opens
/// 7px below its anchor when it fits, otherwise 7px above it, with a 10px side
/// inset and an 8px top inset. Tall menus scroll within the available side.
Future<T?> genAiShowAnchoredMenu<T>({
  required BuildContext context,
  required BuildContext anchorContext,
  required List<PopupMenuEntry<T>> items,
  Offset? pressPosition,
  double minWidth = 220,
  String? semanticLabel,
  bool preferAbove = false,
  bool alignEnd = false,
  double gap = 7,
  double menuPadding = 6,
  double radius = 12,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final anchor = anchorContext.findRenderObject()! as RenderBox;
  final scaffold = Scaffold.maybeOf(anchorContext)?.context.findRenderObject();
  final stage = scaffold is RenderBox ? scaffold : overlay;
  Rect bounds(RenderBox box) => box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  final media = MediaQuery.of(navigator.context);
  final available = media.padding.deflateRect(
    media.viewInsets.deflateRect(Offset.zero & overlay.size),
  );
  final visibleStage = bounds(stage).intersect(available);
  var target = bounds(anchor);
  if (pressPosition != null && target.height > 96) {
    // A tall message can extend past the viewport. Keep its menu by the finger.
    target = overlay.globalToLocal(pressPosition) & Size.zero;
  }
  final route = _GenAiAnchoredMenuRoute<T>(
    anchor: target,
    stage: visibleStage,
    items: items,
    width: minWidth,
    semanticLabel: semanticLabel ?? MaterialLocalizations.of(context).popupMenuLabel,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    preferAbove: preferAbove,
    alignEnd: alignEnd,
    gap: gap,
    menuPadding: menuPadding,
    radius: radius,
  );
  final layout = GenAiLayout.of(context);
  final waitForDismissal = layout.narrow || GenAiLayout.touchPlatform && layout.short;
  final result = await navigator.push(route);
  if (waitForDismissal) await route.completed;
  return result;
}

/// Clips each native menu row's hover and ink to the draft's 7px corners.
/// Dividers and custom entries retain their own presentation.
Widget genAiMenuEntry<T>(PopupMenuEntry<T> entry) => entry is PopupMenuItem<T>
    ? Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(7),
        clipBehavior: Clip.antiAlias,
        child: entry,
      )
    : entry;

class _GenAiAnchoredMenuRoute<T> extends PopupRoute<T> {
  _GenAiAnchoredMenuRoute({
    required this.anchor,
    required this.stage,
    required this.items,
    required this.width,
    required this.semanticLabel,
    required this.barrierLabel,
    required this.themes,
    required this.preferAbove,
    required this.alignEnd,
    required this.gap,
    required this.menuPadding,
    required this.radius,
  });

  final Rect anchor;
  final Rect stage;
  final List<PopupMenuEntry<T>> items;
  final double width;
  final String semanticLabel;
  final CapturedThemes themes;
  final bool preferAbove;
  final bool alignEnd;
  final double gap;
  final double menuPadding;
  final double radius;

  @override
  final String barrierLabel;
  @override
  bool get barrierDismissible => true;
  @override
  Color? get barrierColor => null;
  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return themes.wrap(
      genAiThemeScope(
        context,
        Builder(
          builder: (context) {
            final palette = GenAiPalette.of(context);
            return Semantics(
              role: ui.SemanticsRole.menu,
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: semanticLabel,
              child: CustomSingleChildLayout(
                delegate: _GenAiAnchoredMenuLayout(
                  anchor: anchor,
                  stage: stage,
                  width: width,
                  preferAbove: preferAbove,
                  alignEnd: alignEnd,
                  gap: gap,
                ),
                child: Material(
                  key: const ValueKey('genai-anchored-menu'),
                  color: palette.raised,
                  surfaceTintColor: Colors.transparent,
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radius),
                    side: BorderSide(color: palette.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _GenAiMenuInteraction(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(menuPadding),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: items.map(genAiMenuEntry).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}

/// A menu is one keyboard group, independent of whether it is a sheet or
/// popover. Close on window/keyboard geometry changes rather than retain a
/// stale anchor. The next opening uses the new layout and presentation mode.
class _GenAiMenuInteraction extends StatefulWidget {
  const _GenAiMenuInteraction({required this.child});
  final Widget child;

  @override
  State<_GenAiMenuInteraction> createState() => _GenAiMenuInteractionState();
}

class _GenAiMenuInteractionState extends State<_GenAiMenuInteraction> with WidgetsBindingObserver {
  final _focus = FocusScopeNode(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);
  ui.FlutterView? _view;
  Size? _physicalSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _view = View.of(context);
    _physicalSize ??= _view!.physicalSize;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.nextFocus();
    });
  }

  @override
  void didChangeMetrics() {
    // Web text-field focus also emits metrics notifications. Only a real
    // window resize invalidates the anchor; hiding the keyboard to open a
    // menu must not immediately close that menu again.
    final size = _view?.physicalSize;
    if (size == null || size == _physicalSize) return;
    _physicalSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    super.dispose();
  }

  void _edge(bool last) {
    final nodes = _focus.traversalDescendants.where((node) => node.canRequestFocus).toList();
    if (nodes.isNotEmpty) (last ? nodes.last : nodes.first).requestFocus();
  }

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: WidgetOrderTraversalPolicy(),
    child: FocusScope(
      node: _focus,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): _focus.nextFocus,
          const SingleActivator(LogicalKeyboardKey.arrowUp): _focus.previousFocus,
          const SingleActivator(LogicalKeyboardKey.home): () => _edge(false),
          const SingleActivator(LogicalKeyboardKey.end): () => _edge(true),
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
          const SingleActivator(LogicalKeyboardKey.tab): () => Navigator.pop(context),
          const SingleActivator(LogicalKeyboardKey.tab, shift: true): () => Navigator.pop(context),
        },
        child: widget.child,
      ),
    ),
  );
}

class _GenAiAnchoredMenuLayout extends SingleChildLayoutDelegate {
  const _GenAiAnchoredMenuLayout({
    required this.anchor,
    required this.stage,
    required this.width,
    this.preferAbove = false,
    this.alignEnd = false,
    this.gap = 7,
  });

  final Rect anchor;
  final Rect stage;
  final double width;
  final bool preferAbove;
  final bool alignEnd;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final below = stage.bottom - anchor.bottom - gap;
    final above = anchor.top - gap - stage.top - 8;
    return BoxConstraints(
      minWidth: math.min(width, math.max(0, stage.width - 20)),
      maxWidth: math.min(width, math.max(0, stage.width - 20)),
      maxHeight: math.max(0, math.max(below, above)),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final minLeft = stage.left + 10;
    final maxLeft = stage.right - childSize.width - 10;
    final left = (alignEnd ? anchor.right - childSize.width : anchor.left).clamp(minLeft, maxLeft);
    final below = anchor.bottom + gap;
    final above = anchor.top - gap - childSize.height;
    final fitsBelow = below + childSize.height <= stage.bottom;
    final fitsAbove = above >= stage.top + 8;
    final top = preferAbove && fitsAbove ? above : (fitsBelow ? below : above);
    return Offset(left, math.max(stage.top + 8, top));
  }

  @override
  bool shouldRelayout(_GenAiAnchoredMenuLayout oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.stage != stage ||
      oldDelegate.width != width ||
      oldDelegate.preferAbove != preferAbove ||
      oldDelegate.alignEnd != alignEnd ||
      oldDelegate.gap != gap;
}

/// The workspace's few surface roles, derived from the host scheme so light,
/// dark, AMOLED, dynamic color and iOS accents all follow TechPie settings.
final class GenAiPalette {
  GenAiPalette._(ThemeData theme)
    : canvas = theme.scaffoldBackgroundColor,
      sidebar = theme.colorScheme.surfaceContainerLow,
      raised = theme.brightness == Brightness.light
          ? theme.colorScheme.surfaceContainerLowest
          : theme.colorScheme.surfaceContainerHigh,
      soft = theme.colorScheme.surfaceContainerHigh,
      hover = theme.colorScheme.onSurface.withValues(alpha: .06),
      line = theme.colorScheme.outlineVariant,
      text = theme.colorScheme.onSurface,
      muted = theme.colorScheme.onSurfaceVariant,
      accent = theme.colorScheme.primary,
      accentSoft = theme.colorScheme.primary.withValues(alpha: .1),
      onAccent = theme.colorScheme.onPrimary,
      success = theme.colorScheme.tertiary;

  factory GenAiPalette.of(BuildContext context) => GenAiPalette._(Theme.of(context));

  final Color canvas;
  final Color sidebar;
  final Color raised;
  final Color soft;
  final Color hover;
  final Color line;
  final Color text;
  final Color muted;
  final Color accent;
  final Color accentSoft;
  final Color onAccent;
  final Color success;

  /// Reading width shared by the thread, composer and notices.
  static const readingWidth = 760.0;
  static const wideBreakpoint = 960.0;
}
