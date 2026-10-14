import SwiftUI
import ImageIO
import WatchSupport

@main
struct TechPieWatchApp: App {
  @StateObject private var store = WatchStore()
  var body: some Scene {
    WindowGroup { WatchHome().environmentObject(store) }
  }
}

private enum WatchPalette {
  static let red = Color(red: 157.0 / 255, green: 10.0 / 255, blue: 18.0 / 255)
  static let paper = Color(red: 254.0 / 255, green: 249.0 / 255, blue: 249.0 / 255)
  static let ink = Color(red: 41.0 / 255, green: 25.0 / 255, blue: 28.0 / 255)
  static let secondary = Color(red: 119.0 / 255, green: 94.0 / 255, blue: 101.0 / 255)
}

struct WatchHome: View {
  @EnvironmentObject private var store: WatchStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var path: [String] = []
  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          HStack(spacing: 8) {
            BundledArtwork(name: "Logo").frame(width: 30, height: 30).accessibilityHidden(true)
            Text("TechPie").font(.title2.weight(.semibold)).minimumScaleFactor(0.8).lineLimit(1)
          }.frame(maxWidth: .infinity, alignment: .leading)
          NavigationLink(value: "campusCard") {
            HStack(spacing: 10) {
              Image(systemName: "creditcard.fill").foregroundStyle(.white)
                .frame(width: 30, height: 28).background(WatchPalette.red, in: RoundedRectangle(cornerRadius: 8))
              Text("校园卡").font(.headline)
              Spacer(minLength: 0)
            }
          }
          .buttonBorderShape(.roundedRectangle(radius: 12))
          .accessibilityIdentifier("campus-card-entry")
          NavigationLink(value: "settings") {
            HStack(spacing: 10) {
              Image(systemName: "gearshape.fill").foregroundStyle(.white)
                .frame(width: 30, height: 28).background(WatchPalette.red, in: RoundedRectangle(cornerRadius: 8))
              Text("设置").font(.headline)
              Spacer(minLength: 0)
            }
          }
          .buttonBorderShape(.roundedRectangle(radius: 12))
          .accessibilityIdentifier("watch-settings-entry")
        }.padding(.horizontal, 4)
      }
      .navigationDestination(for: String.self) { destination in
        if destination == "settings" { WatchSettingsPage() }
        else { CampusCardPages() }
      }
      .onAppear {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--preview-settings") { path = ["settings"] }
        else if ProcessInfo.processInfo.arguments.contains("--preview-pay") || ProcessInfo.processInfo.arguments.contains("--preview-info") { path = ["campusCard"] }
        #endif
      }
    }
    .task(id: scenePhase == .active && path.isEmpty) {
      let active = scenePhase == .active
      if !active { store.setCodeVisible(false) }
      guard active, path.isEmpty else { return }
      while !Task.isCancelled {
        store.requestSync()
        do { try await Task.sleep(for: .seconds(10)) } catch { return }
      }
    }
  }
}

struct WatchSettingsPage: View {
  @EnvironmentObject private var store: WatchStore
  var body: some View {
    Form {
      Section {
        Picker("默认消费码", selection: Binding(
          get: { store.prefersOnline }, set: { store.setOnlinePreferred($0) }
        )) {
          Text("在线码").tag(true)
          Text("离线码").tag(false)
        }
        .accessibilityIdentifier("watch-default-payment-code")
      } footer: {
        Text(store.prefersOnline
          ? "网络状况差时将自动使用离线码。"
          : "任何情况下都使用离线码。")
      }
      Section {
        Toggle("自动检查消费结果", isOn: Binding(
          get: { store.automaticallyChecksPayments }, set: { store.setAutomaticPaymentChecking($0) }
        ))
        .accessibilityIdentifier("watch-auto-payment-check")
      } footer: {
        Text("仅在在线码页面可见时检查，成功后提示并换码。关闭后仍会定时刷新在线码。")
      }
    }
    .navigationTitle("设置")
  }
}

struct CampusCardPages: View {
  @EnvironmentObject private var store: WatchStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var page = 0
  var body: some View {
    TabView(selection: $page) {
      PaymentPage(active: page == 0 && scenePhase == .active).tag(0)
      CardInfoPage().tag(1)
    }
    .tabViewStyle(.verticalPage)
    .containerBackground(for: .navigation) { WatchArtwork() }
    .tint(WatchPalette.ink)
    .toolbarColorScheme(.light, for: .navigationBar)
    .onAppear {
      #if DEBUG && targetEnvironment(simulator)
      if ProcessInfo.processInfo.arguments.contains("--preview-info") { page = 1 }
      #endif
      store.requestSync()
    }
    .task(id: page == 0 && scenePhase == .active) {
      let active = page == 0 && scenePhase == .active
      store.setCodeVisible(active)
    }
    .onDisappear { store.setCodeVisible(false) }
  }
}

