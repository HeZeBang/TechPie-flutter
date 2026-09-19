// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "WatchSupport",
  platforms: [.macOS(.v13), .iOS(.v13), .watchOS(.v10)],
  products: [.library(name: "WatchSupport", targets: ["WatchSupport"])],
  targets: [
    .target(name: "CWatchCrypto", exclude: ["gmssl/LICENSE"],
      cSettings: [.headerSearchPath("gmssl/include"), .headerSearchPath("qrcodegen"), .unsafeFlags(["-UDEBUG", "-DDEBUG=0"])],
      linkerSettings: [.linkedFramework("Security")]),
    .target(name: "WatchSupport", dependencies: ["CWatchCrypto"]),
    .testTarget(name: "WatchSupportTests", dependencies: ["WatchSupport"], resources: [.copy("Fixtures")]),
  ]
)
