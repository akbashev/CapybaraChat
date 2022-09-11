import Distributed
import Foundation
import ActorSystems
import Models
import Database
import AsyncPromise

/**
 User-Room connection is one to one.
 */
public distributed actor UserRoomConnection {
  
  public typealias ActorSystem = ClientServerActorSystem
  typealias Guest = Models.Room.Guest
  
  public struct UserRoom: Hashable, Equatable {
    public let user: User.Name
    public let room: Room.Name
    
    public init(
      user: User.Name,
      room: Room.Name
    ) {
      self.user = user
      self.room = room
    }
    
    public var id: String {
      "\(user.rawValue)_\(room.rawValue)"
    }
    
    public static func user(
      for id: String
    ) -> String? {
      id.split(separator: "_")
        .first
        .map { String($0) }
    }
  }
  
  public enum Error: Swift.Error {
    case noRoom
  }

  private var user: User.Name
  distributed public func getRoom() async throws -> Room {
    guard let roomConnection = self.roomConnection else {
      throw UserRoomConnection.Error.noRoom
    }
    return try await roomConnection.wait()
  }
  
  private let client: ServerConnectionClient
  private var roomConnection: RoomConnection?
  
  distributed public func connect(
    to name: Room.Name
  ) async throws -> Room {
    let connection: () async throws -> RoomConnection = {
      if let roomConnection = self.roomConnection {
        return roomConnection
      }
      let roomConnection = try await self.client.roomConnection(name)
      self.roomConnection = roomConnection
      return roomConnection
    }
    
    let roomConnection = try await connection()
    try await roomConnection.connect(to: name)
    return try await roomConnection.add(user)
  }
  
  distributed public func add(
    message: Room.Message
  ) async throws {
    try await self.roomConnection?
      .add(
        message: message,
        from: user
      )
  }
  
  distributed public func set(
    status: Room.Guest.Status
  ) async throws {
    try await self.roomConnection?
      .set(
        status: status,
        for: user
      )
  }
  
  
  distributed internal func disconnect() async throws {
    guard let roomConnection = self.roomConnection else {
      throw UserRoomConnection.Error.noRoom
    }
    try? await roomConnection
      .set(
        status: .offline,
        for: user
      )
    try await self.client.disconnect(roomConnection)
    self.roomConnection = nil
  }
  
  public init(
    actorSystem: ActorSystem,
    client: ServerConnectionClient,
    name: User.Name
  ) {
    self.actorSystem = actorSystem
    self.client = client
    self.user = name
  }
}
