import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/platform.dart';
import 'macos_window_drag.dart';

class SwitchTabIntent extends Intent {
  const SwitchTabIntent(this.index);
  final int index;
}

class ToggleCommandPaletteIntent extends Intent {
  const ToggleCommandPaletteIntent();
}

class RefreshWorkbenchIntent extends Intent {
  const RefreshWorkbenchIntent();
}

class ToggleSidebarIntent extends Intent {
  const ToggleSidebarIntent();
}

class NavigateBackIntent extends Intent {
  const NavigateBackIntent();
}

/// Wraps the desktop shell with global keyboard shortcuts (`Cmd/Ctrl+1..5`,
/// `Cmd/Ctrl+K`, `Cmd/Ctrl+R` / plain `R`, `Cmd/Ctrl+\`, `Esc` / `Cmd+[`) and
/// mounts macOS's native `PlatformMenuBar` on macOS builds.
class DesktopWorkbenchChrome extends StatelessWidget {
  const DesktopWorkbenchChrome({
    super.key,
    required this.onSelectTab,
    required this.onToggleCommandPalette,
    required this.onRefresh,
    required this.onNavigateBack,
    required this.canNavigateBack,
    required this.onToggleTheme,
    this.onEditHomeLayout,
    this.sidebarCollapsed = false,
    this.onToggleSidebar,
    this.enableMenuBar = true,
    required this.child,
  });

  final ValueChanged<int> onSelectTab;
  final VoidCallback onToggleCommandPalette;
  final VoidCallback onRefresh;
  final VoidCallback onNavigateBack;
  final bool Function() canNavigateBack;
  final VoidCallback onToggleTheme;
  final VoidCallback? onEditHomeLayout;
  final bool sidebarCollapsed;
  final VoidCallback? onToggleSidebar;
  final bool enableMenuBar;
  final Widget child;

