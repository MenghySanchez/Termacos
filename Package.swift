// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TermacosSSH",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.7")
    ],
    targets: [
        .executableTarget(
            name: "TermacosSSH",
            dependencies: ["SwiftTerm"],
            path: "Sources/TermacosSSH"
        )
    ]
)
