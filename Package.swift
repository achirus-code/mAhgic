// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "mAhgic",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mAhgic", targets: ["mAhgic"]),
        .executable(name: "mahcli", targets: ["mahcli"]),
    ],
    targets: [
        .target(
            name: "mAhgicCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Security"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(name: "mAhgic", dependencies: ["mAhgicCore"]),
        .executableTarget(name: "mahcli", dependencies: ["mAhgicCore"]),
    ]
)
