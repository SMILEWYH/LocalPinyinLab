// swift-tools-version: 6.0
import PackageDescription

let probes = ["InputSourceTool.swift", "InspectPrivate.m", "MenuIcon.swift", "SettingsIcon.swift"]
func probe(_ name: String, file: String, dependencies: [Target.Dependency] = []) -> Target {
    .executableTarget(name: name, dependencies: dependencies, path: "Probes", exclude: probes.filter { $0 != file }, sources: [file])
}

let package = Package(
    name: "LocalPinyinLab",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "PinyinCore", targets: ["PinyinCore"]),
        .library(name: "PinyinApplication", targets: ["PinyinApplication"]),
        .executable(name: "LocalPinyin", targets: ["LocalPinyin"]),
        .executable(name: "PinyinSettings", targets: ["PinyinSettings"])
    ],
    targets: [
        .target(name: "PinyinCore"),
        .target(name: "PinyinApplication", dependencies: ["PinyinCore"]),
        .target(name: "PinyinInfrastructure", dependencies: ["PinyinCore", "PinyinApplication"]),
        .target(name: "PinyinPresentation", dependencies: ["PinyinCore", "PinyinApplication"]),
        .executableTarget(name: "LocalPinyin", dependencies: ["PinyinCore", "PinyinApplication", "PinyinInfrastructure", "PinyinPresentation"]),
        .executableTarget(name: "input-checks", dependencies: ["PinyinCore", "PinyinApplication"], path: "Tests/InputChecks"),
        .executableTarget(name: "worker-checks", dependencies: ["PinyinCore", "PinyinInfrastructure"], path: "Tests/WorkerChecks"),
        .executableTarget(name: "presentation-checks", dependencies: ["PinyinCore", "PinyinApplication", "PinyinPresentation"], path: "Tests/PresentationChecks"),
        probe("inputsource-tool", file: "InputSourceTool.swift"),
        probe("menu-icon", file: "MenuIcon.swift"),
        probe("settings-icon", file: "SettingsIcon.swift"),
        .executableTarget(name: "PinyinSettings", dependencies: ["PinyinCore", "PinyinInfrastructure"], path: "Tools/PinyinSettings"),
        .testTarget(name: "PinyinSettingsTests", dependencies: ["PinyinSettings", "PinyinCore"])
    ]
)