private struct WatchArtwork: View {
  var body: some View {
    ZStack(alignment: .bottom) {
      WatchPalette.paper
      BundledArtwork(name: "widget-background")
    }.ignoresSafeArea()
  }
}

private struct BundledArtwork: View {
  let name: String
  var body: some View {
    if let url = Bundle.main.url(forResource: name, withExtension: "png"),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: 512,
        kCGImageSourceShouldCacheImmediately: true,
      ] as CFDictionary) {
      Image(decorative: image, scale: 1).resizable().scaledToFit()
    }
  }
}

private struct PaymentPage: View {
  let active: Bool
  @EnvironmentObject private var store: WatchStore
  @Environment(\.displayScale) private var displayScale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private enum Phase { case status, code, success }
  private var phase: Phase {
    if store.paymentConfirmation != nil { return .success }
    return store.matrix == nil ? .status : .code
  }
  var body: some View {
    GeometryReader { geometry in
      ZStack {
        if let confirmation = store.paymentConfirmation {
          PaymentSuccessView(amountFen: confirmation.amountFen)
            .transition(.opacity)
        } else if let matrix = store.matrix {
          let side = min(geometry.size.width - 8, geometry.size.height - 24)
          Button { store.manuallyRefreshCode() } label: {
            VStack(spacing: 6) {
              ZStack {
                Canvas { context, size in
                  let step = floor(min(size.width, size.height) * displayScale / Double(matrix.side)) / displayScale
                  let origin = (size.width - step * Double(matrix.side)) / 2
                  var path = Path()
                  for y in 0..<matrix.side { for x in 0..<matrix.side where matrix.modules[y * matrix.side + x] != 0 {
                    path.addRect(CGRect(x: origin + Double(x) * step, y: origin + Double(y) * step, width: step, height: step))
                  } }
                  context.fill(path, with: .color(WatchPalette.red), style: FillStyle(antialiased: false))
                }
                .id(store.display.codeRevision)
                .transition(.opacity)
              }
              .frame(width: max(1, side), height: max(1, side)).accessibilityHidden(true)
              .animation(active && !reduceMotion ? .easeInOut(duration: 0.2) : nil, value: store.display.codeRevision)
              HStack(spacing: 4) {
                if store.generating {
                  ProgressView().progressViewStyle(.circular).controlSize(.mini)
                    .frame(width: 12, height: 12)
                }
                Text(store.generating ? "正在获取消费码" : store.codeLabel)
              }
              .font(.caption2).foregroundStyle(WatchPalette.secondary).tint(WatchPalette.red)
              .frame(height: 14).offset(y: -4)
            }
          }
          .buttonStyle(.plain)
          .allowsHitTesting(!store.generating)
          .accessibilityLabel(store.generating ? "正在获取消费码" : "\(store.codeLabel)，点击刷新")
          .accessibilityIdentifier("refresh-payment-code")
          .transition(.asymmetric(insertion: .opacity, removal: .identity))
        } else {
          VStack(spacing: 12) {
            Image(systemName: "qrcode").font(.largeTitle).foregroundStyle(WatchPalette.red)
            Text(store.codeMessage ?? (store.requiresAuthorization ? "请在手机同步校园卡授权" : "正在获取消费码"))
              .font(.footnote).multilineTextAlignment(.center)
            if store.requiresAuthorization {
              Button("同步授权") { store.requestSync() }.tint(WatchPalette.red)
            } else if store.generating || store.codeMessage == nil {
              ProgressView().progressViewStyle(.circular).controlSize(.small)
                .frame(width: 20, height: 20).tint(WatchPalette.red)
            } else { Button("重试") { store.manuallyRefreshCode() }.tint(WatchPalette.red) }
          }
          .padding(.horizontal, 14)
          .foregroundStyle(WatchPalette.ink)
          .transition(.opacity)
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
      .animation(active && !reduceMotion ? .easeInOut(duration: 0.24) : nil, value: phase)
    }
    .ignoresSafeArea(.container, edges: .bottom)
    .task(id: store.paymentConfirmation?.id) {
      guard let id = store.paymentConfirmation?.id else { return }
      do { try await Task.sleep(for: .seconds(3)) } catch { return }
      store.dismissPaymentConfirmation(id)
    }
  }
}

private struct PaymentSuccessView: View {
  let amountFen: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var progress = 0.0
  @State private var hapticPulse = 0
  @State private var started = false
  var body: some View {
    VStack(spacing: 10) {
      Color.clear.frame(width: 72, height: 72)
        .modifier(SuccessCheckAnimation(progress: progress, reduceMotion: reduceMotion))
        .accessibilityHidden(true)
      Text("¥\(String(format: "%.2f", Double(amountFen) / 100))")
        .font(.system(size: 30, weight: .semibold)).monospacedDigit()
      Text("支付成功").font(.footnote).foregroundStyle(WatchPalette.red.opacity(0.62))
    }
    .foregroundStyle(WatchPalette.red)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("watch-payment-success")
    // Impact feedback supplies the taps without requesting the success alert tone.
    .sensoryFeedback(.impact, trigger: hapticPulse)
    .task {
      guard !started else { return }
      started = true
      withAnimation(.linear(duration: reduceMotion ? 0.24 : 0.72)) { progress = 1 }
      hapticPulse = 1
      do { try await Task.sleep(nanoseconds: 140_000_000) } catch { return }
      hapticPulse = 2
    }
  }
}

/// Matches AnimatedSuccessCheck's paths, intervals and easing in the iOS app.
private struct SuccessCheckAnimation: AnimatableModifier {
  var progress: Double
  let reduceMotion: Bool
  var animatableData: Double { get { progress } set { progress = newValue } }
  private static let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.215, y: 0.61),
    endControlPoint: UnitPoint(x: 0.355, y: 1))

