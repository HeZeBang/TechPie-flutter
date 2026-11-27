import SwiftUI
import WidgetKit

@main
struct DeadlineWidgets: WidgetBundle {
  var body: some Widget {
    EcardPayWidget()
    ScheduleWidget()
    DeadlineWidget()
    TodayOverviewWidget()
  }
}
