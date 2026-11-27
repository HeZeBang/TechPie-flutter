import Foundation
import ImageIO
import SwiftUI
import WidgetKit
import DeadlineWidgetSupport

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Design Tokens (aligned with lib/theme/tp_tokens.dart & tp_campus_card_strip.dart)

enum TpWidgetColor {
  static func brand(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#E03140") : Color(tpHex: "#A30B19")
  }

  static func brandInk(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#FF6470") : Color(tpHex: "#A30B19")
  }

  static func brandSoft(_ scheme: ColorScheme) -> Color {
    brand(scheme).opacity(scheme == .dark ? 0.16 : 0.10)
  }

  static func surface(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#1C1C1E") : Color(tpHex: "#FFFFFF")
  }

  static func surfaceSubtle(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#2C2C2E") : Color(tpHex: "#F2F2F7")
  }

  static func divider(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
  }

  static func textPrimary(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#FAFAFA") : Color(tpHex: "#171717")
  }

  static func textSecondary(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#D1D1D6") : Color(tpHex: "#3A3A3C")
  }

  static func textMuted(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#98989D") : Color(tpHex: "#636366")
  }

  static func dangerRed(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#FF453A") : Color(tpHex: "#A30B19")
  }

  static func warningAmber(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#F59E0B") : Color(tpHex: "#B45309")
  }

  static func successGreen(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#30D158") : Color(tpHex: "#15803D")
  }

  static func courseAccent(lightHex: String, darkHex: String, isExam: Bool, scheme: ColorScheme) -> Color {
    if isExam {
      return dangerRed(scheme)
    }
    return Color(tpHex: scheme == .dark ? darkHex : lightHex)
  }

  // Campus Entity Card Surface
  static func cardHeader(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#7D0810") : Color(tpHex: "#9D0A12")
  }

  static func cardHeaderSeam(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#5A050A") : Color(tpHex: "#84070E")
  }

  static func cardBodyTop(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#1B1315") : Color(tpHex: "#FEF9F9")
  }

  static func cardBodyBottom(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#28171B") : Color(tpHex: "#FDEBEC")
  }

  static func cardInk(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#FBE8EA") : Color(tpHex: "#7A1018")
  }

  static func cardMutedInk(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? Color(tpHex: "#D8A8AE") : Color(tpHex: "#9E4B52")
  }
}

extension Color {
  init(tpHex hex: String) {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&int)
    let r, g, b: Double
    if cleaned.count == 6 {
      r = Double((int >> 16) & 0xFF) / 255.0
      g = Double((int >> 8) & 0xFF) / 255.0
      b = Double(int & 0xFF) / 255.0
    } else {
      r = 0.64; g = 0.04; b = 0.10
    }
    self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
  }
}

// MARK: - Localization

enum WidgetL10n {
  static func string(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
  }

  static func format(_ key: String, _ arg: Int) -> String {
    String.localizedStringWithFormat(string(key), arg)
  }

  static func format(_ key: String, _ arg1: Int, _ arg2: Int) -> String {
    String.localizedStringWithFormat(string(key), arg1, arg2)
  }

  static func weekdayShort(_ weekday: Int) -> String {
    let clamped = max(1, min(7, weekday))
    return string("widget.weekday.\(clamped)")
  }
}

// MARK: - Rendering Mode & Compatibility Modifiers

@available(iOS 16.0, macOS 13.0, *)
private struct TpRenderingModeReader<Content: View>: View {
  @Environment(\.widgetRenderingMode) private var mode
  let content: (Bool) -> Content

  var body: some View {
    content(mode == .fullColor)
  }
}

struct TpWidgetFullColorReader<Content: View>: View {
  let content: (Bool) -> Content

  init(@ViewBuilder content: @escaping (Bool) -> Content) {
    self.content = content
  }

  var body: some View {
    if #available(iOS 16.0, macOS 13.0, *) {
      TpRenderingModeReader(content: content)
    } else {
      content(true)
    }
  }
}

extension WidgetConfiguration {
  func tpContentMarginsDisabled() -> some WidgetConfiguration {
    if #available(iOS 17.0, macOS 14.0, *) {
      return self.contentMarginsDisabled()
    } else {
      return self
    }
  }
}