  static bool isTextInputFocused() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktop()) return child;

    final isMac = isMacOsDesktop();
    final shortcutMap = <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.digit1, meta: isMac, control: !isMac):
          const SwitchTabIntent(0),
      SingleActivator(LogicalKeyboardKey.digit2, meta: isMac, control: !isMac):
          const SwitchTabIntent(1),
      SingleActivator(LogicalKeyboardKey.digit3, meta: isMac, control: !isMac):
          const SwitchTabIntent(2),
      SingleActivator(LogicalKeyboardKey.digit4, meta: isMac, control: !isMac):
          const SwitchTabIntent(4),
      SingleActivator(LogicalKeyboardKey.digit5, meta: isMac, control: !isMac):
          const SwitchTabIntent(3),
      if (isMac)
        const SingleActivator(LogicalKeyboardKey.comma, meta: true):
            const SwitchTabIntent(3),
      SingleActivator(LogicalKeyboardKey.keyK, meta: isMac, control: !isMac):
          const ToggleCommandPaletteIntent(),
      SingleActivator(LogicalKeyboardKey.keyR, meta: isMac, control: !isMac):
          const RefreshWorkbenchIntent(),
      const SingleActivator(LogicalKeyboardKey.keyR):
          const RefreshWorkbenchIntent(),
      if (onToggleSidebar != null)
        SingleActivator(
          LogicalKeyboardKey.backslash,
          meta: isMac,
          control: !isMac,
        ): const ToggleSidebarIntent(),
      if (isMac)
        const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
            const NavigateBackIntent()
      else
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            const NavigateBackIntent(),
      const SingleActivator(LogicalKeyboardKey.escape):
          const NavigateBackIntent(),
    };

    final body = Shortcuts(
      shortcuts: shortcutMap,
      child: Actions(
        actions: <Type, Action<Intent>>{
          SwitchTabIntent: CallbackAction<SwitchTabIntent>(
            onInvoke: (intent) {
              onSelectTab(intent.index);
              return null;
            },
          ),
          ToggleCommandPaletteIntent:
              CallbackAction<ToggleCommandPaletteIntent>(
            onInvoke: (_) {
              onToggleCommandPalette();
              return null;
            },
          ),
          RefreshWorkbenchIntent: _GuardedCallbackAction<RefreshWorkbenchIntent>(
            enabledCheck: () => !isTextInputFocused(),
            onExecute: onRefresh,
          ),
          ToggleSidebarIntent: _GuardedCallbackAction<ToggleSidebarIntent>(
            enabledCheck: () => onToggleSidebar != null,
            onExecute: () => onToggleSidebar?.call(),
          ),
          NavigateBackIntent: _GuardedCallbackAction<NavigateBackIntent>(
            enabledCheck: () =>
                !isTextInputFocused() &&
                (ModalRoute.of(context)?.isCurrent ?? true) &&
                canNavigateBack(),
            onExecute: onNavigateBack,
          ),
        },
        child: Focus(
          autofocus: true,
          child: child,
        ),
      ),
    );

    if (!isMac || !enableMenuBar) return body;

    return PlatformMenuBar(
      menus: <PlatformMenuItem>[
        const PlatformMenu(
          label: 'TechPie',
          menus: <PlatformMenuItem>[
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.about,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications,
                ),
              ],
            ),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ],
        ),
        PlatformMenu(
          label: '前往',
          menus: <PlatformMenuItem>[
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: '首页',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.digit1,
                    meta: true,
                  ),
                  onSelected: () => onSelectTab(0),
                ),
                PlatformMenuItem(
                  label: '课表',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.digit2,
                    meta: true,
                  ),
                  onSelected: () => onSelectTab(1),
                ),
                PlatformMenuItem(
                  label: 'Deadlines',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.digit3,
                    meta: true,
                  ),
                  onSelected: () => onSelectTab(2),
                ),
                PlatformMenuItem(
                  label: '校园服务',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.digit4,
                    meta: true,
                  ),
                  onSelected: () => onSelectTab(4),
                ),
                PlatformMenuItem(
                  label: '我的',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.digit5,
                    meta: true,
                  ),
                  onSelected: () => onSelectTab(3),
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: '快速命令面板…',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyK,
                    meta: true,
                  ),
                  onSelected: onToggleCommandPalette,
                ),
              ],
            ),
            PlatformMenuItem(
              label: '返回上一页',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.bracketLeft,
                meta: true,
              ),
              onSelected: canNavigateBack() ? onNavigateBack : null,
            ),
          ],
        ),
        PlatformMenu(
          label: '视图',
          menus: <PlatformMenuItem>[
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: '刷新当前数据',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyR,
                    meta: true,
                  ),
                  onSelected: onRefresh,
                ),
                if (onToggleSidebar != null)
                  PlatformMenuItem(
                    label: sidebarCollapsed ? '展开侧边栏' : '收起侧边栏',
                    shortcut: const SingleActivator(
                      LogicalKeyboardKey.backslash,
                      meta: true,
                    ),
                    onSelected: onToggleSidebar,
                  ),
              ],
            ),
            if (onEditHomeLayout != null)
              PlatformMenuItem(
                label: '定制主页控件',
                onSelected: onEditHomeLayout,
              ),
            PlatformMenuItem(
              label: '切换深浅外观',
              onSelected: onToggleTheme,
            ),
          ],
        ),
        const PlatformMenu(
          label: '窗口',
          menus: <PlatformMenuItem>[
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
          ],
        ),
      ],
      child: body,
    );
  }
}

class _GuardedCallbackAction<T extends Intent> extends Action<T> {
  _GuardedCallbackAction({
    required this.enabledCheck,
    required this.onExecute,
  });

  final bool Function() enabledCheck;
  final VoidCallback onExecute;

  @override
  bool isEnabled(T intent) => enabledCheck();

  @override
  Object? invoke(T intent) {
    if (!enabledCheck()) return null;
    onExecute();
    return null;
  }
}
