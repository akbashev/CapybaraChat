// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "CapybaraChat",
  platforms: [
    // we require the 'distributed actor' language and runtime feature:
    .iOS(.v16),
    .macOS(.v13),
    .tvOS(.v16),
    .watchOS(.v9),
  ],
  products: [
    // Products define the executables and libraries a package produces, and make them visible to other packages.
    .executable(name: "server", targets: ["server"]),
    //
    .library(name: "ActorSystems", targets: ["ActorSystems"]),
    .library(name: "Actors", targets: ["Actors"]),
    .library(name: "Database", targets: ["Database"]),
    .library(name: "Main", targets: ["Main"])
  ],
  dependencies: [
    // Dependencies declare other packages that this package depends on.
    // .package(url: /* package url */, from: "1.0.0"),
    .package(
      url: "https://github.com/vapor/vapor.git",
      from: "4.65.1"
    ),
    .package(
      url: "https://github.com/apple/swift-nio.git",
      from: "2.41.1"
    ),
    .package(
      url: "https://github.com/apple/swift-nio-transport-services.git",
      from: "1.13.1"
    ),
    .package(
      url: "https://github.com/groue/GRDB.swift.git",
      from: "6.0.0"
    ),
    .package(
      url: "https://github.com/apple/swift-async-algorithms.git",
      from: "0.0.3"
    )
  ],
  targets: [
    // Targets are the basic building blocks of a package. A target can define a module or a test suite.
    // Targets can depend on other targets in this package, and on products in packages this package depends on.
    .executableTarget(
      name: "server",
      dependencies: [
        .product(name: "Vapor", package: "vapor"),
        "ActorSystems",
        "Actors"
      ],
      path: "Sources/server"
    ),
    .target(
      name: "ActorSystems",
      dependencies: [
        .product(name: "NIO", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
        .product(name: "NIOWebSocket", package: "swift-nio"),
        .product(name: "NIOTransportServices", package: "swift-nio-transport-services")
      ]
    ),
    .target(
      name: "Actors",
      dependencies: [
        "ActorSystems",
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
        "Database"
      ]
    ),
    .target(
      name: "Database",
      dependencies: [
        .product(
          name: "GRDB",
          package: "GRDB.swift"
        )
      ]
    ),
    .target(
      name: "Main",
      dependencies: [
        "Actors"
      ]
    ),
    .testTarget(
      name: "CapybaraChatTests",
      dependencies: [
        "Actors"
      ]
    ),
  ]
)
