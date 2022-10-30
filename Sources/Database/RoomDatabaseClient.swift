import GRDB
import Foundation

public struct RoomDatabaseClient {
  public typealias UserRoomPair = (user: String, room: String)
  
  public let getRoom: (String) async throws -> (Models.Room)
  public let updateRoom: (Models.Room) async throws -> ()
  public let updateStatus: (Int, UserRoomPair) async throws -> ()
  public let addGuest: (UserRoomPair) async throws -> ()
  public let addMessage: (Models.Message, UserRoomPair) async throws -> ()
}

extension RoomDatabaseClient {
  public enum Error: Swift.Error {
    case dbPathError
    case notFound
    case alreadyExists
  }
}

extension RoomDatabaseClient {
  struct Room: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    let name: String
  }
  
  struct Message: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    let createdAt: Date
    let text: String
    let userId: Int64
    let roomId: Int64
  }
  
  struct UserRoom: Codable, FetchableRecord, PersistableRecord {
    enum Status: Int, Codable {
      case online
      case offline
      case texting
    }
    
    var status: Status
    let userId: Int64
    let roomId: Int64
  }
}

// Oof
extension RoomDatabaseClient.UserRoom: TableRecord {
  static let room = belongsTo(RoomDatabaseClient.Room.self, using: .init(["roomId"]))
  var room: QueryInterfaceRequest<RoomDatabaseClient.Room> {
    request(for: RoomDatabaseClient.UserRoom.room)
  }
  static let guest = belongsTo(UserDatabaseClient.User.self, using: .init(["userId"]))
  var guest: QueryInterfaceRequest<UserDatabaseClient.User> {
    request(for: RoomDatabaseClient.UserRoom.guest)
  }
}

extension RoomDatabaseClient.Room: TableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
  
  static let guests = hasMany(RoomDatabaseClient.UserRoom.self)
  var guests: QueryInterfaceRequest<RoomDatabaseClient.UserRoom> {
    request(for: RoomDatabaseClient.Room.guests)
  }
  
  static let messages = hasMany(RoomDatabaseClient.Message.self)
  var messages: QueryInterfaceRequest<RoomDatabaseClient.Message> {
    request(for: RoomDatabaseClient.Room.messages)
  }
}

extension RoomDatabaseClient.Message: TableRecord {
  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
  
  static let user = hasOne(UserDatabaseClient.User.self, using: .init(["userId"]))
  var user: QueryInterfaceRequest<UserDatabaseClient.User> {
    return request(for: RoomDatabaseClient.Message.user)
  }
  
  static let room = hasOne(RoomDatabaseClient.Room.self, using: .init(["roomId"]))
  var room: QueryInterfaceRequest<RoomDatabaseClient.Room> {
    return request(for: RoomDatabaseClient.Message.room)
  }
}

extension RoomDatabaseClient {
  
