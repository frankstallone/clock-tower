// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClockTower",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "ClockTower", targets: ["ClockTowerApp"])],
    targets: [
        .target(name: "ClockTowerCore", resources: [.process("Resources")]),
        .executableTarget(name: "ClockTowerApp", dependencies: ["ClockTowerCore"]),
        .testTarget(name: "ClockTowerCoreTests", dependencies: ["ClockTowerCore"]),
    ]
)
