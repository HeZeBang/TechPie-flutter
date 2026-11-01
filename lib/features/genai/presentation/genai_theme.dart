import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  const menuShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );
  const controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
  );
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

  final filledButtonStyle = ButtonStyle(
    backgroundColor: buttonBackground(palette.accent),
    foregroundColor: buttonForeground(palette.onAccent),
    overlayColor: WidgetStatePropertyAll(palette.hover),
    padding: const WidgetStatePropertyAll(controlPadding),
    shape: const WidgetStatePropertyAll(controlShape),
    textStyle: WidgetStatePropertyAll(
      textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
  );

  final outlinedButtonStyle = ButtonStyle(
    foregroundColor: buttonForeground(palette.accent),
    overlayColor: WidgetStatePropertyAll(palette.hover),
    padding: const WidgetStatePropertyAll(controlPadding),
    shape: const WidgetStatePropertyAll(controlShape),
    side: WidgetStateProperty.resolveWith<BorderSide?>(
      (states) => BorderSide(
        color: states.contains(WidgetState.disabled)
            ? palette.line.withValues(alpha: .5)
            : palette.line,
      ),
    ),
    textStyle: WidgetStatePropertyAll(
      textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
  );

  final textButtonStyle = ButtonStyle(
    foregroundColor: buttonForeground(palette.accent),
    overlayColor: WidgetStatePropertyAll(palette.hover),
    padding: const WidgetStatePropertyAll(controlPadding),
    shape: const WidgetStatePropertyAll(controlShape),
    textStyle: WidgetStatePropertyAll(
      textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
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
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(vertical: 6),
    ),
  );

  final menuButtonStyle = ButtonStyle(
    foregroundColor: WidgetStatePropertyAll(palette.text),
    overlayColor: WidgetStatePropertyAll(palette.hover),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
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
    dividerTheme: DividerThemeData(
      color: palette.line,
      space: 1,
      thickness: 1,
    ),
  );
}

/// Applies the GenAI component theme at an overlay route boundary.
///
/// Dialog and sheet routes capture themes from their launch context, which may
/// be above a widget's local workspace theme. Reapplying the same derived theme
/// in the route builder keeps those overlays consistent without changing the
/// host app's theme.
Widget genAiThemeScope(BuildContext context, Widget child) => Theme(
      data: genAiTheme(Theme.of(context)),
      child: child,
    );

/// Shared draft scrim: drawers are lighter than dialogs and modal sheets.
Color genAiOverlayScrim({bool drawer = false}) =>
    drawer ? const Color(0x55121015) : const Color(0x66121015);

/// Opens a Material dialog with the GenAI scrim and a 3px backdrop blur.
///
/// The filter belongs to the route barrier, not its content, so only the
/// underlying shell is blurred and barrier dismissal/focus behavior is intact.
Future<T?> genAiShowDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool fullscreenDialog = false,
  bool? requestFocus,
  AnimationStyle? animationStyle,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push<T>(
    _GenAiDialogRoute<T>(
      context: context,
      builder: (context) => genAiThemeScope(context, builder(context)),
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierColor: genAiOverlayScrim(),
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      settings: routeSettings,
      anchorPoint: anchorPoint,
      traversalEdgeBehavior: traversalEdgeBehavior ?? TraversalEdgeBehavior.closedLoop,
      fullscreenDialog: fullscreenDialog,
      requestFocus: requestFocus,
      animationStyle: animationStyle,
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
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: palette.text),
                      child: title,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: '关闭',
                    constraints: const BoxConstraints.tightFor(width: 36, height: 36),
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
                padding: actionsPadding ??
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

/// The sheet counterpart of [genAiShowDialog], sharing its barrier treatment.
Future<T?> genAiShowModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  bool isScrollControlled = false,
  double scrollControlDisabledMaxHeightRatio = 9 / 16,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool? requestFocus,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push<T>(
    _GenAiModalBottomSheetRoute<T>(
      builder: (context) => genAiThemeScope(context, builder(context)),
      capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierLabel: barrierLabel ?? localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(localizations.bottomSheetLabel),
      modalBarrierColor: genAiOverlayScrim(),
      backgroundColor: backgroundColor,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      isScrollControlled: isScrollControlled,
      scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      settings: routeSettings,
      transitionAnimationController: transitionAnimationController,
      anchorPoint: anchorPoint,
      sheetAnimationStyle: sheetAnimationStyle,
      requestFocus: requestFocus,
    ),
  );
}

mixin _GenAiOverlayBlur<T> on ModalRoute<T> {
  @override
  ui.ImageFilter get filter => ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3);
}

