import GRDB
import Foundation

public struct UserDatabaseClient {
  public let getUser: (String) async throws -> (Models.User?)
  public let updateUser: (Models.User) async throws -> ()
}

extension UserDatabaseClient {
  public enum Error: Swift.Error {
    case dbPathError
    case notFound
    case alreadyExists
  }
}

extension UserDatabaseClient {
  struct User: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    let name: String
  }
}

extension UserDatabaseClient.User: TableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
  
  static let rooms = hasMany(RoomDatabaseClient.UserRoom.self)
  var rooms: QueryInterfaceRequest<RoomDatabaseClient.UserRoom> {
    request(for: UserDatabaseClient.User.rooms)
  }
  static let messages = hasMany(RoomDatabaseClient.Message.self)
  var messages: QueryInterfaceRequest<RoomDatabaseClient.Message> {
    request(for: UserDatabaseClient.User.messages)
  }
}

extension UserDatabaseClient {
  
  internal static func grdb(
    _ dbQueue: DatabaseQueue
  ) -> UserDatabaseClient {
    let getUser: (String) async throws -> (Models.User?) = { user in
      try await dbQueue.read { db in
        guard let user = try UserDatabaseClient.User
          .including(optional: UserDatabaseClient.User.rooms)
          .filter(Column("name") == user)
          .fetchOne(db)
        else { throw UserDatabaseClient.Error.notFound }
        let rooms = try user
          .rooms
          .fetchAll(db)
          .compactMap {
            try $0.room.fetchOne(db)
          }
          .map {
            $0.name
          }
        return .init(
          name: user.name,
          roomId: nil
        )
      }
    }
    let updateUser: (Models.User) async throws -> () = { user in
      try await dbQueue.write { db in
        try UserDatabaseClient.User
          .init(
            id: nil,
            name: user.name
          )
          .insert(db)
      }
    }
    return UserDatabaseClient(
      getUser: getUser,
      updateUser: updateUser
    )
  }
  
}
