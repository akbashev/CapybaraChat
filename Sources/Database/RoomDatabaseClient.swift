import GRDB
import Foundation
import Models

public struct RoomDatabaseClient {
  public typealias UserRoomPair = (user: Models.User.Name, room: Models.Room.Name)

  public let getRoom: (Models.Room.Name) async throws -> (Models.Room?)
  public let updateRoom: (Models.Room) async throws -> ()
  public let updateStatus: (Models.Room.Guest.Status, UserRoomPair) async throws -> ()
  public let addGuest: (UserRoomPair) async throws -> (Models.Room.Guest)
  public let addMessage: (Models.Room.Message, UserRoomPair) async throws -> ()
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
            name: room.name.rawValue
          )
          .insert(db)
      }
    }
    let getRoom: (Models.Room.Name) async throws -> (Models.Room?) = { room in
      try await dbQueue.read { db in
        guard let room = try RoomDatabaseClient.Room
          .filter(Column("name") == room.rawValue)
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
        let guests = try users
          .map { user -> Models.Room.Guest in
          let status = try RoomDatabaseClient.UserRoom
            .filter(Column("userId") == user.id)
            .filter(Column("roomId") == room.id)
            .fetchOne(db)?
            .status ?? .offline
          let messages: [Models.Room.Message] = try room
            .messages
            .filter(Column("userId") == user.id)
            .fetchAll(db)
            .map { message -> Models.Room.Message in
                .init(
                  user: .init(rawValue: user.name),
                  createdAt: message.createdAt,
                  text: message.text
                )
            }
          return Models.Room.Guest(
            name: .init(rawValue: user.name),
            status: .init(status),
            messages: messages
          )
        }
        return Models.Room(
          name: .init(rawValue: room.name),
          guests: guests
        )
      }
    }
    let addMessage: (Models.Room.Message, UserRoomPair) async throws -> () = { message, userRoom in
      let (user, room) = (userRoom.user, userRoom.room)
      let (roomId, userId) = try await dbQueue.read { db in
        let room = try RoomDatabaseClient.Room
          .filter(Column("name") == room.rawValue)
          .fetchOne(db)
        let user = try UserDatabaseClient.User
          .filter(Column("name") == user.rawValue)
          .fetchOne(db)
        return (room?.id, user?.id)
      }
      guard let roomId = roomId,
              let userId = userId else {
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
    let addGuest: (UserRoomPair) async throws -> (Models.Room.Guest) = { userRoom in
      let (user, room) = (userRoom.user, userRoom.room)
      let (roomId, userId) = try await dbQueue.read { db in
        let room = try RoomDatabaseClient.Room
          .filter(Column("name") == room.rawValue)
          .fetchOne(db)
        let user = try UserDatabaseClient.User
          .filter(Column("name") == user.rawValue)
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
      return try await dbQueue.read { db in
        guard let user = try UserDatabaseClient.User
          .including(optional: UserDatabaseClient.User.messages)
          .filter(key: userId)
          .fetchOne(db)
        else { throw RoomDatabaseClient.Error.notFound }
        let messages: [Models.Room.Message] = try user
          .messages
          .filter(Column("roomId") == roomId)
          .fetchAll(db)
          .map { message -> Models.Room.Message in
            Models.Room.Message
              .init(
                user: .init(rawValue: user.name),
                createdAt: message.createdAt,
                text: message.text
              )
          }
        return .init(
          name: .init(rawValue: user.name),
          status: .online,
          messages: messages
        )
      }
    }
    let updateStatus: (Models.Room.Guest.Status, RoomDatabaseClient.UserRoomPair) async throws -> () = { status, userRoom in
      let (user, room) = (userRoom.user, userRoom.room)
      let userRoom = try await dbQueue.read { db in
        guard let room = try RoomDatabaseClient.Room
          .filter(Column("name") == room.rawValue)
          .fetchOne(db),
        let user = try UserDatabaseClient.User
          .filter(Column("name") == user.rawValue)
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
      let dbStatus = RoomDatabaseClient.UserRoom.Status.init(status)
      return try await dbQueue.write { db in
        try db.execute(
          sql: "UPDATE userRoom SET status = :status WHERE roomId = :roomId AND userId = :userId",
          arguments: [
            "status": dbStatus.rawValue,
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

extension Room.Guest.Status {
  init(_ status: RoomDatabaseClient.UserRoom.Status) {
    switch status {
      case .online:
        self = .online
      case .offline:
        self = .offline
      case .texting:
        self = .texting
    }
  }
}

extension RoomDatabaseClient.UserRoom.Status {
  init(_ status: Models.Room.Guest.Status) {
    switch status {
      case .online:
        self = .online
      case .offline:
        self = .offline
      case .texting:
        self = .texting
    }
  }
}
