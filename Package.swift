// swift-tools-version: 6.0
import PackageDescription
// The macOS application lives in IconShadow.xcodeproj; SPM runs the isolated engine tests.
let package = Package(
    name: "IconShadow", platforms: [.macOS(.v14)],
    products: [.library(name: "IconShadowCore", targets: ["IconShadowCore"])],
    targets: [.target(name: "IconShadowCore"),
              .testTarget(name: "IconShadowCoreTests", dependencies: ["IconShadowCore"])])
