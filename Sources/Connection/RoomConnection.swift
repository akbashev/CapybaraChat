import Distributed
import Foundation
import ActorSystems
import Models
import Database
import AsyncPromise

// TODO: Rewrite using https://github.com/apple/swift-distributed-actors
/**
 Room connection is many to many and can be scaled across many servers.
 */
public distributed actor RoomConnection {
  
  public typealias ActorSystem = ClientServerActorSystem
  public typealias Room = Models.Room
  public typealias Guest = Models.Room.Guest
  
  public enum Error: Swift.Error {
    case noRoom
    case already
    case dbError
    case roomIsNotEmpty
  }
    
  private var _room: Room? {
    didSet {
      guard oldValue != self._room else { return }
      switch _room {
        case .none:
          self.promise.reject(with: RoomConnection.Error.noRoom)
        case .some(let wrapped):
          self.promise.resolve(with: wrapped)
      }
    }
  }
  
  private let database: RoomDatabaseClient
  private let promise = Promised<Room>.init()
  
  @discardableResult
  distributed public func add(
    _ user: User.Name
  ) async throws -> Room {
    guard var room = self._room else {
      throw RoomConnection.Error.noRoom
    }
    
    if let guestIdx = room.guests
      .firstIndex(
        where: { $0.name == user }
      ) {
      room.guests[guestIdx].status = .online
      self._room = room
      return room
    }
    
    var guest = try await self.database
      .addGuest((
        user: user,
        room: room.name
      ))
    guest.status = .online
    room.guests.append(guest)
    self._room = room
    return room
  }
  
  distributed public func add(
    message: Room.Message,
    from guest: User.Name
  ) async throws {
    guard var room = self._room else {
      throw RoomConnection.Error.noRoom
    }
    if let guestIdx = room.guests
      .firstIndex(
        where: { $0.name == guest }
      ) {
      room.guests[guestIdx]
        .messages
        .append(message)
      try await database.addMessage(
        message,
        (user: guest, room: room.name)
      )
      self._room = room
    }
  }
  
  distributed public func set(
    status: Room.Guest.Status,
    for user: User.Name
  ) async throws {
    guard var room = self._room else {
      throw RoomConnection.Error.noRoom
    }
    if let guestIdx = room.guests
      .firstIndex(
        where: { $0.name == user }
      ) {
      let oldStatus = room.guests[guestIdx].status
      guard oldStatus != status else { return }
      room.guests[guestIdx].status = status
      try await database.updateStatus(
        status,
        (user: user, room: room.name)
      )
      self._room = room
    }
  }
  
  @discardableResult
  distributed public func connect(
    to name: Room.Name
  ) async throws -> Room {
    if let room = self._room,
       room.name == name {
      return room
    }
    
    let room = try await getFromDb(for: name)
    self._room = room
    return room
  }
  
  private func getFromDb(
    for name: Room.Name
  ) async throws -> Room {
    if let room = try? await database.getRoom(name) {
      return room
    }
    
    let room = Room(
      name: name,
      guests: []
    )
    try await database.updateRoom(room)
    return room
  }
  
  
  distributed public func wait() async throws -> Room {
    try await self.promise.clearAndWait()
  }
  
  distributed internal func disconnect() async throws {
    guard let room = self._room else {
      throw RoomConnection.Error.noRoom
    }
    guard room.guests
      .filter({ $0.status != .offline })
      .isEmpty else {
      throw RoomConnection.Error.roomIsNotEmpty
    }
    self._room = nil
  }
  
  public init(
    actorSystem: ActorSystem,
    database: RoomDatabaseClient
  ) {
    self.actorSystem = actorSystem
    self.database = database
  }
}