class _GenAiDialogRoute<T> extends DialogRoute<T> with _GenAiOverlayBlur<T> {
  _GenAiDialogRoute({
    required super.context,
    required super.builder,
    super.themes,
    super.barrierColor,
    super.barrierDismissible,
    super.barrierLabel,
    super.useSafeArea,
    super.settings,
    super.anchorPoint,
    super.traversalEdgeBehavior,
    super.fullscreenDialog,
    super.requestFocus,
    super.animationStyle,
  });
}

class _GenAiModalBottomSheetRoute<T> extends ModalBottomSheetRoute<T> with _GenAiOverlayBlur<T> {
  _GenAiModalBottomSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.modalBarrierColor,
    super.backgroundColor,
    super.elevation,
    super.shape,
    super.clipBehavior,
    super.constraints,
    super.scrollControlDisabledMaxHeightRatio,
    super.isDismissible,
    super.enableDrag,
    super.showDragHandle,
    super.useSafeArea,
    super.settings,
    super.transitionAnimationController,
    super.anchorPoint,
    super.sheetAnimationStyle,
    super.requestFocus,
  });
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
  double minWidth = 220,
  String? semanticLabel,
  bool preferAbove = false,
  bool alignEnd = false,
  double gap = 7,
  double menuPadding = 6,
  double radius = 12,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final anchor = anchorContext.findRenderObject()! as RenderBox;
  final scaffold = Scaffold.maybeOf(anchorContext)?.context.findRenderObject();
  final stage = scaffold is RenderBox ? scaffold : overlay;
  Rect bounds(RenderBox box) => box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  return navigator.push<T>(
    _GenAiAnchoredMenuRoute<T>(
      anchor: bounds(anchor),
      stage: bounds(stage).intersect(Offset.zero & overlay.size),
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
    ),
  );
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
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(menuPadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: items.map(genAiMenuEntry).toList(),
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
  ) =>
      FadeTransition(opacity: animation, child: child);
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
    final left = (alignEnd ? anchor.right - childSize.width : anchor.left).clamp(
      minLeft,
      maxLeft,
    );
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

/// A GenAI-styled native text selection menu for [EditableText]-backed widgets.
///
/// Attach it as the `contextMenuBuilder` of a [TextField] or [SelectableText]:
///
/// ```dart
/// TextField(contextMenuBuilder: genAiTextSelectionContextMenu)
/// ```
///
/// The popover reuses [EditableTextState.contextMenuButtonItems], so every
/// copy/cut/paste/select-all action keeps Flutter's own callback. It only
/// paints the draft's menu surface: a 12px radius, a 1px [GenAiPalette.line]
/// border, the raised background, 42px rows and 13px localized labels with the
/// workspace's icon sprite.
///
/// Web keeps Flutter's default path: the browser owns its context menu
/// ([BrowserContextMenu]), and [EditableText] ignores this builder there while
/// that menu is enabled. The default adaptive toolbar is still returned so a
/// host that disabled the browser menu keeps a working one.
Widget genAiTextSelectionContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  if (kIsWeb) {
    return AdaptiveTextSelectionToolbar.editableText(editableTextState: editableTextState);
  }
  final items = editableTextState.contextMenuButtonItems;
  if (items.isEmpty) return const SizedBox.shrink();
  return _GenAiSelectionToolbar(
    anchors: editableTextState.contextMenuAnchors,
    child: genAiThemeScope(
      context,
      _GenAiSelectionPopover(
        items: items,
        localizations: MaterialLocalizations.of(context),
      ),
    ),
  );
}

/// The same GenAI selection popover for [SelectionArea] and [SelectableRegion].
///
/// Keeps the region's native copy/select-all callbacks and mirrors the editable
/// builder's browser-owned context menu fallback on web.
Widget genAiRegionSelectionContextMenu(
  BuildContext context,
  SelectableRegionState selectableRegionState,
) {
  if (kIsWeb) {
    return AdaptiveTextSelectionToolbar.selectableRegion(
      selectableRegionState: selectableRegionState,
    );
  }
  final items = selectableRegionState.contextMenuButtonItems;
  if (items.isEmpty) return const SizedBox.shrink();
  return _GenAiSelectionToolbar(
    anchors: selectableRegionState.contextMenuAnchors,
    child: genAiThemeScope(
      context,
      _GenAiSelectionPopover(
        items: items,
        localizations: MaterialLocalizations.of(context),
      ),
    ),
  );
}

