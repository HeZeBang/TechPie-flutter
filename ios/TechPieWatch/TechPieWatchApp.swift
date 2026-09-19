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
        }.padding(.horizontal, 4)
      }
      .navigationDestination(for: String.self) { _ in CampusCardPages() }
      .onAppear {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--preview-pay") || ProcessInfo.processInfo.arguments.contains("--preview-info") { path = ["campusCard"] }
        #endif
      }
    }
    .task(id: scenePhase == .active) {
      let active = scenePhase == .active
      store.setCodeVisible(active)
      guard active else { return }
      while !Task.isCancelled {
        store.requestSync()
        do { try await Task.sleep(for: .seconds(10)) } catch { return }
      }
    }
  }
}

struct CampusCardPages: View {
  @EnvironmentObject private var store: WatchStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var page = 0
  var body: some View {
    TabView(selection: $page) {
      PaymentPage().tag(0)
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
      guard active else { return }
      store.refreshCode()
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(30)) } catch { return }
        store.refreshCode()
      }
    }
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
  @EnvironmentObject private var store: WatchStore
  @Environment(\.displayScale) private var displayScale
  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        Spacer(minLength: 0)
        if let matrix = store.matrix {
          let side = min(geometry.size.width - 8, geometry.size.height - 24)
          Button { store.refreshCode() } label: {
            VStack(spacing: 6) {
              Canvas { context, size in
                let step = floor(min(size.width, size.height) * displayScale / Double(matrix.side)) / displayScale
                let origin = (size.width - step * Double(matrix.side)) / 2
                var path = Path()
                for y in 0..<matrix.side { for x in 0..<matrix.side where matrix.modules[y * matrix.side + x] != 0 {
                  path.addRect(CGRect(x: origin + Double(x) * step, y: origin + Double(y) * step, width: step, height: step))
                } }
                context.fill(path, with: .color(WatchPalette.red), style: FillStyle(antialiased: false))
              }.frame(width: max(1, side), height: max(1, side)).accessibilityHidden(true)
              Text("离线消费码").font(.caption2).foregroundStyle(WatchPalette.secondary)
                .offset(y: -4)
            }
          }
          .buttonStyle(.plain)
          .accessibilityLabel("离线消费码，点击刷新")
          .accessibilityIdentifier("refresh-offline-code")
        } else {
          VStack(spacing: 12) {
            Image(systemName: "qrcode").font(.largeTitle).foregroundStyle(WatchPalette.red)
            Text(store.codeMessage ?? (store.requiresAuthorization ? "请在手机同步离线授权" : "正在生成消费码"))
              .font(.footnote).multilineTextAlignment(.center)
            if store.requiresAuthorization {
              Button("同步授权") { store.requestSync() }.tint(WatchPalette.red)
            } else if store.generating || store.codeMessage == nil {
              ProgressView().tint(WatchPalette.red)
            } else { Button("重试") { store.refreshCode() }.tint(WatchPalette.red) }
          }.padding(.horizontal, 14).foregroundStyle(WatchPalette.ink)
        }
        Spacer(minLength: 0)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .ignoresSafeArea(.container, edges: .bottom)
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
          Text("¥\(String(format: "%.2f", Double(card.balanceFen) / 100))")
            .font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
            .foregroundStyle(WatchPalette.red).lineLimit(1).minimumScaleFactor(0.65)
          if let time = card.updatedAt {
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