  func body(content: Content) -> some View {
    let circle = Self.curve.value(at: min(1, max(0, progress / 0.58)))
    let check = Self.curve.value(at: min(1, max(0, (progress - 0.42) / 0.46)))
    let eased = Self.curve.value(at: min(1, max(0, progress)))
    let scale = eased <= 0.72 ? 0.84 + 0.23 * eased / 0.72 : 1.07 - 0.07 * (eased - 0.72) / 0.28
    return content.overlay {
      SuccessCheckPath(circleProgress: circle, checkProgress: check)
        .stroke(WatchPalette.red, style: StrokeStyle(lineWidth: 72 * 0.075, lineCap: .round, lineJoin: .round))
    }.scaleEffect(reduceMotion ? 1 : scale)
  }
}

private struct SuccessCheckPath: Shape {
  let circleProgress: Double
  let checkProgress: Double
  func path(in rect: CGRect) -> Path {
    var path = Path()
    if circleProgress > 0 {
      path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width * (1 - 0.075) / 2,
        startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * circleProgress), clockwise: false)
    }
    var check = Path()
    check.move(to: CGPoint(x: rect.width * 0.28, y: rect.height * 0.53))
    check.addLine(to: CGPoint(x: rect.width * 0.44, y: rect.height * 0.68))
    check.addLine(to: CGPoint(x: rect.width * 0.75, y: rect.height * 0.35))
    path.addPath(check.trimmedPath(from: 0, to: checkProgress))
    return path
  }
}

private struct CardInfoPage: View {
  @EnvironmentObject private var store: WatchStore
  private static let updateFormat: DateFormatter = {
    let format = DateFormatter()
    format.locale = Locale(identifier: "zh_CN")
    format.dateFormat = "MM-dd HH:mm"
    return format
  }()
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer(minLength: 0)
      if let card = store.snapshot?.card, store.snapshot?.enabled == true {
        VStack(alignment: .leading, spacing: 3) {
          Text(card.name).font(.title2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
          Text(card.studentID).font(.footnote).monospacedDigit().foregroundStyle(WatchPalette.secondary)
          Capsule().fill(WatchPalette.red.opacity(0.3)).frame(width: 24, height: 2).padding(.vertical, 9)
          Text("余额").font(.caption2).foregroundStyle(WatchPalette.secondary)
          Text("¥\(String(format: "%.2f", Double(store.balanceFen ?? card.balanceFen) / 100))")
            .font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
            .foregroundStyle(WatchPalette.red).lineLimit(1).minimumScaleFactor(0.65)
          if let time = store.balanceUpdatedAt {
            Text("更新于 \(Self.updateFormat.string(from: Date(timeIntervalSince1970: time)))")
              .font(.system(size: 10)).foregroundStyle(WatchPalette.secondary).padding(.top, 8)
          } else { Text("等待手机更新").font(.caption2).foregroundStyle(WatchPalette.secondary).padding(.top, 8) }
        }
      } else {
        Text("请在手机同步校园卡信息").font(.footnote)
        Button("同步信息") { store.requestSync() }.padding(.top, 12).tint(WatchPalette.red)
      }
      Spacer(minLength: 0)
    }
    .foregroundStyle(WatchPalette.ink)
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}