/// Positions the popover above the selection when it fits, otherwise below it,
/// using the same public layout delegate as Material's selection toolbar.
class _GenAiSelectionToolbar extends StatelessWidget {
  const _GenAiSelectionToolbar({required this.anchors, required this.child});

  final TextSelectionToolbarAnchors anchors;
  final Widget child;

  static const _screenPadding = 8.0;
  static const _contentGapAbove = 8.0;
  static const _contentGapBelow = 20.0;

  @override
  Widget build(BuildContext context) {
    final paddingAbove = MediaQuery.paddingOf(context).top + _screenPadding;
    final adjustment = Offset(_screenPadding, paddingAbove);
    return Padding(
      padding: EdgeInsets.fromLTRB(_screenPadding, paddingAbove, _screenPadding, _screenPadding),
      child: CustomSingleChildLayout(
        delegate: TextSelectionToolbarLayoutDelegate(
          anchorAbove: anchors.primaryAnchor - const Offset(0, _contentGapAbove) - adjustment,
          anchorBelow: (anchors.secondaryAnchor ?? anchors.primaryAnchor) +
              const Offset(0, _contentGapBelow) -
              adjustment,
        ),
        child: child,
      ),
    );
  }
}

/// The draft's popover: raised surface, 12px radius, 1px line border and 42px
/// rows whose 13px labels come from [MaterialLocalizations].
class _GenAiSelectionPopover extends StatelessWidget {
  const _GenAiSelectionPopover({required this.items, required this.localizations});

  final List<ContextMenuButtonItem> items;
  final MaterialLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    final palette = GenAiPalette.of(context);
    return Material(
      key: const ValueKey('genai-selection-popover'),
      color: palette.raised,
      elevation: 6,
      shadowColor: Theme.of(context).colorScheme.shadow.withValues(alpha: .18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 220,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items)
                _GenAiSelectionRow(
                  item: item,
                  label: _label(localizations, item),
                  palette: palette,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _label(MaterialLocalizations localizations, ContextMenuButtonItem item) {
    if (item.label != null) return item.label!;
    return switch (item.type) {
      ContextMenuButtonType.cut => localizations.cutButtonLabel,
      ContextMenuButtonType.copy => localizations.copyButtonLabel,
      ContextMenuButtonType.paste => localizations.pasteButtonLabel,
      ContextMenuButtonType.selectAll => localizations.selectAllButtonLabel,
      ContextMenuButtonType.delete => localizations.deleteButtonTooltip.toUpperCase(),
      ContextMenuButtonType.lookUp => localizations.lookUpButtonLabel,
      ContextMenuButtonType.searchWeb => localizations.searchWebButtonLabel,
      ContextMenuButtonType.share => localizations.shareButtonLabel,
      ContextMenuButtonType.liveTextInput => localizations.scanTextButtonLabel,
      ContextMenuButtonType.custom => '',
    };
  }
}

/// A 42px action row. Only existing [GenAiGlyph]s are used; the callback is the
/// one supplied by [EditableTextState.contextMenuButtonItems].
class _GenAiSelectionRow extends StatelessWidget {
  const _GenAiSelectionRow({
    required this.item,
    required this.label,
    required this.palette,
  });

  final ContextMenuButtonItem item;
  final String label;
  final GenAiPalette palette;

  static GenAiGlyph _glyph(ContextMenuButtonType type) => switch (type) {
        ContextMenuButtonType.cut => GenAiGlyph.edit,
        ContextMenuButtonType.copy => GenAiGlyph.copy,
        ContextMenuButtonType.paste => GenAiGlyph.plus,
        ContextMenuButtonType.selectAll => GenAiGlyph.checkCircle,
        ContextMenuButtonType.delete => GenAiGlyph.trash,
        ContextMenuButtonType.lookUp => GenAiGlyph.search,
        ContextMenuButtonType.searchWeb => GenAiGlyph.search,
        ContextMenuButtonType.share => GenAiGlyph.share,
        ContextMenuButtonType.liveTextInput => GenAiGlyph.image,
        ContextMenuButtonType.custom => GenAiGlyph.info,
      };

  @override
  Widget build(BuildContext context) {
    final onPressed = item.onPressed;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('genai-selection-${item.type.name}'),
        onTap: onPressed == null ? null : () => onPressed(),
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          height: 42,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                GenAiIcon(_glyph(item.type), size: 17, color: palette.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: palette.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
