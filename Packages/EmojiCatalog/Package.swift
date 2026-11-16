// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "EmojiCatalog",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "EmojiCatalog", targets: ["EmojiCatalog"]),
    .executable(name: "generate-emoji-catalog", targets: ["EmojiCatalogGenerator"]),
  ],
  targets: [
    .target(
      name: "EmojiCatalog",
      resources: [.copy("Resources/Emoji")]
    ),
    .executableTarget(
      name: "EmojiCatalogGenerator",
      dependencies: ["EmojiCatalog"]
    ),
    .testTarget(
      name: "EmojiCatalogTests",
      dependencies: ["EmojiCatalog"]
    ),
    .testTarget(
      name: "EmojiCatalogGeneratorTests",
      dependencies: ["EmojiCatalogGenerator", "EmojiCatalog"]
    ),
  ]
)