  /**
   Don't remember last time I've touched SQL 🥲.
   So some straight forward naive solutions here.
   */
  internal static func grdb(
    _ dbQueue: DatabaseQueue
  ) -> RoomDatabaseClient {
    let updateRoom: (Models.Room) async throws -> () = { room in
      try await dbQueue.write { db in
        try RoomDatabaseClient.Room
          .init(
            id: nil,
            name: room.name
          )
          .insert(db)
      }
    }
    let getRoom: (String) async throws -> (Models.Room) = { room in
      try await dbQueue.read { db in
        guard let room = try RoomDatabaseClient.Room
          .filter(Column("name") == room)
          .including(optional: Room.guests)
          .including(optional: Room.messages)
          .fetchOne(db)
        else {
          throw RoomDatabaseClient.Error.notFound
        }
        let users = try room.guests
          .fetchAll(db)
          .compactMap {
            try? $0.guest.fetchOne(db)
          }
        let messages: [String: [Models.Message]] = try users
          .reduce(
            into: [String: [Models.Message]](), { partialResult, databaseUser in
              let messages: [Models.Message] = try room
                .messages
                .filter(Column("userId") == databaseUser.id)
                .fetchAll(db)
                .map { Models.Message(createdAt: $0.createdAt, text: $0.text) }
              partialResult[databaseUser.name] = messages
            }
          )
        let statuses: [String: Int] =  try users
          .reduce(
            into: [String: Int](), { partialResult, databaseUser in
              let status = try RoomDatabaseClient.UserRoom
                .filter(Column("userId") == databaseUser.id)
                .filter(Column("roomId") == room.id)
                .fetchOne(db)?
                .status ?? .offline
              partialResult[databaseUser.name] = status.rawValue
            }
          )
        return Models.Room(
          name: room.name,
          messages: messages,
          statuses: statuses
        )
      }
    }
    let addMessage: (Models.Message, UserRoomPair) async throws -> () = { message, userRoom in
      let (user, room) = (userRoom.user, userRoom.room)
      let (roomId, userId) = try await dbQueue.read { db in
        let room = try RoomDatabaseClient.Room
          .filter(Column("name") == room)
          .fetchOne(db)
        let user = try UserDatabaseClient.User
          .filter(Column("name") == user)
          .fetchOne(db)
        return (room?.id, user?.id)
      }
      guard let roomId,
            let userId else {
        return
      }
      try await dbQueue.write { db in
        try RoomDatabaseClient.Message
          .init(
            id: nil,
            createdAt: message.createdAt,
            text: message.text,
            userId: userId,
            roomId: roomId
          ).insert(db)
      }
    }
    let addGuest: (UserRoomPair) async throws -> () = { userRoom in
      let (user, room) = (userRoom.user, userRoom.room)
      let (roomId, userId) = try await dbQueue.read { db in
        let room = try RoomDatabaseClient.Room
          .filter(Column("name") == room)
          .fetchOne(db)
        let user = try UserDatabaseClient.User
          .filter(Column("name") == user)
          .fetchOne(db)
        return (room?.id, user?.id)
      }
      guard let roomId = roomId,
            let userId = userId else {
        throw RoomDatabaseClient.Error.notFound
      }
      if (
        try? await dbQueue.read({ db in
          try RoomDatabaseClient.UserRoom
            .filter(Column("roomId") == roomId)
            .filter(Column("userId") == userId)
            .fetchOne(db)
        })
      ) != nil {
        throw RoomDatabaseClient.Error.alreadyExists
      }
      try await dbQueue.write { db in
        try RoomDatabaseClient.UserRoom(
          status: .online,
          userId: userId,
          roomId: roomId
        ).upsert(db)
      }
    }
    let updateStatus: (Int, RoomDatabaseClient.UserRoomPair) async throws -> () = { status, userRoom in
      let (user, room) = (userRoom.user, userRoom.room)
      let userRoom = try await dbQueue.read { db in
        guard let room = try RoomDatabaseClient.Room
          .filter(Column("name") == room)
          .fetchOne(db),
              let user = try UserDatabaseClient.User
          .filter(Column("name") == user)
          .fetchOne(db)
        else {
          throw RoomDatabaseClient.Error.notFound
        }
        return try RoomDatabaseClient.UserRoom
          .filter(Column("userId") == user.id)
          .filter(Column("roomId") == room.id)
          .fetchOne(db)
      }
      guard let userRoom = userRoom else {
        throw RoomDatabaseClient.Error.notFound
      }
      let dbStatus = RoomDatabaseClient.UserRoom.Status.init(rawValue: status)
      return try await dbQueue.write { db in
        try db.execute(
          sql: "UPDATE userRoom SET status = :status WHERE roomId = :roomId AND userId = :userId",
          arguments: [
            "status": dbStatus?.rawValue ?? 0,
            "roomId": userRoom.roomId,
            "userId": userRoom.userId
          ]
        )
      }
    }
    return RoomDatabaseClient(
      getRoom: getRoom,
      updateRoom: updateRoom,
      updateStatus: updateStatus,
      addGuest: addGuest,
      addMessage: addMessage
    )
  }
}
