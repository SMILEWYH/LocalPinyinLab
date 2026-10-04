// swift-tools-version: 6.0
import PackageDescription

let probes = ["InputSourceTool.swift", "InspectPrivate.m", "MenuIcon.swift", "TranslationSetup.swift"]
func probe(_ name: String, file: String, dependencies: [Target.Dependency] = []) -> Target {
    .executableTarget(name: name, dependencies: dependencies, path: "Probes", exclude: probes.filter { $0 != file }, sources: [file])
}

let package = Package(
    name: "LocalPinyinLab",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "PinyinCore", targets: ["PinyinCore"]),
        .library(name: "PinyinApplication", targets: ["PinyinApplication"]),
        .executable(name: "LocalPinyin", targets: ["LocalPinyin"])
    ],
    targets: [
        .target(name: "PinyinCore"),
        .target(name: "PinyinApplication", dependencies: ["PinyinCore"]),
        .target(name: "PinyinInfrastructure", dependencies: ["PinyinCore", "PinyinApplication"]),
        .target(name: "PinyinPresentation", dependencies: ["PinyinCore", "PinyinApplication"]),
        .executableTarget(name: "LocalPinyin", dependencies: ["PinyinCore", "PinyinApplication", "PinyinInfrastructure", "PinyinPresentation"]),
        probe("inputsource-tool", file: "InputSourceTool.swift"),
        probe("menu-icon", file: "MenuIcon.swift"),
        probe("TranslationSetup", file: "TranslationSetup.swift")
    ]
)
