import Distributed
import Logging
import NIO
import Foundation
import Models
import Vapor
import Database
import ActorSystems
import Connection
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
  let serverConnectionClient = ServerConnectionClient(
    clusterSystem: system
  )
  system.registerOnDemandResolveHandler { actorId in
    // We create new BotPlayers "ad-hoc" as they are requested for.
    // Subsequent resolves are able to resolve the same instance.
    switch actorId {
      case .simple:
        return .none
      case .full(let id, _, _, _):
        switch id.type {
          case String(describing: User.self):
            return system
              .makeActorWithID(actorId) {
                return UserConnection(
                  actorSystem: system,
                  database: database.users
                )
              }
          case String(describing: UserRoomConnection.UserRoom.self):
            guard let userName = UserRoomConnection.UserRoom.user(for: id._id)
            else { return .none }
            return system
              .makeActorWithID(actorId) {
                return UserRoomConnection(
                  actorSystem: system,
                  client: serverConnectionClient,
                  name: .init(rawValue: userName)
                )
              }
          case String(describing: Room.self):
            return system
              .makeActorWithID(actorId) {
                return RoomConnection(
                  actorSystem: system,
                  database: database.rooms
                )
              }
          default:
            return nil
        }
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
