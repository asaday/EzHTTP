// swift-tools-version:5.0
import PackageDescription

let package = Package(
	name: "EzHTTP",
	platforms: [
		.macOS(.v10_11), .iOS(.v9), .tvOS(.v9), .watchOS(.v2),
	],
	products: [
		.library(name: "EzHTTP", targets: ["EzHTTP"]),
	],
	targets: [
		.target(name: "EzHTTP", dependencies: []),
	],
	swiftLanguageVersions: [.v5]
)
