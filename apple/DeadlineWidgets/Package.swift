// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "DeadlineWidgetSupport",
  platforms: [.macOS(.v10_15), .iOS(.v15)],
  products: [.library(name: "DeadlineWidgetSupport", targets: ["DeadlineWidgetSupport"])],
  targets: [
    .target(name: "DeadlineWidgetSupport"),
    .testTarget(name: "DeadlineWidgetSupportTests", dependencies: ["DeadlineWidgetSupport"]),
  ]
)