extension View {
  @ViewBuilder
  func tpAccentable(_ isAccent: Bool = true) -> some View {
    if #available(iOS 16.0, macOS 13.0, *) {
      self.widgetAccentable(isAccent)
    } else {
      self
    }
  }

  @ViewBuilder
  func tpPrivacySensitive(_ sensitive: Bool = true) -> some View {
    if #available(iOS 15.0, macOS 12.0, *), sensitive {
      self.privacySensitive()
    } else {
      self
    }
  }

  @ViewBuilder
  func tpWidgetSurfaceBackground(isFullColor: Bool, colorScheme: ColorScheme) -> some View {
    if #available(iOS 17.0, macOS 14.0, *) {
      self.containerBackground(for: .widget) {
        if isFullColor {
          TpWidgetColor.surface(colorScheme)
        } else {
          Color.clear
        }
      }
    } else {
      self
        .padding(14)
        .background(TpWidgetColor.surface(colorScheme))
    }
  }

  @ViewBuilder
  func tpLockScreenContainerBackground() -> some View {
    if #available(iOS 17.0, macOS 14.0, *) {
      self.containerBackground(for: .widget) {
        Color.clear
      }
    } else {
      self
    }
  }
}

// MARK: - Artwork Loader

enum TpWidgetArtwork {
  static func loadCampusSkyline() -> Image? {
    guard let url = Bundle.main.url(forResource: "card-bottom", withExtension: "png"),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: 640,
        kCGImageSourceShouldCacheImmediately: true,
      ] as CFDictionary)
    else { return nil }
    return Image(decorative: cgImage, scale: 1)
  }
}

// MARK: - Shared Structural Atoms

struct TpAccentBar: View {
  let color: Color
  var width: CGFloat = 3

  var body: some View {
    RoundedRectangle(cornerRadius: width / 2, style: .continuous)
      .fill(color)
      .frame(width: width)
      .tpAccentable()
  }
}

struct TpCountPill: View {
  let text: String
  var foreground: Color
  var background: Color
  var fontSize: CGFloat = 11

  var body: some View {
    Text(text)
      .font(.system(size: fontSize, weight: .semibold, design: .rounded).monospacedDigit())
      .foregroundColor(foreground)
      .padding(.horizontal, 7)
      .padding(.vertical, 2.5)
      .background(
        Capsule(style: .continuous)
          .fill(background)
      )
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
  }
}

struct TpWidgetHeader<Trailing: View>: View {
  @Environment(\.colorScheme) private var colorScheme
  let icon: String
  let titleKey: String
  let badgeText: String?
  let trailing: () -> Trailing

  init(
    icon: String,
    titleKey: String,
    badgeText: String? = nil,
    @ViewBuilder trailing: @escaping () -> Trailing
  ) {
    self.icon = icon
    self.titleKey = titleKey
    self.badgeText = badgeText
    self.trailing = trailing
  }

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(TpWidgetColor.brandInk(colorScheme))
        .tpAccentable()
      Text(LocalizedStringKey(titleKey))
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(TpWidgetColor.brandInk(colorScheme))
        .lineLimit(1)
        .tpAccentable()
      if let badgeText, !badgeText.isEmpty {
        TpCountPill(
          text: badgeText,
          foreground: TpWidgetColor.brandInk(colorScheme),
          background: TpWidgetColor.brandSoft(colorScheme),
          fontSize: 10.5
        )
      }
      Spacer(minLength: 4)
      trailing()
    }
  }
}

extension TpWidgetHeader where Trailing == EmptyView {
  init(icon: String, titleKey: String, badgeText: String? = nil) {
    self.init(icon: icon, titleKey: titleKey, badgeText: badgeText) {
      EmptyView()
    }
  }
}

struct TpWidgetEmptyState: View {
  @Environment(\.colorScheme) private var colorScheme
  let icon: String
  let messageKey: String

  var body: some View {
    VStack(spacing: 6) {
      Spacer(minLength: 0)
      Image(systemName: icon)
        .font(.system(size: 22, weight: .medium))
        .foregroundColor(TpWidgetColor.textMuted(colorScheme))
        .accessibilityHidden(true)
      Text(LocalizedStringKey(messageKey))
        .font(.system(size: 12.5, weight: .medium))
        .foregroundColor(TpWidgetColor.textSecondary(colorScheme))
        .multilineTextAlignment(.center)
        .lineLimit(2)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
