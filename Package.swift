// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShiftDrop",
    platforms: [.macOS(.v14)],
    targets: [
        // File conversion and tool logic. No UI, so it can be unit tested.
        .target(
            name: "ShiftDropCore",
            path: "Sources/ShiftDropCore"
        ),
        // The menu bar app: drag detection, the ring menu and editor windows.
        .executableTarget(
            name: "ShiftDrop",
            dependencies: ["ShiftDropCore"],
            path: "Sources/ShiftDrop"
        ),
        .testTarget(
            name: "ShiftDropCoreTests",
            dependencies: ["ShiftDropCore"],
            path: "Tests/ShiftDropCoreTests"
        ),
    ]
)
