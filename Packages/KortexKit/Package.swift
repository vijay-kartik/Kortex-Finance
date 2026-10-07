// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KortexKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KortexKit", targets: ["KortexKit", "KortexCloud", "KortexFinance", "KortexAI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "12.0.0"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "9.0.0"),
    ],
    targets: [
        // Screens and theme.
        .target(
            name: "KortexKit",
            dependencies: ["KortexFinance", "KortexCloud", "KortexAI"],
            resources: [.copy("Resources/Fonts")]
        ),
        // Finance models, document decoding and balance rules. Plain Swift, no Firebase.
        .target(name: "KortexFinance"),
        // Vercel AI Gateway: the key in the Keychain, and chat completions with images and JSON schemas.
        .target(name: "KortexAI"),
        // Sign-in, Firestore listeners, App Check and the finance key.
        .target(
            name: "KortexCloud",
            dependencies: [
                "KortexFinance",
                .product(name: "FirebaseAppCheck", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFunctions", package: "firebase-ios-sdk"),
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
            ],
            // Firebase and GoogleSignIn types aren't Sendable-annotated; Swift 6 mode would flag every callback.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "KortexKitTests", dependencies: ["KortexKit"]),
        .testTarget(name: "KortexFinanceTests", dependencies: ["KortexFinance"]),
    ]
)
