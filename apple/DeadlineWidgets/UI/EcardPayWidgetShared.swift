import SwiftUI
import WidgetKit
import DeadlineWidgetSupport

struct EcardPayEntry: TimelineEntry {
  let date: Date
  let state: WidgetSnapshotState<EcardWidgetSnapshot>
  let effectiveHideBalance: Bool
}

struct EcardPayProvider: TimelineProvider {
  func placeholder(in context: Context) -> EcardPayEntry {
    EcardPayEntry(
      date: Date(),
      state: .ready(
        EcardWidgetSnapshot(
          configured: true,
          balanceText: "¥ 86.20",
          hideBalance: false
        )
      ),
      effectiveHideBalance: false
    )
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (EcardPayEntry) -> Void
  ) {
    completion(loadEntry(at: Date()))
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<EcardPayEntry>) -> Void
  ) {
    completion(Timeline(entries: [loadEntry(at: Date())], policy: .never))
  }

  private func loadEntry(at date: Date) -> EcardPayEntry {
    let state = EcardSnapshotStore.configured()?.read() ?? .notSynced
    let prefs = WidgetPreferenceStore.configured()
    let effectiveHide: Bool
    if case .ready(let snapshot) = state {
      effectiveHide = snapshot.effectiveHideBalance(using: prefs)
    } else {
      effectiveHide = false
    }
    return EcardPayEntry(date: date, state: state, effectiveHideBalance: effectiveHide)
  }
}

struct EcardPayWidgetView: View {
  let entry: EcardPayEntry

  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var colorScheme

  private static let skyline = TpWidgetArtwork.loadCampusSkyline()

  var body: some View {
    TpWidgetFullColorReader { isFullColor in
      rootContent(isFullColor: isFullColor)
    }
    .widgetURL(TechPieWidgetURL.ecardPay())
  }

