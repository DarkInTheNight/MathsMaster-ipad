// swift-tools-version: 6.0

// MathsMaster: a Swift Playgrounds app project.
// Owned by the repo: change it here (in git), not through Playgrounds' settings UI,
// so Playgrounds never rewrites it and drops keys.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "MMTestA",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .iOSApplication(
            name: "MMTestA",
            targets: ["AppModule"],
            bundleIdentifier: "com.darkinthenight.mmtest.a",
            displayVersion: "0.1",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .leaf),
            accentColor: .presetColor(.teal),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ],
    swiftLanguageModes: [.v5]
)
