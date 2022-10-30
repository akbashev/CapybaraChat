import Distributed
import Logging
import NIO
import Foundation
import Vapor
import Database
import ActorSystems
import Actors
import GRDB

#if DEBUG
  let numberOfThreads = 1
#else
  let numberOfThreads = System.coreCount
#endif

let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)

public func configure(_ app: Application) async throws {
  let database = try await liveDB()
  let system = try ClientServerActorSystem(
    mode: .server(
      host: "localhost",
      port: 8888,
      protocol: .ws
    )
  )
  system.registerOnDemandResolveHandler { actorId in
    // We create new BotPlayers "ad-hoc" as they are requested for.
    // Subsequent resolves are able to resolve the same instance.
    switch actorId {
      case .full(let id, _, _, _):
        switch id.type {
          case String(describing: User.self):
            return system
              .makeActorWithID(actorId) {
                return User(
                  actorSystem: system,
                  database: database.users,
                  userId: .init(rawValue: id._id)
                )
              }
          case String(describing: Room.self):
            return system
              .makeActorWithID(actorId) {
                return Room(
                  actorSystem: system,
                  database: database.rooms,
                  roomId: .init(rawValue: id._id)
                )
              }
          default:
            return nil
        }
      default:
        return nil
    }

  }
}

private func liveDB() async throws -> DatabaseClient {
  let path = NSSearchPathForDirectoriesInDomains(
    .applicationSupportDirectory,
    .userDomainMask,
    true
  ).first! + "/CapybaraChat"
  try FileManager.default.createDirectory(
    atPath: path,
    withIntermediateDirectories: true,
    attributes: nil
  )
  return try await DatabaseClient
    .live(path: "\(path)/db.sqlite3")
}

private func memoryDB() async throws -> DatabaseClient {
  try await DatabaseClient.memory()
}
