import SwiftUI
import WidgetKit
import ImageIO

private struct EcardPayEntry: TimelineEntry {
  let date: Date
}

private struct EcardPayProvider: TimelineProvider {
  func placeholder(in context: Context) -> EcardPayEntry {
    EcardPayEntry(date: Date())
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (EcardPayEntry) -> Void
  ) {
    completion(EcardPayEntry(date: Date()))
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<EcardPayEntry>) -> Void
  ) {
    completion(
      Timeline(
        entries: [EcardPayEntry(date: Date())],
        policy: .never
      )
    )
  }
}

private struct EcardPayWidgetView: View {
  var body: some View {
    Group {
      if #available(iOS 17.0, *) {
        content.containerBackground(for: .widget) { artwork }
      } else {
        content.padding(16).background(artwork)
      }
    }
    .widgetURL(URL(string: "techpie://ecard/pay"))
  }

  @ViewBuilder
  private var artwork: some View {
    if let url = Bundle.main.url(forResource: "widget-background", withExtension: "png"),
       let source = CGImageSourceCreateWithURL(url as CFURL, nil),
       let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
         kCGImageSourceCreateThumbnailFromImageAlways: true,
         kCGImageSourceThumbnailMaxPixelSize: 512,
         kCGImageSourceShouldCacheImmediately: true,
       ] as CFDictionary) {
      // WidgetKit archives the rendered image; bound its decoded memory cost.
      Image(decorative: image, scale: 1).resizable().scaledToFill()
    } else {
      Color(red: 1, green: 247.0 / 255, blue: 248.0 / 255)
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 6) {
      Image(systemName: "qrcode")
        .font(.system(size: 36, weight: .semibold))
        .foregroundColor(Color(red: 157.0 / 255, green: 10.0 / 255, blue: 18.0 / 255))
        .accessibilityHidden(true)
      Spacer(minLength: 8)
      Text("widget.title")
        .font(.headline)
        .foregroundColor(Color(red: 36.0 / 255, green: 36.0 / 255, blue: 40.0 / 255))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      Text("widget.subtitle")
        .font(.caption)
        .foregroundColor(Color(red: 118.0 / 255, green: 101.0 / 255, blue: 106.0 / 255))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

@main
struct EcardPayWidget: Widget {
  let kind = "EcardPayWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: EcardPayProvider()) { _ in
      EcardPayWidgetView()
    }
    .configurationDisplayName("widget.title")
    .description("widget.description")
    .supportedFamilies([.systemSmall])
  }
}