  @ViewBuilder
  private func rootContent(isFullColor: Bool) -> some View {
    #if os(iOS)
    if #available(iOS 16.0, *) {
      switch family {
      case .accessoryCircular:
        circularAccessory
      case .accessoryInline:
        inlineAccessory
      case .systemMedium:
        homeCard(isMedium: true, isFullColor: isFullColor)
      default:
        homeCard(isMedium: false, isFullColor: isFullColor)
      }
    } else {
      homeCard(isMedium: family == .systemMedium, isFullColor: isFullColor)
    }
    #else
    homeCard(isMedium: family == .systemMedium, isFullColor: isFullColor)
    #endif
  }

  // MARK: - Home & Desktop Entity Card

  @ViewBuilder
  private func homeCard(isMedium: Bool, isFullColor: Bool) -> some View {
    if #available(iOS 17.0, macOS 14.0, *) {
      cardBody(isMedium: isMedium, isFullColor: isFullColor)
        .containerBackground(for: .widget) {
          Color.clear
        }
    } else {
      cardBody(isMedium: isMedium, isFullColor: isFullColor)
    }
  }

  private func cardBody(isMedium: Bool, isFullColor: Bool) -> some View {
    VStack(spacing: 0) {
      topCrimsonBand(isMedium: isMedium, isFullColor: isFullColor)
      ZStack(alignment: .bottomLeading) {
        if isFullColor {
          LinearGradient(
            colors: [
              TpWidgetColor.cardBodyTop(colorScheme),
              TpWidgetColor.cardBodyBottom(colorScheme),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          if let skyline = Self.skyline {
            GeometryReader { geo in
              skyline
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                .opacity(colorScheme == .dark ? 0.20 : 0.72)
                .clipped()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
          }
        }

        Group {
          if isMedium {
            mediumBody(isFullColor: isFullColor)
          } else {
            smallBody(isFullColor: isFullColor)
          }
        }
        .padding(.horizontal, isMedium ? 16 : 14)
        .padding(.vertical, isMedium ? 12 : 11)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private func topCrimsonBand(isMedium: Bool, isFullColor: Bool) -> some View {
    let headerTextColor: Color = isFullColor ? .white : .primary
    HStack(spacing: 6) {
      Image(systemName: "creditcard.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(headerTextColor.opacity(0.92))
        .tpAccentable(!isFullColor)
      Text(LocalizedStringKey("ecard.widget.brand"))
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(headerTextColor)
        .lineLimit(1)
        .tpAccentable(!isFullColor)

      Spacer(minLength: 4)

      if isMedium, case .ready(let snapshot) = entry.state, snapshot.configured,
        let balance = snapshot.balanceText, !balance.isEmpty
      {
        eyeToggleButton(snapshot: snapshot, tint: headerTextColor)
      } else if isMedium {
        Text("ShanghaiTech")
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(headerTextColor.opacity(0.75))
          .lineLimit(1)
      }
    }
    .padding(.horizontal, isMedium ? 16 : 14)
    .frame(height: isMedium ? 36 : 34)
    .frame(maxWidth: .infinity)
    .background {
      if isFullColor {
        TpWidgetColor.cardHeader(colorScheme)
      } else {
        Color.primary.opacity(0.08)
      }
    }
    .overlay(alignment: .bottom) {
      if isFullColor {
        TpWidgetColor.cardHeaderSeam(colorScheme)
          .frame(height: 0.5)
      }
    }
  }

  @ViewBuilder
  private func eyeToggleButton(snapshot: EcardWidgetSnapshot, tint: Color) -> some View {
    if #available(iOS 17.0, macOS 14.0, *) {
      Button(intent: ToggleEcardBalanceMaskIntent(currentSyncedHide: snapshot.hideBalance)) {
        Image(systemName: entry.effectiveHideBalance ? "eye.slash" : "eye")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(tint.opacity(0.92))
          .frame(width: 28, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(LocalizedStringKey("ecard.widget.toggleBalance"))
    }
  }

  private func smallBody(isFullColor: Bool) -> some View {
    let inkColor = isFullColor ? TpWidgetColor.cardInk(colorScheme) : Color.primary
    let mutedColor = isFullColor ? TpWidgetColor.cardMutedInk(colorScheme) : Color.secondary
    let badgeBg = isFullColor ? TpWidgetColor.brand(colorScheme) : Color.primary.opacity(0.14)
    let badgeFg: Color = isFullColor ? .white : .primary

    return VStack(alignment: .leading, spacing: 6) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(badgeBg)
          .frame(width: 42, height: 42)
        Image(systemName: "qrcode")
          .font(.system(size: 22, weight: .semibold))
          .foregroundColor(badgeFg)
          .tpAccentable(!isFullColor)
      }
      .accessibilityHidden(true)

      Spacer(minLength: 4)

      Text(LocalizedStringKey("widget.title"))
        .font(.system(size: 15, weight: .bold))
        .foregroundColor(inkColor)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
      Text(smallSubtitleKey)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(mutedColor)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func mediumBody(isFullColor: Bool) -> some View {
    let inkColor = isFullColor ? TpWidgetColor.cardInk(colorScheme) : Color.primary
    let mutedColor = isFullColor ? TpWidgetColor.cardMutedInk(colorScheme) : Color.secondary

    return HStack(alignment: .bottom, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(mediumEyebrowKey)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(mutedColor)
          .lineLimit(1)

        mediumPrimaryValueView(inkColor: inkColor)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

      qrActionBadge(isFullColor: isFullColor)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private func mediumPrimaryValueView(inkColor: Color) -> some View {
    switch entry.state {
    case .ready(let snapshot) where !snapshot.configured:
      Text(LocalizedStringKey("ecard.widget.tapToLink"))
        .font(.system(size: 20, weight: .bold))
        .foregroundColor(inkColor)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    case .ready(let snapshot) where snapshot.balanceText != nil && !(snapshot.balanceText?.isEmpty ?? true):
      if entry.effectiveHideBalance {
        Text("••••")
          .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
          .foregroundColor(inkColor)
          .lineLimit(1)
      } else {
        Text(snapshot.balanceText ?? "")
          .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
          .foregroundColor(inkColor)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .tpPrivacySensitive(true)
      }
    default:
      Text(LocalizedStringKey("widget.subtitle"))
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(inkColor)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
    }
  }

  private func qrActionBadge(isFullColor: Bool) -> some View {
    let pillBg = isFullColor ? TpWidgetColor.brand(colorScheme) : Color.primary.opacity(0.14)
    let pillFg: Color = isFullColor ? .white : .primary

    return HStack(spacing: 6) {
      Image(systemName: "qrcode")
        .font(.system(size: 15, weight: .semibold))
        .tpAccentable(!isFullColor)
      Text(LocalizedStringKey("ecard.widget.payButton"))
        .font(.system(size: 12.5, weight: .bold))
        .lineLimit(1)
    }
    .foregroundColor(pillFg)
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(pillBg)
    )
    .fixedSize(horizontal: true, vertical: false)
  }

  private var smallSubtitleKey: LocalizedStringKey {
    if case .ready(let snapshot) = entry.state, !snapshot.configured {
      return LocalizedStringKey("ecard.widget.tapToLink")
    }
    return LocalizedStringKey("widget.subtitle")
  }

  private var mediumEyebrowKey: LocalizedStringKey {
    switch entry.state {
    case .ready(let snapshot) where !snapshot.configured:
      return LocalizedStringKey("ecard.widget.notLinkedEyebrow")
    case .ready(let snapshot) where snapshot.balanceText != nil && !(snapshot.balanceText?.isEmpty ?? true):
      return LocalizedStringKey("ecard.widget.balanceEyebrow")
    default:
      return LocalizedStringKey("widget.title")
    }
  }

  // MARK: - iOS Lock Screen Accessories

  #if os(iOS)
  @available(iOS 16.0, *)
  private var circularAccessory: some View {
    ZStack {
      AccessoryWidgetBackground()
      VStack(spacing: 1) {
        Image(systemName: "qrcode")
          .font(.system(size: 20, weight: .semibold))
          .tpAccentable()
        Text(LocalizedStringKey("ecard.widget.shortPay"))
          .font(.system(size: 8.5, weight: .bold))
          .lineLimit(1)
      }
    }
    .tpLockScreenContainerBackground()
    .accessibilityLabel(LocalizedStringKey("widget.description"))
  }

  @available(iOS 16.0, *)
  private var inlineAccessory: some View {
    Label {
      Text(LocalizedStringKey("widget.title"))
    } icon: {
      Image(systemName: "qrcode")
    }
    .tpLockScreenContainerBackground()
  }
  #endif
}

struct EcardPayWidget: Widget {
  static let kind = "EcardPayWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: EcardPayProvider()) { entry in
      EcardPayWidgetView(entry: entry)
    }
    .configurationDisplayName("widget.title")
    .description("widget.description")
    .supportedFamilies(supportedFamilies)
    .tpContentMarginsDisabled()
  }

  private var supportedFamilies: [WidgetFamily] {
    #if os(iOS)
    if #available(iOS 16.0, *) {
      return [.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline]
    }
    #endif
    return [.systemSmall, .systemMedium]
  }
}
