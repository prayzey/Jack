// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Gilt",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.1"),
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.12.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "9.8.0"),
        // Local-only meeting AI stack. All three pull pre-converted models from
        // public Hugging Face repos at runtime — nothing self-hosted.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.16.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.13.6"),
        .package(url: "https://github.com/obra/LLM.swift.git", branch: "main"),
        // Ogg-Opus decoder. WhatsApp/Telegram/Signal voice notes ship as
        // Ogg-encapsulated Opus, which AVFoundation can't read — this converts
        // them to .m4a so the existing WhisperKit/FluidAudio file path works.
        .package(url: "https://github.com/element-hq/swift-ogg", from: "0.0.4"),
    ],
    targets: [
        .executableTarget(
            name: "Gilt",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "LLM", package: "LLM.swift"),
                .product(name: "SwiftOGG", package: "swift-ogg"),
            ],
            exclude: [
                "App/CLAUDE.md",
                "App/AGENTS.md",
                "Views/CLAUDE.md",
                "Views/AGENTS.md",
                "Services/CLAUDE.md",
                "Services/AGENTS.md",
                "Models/CLAUDE.md",
                "Models/AGENTS.md",
            ],
            resources: [
                .copy("Resources"),
                .process("Localization")
            ]
        ),
        .testTarget(
            name: "JackTests",
            dependencies: ["Gilt"],
            // Binary audio fixture loaded by path (#filePath) in
            // AudioFileTranscriptionTests — not a bundled resource.
            exclude: ["Fixtures"]
        ),
    ]
)
