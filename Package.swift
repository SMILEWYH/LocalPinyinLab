// swift-tools-version: 6.0
import PackageDescription

let probes = ["IMKCompileProbe.swift", "InputSourceTool.swift", "InspectPrivate.m", "MenuIcon.swift", "Preview.swift", "TranslationProbe.swift", "TranslationSetup.swift"]
func probe(_ name: String, file: String, dependencies: [Target.Dependency] = []) -> Target {
    .executableTarget(name: name, dependencies: dependencies, path: "Probes", exclude: probes.filter { $0 != file }, sources: [file])
}

let integrationFiles = ["CompositionTests.swift", "PerformanceTests.swift", "SingleInstanceTests.swift", "SpeechTests.swift", "WorkerTimeoutTest.swift", "UnresponsiveWorker.c", "PinyinCoreTests", "PinyinApplicationTests", "PinyinInfrastructureTests", "PinyinPresentationTests"]
func integration(_ name: String, file: String, dependencies: [Target.Dependency]) -> Target {
    .executableTarget(name: name, dependencies: dependencies,
                      path: "Tests", exclude: integrationFiles.filter { $0 != file }, sources: [file])
}

let package = Package(
    name: "LocalPinyinLab",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "PinyinCore", targets: ["PinyinCore"]),
        .library(name: "PinyinApplication", targets: ["PinyinApplication"]),
        .executable(name: "LocalPinyin", targets: ["LocalPinyin"]),
        .library(name: "IMKCompileProbe", type: .dynamic, targets: ["IMKCompileProbe"])
    ],
    targets: [
        .target(name: "PinyinCore"),
        .target(name: "PinyinApplication", dependencies: ["PinyinCore"]),
        .target(name: "PinyinInfrastructure", dependencies: ["PinyinCore", "PinyinApplication"]),
        .target(name: "PinyinPresentation", dependencies: ["PinyinCore", "PinyinApplication"]),
        .executableTarget(name: "LocalPinyin", dependencies: ["PinyinCore", "PinyinApplication", "PinyinInfrastructure", "PinyinPresentation"]),
        .target(name: "IMKCompileProbe", dependencies: ["PinyinCore"], path: "Probes", exclude: probes.filter { $0 != "IMKCompileProbe.swift" }, sources: ["IMKCompileProbe.swift"]),
        probe("translation-probe", file: "TranslationProbe.swift", dependencies: ["PinyinInfrastructure"]),
        probe("candidate-preview", file: "Preview.swift", dependencies: ["PinyinCore", "PinyinPresentation"]),
        probe("inputsource-tool", file: "InputSourceTool.swift"),
        probe("menu-icon", file: "MenuIcon.swift"),
        probe("TranslationSetup", file: "TranslationSetup.swift"),
        integration("composition-tests", file: "CompositionTests.swift", dependencies: ["PinyinCore", "PinyinInfrastructure"]),
        integration("performance-tests", file: "PerformanceTests.swift", dependencies: ["PinyinCore", "PinyinInfrastructure"]),
        integration("single-instance-tests", file: "SingleInstanceTests.swift", dependencies: ["PinyinInfrastructure"]),
        integration("speech-tests", file: "SpeechTests.swift", dependencies: ["PinyinCore", "PinyinApplication", "PinyinInfrastructure"]),
        integration("worker-timeout-test", file: "WorkerTimeoutTest.swift", dependencies: ["PinyinInfrastructure"]),
        .target(name: "TestSupport"),
        .executableTarget(name: "PinyinCoreTests", dependencies: ["PinyinCore", "TestSupport"], path: "Tests/PinyinCoreTests"),
        .executableTarget(name: "TranslationServiceTests", dependencies: ["PinyinApplication", "TestSupport"], path: "Tests/PinyinApplicationTests", exclude: ["ReturnKeyTests.swift"], sources: ["TranslationServiceTests.swift"]),
        .executableTarget(name: "InputSessionTests", dependencies: ["PinyinCore", "PinyinApplication", "TestSupport"], path: "Tests/PinyinApplicationTests", exclude: ["TranslationServiceTests.swift"], sources: ["ReturnKeyTests.swift"]),
        .executableTarget(name: "PinyinInfrastructureTests", dependencies: ["PinyinCore", "PinyinInfrastructure", "TestSupport"], path: "Tests/PinyinInfrastructureTests"),
        .executableTarget(name: "PinyinPresentationTests", dependencies: ["PinyinApplication", "PinyinPresentation", "TestSupport"], path: "Tests/PinyinPresentationTests")
    ]
)
