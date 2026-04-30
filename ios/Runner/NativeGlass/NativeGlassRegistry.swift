import Flutter
import UIKit

enum NativeGlassRegistry {
  static func registerAll(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()

    registrar.register(
      NativeGlassTabBarFactory(messenger: messenger),
      withId: NativeGlassTabBarPlatformView.viewType
    )
    registrar.register(
      NativeGlassFloatingButtonFactory(messenger: messenger),
      withId: NativeGlassFloatingButtonPlatformView.viewType
    )
    registrar.register(
      NativeGlassButtonGroupFactory(messenger: messenger),
      withId: NativeGlassButtonGroupPlatformView.viewType
    )
    registrar.register(
      NativeGlassDropdownMenuFactory(messenger: messenger),
      withId: NativeGlassDropdownMenuPlatformView.viewType
    )
    registrar.register(
      NativeGlassSelectFactory(messenger: messenger),
      withId: NativeGlassSelectPlatformView.viewType
    )
    registrar.register(
      NativeGlassSwitchFactory(messenger: messenger),
      withId: NativeGlassSwitchPlatformView.viewType
    )
  }
}
