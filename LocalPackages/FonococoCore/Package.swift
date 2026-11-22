// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "FonococoCore",
    platforms: [.iOS(.v17)],
    products: [.library(name: "FonococoCore", targets: ["FonococoCore"])],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "12.0.0"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "9.0.0")
    ],
    targets: [.target(name: "FonococoCore", dependencies: [
        .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
        .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
        .product(name: "FirebaseDatabase", package: "firebase-ios-sdk"),
        .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS")
    ], path: "Sources")],
    swiftLanguageVersions: [.v5]
)
