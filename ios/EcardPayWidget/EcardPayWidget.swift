import SwiftUI
import WidgetKit

/// Hosts TechPie's iOS Home Screen, Lock Screen, and Control Center widgets.
/// EcardPayWidget & EcardPayControlWidget route to `techpie://ecard/pay` via `TechPieWidgetURL.ecardPay()`.
@main
struct TechPieWidgets: WidgetBundle {
  var body: some Widget {
    EcardPayWidget()
    ScheduleWidget()
    DeadlineWidget()
    TodayOverviewWidget()
    #if compiler(>=6.0)
    if #available(iOS 18.0, *) {
      EcardPayControlWidget()
    }
    #endif
  }
}
