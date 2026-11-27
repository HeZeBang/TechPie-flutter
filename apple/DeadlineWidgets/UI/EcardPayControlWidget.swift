import SwiftUI
import WidgetKit
import DeadlineWidgetSupport

#if os(iOS) && compiler(>=6.0)
@available(iOS 18.0, *)
struct EcardPayControlWidget: ControlWidget {
  static let kind = "EcardPayControlWidget"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind) {
      ControlWidgetButton(action: OpenEcardPayCodeControlIntent()) {
        Label {
          Text(LocalizedStringKey("widget.title"))
        } icon: {
          Image(systemName: "qrcode")
        }
      }
    }
    .displayName("widget.title")
    .description("widget.description")
  }
}
#endif
