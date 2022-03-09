// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "MMMObservables",
    platforms: [
        .iOS(.v11),
        .watchOS(.v3),
        .tvOS(.v10)
    ],
    products: [
        .library(
            name: "MMMObservables",
            targets: ["MMMObservables"]
		)
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MMMObservablesObjC",
            dependencies: [],
            path: "Sources/MMMObservablesObjC"
		),
        .target(
            name: "MMMObservables",
            dependencies: ["MMMObservablesObjC"],
            path: "Sources/MMMObservables"
		),
        .testTarget(
            name: "MMMObservablesTests",
            dependencies: ["MMMObservables"],
            path: "Tests"
		)
    ]
)

